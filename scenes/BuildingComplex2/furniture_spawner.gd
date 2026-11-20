@tool
extends Node
## Populate only at runtime; fixed ordering gives both peers identical furniture.
const CATALOG = preload("res://scenes/BuildingComplex2/household_furniture_catalog.gd")
## Minimum world-space clearance radius around a spawned SearchableDrawer so adjacent
## decorative furniture never clips into the desk or blocks its open sliding tray.
const DRAWER_NEIGHBOR_CLEARANCE_RADIUS: float = 2.65
const MAX_FURNITURE_WIDTH: float = 1.75
const MAX_FURNITURE_DEPTH: float = 1.05
const MAX_FURNITURE_HEIGHT: float = 2.50

@export var layout_seed: int = 7321
var spawned_count: int = 0

func _ready() -> void:
	if not Engine.is_editor_hint():
		call_deferred("populate")

func reset_and_populate(new_seed: int) -> void:
	layout_seed = new_seed
	spawned_count = 0
	var rooms: Node = get_parent().get_node_or_null("Rooms") if get_parent() != null else null
	if rooms != null:
		for room in rooms.get_children():
			var markers: Node = room.get_node_or_null("FurnitureSpawnPoints")
			if markers == null:
				continue
			for marker in markers.get_children():
				if marker is Marker3D:
					for child in marker.get_children():
						marker.remove_child(child)
						child.queue_free()
	populate()


func populate() -> void:
	if spawned_count > 0:
		return
	var source := Node3D.new()
	var pieces: Array[Node3D] = []
	for packed in CATALOG.SCENES:
		var child := packed.instantiate() as Node3D
		if child == null:
			continue
		child.name = packed.resource_path.get_file().get_basename().replace(" ", "_")
		child.set_meta("source_asset", packed.resource_path)
		source.add_child(child)
		pieces.append(child)
	pieces.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	if pieces.is_empty():
		push_error("Furniture source has no furniture objects.")
		source.free()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	for index in range(pieces.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var saved := pieces[index]
		pieces[index] = pieces[other]
		pieces[other] = saved
	var rooms := get_parent().get_node("Rooms")
	for room in rooms.get_children():
		var markers := room.get_node_or_null("FurnitureSpawnPoints")
		if markers == null:
			continue
		var occupied_drawer_positions: Array[Vector3] = []
		for m_check in markers.get_children():
			if m_check is Marker3D and bool((m_check as Marker3D).get_meta("occupied_by_match_drawer", false)):
				occupied_drawer_positions.append((m_check as Marker3D).position)

		for marker in markers.get_children():
			if not marker is Marker3D:
				continue
			var marker_3d := marker as Marker3D
			if bool(marker_3d.get_meta("occupied_by_match_drawer", false)):
				continue
			if _is_too_close_to_occupied_drawer(marker_3d.position, occupied_drawer_positions):
				continue
			var anchor := Node3D.new()
			anchor.name = "PlacedFurniture"
			anchor.add_to_group("spawned_furniture")
			var original := pieces[spawned_count % pieces.size()]
			var piece := original.duplicate() as Node3D
			piece.position = Vector3.ZERO
			anchor.add_child(piece)
			var bounds := _bounds(piece, Transform3D.IDENTITY)
			# Wall markers are 1 m from the wall; clamp width/depth so corner & wall props stay clear.
			var fit := minf(1.0, minf(MAX_FURNITURE_WIDTH / maxf(bounds.size.x, 0.001),
				minf(MAX_FURNITURE_DEPTH / maxf(bounds.size.z, 0.001), MAX_FURNITURE_HEIGHT / maxf(bounds.size.y, 0.001))))
			anchor.scale = Vector3.ONE * fit
			anchor.rotation.y = _compute_inward_yaw_correction(marker_3d)
			piece.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
			_add_collision(piece)
			anchor.set_meta("source_piece", String(original.name))
			anchor.set_meta("source_asset", original.get_meta("source_asset"))
			marker_3d.add_child(anchor)
			spawned_count += 1
	source.free()
	print("BuildingComplex2: placed %d furniture pieces at room markers." % spawned_count)


func _is_too_close_to_occupied_drawer(marker_pos: Vector3, drawer_positions: Array[Vector3]) -> bool:
	for d_pos in drawer_positions:
		if marker_pos.distance_to(d_pos) < DRAWER_NEIGHBOR_CLEARANCE_RADIUS:
			return true
	return false


func _compute_inward_yaw_correction(marker: Marker3D) -> float:
	# East & West wall markers in BuildingComplex2 have local +Z pointing into the wall instead of into the room.
	var local_offset: Vector3 = marker.position
	var desired_inward: Vector3 = Vector3.ZERO
	if absf(local_offset.x) > absf(local_offset.z):
		desired_inward = Vector3(-signf(local_offset.x), 0.0, 0.0)
	else:
		desired_inward = Vector3(0.0, 0.0, -signf(local_offset.z))
	var current_forward: Vector3 = marker.transform.basis.z.normalized()
	if current_forward.dot(desired_inward) < -0.5:
		return PI
	return 0.0

func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var current := parent_transform * node.transform
	var result := AABB()
	var found := false
	if node is MeshInstance3D and node.mesh != null:
		result = current * node.get_aabb()
		found = true
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _bounds(child, current)
			if child_bounds.size != Vector3.ZERO:
				result = result.merge(child_bounds) if found else child_bounds
				found = true
	return result

func _add_collision(node: Node3D) -> void:
	var children := node.get_children()
	if node is MeshInstance3D and node.mesh != null:
		var body := StaticBody3D.new()
		body.name = "FurnitureCollision"
		body.collision_layer = 1
		body.collision_mask = 4
		var shape := CollisionShape3D.new()
		shape.shape = node.mesh.create_trimesh_shape()
		body.add_child(shape)
		node.add_child(body)
	for child in children:
		if child is Node3D:
			_add_collision(child)
