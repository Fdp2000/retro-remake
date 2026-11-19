@tool
class_name MatchSpawner
extends RefCounted

## Deterministic 3-Tier Match Randomizer (Doc 7 §2 & AGENTS.md §2).
## Uses a seed-pinned RandomNumberGenerator so Host and all Clients spawn
## identical searchable drawers, objectives, Briefcase, gadgets, and floor Water Buckets.
## Always enforces starting_prearmed_traps = 0.

const DEFAULT_OBJECTIVES: Array[String] = ["KEY", "MONEY", "PASSPORT", "PLANS"]
const DEFAULT_GADGETS: Array[String] = ["SPRING", "BOMB", "TRIPWIRE", "DART_GUN"]
const DEFAULT_DRAWER_SCENE: PackedScene = preload("res://entities/props/searchable_drawer.tscn")
const DEFAULT_PICKUP_SCENE: PackedScene = preload("res://entities/props/world_item_pickup.tscn")


func generate_spawn_manifest(match_seed: int) -> Dictionary:
	var resolved_seed: int = match_seed if match_seed != 0 else 7321
	var rng := RandomNumberGenerator.new()
	rng.seed = resolved_seed

	var drawer_count: int = GameConfig.spawner_searchable_drawers_count if GameConfig != null else 12
	var cover_count: int = GameConfig.spawner_cover_props_count if GameConfig != null else 6
	var bucket_count: int = GameConfig.spawner_floor_buckets_count if GameConfig != null else 3

	var drawer_loot: Array[Array] = []
	for obj_id in DEFAULT_OBJECTIVES:
		drawer_loot.append([obj_id])
	drawer_loot.append(["BRIEFCASE"])
	for gadget_id in DEFAULT_GADGETS:
		drawer_loot.append([gadget_id])
	while drawer_loot.size() < drawer_count:
		drawer_loot.append([] as Array[String])

	_shuffle_array(drawer_loot, rng)

	var slot_roles: Array[String] = []
	for i in range(drawer_count):
		slot_roles.append("DRAWER")
	for i in range(cover_count):
		slot_roles.append("COVER")
	for i in range(5):
		slot_roles.append("EMPTY")
	_shuffle_array(slot_roles, rng)

	var bucket_indices: Array[int] = []
	for b_i in range(bucket_count):
		bucket_indices.append(rng.randi_range(0, 999))

	return {
		"seed": resolved_seed,
		"drawer_count": drawer_count,
		"cover_count": cover_count,
		"floor_buckets_count": bucket_count,
		"starting_prearmed_traps": 0,
		"drawer_loot_slots": drawer_loot,
		"slot_roles": slot_roles,
		"bucket_rolls": bucket_indices
	}


func populate_level(
	level_root: Node,
	match_seed: int,
	drawer_scene: PackedScene = null,
	pickup_scene: PackedScene = null,
	skip_rooms: Array[String] = []
) -> Dictionary:
	var manifest: Dictionary = generate_spawn_manifest(match_seed)
	if level_root == null:
		return {
			"seed": int(manifest["seed"]),
			"drawers_spawned": 0,
			"floor_buckets_spawned": 0,
			"starting_prearmed_traps": 0,
			"manifest": manifest
		}

	var f_spawner: Node = level_root.get_node_or_null("BuildingComplex2/FurnitureSpawner")

	var rooms_root_all: Node = level_root.get_node_or_null("BuildingComplex2/Rooms")
	if rooms_root_all != null:
		for r_node in rooms_root_all.get_children():
			var pts_all: Node = r_node.get_node_or_null("FurnitureSpawnPoints")
			if pts_all == null:
				continue
			for m_child in pts_all.get_children():
				if m_child is Marker3D:
					(m_child as Marker3D).set_meta("occupied_by_match_drawer", false)

	var existing_root: Node = level_root.get_node_or_null("MatchSpawnedProps")
	if existing_root != null:
		level_root.remove_child(existing_root)
		existing_root.queue_free()

	var spawn_root := Node3D.new()
	spawn_root.name = "MatchSpawnedProps"
	level_root.add_child(spawn_root)

	var resolved_drawer_scene: PackedScene = drawer_scene if drawer_scene != null else DEFAULT_DRAWER_SCENE
	var resolved_pickup_scene: PackedScene = pickup_scene if pickup_scene != null else DEFAULT_PICKUP_SCENE

	var rooms: Array[Node3D] = _collect_sorted_rooms(level_root, skip_rooms)
	var markers: Array[Marker3D] = []
	for room in rooms:
		var pts: Node = room.get_node_or_null("FurnitureSpawnPoints")
		if pts == null:
			continue
		var room_markers: Array[Marker3D] = []
		for child in pts.get_children():
			if child is Marker3D:
				room_markers.append(child as Marker3D)
		room_markers.sort_custom(func(a: Marker3D, b: Marker3D) -> bool: return String(a.name) < String(b.name))
		markers.append_array(room_markers)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(manifest["seed"]) ^ 0x5A17
	if not markers.is_empty():
		_shuffle_array(markers, rng)

	var drawer_loot: Array = manifest["drawer_loot_slots"]
	var drawers_spawned: int = 0
	var used_marker_count: int = mini(drawer_loot.size(), markers.size())

	for i in range(used_marker_count):
		var marker: Marker3D = markers[i]
		marker.set_meta("occupied_by_match_drawer", true)
		for old_child in marker.get_children():
			marker.remove_child(old_child)
			old_child.queue_free()
		var drawer: Node = resolved_drawer_scene.instantiate()
		drawer.name = "MatchDrawer_%02d" % i
		var typed_items: Array[String] = []
		for entry in (drawer_loot[i] as Array):
			typed_items.append(str(entry))
		drawer.set("stored_items", typed_items)
		drawer.set("armed_spring", false)
		drawer.set("armed_bomb", false)
		drawer.set("container_seed", int(manifest["seed"]) + i * 31)
		spawn_root.add_child(drawer)
		if drawer is Node3D and marker.is_inside_tree():
			(drawer as Node3D).global_transform = marker.global_transform
		drawers_spawned += 1

	if f_spawner != null:
		if f_spawner.has_method("reset_and_populate") and not Engine.is_editor_hint():
			f_spawner.call("reset_and_populate", int(manifest["seed"]))
		else:
			f_spawner.set("layout_seed", int(manifest["seed"]))

	var buckets_spawned: int = 0
	if not rooms.is_empty():
		var bucket_target: int = int(manifest["floor_buckets_count"])
		var shuffled_rooms: Array[Node3D] = rooms.duplicate()
		_shuffle_array(shuffled_rooms, rng)
		for b_idx in range(bucket_target):
			var target_room: Node3D = shuffled_rooms[b_idx % shuffled_rooms.size()]
			var bucket_pickup: Node = resolved_pickup_scene.instantiate()
			bucket_pickup.name = "MatchFloorBucket_%d" % b_idx
			bucket_pickup.set("item_id", "BUCKET")
			spawn_root.add_child(bucket_pickup)
			if bucket_pickup is Node3D:
				var jitter := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
				var base_pos: Vector3 = target_room.global_position if target_room.is_inside_tree() else target_room.position
				(bucket_pickup as Node3D).global_position = Vector3(base_pos.x + jitter.x, maxf(base_pos.y, 0.0), base_pos.z + jitter.z)
			buckets_spawned += 1

	return {
		"seed": int(manifest["seed"]),
		"drawers_spawned": drawers_spawned,
		"floor_buckets_spawned": buckets_spawned,
		"starting_prearmed_traps": 0,
		"manifest": manifest
	}


func _collect_sorted_rooms(level_root: Node, skip_rooms: Array[String]) -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	var rooms_root: Node = level_root.get_node_or_null("BuildingComplex2/Rooms")
	if rooms_root == null:
		return rooms
	for c in rooms_root.get_children():
		if c is Node3D and not (String(c.name) in skip_rooms):
			rooms.append(c as Node3D)
	rooms.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	return rooms


func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
