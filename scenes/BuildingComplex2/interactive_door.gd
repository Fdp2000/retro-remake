extends MeshInstance3D

@export var open_angle: float = -90.0
@export var swing_duration: float = 0.3

var is_open: bool = false
var _closed_rotation: float = 0.0
var _open_fraction: float = 0.0
var _push_target_y: float = 0.0
var _swing: Tween
var _busy: bool = false

func _ready() -> void:
	set_multiplayer_authority(1)
	is_open = absf(rotation.y) > 0.5
	_closed_rotation = 0.0 if is_open else rotation.y
	_open_fraction = 1.0 if is_open else 0.0
	_push_target_y = rotation.y if is_open else (_closed_rotation + deg_to_rad(open_angle))
	for body in find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 2 if is_open else 3
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state.call_deferred()

func get_interaction_prompt() -> String:
	return "[Tap E] Close  |  [Hold E] Pull Shut" if is_open else "[Tap E] Fast Open  |  [Hold E] Slowly Push Open"


func get_hold_interaction_duration() -> float:
	return GameConfig.door_slow_peek_hold_time if GameConfig != null else 2.80


func request_step_push(_peer_id: int, delta: float) -> void:
	if multiplayer.is_server():
		server_step_push(delta)
	else:
		server_step_push.rpc_id(1, delta)


func request_begin_peek(_peer_id: int) -> void:
	pass


func request_interaction(_peer_id: int) -> void:
	if multiplayer.is_server():
		server_interact(false, false)
	else:
		server_interact.rpc_id(1, false, false)


func request_hold_interaction(_peer_id: int) -> void:
	if multiplayer.is_server():
		server_interact(true, false)
	else:
		server_interact.rpc_id(1, true, false)


func request_sprint_bash(_peer_id: int, _basher_pos: Vector3) -> void:
	if is_open:
		return
	if multiplayer.is_server():
		server_interact(false, true)
	else:
		server_interact.rpc_id(1, false, true)


func _request_state() -> void:
	server_get_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func server_get_state() -> void:
	if multiplayer.is_server():
		sync_state.rpc_id(multiplayer.get_remote_sender_id(), is_open, rotation.y, swing_duration)


func _find_verified_opener(is_sprint_bash: bool) -> Dictionary:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var scene: Node = get_tree().current_scene
	if scene == null:
		return {}
	var player: CharacterBody3D = scene.get_node_or_null("Players/" + str(sender)) as CharacterBody3D
	if player == null:
		return {}
	var view: Camera3D = player.get_node_or_null("Head/Camera3D") as Camera3D
	if view == null:
		return {}
	if not is_sprint_bash:
		var query := PhysicsRayQueryParameters3D.create(
			view.global_position, view.global_position - view.global_basis.z * 2.5, 3, [player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not is_ancestor_of(hit["collider"]):
			return {}
	return {"player": player, "sender": sender}


func _compute_away_target_y(player: CharacterBody3D) -> float:
	# +X door leaf rotated by +90 deg (-open_angle) swings into -Z (away from +Z opener);
	# -90 deg (open_angle) swings into +Z (away from -Z opener).
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var z_dot: float = global_basis.z.dot(to_player)
	var angle_deg: float = -open_angle if z_dot >= 0.0 else open_angle
	return _closed_rotation + deg_to_rad(angle_deg)


@rpc("any_peer", "call_remote", "reliable")
func server_step_push(delta: float) -> void:
	if not multiplayer.is_server() or _busy:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var player: CharacterBody3D = scene.get_node_or_null("Players/" + str(sender)) as CharacterBody3D
	if player == null or player.global_position.distance_to(global_position) > 3.5:
		return

	var slow_dur: float = GameConfig.door_slow_peek_swing_duration if GameConfig != null else 2.80
	var step: float = clampf(delta, 0.0, 0.15) / maxf(slow_dur, 0.5)
	if is_open:
		_open_fraction = clampf(_open_fraction - step, 0.0, 1.0)
		if _open_fraction <= 0.02:
			_open_fraction = 0.0
			is_open = false
	else:
		if _open_fraction <= 0.02:
			_push_target_y = _compute_away_target_y(player)
		_open_fraction = clampf(_open_fraction + step, 0.0, 1.0)
		if _open_fraction >= 0.98:
			_open_fraction = 1.0
			is_open = true

	var new_y: float = lerpf(_closed_rotation, _push_target_y, _open_fraction)
	if multiplayer.has_multiplayer_peer():
		sync_step_angle.rpc(new_y, is_open, _open_fraction, _push_target_y)
	else:
		sync_step_angle(new_y, is_open, _open_fraction, _push_target_y)


@rpc("authority", "call_local", "unreliable_ordered")
func sync_step_angle(new_y: float, opened_state: bool, frac: float, push_target_y: float) -> void:
	if _swing != null and _swing.is_valid():
		_swing.kill()
	_busy = false
	is_open = opened_state
	_open_fraction = clampf(frac, 0.0, 1.0)
	_push_target_y = push_target_y
	rotation.y = new_y
	var passable: bool = is_open or _open_fraction >= 0.35
	for body in find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 2 if passable else 3


@rpc("any_peer", "call_remote", "reliable")
func server_interact(is_slow_peek: bool = false, is_sprint_bash: bool = false) -> void:
	if not multiplayer.is_server() or _busy:
		return
	var opener_info: Dictionary = _find_verified_opener(is_sprint_bash)
	if opener_info.is_empty():
		return
	var player: CharacterBody3D = opener_info["player"] as CharacterBody3D
	var sender: int = int(opener_info["sender"])

	var next_open: bool = not is_open
	if is_sprint_bash and is_open:
		return

	var dur: float = swing_duration
	var target_y: float = _closed_rotation
	if next_open:
		target_y = _push_target_y if _open_fraction > 0.05 else _compute_away_target_y(player)
		if is_sprint_bash:
			dur = GameConfig.door_sprint_bash_duration if GameConfig != null else 0.12
			if AudioBridge != null and GameConfig != null:
				AudioBridge.request_world_cue("door_bash", global_position, GameConfig.audio_radius_door_bash, sender)
		elif is_slow_peek:
			dur = GameConfig.door_slow_peek_swing_duration if GameConfig != null else 2.80
		else:
			dur = GameConfig.door_fast_open_duration if GameConfig != null else 0.25
			if AudioBridge != null and GameConfig != null:
				AudioBridge.request_world_cue("door_open", global_position, GameConfig.audio_radius_door_fast, sender)
	else:
		dur = GameConfig.door_close_duration if GameConfig != null else 0.30
		if not is_slow_peek and AudioBridge != null and GameConfig != null:
			AudioBridge.request_world_cue("door_close", global_position, GameConfig.audio_radius_door_close, sender)

	if multiplayer.has_multiplayer_peer():
		sync_state.rpc(next_open, target_y, dur)
	else:
		sync_state(next_open, target_y, dur)


@rpc("authority", "call_local", "reliable")
func sync_state(opened: bool, target_y: float = 9999.0, dur: float = -1.0) -> void:
	is_open = opened
	_open_fraction = 1.0 if is_open else 0.0
	for body in find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 2 if is_open else 3
	if _swing != null and _swing.is_valid():
		_swing.kill()
	var final_y: float = target_y
	if final_y > 9000.0:
		final_y = _closed_rotation + (deg_to_rad(open_angle) if is_open else 0.0)
	if is_open:
		_push_target_y = final_y
	var final_dur: float = dur if dur > 0.0 else swing_duration
	var total_span: float = maxf(deg_to_rad(absf(open_angle)), 0.1)
	var scaled_dur: float = final_dur * clampf(absf(final_y - rotation.y) / total_span, 0.12, 1.0)
	if scaled_dur <= 0.01 or is_equal_approx(rotation.y, final_y):
		rotation.y = final_y
		_busy = false
		return
	_busy = true
	_swing = create_tween()
	_swing.tween_property(self, "rotation:y", final_y, scaled_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swing.finished.connect(func() -> void: _busy = false)
