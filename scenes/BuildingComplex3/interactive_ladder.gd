extends Node3D

const SHAFT_WIDTH := 1.1
const SHAFT_DEPTH := 1.5
const POCKET_REAR_DEPTH := 0.22
const GUARD_THICKNESS := 0.08
const CLIMB_OFFSET := 0.25
const LANDING_OFFSET := SHAFT_DEPTH * 0.5 + 0.55

var inward_only := false
var lower_landing_y := 0.0
var upper_landing_y := 0.0
var climb_body: PhysicsBody3D
var shaft_guard: StaticBody3D


func _ready() -> void:
	# The door interaction ray sees layer 2 without adding a player obstacle.
	var target := StaticBody3D.new()
	target.name = "InteractTarget"
	target.collision_layer = 2
	target.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, upper_landing_y - lower_landing_y + 0.5, 0.7)
	collider.shape = box
	collider.position = Vector3(0.0, box.size.y * 0.5, 0.16 if inward_only else 0.0)
	target.add_child(collider)
	add_child(target)
	_add_shaft_guard()


func _add_shaft_guard() -> void:
	shaft_guard = StaticBody3D.new()
	shaft_guard.name = "ShaftGuard"
	shaft_guard.collision_layer = 1
	shaft_guard.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(SHAFT_WIDTH, GUARD_THICKNESS, shaft_depth())
	var collider := CollisionShape3D.new()
	collider.shape = shape
	shaft_guard.position.y = upper_landing_y - global_position.y - GUARD_THICKNESS * 0.5
	shaft_guard.position.z = shaft_center_offset()
	shaft_guard.add_child(collider)
	add_child(shaft_guard)


func get_interaction_prompt() -> String:
	return "[E] Use Ladder"


func request_interaction(peer_id: int) -> void:
	for player in get_tree().get_nodes_in_group("spy_players"):
		if not player.is_multiplayer_authority() or not player.has_method("request_ladder_mount"):
			continue
		if player.name.to_int() == peer_id or player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
			player.request_ladder_mount(self)
			return


func shaft_depth() -> float:
	return SHAFT_DEPTH * 0.5 + POCKET_REAR_DEPTH if inward_only else SHAFT_DEPTH


func shaft_center_offset() -> float:
	return (SHAFT_DEPTH - shaft_depth()) * 0.5


func can_mount_from(world_position: Vector3) -> bool:
	return not inward_only or to_local(world_position).z >= 0.0


func approach_side(world_position: Vector3) -> float:
	if inward_only:
		return 1.0
	return -1.0 if to_local(world_position).z < 0.0 else 1.0


func climb_point(height: float, side: float) -> Vector3:
	var point := to_global(Vector3(0.0, 0.0, CLIMB_OFFSET * side))
	point.y = height
	return point


func exit_point(height: float, side: float) -> Vector3:
	var point := to_global(Vector3(0.0, 0.0, LANDING_OFFSET * side))
	point.y = height
	return point
