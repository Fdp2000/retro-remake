class_name OcclusionEmitter3D
extends AudioStreamPlayer3D

## Client-side 3D emitter with throttled listener-to-emitter raycast occlusion
## and smooth DSP low-pass + volume attenuation lerping (Phase 4).

@export var check_interval: float = 0.08
@export var unoccluded_cutoff_hz: float = 20000.0
@export var occluded_cutoff_hz: float = 3200.0
@export var occluded_volume_drop_db: float = -2.5
@export var base_volume_db: float = 0.0
@export var smoothing_speed: float = 10.0
@export var occlusion_mask: int = GameConfig.LAYER_ENVIRONMENT
@export var parent_bus: StringName = &"SFX"
@export var use_dedicated_lowpass_bus: bool = true
@export var always_evaluate_occlusion: bool = false

var _dedicated_bus_name: StringName = &""
var _lowpass_effect: AudioEffectLowPassFilter = null
var _check_timer: float = 0.0
var _is_occluded: bool = false
var _current_cutoff_hz: float = 20000.0
var _target_cutoff_hz: float = 20000.0
var _current_occlusion_db: float = 0.0
var _target_occlusion_db: float = 0.0


func _ready() -> void:
	_current_cutoff_hz = unoccluded_cutoff_hz
	_target_cutoff_hz = unoccluded_cutoff_hz
	_current_occlusion_db = 0.0
	_target_occlusion_db = 0.0
	attenuation_filter_cutoff_hz = _current_cutoff_hz
	if use_dedicated_lowpass_bus:
		attenuation_filter_db = 0.0
	volume_db = base_volume_db

	if check_interval > 0.0:
		_check_timer = randf_range(0.0, check_interval)

	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return

	if use_dedicated_lowpass_bus:
		_setup_dedicated_bus()
	elif AudioServer.get_bus_index(parent_bus) != -1:
		bus = parent_bus


func _exit_tree() -> void:
	if _dedicated_bus_name != &"":
		var idx: int = AudioServer.get_bus_index(_dedicated_bus_name)
		if idx > 0:
			AudioServer.remove_bus(idx)
		_dedicated_bus_name = &""
		_lowpass_effect = null


func _setup_dedicated_bus() -> void:
	var candidate_name := StringName("OccEmitter_%d" % get_instance_id())
	if AudioServer.get_bus_index(candidate_name) != -1:
		_dedicated_bus_name = candidate_name
		bus = _dedicated_bus_name
		return

	var insert_idx: int = AudioServer.bus_count
	AudioServer.add_bus(insert_idx)
	AudioServer.set_bus_name(insert_idx, String(candidate_name))

	var send_target: StringName = parent_bus if AudioServer.get_bus_index(parent_bus) != -1 else &"Master"
	AudioServer.set_bus_send(insert_idx, send_target)

	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = _current_cutoff_hz
	lpf.resonance = 0.5
	lpf.db = AudioEffectFilter.FILTER_12DB
	AudioServer.add_bus_effect(insert_idx, lpf, 0)

	_dedicated_bus_name = candidate_name
	_lowpass_effect = lpf
	bus = _dedicated_bus_name


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not (playing or always_evaluate_occlusion):
		return

	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = maxf(check_interval, 0.02)
		evaluate_occlusion_now()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not (playing or always_evaluate_occlusion):
		return

	var alpha: float = 1.0 if smoothing_speed <= 0.0 else (1.0 - exp(-smoothing_speed * maxf(delta, 0.0)))
	_current_cutoff_hz = lerpf(_current_cutoff_hz, _target_cutoff_hz, alpha)
	_current_occlusion_db = lerpf(_current_occlusion_db, _target_occlusion_db, alpha)
	_apply_dsp_state()


func evaluate_occlusion_now() -> bool:
	var listener_pos: Vector3 = _get_listener_position()
	var dist: float = 0.0 if listener_pos == Vector3.INF else listener_pos.distance_to(global_position)
	if listener_pos == Vector3.INF or dist <= 0.45:
		_is_occluded = false
	else:
		var world: World3D = get_world_3d()
		if world == null:
			_is_occluded = false
		else:
			var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
			if space_state == null:
				_is_occluded = false
			else:
				# Stop 0.35m short of the emitter so floors, desks, and drawers at the source don't self-occlude.
				var dir: Vector3 = (global_position - listener_pos) / dist
				var ray_from: Vector3 = listener_pos + dir * 0.10
				var ray_to: Vector3 = global_position - dir * 0.35
				var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, occlusion_mask)
				query.collide_with_areas = false
				query.collide_with_bodies = true
				var hit: Dictionary = space_state.intersect_ray(query)
				_is_occluded = not hit.is_empty()

	_target_cutoff_hz = occluded_cutoff_hz if _is_occluded else unoccluded_cutoff_hz
	_target_occlusion_db = occluded_volume_drop_db if _is_occluded else 0.0
	return _is_occluded


func snap_occlusion_immediately() -> void:
	evaluate_occlusion_now()
	_current_cutoff_hz = _target_cutoff_hz
	_current_occlusion_db = _target_occlusion_db
	_apply_dsp_state()


func is_occluded() -> bool:
	return _is_occluded


func get_current_cutoff_hz() -> float:
	return _current_cutoff_hz


func get_current_occlusion_db() -> float:
	return _current_occlusion_db


func _apply_dsp_state() -> void:
	if _lowpass_effect != null:
		_lowpass_effect.cutoff_hz = _current_cutoff_hz
	attenuation_filter_cutoff_hz = _current_cutoff_hz
	volume_db = base_volume_db + _current_occlusion_db


func _get_listener_position() -> Vector3:
	if not is_inside_tree():
		return Vector3.INF
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector3.INF

	var listener: AudioListener3D = viewport.get_audio_listener_3d()
	if listener != null and is_instance_valid(listener) and listener.is_inside_tree() and listener.is_current():
		return listener.global_position

	var cam: Camera3D = viewport.get_camera_3d()
	if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
		return cam.global_position

	return Vector3.INF
