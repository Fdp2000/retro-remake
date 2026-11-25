extends Node

## 3D Proximity Voice Chat powered by TwoVoip (libopus + RNNoise + C++ jitter buffer).
## Captures local microphone audio via TwoVoipMic and streams compressed Opus
## packets to each remote player's head-mounted ProximityVoiceEmitter (OcclusionEmitter3D).

signal peer_speaking_changed(peer_id: int, is_speaking: bool)
signal local_transmit_changed(is_transmitting: bool)
signal voip_packet_captured(sender_peer_id: int, packet: PackedByteArray)

const TWO_VOIP_MIC_SCRIPT = preload("res://addons/twovoip/voiphelper/two_voip_mic.gd")
const TWO_VOIP_SPEAKER_SCRIPT = preload("res://addons/twovoip/voiphelper/two_voip_speaker.gd")

@export var vad_threshold: float = 0.03:
	set(value):
		vad_threshold = clampf(value, 0.0, 1.0)
		if _mic != null and _mic.has_method("set_voxthreshhold"):
			_mic.call("set_voxthreshhold", vad_threshold)

@export var denoise_enabled: bool = true:
	set(value):
		denoise_enabled = value
		if _denoise_btn != null:
			_denoise_btn.button_pressed = denoise_enabled

@export var voice_enabled: bool = true
@export var is_muted: bool = false:
	set(value):
		is_muted = value
		if _mic_on_btn != null:
			_mic_on_btn.button_pressed = voice_enabled and not is_muted
		if is_muted:
			local_transmit_changed.emit(false)

@export var local_loopback_enabled: bool = false
@export var speaker_lag_target_sec: float = 0.09
@export var speaker_lag_tolerance_sec: float = 0.06

var _mic: Node = null
var _mic_on_btn: Button = null
var _ptt_btn: Button = null
var _vox_btn: Button = null
var _denoise_btn: Button = null

var _current_stream_header: Variant = null
var _peers_needing_header: Array[int] = []
var _peer_speakers: Dictionary = {} # peer_id -> TwoVoipSpeaker (3D in-match)
var _lobby_speaker_players: Dictionary = {} # peer_id -> AudioStreamPlayer (2D in-lobby)
var _lobby_speakers: Dictionary = {} # peer_id -> TwoVoipSpeaker (2D in-lobby)
var _lobby_muted_peers: Dictionary = {} # peer_id -> bool
var _peer_speaking: Dictionary = {} # peer_id -> bool


func _ready() -> void:
	if NetworkManager != null:
		if not NetworkManager.player_connected.is_connected(_on_peer_connected):
			NetworkManager.player_connected.connect(_on_peer_connected)
		if not NetworkManager.player_disconnected.is_connected(_on_peer_disconnected):
			NetworkManager.player_disconnected.connect(_on_peer_disconnected)
	if MatchManager != null and not MatchManager.match_started.is_connected(_on_match_started):
		MatchManager.match_started.connect(_on_match_started)

	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return

	_setup_twovoip_mic()


func _on_match_started(_seed_value: int) -> void:
	clear_lobby_voip_state()


func set_lobby_peer_muted(peer_id: int, muted: bool) -> void:
	if peer_id <= 0:
		return
	if muted:
		_lobby_muted_peers[peer_id] = true
	else:
		_lobby_muted_peers.erase(peer_id)
	var lobby_player: AudioStreamPlayer = _lobby_speaker_players.get(peer_id, null) as AudioStreamPlayer
	if lobby_player != null and is_instance_valid(lobby_player):
		lobby_player.volume_db = -80.0 if muted else 0.0


func is_lobby_peer_muted(peer_id: int) -> bool:
	return bool(_lobby_muted_peers.get(peer_id, false))


func clear_lobby_voip_state() -> void:
	_lobby_muted_peers.clear()
	for pid in _lobby_speakers.keys():
		var spk: Node = _lobby_speakers[pid] as Node
		if spk != null and is_instance_valid(spk):
			spk.call("external_end_stream")
			spk.queue_free()
	_lobby_speakers.clear()
	for pid in _lobby_speaker_players.keys():
		var p: AudioStreamPlayer = _lobby_speaker_players[pid] as AudioStreamPlayer
		if p != null and is_instance_valid(p):
			p.stop()
			p.queue_free()
	_lobby_speaker_players.clear()


func _setup_twovoip_mic() -> void:
	_mic = TWO_VOIP_MIC_SCRIPT.new()
	_mic.name = "TwoVoipMic"
	add_child(_mic)

	_mic_on_btn = Button.new()
	_mic_on_btn.toggle_mode = true
	_mic_on_btn.button_pressed = voice_enabled and not is_muted

	_ptt_btn = Button.new()
	_ptt_btn.toggle_mode = true

	_vox_btn = Button.new()
	_vox_btn.toggle_mode = true
	_vox_btn.button_pressed = true

	_denoise_btn = Button.new()
	_denoise_btn.toggle_mode = true
	_denoise_btn.button_pressed = denoise_enabled

	_mic.call("initvoipmic", _mic_on_btn, null, _ptt_btn, _vox_btn, _denoise_btn, null)
	# 48 kHz mono, 20 ms frames, 24 kbps voice-optimized Opus (~60 bytes/packet)
	_mic.call("setopusvalues", 48000, 20, 1, 24000, 5, true)
	_mic.call("set_voxthreshhold", vad_threshold)

	_mic.connect("transmitaudiojsonpacket", _on_mic_json_packet)
	_mic.connect("transmitaudiopacket", _on_mic_audio_packet)


func set_muted(muted: bool) -> void:
	is_muted = muted


func set_local_loopback(enabled: bool) -> void:
	local_loopback_enabled = enabled


func set_input_device(device_name: String) -> void:
	if device_name == "" or not AudioServer.get_input_device_list().has(device_name):
		return
	var was_on: bool = (_mic_on_btn != null and _mic_on_btn.button_pressed)
	if was_on:
		_mic_on_btn.set_pressed(false)
	AudioServer.set_input_device(device_name)
	if was_on:
		_mic_on_btn.set_pressed(true)


func get_live_mic_level() -> float:
	if _mic != null and is_instance_valid(_mic):
		return clampf(float(_mic.get("last_chunkmax")), 0.0, 1.0)
	return 0.0


func is_peer_speaking(peer_id: int) -> bool:
	return bool(_peer_speaking.get(peer_id, false))


## Returns normalized [0.0..1.0] live voice volume for a peer (remote speaker or local mic).
func get_peer_voice_level(peer_id: int) -> float:
	if not voice_enabled:
		return 0.0

	var speaker: Node = _peer_speakers.get(peer_id, null) as Node
	if speaker == null or not is_instance_valid(speaker):
		speaker = _lobby_speakers.get(peer_id, null) as Node
	if speaker != null and is_instance_valid(speaker):
		var playback: Variant = speaker.get("audiostreamplaybackopus")
		if playback != null and playback.has_method("get_chunk_max"):
			var queue_len: int = int(playback.call("queue_length_frames")) if playback.has_method("queue_length_frames") else 0
			if is_peer_speaking(peer_id) or queue_len > 0:
				return clampf(float(playback.call("get_chunk_max")), 0.0, 1.0)

	var local_id: int = multiplayer.get_unique_id() if _is_network_connected() else 1
	if peer_id == local_id and not is_muted and _mic != null and is_instance_valid(_mic):
		if bool(_mic.get("currentlytalking")):
			return clampf(float(_mic.get("last_chunkmax")), 0.0, 1.0)

	return 0.0


func _on_mic_json_packet(json_packet: Dictionary) -> void:
	if json_packet.has("talkingtimestart"):
		_current_stream_header = json_packet.duplicate()
		_peers_needing_header.clear()
		local_transmit_changed.emit(true)

	var frame_count: int = int(_current_stream_header["opusframecount"]) if _current_stream_header is Dictionary else 0
	if json_packet.has("talkingtimeend"):
		frame_count += 1
		_current_stream_header = null
		local_transmit_changed.emit(false)

	var header_bytes: PackedByteArray = JSON.stringify(json_packet).to_ascii_buffer()
	_send_voip_header_packet(header_bytes, frame_count)


func _on_mic_audio_packet(opus_packet: PackedByteArray, opus_frame_count: int) -> void:
	if not voice_enabled or is_muted:
		return

	if _current_stream_header is Dictionary:
		(_current_stream_header as Dictionary)["opusframecount"] = opus_frame_count

	if not _peers_needing_header.is_empty() and _current_stream_header is Dictionary:
		var mid_header: PackedByteArray = JSON.stringify(_current_stream_header).to_ascii_buffer()
		if _is_network_connected():
			for peer_id in _peers_needing_header:
				_rpc_receive_voip_header.rpc_id(peer_id, mid_header)
		_peers_needing_header.clear()

	var local_id: int = multiplayer.get_unique_id() if _is_network_connected() else 1
	voip_packet_captured.emit(local_id, opus_packet)

	if _is_network_connected():
		if not multiplayer.get_peers().is_empty():
			_rpc_receive_voip_audio.rpc(opus_packet)
	elif local_loopback_enabled:
		_ingest_voip_packet(local_id, opus_packet, false)


func _send_voip_header_packet(header_bytes: PackedByteArray, _frame_count: int) -> void:
	if not voice_enabled or is_muted:
		return
	var local_id: int = multiplayer.get_unique_id() if _is_network_connected() else 1
	voip_packet_captured.emit(local_id, header_bytes)
	if _is_network_connected():
		if not multiplayer.get_peers().is_empty():
			_rpc_receive_voip_header.rpc(header_bytes)
	elif local_loopback_enabled:
		_ingest_voip_packet(local_id, header_bytes, false)


func _is_network_connected() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_voip_header(header_bytes: PackedByteArray) -> void:
	if not voice_enabled:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	_ingest_voip_packet(sender_id, header_bytes)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_receive_voip_audio(opus_packet: PackedByteArray) -> void:
	if not voice_enabled:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	_ingest_voip_packet(sender_id, opus_packet)


func _ingest_voip_packet(sender_peer_id: int, packet: PackedByteArray, emit_capture: bool = true) -> void:
	if packet.is_empty():
		return
	if emit_capture:
		voip_packet_captured.emit(sender_peer_id, packet)

	var speaker: Node = _get_or_create_speaker(sender_peer_id)
	if speaker == null:
		return

	# Track speaking state from start/end JSON headers
	if packet.size() > 3 and packet[0] == 123 and packet[-1] == 125:
		var parsed: Variant = JSON.parse_string(packet.get_string_from_ascii())
		if parsed is Dictionary:
			var dict := parsed as Dictionary
			if dict.has("talkingtimestart") and not bool(_peer_speaking.get(sender_peer_id, false)):
				_peer_speaking[sender_peer_id] = true
				peer_speaking_changed.emit(sender_peer_id, true)
			elif dict.has("talkingtimeend") and bool(_peer_speaking.get(sender_peer_id, false)):
				_peer_speaking[sender_peer_id] = false
				peer_speaking_changed.emit(sender_peer_id, false)

	speaker.call("tv_incomingaudiopacket", packet)


func _get_or_create_speaker(peer_id: int) -> Node:
	var target_player: Node = _find_player_by_peer_id(peer_id)
	if target_player != null and target_player.has_method("get_proximity_voice_emitter"):
		if _lobby_speakers.has(peer_id) or _lobby_speaker_players.has(peer_id):
			_free_lobby_speaker_for_peer(peer_id)
		var existing: Node = _peer_speakers.get(peer_id, null) as Node
		if existing != null and is_instance_valid(existing):
			return existing

		var emitter: AudioStreamPlayer3D = target_player.call("get_proximity_voice_emitter") as AudioStreamPlayer3D
		if emitter == null or not is_instance_valid(emitter):
			return null

		var speaker: Node = TWO_VOIP_SPEAKER_SCRIPT.new()
		speaker.name = "TwoVoipSpeaker_%d" % peer_id
		speaker.set("audiobufferlagtimetarget", speaker_lag_target_sec)
		speaker.set("audiobufferlagtimetargettolerance", speaker_lag_tolerance_sec)
		emitter.add_child(speaker)
		_peer_speakers[peer_id] = speaker
		return speaker

	# Lobby fallback: 2D non-spatial AudioStreamPlayer so players can talk before match starts
	var existing_lobby: Node = _lobby_speakers.get(peer_id, null) as Node
	if existing_lobby != null and is_instance_valid(existing_lobby):
		return existing_lobby

	var lobby_player := AudioStreamPlayer.new()
	lobby_player.name = "LobbyVoicePlayer_%d" % peer_id
	if AudioServer.get_bus_index(&"Voice") != -1:
		lobby_player.bus = &"Voice"
	lobby_player.volume_db = -80.0 if is_lobby_peer_muted(peer_id) else 0.0
	add_child(lobby_player)

	var lobby_speaker: Node = TWO_VOIP_SPEAKER_SCRIPT.new()
	lobby_speaker.name = "TwoVoipLobbySpeaker_%d" % peer_id
	lobby_speaker.set("audiobufferlagtimetarget", speaker_lag_target_sec)
	lobby_speaker.set("audiobufferlagtimetargettolerance", speaker_lag_tolerance_sec)
	lobby_player.add_child(lobby_speaker)

	_lobby_speaker_players[peer_id] = lobby_player
	_lobby_speakers[peer_id] = lobby_speaker
	return lobby_speaker


func _free_lobby_speaker_for_peer(peer_id: int) -> void:
	var spk: Node = _lobby_speakers.get(peer_id, null) as Node
	if spk != null and is_instance_valid(spk):
		spk.call("external_end_stream")
		spk.queue_free()
	_lobby_speakers.erase(peer_id)
	var p: AudioStreamPlayer = _lobby_speaker_players.get(peer_id, null) as AudioStreamPlayer
	if p != null and is_instance_valid(p):
		p.stop()
		p.queue_free()
	_lobby_speaker_players.erase(peer_id)


func _find_player_by_peer_id(peer_id: int) -> Node:
	if not is_inside_tree() or get_tree() == null:
		return null
	for node in get_tree().get_nodes_in_group("spy_players"):
		if is_instance_valid(node) and node.name.to_int() == peer_id:
			return node
	return null


func _on_peer_connected(peer_id: int) -> void:
	if _current_stream_header is Dictionary and not _peers_needing_header.has(peer_id):
		_peers_needing_header.append(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_peers_needing_header.erase(peer_id)
	if bool(_peer_speaking.get(peer_id, false)):
		_peer_speaking[peer_id] = false
		peer_speaking_changed.emit(peer_id, false)
	_peer_speaking.erase(peer_id)

	var speaker: Node = _peer_speakers.get(peer_id, null) as Node
	if speaker != null and is_instance_valid(speaker):
		speaker.call("external_end_stream")
		speaker.queue_free()
	_peer_speakers.erase(peer_id)
	_free_lobby_speaker_for_peer(peer_id)
	_lobby_muted_peers.erase(peer_id)
