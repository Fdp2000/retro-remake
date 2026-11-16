extends MeshInstance3D

@export var open_angle: float = -90.0
@export var swing_duration: float = 0.3

var is_open: bool = false
var _closed_rotation: float = 0.0
var _swing: Tween
var _busy: bool = false

func _ready() -> void:
	set_multiplayer_authority(1)
	is_open = absf(rotation.y) > 0.5
	_closed_rotation = 0.0 if is_open else rotation.y
	for body in find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 3
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state.call_deferred()

func get_interaction_prompt() -> String:
	return "[E] Close Door" if is_open else "[Tap E] Fast Open  |  [Hold E] Silent Peek"


func get_hold_interaction_duration() -> float:
	return GameConfig.door_slow_peek_hold_time if GameConfig != null else 0.60


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


@rpc("any_peer", "call_remote", "reliable")
func server_interact(is_slow_peek: bool = false, is_sprint_bash: bool = false) -> void:
	if not multiplayer.is_server() or _busy:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var scene: Node = get_tree().current_scene
	var player: CharacterBody3D = scene.get_node_or_null("Players/" + str(sender)) as CharacterBody3D
	if player == null:
		return
	var view: Camera3D = player.get_node_or_null("Head/Camera3D") as Camera3D
	if view == null:
		return
	if not is_sprint_bash:
		var query := PhysicsRayQueryParameters3D.create(
			view.global_position, view.global_position - view.global_basis.z * 2.5, 3, [player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not is_ancestor_of(hit["collider"]):
			return

	var next_open: bool = not is_open
	if is_sprint_bash and is_open:
		return

	var dur: float = swing_duration
	var target_y: float = _closed_rotation
	if next_open:
		# Preserve -90 deg when approached from +Z front side for door_interaction_check.gd compatibility,
		# and swing opposite (+90 deg) when approached from the -Z rear side.
		var to_player: Vector3 = player.global_position - global_position
		to_player.y = 0.0
		var z_dot: float = global_basis.z.dot(to_player)
		var angle_deg: float = open_angle if z_dot >= 0.0 else -open_angle
		target_y = _closed_rotation + deg_to_rad(angle_deg)
		if is_sprint_bash:
			dur = GameConfig.door_sprint_bash_duration if GameConfig != null else 0.12
			if AudioBridge != null and GameConfig != null:
				AudioBridge.request_world_cue("door_bash", global_position, GameConfig.audio_radius_door_bash, sender)
		elif is_slow_peek:
			dur = GameConfig.door_slow_peek_swing_duration if GameConfig != null else 0.60
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
	if _swing != null and _swing.is_valid():
		_swing.kill()
	_busy = true
	var final_y: float = target_y
	if final_y > 9000.0:
		final_y = _closed_rotation + (deg_to_rad(open_angle) if is_open else 0.0)
	var final_dur: float = dur if dur > 0.0 else swing_duration
	_swing = create_tween()
	_swing.tween_property(self, "rotation:y",
		final_y,
		final_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swing.finished.connect(func() -> void: _busy = false)
