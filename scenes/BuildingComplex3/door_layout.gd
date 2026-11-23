extends RefCounted

const DOOR_WALL_TILE := preload("res://Assets/Models/Import/Interiors_A/Scenes/Walls/wall_3m_door_a.tscn")
const DOOR_SCENE := preload("res://Assets/Models/Import/Interiors_A/Scenes/Doors/door_b_grp.tscn")
const INTERACTIVE_DOOR := preload("res://scenes/BuildingComplex2/interactive_door.gd")
const DOOR_WIDTH_SCALE := 1.2
const SEGMENT_WIDTH := 3.0


static func randomize_floor(floor: Node3D, grid_size: Vector2i, rng: RandomNumberGenerator, min_doors: int, max_doors: int, reserved_boundary: String = "") -> int:
	var selected := select_doorways(grid_size, rng, min_doors, max_doors, reserved_boundary)
	for boundary_name in selected:
		_add_doorway(floor, boundary_name)
	return selected.size()


static func select_doorways(grid_size: Vector2i, rng: RandomNumberGenerator, min_doors: int, max_doors: int, reserved_boundary: String = "") -> Array[String]:
	var connections: Dictionary[String, Vector2i] = {}
	for boundary in range(1, grid_size.x):
		for row in range(grid_size.y):
			var across := row * grid_size.x + boundary
			connections["Vertical_%d_%d" % [boundary, row]] = Vector2i(across - 1, across)
	for boundary in range(1, grid_size.y):
		for column in range(grid_size.x):
			var down := boundary * grid_size.x + column
			connections["Horizontal_%d_%d" % [boundary, column]] = Vector2i(down - grid_size.x, down)

	connections.erase(reserved_boundary)
	var order := connections.keys()
	for index in range(order.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var saved: String = order[index]
		order[index] = order[other]
		order[other] = saved

	# Connect all rooms first, then add optional routes from the remaining boundaries.
	var components := range(grid_size.x * grid_size.y)
	var selected: Array[String] = []
	var extra: Array[String] = []
	for boundary_name in order:
		var rooms: Vector2i = connections[boundary_name]
		var from_component: int = components[rooms.x]
		var to_component: int = components[rooms.y]
		if from_component == to_component:
			extra.append(boundary_name)
			continue
		selected.append(boundary_name)
		for room in range(components.size()):
			if components[room] == to_component:
				components[room] = from_component

	var minimum := clampi(min_doors, components.size() - 1, order.size())
	var maximum := clampi(max_doors, minimum, order.size())
	var target := rng.randi_range(minimum, maximum)
	for index in range(target - selected.size()):
		selected.append(extra[index])
	return selected


static func _add_doorway(floor: Node3D, boundary_name: String) -> void:
	var walls := floor.get_node("Walls")
	var doors := floor.get_node("Doors")
	var center_name := boundary_name + "_1"
	var center := walls.get_node(NodePath(center_name)) as MeshInstance3D
	var assembly_transform := center.transform
	var baseline_x := assembly_transform.basis.x.normalized()
	assembly_transform.basis.x = baseline_x * DOOR_WIDTH_SCALE
	var opening := DOOR_WALL_TILE.instantiate() as MeshInstance3D
	opening.name = center_name
	opening.transform = assembly_transform
	opening.set_surface_override_material(0, center.get_surface_override_material(0))
	walls.remove_child(center)
	center.queue_free()
	walls.add_child(opening)

	# Resize the adjoining panels to keep the entire wall exactly nine metres.
	var side_scale := (3.0 - DOOR_WIDTH_SCALE) * 0.5
	var side_distance := SEGMENT_WIDTH * (DOOR_WIDTH_SCALE + side_scale) * 0.5
	for suffix in ["_0", "_2"]:
		var neighbor := walls.get_node(NodePath(boundary_name + suffix)) as Node3D
		var outward := (neighbor.position - assembly_transform.origin).normalized()
		var adjusted := neighbor.transform
		adjusted.origin = assembly_transform.origin + outward * side_distance
		adjusted.basis.x = baseline_x * side_scale
		neighbor.transform = adjusted

	var door := DOOR_SCENE.instantiate() as Node3D
	door.name = center_name
	assembly_transform.basis.z *= DOOR_WIDTH_SCALE
	door.transform = assembly_transform
	door.get_node("Door_B_Frame/Door_B_Door").set_script(INTERACTIVE_DOOR)
	doors.add_child(door)
