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

const EXPLOSION_SMOKE_TEX: Texture2D = preload("res://Assets/Sprites/SmokeParticle.png")

var _cached_streams: Dictionary = {}
var _emitter_pool: Array[AudioStreamPlayer3D] = []
var _pool_cursor: int = 0
var _local_player: AudioStreamPlayer = null
var _cue_history: Array[Dictionary] = []
var _explosion_smoke_mat: StandardMaterial3D = null
var _explosion_spark_mat: StandardMaterial3D = null


func _ready() -> void:
	_ensure_nodes()
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		_ensure_explosion_fx_resources()


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
		if cue_id == "bomb_explode":
			_rpc_emit_reliable_world_cue.rpc(cue_id, world_pos, radius, source_peer_id)
		else:
			_rpc_emit_world_cue.rpc(cue_id, world_pos, radius, source_peer_id)
	else:
		play_world_cue(cue_id, world_pos, radius, source_peer_id)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_emit_world_cue(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int) -> void:
	play_world_cue(cue_id, world_pos, radius, source_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_emit_reliable_world_cue(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int) -> void:
	play_world_cue(cue_id, world_pos, radius, source_peer_id)


## Plays a 3D spatial cue locally and evaluates client-side raycast occlusion against Layer 1 (Environment).
func play_world_cue(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int = 0) -> void:
	if radius <= 0.0:
		return

	_record_cue(cue_id, world_pos, radius, source_peer_id)
	world_cue_emitted.emit(cue_id, world_pos, radius, source_peer_id)

	# Skip audio & VFX playback in editor or headless mode
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return

	if cue_id == "bomb_explode":
		_spawn_bomb_explosion_fx(world_pos)

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


func _ensure_explosion_fx_resources() -> void:
	if _explosion_smoke_mat == null:
		_explosion_smoke_mat = StandardMaterial3D.new()
		_explosion_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_explosion_smoke_mat.disable_receive_shadows = true
		_explosion_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_explosion_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_explosion_smoke_mat.vertex_color_use_as_albedo = true
		_explosion_smoke_mat.albedo_texture = EXPLOSION_SMOKE_TEX

	if _explosion_spark_mat == null:
		_explosion_spark_mat = StandardMaterial3D.new()
		_explosion_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_explosion_spark_mat.disable_receive_shadows = true
		_explosion_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_explosion_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_explosion_spark_mat.vertex_color_use_as_albedo = true


func _spawn_bomb_explosion_fx(world_pos: Vector3) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	if host == null:
		return

	_ensure_explosion_fx_resources()

	var blast_radius: float = GameConfig.time_bomb_blast_radius if GameConfig != null else 5.7

	var fx_root := Node3D.new()
	fx_root.name = "BombExplosionFX"
	host.add_child(fx_root)
	fx_root.global_position = world_pos

	var flash_light := OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.65, 0.22)
	flash_light.light_energy = 6.0
	flash_light.omni_range = blast_radius * 1.8
	flash_light.shadow_enabled = false
	fx_root.add_child(flash_light)

	var flash_sphere := MeshInstance3D.new()
	flash_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sph := SphereMesh.new()
	sph.radius = 0.45
	sph.height = 0.90
	flash_sphere.mesh = sph
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.disable_receive_shadows = true
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.albedo_color = Color(1.0, 0.85, 0.35, 0.88)
	flash_sphere.material_override = flash_mat
	flash_sphere.scale = Vector3.ONE * 0.6
	fx_root.add_child(flash_sphere)

	var shockwave_ring := MeshInstance3D.new()
	shockwave_ring.name = "ShockwaveRing"
	shockwave_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	shockwave_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.disable_receive_shadows = true
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(1.0, 0.78, 0.36, 0.75)
	shockwave_ring.material_override = ring_mat
	shockwave_ring.scale = Vector3(0.35, 0.35, 0.35)
	fx_root.add_child(shockwave_ring)

	var sparks := CPUParticles3D.new()
	sparks.name = "ExplosionSparks"
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 40
	sparks.lifetime = 0.55
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.35
	sparks.direction = Vector3(0.0, 1.0, 0.0)
	sparks.spread = 180.0
	sparks.gravity = Vector3(0.0, -7.5, 0.0)
	sparks.initial_velocity_min = 9.0
	sparks.initial_velocity_max = 16.5
	sparks.damping_min = 2.0
	sparks.damping_max = 3.2
	sparks.scale_amount_min = 0.8
	sparks.scale_amount_max = 1.5
	var spark_scale := Curve.new()
	spark_scale.add_point(Vector2(0.0, 1.0))
	spark_scale.add_point(Vector2(1.0, 0.0))
	sparks.scale_amount_curve = spark_scale
	var spark_grad := Gradient.new()
	spark_grad.set_offset(0, 0.0)
	spark_grad.set_color(0, Color(1.0, 0.94, 0.55, 1.0))
	spark_grad.set_offset(1, 1.0)
	spark_grad.set_color(1, Color(1.0, 0.30, 0.05, 0.0))
	spark_grad.add_point(0.45, Color(1.0, 0.58, 0.14, 0.95))
	sparks.color_ramp = spark_grad
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.14, 0.14)
	spark_mesh.material = _explosion_spark_mat
	sparks.mesh = spark_mesh
	fx_root.add_child(sparks)

	var smoke := CPUParticles3D.new()
	smoke.name = "ExplosionSmoke"
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.one_shot = true
	smoke.explosiveness = 0.95
	smoke.amount = 32
	smoke.lifetime = 1.65
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.55
	smoke.direction = Vector3(0.0, 1.0, 0.0)
	smoke.spread = 140.0
	smoke.gravity = Vector3(0.0, 1.2, 0.0)
	smoke.initial_velocity_min = 4.5
	smoke.initial_velocity_max = 8.5
	smoke.damping_min = 1.6
	smoke.damping_max = 2.4
	smoke.scale_amount_min = 0.85
	smoke.scale_amount_max = 1.45
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	var smoke_scale := Curve.new()
	smoke_scale.min_value = 0.0
	smoke_scale.max_value = 2.2
	smoke_scale.add_point(Vector2(0.0, 0.5))
	smoke_scale.add_point(Vector2(0.35, 1.35))
	smoke_scale.add_point(Vector2(1.0, 2.1))
	smoke.scale_amount_curve = smoke_scale
	var smoke_grad := Gradient.new()
	smoke_grad.set_offset(0, 0.0)
	smoke_grad.set_color(0, Color(1.0, 0.88, 0.72, 0.92))
	smoke_grad.set_offset(1, 1.0)
	smoke_grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	smoke_grad.add_point(0.28, Color(1.0, 1.0, 1.0, 0.85))
	smoke_grad.add_point(0.68, Color(1.0, 1.0, 1.0, 0.45))
	smoke.color_ramp = smoke_grad
	var smoke_mesh := QuadMesh.new()
	smoke_mesh.size = Vector2(1.05, 1.05)
	smoke_mesh.material = _explosion_smoke_mat
	smoke.mesh = smoke_mesh
	fx_root.add_child(smoke)

	sparks.emitting = true
	smoke.emitting = true

	var tw: Tween = fx_root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash_light, "light_energy", 0.0, 0.25)
	tw.tween_property(flash_sphere, "scale", Vector3.ONE * 4.2, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash_mat, "albedo_color:a", 0.0, 0.20)
	tw.tween_property(shockwave_ring, "scale", Vector3(blast_radius, 0.65, blast_radius), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring_mat, "albedo_color:a", 0.0, 0.28)

	tree.create_timer(2.2).timeout.connect(func() -> void:
		if is_instance_valid(fx_root):
			fx_root.queue_free()
	)
