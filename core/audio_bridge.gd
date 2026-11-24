@tool
extends Node

## Decoupled Physical Audio Bridge (AGENTS.md §4.5, Doc 6 & AudioImplementatioPlan.md).
## All gameplay scripts route acoustic cues through AudioBridge.play_world_cue(...)
## or AudioBridge.play_local_cue(...) instead of scattering raw AudioStreamPlayer3D calls.

signal world_cue_emitted(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int)
signal local_cue_emitted(cue_id: String)

const EMITTER_POOL_SIZE: int = 16
const OCCLUSION_LOWPASS_HZ: float = 3200.0
const UNOCCLUDED_LOWPASS_HZ: float = 20000.0
const OCCLUDED_VOLUME_DROP_DB: float = -2.5

const OCCLUSION_EMITTER_SCRIPT = preload("res://core/audio/occlusion_emitter.gd")
const SURFACE_DETECTOR_SCRIPT = preload("res://core/audio/surface_detector.gd")

const SURFACE_AWARE_CUES: Array[String] = [
	"footstep_walk",
	"footstep_sprint",
	"jump_land"
]

# Real audio asset banks (cue_id -> Array[String] of resource paths)
const DEFAULT_CUE_ASSET_PATHS: Dictionary = {
	"bomb_hiss": [
		"res://Assets/SFX/Bomb/BombFuse.wav",
	],
	"bomb_explode": [
		"res://Assets/SFX/Bomb/BombExplosion.wav",
	],
	"player_ko": [
		"res://Assets/SFX/KO/TomScreamKO.wav",
	],
	"loot_sound": [
		"res://Assets/SFX/Interact Sound/loot sound.wav",
	],
	"bucket_arm": [
		"res://Assets/SFX/water bucket/BucketArm.wav",
	],
	"bucket_spill": [
		"res://Assets/SFX/water bucket/BucketTrigger.wav",
	],
	"bomb_arm": [
		"res://Assets/SFX/Bomb/BombArm.wav",
	],
	"spring_arm": [
		"res://Assets/SFX/Spring/SpringArm.wav",
	],
	"tripwire_arm": [
		"res://Assets/SFX/Tripwire/TripwirePolePlace.wav",
	],
	"tripwire_snap": [
		"res://Assets/SFX/Spring/SpringArm.wav",
	],
	"dart_gun_equip": [
		"res://Assets/SFX/DartGun/DartGunEquip.wav",
	],
	"dart_fire": [
		"res://Assets/SFX/DartGun/DartGunFire.wav",
	],
	"player_jump": [
		"res://Assets/SFX/Player/PlayerJump.wav",
	],
	"footstep_walk": [
		"res://Assets/SFX/Player/ConcreteFootstep_01.wav",
		"res://Assets/SFX/Player/ConcreteFootstep_02.wav",
		"res://Assets/SFX/Player/ConcreteFootstep_03.wav",
		"res://Assets/SFX/Player/ConcreteFootstep_04.wav",
	],
	"footstep_sprint": [
		"res://Assets/SFX/Player/ConcreteFootstep_01.wav",
		"res://Assets/SFX/Player/ConcreteFootstep_02.wav",
		"res://Assets/SFX/Player/ConcreteFootstep_03.wav",
		"res://Assets/SFX/Player/ConcreteFootstep_04.wav",
	],
	"spring_trigger": [
		"res://Assets/SFX/Spring/SpringTrigger_01.wav",
		"res://Assets/SFX/Spring/SpringTrigger_02.wav",
		"res://Assets/SFX/Spring/SpringTrigger_03.wav",
		"res://Assets/SFX/Spring/SpringTrigger_04.wav",
	],
}

const EXPLOSION_SMOKE_TEX: Texture2D = preload("res://Assets/Sprites/SmokeParticle.png")

var _custom_sound_banks: Dictionary = {} # cue_id -> Array[AudioStream]
var _emitter_pool: Array = []
var _pool_cursor: int = 0
var _local_player: AudioStreamPlayer = null
var _cue_history: Array[Dictionary] = []
var _explosion_smoke_mat: StandardMaterial3D = null
var _explosion_spark_mat: StandardMaterial3D = null


func _ready() -> void:
	_ensure_nodes()
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		_register_default_sound_banks()
		_ensure_explosion_fx_resources()


func _register_default_sound_banks() -> void:
	for cue_id in DEFAULT_CUE_ASSET_PATHS:
		var paths: Array = DEFAULT_CUE_ASSET_PATHS[cue_id]
		var streams: Array[AudioStream] = []
		for path_var in paths:
			var path: String = str(path_var)
			if ResourceLoader.exists(path):
				var s: AudioStream = load(path) as AudioStream
				if s != null:
					streams.append(s)
		if not streams.is_empty():
			register_cue_bank(str(cue_id), streams)


func _ensure_nodes() -> void:
	if _local_player == null:
		_local_player = AudioStreamPlayer.new()
		_local_player.name = "LocalCuePlayer"
		if AudioServer.get_bus_index(&"SFX") != -1:
			_local_player.bus = &"SFX"
		add_child(_local_player)

	if _emitter_pool.is_empty():
		for i in range(EMITTER_POOL_SIZE):
			var p = OCCLUSION_EMITTER_SCRIPT.new()
			p.name = "WorldEmitter_%d" % i
			p.unit_size = 4.0
			p.max_db = 3.0
			p.parent_bus = &"SFX"
			p.unoccluded_cutoff_hz = UNOCCLUDED_LOWPASS_HZ
			p.occluded_cutoff_hz = OCCLUSION_LOWPASS_HZ
			p.occluded_volume_drop_db = OCCLUDED_VOLUME_DROP_DB
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
func play_world_cue(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int = 0, follow_node: Node3D = null) -> void:
	if radius <= 0.0:
		return

	_record_cue(cue_id, world_pos, radius, source_peer_id)
	world_cue_emitted.emit(cue_id, world_pos, radius, source_peer_id)

	# Skip audio & VFX playback in editor or headless mode
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return

	if cue_id == "bomb_explode":
		_stop_active_cues("bomb_hiss", world_pos, 12.0)
		_spawn_bomb_explosion_fx(world_pos)

	_ensure_nodes()
	var resolved_cue: String = resolve_surface_cue(cue_id, world_pos)
	var stream: AudioStream = _get_stream_for_cue(resolved_cue)
	if stream == null:
		return

	var emitter = _emitter_pool[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % EMITTER_POOL_SIZE

	emitter.set_meta("cue_id", resolved_cue)
	emitter.follow_target = follow_node
	emitter.global_position = follow_node.global_position if (follow_node != null and is_instance_valid(follow_node) and follow_node.is_inside_tree()) else world_pos
	if resolved_cue == "player_ko":
		var local_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		var is_self_ko: bool = (source_peer_id != 0 and source_peer_id == local_id)
		emitter.unit_size = 14.0
		emitter.max_db = -3.0
		emitter.base_volume_db = -22.0 if is_self_ko else -13.0
		emitter.occluded_cutoff_hz = 7500.0
		emitter.occluded_volume_drop_db = -0.5
	elif resolved_cue == "bomb_explode" or resolved_cue == "dart_fire":
		emitter.unit_size = 16.0
		emitter.max_db = 0.0
		emitter.base_volume_db = -8.0
		emitter.occluded_cutoff_hz = 5500.0
		emitter.occluded_volume_drop_db = -1.5
	elif resolved_cue == "bomb_hiss":
		emitter.unit_size = 8.0
		emitter.max_db = 3.0
		emitter.base_volume_db = 0.0
		emitter.occluded_cutoff_hz = OCCLUSION_LOWPASS_HZ
		emitter.occluded_volume_drop_db = OCCLUDED_VOLUME_DROP_DB
	elif resolved_cue == "bucket_arm" or resolved_cue == "player_jump":
		emitter.unit_size = 1.5
		emitter.max_db = 2.0
		emitter.base_volume_db = 0.0
		emitter.occluded_cutoff_hz = OCCLUSION_LOWPASS_HZ
		emitter.occluded_volume_drop_db = OCCLUDED_VOLUME_DROP_DB
	elif resolved_cue == "bucket_spill":
		var is_ko_splash: bool = radius >= 20.0
		emitter.unit_size = 12.0 if is_ko_splash else 6.0
		emitter.max_db = 2.0
		emitter.base_volume_db = -2.0
		emitter.occluded_cutoff_hz = 5500.0 if is_ko_splash else OCCLUSION_LOWPASS_HZ
		emitter.occluded_volume_drop_db = -1.5 if is_ko_splash else OCCLUDED_VOLUME_DROP_DB
	elif resolved_cue == "bomb_arm":
		emitter.unit_size = 2.0
		emitter.max_db = 4.0
		emitter.base_volume_db = 2.0
		emitter.occluded_cutoff_hz = 6000.0
		emitter.occluded_volume_drop_db = -1.5
	elif resolved_cue == "spring_arm":
		emitter.unit_size = 2.5
		emitter.max_db = 6.0
		emitter.base_volume_db = 4.0
		emitter.occluded_cutoff_hz = 6000.0
		emitter.occluded_volume_drop_db = -1.5
	elif resolved_cue == "tripwire_arm":
		emitter.unit_size = 2.0
		emitter.max_db = 3.0
		emitter.base_volume_db = 0.0
		emitter.occluded_cutoff_hz = OCCLUSION_LOWPASS_HZ
		emitter.occluded_volume_drop_db = OCCLUDED_VOLUME_DROP_DB
	elif resolved_cue == "tripwire_snap":
		emitter.unit_size = 12.0
		emitter.max_db = 4.0
		emitter.base_volume_db = 2.5
		emitter.occluded_cutoff_hz = 5500.0
		emitter.occluded_volume_drop_db = -1.5
	elif resolved_cue == "dart_gun_equip":
		emitter.unit_size = 2.0
		emitter.max_db = 2.0
		emitter.base_volume_db = -2.0
		emitter.occluded_cutoff_hz = OCCLUSION_LOWPASS_HZ
		emitter.occluded_volume_drop_db = OCCLUDED_VOLUME_DROP_DB
	elif resolved_cue == "spring_trigger":
		emitter.unit_size = 12.0
		emitter.max_db = 3.0
		emitter.base_volume_db = -1.0
		emitter.occluded_cutoff_hz = 5500.0
		emitter.occluded_volume_drop_db = -1.5
	elif resolved_cue == "footstep_walk" or resolved_cue == "footstep_sprint":
		var is_sprint: bool = resolved_cue == "footstep_sprint"
		emitter.unit_size = 4.0 if is_sprint else 1.5
		emitter.max_db = -10.0
		emitter.base_volume_db = -15.0 if is_sprint else -19.0
		emitter.occluded_cutoff_hz = OCCLUSION_LOWPASS_HZ
		emitter.occluded_volume_drop_db = OCCLUDED_VOLUME_DROP_DB
	else:
		emitter.unit_size = 4.0
		emitter.max_db = 3.0
		emitter.base_volume_db = 0.0
		emitter.occluded_cutoff_hz = OCCLUSION_LOWPASS_HZ
		emitter.occluded_volume_drop_db = OCCLUDED_VOLUME_DROP_DB
	emitter.max_distance = maxf(radius, 0.5)
	emitter.stream = stream
	emitter.pitch_scale = randf_range(0.88, 1.12) if (resolved_cue == "footstep_walk" or resolved_cue == "footstep_sprint") else randf_range(0.95, 1.05)

	# Client-side line-of-sight occlusion check against Layer 1 (solid walls & closed doors)
	emitter.snap_occlusion_immediately()
	emitter.play()


func _stop_active_cues(target_cue_id: String, near_pos: Vector3, max_dist: float) -> void:
	var max_dist_sq: float = max_dist * max_dist
	for emitter in _emitter_pool:
		if emitter != null and is_instance_valid(emitter) and emitter.playing:
			if str(emitter.get_meta("cue_id", "")) == target_cue_id:
				if emitter.global_position.distance_squared_to(near_pos) <= max_dist_sq:
					emitter.stop()


## Registers a real AudioStream bank (one or more variations) for a cue_id.
func register_cue_bank(cue_id: String, streams: Array[AudioStream]) -> void:
	var valid_streams: Array[AudioStream] = []
	for s in streams:
		if s != null:
			valid_streams.append(s)
	if valid_streams.is_empty():
		_custom_sound_banks.erase(cue_id)
	else:
		_custom_sound_banks[cue_id] = valid_streams


## Resolves surface-aware cues (footsteps/landings) on the local listener's machine.
func resolve_surface_cue(cue_id: String, world_pos: Vector3) -> String:
	if not SURFACE_AWARE_CUES.has(cue_id):
		return cue_id
	var world: World3D = _get_active_world_3d()
	if world == null:
		return cue_id
	var surface: String = SURFACE_DETECTOR_SCRIPT.detect_surface_at(world, world_pos)
	if surface == SURFACE_DETECTOR_SCRIPT.SURFACE_DEFAULT:
		return cue_id
	var surface_cue: String = "%s_%s" % [cue_id, surface]
	if _custom_sound_banks.has(surface_cue):
		return surface_cue
	return cue_id


## Plays a non-spatial 2D cue for a specific peer only (e.g. container item take/put UI feedback).
func play_local_cue_for_peer(target_peer_id: int, cue_id: String) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		var local_id: int = multiplayer.get_unique_id()
		if target_peer_id <= 0 or target_peer_id == local_id:
			play_local_cue(cue_id)
		else:
			_rpc_play_local_cue.rpc_id(target_peer_id, cue_id)
	else:
		play_local_cue(cue_id)


@rpc("authority", "call_local", "reliable")
func _rpc_play_local_cue(cue_id: String) -> void:
	play_local_cue(cue_id)


## Plays a non-spatial 2D cue for the local player only (e.g. +10s clock ding, 15s sniffle warning).
func play_local_cue(cue_id: String) -> void:
	_record_cue(cue_id, Vector3.ZERO, 0.0, multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1)
	local_cue_emitted.emit(cue_id)

	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return

	_ensure_nodes()
	var stream: AudioStream = _get_stream_for_cue(cue_id)
	if stream == null:
		return
	_local_player.stream = stream
	_local_player.pitch_scale = randf_range(0.92, 1.08) if cue_id == "loot_sound" else 1.0
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


func _get_active_world_3d() -> World3D:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var cam: Camera3D = viewport.get_camera_3d()
		if cam != null and cam.is_inside_tree():
			return cam.get_world_3d()
		if viewport.world_3d != null:
			return viewport.world_3d
	if get_tree() != null and get_tree().root != null:
		return get_tree().root.world_3d
	return null


func _get_stream_for_cue(cue_id: String) -> AudioStream:
	if not _custom_sound_banks.has(cue_id) and DEFAULT_CUE_ASSET_PATHS.has(cue_id):
		var streams: Array[AudioStream] = []
		for path_var in DEFAULT_CUE_ASSET_PATHS[cue_id]:
			var path: String = str(path_var)
			if ResourceLoader.exists(path):
				var s: AudioStream = load(path) as AudioStream
				if s != null:
					streams.append(s)
		if not streams.is_empty():
			register_cue_bank(cue_id, streams)
	if _custom_sound_banks.has(cue_id):
		var bank: Array = _custom_sound_banks[cue_id]
		if not bank.is_empty():
			return bank[randi() % bank.size()] as AudioStream
	return null


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
