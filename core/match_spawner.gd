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
const SPAWN_ROOM_NAMES: Array[String] = ["Room_1_1", "Room_4_4", "Room_1_4", "Room_4_1"]
const DEFAULT_DRAWER_SCENE: PackedScene = preload("res://entities/props/searchable_drawer.tscn")
const DEFAULT_SMALL_DRAWER_SCENE: PackedScene = preload("res://entities/props/searchable_drawer_small.tscn")
const DEFAULT_PICKUP_SCENE: PackedScene = preload("res://entities/props/world_item_pickup.tscn")


func _resolve_config(custom_config: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = {}
	if GameConfig != null and GameConfig.has_method("get_spawner_config_dict"):
		cfg = GameConfig.get_spawner_config_dict()
	else:
		cfg = {
			"min_containers": 24,
			"max_containers": 32,
			"min_drawers": 24,
			"max_drawers": 32,
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
			"floor_traps_min": 2,
			"floor_traps_max": 4,
			"prearmed_buckets_min": 1,
			"prearmed_buckets_max": 2,
			"prearmed_springs_min": 1,
			"prearmed_springs_max": 2,
			"prearmed_bombs_min": 1,
			"prearmed_bombs_max": 2,
			"exclude_spawn_room_doors_from_buckets": true,
			"enable_upper_floor": false,
			"cover_props_count": 6
		}
	for k in custom_config.keys():
		cfg[k] = custom_config[k]
	if custom_config.has("min_drawers") and not custom_config.has("min_containers"):
		cfg["min_containers"] = custom_config["min_drawers"]
	if custom_config.has("max_drawers") and not custom_config.has("max_containers"):
		cfg["max_containers"] = custom_config["max_drawers"]
	if custom_config.has("min_containers") and not custom_config.has("min_drawers"):
		cfg["min_drawers"] = custom_config["min_containers"]
	if custom_config.has("max_containers") and not custom_config.has("max_drawers"):
		cfg["max_drawers"] = custom_config["max_containers"]
	return cfg


func generate_spawn_manifest(match_seed: int, custom_config: Dictionary = {}) -> Dictionary:
	var resolved_seed: int = match_seed if match_seed != 0 else 7321
	var rng := RandomNumberGenerator.new()
	rng.seed = resolved_seed

	var cfg: Dictionary = _resolve_config(custom_config)

	var min_containers: int = maxi(int(cfg.get("min_containers", cfg.get("min_drawers", 24))), DEFAULT_OBJECTIVES.size() + 1)
	var max_containers: int = maxi(int(cfg.get("max_containers", cfg.get("max_drawers", min_containers))), min_containers)
	var target_containers: int = rng.randi_range(min_containers, max_containers)
	var max_per_room: int = clampi(int(cfg.get("max_drawers_per_room", 2)), 1, 8)
	var allow_spawn_rooms: bool = bool(cfg.get("allow_drawers_in_spawn_rooms", true))
	var max_in_spawn_room: int = clampi(int(cfg.get("max_drawers_in_spawn_room", 1)), 0, max_per_room)
	var isolate_briefcase: bool = bool(cfg.get("isolate_briefcase_from_objectives", true))
	var cover_count: int = maxi(int(cfg.get("cover_props_count", 6)), 0)

	var b_min: int = maxi(int(cfg.get("floor_buckets_min", 3)), 0)
	var b_max: int = maxi(int(cfg.get("floor_buckets_max", b_min)), b_min)
	var bucket_count: int = rng.randi_range(b_min, b_max)

	var pb_min: int = maxi(int(cfg.get("prearmed_buckets_min", 1)), 0)
	var pb_max: int = maxi(int(cfg.get("prearmed_buckets_max", pb_min)), pb_min)
	var prearmed_buckets_count: int = rng.randi_range(pb_min, pb_max)

	var ps_min: int = maxi(int(cfg.get("prearmed_springs_min", 1)), 0)
	var ps_max: int = maxi(int(cfg.get("prearmed_springs_max", ps_min)), ps_min)
	var prearmed_springs_count: int = rng.randi_range(ps_min, ps_max)

	var pbm_min: int = maxi(int(cfg.get("prearmed_bombs_min", 1)), 0)
	var pbm_max: int = maxi(int(cfg.get("prearmed_bombs_max", pbm_min)), pbm_min)
	var prearmed_bombs_count: int = rng.randi_range(pbm_min, pbm_max)

	var exclude_spawn_room_doors: bool = bool(cfg.get("exclude_spawn_room_doors_from_buckets", true))
	var enable_upper_floor: bool = bool(cfg.get("enable_upper_floor", int(cfg.get("active_preset_players", 2)) > 2))
	var starting_prearmed_traps: int = prearmed_buckets_count + prearmed_springs_count + prearmed_bombs_count

	var ft_min: int = maxi(int(cfg.get("floor_traps_min", 2)), 0)
	var ft_max: int = maxi(int(cfg.get("floor_traps_max", ft_min)), ft_min)
	var floor_traps_count: int = rng.randi_range(ft_min, ft_max)
	var floor_trap_counts: Dictionary = {
		"SPRING": 0,
		"BOMB": 0,
		"TRIPWIRE": 0,
		"DART_GUN": 0
	}
	var floor_trap_items: Array[String] = []
	for _ft_i in range(floor_traps_count):
		var trap_id: String = DEFAULT_GADGETS[rng.randi_range(0, DEFAULT_GADGETS.size() - 1)]
		floor_trap_items.append(trap_id)
		floor_trap_counts[trap_id] = int(floor_trap_counts.get(trap_id, 0)) + 1

	# 1. Core mandatory container items (4 Objectives + 1 Briefcase = 5 items)
	var container_loot: Array[Array] = []
	for obj_id in DEFAULT_OBJECTIVES:
		container_loot.append([obj_id])
	container_loot.append(["BRIEFCASE"])

	var remaining_container_capacity: int = maxi(target_containers - container_loot.size(), 0)

	# 2. Build gadget pool using per-gadget [min..max] and total gadget [min..max]
	var gadget_specs: Array[Dictionary] = [
		{"id": "SPRING", "min": maxi(int(cfg.get("spring_min", 1)), 0), "max": maxi(int(cfg.get("spring_max", 2)), 0)},
		{"id": "BOMB", "min": maxi(int(cfg.get("bomb_min", 1)), 0), "max": maxi(int(cfg.get("bomb_max", 2)), 0)},
		{"id": "TRIPWIRE", "min": maxi(int(cfg.get("tripwire_min", 1)), 0), "max": maxi(int(cfg.get("tripwire_max", 2)), 0)},
		{"id": "DART_GUN", "min": maxi(int(cfg.get("dart_gun_min", 1)), 0), "max": maxi(int(cfg.get("dart_gun_max", 2)), 0)}
	]

	var min_total_gadgets: int = clampi(int(cfg.get("min_total_gadgets", 4)), 0, remaining_container_capacity)
	var max_total_gadgets: int = clampi(maxi(int(cfg.get("max_total_gadgets", 6)), min_total_gadgets), min_total_gadgets, remaining_container_capacity)
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
		if selected_gadgets.size() >= max_total_gadgets or selected_gadgets.size() >= remaining_container_capacity:
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
		if selected_gadgets.size() >= target_total_gadgets or selected_gadgets.size() >= remaining_container_capacity:
			break
		selected_gadgets.append(g_id)
		gadget_counts[g_id] = int(gadget_counts.get(g_id, 0)) + 1

	for g_id in selected_gadgets:
		container_loot.append([g_id])

	while container_loot.size() < target_containers:
		container_loot.append([] as Array[String])

	_shuffle_array(container_loot, rng)

	var slot_roles: Array[String] = []
	for i in range(target_containers):
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
		"target_containers": target_containers,
		"drawer_count": target_containers,
		"max_drawers_per_room": max_per_room,
		"allow_drawers_in_spawn_rooms": allow_spawn_rooms,
		"max_drawers_in_spawn_room": max_in_spawn_room,
		"isolate_briefcase_from_objectives": isolate_briefcase,
		"cover_count": cover_count,
		"floor_buckets_count": bucket_count,
		"floor_traps_count": floor_traps_count,
		"floor_trap_items": floor_trap_items,
		"floor_trap_counts": floor_trap_counts,
		"total_gadgets_count": selected_gadgets.size(),
		"gadget_counts": gadget_counts,
		"starting_prearmed_traps": starting_prearmed_traps,
		"prearmed_buckets_count": prearmed_buckets_count,
		"prearmed_springs_count": prearmed_springs_count,
		"prearmed_bombs_count": prearmed_bombs_count,
		"exclude_spawn_room_doors_from_buckets": exclude_spawn_room_doors,
		"enable_upper_floor": enable_upper_floor,
		"container_loot_slots": container_loot,
		"drawer_loot_slots": container_loot,
		"slot_roles": slot_roles,
		"bucket_rolls": bucket_indices,
		"config": cfg
	}


func _is_small_only_marker(marker: Marker3D) -> bool:
	return String(marker.name).begins_with("SmallDrawerSpawn") or str(marker.get_meta("drawer_size", "")) == "small"


func _min_marker_spacing(is_big_a: bool, is_big_b: bool) -> float:
	if is_big_a and is_big_b:
		return 2.85
	if is_big_a or is_big_b:
		return 1.85
	return 1.15


func _to_typed_items(entry: Array) -> Array[String]:
	var typed: Array[String] = []
	for item in entry:
		typed.append(str(item))
	return typed


func populate_level(
	level_root: Node,
	match_seed: int,
	drawer_scene: PackedScene = null,
	pickup_scene: PackedScene = null,
	skip_rooms: Array[String] = [],
	custom_config: Dictionary = {},
	small_drawer_scene: PackedScene = null
) -> Dictionary:
	var manifest: Dictionary = generate_spawn_manifest(match_seed, custom_config)
	if level_root == null:
		return {
			"seed": int(manifest["seed"]),
			"drawers_spawned": 0,
			"containers_spawned": 0,
			"big_drawers_spawned": 0,
			"small_drawers_spawned": 0,
			"floor_buckets_spawned": 0,
			"buckets_per_room": {},
			"floor_traps_spawned": 0,
			"floor_traps_per_room": {},
			"floor_trap_counts": {},
			"prearmed_buckets_spawned": 0,
			"prearmed_springs_spawned": 0,
			"prearmed_bombs_spawned": 0,
			"starting_prearmed_traps": 0,
			"excluded_spawn_doors_count": 0,
			"eligible_doors_count": 0,
			"prearmed_traps_per_room": {},
			"prearmed_door_buckets_list": [],
			"drawers_per_room": {},
			"containers_per_room": {},
			"manifest": manifest
		}

	var building := _get_building(level_root)
	var include_upper_floor: bool = bool(manifest.get("enable_upper_floor", true))
	if not include_upper_floor and building != null and not Engine.is_editor_hint():
		var upper_floor_node := building.get_node_or_null("SecondFloor")
		if upper_floor_node != null:
			building.remove_child(upper_floor_node)
			upper_floor_node.queue_free()

	var f_spawner: Node = building.get_node_or_null("FurnitureSpawner") if building != null else null
	var spawn_room_keys: Array[String] = SPAWN_ROOM_NAMES.duplicate()
	if building != null and building.name == &"BuildingComplex3":
		var discovered_spawns := _discover_building_spawn_room_keys(building, include_upper_floor)
		if not discovered_spawns.is_empty():
			spawn_room_keys = discovered_spawns
		else:
			var grid_size: Vector2i = building.get_meta("grid_size")
			spawn_room_keys = [
				"Room_1_1",
				"Room_%d_%d" % [grid_size.y, grid_size.x],
				"Room_1_%d" % grid_size.x,
				"Room_%d_1" % grid_size.y
			]

	for room in _collect_sorted_rooms(level_root, [], include_upper_floor):
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
	var resolved_small_drawer_scene: PackedScene = small_drawer_scene if small_drawer_scene != null else DEFAULT_SMALL_DRAWER_SCENE
	var resolved_pickup_scene: PackedScene = pickup_scene if pickup_scene != null else DEFAULT_PICKUP_SCENE

	var effective_skip_rooms: Array[String] = skip_rooms.duplicate()
	var allow_spawn_rooms: bool = bool(manifest.get("allow_drawers_in_spawn_rooms", true))
	var max_in_spawn_room: int = int(manifest.get("max_drawers_in_spawn_room", 1))
	if not allow_spawn_rooms or max_in_spawn_room <= 0:
		for sp_room in spawn_room_keys:
			if not (sp_room in effective_skip_rooms):
				effective_skip_rooms.append(sp_room)

	var rooms: Array[Node3D] = _collect_sorted_rooms(level_root, effective_skip_rooms, include_upper_floor)
	var max_per_room: int = maxi(int(manifest.get("max_drawers_per_room", 2)), 1)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(manifest["seed"]) ^ 0x5A17

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

	var container_loot: Array = (manifest["container_loot_slots"] as Array).duplicate(true)
	var target_containers: int = container_loot.size()
	var selected_placements: Array[Dictionary] = []
	var room_placements: Dictionary = {} # room_name -> Array[Dictionary]
	var drawers_per_room: Dictionary = {}
	var containers_per_room: Dictionary = {}
	var containers_allocated: int = 0

	# Round-robin pass across shuffled rooms up to max_per_room props per room:
	# Pass 0 prioritizes contested non-spawn rooms, then spawn rooms up to max_in_spawn_room.
	for pass_idx in range(max_per_room):
		if containers_allocated >= target_containers:
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
			if containers_allocated >= target_containers:
				break
			var r_cap: int = max_in_spawn_room if (r_name in spawn_room_keys) else max_per_room
			if int(drawers_per_room.get(r_name, 0)) >= r_cap:
				continue
			var remaining: int = target_containers - containers_allocated
			var r_pool: Array = room_marker_pools[r_name]
			var already_picked: Array = room_placements.get(r_name, [])
			var chosen_marker: Marker3D = null
			var chosen_is_big: bool = false
			for candidate in r_pool:
				var m_cand := candidate as Marker3D
				var try_sizes: Array[bool] = []
				if _is_small_only_marker(m_cand) or remaining < 2:
					try_sizes = [false]
				elif rng.randf() < 0.65:
					try_sizes = [true, false]
				else:
					try_sizes = [false]
				for cand_is_big in try_sizes:
					var fits: bool = true
					for prev_entry in already_picked:
						var prev_dict: Dictionary = prev_entry as Dictionary
						var prev_m: Marker3D = prev_dict["marker"] as Marker3D
						var min_dist: float = _min_marker_spacing(cand_is_big, bool(prev_dict["is_big"]))
						if m_cand.position.distance_to(prev_m.position) < min_dist:
							fits = false
							break
					if fits:
						chosen_marker = m_cand
						chosen_is_big = cand_is_big
						break
				if chosen_marker != null:
					break
			if chosen_marker != null:
				r_pool.erase(chosen_marker)
				var cap: int = 2 if chosen_is_big else 1
				var placement: Dictionary = {
					"marker": chosen_marker,
					"room": r_name,
					"is_big": chosen_is_big,
					"capacity": cap
				}
				already_picked.append(placement)
				room_placements[r_name] = already_picked
				selected_placements.append(placement)
				drawers_per_room[r_name] = int(drawers_per_room.get(r_name, 0)) + 1
				containers_per_room[r_name] = int(containers_per_room.get(r_name, 0)) + cap
				containers_allocated += cap

	# Post-pass top-up: if still short of target_containers, upgrade eligible small placements on big-capable markers
	if containers_allocated < target_containers:
		for placement in selected_placements:
			if containers_allocated >= target_containers:
				break
			if bool(placement["is_big"]):
				continue
			var m_up: Marker3D = placement["marker"] as Marker3D
			if _is_small_only_marker(m_up):
				continue
			var r_up: String = str(placement["room"])
			var can_upgrade: bool = true
			for sib_entry in (room_placements.get(r_up, []) as Array):
				var sib: Dictionary = sib_entry as Dictionary
				if sib["marker"] == m_up:
					continue
				if m_up.position.distance_to((sib["marker"] as Marker3D).position) < _min_marker_spacing(true, bool(sib["is_big"])):
					can_upgrade = false
					break
			if can_upgrade:
				placement["is_big"] = true
				placement["capacity"] = 2
				containers_per_room[r_up] = int(containers_per_room.get(r_up, 0)) + 1
				containers_allocated += 1

	_shuffle_array(selected_placements, rng)

	var slot_rooms: Array[String] = []
	for p in selected_placements:
		var r_slot: String = str(p["room"])
		slot_rooms.append(r_slot)
		if bool(p["is_big"]):
			slot_rooms.append(r_slot)

	var used_container_count: int = mini(container_loot.size(), slot_rooms.size())

	# Enforce Briefcase isolation across every container slot (never in the same room as an Objective).
	if bool(manifest.get("isolate_briefcase_from_objectives", true)) and used_container_count > 1:
		_enforce_briefcase_isolated_from_objectives(container_loot, slot_rooms, used_container_count)

	# Pre-arm random Spring & Bomb traps across spawned container slots
	var prearmed_spring_slots: Dictionary = {}
	var prearmed_bomb_slots: Dictionary = {}
	var prearmed_traps_per_room: Dictionary = {}
	var target_prearmed_springs: int = mini(int(manifest.get("prearmed_springs_count", 0)), used_container_count)
	var target_prearmed_bombs: int = mini(int(manifest.get("prearmed_bombs_count", 0)), used_container_count)
	if used_container_count > 0 and (target_prearmed_springs > 0 or target_prearmed_bombs > 0):
		var slot_indices: Array[int] = []
		for s_i in range(used_container_count):
			slot_indices.append(s_i)
		_shuffle_array(slot_indices, rng)
		var cursor_idx: int = 0
		for _s_k in range(target_prearmed_springs):
			var chosen_s: int = slot_indices[cursor_idx % slot_indices.size()]
			prearmed_spring_slots[chosen_s] = true
			cursor_idx += 1
		for _b_k in range(target_prearmed_bombs):
			var chosen_b: int = slot_indices[cursor_idx % slot_indices.size()]
			prearmed_bomb_slots[chosen_b] = true
			cursor_idx += 1

	var drawers_spawned: int = 0
	var big_drawers_spawned: int = 0
	var small_drawers_spawned: int = 0
	var containers_spawned: int = 0
	var prearmed_springs_spawned: int = 0
	var prearmed_bombs_spawned: int = 0
	var slot_cursor: int = 0

	for i in range(selected_placements.size()):
		if slot_cursor >= used_container_count:
			break
		var placement: Dictionary = selected_placements[i]
		var marker: Marker3D = placement["marker"] as Marker3D
		var r_placement: String = str(placement["room"])
		var is_big: bool = bool(placement["is_big"])
		marker.set_meta("occupied_by_match_drawer", true)
		for old_child in marker.get_children():
			marker.remove_child(old_child)
			old_child.queue_free()

		var drawer: Node
		var prop_seed: int = int(manifest["seed"]) + i * 31
		if is_big:
			drawer = resolved_drawer_scene.instantiate()
			drawer.name = "MatchDrawer_%02d" % i
			var left_items: Array[String] = _to_typed_items(container_loot[slot_cursor] as Array)
			var left_spring: bool = bool(prearmed_spring_slots.get(slot_cursor, false))
			var left_bomb: bool = bool(prearmed_bomb_slots.get(slot_cursor, false))
			slot_cursor += 1
			drawer.set("container_id", "Left Drawer")
			drawer.set("stored_items", left_items)
			drawer.set("armed_spring", left_spring)
			drawer.set("spring_owner_peer_id", 0)
			drawer.set("armed_bomb", left_bomb)
			drawer.set("bomb_owner_peer_id", 0)
			drawer.set("container_seed", prop_seed)
			if left_spring:
				prearmed_springs_spawned += 1
				prearmed_traps_per_room[r_placement] = int(prearmed_traps_per_room.get(r_placement, 0)) + 1
			if left_bomb:
				prearmed_bombs_spawned += 1
				prearmed_traps_per_room[r_placement] = int(prearmed_traps_per_room.get(r_placement, 0)) + 1
			var right_drawer: Node = drawer.get_node_or_null("RightUpperDrawer")
			if right_drawer != null:
				var has_right_slot: bool = slot_cursor < used_container_count
				var right_items: Array[String] = _to_typed_items(container_loot[slot_cursor] as Array) if has_right_slot else ([] as Array[String])
				var right_spring: bool = bool(prearmed_spring_slots.get(slot_cursor, false)) if has_right_slot else false
				var right_bomb: bool = bool(prearmed_bomb_slots.get(slot_cursor, false)) if has_right_slot else false
				if has_right_slot:
					slot_cursor += 1
				right_drawer.set("container_id", "Right Drawer")
				right_drawer.set("stored_items", right_items)
				right_drawer.set("armed_spring", right_spring)
				right_drawer.set("spring_owner_peer_id", 0)
				right_drawer.set("armed_bomb", right_bomb)
				right_drawer.set("bomb_owner_peer_id", 0)
				right_drawer.set("container_seed", prop_seed + 17)
				if right_spring:
					prearmed_springs_spawned += 1
					prearmed_traps_per_room[r_placement] = int(prearmed_traps_per_room.get(r_placement, 0)) + 1
				if right_bomb:
					prearmed_bombs_spawned += 1
					prearmed_traps_per_room[r_placement] = int(prearmed_traps_per_room.get(r_placement, 0)) + 1
				containers_spawned += 2
			else:
				containers_spawned += 1
			big_drawers_spawned += 1
		else:
			drawer = resolved_small_drawer_scene.instantiate()
			drawer.name = "MatchDrawer_%02d" % i
			var mid_items: Array[String] = _to_typed_items(container_loot[slot_cursor] as Array)
			var mid_spring: bool = bool(prearmed_spring_slots.get(slot_cursor, false))
			var mid_bomb: bool = bool(prearmed_bomb_slots.get(slot_cursor, false))
			slot_cursor += 1
			drawer.set("container_id", "Middle Drawer")
			drawer.set("stored_items", mid_items)
			drawer.set("armed_spring", mid_spring)
			drawer.set("spring_owner_peer_id", 0)
			drawer.set("armed_bomb", mid_bomb)
			drawer.set("bomb_owner_peer_id", 0)
			drawer.set("container_seed", prop_seed)
			if mid_spring:
				prearmed_springs_spawned += 1
				prearmed_traps_per_room[r_placement] = int(prearmed_traps_per_room.get(r_placement, 0)) + 1
			if mid_bomb:
				prearmed_bombs_spawned += 1
				prearmed_traps_per_room[r_placement] = int(prearmed_traps_per_room.get(r_placement, 0)) + 1
			small_drawers_spawned += 1
			containers_spawned += 1

		spawn_root.add_child(drawer)
		if drawer is Node3D and marker.is_inside_tree():
			(drawer as Node3D).global_transform = _compute_inward_facing_drawer_transform(marker)
		drawers_spawned += 1

	manifest["container_loot_slots"] = container_loot
	manifest["drawer_loot_slots"] = container_loot

	if f_spawner != null:
		if f_spawner.has_method("reset_and_populate") and not Engine.is_editor_hint():
			f_spawner.call("reset_and_populate", int(manifest["seed"]))
		else:
			f_spawner.set("layout_seed", int(manifest["seed"]))

	var bucket_rooms: Array[Node3D] = _collect_sorted_rooms(level_root, skip_rooms, include_upper_floor)
	var buckets_spawned: int = 0
	var buckets_per_room: Dictionary = {}
	var floor_traps_spawned: int = 0
	var floor_traps_per_room: Dictionary = {}
	var floor_trap_counts_spawned: Dictionary = {
		"SPRING": 0,
		"BOMB": 0,
		"TRIPWIRE": 0,
		"DART_GUN": 0
	}
	if not bucket_rooms.is_empty():
		var bucket_target: int = int(manifest["floor_buckets_count"])
		var floor_trap_items: Array = manifest.get("floor_trap_items", []) as Array
		var surface_items: Array[String] = []
		for _b_i in range(bucket_target):
			surface_items.append("BUCKET")
		for t_item in floor_trap_items:
			surface_items.append(str(t_item))

		var shuffled_rooms: Array[Node3D] = bucket_rooms.duplicate()
		_shuffle_array(shuffled_rooms, rng)
		var room_bucket_pools: Dictionary = {} # room_key -> Array[Marker3D]
		for r_node in shuffled_rooms:
			var r_k: String = _room_key(r_node)
			var b_markers: Array[Marker3D] = _get_bucket_markers(r_node)
			_shuffle_array(b_markers, rng)
			room_bucket_pools[r_k] = b_markers

		var room_cursor: int = 0
		var trap_idx: int = 0
		for item_idx in range(surface_items.size()):
			var spawn_item_id: String = surface_items[item_idx]
			var target_room: Node3D = shuffled_rooms[room_cursor % shuffled_rooms.size()]
			var r_k: String = _room_key(target_room)
			var b_pool: Array = room_bucket_pools.get(r_k, [])
			if b_pool.is_empty():
				for probe_offset in range(1, shuffled_rooms.size()):
					var probe_room: Node3D = shuffled_rooms[(room_cursor + probe_offset) % shuffled_rooms.size()]
					var probe_key: String = _room_key(probe_room)
					var probe_pool: Array = room_bucket_pools.get(probe_key, [])
					if not probe_pool.is_empty():
						target_room = probe_room
						r_k = probe_key
						b_pool = probe_pool
						break
			room_cursor += 1
			var chosen_marker: Marker3D = null
			if not b_pool.is_empty():
				chosen_marker = b_pool.pop_front() as Marker3D

			var surface_pickup: Node = resolved_pickup_scene.instantiate()
			if spawn_item_id == "BUCKET":
				surface_pickup.name = "MatchFloorBucket_%d" % buckets_spawned
			else:
				surface_pickup.name = "MatchFloorTrap_%d" % trap_idx
				trap_idx += 1
			surface_pickup.set("item_id", spawn_item_id)
			spawn_root.add_child(surface_pickup)
			if surface_pickup is Node3D:
				if chosen_marker != null:
					if chosen_marker.is_inside_tree():
						(surface_pickup as Node3D).global_transform = chosen_marker.global_transform
					else:
						var floor_offset: Vector3 = Vector3.ZERO
						var f_node: Node = target_room.get_parent().get_parent()
						if f_node is Node3D and f_node.name == &"SecondFloor":
							floor_offset = (f_node as Node3D).position
						(surface_pickup as Node3D).position = floor_offset + target_room.position + chosen_marker.position
				else:
					var jitter := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
					var base_pos: Vector3 = target_room.global_position if target_room.is_inside_tree() else target_room.position
					(surface_pickup as Node3D).global_position = Vector3(base_pos.x + jitter.x, maxf(base_pos.y, 0.0), base_pos.z + jitter.z)

			if spawn_item_id == "BUCKET":
				buckets_per_room[r_k] = int(buckets_per_room.get(r_k, 0)) + 1
				buckets_spawned += 1
			else:
				floor_traps_per_room[r_k] = int(floor_traps_per_room.get(r_k, 0)) + 1
				floor_trap_counts_spawned[spawn_item_id] = int(floor_trap_counts_spawned.get(spawn_item_id, 0)) + 1
				floor_traps_spawned += 1

	# Pre-arm random Water Bucket traps on doors (excluding first doors from player spawn rooms)
	var prearmed_buckets_spawned: int = 0
	var excluded_spawn_doors_count: int = 0
	var eligible_doors_count: int = 0
	var prearmed_door_buckets_list: Array[String] = []
	if building != null:
		var ladder_layout: Node = building.get_node_or_null("LadderLayout")
		if ladder_layout != null and ladder_layout.has_method("_build_layout") and not bool(ladder_layout.get("_layout_built")):
			ladder_layout.call("_build_layout", int(manifest["seed"]))

		var exclude_spawn_doors: bool = bool(manifest.get("exclude_spawn_room_doors_from_buckets", true))
		var eligible_doors: Array[Dictionary] = []
		var door_floors: Array[Dictionary] = [
			{"path": "Doors", "upper": false, "prefix": "Ground/"}
		]
		if include_upper_floor:
			door_floors.append({"path": "SecondFloor/Doors", "upper": true, "prefix": "Upper/"})
		for floor_info in door_floors:
			var doors_root: Node = building.get_node_or_null(str(floor_info["path"]))
			if doors_root == null:
				continue
			var is_upper: bool = bool(floor_info["upper"])
			var f_prefix: String = str(floor_info["prefix"])
			var door_children: Array[Node3D] = []
			for dc in doors_root.get_children():
				if dc is Node3D and dc.has_method("set_prearmed_water_bucket"):
					door_children.append(dc as Node3D)
			door_children.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
			for door_node in door_children:
				door_node.call("set_prearmed_water_bucket", false, 1.0)
				if exclude_spawn_doors and _is_door_touching_spawn_room(door_node, is_upper, building, spawn_room_keys):
					excluded_spawn_doors_count += 1
					continue
				eligible_doors.append({"door": door_node, "label": f_prefix + String(door_node.name)})

		eligible_doors_count = eligible_doors.size()
		_shuffle_array(eligible_doors, rng)
		var target_prearmed_buckets: int = mini(int(manifest.get("prearmed_buckets_count", 0)), eligible_doors.size())
		for d_i in range(target_prearmed_buckets):
			var d_rec: Dictionary = eligible_doors[d_i] as Dictionary
			var d_node: Node3D = d_rec["door"] as Node3D
			var side_sign: float = 1.0 if rng.randf() < 0.5 else -1.0
			d_node.call("set_prearmed_water_bucket", true, side_sign)
			prearmed_buckets_spawned += 1
			prearmed_door_buckets_list.append(str(d_rec["label"]))

	var total_prearmed_spawned: int = prearmed_buckets_spawned + prearmed_springs_spawned + prearmed_bombs_spawned

	return {
		"seed": int(manifest["seed"]),
		"drawers_spawned": drawers_spawned,
		"containers_spawned": containers_spawned,
		"big_drawers_spawned": big_drawers_spawned,
		"small_drawers_spawned": small_drawers_spawned,
		"floor_buckets_spawned": buckets_spawned,
		"buckets_per_room": buckets_per_room,
		"floor_traps_spawned": floor_traps_spawned,
		"floor_traps_per_room": floor_traps_per_room,
		"floor_trap_counts": floor_trap_counts_spawned,
		"prearmed_buckets_spawned": prearmed_buckets_spawned,
		"prearmed_springs_spawned": prearmed_springs_spawned,
		"prearmed_bombs_spawned": prearmed_bombs_spawned,
		"starting_prearmed_traps": total_prearmed_spawned,
		"excluded_spawn_doors_count": excluded_spawn_doors_count,
		"eligible_doors_count": eligible_doors_count,
		"prearmed_traps_per_room": prearmed_traps_per_room,
		"prearmed_door_buckets_list": prearmed_door_buckets_list,
		"drawers_per_room": drawers_per_room,
		"containers_per_room": containers_per_room,
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


func _discover_building_spawn_room_keys(building: Node, include_upper_floor: bool = true) -> Array[String]:
	var result: Array[String] = []
	if building == null:
		return result
	var room_paths: Array[String] = ["Rooms"]
	if include_upper_floor:
		room_paths.append("SecondFloor/Rooms")
	for room_path in room_paths:
		var room_root := building.get_node_or_null(room_path)
		if room_root == null:
			continue
		for child in room_root.get_children():
			if not (child is Node3D):
				continue
			var pts := child.get_node_or_null("MatchPlayerSpawnPoints")
			if pts == null:
				continue
			var has_marker := false
			for m in pts.get_children():
				if m is Marker3D:
					has_marker = true
					break
			if has_marker:
				result.append(_room_key(child as Node3D))
	return result


func _get_door_connected_room_keys(door: Node3D, is_upper_floor: bool) -> Array[String]:
	var connected: Array[String] = []
	var d_name: String = String(door.name)
	var parts: PackedStringArray = d_name.split("_")
	if parts.size() >= 3 and parts[1].is_valid_int() and parts[2].is_valid_int():
		var boundary: int = parts[1].to_int()
		var idx: int = parts[2].to_int()
		var floor_prefix: String = "SecondFloor/" if is_upper_floor else ""
		if parts[0] == "Vertical":
			connected.append("%sRoom_%d_%d" % [floor_prefix, idx + 1, boundary])
			connected.append("%sRoom_%d_%d" % [floor_prefix, idx + 1, boundary + 1])
		elif parts[0] == "Horizontal":
			connected.append("%sRoom_%d_%d" % [floor_prefix, boundary, idx + 1])
			connected.append("%sRoom_%d_%d" % [floor_prefix, boundary + 1, idx + 1])
	return connected


func _is_door_touching_spawn_room(door: Node3D, is_upper_floor: bool, building: Node, spawn_room_keys: Array[String]) -> bool:
	for r_key in _get_door_connected_room_keys(door, is_upper_floor):
		if r_key in spawn_room_keys:
			return true

	# Geometric fallback against 9x9m spawn room boundaries
	var room_path: String = "SecondFloor/Rooms" if is_upper_floor else "Rooms"
	var room_root: Node = building.get_node_or_null(room_path)
	if room_root == null:
		return false
	var door_pos: Vector3 = door.position
	for child in room_root.get_children():
		if not (child is Node3D):
			continue
		var r_node := child as Node3D
		if not (_room_key(r_node) in spawn_room_keys):
			continue
		var dx: float = absf(door_pos.x - r_node.position.x)
		var dz: float = absf(door_pos.z - r_node.position.z)
		if dx <= 4.65 and dz <= 4.65:
			return true
	return false


func _get_drawer_markers(room: Node3D) -> Node:
	var dedicated := room.get_node_or_null("MatchDrawerSpawnPoints")
	return dedicated if dedicated != null else room.get_node_or_null("FurnitureSpawnPoints")


func _get_bucket_markers(room: Node3D) -> Array[Marker3D]:
	var result: Array[Marker3D] = []
	var dedicated := room.get_node_or_null("MatchBucketSpawnPoints")
	if dedicated == null:
		return result
	for child in dedicated.get_children():
		if child is Marker3D:
			result.append(child as Marker3D)
	result.sort_custom(func(a: Marker3D, b: Marker3D) -> bool: return String(a.name) < String(b.name))
	return result


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
