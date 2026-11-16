@tool
extends Node
## Populate only at runtime; fixed ordering gives both peers identical furniture.
@export var furniture_source: PackedScene = preload("res://Assets/Models/Import/Wood Furnitures/GLTF/Furnitures.gltf")
@export var layout_seed: int = 7321
@export var wood_material: Material = preload("res://scenes/BuildingComplex2/furniture_wood.tres")
var spawned_count: int = 0

func _ready() -> void:
	if not Engine.is_editor_hint():
		call_deferred("populate")

func populate() -> void:
	if spawned_count > 0 or furniture_source == null:
		return
	var source := furniture_source.instantiate()
	var pieces: Array[Node3D] = []
	for child in source.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Furniture_"):
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
		for marker in markers.get_children():
			if not marker is Marker3D:
				continue
			var anchor := Node3D.new()
			anchor.name = "PlacedFurniture"
			anchor.add_to_group("spawned_furniture")
			var original := pieces[spawned_count % pieces.size()]
			var piece := original.duplicate() as Node3D
			piece.position = Vector3.ZERO
			anchor.add_child(piece)
			var bounds := _bounds(piece, Transform3D.IDENTITY)
			# Wall markers are 1 m from the wall; reserve a 1.4 m depth.
			var fit := minf(1.0, minf(2.0 / maxf(bounds.size.x, 0.001),
				minf(1.4 / maxf(bounds.size.z, 0.001), 2.7 / maxf(bounds.size.y, 0.001))))
			anchor.scale = Vector3.ONE * fit
			piece.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
			_apply_wood_material(piece)
			_add_collision(piece)
			anchor.set_meta("source_piece", String(original.name))
			marker.add_child(anchor)
			spawned_count += 1
	source.free()
	print("BuildingComplex2: placed %d furniture pieces at room markers." % spawned_count)

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

func _apply_wood_material(node: Node3D) -> void:
	if node is MeshInstance3D:
		node.material_override = wood_material
	for child in node.get_children():
		if child is Node3D:
			_apply_wood_material(child)

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
