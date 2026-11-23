@tool
extends "res://scenes/BuildingComplex2/furniture_spawner.gd"

const PREFABS = {
	"bin_2": preload("res://Assets/Models/Prefabs/bin_2.tscn"),
	"chair_a": preload("res://Assets/Models/Prefabs/chair_a.tscn"),
	"chair_d": preload("res://Assets/Models/Prefabs/chair_d.tscn"),
	"chair_e": preload("res://Assets/Models/Prefabs/chair_e.tscn"),
	"coathanger": preload("res://Assets/Models/Prefabs/coathanger.tscn"),
	"desk_2": preload("res://Assets/Models/Prefabs/desk_2.tscn"),
	"drawer_a": preload("res://Assets/Models/Prefabs/drawer_a.tscn"),
	"drawer_b": preload("res://Assets/Models/Prefabs/drawer_b.tscn"),
	"large_safe": preload("res://Assets/Models/Prefabs/large_safe.tscn"),
	"shelf_a": preload("res://Assets/Models/Prefabs/shelf_a.tscn"),
	"shelf_b": preload("res://Assets/Models/Prefabs/shelf_b.tscn"),
	"shelf_c": preload("res://Assets/Models/Prefabs/shelf_c.tscn"),
	"shelf_d": preload("res://Assets/Models/Prefabs/shelf_d.tscn"),
	"sofa_a": preload("res://Assets/Models/Prefabs/sofa_a.tscn"),
	"table_a": preload("res://Assets/Models/Prefabs/table_a.tscn"),
}

const ROOM_LAYOUTS = [
	["desk_2", "chair_a"],
	["desk_2", "shelf_c"],
	["desk_2", "bin_2"],
	["sofa_a", "table_a"],
	["sofa_a", "shelf_b"],
	["sofa_a", "chair_e"],
	["table_a", "chair_d"],
	["table_a", "shelf_a"],
	["table_a", "coathanger"],
	["drawer_a", "chair_e"],
	["drawer_a", "shelf_d"],
	["drawer_b", "chair_a"],
	["drawer_b", "coathanger"],
	["large_safe", "shelf_c"],
	["large_safe", "drawer_b"],
	["shelf_b", "chair_d"],
]


func populate() -> void:
	if spawned_count > 0:
		return

	var layouts := ROOM_LAYOUTS.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	for index in range(layouts.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var saved: Array = layouts[index]
		layouts[index] = layouts[other]
		layouts[other] = saved

	var room_index := 0
	for room in get_parent().get_node("Rooms").get_children():
		var markers := room.get_node_or_null("FurnitureSpawnPoints")
		if markers == null:
			continue

		var layout: Array = layouts[room_index % layouts.size()]
		room_index += 1
		var occupied_drawer_positions: Array[Vector3] = []
		for child in markers.get_children():
			if child is Marker3D and bool(child.get_meta("occupied_by_match_drawer", false)):
				occupied_drawer_positions.append(child.position)

		var slot := 0
		for child in markers.get_children():
			var marker := child as Marker3D
			if marker == null:
				continue
			var prefab_name: String = layout[slot % layout.size()]
			slot += 1
			if _is_too_close_to_occupied_drawer(marker.position, occupied_drawer_positions):
				continue
			_place_prefab(marker, prefab_name)

	print("BuildingComplex3: placed %d prefab furniture pieces." % spawned_count)


func _place_prefab(marker: Marker3D, prefab_name: String) -> void:
	var scene: PackedScene = PREFABS[prefab_name]
	var piece := scene.instantiate() as Node3D
	piece.position = Vector3.ZERO
	var bounds := _bounds(piece, Transform3D.IDENTITY)
	var fit := minf(1.0, minf(MAX_FURNITURE_WIDTH / maxf(bounds.size.x, 0.001),
		minf(MAX_FURNITURE_DEPTH / maxf(bounds.size.z, 0.001),
			MAX_FURNITURE_HEIGHT / maxf(bounds.size.y, 0.001))))

	var anchor := Node3D.new()
	anchor.name = "PlacedFurniture"
	anchor.add_to_group("spawned_furniture")
	anchor.set_meta("source_piece", prefab_name)
	anchor.set_meta("source_asset", scene.resource_path)
	anchor.scale = Vector3.ONE * fit
	anchor.rotation.y = _compute_inward_yaw_correction(marker)

	piece.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	anchor.add_child(piece)
	marker.add_child(anchor)
	spawned_count += 1
