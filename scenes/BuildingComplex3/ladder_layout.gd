extends Node

const DOOR_LAYOUT := preload("res://scenes/BuildingComplex3/door_layout.gd")
const INTERACTIVE_LADDER := preload("res://scenes/BuildingComplex3/interactive_ladder.gd")
const LADDER_SCENE := preload("res://Assets/Models/Prefabs/ladder_2.tscn")
const UPPER_FLOOR_SCENE := preload("res://scenes/BuildingComplex3/BuildingComplex3UpperFloor.tscn")
const TILE_SIDE := 3.0
const SHAFT_WIDTH := INTERACTIVE_LADDER.SHAFT_WIDTH
const SHAFT_LINER_THICKNESS := 0.02
const LADDER_HEIGHT := 2.87

@export_range(11, 17) var min_doors_per_floor: int = 11
@export_range(11, 17) var max_doors_per_floor: int = 15
@export_range(1, 12) var ladder_count: int = 4
## Zero randomizes offline launches. Network games always use the shared match seed.
@export var layout_seed: int = 0

var reserved_lower_boundary := ""
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


func _is_upper_floor_enabled() -> bool:
	if MatchManager != null and not MatchManager.active_spawner_config.is_empty():
		var cfg: Dictionary = MatchManager.active_spawner_config
		if cfg.has("enable_upper_floor"):
			return bool(cfg["enable_upper_floor"])
		if cfg.has("active_preset_players"):
			return int(cfg["active_preset_players"]) > 2
	if GameConfig != null:
		return GameConfig.spawner_enable_upper_floor
	return true


func sync_upper_floor_state(enable_upper: bool, seed_value: int) -> void:
	if not _layout_built:
		_build_layout(seed_value)
		return
	if building == null:
		return

	var upper_floor := building.get_node_or_null("SecondFloor") as Node3D
	if not enable_upper:
		if upper_floor != null:
			building.remove_child(upper_floor)
			upper_floor.queue_free()
		var rooms_root := building.get_node_or_null("Rooms")
		if rooms_root != null:
			for room in rooms_root.get_children():
				var marker := room.get_node_or_null("LadderSpawn")
				if marker != null:
					for c in marker.get_children():
						if c.name == &"AccessLadder" or c is INTERACTIVE_LADDER:
							marker.remove_child(c)
							c.queue_free()
		var roofs := building.get_node_or_null("Roofs")
		if roofs != null:
			for c in roofs.get_children():
				if bool(c.get_meta("ladder_shaft_piece", false)):
					roofs.remove_child(c)
					c.queue_free()
				elif bool(c.get_meta("hidden_for_ladder_shaft", false)):
					c.remove_meta("hidden_for_ladder_shaft")
					if c is Node3D:
						(c as Node3D).visible = true
					for sb in c.find_children("*", "StaticBody3D", true, false):
						if sb is StaticBody3D:
							(sb as StaticBody3D).collision_layer = int(sb.get_meta("orig_collision_layer", 1))
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value ^ 0x4C4144
		if upper_floor == null:
			upper_floor = UPPER_FLOOR_SCENE.instantiate() as Node3D
			upper_floor.name = "SecondFloor"
			upper_floor.position = Vector3(0.0, 3.22, 0.0)
			building.add_child(upper_floor)
			var grid_size: Vector2i = building.get_meta("grid_size")
			DOOR_LAYOUT.randomize_floor(upper_floor, grid_size, rng, min_doors_per_floor, max_doors_per_floor)
		var has_ladders := false
		var rooms_root := building.get_node_or_null("Rooms")
		if rooms_root != null:
			for room in rooms_root.get_children():
				var marker := room.get_node_or_null("LadderSpawn")
				if marker != null and marker.get_node_or_null("AccessLadder") != null:
					has_ladders = true
					break
		if not has_ladders:
			_spawn_ladders(rng)


func _build_layout(seed_value: int) -> void:
	if _layout_built:
		return
	_layout_built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid_size: Vector2i = building.get_meta("grid_size")
	var lower_doors := DOOR_LAYOUT.randomize_floor(building, grid_size, rng, min_doors_per_floor, max_doors_per_floor, reserved_lower_boundary)
	var upper_doors := 0
	var ladders := 0
	var upper_floor := building.get_node_or_null("SecondFloor") as Node3D
	if _is_upper_floor_enabled():
		if upper_floor != null:
			upper_doors = DOOR_LAYOUT.randomize_floor(upper_floor, grid_size, rng, min_doors_per_floor, max_doors_per_floor)
		ladders = _spawn_ladders(rng)
	elif upper_floor != null:
		building.remove_child(upper_floor)
		upper_floor.queue_free()
	print("BuildingComplex3: seed %d opened %d downstairs doors, %d upstairs doors, and %d ladder shafts (upper_floor=%s)." % [
		seed_value, lower_doors, upper_doors, ladders, str(_is_upper_floor_enabled())
	])


func _spawn_ladders(rng: RandomNumberGenerator) -> int:
	var markers: Array[Marker3D] = []
	for room in building.get_node("Rooms").get_children():
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
	var floor_path := NodePath(marker.get_meta("upper_floor_tile", "Floor_1_1"))
	var floor_tile := upper_room.get_node_or_null(floor_path) as Node3D
	if floor_tile == null:
		push_error("Missing upper floor tile for %s" % marker.get_path())
		return false

	var ladder := INTERACTIVE_LADDER.new()
	ladder.name = "AccessLadder"
	ladder.inward_only = marker.has_meta("upper_floor_tile")
	ladder.lower_landing_y = marker.global_position.y
	ladder.upper_landing_y = upper_floor.global_position.y
	var model := LADDER_SCENE.instantiate() as Node3D
	var ladder_scale := (ladder.upper_landing_y - ladder.lower_landing_y + 0.15) / LADDER_HEIGHT
	model.scale = Vector3.ONE * ladder_scale
	ladder.climb_body = model.get_node("Ladder/StaticBody3D") as PhysicsBody3D
	ladder.add_child(model)
	marker.add_child(ladder)
	_add_shaft_liner(ladder, ceiling as MeshInstance3D)
	_replace_with_shaft_edges(ceiling, ladder)
	_replace_with_shaft_edges(floor_tile, ladder)
	return true


func _replace_with_shaft_edges(tile: Node3D, ladder: INTERACTIVE_LADDER) -> void:
	var shaft_center := ladder.to_global(Vector3(0.0, 0.0, ladder.shaft_center_offset()))
	var center := tile.to_local(shaft_center)
	var forward := tile.global_transform.basis.inverse() * ladder.global_transform.basis.z
	var opening_size := Vector2(SHAFT_WIDTH, ladder.shaft_depth())
	if absf(forward.x) > absf(forward.z):
		opening_size = Vector2(opening_size.y, opening_size.x)
	var opening := Rect2(Vector2(center.x, center.z) - opening_size * 0.5, opening_size)
	var half_tile := TILE_SIDE * 0.5
	_add_edge(tile, "West", Rect2(-half_tile, -half_tile, opening.position.x + half_tile, TILE_SIDE))
	_add_edge(tile, "East", Rect2(opening.end.x, -half_tile, half_tile - opening.end.x, TILE_SIDE))
	_add_edge(tile, "North", Rect2(opening.position.x, -half_tile, opening.size.x, opening.position.y + half_tile))
	_add_edge(tile, "South", Rect2(opening.position.x, opening.end.y, opening.size.x, half_tile - opening.end.y))
	if tile.get_parent() != null and tile.get_parent().name == &"Roofs":
		tile.set_meta("hidden_for_ladder_shaft", true)
		tile.visible = false
		for sb in tile.find_children("*", "StaticBody3D", true, false):
			if sb is StaticBody3D:
				sb.set_meta("orig_collision_layer", (sb as StaticBody3D).collision_layer)
				(sb as StaticBody3D).collision_layer = 0
	else:
		tile.get_parent().remove_child(tile)
		tile.queue_free()


func _add_edge(tile: Node3D, suffix: String, strip: Rect2) -> void:
	var edge := tile.duplicate() as Node3D
	edge.name = String(tile.name) + "_Shaft" + suffix
	edge.set_meta("ladder_shaft_piece", true)
	var center := strip.get_center()
	var basis := Basis.from_scale(Vector3(strip.size.x / TILE_SIDE, 1.0, strip.size.y / TILE_SIDE))
	edge.transform = tile.transform * Transform3D(basis, Vector3(center.x, 0.0, center.y))
	tile.get_parent().add_child(edge)

func _add_shaft_liner(ladder: INTERACTIVE_LADDER, ceiling: MeshInstance3D) -> void:
	var ceiling_y := ceiling.global_position.y
	var height := maxf(ladder.upper_landing_y - ceiling_y - 0.002, 0.0)
	if height <= 0.0:
		return

	# The modular slabs have horizontal faces only. Seal the exposed gap between them.
	var liner := Node3D.new()
	liner.name = "ShaftLiner"
	liner.position = Vector3(0.0, ceiling_y - ladder.global_position.y + height * 0.5 + 0.001, ladder.shaft_center_offset())
	ladder.add_child(liner)

	var depth := ladder.shaft_depth()
	var thickness := SHAFT_LINER_THICKNESS
	var x_edge := (SHAFT_WIDTH + thickness) * 0.5
	var z_edge := (depth + thickness) * 0.5
	var material := ceiling.get_active_material(0)
	_add_liner_strip(liner, Vector3(-x_edge, 0.0, 0.0), Vector3(thickness, height, depth), material)
	_add_liner_strip(liner, Vector3(x_edge, 0.0, 0.0), Vector3(thickness, height, depth), material)
	_add_liner_strip(liner, Vector3(0.0, 0.0, -z_edge), Vector3(SHAFT_WIDTH + thickness * 2.0, height, thickness), material)
	_add_liner_strip(liner, Vector3(0.0, 0.0, z_edge), Vector3(SHAFT_WIDTH + thickness * 2.0, height, thickness), material)


func _add_liner_strip(liner: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var strip := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	strip.mesh = mesh
	strip.material_override = material
	strip.position = center
	liner.add_child(strip)
