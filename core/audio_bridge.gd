@tool
extends Node

## Decoupled Physical Audio Bridge (AGENTS.md §4.5, Doc 6 & AudioImplementatioPlan.md).
## All gameplay scripts route acoustic cues through AudioBridge.play_world_cue(...)
## or AudioBridge.play_local_cue(...) instead of scattering raw AudioStreamPlayer3D calls.

signal world_cue_emitted(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int)
signal local_cue_emitted(cue_id: String)

const SAMPLE_RATE: int = 22050
const EMITTER_POOL_SIZE: int = 16
const OCCLUSION_LOWPASS_HZ: float = 700.0
const UNOCCLUDED_LOWPASS_HZ: float = 20000.0
const OCCLUDED_VOLUME_DROP_DB: float = -8.0

# Procedural greybox tone presets: [start_freq_hz, end_freq_hz, duration_sec, noise_mix]
const CUE_SYNTH_PRESETS: Dictionary = {
	"footstep_walk": [140.0, 90.0, 0.07, 0.35],
	"footstep_sprint": [190.0, 110.0, 0.09, 0.50],
	"jump_land": [120.0, 65.0, 0.14, 0.45],
	"door_open": [260.0, 340.0, 0.18, 0.15],
	"door_bash": [180.0, 80.0, 0.22, 0.70],
	"door_close": [220.0, 160.0, 0.12, 0.20],
	"bucket_spill": [320.0, 120.0, 0.35, 0.80],
	"drawer_slam": [210.0, 130.0, 0.16, 0.55],
	"paper_rustle": [800.0, 1200.0, 0.10, 0.85],
	"trap_arm": [620.0, 880.0, 0.10, 0.10],
	"spring_unlatch": [740.0, 520.0, 0.09, 0.15],
	"spring_trigger": [240.0, 680.0, 0.28, 0.20],
	"bomb_hiss": [1400.0, 1800.0, 0.25, 0.90],
	"bomb_explode": [110.0, 45.0, 0.55, 0.85],
	"club_whoosh": [300.0, 160.0, 0.14, 0.40],
	"club_slam": [160.0, 70.0, 0.26, 0.65],
	"club_stumble": [480.0, 200.0, 0.30, 0.25],
	"dart_fire": [900.0, 420.0, 0.11, 0.30],
	"sneeze": [520.0, 280.0, 0.38, 0.60],
	"sniffle_warning": [650.0, 780.0, 0.12, 0.50],
	"clock_bonus_ding": [880.0, 1320.0, 0.18, 0.02],
	"crt_static": [1200.0, 1200.0, 0.15, 0.95],
	"crt_click_off": [900.0, 320.0, 0.10, 0.85]
}

var _cached_streams: Dictionary = {}
var _emitter_pool: Array[AudioStreamPlayer3D] = []
var _pool_cursor: int = 0
var _local_player: AudioStreamPlayer = null
var _cue_history: Array[Dictionary] = []


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _local_player == null:
		_local_player = AudioStreamPlayer.new()
		_local_player.name = "LocalCuePlayer"
		add_child(_local_player)

	if _emitter_pool.is_empty():
		for i in range(EMITTER_POOL_SIZE):
			var p := AudioStreamPlayer3D.new()
			p.name = "WorldEmitter_%d" % i
			p.unit_size = 4.0
			p.max_db = 3.0
			add_child(p)
			_emitter_pool.append(p)


## Broadcasts a world audio cue across the network (or plays locally if offline)
func request_world_cue(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int = 0) -> void:
	if radius <= 0.0:
		return
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_rpc_emit_world_cue.rpc(cue_id, world_pos, radius, source_peer_id)
	else:
		play_world_cue(cue_id, world_pos, radius, source_peer_id)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_emit_world_cue(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int) -> void:
	play_world_cue(cue_id, world_pos, radius, source_peer_id)


## Plays a 3D spatial cue locally and evaluates client-side raycast occlusion against Layer 1 (Environment).
func play_world_cue(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int = 0) -> void:
	if radius <= 0.0:
		return

	_record_cue(cue_id, world_pos, radius, source_peer_id)
	world_cue_emitted.emit(cue_id, world_pos, radius, source_peer_id)

	# Skip audio playback in editor or headless mode
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return

	_ensure_nodes()
	var emitter: AudioStreamPlayer3D = _emitter_pool[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % EMITTER_POOL_SIZE

	emitter.global_position = world_pos
	emitter.max_distance = maxf(radius, 0.5)
	emitter.stream = _get_or_build_stream(cue_id)
	emitter.pitch_scale = randf_range(0.95, 1.05)

	# Client-side line-of-sight occlusion check against Layer 1 (solid walls & closed doors)
	var is_occluded: bool = _check_listener_occlusion(world_pos)
	emitter.attenuation_filter_cutoff_hz = OCCLUSION_LOWPASS_HZ if is_occluded else UNOCCLUDED_LOWPASS_HZ
	emitter.volume_db = OCCLUDED_VOLUME_DROP_DB if is_occluded else 0.0

	emitter.play()


## Plays a non-spatial 2D cue for the local player only (e.g. +10s clock ding, 15s sniffle warning).
func play_local_cue(cue_id: String) -> void:
	_record_cue(cue_id, Vector3.ZERO, 0.0, multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1)
	local_cue_emitted.emit(cue_id)

	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return

	_ensure_nodes()
	_local_player.stream = _get_or_build_stream(cue_id)
	_local_player.pitch_scale = 1.0
	_local_player.play()


func get_recent_cues() -> Array[Dictionary]:
	return _cue_history


func clear_recent_cues() -> void:
	_cue_history.clear()


func _record_cue(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int) -> void:
	_cue_history.append({
		"cue_id": cue_id,
		"world_pos": world_pos,
		"radius": radius,
		"source_peer_id": source_peer_id,
		"timestamp_msec": Time.get_ticks_msec()
	})
	if _cue_history.size() > 64:
		_cue_history.pop_front()


func _check_listener_occlusion(emitter_pos: Vector3) -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false
	var cam: Camera3D = viewport.get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return false
	var world: World3D = cam.get_world_3d()
	if world == null:
		return false

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return false

	var query := PhysicsRayQueryParameters3D.create(
		cam.global_position,
		emitter_pos,
		GameConfig.LAYER_ENVIRONMENT
	)
	var hit: Dictionary = space_state.intersect_ray(query)
	return not hit.is_empty()


func _get_or_build_stream(cue_id: String) -> AudioStreamWAV:
	if _cached_streams.has(cue_id):
		return _cached_streams[cue_id]

	var preset: Array = CUE_SYNTH_PRESETS.get(cue_id, [440.0, 440.0, 0.10, 0.10])
	var f0: float = float(preset[0])
	var f1: float = float(preset[1])
	var duration: float = float(preset[2])
	var noise_mix: float = float(preset[3])

	var sample_count: int = maxi(int(SAMPLE_RATE * duration), 64)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)

	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = cue_id.hash()

	for i in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var env: float = sin(t * PI) # Smooth attack/release envelope (zero click/pop)
		var freq: float = lerpf(f0, f1, t)
		phase += (TAU * freq) / float(SAMPLE_RATE)
		var tone: float = sin(phase)
		var noise: float = rng.randf_range(-1.0, 1.0)
		var sample_val: float = lerpf(tone, noise, noise_mix) * env * 0.45
		var s16: int = clampi(int(sample_val * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, s16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm

	_cached_streams[cue_id] = wav
	return wav
