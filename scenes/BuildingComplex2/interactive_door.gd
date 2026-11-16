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
	return "[E] Close door" if is_open else "[E] Open door"

func request_interaction(_peer_id: int) -> void:
	if multiplayer.is_server():
		server_interact()
	else:
		server_interact.rpc_id(1)

func _request_state() -> void:
	server_get_state.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_get_state() -> void:
	if multiplayer.is_server():
		sync_state.rpc_id(multiplayer.get_remote_sender_id(), is_open)

@rpc("any_peer", "call_remote", "reliable")
func server_interact() -> void:
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
	var query := PhysicsRayQueryParameters3D.create(
		view.global_position, view.global_position - view.global_basis.z * 2.5, 3, [player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not is_ancestor_of(hit["collider"]):
		return
	if multiplayer.has_multiplayer_peer():
		sync_state.rpc(not is_open)
	else:
		sync_state(not is_open)

@rpc("authority", "call_local", "reliable")
func sync_state(opened: bool) -> void:
	is_open = opened
	if _swing != null and _swing.is_valid():
		_swing.kill()
	_busy = true
	_swing = create_tween()
	_swing.tween_property(self, "rotation:y",
		_closed_rotation + (deg_to_rad(open_angle) if is_open else 0.0),
		swing_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swing.finished.connect(func() -> void: _busy = false)
