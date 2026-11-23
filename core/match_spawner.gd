@tool
class_name MatchSpawner
extends RefCounted

## Deterministic 3-Tier Match Randomizer (Doc 7 §2 & AGENTS.md §2).
## Uses a seed-pinned RandomNumberGenerator so Host and all Clients spawn
## identical searchable drawers, objectives, Briefcase, gadgets, and floor Water Buckets.
## Always enforces starting_prearmed_traps = 0 and respects per-room drawer caps
## plus min/max gadget & bucket bounds from GameConfig.

const DEFAULT_OBJECTIVES: Array[String] = ["KEY", "MONEY", "PASSPORT", "PLANS"]
const DEFAULT_GADGETS: Array[String] = ["SPRING", "BOMB", "TRIPWIRE", "DART_GUN"]
const SPAWN_ROOM_NAMES: Array[String] = ["Room_1_1", "Room_4_4"]
const DEFAULT_DRAWER_SCENE: PackedScene = preload("res://entities/props/searchable_drawer.tscn")
const DEFAULT_PICKUP_SCENE: PackedScene = preload("res://entities/props/world_item_pickup.tscn")


func _resolve_config(custom_config: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = {}
	if GameConfig != null and GameConfig.has_method("get_spawner_config_dict"):
		cfg = GameConfig.get_spawner_config_dict()
	else:
		cfg = {
			"min_drawers": 16,
			"max_drawers": 20,
			"max_drawers_per_room": 2,
			"allow_drawers_in_spawn_rooms": true,
			"max_drawers_in_spawn_room": 1,
			"isolate_briefcase_from_objectives": true,
			"min_total_gadgets": 11,
			"max_total_gadgets": 14,
			"spring_min": 1,
			"spring_max": 6,
			"bomb_min": 1,
			"bomb_max": 6,
			"tripwire_min": 1,
			"tripwire_max": 6,
			"dart_gun_min": 0,
			"dart_gun_max": 4,
			"floor_buckets_min": 3,
			"floor_buckets_max": 5,
			"cover_props_count": 6
		}
	for k in custom_config.keys():
		cfg[k] = custom_config[k]
	return cfg


func generate_spawn_manifest(match_seed: int, custom_config: Dictionary = {}) -> Dictionary:
	var resolved_seed: int = match_seed if match_seed != 0 else 7321
	var rng := RandomNumberGenerator.new()
	rng.seed = resolved_seed

	var cfg: Dictionary = _resolve_config(custom_config)

	var min_drawers: int = maxi(int(cfg.get("min_drawers", 16)), DEFAULT_OBJECTIVES.size() + 1)
	var max_drawers: int = maxi(int(cfg.get("max_drawers", min_drawers)), min_drawers)
	var drawer_count: int = rng.randi_range(min_drawers, max_drawers)
	var max_per_room: int = clampi(int(cfg.get("max_drawers_per_room", 2)), 1, 8)
	var allow_spawn_rooms: bool = bool(cfg.get("allow_drawers_in_spawn_rooms", true))
	var max_in_spawn_room: int = clampi(int(cfg.get("max_drawers_in_spawn_room", 1)), 0, max_per_room)
	var isolate_briefcase: bool = bool(cfg.get("isolate_briefcase_from_objectives", true))
	var cover_count: int = maxi(int(cfg.get("cover_props_count", 6)), 0)

	var b_min: int = maxi(int(cfg.get("floor_buckets_min", 3)), 0)
	var b_max: int = maxi(int(cfg.get("floor_buckets_max", b_min)), b_min)
	var bucket_count: int = rng.randi_range(b_min, b_max)

	# 1. Core mandatory drawer items (4 Objectives + 1 Briefcase = 5 items)
	var drawer_loot: Array[Array] = []
	for obj_id in DEFAULT_OBJECTIVES:
		drawer_loot.append([obj_id])
	drawer_loot.append(["BRIEFCASE"])

	var remaining_drawer_capacity: int = maxi(drawer_count - drawer_loot.size(), 0)

	# 2. Build gadget pool using per-gadget [min..max] and total gadget [min..max]
	var gadget_specs: Array[Dictionary] = [
		{"id": "SPRING", "min": maxi(int(cfg.get("spring_min", 1)), 0), "max": maxi(int(cfg.get("spring_max", 2)), 0)},
		{"id": "BOMB", "min": maxi(int(cfg.get("bomb_min", 1)), 0), "max": maxi(int(cfg.get("bomb_max", 2)), 0)},
		{"id": "TRIPWIRE", "min": maxi(int(cfg.get("tripwire_min", 1)), 0), "max": maxi(int(cfg.get("tripwire_max", 2)), 0)},
		{"id": "DART_GUN", "min": maxi(int(cfg.get("dart_gun_min", 1)), 0), "max": maxi(int(cfg.get("dart_gun_max", 2)), 0)}
	]

	var min_total_gadgets: int = clampi(int(cfg.get("min_total_gadgets", 4)), 0, remaining_drawer_capacity)
	var max_total_gadgets: int = clampi(maxi(int(cfg.get("max_total_gadgets", 6)), min_total_gadgets), min_total_gadgets, remaining_drawer_capacity)
	var target_total_gadgets: int = rng.randi_range(min_total_gadgets, max_total_gadgets)

	var gadget_counts: Dictionary = {
		"SPRING": 0,
		"BOMB": 0,
		"TRIPWIRE": 0,
		"DART_GUN": 0
	}
	var selected_gadgets: Array[String] = []

	# First satisfy each gadget's minimum (shuffled order in case sum of mins > max_total_gadgets)
	var min_candidates: Array[String] = []
	for spec in gadget_specs:
		var g_id: String = str(spec["id"])
		var g_min: int = int(spec["min"])
		var g_max: int = maxi(int(spec["max"]), g_min)
		spec["max"] = g_max
		for _k in range(g_min):
			min_candidates.append(g_id)
	_shuffle_array(min_candidates, rng)
	for g_id in min_candidates:
		if selected_gadgets.size() >= max_total_gadgets or selected_gadgets.size() >= remaining_drawer_capacity:
			break
		selected_gadgets.append(g_id)
		gadget_counts[g_id] = int(gadget_counts.get(g_id, 0)) + 1

	# Next fill up to target_total_gadgets from remaining headroom (max - current)
	var extra_pool: Array[String] = []
	for spec in gadget_specs:
		var g_id: String = str(spec["id"])
		var cur_c: int = int(gadget_counts.get(g_id, 0))
		var g_max: int = int(spec["max"])
		for _k in range(maxi(g_max - cur_c, 0)):
			extra_pool.append(g_id)
	_shuffle_array(extra_pool, rng)
	for g_id in extra_pool:
		if selected_gadgets.size() >= target_total_gadgets or selected_gadgets.size() >= remaining_drawer_capacity:
			break
		selected_gadgets.append(g_id)
		gadget_counts[g_id] = int(gadget_counts.get(g_id, 0)) + 1

	for g_id in selected_gadgets:
		drawer_loot.append([g_id])

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
		"max_drawers_per_room": max_per_room,
		"allow_drawers_in_spawn_rooms": allow_spawn_rooms,
		"max_drawers_in_spawn_room": max_in_spawn_room,
		"isolate_briefcase_from_objectives": isolate_briefcase,
		"cover_count": cover_count,
		"floor_buckets_count": bucket_count,
		"total_gadgets_count": selected_gadgets.size(),
		"gadget_counts": gadget_counts,
		"starting_prearmed_traps": 0,
		"drawer_loot_slots": drawer_loot,
		"slot_roles": slot_roles,
		"bucket_rolls": bucket_indices,
		"config": cfg
	}


func populate_level(
	level_root: Node,
	match_seed: int,
	drawer_scene: PackedScene = null,
	pickup_scene: PackedScene = null,
	skip_rooms: Array[String] = [],
	custom_config: Dictionary = {}
) -> Dictionary:
	var manifest: Dictionary = generate_spawn_manifest(match_seed, custom_config)
	if level_root == null:
		return {
			"seed": int(manifest["seed"]),
			"drawers_spawned": 0,
			"floor_buckets_spawned": 0,
			"starting_prearmed_traps": 0,
			"drawers_per_room": {},
			"manifest": manifest
		}

	var building := _get_building(level_root)
	var f_spawner: Node = building.get_node_or_null("FurnitureSpawner") if building != null else null
	var spawn_room_keys: Array[String] = SPAWN_ROOM_NAMES.duplicate()
	if building != null and building.name == &"BuildingComplex3":
		var grid_size: Vector2i = building.get_meta("grid_size")
		spawn_room_keys[1] = "Room_%d_%d" % [grid_size.y, grid_size.x]

	for room in _collect_sorted_rooms(level_root, []):
		var markers := _get_drawer_markers(room)
		if markers == null:
			continue
		for marker in markers.get_children():
			if marker is Marker3D:
				marker.set_meta("occupied_by_match_drawer", false)

	var existing_root: Node = level_root.get_node_or_null("MatchSpawnedProps")
	if existing_root != null:
		level_root.remove_child(existing_root)
		existing_root.queue_free()

	var spawn_root := Node3D.new()
	spawn_root.name = "MatchSpawnedProps"
	level_root.add_child(spawn_root)

	var resolved_drawer_scene: PackedScene = drawer_scene if drawer_scene != null else DEFAULT_DRAWER_SCENE
	var resolved_pickup_scene: PackedScene = pickup_scene if pickup_scene != null else DEFAULT_PICKUP_SCENE

	var effective_skip_rooms: Array[String] = skip_rooms.duplicate()
	var allow_spawn_rooms: bool = bool(manifest.get("allow_drawers_in_spawn_rooms", true))
	var max_in_spawn_room: int = int(manifest.get("max_drawers_in_spawn_room", 1))
	if not allow_spawn_rooms or max_in_spawn_room <= 0:
		for sp_room in spawn_room_keys:
			if not (sp_room in effective_skip_rooms):
				effective_skip_rooms.append(sp_room)

	var rooms: Array[Node3D] = _collect_sorted_rooms(level_root, effective_skip_rooms)
	var max_per_room: int = maxi(int(manifest.get("max_drawers_per_room", 2)), 1)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(manifest["seed"]) ^ 0x5A17

	# Collect per-room shuffled markers and select at most `max_per_room` markers per room
	# (Contested non-spawn rooms are prioritized on pass 0 so every contested room gets at least 1 drawer first,
	# while spawn rooms are capped at max_in_spawn_room).
	var room_marker_pools: Dictionary = {} # room_name -> Array[Marker3D]
	var contested_room_names: Array[String] = []
	var spawn_room_names: Array[String] = []
	for room in rooms:
		var pts := _get_drawer_markers(room)
		if pts == null:
			continue
		var room_markers: Array[Marker3D] = []
		for child in pts.get_children():
			if child is Marker3D:
				room_markers.append(child as Marker3D)
		if room_markers.is_empty():
			continue
		room_markers.sort_custom(func(a: Marker3D, b: Marker3D) -> bool: return String(a.name) < String(b.name))
		_shuffle_array(room_markers, rng)
		var r_name := _room_key(room)
		room_marker_pools[r_name] = room_markers
		if r_name in spawn_room_keys:
			spawn_room_names.append(r_name)
		else:
			contested_room_names.append(r_name)

	var drawer_loot: Array = (manifest["drawer_loot_slots"] as Array).duplicate(true)
	var target_drawer_count: int = drawer_loot.size()
	var selected_markers: Array[Marker3D] = []
	var selected_marker_rooms: Array[String] = []
	var drawers_per_room: Dictionary = {}
	var chosen_room_positions: Dictionary = {} # room_name -> Array[Vector3]

	# Round-robin pass across shuffled rooms up to max_per_room:
	# Pass 0 guarantees every contested room gets 1 drawer first, then spawn rooms up to max_in_spawn_room.
	for pass_idx in range(max_per_room):
		if selected_markers.size() >= target_drawer_count:
			break
		var pass_contested: Array[String] = contested_room_names.duplicate()
		_shuffle_array(pass_contested, rng)
		var pass_spawns: Array[String] = spawn_room_names.duplicate()
		_shuffle_array(pass_spawns, rng)
		var pass_rooms: Array[String] = []
		pass_rooms.append_array(pass_contested)
		if pass_idx < max_in_spawn_room:
			pass_rooms.append_array(pass_spawns)

		for r_name in pass_rooms:
			if selected_markers.size() >= target_drawer_count:
				break
			var r_cap: int = max_in_spawn_room if (r_name in spawn_room_keys) else max_per_room
			if int(drawers_per_room.get(r_name, 0)) >= r_cap:
				continue
			var r_pool: Array = room_marker_pools[r_name]
			var already_picked: Array = chosen_room_positions.get(r_name, [])
			var chosen_marker: Marker3D = null
			for candidate in r_pool:
				var m_cand := candidate as Marker3D
				var too_close: bool = false
				for prev_pos in already_picked:
					if m_cand.position.distance_to(prev_pos as Vector3) < 2.65:
						too_close = true
						break
				if not too_close:
					chosen_marker = m_cand
					break
			if chosen_marker != null:
				r_pool.erase(chosen_marker)
				already_picked.append(chosen_marker.position)
				chosen_room_positions[r_name] = already_picked
				selected_markers.append(chosen_marker)
				selected_marker_rooms.append(r_name)
				drawers_per_room[r_name] = int(drawers_per_room.get(r_name, 0)) + 1

	# Shuffle markers together with their room labels
	var paired_indices: Array[int] = []
	for idx in range(selected_markers.size()):
		paired_indices.append(idx)
	_shuffle_array(paired_indices, rng)
	var final_markers: Array[Marker3D] = []
	var final_marker_rooms: Array[String] = []
	for p_i in paired_indices:
		final_markers.append(selected_markers[p_i])
		final_marker_rooms.append(selected_marker_rooms[p_i])
	selected_markers = final_markers
	selected_marker_rooms = final_marker_rooms

	var used_marker_count: int = mini(drawer_loot.size(), selected_markers.size())

	# Enforce Briefcase isolation: if the Briefcase landed in a room that also contains an Objective item in its other drawer,
	# swap the Briefcase with a drawer in a room that has 0 Objectives.
	if bool(manifest.get("isolate_briefcase_from_objectives", true)) and used_marker_count > 1:
		_enforce_briefcase_isolated_from_objectives(drawer_loot, selected_marker_rooms, used_marker_count)

	var drawers_spawned: int = 0

	for i in range(used_marker_count):
		var marker: Marker3D = selected_markers[i]
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
			(drawer as Node3D).global_transform = _compute_inward_facing_drawer_transform(marker)
		drawers_spawned += 1

	manifest["drawer_loot_slots"] = drawer_loot

	if f_spawner != null:
		if f_spawner.has_method("reset_and_populate") and not Engine.is_editor_hint():
			f_spawner.call("reset_and_populate", int(manifest["seed"]))
		else:
			f_spawner.set("layout_seed", int(manifest["seed"]))

	var bucket_rooms: Array[Node3D] = _collect_sorted_rooms(level_root, skip_rooms, false)
	var buckets_spawned: int = 0
	if not bucket_rooms.is_empty():
		var bucket_target: int = int(manifest["floor_buckets_count"])
		var shuffled_rooms: Array[Node3D] = bucket_rooms.duplicate()
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
		"drawers_per_room": drawers_per_room,
		"manifest": manifest
	}


func _enforce_briefcase_isolated_from_objectives(drawer_loot: Array, marker_rooms: Array[String], count: int) -> void:
	var briefcase_idx: int = -1
	var objective_rooms: Dictionary = {} # room_name -> int count of objectives in that room
	for i in range(count):
		var items: Array = drawer_loot[i] as Array
		var r_name: String = marker_rooms[i]
		for item in items:
			var id_str: String = str(item).to_upper()
			if id_str == "BRIEFCASE":
				briefcase_idx = i
			elif id_str in DEFAULT_OBJECTIVES:
				objective_rooms[r_name] = int(objective_rooms.get(r_name, 0)) + 1

	if briefcase_idx == -1:
		return
	var briefcase_room: String = marker_rooms[briefcase_idx]
	if int(objective_rooms.get(briefcase_room, 0)) == 0:
		return # Briefcase is already in a room with zero objectives!

	# Find the first drawer in a room that has 0 objectives and swap loot with it
	for candidate_idx in range(count):
		if candidate_idx == briefcase_idx:
			continue
		var cand_room: String = marker_rooms[candidate_idx]
		if int(objective_rooms.get(cand_room, 0)) == 0:
			var tmp: Variant = drawer_loot[briefcase_idx]
			drawer_loot[briefcase_idx] = drawer_loot[candidate_idx]
			drawer_loot[candidate_idx] = tmp
			return


func _compute_inward_facing_drawer_transform(marker: Marker3D) -> Transform3D:
	# SearchableDrawer slides its tray out along local +Z (from 0.08 to 0.56).
	# In BuildingComplex2, wall markers have local +X/+Z offsets relative to their parent room center.
	# Ensure the drawer's local +Z axis always points toward the room interior (away from the nearest wall).
	var xform: Transform3D = marker.global_transform
	var pts_parent: Node = marker.get_parent()
	if pts_parent != null and pts_parent.name == &"MatchDrawerSpawnPoints":
		return xform
	var room_node: Node3D = (pts_parent.get_parent() as Node3D) if pts_parent != null else null
	if room_node == null:
		return xform

	var local_offset: Vector3 = marker.position
	# Pick the dominant wall axis (whichever of |x| or |z| is closer to the wall at ±3.5m)
	var inward_dir: Vector3 = Vector3.ZERO
	if absf(local_offset.x) > absf(local_offset.z):
		inward_dir = Vector3(-signf(local_offset.x), 0.0, 0.0)
	else:
		inward_dir = Vector3(0.0, 0.0, -signf(local_offset.z))

	var world_inward: Vector3 = (room_node.global_transform.basis * inward_dir).normalized()
	if world_inward.length_squared() < 0.001:
		return xform

	# Construct an orthonormal basis where local +Z (+basis.z) points along world_inward
	var up := Vector3.UP
	var right: Vector3 = up.cross(world_inward).normalized()
	xform.basis = Basis(right, up, world_inward)
	return xform


func _get_building(level_root: Node) -> Node:
	var building := level_root.get_node_or_null("BuildingComplex3")
	return building if building != null else level_root.get_node_or_null("BuildingComplex2")


func _get_drawer_markers(room: Node3D) -> Node:
	var dedicated := room.get_node_or_null("MatchDrawerSpawnPoints")
	return dedicated if dedicated != null else room.get_node_or_null("FurnitureSpawnPoints")


func _room_key(room: Node3D) -> String:
	var floor_node := room.get_parent().get_parent()
	if floor_node.name == &"SecondFloor":
		return "SecondFloor/" + String(room.name)
	return String(room.name)


func _collect_sorted_rooms(level_root: Node, skip_rooms: Array[String], include_upper_floor: bool = true) -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	var building := _get_building(level_root)
	if building == null:
		return rooms
	var room_paths := ["Rooms", "SecondFloor/Rooms"] if include_upper_floor else ["Rooms"]
	for room_path in room_paths:
		var room_root := building.get_node_or_null(room_path)
		if room_root == null:
			continue
		for child in room_root.get_children():
			if child is Node3D and not (_room_key(child) in skip_rooms):
				rooms.append(child)
	rooms.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _room_key(a) < _room_key(b))
	return rooms


func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
