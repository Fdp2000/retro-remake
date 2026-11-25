class_name TrapOfTheGameUI
extends CanvasLayer

## Fullscreen end-of-round "Trap of the Game" compilation player.
## Plays all archived trap replays in chronological order from each victim's
## visual and audio perspective (AudioBridge SFX + TwoVoip proximity voice),
## with a small bottom-right Skip button to return to the lobby.

signal compilation_finished()
signal skip_to_lobby_requested()

const TWO_VOIP_SPEAKER_SCRIPT = preload("res://addons/twovoip/voiphelper/two_voip_speaker.gd")
const SFX_POOL_SIZE: int = 6
const BUCKET_MUFFLE_BUS_NAME: StringName = &"TOTGBucketMuffle"

var _root: Control = null
var _title_label: Label = null
var _detail_label: Label = null
var _texture_rect: TextureRect = null
var _display_tex: ImageTexture = null
var _crt_material: ShaderMaterial = null
var _skip_button: Button = null

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _voice_nodes: Dictionary = {} # peer_id -> {player: AudioStreamPlayer, speaker: Node}

var _clips: Array[Dictionary] = []
var _clip_idx: int = 0
var _clip_elapsed: float = 0.0
var _frame_accum: float = 0.0
var _frame_idx: int = 0
var _cue_cursor: int = 0
var _voice_cursor: int = 0
var _is_playing: bool = false


func _ready() -> void:
	layer = 45
	visible = false
	_build_ui()


func _build_ui() -> void:
	if _root != null:
		return

	_root = Control.new()
	_root.name = "TrapOfTheGameRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.025, 0.03, 0.97)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	_texture_rect = TextureRect.new()
	_texture_rect.anchor_left = 0.015
	_texture_rect.anchor_top = 0.06
	_texture_rect.anchor_right = 0.985
	_texture_rect.anchor_bottom = 0.97
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = CRTReplayMonitorUI.CRT_SHADER_CODE
	_crt_material = ShaderMaterial.new()
	_crt_material.shader = shader
	_crt_material.set_shader_parameter("static_amount", 0.03)
	_crt_material.set_shader_parameter("impact_flash", 0.0)
	_crt_material.set_shader_parameter("time_seed", 0.0)
	_texture_rect.material = _crt_material
	_root.add_child(_texture_rect)

	var top_bar := HBoxContainer.new()
	top_bar.anchor_left = 0.03
	top_bar.anchor_top = 0.015
	top_bar.anchor_right = 0.97
	top_bar.anchor_bottom = 0.065
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top_bar)

	_title_label = Label.new()
	_title_label.text = "★ TRAP OF THE GAME"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.modulate = Color(1.0, 0.84, 0.32)
	top_bar.add_child(_title_label)

	_detail_label = Label.new()
	_detail_label.text = ""
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_detail_label.add_theme_font_size_override("font_size", 18)
	_detail_label.modulate = Color(1.0, 0.45, 0.30)
	top_bar.add_child(_detail_label)

	_skip_button = Button.new()
	_skip_button.name = "SkipToLobbyButton"
	_skip_button.text = "Skip → Lobby"
	_skip_button.anchor_left = 1.0
	_skip_button.anchor_top = 1.0
	_skip_button.anchor_right = 1.0
	_skip_button.anchor_bottom = 1.0
	_skip_button.offset_left = -150.0
	_skip_button.offset_top = -52.0
	_skip_button.offset_right = -24.0
	_skip_button.offset_bottom = -16.0
	_skip_button.pressed.connect(_on_skip_pressed)
	_root.add_child(_skip_button)

	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "TOTGSfxPlayer_%d" % i
		add_child(player)
		_sfx_pool.append(player)


func start_compilation(clips: Array[Dictionary]) -> void:
	_build_ui()
	if clips.is_empty():
		compilation_finished.emit()
		return

	_clips = clips.duplicate()
	_clip_idx = 0
	_is_playing = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_begin_clip(0)


func stop_compilation(emit_click_off: bool = false) -> void:
	var was_playing: bool = _is_playing
	_is_playing = false
	_clips.clear()
	_clear_voice_nodes()
	for p in _sfx_pool:
		if p != null and is_instance_valid(p) and p.playing:
			p.stop()
	visible = false
	if was_playing and emit_click_off and AudioBridge != null:
		AudioBridge.play_local_cue("crt_click_off")


func is_playing() -> bool:
	return _is_playing


func _on_skip_pressed() -> void:
	stop_compilation(true)
	skip_to_lobby_requested.emit()


func _begin_clip(index: int) -> void:
	_clear_voice_nodes()
	_clip_idx = index
	_clip_elapsed = 0.0
	_frame_accum = 0.0
	_frame_idx = 0
	_cue_cursor = 0
	_voice_cursor = 0

	var clip: Dictionary = _clips[_clip_idx]
	var reason: String = str(clip.get("reason", "TRAP"))
	var attacker_id: int = int(clip.get("attacker_peer_id", 0))
	var victim_id: int = int(clip.get("victim_peer_id", 0))
	var attacker_lbl: String = str(clip.get("attacker_label", "TRAP"))
	var victim_lbl: String = str(clip.get("victim_label", "SPY"))

	if _title_label != null:
		_title_label.text = "★ TRAP OF THE GAME • CLIP %d/%d" % [_clip_idx + 1, _clips.size()]
	if _detail_label != null:
		if attacker_id > 0 and attacker_id == victim_id:
			_detail_label.text = "%s: %s KO'D THEMSELF!" % [reason, victim_lbl]
		elif attacker_id <= 0:
			_detail_label.text = "%s: %s WAS KO'D!" % [reason, victim_lbl]
		else:
			_detail_label.text = "%s: %s HIT %s" % [reason, attacker_lbl, victim_lbl]

	var frames: Array = clip.get("playback_frames", [])
	if not frames.is_empty():
		_show_frame(frames[0] as Image)

	_setup_voice_nodes_for_clip(clip)
	if AudioBridge != null:
		AudioBridge.play_local_cue("crt_static")
	_update_visuals(clip)


func _setup_voice_nodes_for_clip(clip: Dictionary) -> void:
	var headers: Dictionary = clip.get("voice_headers", {})
	var packets: Array = clip.get("voice_packets", [])
	var seen_peers: Dictionary = {}
	for pkt in packets:
		var sid: int = int(pkt.get("sender_peer_id", 0))
		if sid > 0:
			seen_peers[sid] = true

	for sid_var in seen_peers.keys():
		var sid: int = int(sid_var)
		var player := AudioStreamPlayer.new()
		player.name = "TOTGVoicePlayer_%d" % sid
		add_child(player)

		var speaker: Node = TWO_VOIP_SPEAKER_SCRIPT.new()
		speaker.name = "TOTGVoiceSpeaker_%d" % sid
		if VoiceChatManager != null:
			speaker.set("audiobufferlagtimetarget", VoiceChatManager.speaker_lag_target_sec)
			speaker.set("audiobufferlagtimetargettolerance", VoiceChatManager.speaker_lag_tolerance_sec)
		else:
			speaker.set("audiobufferlagtimetarget", 0.09)
			speaker.set("audiobufferlagtimetargettolerance", 0.06)
		player.add_child(speaker)

		if headers.has(sid):
			var hdr: PackedByteArray = headers[sid]
			if not hdr.is_empty():
				speaker.call("tv_incomingaudiopacket", hdr)

		_voice_nodes[sid] = {
			"player": player,
			"speaker": speaker
		}


func _ensure_bucket_muffle_bus() -> StringName:
	if AudioServer.get_bus_index(BUCKET_MUFFLE_BUS_NAME) == -1:
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUCKET_MUFFLE_BUS_NAME)
		AudioServer.set_bus_send(idx, &"Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 650.0
		AudioServer.add_bus_effect(idx, lp)
	return BUCKET_MUFFLE_BUS_NAME


func _clear_voice_nodes() -> void:
	for sid in _voice_nodes.keys():
		var entry: Dictionary = _voice_nodes[sid]
		var player: AudioStreamPlayer = entry.get("player") as AudioStreamPlayer
		if player != null and is_instance_valid(player):
			player.queue_free()
	_voice_nodes.clear()


func _process(delta: float) -> void:
	if not _is_playing or _clip_idx < 0 or _clip_idx >= _clips.size():
		return

	var clip: Dictionary = _clips[_clip_idx]
	var dur: float = maxf(float(clip.get("duration", 3.0)), 0.5)
	var fps: int = maxi(int(clip.get("fps", 24)), 1)
	var frames: Array = clip.get("playback_frames", [])

	_clip_elapsed += delta
	if _clip_elapsed >= dur:
		if _clip_idx + 1 < _clips.size():
			_begin_clip(_clip_idx + 1)
		else:
			stop_compilation(true)
			compilation_finished.emit()
		return

	var step_sec: float = 1.0 / float(fps)
	_frame_accum += delta
	while _frame_accum >= step_sec:
		_frame_accum -= step_sec
		if _frame_idx + 1 < frames.size():
			_frame_idx += 1
			_show_frame(frames[_frame_idx] as Image)

	_step_victim_audio(clip)
	_update_visuals(clip)


func _get_victim_pos_at_frame(clip: Dictionary) -> Vector3:
	var positions: Array = clip.get("victim_positions", [])
	if positions.is_empty():
		return Vector3.ZERO
	var idx: int = clampi(_frame_idx, 0, positions.size() - 1)
	return positions[idx] as Vector3


func _step_victim_audio(clip: Dictionary) -> void:
	var victim_pos: Vector3 = _get_victim_pos_at_frame(clip)
	var victim_id: int = int(clip.get("victim_peer_id", 0))

	# 1. AudioBridge SFX cues attenuated by distance to the victim
	var cues: Array = clip.get("audio_cues", [])
	while _cue_cursor < cues.size():
		var cue: Dictionary = cues[_cue_cursor]
		if float(cue.get("rel_sec", 0.0)) > _clip_elapsed:
			break
		_cue_cursor += 1
		_play_cue_from_victim_perspective(cue, victim_pos)

	# 2. TwoVoip proximity voice packets attenuated by distance to the victim
	var voice_pkts: Array = clip.get("voice_packets", [])
	var max_voice_rad: float = GameConfig.audio_radius_proximity_voice if GameConfig != null else 24.0
	var impact_idx: int = int(clip.get("impact_frame_idx", 0))
	var victim_bucket_muffled: bool = (str(clip.get("reason", "")).to_upper() == "BUCKET") and (_frame_idx >= impact_idx)
	if victim_bucket_muffled and _voice_nodes.has(victim_id):
		var vp: AudioStreamPlayer = _voice_nodes[victim_id]["player"] as AudioStreamPlayer
		var target_bus: StringName = _ensure_bucket_muffle_bus()
		if vp.bus != target_bus:
			vp.bus = target_bus
	while _voice_cursor < voice_pkts.size():
		var pkt: Dictionary = voice_pkts[_voice_cursor]
		if float(pkt.get("rel_sec", 0.0)) > _clip_elapsed:
			break
		_voice_cursor += 1
		var sid: int = int(pkt.get("sender_peer_id", 0))
		if _voice_nodes.has(sid):
			var vnode: Dictionary = _voice_nodes[sid]
			var player: AudioStreamPlayer = vnode["player"] as AudioStreamPlayer
			var speaker: Node = vnode["speaker"] as Node
			if sid == victim_id:
				player.volume_db = -4.5 if victim_bucket_muffled else 0.0
			else:
				var spos: Vector3 = pkt.get("sender_pos", victim_pos)
				var dist: float = spos.distance_to(victim_pos)
				var atten: float = clampf(1.0 - (dist / maxf(max_voice_rad, 1.0)), 0.0, 1.0)
				player.volume_db = linear_to_db(maxf(atten, 0.001)) if atten > 0.01 else -60.0
			speaker.call("tv_incomingaudiopacket", pkt["packet"])


func _play_cue_from_victim_perspective(cue: Dictionary, victim_pos: Vector3) -> void:
	if AudioBridge == null:
		return
	var cue_id: String = str(cue.get("cue_id", ""))
	if cue_id == "":
		return
	var world_pos: Vector3 = cue.get("world_pos", victim_pos)
	var radius: float = maxf(float(cue.get("radius", 10.0)), 1.0)
	var dist: float = world_pos.distance_to(victim_pos)
	if dist > radius:
		return

	var resolved: String = AudioBridge.resolve_surface_cue(cue_id, world_pos)
	var variant_seed: int = int(cue.get("variant_seed", -1))
	var stream: AudioStream = AudioBridge.call("_get_stream_for_cue", resolved, variant_seed) as AudioStream
	if stream == null:
		return

	var atten: float = clampf(1.0 - (dist / radius), 0.08, 1.0)
	var p: AudioStreamPlayer = _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	p.stream = stream
	p.volume_db = clampf(linear_to_db(atten), -28.0, 0.0)
	p.play()


func _update_visuals(clip: Dictionary) -> void:
	var dur: float = maxf(float(clip.get("duration", 3.0)), 0.5)
	var impact_idx: int = int(clip.get("impact_frame_idx", 0))
	var burst_sec: float = 0.16
	var static_val: float = 0.03
	if _clip_elapsed < burst_sec:
		static_val = 1.0 - (_clip_elapsed / burst_sec)
	elif _clip_elapsed > dur - burst_sec and _clip_idx + 1 >= _clips.size():
		static_val = (_clip_elapsed - (dur - burst_sec)) / burst_sec

	var impact_flash_val: float = 0.0
	if impact_idx > 0:
		var frames_past: int = _frame_idx - impact_idx
		if frames_past >= -1 and frames_past <= 3:
			impact_flash_val = clampf(0.85 - float(maxi(frames_past, 0)) * 0.25, 0.0, 0.85)

	if _crt_material != null:
		_crt_material.set_shader_parameter("static_amount", clampf(static_val, 0.02, 1.0))
		_crt_material.set_shader_parameter("impact_flash", impact_flash_val)
		_crt_material.set_shader_parameter("time_seed", _clip_elapsed)


func _show_frame(img: Image) -> void:
	if _texture_rect == null or img == null:
		return
	if _display_tex == null or _display_tex.get_size() != Vector2(img.get_size()):
		_display_tex = ImageTexture.create_from_image(img)
		_texture_rect.texture = _display_tex
	else:
		_display_tex.update(img)
