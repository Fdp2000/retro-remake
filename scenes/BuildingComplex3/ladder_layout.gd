extends Node

const DOOR_LAYOUT := preload("res://scenes/BuildingComplex3/door_layout.gd")
const INTERACTIVE_LADDER := preload("res://scenes/BuildingComplex3/interactive_ladder.gd")
const LADDER_SCENE := preload("res://Assets/Models/Prefabs/ladder_2.tscn")
const TILE_SIDE := 3.0
const SHAFT_WIDTH := INTERACTIVE_LADDER.SHAFT_WIDTH
const SHAFT_DEPTH := INTERACTIVE_LADDER.SHAFT_DEPTH
const LADDER_HEIGHT := 2.87

@export_range(11, 17) var min_doors_per_floor: int = 11
@export_range(11, 17) var max_doors_per_floor: int = 15
@export_range(1, 12) var ladder_count: int = 4
## Zero randomizes offline launches. Network games always use the shared match seed.
@export var layout_seed: int = 0

var reserved_lower_boundary := ""
var reserved_ladder_rooms: Array[StringName] = []
var _layout_built := false

@onready var building: Node3D = get_parent()


func _ready() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		MatchManager.match_started.connect(_build_layout, CONNECT_ONE_SHOT)
	else:
		var seeder := RandomNumberGenerator.new()
		seeder.randomize()
		# Wait for both floors' palette scripts to finish their initial setup.
		_build_layout.call_deferred(layout_seed if layout_seed != 0 else seeder.randi())


func _build_layout(seed_value: int) -> void:
	if _layout_built:
		return
	_layout_built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid_size: Vector2i = building.get_meta("grid_size")
	var lower_doors := DOOR_LAYOUT.randomize_floor(building, grid_size, rng, min_doors_per_floor, max_doors_per_floor, reserved_lower_boundary)
	var upper_doors := DOOR_LAYOUT.randomize_floor(building.get_node("SecondFloor") as Node3D, grid_size, rng, min_doors_per_floor, max_doors_per_floor)
	var ladders := _spawn_ladders(rng)
	print("BuildingComplex3: seed %d opened %d downstairs doors, %d upstairs doors, and %d ladder shafts." % [
		seed_value, lower_doors, upper_doors, ladders
	])


func _spawn_ladders(rng: RandomNumberGenerator) -> int:
	var markers: Array[Marker3D] = []
	for room in building.get_node("Rooms").get_children():
		if room.name in reserved_ladder_rooms:
			continue
		var marker := room.get_node_or_null("LadderSpawn") as Marker3D
		if marker != null:
			markers.append(marker)

	for index in range(markers.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var saved := markers[index]
		markers[index] = markers[other]
		markers[other] = saved

	var spawned := 0
	for index in range(mini(maxi(ladder_count, 1), markers.size())):
		if _open_shaft(markers[index]):
			spawned += 1
	return spawned


func _open_shaft(marker: Marker3D) -> bool:
	var upper_floor := building.get_node("SecondFloor") as Node3D
	var upper_room := upper_floor.get_node_or_null(NodePath("Rooms/" + String(marker.get_parent().name)))
	var ceiling_path := NodePath("Roofs/" + String(marker.get_meta("ceiling_tile")))
	var ceiling := building.get_node_or_null(ceiling_path) as Node3D
	if upper_room == null or ceiling == null:
		push_error("Missing ladder shaft geometry for %s" % marker.get_path())
		return false
	var floor_tile := upper_room.get_node_or_null("Floor_1_1") as Node3D
	if floor_tile == null:
		push_error("Missing upper floor tile for %s" % marker.get_path())
		return false

	var ladder := INTERACTIVE_LADDER.new()
	ladder.name = "AccessLadder"
	ladder.lower_landing_y = marker.global_position.y
	ladder.upper_landing_y = upper_floor.global_position.y
	var model := LADDER_SCENE.instantiate() as Node3D
	var ladder_scale := (upper_floor.position.y - marker.position.y + 0.15) / LADDER_HEIGHT
	model.scale = Vector3.ONE * ladder_scale
	ladder.climb_body = model.get_node("Ladder/StaticBody3D") as PhysicsBody3D
	ladder.add_child(model)
	_replace_with_shaft_edges(ceiling)
	_replace_with_shaft_edges(floor_tile)
	marker.add_child(ladder)
	return true


func _replace_with_shaft_edges(tile: Node3D) -> void:
	var tile_parent := tile.get_parent()
	var edge_width := (TILE_SIDE - SHAFT_WIDTH) * 0.5
	var edge_depth := (TILE_SIDE - SHAFT_DEPTH) * 0.5
	var side_x := (TILE_SIDE + SHAFT_WIDTH) * 0.25
	var side_z := (TILE_SIDE + SHAFT_DEPTH) * 0.25
	_add_edge(tile, "West", Vector3(-side_x, 0, 0), Vector2(edge_width, TILE_SIDE))
	_add_edge(tile, "East", Vector3(side_x, 0, 0), Vector2(edge_width, TILE_SIDE))
	_add_edge(tile, "North", Vector3(0, 0, -side_z), Vector2(SHAFT_WIDTH, edge_depth))
	_add_edge(tile, "South", Vector3(0, 0, side_z), Vector2(SHAFT_WIDTH, edge_depth))
	tile_parent.remove_child(tile)
	tile.queue_free()


func _add_edge(tile: Node3D, suffix: String, offset: Vector3, size: Vector2) -> void:
	var edge := tile.duplicate() as Node3D
	edge.name = String(tile.name) + "_Shaft" + suffix
	var edge_basis := Basis.from_scale(Vector3(size.x / TILE_SIDE, 1.0, size.y / TILE_SIDE))
	edge.transform = tile.transform * Transform3D(edge_basis, offset)
	tile.get_parent().add_child(edge)
