@tool
class_name SearchableContainer
extends StaticBody3D

## Unified Searchable Container for Desk Drawers, Filing Cabinets & Dropped Briefcases (Doc 3 §3 & §4).
## Enforces single-user lock, +10s first-visit bonus, Tap-E vs Hold-E asymmetric trap triggers,
## draggable clutter persistence, and Top-Down Container View RPC synchronization.

signal state_changed()
signal slide_progressed()

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const BRIEFCASE_BUILDER = preload("res://entities/props/briefcase_visual_builder.gd")
const DRAWER_CONTENTS_MASK: int = 32
const DRAWER_CLOSED_Z: float = 0.08
const DRAWER_OPEN_Z: float = 0.56
const SPRING_TRIGGER_VISUAL_RATIO: float = 0.49
const DRAWER_EASE_EXPONENT: float = 4.5
const DRAWER_BOMB_BOTTOM_Y: float = -0.034
const DRAWER_STORED_ITEMS_START_Y: float = -0.006
const DRAWER_ITEM_SLOT_STEP_Y: float = 0.024
const DRAWER_CLUTTER_START_Y: float = 0.066
const DRAWER_LIP_SPRING_BOTTOM_Y: float = 0.150
const CLUTTER_START_Y: float = -0.002
const CLUTTER_STEP_Y: float = 0.012
const DEFAULT_CLUTTER_POSITIONS: Array[Vector2] = [
	Vector2(0.34, 0.40), # Layer 1: Manila Folder / Mail
	Vector2(0.62, 0.42), # Layer 1: Ledger / Book
	Vector2(0.38, 0.66), # Layer 2: Paper
	Vector2(0.64, 0.66), # Layer 2: Book
	Vector2(0.48, 0.50), # Layer 3: Misc
	Vector2(0.52, 0.36)  # Layer 3: Misc
]
const ITEM_TRAY_POSITIONS: Array[Vector2] = [
	Vector2(0.32, 0.38),
	Vector2(0.62, 0.40),
	Vector2(0.36, 0.68),
	Vector2(0.64, 0.68)
]
const CLUTTER_PROP_SPECS: Array[Dictionary] = [
	{"id": "misc_fags", "scene": preload("res://Assets/Models/Prefabs/misc_fags.tscn"), "size": Vector3(0.15, 0.010, 0.10), "wide": false},
	{"id": "misc_mail", "scene": preload("res://Assets/Models/Prefabs/misc_mail.tscn"), "size": Vector3(0.21, 0.007, 0.15), "wide": true},
	{"id": "misc_money", "scene": preload("res://Assets/Models/Prefabs/misc_money.tscn"), "size": Vector3(0.19, 0.008, 0.11), "wide": false},
	{"id": "misc_paper", "scene": preload("res://Assets/Models/Prefabs/misc_paper.tscn"), "size": Vector3(0.25, 0.006, 0.19), "wide": true},
	{"id": "misc_phone", "scene": preload("res://Assets/Models/Prefabs/misc_phone.tscn"), "size": Vector3(0.17, 0.010, 0.11), "wide": false},
	{"id": "frede_book", "scene": preload("res://Assets/Models/Prefabs/FredeBook.tscn"), "size": Vector3(0.24, 0.010, 0.17), "wide": true},
	{"id": "noah_book", "scene": preload("res://Assets/Models/Prefabs/NoahBook.tscn"), "size": Vector3(0.24, 0.010, 0.17), "wide": true},
	{"id": "nete_book", "scene": preload("res://Assets/Models/Prefabs/NeteBook.tscn"), "size": Vector3(0.24, 0.010, 0.17), "wide": true},
	{"id": "alex_book", "scene": preload("res://Assets/Models/Prefabs/AlexBook.tscn"), "size": Vector3(0.24, 0.010, 0.17), "wide": true}
]

@export var container_id: String = "Drawer"
@export var container_seed: int = 0
@export var is_briefcase_container: bool = false
@export var use_custom_tray_mesh: bool = false
@export var drawer_closed_z: float = DRAWER_CLOSED_Z
@export var drawer_open_z: float = DRAWER_OPEN_Z
@export var tray_local_center_xz: Vector2 = Vector2.ZERO
@export var tray_local_half_extents: Vector2 = Vector2(0.33, 0.17)
@export var min_pick_local_z: float = 0.34
@export var lip_spring_local_pos: Vector3 = Vector3(0.0, 0.055, 0.19)
@export var clutter_count: int = 6
@export var max_clutter_layers_override: int = 0
@export var clutter_scale_multiplier: float = 1.0
@export var stored_items: Array[String] = []
@export var armed_spring: bool = false
@export var spring_owner_peer_id: int = 0
@export var armed_bomb: bool = false
@export var bomb_owner_peer_id: int = 0

var spring_unlatched: bool = false
var staged_spring_on_lip: bool = false
var staged_bomb_in_tray: bool = false
var live_bomb_lit: bool = false
var live_bomb_fuse_remaining: float = 0.0
var occupied_by_peer_id: int = 0
var searched_by_peers: Dictionary = {} # peer_id -> bool
var clutter_positions: Array[Vector2] = []
var item_positions: Dictionary = {} # String item_id -> Vector2 norm [0.08..0.92]
var bomb_norm_pos: Vector2 = BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
var linked_briefcase_pickup: Node = null

var _occupant_player_override: Node = null
var _tray_drawer_node: Node3D = null
var _top_down_vantage: Marker3D = null
var _slide_tween: Tween = null
var _tray_target_z: float = DRAWER_CLOSED_Z
var _opened_effects_applied: bool = false
var is_slow_opening: bool = false
var _slow_open_peer_id: int = 0
var drawer_open_progress: float = 0.0
var drawer_visual_ratio: float = 0.0
var _hollow_built: bool = false
var _contents_root: Node3D = null
var _clutter_area_nodes: Dictionary = {}
var _briefcase_lid_pivot: Node3D = null
var _briefcase_interior_light: OmniLight3D = null
var _lid_tween: Tween = null
var _clutter_yaws: Array[float] = []
var _clutter_spec_indices: Array[int] = []
var _item_yaws: Dictionary = {} # String item_id -> float degrees
var _item_layer_slots: Dictionary = {} # String item_id -> int fixed Y slot
var _bomb_yaw: float = 0.0
var _layout_randomized: bool = false
var _has_player_modified_layout: bool = false
var _is_focused_closed: bool = false


func _ready() -> void:
	if not is_briefcase_container:
		collision_layer = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3
	else:
		collision_layer = 0
	collision_mask = 0
	_tray_target_z = 0.0 if is_briefcase_container else drawer_closed_z
	if not is_briefcase_container:
		if clutter_positions.is_empty() and not _layout_randomized:
			_randomize_initial_drawer_layout()
		else:
			_init_clutter_if_empty()
	else:
		_init_clutter_if_empty()
	_ensure_item_positions()
	_tray_drawer_node = get_node_or_null("TrayPivot") as Node3D
	_top_down_vantage = get_node_or_null("TopDownVantage") as Marker3D
	if not Engine.is_editor_hint():
		if MatchManager != null and not is_briefcase_container and not MatchManager.match_started.is_connected(_on_match_started_reseed):
			MatchManager.match_started.connect(_on_match_started_reseed)
		_ensure_3d_tray_structure()
		_rebuild_3d_interior()
		if _tray_drawer_node != null and not is_briefcase_container:
			_tray_drawer_node.position.z = lerpf(drawer_closed_z, drawer_open_z, drawer_visual_ratio)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if is_slow_opening:
		_step_committed_slow_open(delta)
	if not live_bomb_lit:
		return
	if _is_peer_connected() and not multiplayer.is_server():
		live_bomb_fuse_remaining = maxf(live_bomb_fuse_remaining - delta, 0.0)
		state_changed.emit()
		return

	live_bomb_fuse_remaining -= delta
	if live_bomb_fuse_remaining <= 0.0:
		_detonate_container_bomb()
	else:
		state_changed.emit()


static func evaluate_slow_open_curve(progress: float, steepness: float = DRAWER_EASE_EXPONENT) -> float:
	var t: float = clampf(progress, 0.0, 1.0)
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var k: float = maxf(steepness, 0.01)
	var denom: float = maxf(pow(2.0, k) - 1.0, 0.0001)
	return clampf((pow(2.0, k * t) - 1.0) / denom, 0.0, 1.0)


func _get_slow_open_exp_steepness() -> float:
	if GameConfig != null:
		var v: Variant = GameConfig.get("drawer_slow_open_exp_steepness")
		if v is float or v is int:
			return maxf(float(v), 0.1)
	return DRAWER_EASE_EXPONENT


func _eval_slow_open_ratio(progress: float) -> float:
	return evaluate_slow_open_curve(progress, _get_slow_open_exp_steepness())


func _get_drawer_mesh_scale() -> float:
	if GameConfig != null:
		var v: Variant = GameConfig.get("drawer_interior_mesh_scale")
		if v is float or v is int:
			return maxf(float(v), 0.1)
	return 1.10


func _get_effective_clutter_scale() -> float:
	return _get_drawer_mesh_scale() * maxf(clutter_scale_multiplier, 0.25)


func _get_max_clutter_layers() -> int:
	if max_clutter_layers_override > 0:
		return max_clutter_layers_override
	if GameConfig != null:
		var v: Variant = GameConfig.get("drawer_max_clutter_layers")
		if v is int or v is float:
			return maxi(int(v), 0)
	return 3


func _get_effective_clutter_count() -> int:
	if is_briefcase_container:
		return 0
	return maxi(clutter_count, 0)


func _stable_hash(text: String) -> int:
	var h: int = 17
	for b in text.to_utf8_buffer():
		h = int((h * 31 + int(b)) & 0x7FFFFFFF)
	return h if h != 0 else 1


func _compute_layout_seed(override_match_seed: int = 0) -> int:
	if container_seed != 0:
		return container_seed
	var m_seed: int = override_match_seed if override_match_seed != 0 else (MatchManager.match_seed if MatchManager != null else 0)
	var name_hash: int = _stable_hash(String(name) + "|" + container_id)
	var combined: int = ((m_seed ^ name_hash) if m_seed != 0 else (name_hash ^ 0x5A17)) & 0x7FFFFFFF
	return combined if combined != 0 else 7321


func _on_match_started_reseed(seed_value: int) -> void:
	if is_briefcase_container or container_seed != 0 or _has_player_modified_layout:
		return
	if occupied_by_peer_id != 0 or not searched_by_peers.is_empty():
		return
	_randomize_initial_drawer_layout(seed_value)
	_ensure_item_positions()
	_rebuild_3d_interior()
	state_changed.emit()


func _pick_spaced_norm(rng: RandomNumberGenerator, existing: Array[Vector2], min_x: float, max_x: float, min_y: float, max_y: float, min_dist: float, attempts: int) -> Vector2:
	var best := Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_y, max_y))
	var best_min_d: float = -1.0
	for _a in range(attempts):
		var cand := Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_y, max_y))
		var nearest: float = 999.0
		for prev in existing:
			nearest = minf(nearest, cand.distance_to(prev))
		if nearest >= min_dist:
			return cand
		if nearest > best_min_d:
			best_min_d = nearest
			best = cand
	return best


func _shuffle_int_array(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _generate_clutter_spec_indices(target_count: int, rng: RandomNumberGenerator) -> Array[int]:
	var result: Array[int] = []
	var catalog_size: int = CLUTTER_PROP_SPECS.size()
	if catalog_size <= 0 or target_count <= 0:
		return result
	var pool: Array[int] = []
	while result.size() < target_count:
		if pool.is_empty():
			for s_i in range(catalog_size):
				pool.append(s_i)
			_shuffle_int_array(pool, rng)
		result.append(int(pool.pop_back()))
	return result


func _randomize_initial_drawer_layout(override_match_seed: int = 0) -> void:
	if is_briefcase_container:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _compute_layout_seed(override_match_seed)

	# 1. Place important items & drawer traps FIRST on distinct bottom layers with full 360 Y rotation
	item_positions.clear()
	_item_yaws.clear()
	var placed_items: Array[Vector2] = []
	for i in range(stored_items.size()):
		var item_id: String = str(stored_items[i]).to_upper()
		var item_yaw: float = rng.randf_range(0.0, 360.0)
		_item_yaws[item_id] = item_yaw
		var item_pos: Vector2 = _pick_spaced_norm(rng, placed_items, 0.20, 0.80, 0.24, 0.76, 0.26, 10)
		var clamped_item_pos: Vector2 = clamp_item_norm_to_tray_walls(item_pos, "loot_item", -1, item_id)
		item_positions[item_id] = clamped_item_pos
		placed_items.append(clamped_item_pos)

	_bomb_yaw = rng.randf_range(0.0, 360.0)
	var raw_bomb_pos: Vector2 = _pick_spaced_norm(rng, placed_items, 0.20, 0.80, 0.24, 0.76, 0.24, 8)
	bomb_norm_pos = clamp_item_norm_to_tray_walls(raw_bomb_pos, "planted_bomb")

	var important_targets: Array[Vector2] = placed_items.duplicate()
	if armed_bomb or staged_bomb_in_tray or live_bomb_lit:
		important_targets.append(bomb_norm_pos)

	# 2. Spread randomized junk clutter across the tray on distinct compact Y layers,
	#    with full 0..360 deg Y rotation and zero wall clipping.
	var target_count: int = _get_effective_clutter_count()
	clutter_positions.clear()
	_clutter_yaws.clear()
	_clutter_spec_indices = _generate_clutter_spec_indices(target_count, rng)
	for i in range(target_count):
		clutter_positions.append(Vector2(-1.0, -1.0))
		_clutter_yaws.append(rng.randf_range(0.0, 360.0))

	var wide_slots: Array[int] = []
	var narrow_slots: Array[int] = []
	for i in range(target_count):
		var spec_idx: int = _clutter_spec_indices[i]
		if bool(CLUTTER_PROP_SPECS[spec_idx].get("wide", true)):
			wide_slots.append(i)
		else:
			narrow_slots.append(i)
	_shuffle_int_array(wide_slots, rng)
	_shuffle_int_array(narrow_slots, rng)

	var available_slots: Array[int] = []
	available_slots.append_array(wide_slots)
	available_slots.append_array(narrow_slots)

	# Build stratified grid zones across the tray so junk is distributed evenly instead of piling up
	var cols: int = 2 if target_count <= 4 else 3
	var rows: int = maxi(int(ceilf(float(maxi(target_count, 1)) / float(cols))), 2)
	var zones: Array[Vector2] = []
	for r_i in range(rows):
		for c_i in range(cols):
			zones.append(Vector2(
				lerpf(0.18, 0.82, (float(c_i) + 0.5) / float(cols)),
				lerpf(0.22, 0.78, (float(r_i) + 0.5) / float(rows))
			))
	for z_i in range(zones.size() - 1, 0, -1):
		var z_swap: int = rng.randi_range(0, z_i)
		var tmp_z: Vector2 = zones[z_i]
		zones[z_i] = zones[z_swap]
		zones[z_swap] = tmp_z

	var placed_clutter: Array[Vector2] = []

	# Pass 1: Cover each objective / trap with at most 1 wide clutter piece
	for t_idx in range(important_targets.size()):
		if available_slots.is_empty():
			break
		var slot_i: int = int(available_slots[0])
		available_slots.remove_at(0)
		var off := Vector2(rng.randf_range(-0.045, 0.045), rng.randf_range(-0.055, 0.055))
		var cover_pos: Vector2 = clamp_item_norm_to_tray_walls(important_targets[t_idx] + off, "clutter", slot_i)
		clutter_positions[slot_i] = cover_pos
		placed_clutter.append(cover_pos)
		if zones.size() > available_slots.size():
			var closest_zone: int = -1
			var closest_d: float = INF
			for z_i in range(zones.size()):
				var d_z: float = cover_pos.distance_squared_to(zones[z_i])
				if d_z < closest_d:
					closest_d = d_z
					closest_zone = z_i
			if closest_zone >= 0:
				zones.remove_at(closest_zone)

	# Pass 2: Distribute remaining junk across open tray zones & maximize pairwise separation
	var z_cursor: int = 0
	for remaining_slot in available_slots:
		var slot_r: int = int(remaining_slot)
		var picked := Vector2.ZERO
		if z_cursor < zones.size():
			var z_center: Vector2 = zones[z_cursor]
			picked = _pick_spaced_norm(
				rng,
				placed_clutter,
				clampf(z_center.x - 0.08, 0.14, 0.86),
				clampf(z_center.x + 0.08, 0.14, 0.86),
				clampf(z_center.y - 0.08, 0.16, 0.84),
				clampf(z_center.y + 0.08, 0.16, 0.84),
				0.26,
				6
			)
			var nearest_existing: float = INF
			for prev_p in placed_clutter:
				nearest_existing = minf(nearest_existing, picked.distance_to(prev_p))
			if nearest_existing < 0.24:
				picked = _pick_spaced_norm(rng, placed_clutter, 0.14, 0.86, 0.16, 0.84, 0.30, 14)
		else:
			picked = _pick_spaced_norm(rng, placed_clutter, 0.14, 0.86, 0.16, 0.84, 0.30, 14)
		z_cursor += 1
		var clamped_r: Vector2 = clamp_item_norm_to_tray_walls(picked, "clutter", slot_r)
		clutter_positions[slot_r] = clamped_r
		placed_clutter.append(clamped_r)

	_layout_randomized = true


func _init_clutter_if_empty() -> void:
	var target_count: int = _get_effective_clutter_count()
	if not is_briefcase_container and clutter_positions.is_empty() and not _layout_randomized and target_count > 0:
		_randomize_initial_drawer_layout()
		return
	if clutter_positions.size() == target_count:
		if not is_briefcase_container and _clutter_spec_indices.size() != target_count:
			var rng_specs := RandomNumberGenerator.new()
			rng_specs.seed = _compute_layout_seed() + 4099
			_clutter_spec_indices = _generate_clutter_spec_indices(target_count, rng_specs)
		if not is_briefcase_container and _clutter_yaws.size() < target_count:
			var rng_y := RandomNumberGenerator.new()
			rng_y.seed = _compute_layout_seed() + 8191
			while _clutter_yaws.size() < target_count:
				_clutter_yaws.append(rng_y.randf_range(0.0, 360.0))
		return
	if clutter_positions.size() > target_count:
		clutter_positions.resize(target_count)
		_clutter_yaws.resize(mini(_clutter_yaws.size(), target_count))
		_clutter_spec_indices.resize(mini(_clutter_spec_indices.size(), target_count))
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _compute_layout_seed() + clutter_positions.size() * 97 + 13
	if _clutter_spec_indices.size() < target_count:
		var generated: Array[int] = _generate_clutter_spec_indices(target_count, rng)
		for i in range(_clutter_spec_indices.size(), target_count):
			_clutter_spec_indices.append(generated[i])
	for i in range(clutter_positions.size(), target_count):
		_clutter_yaws.append(rng.randf_range(0.0, 360.0))
		var spread_pos: Vector2 = _pick_spaced_norm(rng, clutter_positions, 0.14, 0.86, 0.16, 0.84, 0.28, 12)
		clutter_positions.append(clamp_item_norm_to_tray_walls(spread_pos, "clutter", i))


func _sync_item_layer_slots() -> void:
	var present: Dictionary = {}
	for raw_id in stored_items:
		var upper: String = str(raw_id).to_upper()
		if not upper.is_empty():
			present[upper] = true
	var existing_keys: Array = _item_layer_slots.keys()
	for k in existing_keys:
		var key_str: String = str(k).to_upper()
		if not present.has(key_str):
			_item_layer_slots.erase(k)
	var used_slots: Dictionary = {}
	for v in _item_layer_slots.values():
		used_slots[int(v)] = true
	for raw_id in stored_items:
		var upper: String = str(raw_id).to_upper()
		if upper.is_empty() or _item_layer_slots.has(upper):
			continue
		var slot: int = 0
		while used_slots.has(slot):
			slot += 1
		_item_layer_slots[upper] = slot
		used_slots[slot] = true


func _ensure_item_positions() -> void:
	if not is_briefcase_container and not _layout_randomized and not stored_items.is_empty() and item_positions.is_empty():
		_randomize_initial_drawer_layout()
	var next_positions: Dictionary = {}
	var fallback_list: Array[Vector2] = BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS if is_briefcase_container else ITEM_TRAY_POSITIONS
	for i in range(stored_items.size()):
		var item_id: String = str(stored_items[i]).to_upper()
		if not is_briefcase_container and not _item_yaws.has(item_id):
			var yaw_rng := RandomNumberGenerator.new()
			yaw_rng.seed = (_compute_layout_seed() ^ _stable_hash(item_id)) & 0x7FFFFFFF
			_item_yaws[item_id] = yaw_rng.randf_range(0.0, 360.0)
		if item_positions.has(item_id) and item_positions[item_id] is Vector2:
			next_positions[item_id] = clamp_item_norm_to_tray_walls(item_positions[item_id] as Vector2, "loot_item", -1, item_id)
		else:
			next_positions[item_id] = clamp_item_norm_to_tray_walls(fallback_list[i % fallback_list.size()], "loot_item", -1, item_id)
	item_positions = next_positions


func get_interaction_prompt() -> String:
	if occupied_by_peer_id != 0:
		return "[IN USE]"
	if is_briefcase_container:
		return "[Hold E] Inspect Briefcase"
	if not container_id.is_empty() and container_id != "Drawer":
		return "[E] Look Inside %s" % container_id
	return "[E] Look Inside Drawer"


func get_hold_interaction_duration() -> float:
	return GameConfig.drawer_slow_peek_hold_time if GameConfig != null else 2.50


func get_top_down_camera_transform() -> Transform3D:
	if _top_down_vantage != null and is_inside_tree():
		return _top_down_vantage.global_transform
	var xform: Transform3D = global_transform if is_inside_tree() else transform
	var up_dir: Vector3 = -xform.basis.z
	up_dir.y = 0.0
	up_dir = Vector3.FORWARD if up_dir.length_squared() < 0.0001 else up_dir.normalized()
	if is_briefcase_container:
		var cam_h: float = float(GameConfig.get("briefcase_camera_height")) if (GameConfig != null and GameConfig.get("briefcase_camera_height") != null) else 0.88
		var cam_front: float = float(GameConfig.get("briefcase_camera_front_offset")) if (GameConfig != null and GameConfig.get("briefcase_camera_front_offset") != null) else 0.30
		var tgt_y: float = float(GameConfig.get("briefcase_camera_target_y")) if (GameConfig != null and GameConfig.get("briefcase_camera_target_y") != null) else 0.04
		var tgt_z: float = float(GameConfig.get("briefcase_camera_target_z")) if (GameConfig != null and GameConfig.get("briefcase_camera_target_z") != null) else -0.02
		var b_origin: Vector3 = xform * Vector3(0.0, cam_h, cam_front)
		var b_target: Vector3 = xform * Vector3(0.0, tgt_y, tgt_z)
		var look_dir: Vector3 = (b_target - b_origin).normalized()
		var cam_up: Vector3 = Vector3.UP if absf(look_dir.dot(Vector3.UP)) < 0.98 else up_dir
		return Transform3D(Basis.looking_at(look_dir, cam_up), b_origin)
	var origin: Vector3 = xform * Vector3(0.0, 1.42, 0.52)
	var look_target: Vector3 = xform * Vector3(0.0, 0.55, 0.52)
	return Transform3D(Basis.looking_at((look_target - origin).normalized(), up_dir), origin)


func request_focus_container(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_focus_container.rpc_id(1, caller_peer_id)
	else:
		focus_container(caller_peer_id)


func request_start_slow_open(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_start_slow_open.rpc_id(1, caller_peer_id)
	else:
		start_slow_open(caller_peer_id)


func request_begin_open(caller_peer_id: int) -> void:
	request_focus_container(caller_peer_id)


func request_interaction(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_open_container.rpc_id(1, caller_peer_id, false)
	else:
		open_container(caller_peer_id, false)


func request_hold_interaction(caller_peer_id: int) -> void:
	request_start_slow_open(caller_peer_id)


func request_close_container(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_close_container.rpc_id(1, caller_peer_id)
	else:
		close_container(caller_peer_id)


func request_move_clutter(caller_peer_id: int, clutter_idx: int, norm_pos: Vector2) -> void:
	if _is_peer_connected():
		_server_move_clutter.rpc_id(1, caller_peer_id, clutter_idx, norm_pos)
	else:
		move_clutter(caller_peer_id, clutter_idx, norm_pos)


func request_unlatch_spring(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_unlatch_spring.rpc_id(1, caller_peer_id)
	else:
		unlatch_spring(caller_peer_id)


func request_steal_spring(caller_peer_id: int, target_slot: int = -1) -> void:
	if _is_peer_connected():
		_server_steal_spring.rpc_id(1, caller_peer_id, target_slot)
	else:
		steal_unlatched_spring_to_jacket(caller_peer_id, target_slot)


func request_rearm_spring(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_rearm_spring.rpc_id(1, caller_peer_id)
	else:
		rearm_unlatched_spring_on_lip(caller_peer_id)


func request_loot_item(caller_peer_id: int, item_id: String, target_slot: int = -1, target_briefcase_norm: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected():
		_server_loot_item.rpc_id(1, caller_peer_id, item_id, target_slot, target_briefcase_norm)
	else:
		loot_item_to_player(caller_peer_id, item_id, target_slot, null, target_briefcase_norm)


func request_deposit_left_hand_item(caller_peer_id: int, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected():
		_server_deposit_left_hand_item.rpc_id(1, caller_peer_id, norm_pos)
	else:
		deposit_left_hand_item(caller_peer_id, null, norm_pos)


func request_deposit_briefcase_item(caller_peer_id: int, obj_id: String, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected():
		_server_deposit_briefcase_item.rpc_id(1, caller_peer_id, obj_id, norm_pos)
	else:
		deposit_briefcase_item(caller_peer_id, obj_id, null, norm_pos)


func request_deposit_jacket_item(caller_peer_id: int, slot_index: int, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected():
		_server_deposit_jacket_item.rpc_id(1, caller_peer_id, slot_index, norm_pos)
	else:
		deposit_jacket_item(caller_peer_id, slot_index, null, norm_pos)


func request_stash_jacket_item(caller_peer_id: int, slot_index: int, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	request_deposit_jacket_item(caller_peer_id, slot_index, norm_pos)


func request_move_stored_item(caller_peer_id: int, item_id: String, norm_pos: Vector2) -> void:
	if _is_peer_connected():
		_server_move_stored_item.rpc_id(1, caller_peer_id, item_id, norm_pos)
	else:
		move_stored_item(caller_peer_id, item_id, norm_pos)


func request_move_planted_bomb(caller_peer_id: int, norm_pos: Vector2) -> void:
	if _is_peer_connected():
		_server_move_planted_bomb.rpc_id(1, caller_peer_id, norm_pos)
	else:
		move_planted_bomb(caller_peer_id, norm_pos)


func request_plant_trap(caller_peer_id: int, slot_index: int, target_zone: String, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected():
		_server_plant_trap.rpc_id(1, caller_peer_id, slot_index, target_zone, norm_pos)
	else:
		plant_trap_from_jacket(caller_peer_id, slot_index, target_zone, null, norm_pos)


func request_grab_lit_bomb(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_grab_lit_bomb.rpc_id(1, caller_peer_id)
	else:
		grab_lit_bomb(caller_peer_id)


# ==========================================
# Core Authoritative Operations
# ==========================================

func focus_container(peer_id: int, player_override: Node = null) -> bool:
	_init_clutter_if_empty()
	_ensure_item_positions()
	if occupied_by_peer_id != 0 and occupied_by_peer_id != peer_id:
		return false

	var player: Node = player_override if player_override != null else _find_player_node(peer_id)
	var already_this_occupant: bool = (occupied_by_peer_id == peer_id)
	occupied_by_peer_id = peer_id
	_occupant_player_override = player_override

	if not already_this_occupant:
		# Both Drawers and Floor Briefcases start at Stage 1 Closed (0%) so player chooses Fast (Tap E) vs Slow (Hold E)
		_is_focused_closed = true
		is_slow_opening = false
		_slow_open_peer_id = 0
		drawer_open_progress = 0.0
		drawer_visual_ratio = 0.0
		_opened_effects_applied = false
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.kill()
		if _lid_tween != null and _lid_tween.is_valid():
			_lid_tween.kill()
		if _tray_drawer_node != null:
			_tray_drawer_node.position.z = 0.0 if is_briefcase_container else drawer_closed_z
			_tray_target_z = _tray_drawer_node.position.z
		if is_briefcase_container:
			_apply_briefcase_lid_ratio(0.0)

	_sync_state_to_peers()
	if player != null and player.has_method("enter_container_view"):
		player.enter_container_view(self)
	return true


func start_slow_open(peer_id: int, player_override: Node = null) -> bool:
	_init_clutter_if_empty()
	_ensure_item_positions()
	if occupied_by_peer_id != 0 and occupied_by_peer_id != peer_id:
		return false
	if is_slow_opening:
		return true
	if drawer_open_progress >= 0.999:
		return false

	occupied_by_peer_id = peer_id
	if player_override != null:
		_occupant_player_override = player_override
	_is_focused_closed = false
	is_slow_opening = true
	_slow_open_peer_id = peer_id
	drawer_open_progress = clampf(drawer_open_progress, 0.0, 1.0)
	drawer_visual_ratio = _eval_slow_open_ratio(drawer_open_progress)
	_apply_open_visual_ratio(drawer_visual_ratio)
	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if _ignite_armed_bombs_on_open(peer_id, player):
		_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()
	return true


func _step_committed_slow_open(delta: float) -> void:
	var slow_dur: float = GameConfig.drawer_slow_peek_hold_time if GameConfig != null else 2.50
	drawer_open_progress = clampf(drawer_open_progress + delta / maxf(slow_dur, 0.25), 0.0, 1.0)
	drawer_visual_ratio = _eval_slow_open_ratio(drawer_open_progress)
	_apply_open_visual_ratio(drawer_visual_ratio)

	if _is_peer_connected() and not multiplayer.is_server():
		slide_progressed.emit()
		return

	var target_peer: int = _slow_open_peer_id if _slow_open_peer_id != 0 else occupied_by_peer_id
	var player: Node = _occupant_player_override if _occupant_player_override != null else _find_player_node(target_peer)

	if armed_spring and drawer_visual_ratio >= SPRING_TRIGGER_VISUAL_RATIO:
		_trigger_spring_trap_ko(target_peer, player)
		return
	if (
		not is_briefcase_container
		and player != null
		and player.has_method("has_held_briefcase_armed_spring")
		and bool(player.has_held_briefcase_armed_spring())
		and drawer_visual_ratio >= SPRING_TRIGGER_VISUAL_RATIO
	):
		_trigger_held_briefcase_spring_from_drawer(target_peer, player)
		return

	if drawer_visual_ratio >= 0.45 and not _opened_effects_applied:
		_activate_opened_drawer_effects(target_peer, true, player)
		if drawer_open_progress < 0.999:
			_sync_state_to_peers()

	if drawer_open_progress >= 0.999:
		drawer_open_progress = 1.0
		drawer_visual_ratio = 1.0
		is_slow_opening = false
		_slow_open_peer_id = 0
		_apply_open_visual_ratio(1.0)
		_activate_opened_drawer_effects(target_peer, true, player)
		_sync_back_to_briefcase_pickup()
		_sync_state_to_peers()
	else:
		slide_progressed.emit()


func _ignite_armed_bombs_on_open(peer_id: int, player: Node = null) -> bool:
	var lit: bool = false
	if armed_bomb:
		armed_bomb = false
		live_bomb_lit = true
		var min_f: float = GameConfig.time_bomb_fuse_min if GameConfig != null else 2.5
		var max_f: float = GameConfig.time_bomb_fuse_max if GameConfig != null else 4.0
		live_bomb_fuse_remaining = randf_range(min_f, max_f)
		if AudioBridge != null:
			var fuse_rad: float = GameConfig.audio_radius_bomb_fuse if GameConfig != null else 10.0
			AudioBridge.request_world_cue("bomb_hiss", _safe_global_pos(), fuse_rad, bomb_owner_peer_id)
		lit = true

	# Simultaneous carried-Briefcase Time Bomb ignition when opening a Drawer while holding Briefcase
	var resolved_player: Node = player if player != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if not is_briefcase_container and resolved_player != null and resolved_player.has_method("has_held_briefcase_armed_bomb") and bool(resolved_player.has_held_briefcase_armed_bomb()):
		if resolved_player.has_method("ignite_held_briefcase_bomb"):
			resolved_player.ignite_held_briefcase_bomb(false)
			lit = true

	return lit


func _activate_opened_drawer_effects(peer_id: int, _is_slow_peek: bool, player: Node = null) -> Dictionary:
	var out: Dictionary = {"lit_bomb": false, "awarded_bonus": false}
	if _opened_effects_applied:
		return out
	_opened_effects_applied = true

	out["lit_bomb"] = _ignite_armed_bombs_on_open(peer_id, player)

	if not is_briefcase_container and not searched_by_peers.has(peer_id):
		searched_by_peers[peer_id] = true
		out["awarded_bonus"] = true
		if MatchManager != null:
			if MatchManager.match_state != MatchManager.MatchState.IN_PROGRESS:
				MatchManager.start_new_match([1, 2])
			MatchManager.award_first_search_bonus(peer_id)

	return out


func _trigger_held_briefcase_spring_from_drawer(_peer_id: int, player: Node) -> void:
	is_slow_opening = false
	_slow_open_peer_id = 0
	drawer_open_progress = 0.0
	drawer_visual_ratio = 0.0
	_opened_effects_applied = false
	occupied_by_peer_id = 0
	_occupant_player_override = null
	_animate_tray_open(false, false)
	_sync_state_to_peers()
	if player != null and player.has_method("trigger_held_briefcase_spring_ko"):
		player.trigger_held_briefcase_spring_ko()


func _trigger_spring_trap_ko(_peer_id: int, player: Node) -> void:
	is_slow_opening = false
	_slow_open_peer_id = 0
	armed_spring = false
	spring_unlatched = false
	var owner_id: int = spring_owner_peer_id
	spring_owner_peer_id = 0
	drawer_open_progress = 0.0
	drawer_visual_ratio = 0.0
	_opened_effects_applied = false
	if AudioBridge != null:
		AudioBridge.request_world_cue("spring_trigger", _safe_global_pos(), 10.0, owner_id)
	if player != null and player.has_method("apply_trap_ko"):
		var spring_dir: Vector3 = global_transform.basis.z.normalized() if is_inside_tree() else Vector3(0.0, 0.0, 1.0)
		var spring_kick: Vector3 = spring_dir * 13.5 + Vector3(0.0, 6.0, 0.0)
		player.apply_trap_ko("SPRING", owner_id, spring_kick)
	elif player != null and player.has_method("force_drop_all_hands"):
		player.force_drop_all_hands()
	occupied_by_peer_id = 0
	_occupant_player_override = null
	_animate_tray_open(false, false)
	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()


func open_container(peer_id: int, is_slow_peek: bool, player_override: Node = null) -> Dictionary:
	_init_clutter_if_empty()
	_ensure_item_positions()
	var result: Dictionary = {
		"opened": false,
		"reason": "",
		"triggered_spring": false,
		"lit_bomb": false,
		"awarded_bonus": false
	}

	if occupied_by_peer_id != 0 and occupied_by_peer_id != peer_id:
		result["reason"] = "IN_USE"
		return result
	if is_slow_opening:
		result["reason"] = "SLOW_OPENING"
		return result

	var player: Node = player_override if player_override != null else _find_player_node(peer_id)

	if not is_slow_peek and not _opened_effects_applied and AudioBridge != null:
		var slam_rad: float = GameConfig.audio_radius_drawer_fast if GameConfig != null else 10.0
		AudioBridge.request_world_cue("drawer_slam", _safe_global_pos(), slam_rad, peer_id)

	var held_briefcase_spring: bool = (
		not is_briefcase_container
		and player != null
		and player.has_method("has_held_briefcase_armed_spring")
		and bool(player.has_held_briefcase_armed_spring())
	)

	# 1. Armed Spring Check (Both Drawers AND Briefcases, plus Simultaneous Held Briefcase on Drawers!)
	# Slow Open commits cleanly from 0% -> 100% without tripping armed Springs.
	if armed_spring:
		if not is_slow_peek:
			_trigger_spring_trap_ko(peer_id, player)
			result["reason"] = "SPRING_KO"
			result["triggered_spring"] = true
			return result
		spring_unlatched = false
	elif held_briefcase_spring and not is_slow_peek:
		_trigger_held_briefcase_spring_from_drawer(peer_id, player)
		result["reason"] = "SPRING_KO"
		result["triggered_spring"] = true
		return result

	drawer_open_progress = 1.0
	drawer_visual_ratio = 1.0
	_is_focused_closed = false

	# 2 & 3. Armed Bomb Ignition + First-Visit Exploration Bonus (+10s)
	var eff: Dictionary = _activate_opened_drawer_effects(peer_id, is_slow_peek, player)
	result["lit_bomb"] = bool(eff["lit_bomb"])
	result["awarded_bonus"] = bool(eff["awarded_bonus"])

	occupied_by_peer_id = peer_id
	_occupant_player_override = player_override
	_animate_tray_to_ratio(drawer_visual_ratio, is_slow_peek)
	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()

	if player != null and player.has_method("enter_container_view"):
		player.enter_container_view(self)

	result["opened"] = true
	result["reason"] = "OK"
	return result


func close_container(peer_id: int, player_override: Node = null, force: bool = false) -> void:
	if occupied_by_peer_id != 0 and occupied_by_peer_id != peer_id:
		return
	if is_slow_opening and not force:
		return

	is_slow_opening = false
	_slow_open_peer_id = 0
	_opened_effects_applied = false
	_is_focused_closed = false
	drawer_open_progress = 0.0
	drawer_visual_ratio = 0.0
	if staged_spring_on_lip:
		staged_spring_on_lip = false
		armed_spring = true
	if staged_bomb_in_tray:
		staged_bomb_in_tray = false
		armed_bomb = true

	var prev_occupant: int = occupied_by_peer_id if occupied_by_peer_id != 0 else peer_id
	occupied_by_peer_id = 0
	var cached_player: Node = player_override if player_override != null else _occupant_player_override
	_occupant_player_override = null

	var player: Node = cached_player if cached_player != null else _find_player_node(prev_occupant)
	if not is_briefcase_container and player != null and player.has_method("commit_held_briefcase_traps"):
		player.commit_held_briefcase_traps()

	if not live_bomb_lit:
		_animate_tray_open(false, false)

	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()

	if player != null and player.has_method("exit_container_view"):
		player.exit_container_view()


func _get_item_rotated_half_extents(role: String, clutter_idx: int = -1, item_id: String = "") -> Vector2:
	var half_x: float = 0.08
	var half_z: float = 0.06
	var yaw: float = 0.0
	var area: Node3D = null
	if role == "clutter":
		area = _clutter_area_nodes.get(clutter_idx, null) as Node3D
	elif role == "loot_item":
		area = get_content_area_node("loot_item", item_id)
	elif role == "planted_bomb" or role == "lit_bomb":
		area = get_content_area_node("planted_bomb")
	if area != null and is_instance_valid(area):
		var aabb_val: Variant = area.get_meta("exact_aabb", null)
		if aabb_val is AABB:
			var aabb: AABB = aabb_val as AABB
			half_x = maxf(aabb.size.x * 0.5, 0.015)
			half_z = maxf(aabb.size.z * 0.5, 0.015)
		yaw = area.rotation.y
	else:
		if role == "clutter" and clutter_idx >= 0:
			var spec_idx: int = _clutter_spec_indices[clutter_idx] if clutter_idx < _clutter_spec_indices.size() else (clutter_idx % CLUTTER_PROP_SPECS.size())
			var sz: Vector3 = (CLUTTER_PROP_SPECS[spec_idx]["size"] as Vector3) * _get_effective_clutter_scale()
			half_x = maxf(sz.x * 0.5, 0.015)
			half_z = maxf(sz.z * 0.5, 0.015)
			if clutter_idx < _clutter_yaws.size():
				yaw = deg_to_rad(_clutter_yaws[clutter_idx])
		elif role == "loot_item" and item_id != "":
			var layout: Dictionary = _get_stored_item_tray_layout(item_id, is_briefcase_container)
			var sz: Vector3 = layout["size"] as Vector3
			half_x = maxf(sz.x * 0.5, 0.015)
			half_z = maxf(sz.z * 0.5, 0.015)
			yaw = deg_to_rad(float(_item_yaws.get(item_id.to_upper(), 0.0)))
		elif role == "planted_bomb" or role == "lit_bomb":
			half_x = 0.09
			half_z = 0.12
			yaw = deg_to_rad(_bomb_yaw)
	var ca: float = absf(cos(yaw))
	var sa: float = absf(sin(yaw))
	return Vector2(half_x * ca + half_z * sa, half_x * sa + half_z * ca)


func clamp_item_norm_to_tray_walls(norm_pos: Vector2, role: String, clutter_idx: int = -1, item_id: String = "") -> Vector2:
	if is_briefcase_container:
		return _clamp_container_norm(norm_pos)
	var local_xz: Vector2 = norm_to_tray_local_xz(Vector2(clampf(norm_pos.x, 0.0, 1.0), clampf(norm_pos.y, 0.0, 1.0)))
	var rot_ext: Vector2 = _get_item_rotated_half_extents(role, clutter_idx, item_id)
	var tray_hx: float = maxf(tray_local_half_extents.x, 0.05)
	var tray_hz: float = maxf(tray_local_half_extents.y, 0.05)
	var wall_hx: float = tray_hx + 0.06
	var allow_hx: float = minf(tray_hx, maxf(wall_hx - rot_ext.x, 0.0))
	var front_wall_z: float = tray_local_center_xz.y + tray_hz + 0.025
	var back_wall_z: float = tray_local_center_xz.y - tray_hz - 0.06
	var min_z: float = maxf(tray_local_center_xz.y - tray_hz, back_wall_z + rot_ext.y)
	var max_z: float = minf(tray_local_center_xz.y + tray_hz, front_wall_z - rot_ext.y)
	if min_z > max_z:
		var mid_z: float = (min_z + max_z) * 0.5
		min_z = mid_z
		max_z = mid_z
	var clamped_x: float = clampf(local_xz.x, tray_local_center_xz.x - allow_hx, tray_local_center_xz.x + allow_hx)
	var clamped_z: float = clampf(local_xz.y, min_z, max_z)
	return tray_local_xz_to_norm(clamped_x, clamped_z)


func move_clutter(peer_id: int, clutter_idx: int, new_norm_pos: Vector2) -> bool:
	if occupied_by_peer_id != peer_id:
		return false
	_init_clutter_if_empty()
	if clutter_idx < 0 or clutter_idx >= clutter_positions.size():
		return false
	_has_player_modified_layout = true
	clutter_positions[clutter_idx] = clamp_item_norm_to_tray_walls(new_norm_pos, "clutter", clutter_idx)
	if AudioBridge != null:
		AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, peer_id)
	_sync_state_to_peers()
	return true


func unlatch_spring(peer_id: int) -> bool:
	if occupied_by_peer_id != peer_id or not armed_spring or spring_unlatched:
		return false
	armed_spring = false
	staged_spring_on_lip = false
	spring_unlatched = true
	if AudioBridge != null:
		AudioBridge.request_world_cue("spring_unlatch", _safe_global_pos(), 5.0, peer_id)
	_sync_state_to_peers()
	return true


func steal_unlatched_spring_to_jacket(peer_id: int, target_slot: int = -1, player_override: Node = null) -> bool:
	if occupied_by_peer_id != peer_id or not spring_unlatched:
		return false
	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if player == null:
		return false

	if not _give_item_to_player(player, "SPRING", target_slot):
		return false

	spring_unlatched = false
	spring_owner_peer_id = 0
	_sync_state_to_peers()
	return true


func rearm_unlatched_spring_on_lip(peer_id: int) -> bool:
	if occupied_by_peer_id != peer_id or not spring_unlatched:
		return false
	spring_unlatched = false
	staged_spring_on_lip = true
	spring_owner_peer_id = peer_id
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("trap_arm", _safe_global_pos(), GameConfig.audio_radius_trap_setup, peer_id)
	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()
	return true


func loot_item_to_player(
	peer_id: int,
	item_id: String,
	target_jacket_slot: int = -1,
	player_override: Node = null,
	target_briefcase_norm: Vector2 = Vector2(-1.0, -1.0)
) -> bool:
	if occupied_by_peer_id != peer_id:
		return false
	var upper: String = item_id.to_upper()
	var idx: int = stored_items.find(upper)
	if idx == -1:
		return false

	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if player == null:
		return false

	# Objective transfer rules: pack into held Briefcase, equip to empty Left Hand, or cleanly swap with held Objective
	if PICKUP_SCRIPT.is_objective_item(upper):
		var held_left: String = str(player.get("left_hand_item_id")).to_upper()
		if held_left == "BRIEFCASE":
			if player.has_method("server_pack_objective_into_briefcase"):
				if not bool(player.server_pack_objective_into_briefcase(upper, target_briefcase_norm)):
					return false
			elif not _give_item_to_player(player, upper, target_jacket_slot):
				return false
			stored_items.remove_at(idx)
			item_positions.erase(upper)
			_has_player_modified_layout = true
			_ensure_item_positions()
			_sync_back_to_briefcase_pickup()
			_sync_state_to_peers()
			return true
		elif PICKUP_SCRIPT.is_objective_item(held_left):
			if held_left == upper:
				return false
			if player.has_method("server_swap_left_hand_objective"):
				var prev_pos: Variant = item_positions.get(upper, null)
				var prev_obj: String = str(player.server_swap_left_hand_objective(upper))
				if prev_obj == "NONE":
					return false
				stored_items.remove_at(idx)
				item_positions.erase(upper)
				if not (prev_obj in stored_items):
					stored_items.append(prev_obj)
					if prev_pos is Vector2:
						item_positions[prev_obj] = prev_pos as Vector2
				_has_player_modified_layout = true
				_ensure_item_positions()
				_sync_back_to_briefcase_pickup()
				_sync_state_to_peers()
				return true

	if PICKUP_SCRIPT.is_gadget_item(upper):
		var raw_slots: Variant = player.get("jacket_slots")
		if raw_slots is Array:
			var slot_arr: Array = raw_slots as Array
			var empty_idx: int = -1
			for i in range(slot_arr.size()):
				var s_val: String = str(slot_arr[i]).to_upper()
				if s_val == "NONE" or s_val.is_empty():
					empty_idx = i
					break

			if empty_idx != -1:
				var dest_slot: int = empty_idx
				if target_jacket_slot >= 0 and target_jacket_slot < slot_arr.size():
					var target_val: String = str(slot_arr[target_jacket_slot]).to_upper()
					if target_val == "NONE" or target_val.is_empty():
						dest_slot = target_jacket_slot
				var next_slots: Array[String] = []
				for s in slot_arr:
					next_slots.append(str(s).to_upper())
				next_slots[dest_slot] = upper
				player.set("jacket_slots", next_slots)
				player.set("active_jacket_slot", dest_slot)
				player.set("right_hand_mode", 0)
				if player.has_method("cancel_tripwire_placement"):
					player.cancel_tripwire_placement()
				if player.has_method("_sync_inventory_state_to_peers"):
					player._sync_inventory_state_to_peers()
				stored_items.remove_at(idx)
				if not (upper in stored_items):
					item_positions.erase(upper)
				_has_player_modified_layout = true
				_ensure_item_positions()
				_sync_back_to_briefcase_pickup()
				_sync_state_to_peers()
				return true

			# All 3 Inner Jacket slots are occupied: swap directly between jacket slot and drawer (unless BUCKET)
			if is_briefcase_container:
				return false
			var swap_slot: int = -1
			if target_jacket_slot >= 0 and target_jacket_slot < slot_arr.size():
				swap_slot = target_jacket_slot
			else:
				var active_idx: int = clampi(int(player.get("active_jacket_slot")), 0, slot_arr.size() - 1)
				if str(slot_arr[active_idx]).to_upper() != "BUCKET":
					swap_slot = active_idx
				else:
					for i in range(slot_arr.size()):
						var cand: String = str(slot_arr[i]).to_upper()
						if cand != "BUCKET" and cand != "NONE" and not cand.is_empty():
							swap_slot = i
							break
			if swap_slot < 0 or swap_slot >= slot_arr.size():
				return false
			var existing: String = str(slot_arr[swap_slot]).to_upper()
			if existing == "BUCKET" or existing == "NONE" or existing.is_empty():
				return false

			var prev_pos: Variant = item_positions.get(upper, null)
			var next_swap_slots: Array[String] = []
			for s in slot_arr:
				next_swap_slots.append(str(s).to_upper())
			next_swap_slots[swap_slot] = upper
			player.set("jacket_slots", next_swap_slots)
			player.set("active_jacket_slot", swap_slot)
			player.set("right_hand_mode", 0)
			if player.has_method("cancel_tripwire_placement"):
				player.cancel_tripwire_placement()
			if player.has_method("_sync_inventory_state_to_peers"):
				player._sync_inventory_state_to_peers()

			stored_items[idx] = existing
			if not (upper in stored_items):
				item_positions.erase(upper)
			if prev_pos is Vector2:
				item_positions[existing] = _clamp_container_norm(prev_pos as Vector2)
			_has_player_modified_layout = true
			_ensure_item_positions()
			if AudioBridge != null:
				AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, peer_id)
			_sync_back_to_briefcase_pickup()
			_sync_state_to_peers()
			return true

	if not _give_item_to_player(player, upper, target_jacket_slot):
		return false

	stored_items.remove_at(idx)
	if not (upper in stored_items):
		item_positions.erase(upper)
	_has_player_modified_layout = true
	_ensure_item_positions()
	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()
	return true


func deposit_left_hand_item(peer_id: int, player_override: Node = null, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> bool:
	if occupied_by_peer_id != peer_id:
		return false
	if drawer_visual_ratio < 0.35:
		return false
	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if player == null:
		return false

	var held_left: String = str(player.get("left_hand_item_id")).to_upper()
	if not PICKUP_SCRIPT.is_objective_item(held_left):
		return false
	if is_briefcase_container:
		if (held_left in stored_items) or stored_items.size() >= 4:
			return false

	var taken: String = "NONE"
	if player.has_method("server_take_left_hand_objective"):
		taken = str(player.server_take_left_hand_objective())
	else:
		taken = held_left
		player.set("left_hand_item_id", "NONE")
		if player.has_method("_sync_inventory_state_to_peers"):
			player._sync_inventory_state_to_peers()

	if taken == "NONE":
		return false

	stored_items.append(taken)
	if norm_pos.x >= 0.0 and norm_pos.y >= 0.0:
		item_positions[taken] = _clamp_container_norm(norm_pos)
	_has_player_modified_layout = true
	_ensure_item_positions()
	if AudioBridge != null:
		AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, peer_id)
	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()
	return true


func deposit_briefcase_item(peer_id: int, obj_id: String, player_override: Node = null, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> bool:
	if occupied_by_peer_id != peer_id or is_briefcase_container:
		return false
	if drawer_visual_ratio < 0.35:
		return false
	var upper: String = obj_id.to_upper()
	if not PICKUP_SCRIPT.is_objective_item(upper):
		return false
	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if player == null:
		return false
	if not player.has_method("server_remove_objective_from_briefcase"):
		return false
	if not bool(player.server_remove_objective_from_briefcase(upper)):
		return false

	stored_items.append(upper)
	if norm_pos.x >= 0.0 and norm_pos.y >= 0.0:
		item_positions[upper] = _clamp_container_norm(norm_pos)
	_has_player_modified_layout = true
	_ensure_item_positions()
	if AudioBridge != null:
		AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, peer_id)
	_sync_state_to_peers()
	return true


func deposit_jacket_item(
	peer_id: int,
	slot_index: int,
	player_override: Node = null,
	norm_pos: Vector2 = Vector2(-1.0, -1.0)
) -> bool:
	if occupied_by_peer_id != peer_id or is_briefcase_container:
		return false
	if is_slow_opening or (_is_focused_closed and drawer_visual_ratio < 0.35):
		return false
	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if player == null:
		return false

	var slots: Variant = player.get("jacket_slots")
	if not (slots is Array) or slot_index < 0 or slot_index >= (slots as Array).size():
		return false

	var gadget_id: String = str((slots as Array)[slot_index]).to_upper()
	if gadget_id != "DART_GUN" and gadget_id != "TRIPWIRE":
		return false

	_consume_jacket_slot(player, slot_index)
	if gadget_id == "TRIPWIRE" and player.has_method("cancel_tripwire_placement"):
		player.cancel_tripwire_placement()

	stored_items.append(gadget_id)
	if norm_pos.x >= 0.0 and norm_pos.y >= 0.0:
		item_positions[gadget_id] = _clamp_container_norm(norm_pos)
	elif not item_positions.has(gadget_id):
		item_positions[gadget_id] = ITEM_TRAY_POSITIONS[(stored_items.size() - 1) % ITEM_TRAY_POSITIONS.size()]
	_has_player_modified_layout = true
	_ensure_item_positions()
	if AudioBridge != null:
		AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, peer_id)
	_sync_state_to_peers()
	return true


func stash_jacket_item(
	peer_id: int,
	slot_index: int,
	player_override: Node = null,
	norm_pos: Vector2 = Vector2(-1.0, -1.0)
) -> bool:
	return deposit_jacket_item(peer_id, slot_index, player_override, norm_pos)


func move_stored_item(peer_id: int, item_id: String, new_norm_pos: Vector2) -> bool:
	if occupied_by_peer_id != peer_id:
		return false
	var upper: String = item_id.to_upper()
	if not (upper in stored_items):
		return false
	item_positions[upper] = clamp_item_norm_to_tray_walls(new_norm_pos, "loot_item", -1, upper)
	_has_player_modified_layout = true
	_ensure_item_positions()
	if AudioBridge != null:
		AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, peer_id)
	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()
	return true


func move_planted_bomb(peer_id: int, new_norm_pos: Vector2) -> bool:
	if occupied_by_peer_id != peer_id:
		return false
	if not (staged_bomb_in_tray or armed_bomb or live_bomb_lit):
		return false
	bomb_norm_pos = clamp_item_norm_to_tray_walls(new_norm_pos, "planted_bomb")
	_has_player_modified_layout = true
	if AudioBridge != null:
		AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, peer_id)
	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()
	return true


func plant_trap_from_jacket(
	peer_id: int,
	slot_index: int,
	target_zone: String,
	player_override: Node = null,
	norm_pos: Vector2 = Vector2(-1.0, -1.0)
) -> bool:
	if occupied_by_peer_id != peer_id:
		return false
	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if player == null:
		return false

	var slots: Array = player.get("jacket_slots")
	if slot_index < 0 or slot_index >= slots.size():
		return false

	var trap_id: String = str(slots[slot_index]).to_upper()
	var zone: String = target_zone.to_upper()

	if trap_id == "SPRING" and (zone == "LIP" or zone == "TRAY") and not armed_spring and not staged_spring_on_lip and not spring_unlatched:
		_consume_jacket_slot(player, slot_index)
		staged_spring_on_lip = true
		spring_owner_peer_id = peer_id
		if AudioBridge != null and GameConfig != null:
			AudioBridge.request_world_cue("trap_arm", _safe_global_pos(), GameConfig.audio_radius_trap_setup, peer_id)
		_sync_back_to_briefcase_pickup()
		_sync_state_to_peers()
		return true

	if trap_id == "BOMB" and (zone == "TRAY" or zone == "LIP") and not armed_bomb and not staged_bomb_in_tray and not live_bomb_lit:
		_consume_jacket_slot(player, slot_index)
		staged_bomb_in_tray = true
		bomb_owner_peer_id = peer_id
		if norm_pos.x >= 0.0 and norm_pos.y >= 0.0:
			bomb_norm_pos = _clamp_container_norm(norm_pos)
		elif is_briefcase_container:
			bomb_norm_pos = BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
		_has_player_modified_layout = true
		if AudioBridge != null and GameConfig != null:
			AudioBridge.request_world_cue("trap_arm", _safe_global_pos(), GameConfig.audio_radius_trap_setup, peer_id)
		_sync_back_to_briefcase_pickup()
		_sync_state_to_peers()
		return true

	if (trap_id == "DART_GUN" or trap_id == "TRIPWIRE") and not is_briefcase_container and (zone == "TRAY" or zone == "STASH" or zone.is_empty()):
		return deposit_jacket_item(peer_id, slot_index, player, norm_pos)

	return false


func grab_lit_bomb(peer_id: int, player_override: Node = null) -> bool:
	if occupied_by_peer_id != peer_id or not live_bomb_lit:
		return false
	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if player == null:
		return false

	live_bomb_lit = false
	var remaining: float = live_bomb_fuse_remaining
	live_bomb_fuse_remaining = 0.0
	var owner_id: int = bomb_owner_peer_id

	close_container(peer_id, player, true)

	if player.has_method("server_pickup_world_item"):
		player.server_pickup_world_item("LIVE_BOMB", [], _safe_global_pos())
	elif player.has_method("pickup_item"):
		player.pickup_item("LIVE_BOMB")

	if player.has_method("set_live_bomb_timer"):
		player.set_live_bomb_timer(remaining, owner_id)

	return true


func _detonate_container_bomb() -> void:
	live_bomb_lit = false
	live_bomb_fuse_remaining = 0.0
	var owner_id: int = bomb_owner_peer_id
	bomb_owner_peer_id = 0

	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("bomb_explode", _safe_global_pos(), GameConfig.audio_radius_bomb_explosion, owner_id)

	var occ: int = occupied_by_peer_id
	if occ != 0:
		var occ_player: Node = _occupant_player_override if _occupant_player_override != null else _find_player_node(occ)
		close_container(occ, occ_player, true)

	var blast_radius: float = GameConfig.time_bomb_blast_radius if GameConfig != null else 5.0
	if is_inside_tree() and get_tree() != null:
		for p in get_tree().get_nodes_in_group("spy_players"):
			if p is Node3D and (p as Node3D).global_position.distance_to(global_position) <= blast_radius:
				if not _is_blast_occluded((p as Node3D).global_position):
					if p.has_method("apply_trap_ko"):
						p.apply_trap_ko("BOMB", owner_id)
					elif p.has_method("force_drop_all_hands"):
						p.force_drop_all_hands()

	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()


func _is_blast_occluded(target_pos: Vector3) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 0.8, 0.0),
		target_pos + Vector3(0.0, 0.8, 0.0),
		GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1,
		[get_rid()]
	)
	var hit: Dictionary = space.intersect_ray(query)
	return not hit.is_empty()


func _give_item_to_player(player: Node, item_id: String, target_jacket_slot: int) -> bool:
	var upper: String = item_id.to_upper()
	if target_jacket_slot >= 0 and target_jacket_slot < 3 and PICKUP_SCRIPT.is_gadget_item(upper):
		var slots: Array = player.get("jacket_slots")
		if slots is Array and target_jacket_slot < slots.size():
			var existing: String = str(slots[target_jacket_slot]).to_upper()
			if existing == "NONE":
				slots[target_jacket_slot] = upper
				player.set("jacket_slots", slots)
				player.set("active_jacket_slot", target_jacket_slot)
				player.set("right_hand_mode", 0)
				if player.has_method("_sync_inventory_state_to_peers"):
					player._sync_inventory_state_to_peers()
				return true

	if player.has_method("server_pickup_world_item"):
		return player.server_pickup_world_item(upper, [], _safe_global_pos())
	if player.has_method("pickup_item"):
		var res: Dictionary = player.pickup_item(upper)
		return bool(res.get("picked", false))
	return false


func _consume_jacket_slot(player: Node, slot_index: int) -> void:
	var slots: Variant = player.get("jacket_slots")
	if slots is Array and slot_index >= 0 and slot_index < (slots as Array).size():
		var next_slots: Array[String] = []
		for s in (slots as Array):
			next_slots.append(str(s).to_upper())
		next_slots[slot_index] = "NONE"
		player.set("jacket_slots", next_slots)
		if player.has_method("_sync_inventory_state_to_peers"):
			player._sync_inventory_state_to_peers()


func _sync_back_to_briefcase_pickup() -> void:
	if is_briefcase_container and linked_briefcase_pickup != null and is_instance_valid(linked_briefcase_pickup):
		var packed: Array[String] = []
		for item in stored_items:
			if PICKUP_SCRIPT.is_objective_item(item):
				packed.append(item)
		linked_briefcase_pickup.set("packed_objectives", packed)
		linked_briefcase_pickup.set("packed_item_positions", item_positions.duplicate())
		linked_briefcase_pickup.set("bomb_norm_pos", bomb_norm_pos)
		linked_briefcase_pickup.set("armed_spring", armed_spring or staged_spring_on_lip)
		linked_briefcase_pickup.set("spring_owner_peer_id", spring_owner_peer_id)
		linked_briefcase_pickup.set("armed_bomb", armed_bomb or staged_bomb_in_tray)
		linked_briefcase_pickup.set("bomb_owner_peer_id", bomb_owner_peer_id)


func _apply_briefcase_lid_ratio(ratio: float) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	BRIEFCASE_BUILDER.set_lid_open_ratio(_briefcase_lid_pivot, clamped, _briefcase_interior_light)
	if _contents_root != null and is_instance_valid(_contents_root):
		_contents_root.visible = (clamped > 0.03)


func _apply_open_visual_ratio(ratio: float) -> void:
	var clamped_ratio: float = clampf(ratio, 0.0, 1.0)
	if is_briefcase_container:
		if _lid_tween != null and _lid_tween.is_valid():
			_lid_tween.kill()
		_apply_briefcase_lid_ratio(clamped_ratio)
	else:
		_tray_target_z = lerpf(drawer_closed_z, drawer_open_z, clamped_ratio)
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.kill()
		if _tray_drawer_node != null:
			_tray_drawer_node.position.z = _tray_target_z


func _animate_tray_open(open_state: bool, slow: bool) -> void:
	_animate_tray_to_ratio(1.0 if open_state else 0.0, slow)


func _animate_tray_to_ratio(ratio: float, slow: bool) -> void:
	if _tray_drawer_node == null:
		return
	var clamped_ratio: float = clampf(ratio, 0.0, 1.0)

	var base_dur: float = 0.0
	if clamped_ratio > 0.01:
		base_dur = (GameConfig.drawer_slow_peek_hold_time if GameConfig != null else 2.50) if slow else (GameConfig.drawer_fast_slam_duration if GameConfig != null else 0.22)
	else:
		base_dur = GameConfig.drawer_close_duration if GameConfig != null else 0.30

	var trans_type: Tween.TransitionType = Tween.TRANS_EXPO if slow else Tween.TRANS_QUAD
	var ease_type: Tween.EaseType = Tween.EASE_IN if slow else Tween.EASE_OUT

	if is_briefcase_container:
		if _lid_tween != null and _lid_tween.is_valid():
			_lid_tween.kill()
		if _briefcase_lid_pivot != null and is_inside_tree() and base_dur > 0.01:
			var target_rot_x: float = deg_to_rad(BRIEFCASE_BUILDER.OPEN_LID_ANGLE_DEG * clamped_ratio)
			if _contents_root != null and clamped_ratio > 0.03:
				_contents_root.visible = true
			if _briefcase_interior_light != null:
				_briefcase_interior_light.visible = clamped_ratio > 0.04
			_lid_tween = create_tween()
			_lid_tween.tween_property(_briefcase_lid_pivot, "rotation:x", target_rot_x, base_dur).set_trans(trans_type).set_ease(ease_type)
			if clamped_ratio <= 0.03:
				_lid_tween.tween_callback(func():
					_apply_briefcase_lid_ratio(0.0)
				)
		else:
			_apply_briefcase_lid_ratio(clamped_ratio)
		return

	var target_z: float = lerpf(drawer_closed_z, drawer_open_z, clamped_ratio)
	var current_z: float = _tray_drawer_node.position.z
	if slow and is_equal_approx(_tray_target_z, target_z) and _slide_tween != null and _slide_tween.is_valid() and _slide_tween.is_running():
		return

	var travel: float = maxf(absf(drawer_open_z - drawer_closed_z), 0.01)
	var frac: float = clampf(absf(target_z - current_z) / travel, 0.12, 1.0)
	var dur: float = base_dur * frac
	_tray_target_z = target_z

	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if is_inside_tree() and dur > 0.01 and not is_equal_approx(current_z, target_z):
		_slide_tween = create_tween()
		_slide_tween.tween_property(_tray_drawer_node, "position:z", target_z, dur).set_trans(trans_type).set_ease(ease_type)
	else:
		_tray_drawer_node.position.z = target_z


# ==========================================
# RPC Bridge & State Synchronization
# ==========================================

@rpc("any_peer", "call_local", "reliable")
func _server_focus_container(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	focus_container(caller_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _server_start_slow_open(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	start_slow_open(caller_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _server_open_container(caller_peer_id: int, is_slow_peek: bool) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	open_container(caller_peer_id, is_slow_peek)


@rpc("any_peer", "call_local", "reliable")
func _server_close_container(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	close_container(caller_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _server_move_clutter(caller_peer_id: int, clutter_idx: int, norm_pos: Vector2) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	move_clutter(caller_peer_id, clutter_idx, norm_pos)


@rpc("any_peer", "call_local", "reliable")
func _server_unlatch_spring(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	unlatch_spring(caller_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _server_steal_spring(caller_peer_id: int, target_slot: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	steal_unlatched_spring_to_jacket(caller_peer_id, target_slot)


@rpc("any_peer", "call_local", "reliable")
func _server_rearm_spring(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	rearm_unlatched_spring_on_lip(caller_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _server_loot_item(caller_peer_id: int, item_id: String, target_slot: int, target_briefcase_norm: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender != 0:
		caller_peer_id = sender
	loot_item_to_player(caller_peer_id, item_id, target_slot, null, target_briefcase_norm)


@rpc("any_peer", "call_local", "reliable")
func _server_deposit_left_hand_item(caller_peer_id: int, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender != 0:
		caller_peer_id = sender
	deposit_left_hand_item(caller_peer_id, null, norm_pos)


@rpc("any_peer", "call_local", "reliable")
func _server_deposit_briefcase_item(caller_peer_id: int, obj_id: String, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender != 0:
		caller_peer_id = sender
	deposit_briefcase_item(caller_peer_id, obj_id, null, norm_pos)


@rpc("any_peer", "call_local", "reliable")
func _server_deposit_jacket_item(caller_peer_id: int, slot_index: int, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender != 0:
		caller_peer_id = sender
	deposit_jacket_item(caller_peer_id, slot_index, null, norm_pos)


@rpc("any_peer", "call_local", "reliable")
func _server_move_stored_item(caller_peer_id: int, item_id: String, norm_pos: Vector2) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender != 0:
		caller_peer_id = sender
	move_stored_item(caller_peer_id, item_id, norm_pos)


@rpc("any_peer", "call_local", "reliable")
func _server_move_planted_bomb(caller_peer_id: int, norm_pos: Vector2) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender != 0:
		caller_peer_id = sender
	move_planted_bomb(caller_peer_id, norm_pos)


@rpc("any_peer", "call_local", "reliable")
func _server_plant_trap(caller_peer_id: int, slot_index: int, target_zone: String, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender != 0:
		caller_peer_id = sender
	plant_trap_from_jacket(caller_peer_id, slot_index, target_zone, null, norm_pos)


@rpc("any_peer", "call_local", "reliable")
func _server_grab_lit_bomb(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	grab_lit_bomb(caller_peer_id)


func _sync_state_to_peers() -> void:
	_sync_item_layer_slots()
	var state_dict: Dictionary = {
		"stored_items": stored_items.duplicate(),
		"item_positions": item_positions.duplicate(),
		"item_yaws": _item_yaws.duplicate(),
		"item_layer_slots": _item_layer_slots.duplicate(),
		"bomb_norm_pos": bomb_norm_pos,
		"bomb_yaw": _bomb_yaw,
		"armed_spring": armed_spring,
		"spring_unlatched": spring_unlatched,
		"staged_spring_on_lip": staged_spring_on_lip,
		"armed_bomb": armed_bomb,
		"staged_bomb_in_tray": staged_bomb_in_tray,
		"live_bomb_lit": live_bomb_lit,
		"live_bomb_fuse_remaining": live_bomb_fuse_remaining,
		"occupied_by_peer_id": occupied_by_peer_id,
		"is_slow_opening": is_slow_opening,
		"drawer_open_progress": drawer_open_progress,
		"drawer_visual_ratio": drawer_visual_ratio,
		"clutter_positions": clutter_positions.duplicate(),
		"clutter_yaws": _clutter_yaws.duplicate(),
		"clutter_spec_indices": _clutter_spec_indices.duplicate()
	}
	if _is_peer_connected():
		_rpc_sync_container_state.rpc(state_dict)
	else:
		if not _sync_positions_in_place():
			_rebuild_3d_interior()
		state_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_container_state(state_dict: Dictionary) -> void:
	var prev_occ: int = occupied_by_peer_id
	var was_slow_opening: bool = is_slow_opening
	var next_items: Array[String] = []
	for it in state_dict.get("stored_items", []):
		next_items.append(str(it))
	stored_items = next_items

	var raw_item_yaws: Variant = state_dict.get("item_yaws", {})
	if raw_item_yaws is Dictionary:
		_item_yaws.clear()
		for yk in (raw_item_yaws as Dictionary).keys():
			_item_yaws[str(yk).to_upper()] = float((raw_item_yaws as Dictionary)[yk])

	var raw_layer_slots: Variant = state_dict.get("item_layer_slots", null)
	if raw_layer_slots is Dictionary:
		_item_layer_slots.clear()
		for sk in (raw_layer_slots as Dictionary).keys():
			_item_layer_slots[str(sk).to_upper()] = maxi(int((raw_layer_slots as Dictionary)[sk]), 0)
	_sync_item_layer_slots()

	_bomb_yaw = float(state_dict.get("bomb_yaw", _bomb_yaw))

	var raw_positions: Variant = state_dict.get("item_positions", {})
	var next_positions: Dictionary = {}
	if raw_positions is Dictionary:
		for k in (raw_positions as Dictionary).keys():
			var pos_val: Variant = (raw_positions as Dictionary)[k]
			if pos_val is Vector2:
				var up_k: String = str(k).to_upper()
				next_positions[up_k] = clamp_item_norm_to_tray_walls(pos_val as Vector2, "loot_item", -1, up_k)
	item_positions = next_positions
	_ensure_item_positions()

	var raw_bpos: Variant = state_dict.get("bomb_norm_pos", BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS)
	bomb_norm_pos = clamp_item_norm_to_tray_walls(raw_bpos as Vector2, "planted_bomb") if raw_bpos is Vector2 else BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS

	armed_spring = bool(state_dict.get("armed_spring", false))
	spring_unlatched = bool(state_dict.get("spring_unlatched", false))
	staged_spring_on_lip = bool(state_dict.get("staged_spring_on_lip", false))
	armed_bomb = bool(state_dict.get("armed_bomb", false))
	staged_bomb_in_tray = bool(state_dict.get("staged_bomb_in_tray", false))
	live_bomb_lit = bool(state_dict.get("live_bomb_lit", false))
	live_bomb_fuse_remaining = float(state_dict.get("live_bomb_fuse_remaining", 0.0))
	occupied_by_peer_id = int(state_dict.get("occupied_by_peer_id", 0))
	is_slow_opening = bool(state_dict.get("is_slow_opening", false))
	var synced_prog: float = float(state_dict.get("drawer_open_progress", 0.0))
	var synced_vis: float = float(state_dict.get("drawer_visual_ratio", 0.0))
	if was_slow_opening and is_slow_opening:
		drawer_open_progress = clampf(maxf(drawer_open_progress, synced_prog), 0.0, 1.0)
		drawer_visual_ratio = _eval_slow_open_ratio(drawer_open_progress)
	else:
		drawer_open_progress = clampf(synced_prog, 0.0, 1.0)
		drawer_visual_ratio = clampf(synced_vis, 0.0, 1.0)
	_is_focused_closed = (occupied_by_peer_id != 0 and not is_slow_opening and drawer_visual_ratio < 0.35)

	var raw_clutter: Array = state_dict.get("clutter_positions", [])
	var raw_clutter_yaws: Array = state_dict.get("clutter_yaws", [])
	var raw_specs: Array = state_dict.get("clutter_spec_indices", [])
	if is_briefcase_container:
		clutter_positions.clear()
		_clutter_yaws.clear()
		_clutter_spec_indices.clear()
	else:
		if not raw_specs.is_empty():
			_clutter_spec_indices.clear()
			for s in raw_specs:
				_clutter_spec_indices.append(clampi(int(s), 0, CLUTTER_PROP_SPECS.size() - 1))
		if not raw_clutter_yaws.is_empty():
			_clutter_yaws.clear()
			for yv in raw_clutter_yaws:
				_clutter_yaws.append(float(yv))
		if not raw_clutter.is_empty():
			clutter_positions.clear()
			for p_idx in range(raw_clutter.size()):
				clutter_positions.append(clamp_item_norm_to_tray_walls(raw_clutter[p_idx] as Vector2, "clutter", p_idx))
	_init_clutter_if_empty()
	_has_player_modified_layout = true

	var local_id: int = multiplayer.get_unique_id() if _is_peer_connected() else 1
	if prev_occ != occupied_by_peer_id:
		var local_player: Node = _find_player_node(local_id)
		if local_player != null:
			if occupied_by_peer_id == local_id and local_player.has_method("enter_container_view"):
				local_player.enter_container_view(self)
			elif prev_occ == local_id and occupied_by_peer_id == 0 and local_player.has_method("exit_container_view"):
				local_player.exit_container_view()
		if occupied_by_peer_id == 0:
			_animate_tray_to_ratio(0.0, false)
		elif is_slow_opening:
			_apply_open_visual_ratio(drawer_visual_ratio)
		elif drawer_visual_ratio > 0.0:
			_animate_tray_to_ratio(drawer_visual_ratio, false)
	elif occupied_by_peer_id != 0:
		if is_slow_opening:
			_apply_open_visual_ratio(drawer_visual_ratio)
		elif is_briefcase_container:
			_animate_tray_to_ratio(drawer_visual_ratio, false)
		else:
			var desired_z: float = lerpf(drawer_closed_z, drawer_open_z, drawer_visual_ratio)
			if not is_equal_approx(_tray_target_z, desired_z):
				_animate_tray_to_ratio(drawer_visual_ratio, false)

	_sync_back_to_briefcase_pickup()
	if not _sync_positions_in_place():
		_rebuild_3d_interior()
	state_changed.emit()


# ==========================================
# Physical 3D Hollow Drawer & Multi-Layer Clutter Interior
# ==========================================

func get_norm_bounds() -> Vector2:
	if is_briefcase_container:
		return Vector2(BRIEFCASE_BUILDER.NORM_MIN, BRIEFCASE_BUILDER.NORM_MAX)
	return Vector2(0.02, 0.98)


func _clamp_container_norm(norm: Vector2) -> Vector2:
	var b: Vector2 = get_norm_bounds()
	return Vector2(clampf(norm.x, b.x, b.y), clampf(norm.y, b.x, b.y))


func norm_to_container_local_xz(norm: Vector2) -> Vector2:
	if is_briefcase_container:
		return BRIEFCASE_BUILDER.norm_to_briefcase_local_xz(norm)
	return norm_to_tray_local_xz(norm)


func container_local_xz_to_norm(local_x: float, local_z: float) -> Vector2:
	if is_briefcase_container:
		return BRIEFCASE_BUILDER.briefcase_local_xz_to_norm(local_x, local_z)
	return tray_local_xz_to_norm(local_x, local_z)


func norm_to_tray_local_xz(norm: Vector2) -> Vector2:
	var half_x: float = maxf(tray_local_half_extents.x, 0.05)
	var half_z: float = maxf(tray_local_half_extents.y, 0.05)
	return Vector2(
		tray_local_center_xz.x + lerpf(-half_x, half_x, clampf(norm.x, 0.0, 1.0)),
		tray_local_center_xz.y + lerpf(-half_z, half_z, clampf(norm.y, 0.0, 1.0))
	)


func tray_local_xz_to_norm(local_x: float, local_z: float) -> Vector2:
	var half_x: float = maxf(tray_local_half_extents.x, 0.05)
	var half_z: float = maxf(tray_local_half_extents.y, 0.05)
	return Vector2(
		clampf((local_x - tray_local_center_xz.x + half_x) / (2.0 * half_x), 0.02, 0.98),
		clampf((local_z - tray_local_center_xz.y + half_z) / (2.0 * half_z), 0.02, 0.98)
	)


func get_tray_node() -> Node3D:
	return _tray_drawer_node


func get_clutter_area_node(clutter_idx: int) -> Node3D:
	return _clutter_area_nodes.get(clutter_idx, null) as Node3D


func get_content_area_node(kind: String, key: Variant = "") -> Node3D:
	if kind == "clutter":
		return _clutter_area_nodes.get(int(key), null) as Node3D
	if _contents_root == null or not is_instance_valid(_contents_root):
		return null
	if kind == "planted_bomb":
		return _contents_root.get_node_or_null("TrayTimeBomb") as Node3D
	if kind == "loot_item":
		var target_id: String = str(key).to_upper()
		for child in _contents_root.get_children():
			if child is Area3D and str(child.get_meta("container_role", "")) == "loot_item":
				if str(child.get_meta("item_id", "")).to_upper() == target_id:
					return child as Node3D
	return null


func _ensure_3d_tray_structure() -> void:
	if not is_inside_tree():
		return
	if _tray_drawer_node == null:
		_tray_drawer_node = get_node_or_null("TrayPivot") as Node3D
	if _tray_drawer_node == null:
		_tray_drawer_node = Node3D.new()
		_tray_drawer_node.name = "TrayPivot"
		_tray_drawer_node.position = Vector3(0.0, 0.075 if is_briefcase_container else 0.62, 0.0)
		add_child(_tray_drawer_node)

	var has_custom_mesh: bool = use_custom_tray_mesh or (_tray_drawer_node.get_node_or_null("DrawerMesh") != null)
	if not has_custom_mesh:
		var legacy_mesh: Node3D = _tray_drawer_node.get_node_or_null("TrayMesh") as Node3D
		if legacy_mesh != null:
			legacy_mesh.visible = false

	if not _hollow_built:
		_hollow_built = true
		if is_briefcase_container:
			var rig: Dictionary = BRIEFCASE_BUILDER.build_briefcase_rig(_tray_drawer_node)
			_briefcase_lid_pivot = rig.get("lid_pivot") as Node3D
			_briefcase_interior_light = rig.get("interior_light") as OmniLight3D
		else:
			if not has_custom_mesh:
				var geom := Node3D.new()
				geom.name = "HollowTrayGeometry"
				_tray_drawer_node.add_child(geom)

				var floor_w: float = 0.88
				var floor_d: float = 0.50
				var wall_h: float = 0.16

				var floor_mat := StandardMaterial3D.new()
				floor_mat.albedo_color = Color(0.14, 0.22, 0.18)
				var wall_mat := StandardMaterial3D.new()
				wall_mat.albedo_color = Color(0.58, 0.42, 0.26)
				var brass_mat := StandardMaterial3D.new()
				brass_mat.albedo_color = Color(0.86, 0.72, 0.28)
				brass_mat.metallic = 0.65

				var floor_mi := MeshInstance3D.new()
				var floor_box := BoxMesh.new()
				floor_box.size = Vector3(floor_w, 0.02, floor_d)
				floor_mi.mesh = floor_box
				floor_mi.material_override = floor_mat
				floor_mi.position = Vector3(0.0, -0.07, 0.0)
				geom.add_child(floor_mi)

				var side_box := BoxMesh.new()
				side_box.size = Vector3(0.03, wall_h, floor_d + 0.02)
				for side_sign in [-1.0, 1.0]:
					var s_mi := MeshInstance3D.new()
					s_mi.mesh = side_box
					s_mi.material_override = wall_mat
					s_mi.position = Vector3(side_sign * (floor_w * 0.5), 0.0, 0.0)
					geom.add_child(s_mi)

				var back_mi := MeshInstance3D.new()
				var back_box := BoxMesh.new()
				back_box.size = Vector3(floor_w + 0.03, wall_h, 0.03)
				back_mi.mesh = back_box
				back_mi.material_override = wall_mat
				back_mi.position = Vector3(0.0, 0.0, -floor_d * 0.5)
				geom.add_child(back_mi)

				var front_mi := MeshInstance3D.new()
				var front_box := BoxMesh.new()
				front_box.size = Vector3(floor_w + 0.06, wall_h + 0.02, 0.03)
				front_mi.mesh = front_box
				front_mi.material_override = wall_mat
				front_mi.position = Vector3(0.0, 0.0, floor_d * 0.5)
				geom.add_child(front_mi)

				var handle_mi := MeshInstance3D.new()
				var handle_box := BoxMesh.new()
				handle_box.size = Vector3(0.22, 0.03, 0.03)
				handle_mi.mesh = handle_box
				handle_mi.material_override = brass_mat
				handle_mi.position = Vector3(0.0, 0.01, floor_d * 0.5 + 0.025)
				geom.add_child(handle_mi)

	_contents_root = _tray_drawer_node.get_node_or_null("ContentsRoot") as Node3D
	if _contents_root == null:
		_contents_root = Node3D.new()
		_contents_root.name = "ContentsRoot"
		_tray_drawer_node.add_child(_contents_root)
	if is_briefcase_container:
		_apply_briefcase_lid_ratio(drawer_visual_ratio)


func _get_stored_item_tray_layout(item_id: String, for_briefcase: bool = false) -> Dictionary:
	# Drawers match 1:1 ground XZ footprint while flattening only vertical Y <= ~0.04m
	# so items rest cleanly under the 3 clutter strata in top-down search view.
	var s: float = 0.62 if for_briefcase else 1.0
	match item_id.to_upper():
		"KEY":
			return {"scale": Vector3(s, s, s), "size": Vector3(0.266, 0.020, 0.093) * s, "rot": Vector3(0.0, PI * 0.5, 0.0)}
		"MONEY":
			return {"scale": Vector3(0.30 if for_briefcase else 0.16, s, s), "size": Vector3(0.209 * s, 0.039 if for_briefcase else 0.020, 0.160 * s), "rot": Vector3(0.0, 0.0, PI * 0.5)}
		"PASSPORT":
			return {"scale": Vector3(s, s, s), "size": Vector3(0.142, 0.014, 0.228) * s, "rot": Vector3.ZERO}
		"PLANS":
			return {"scale": Vector3(s, s, s), "size": Vector3(0.251, 0.012, 0.202) * s, "rot": Vector3.ZERO}
		"BUCKET":
			return {"scale": Vector3(0.95 * s, 0.95 * s, 0.14 if for_briefcase else 0.075), "size": Vector3(0.281 * s, 0.040 if for_briefcase else 0.020, 0.295 * s), "rot": Vector3(PI * 0.5, 0.0, 0.0)}
		"BOMB", "LIVE_BOMB":
			return {"scale": Vector3(0.92 * s, 0.92 * s, 0.20 if for_briefcase else 0.10), "size": Vector3(0.175 * s, 0.040 if for_briefcase else 0.020, 0.267 * s), "rot": Vector3(-PI * 0.5, 0.0, 0.0)}
		"TRIPWIRE":
			return {"scale": Vector3(s, s, s), "size": Vector3(0.081 * s, 0.018, 0.211 * s), "rot": Vector3(PI * 0.5, 0.0, 0.0)}
		"DART_GUN":
			return {"scale": Vector3(0.60 if for_briefcase else 0.34, s, s), "size": Vector3(0.212 * s, 0.036 if for_briefcase else 0.020, 0.353 * s), "rot": Vector3(0.0, 0.0, PI * 0.5)}
		"SPRING":
			return {"scale": Vector3(s, s, 0.25 if for_briefcase else 0.14), "size": Vector3(0.148 * s, 0.037 if for_briefcase else 0.020, 0.202 * s), "rot": Vector3(PI * 0.5, 0.0, 0.0)}
		_:
			return {"scale": Vector3(0.72 * s, 0.11, 0.72 * s), "size": Vector3(0.158 * s, 0.016, 0.158 * s), "rot": Vector3.ZERO}


func pick_drawer_object_at_ray(ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	if _contents_root == null or not is_instance_valid(_contents_root) or not is_inside_tree():
		return {}
	if is_briefcase_container and drawer_visual_ratio < 0.12:
		return {}
	var best_area: Node3D = null
	var best_world_hit := Vector3.ZERO
	var best_dist_sq: float = INF
	for child in _contents_root.get_children():
		if not (child is Area3D):
			continue
		var area: Area3D = child as Area3D
		if not area.has_meta("exact_aabb"):
			continue
		var role: String = str(area.get_meta("container_role", ""))
		if is_slow_opening and role != "lip_spring":
			continue
		if is_briefcase_container and drawer_visual_ratio < 0.42 and role != "lip_spring":
			continue
		var inv: Transform3D = area.global_transform.affine_inverse()
		var local_orig: Vector3 = inv * ray_origin
		var local_dir: Vector3 = (inv.basis * ray_dir).normalized()
		var aabb: AABB = area.get_meta("exact_aabb") as AABB
		var local_hit: Variant = aabb.intersects_ray(local_orig, local_dir)
		if not (local_hit is Vector3):
			continue
		var world_hit: Vector3 = area.global_transform * (local_hit as Vector3)
		var pick_z_limit: float = (min_pick_local_z - 0.03) if role == "lip_spring" else min_pick_local_z
		if not is_briefcase_container and to_local(world_hit).z < pick_z_limit:
			continue
		var dist_sq: float = ray_origin.distance_squared_to(world_hit)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_area = area
			best_world_hit = world_hit
	if best_area == null:
		return {}
	return {"collider": best_area, "position": best_world_hit}


func _rebuild_3d_interior() -> void:
	if not is_inside_tree():
		return
	_init_clutter_if_empty()
	_ensure_item_positions()
	_sync_item_layer_slots()
	_ensure_3d_tray_structure()
	if _contents_root == null:
		return

	_clutter_area_nodes.clear()
	for child in _contents_root.get_children():
		_contents_root.remove_child(child)
		child.queue_free()

	var cursor_y: float = DRAWER_BOMB_BOTTOM_Y

	# 1. Bottom-most (last) layer — Lit, Armed, or Staged Time Bomb in Tray
	if live_bomb_lit or armed_bomb or staged_bomb_in_tray:
		var bomb_area := Area3D.new()
		bomb_area.name = "TrayTimeBomb"
		bomb_area.collision_layer = DRAWER_CONTENTS_MASK
		bomb_area.collision_mask = 0
		var bomb_size := Vector3(0.13, 0.026, 0.16) if is_briefcase_container else Vector3(0.18, 0.042, 0.24)
		var bomb_visual: Node3D = PICKUP_SCRIPT.build_item_visual("LIVE_BOMB" if live_bomb_lit else "BOMB")
		var b_s: float = 0.56 if is_briefcase_container else 0.92
		bomb_visual.scale = Vector3(b_s, b_s, 0.18 if is_briefcase_container else 0.11)
		bomb_visual.rotation.x = -PI * 0.5
		if is_briefcase_container:
			var b_xz: Vector2 = BRIEFCASE_BUILDER.norm_to_briefcase_local_xz(bomb_norm_pos)
			bomb_area.position = Vector3(b_xz.x, BRIEFCASE_BUILDER.BOMB_LAYER_Y, b_xz.y)
		else:
			var bomb_aabb: AABB = _compute_visual_aabb_recursive(bomb_visual, bomb_visual.transform)
			if bomb_aabb.size != Vector3.ZERO:
				bomb_visual.position.y -= bomb_aabb.get_center().y
				bomb_size.y = maxf(bomb_size.y, bomb_aabb.size.y)
			var bomb_half_h: float = maxf(bomb_aabb.size.y * 0.5, 0.010)
			var d_bxz: Vector2 = norm_to_tray_local_xz(bomb_norm_pos)
			bomb_area.position = Vector3(d_bxz.x, DRAWER_BOMB_BOTTOM_Y + bomb_half_h, d_bxz.y)
			bomb_area.rotation.y = deg_to_rad(_bomb_yaw)
			cursor_y = bomb_area.position.y + bomb_half_h + 0.004
		bomb_area.set_meta("container_role", "lit_bomb" if live_bomb_lit else "planted_bomb")
		bomb_area.set_meta("base_y", bomb_area.position.y)
		bomb_area.set_meta("exact_aabb", AABB(-bomb_size * 0.5, bomb_size))

		var bomb_col := CollisionShape3D.new()
		var bomb_shape := BoxShape3D.new()
		bomb_shape.size = bomb_size
		bomb_col.shape = bomb_shape
		bomb_area.add_child(bomb_col)
		bomb_area.add_child(bomb_visual)
		_contents_root.add_child(bomb_area)

	if not is_briefcase_container:
		cursor_y = maxf(cursor_y, DRAWER_STORED_ITEMS_START_Y)
	var item_band_base_y: float = cursor_y
	var max_item_top_y: float = cursor_y
	var used_slots_in_pass: Dictionary = {}

	# 2. Stored Objectives & Gadgets — Freeform XZ + Fixed Disjoint Vertical Slots
	for i in range(stored_items.size()):
		var item_id: String = str(stored_items[i]).to_upper()
		var slot_idx: int = int(_item_layer_slots.get(item_id, i))
		while used_slots_in_pass.has(slot_idx):
			slot_idx += 1
		used_slots_in_pass[slot_idx] = true
		var xz := Vector2.ZERO
		var item_y: float = -0.048 + float(slot_idx) * 0.018
		if is_briefcase_container:
			var fallback_norm: Vector2 = BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS[i % BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS.size()]
			var norm_pos: Vector2 = item_positions.get(item_id, fallback_norm) as Vector2
			xz = BRIEFCASE_BUILDER.norm_to_briefcase_local_xz(norm_pos)
			item_y = BRIEFCASE_BUILDER.get_item_layer_y(slot_idx)
		else:
			var fallback_drawer_norm: Vector2 = ITEM_TRAY_POSITIONS[i % ITEM_TRAY_POSITIONS.size()]
			var drawer_norm: Vector2 = item_positions.get(item_id, fallback_drawer_norm) as Vector2
			xz = norm_to_tray_local_xz(drawer_norm)
		var layout: Dictionary = _get_stored_item_tray_layout(item_id, is_briefcase_container)
		var exact_size: Vector3 = layout["size"] as Vector3

		var item_visual: Node3D = PICKUP_SCRIPT.build_item_visual(item_id)
		item_visual.scale = layout["scale"] as Vector3
		item_visual.rotation = layout.get("rot", Vector3.ZERO) as Vector3
		if not is_briefcase_container:
			var item_aabb: AABB = _compute_visual_aabb_recursive(item_visual, item_visual.transform)
			if item_aabb.size != Vector3.ZERO:
				item_visual.position.y -= item_aabb.get_center().y
				exact_size.y = maxf(exact_size.y, item_aabb.size.y)
			var item_half_h: float = maxf(item_aabb.size.y * 0.5, 0.007)
			item_y = item_band_base_y + float(slot_idx) * DRAWER_ITEM_SLOT_STEP_Y + item_half_h
			max_item_top_y = maxf(max_item_top_y, item_y + item_half_h + 0.004)

		var item_area := Area3D.new()
		item_area.name = "TrayItem_%d_%s" % [i, item_id]
		item_area.collision_layer = DRAWER_CONTENTS_MASK
		item_area.collision_mask = 0
		item_area.position = Vector3(xz.x, item_y, xz.y)
		if not is_briefcase_container:
			item_area.rotation.y = deg_to_rad(float(_item_yaws.get(item_id, 0.0)))
		item_area.set_meta("container_role", "loot_item")
		item_area.set_meta("item_id", item_id)
		item_area.set_meta("base_y", item_y)
		item_area.set_meta("exact_aabb", AABB(-exact_size * 0.5, exact_size))

		var item_col := CollisionShape3D.new()
		var item_shape := BoxShape3D.new()
		item_shape.size = exact_size
		item_col.shape = item_shape
		item_area.add_child(item_col)
		item_area.add_child(item_visual)
		if PICKUP_SCRIPT.is_objective_item(item_id) or PICKUP_SCRIPT.is_briefcase_item(item_id):
			var glint: CPUParticles3D = PICKUP_SCRIPT.create_objective_glint_particles(true)
			glint.position = Vector3(0.0, 0.012, 0.0)
			item_area.add_child(glint)
		_contents_root.add_child(item_area)

	# 3. Upper Clutter Layers — Fixed band above stored items (each junk piece gets its own Y step)
	if not is_briefcase_container:
		cursor_y = maxf(max_item_top_y, DRAWER_CLUTTER_START_Y)
	var total_clutter: int = clutter_positions.size()
	var clutter_scale: float = _get_effective_clutter_scale()
	for i in range(total_clutter):
		var spec_idx: int = (
			clampi(int(_clutter_spec_indices[i]), 0, CLUTTER_PROP_SPECS.size() - 1)
			if i < _clutter_spec_indices.size()
			else (i + absi(container_seed)) % CLUTTER_PROP_SPECS.size()
		)
		var spec: Dictionary = CLUTTER_PROP_SPECS[spec_idx]
		var base_y: float = CLUTTER_START_Y + float(i) * CLUTTER_STEP_Y
		var c_size: Vector3 = (spec["size"] as Vector3) * clutter_scale
		if not is_briefcase_container:
			var c_half_h: float = c_size.y * 0.5
			base_y = cursor_y + c_half_h
			cursor_y = base_y + c_half_h + 0.004
		var xz: Vector2 = norm_to_tray_local_xz(clutter_positions[i])

		var clutter_area := Area3D.new()
		clutter_area.name = "ClutterProp_%d" % i
		clutter_area.collision_layer = DRAWER_CONTENTS_MASK
		clutter_area.collision_mask = 0
		clutter_area.position = Vector3(xz.x, base_y, xz.y)
		var yaw_deg: float = _clutter_yaws[i] if i < _clutter_yaws.size() else float((spec_idx * 47 + i * 73) % 360)
		clutter_area.rotation.y = deg_to_rad(yaw_deg)
		clutter_area.set_meta("container_role", "clutter")
		clutter_area.set_meta("clutter_idx", i)
		clutter_area.set_meta("clutter_layer", i)
		clutter_area.set_meta("base_y", base_y)
		clutter_area.set_meta("exact_aabb", AABB(-c_size * 0.5, c_size))

		var c_col := CollisionShape3D.new()
		var c_shape := BoxShape3D.new()
		c_shape.size = c_size
		c_col.shape = c_shape
		clutter_area.add_child(c_col)

		_build_3d_clutter_prop(clutter_area, spec_idx, clutter_scale)
		_contents_root.add_child(clutter_area)
		_clutter_area_nodes[i] = clutter_area

	# 4. Top-most layer — Front-Inside Lip Spring Trap (Drawers sit fixed at top band; Briefcases stay on lip)
	if armed_spring or spring_unlatched or staged_spring_on_lip:
		var lip_area := Area3D.new()
		lip_area.name = "LipSpringTrap"
		lip_area.collision_layer = DRAWER_CONTENTS_MASK
		lip_area.collision_mask = 0
		var lip_size := Vector3(0.14, 0.10, 0.14) if is_briefcase_container else Vector3(0.16, 0.16, 0.20)
		var spring_visual: Node3D = PICKUP_SCRIPT.build_item_visual("SPRING")
		var lip_scale: float = 0.52 if is_briefcase_container else 0.85
		spring_visual.scale = Vector3(lip_scale, lip_scale, lip_scale) if is_briefcase_container else Vector3(lip_scale, lip_scale, lip_scale * 0.40)
		spring_visual.rotation.x = PI * 0.5
		if is_briefcase_container:
			lip_area.position = Vector3(0.0, 0.010, 0.145)
		else:
			var spring_aabb: AABB = _compute_visual_aabb_recursive(spring_visual, spring_visual.transform)
			if spring_aabb.size != Vector3.ZERO:
				spring_visual.position.y -= spring_aabb.get_center().y
				lip_size.y = maxf(lip_size.y, spring_aabb.size.y)
			var spring_half_h: float = maxf(spring_aabb.size.y * 0.5, 0.020)
			lip_area.position = Vector3(
				lip_spring_local_pos.x,
				maxf(lip_spring_local_pos.y, maxf(cursor_y + 0.004, DRAWER_LIP_SPRING_BOTTOM_Y) + spring_half_h),
				lip_spring_local_pos.z
			)
		lip_area.set_meta("container_role", "lip_spring")
		lip_area.set_meta("exact_aabb", AABB(-lip_size * 0.5, lip_size))

		var lip_col := CollisionShape3D.new()
		var lip_shape := BoxShape3D.new()
		lip_shape.size = lip_size
		lip_col.shape = lip_shape
		lip_area.add_child(lip_col)

		var state_color := Color(0.95, 0.65, 0.18)
		if armed_spring:
			state_color = Color(0.95, 0.18, 0.18)
		elif spring_unlatched:
			state_color = Color(0.22, 0.82, 0.72)
		for child_mi in spring_visual.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := child_mi as MeshInstance3D
			var src_mat: Material = mesh_node.material_override
			if src_mat == null and mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
				src_mat = mesh_node.mesh.surface_get_material(0)
			var tint_mat: StandardMaterial3D = (src_mat.duplicate() as StandardMaterial3D) if src_mat is StandardMaterial3D else StandardMaterial3D.new()
			tint_mat.albedo_color = state_color.lerp(Color.WHITE, 0.25)
			tint_mat.emission_enabled = true
			tint_mat.emission = state_color
			tint_mat.emission_energy_multiplier = 0.55
			mesh_node.material_override = tint_mat
		lip_area.add_child(spring_visual)
		_contents_root.add_child(lip_area)

	_contents_root.set_meta("structure_sig", _compute_structure_signature())
	if is_briefcase_container:
		_apply_briefcase_lid_ratio(drawer_visual_ratio)


func _compute_structure_signature() -> String:
	return "%s|%s|%d|%d|%d|%d|%d|%d|%d|%s|%s" % [
		"B" if is_briefcase_container else "D",
		",".join(PackedStringArray(stored_items)),
		1 if armed_spring else 0,
		1 if spring_unlatched else 0,
		1 if staged_spring_on_lip else 0,
		1 if armed_bomb else 0,
		1 if staged_bomb_in_tray else 0,
		1 if live_bomb_lit else 0,
		clutter_positions.size(),
		str(_clutter_spec_indices),
		str(max_clutter_layers_override)
	]


func _sync_positions_in_place() -> bool:
	if _contents_root == null or not is_instance_valid(_contents_root) or not is_inside_tree():
		return false
	if str(_contents_root.get_meta("structure_sig", "")) != _compute_structure_signature():
		return false
	for i in range(clutter_positions.size()):
		var area: Node3D = _clutter_area_nodes.get(i, null) as Node3D
		if area == null or not is_instance_valid(area):
			return false
		var xz: Vector2 = norm_to_container_local_xz(clutter_positions[i])
		area.position.x = xz.x
		area.position.z = xz.y
		area.position.y = float(area.get_meta("base_y", area.position.y))
		if i < _clutter_yaws.size():
			area.rotation.y = deg_to_rad(_clutter_yaws[i])
	for i in range(stored_items.size()):
		var item_id: String = str(stored_items[i]).to_upper()
		var item_area: Node3D = get_content_area_node("loot_item", item_id)
		if item_area == null or not is_instance_valid(item_area):
			return false
		var norm_pos: Vector2 = item_positions.get(item_id, Vector2(0.5, 0.5)) as Vector2
		var i_xz: Vector2 = norm_to_container_local_xz(norm_pos)
		item_area.position.x = i_xz.x
		item_area.position.z = i_xz.y
		item_area.position.y = float(item_area.get_meta("base_y", item_area.position.y))
		if not is_briefcase_container and _item_yaws.has(item_id):
			item_area.rotation.y = deg_to_rad(float(_item_yaws[item_id]))
	if live_bomb_lit or armed_bomb or staged_bomb_in_tray:
		var bomb_area: Node3D = get_content_area_node("planted_bomb")
		if bomb_area == null or not is_instance_valid(bomb_area):
			return false
		var b_xz: Vector2 = norm_to_container_local_xz(bomb_norm_pos)
		bomb_area.position.x = b_xz.x
		bomb_area.position.z = b_xz.y
		bomb_area.position.y = float(bomb_area.get_meta("base_y", bomb_area.position.y))
		if not is_briefcase_container:
			bomb_area.rotation.y = deg_to_rad(_bomb_yaw)
	return true


func _strip_physics_nodes_recursive(node: Node) -> void:
	var children: Array[Node] = node.get_children()
	for child in children:
		if child is PhysicsBody3D or child is CollisionShape3D or child is CollisionPolygon3D:
			node.remove_child(child)
			child.queue_free()
		else:
			_strip_physics_nodes_recursive(child)


func _compute_visual_aabb_recursive(node: Node, parent_xf: Transform3D) -> AABB:
	var combined := AABB()
	var has_any: bool = false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var mesh_aabb: AABB = mi.mesh.get_aabb()
			for i in range(8):
				var pt: Vector3 = parent_xf * mesh_aabb.get_endpoint(i)
				if not has_any:
					combined = AABB(pt, Vector3.ZERO)
					has_any = true
				else:
					combined = combined.expand(pt)
	for child in node.get_children():
		var child_xf: Transform3D = parent_xf
		if child is Node3D:
			child_xf = parent_xf * (child as Node3D).transform
		var child_aabb: AABB = _compute_visual_aabb_recursive(child, child_xf)
		if child_aabb.size != Vector3.ZERO or (child is MeshInstance3D and (child as MeshInstance3D).mesh != null):
			if not has_any:
				combined = child_aabb
				has_any = true
			else:
				combined = combined.merge(child_aabb)
	return combined


func _build_3d_clutter_prop(parent_area: Area3D, idx: int, scale_factor: float = 1.0) -> void:
	var spec: Dictionary = CLUTTER_PROP_SPECS[clampi(idx, 0, CLUTTER_PROP_SPECS.size() - 1)]
	var scene_res: PackedScene = spec["scene"] as PackedScene
	var visual: Node3D = scene_res.instantiate() as Node3D
	if visual == null:
		return
	_strip_physics_nodes_recursive(visual)
	var target_size: Vector3 = (spec["size"] as Vector3) * scale_factor
	var raw_aabb: AABB = _compute_visual_aabb_recursive(visual, visual.transform)
	if raw_aabb.size.x > 0.0001 and raw_aabb.size.y > 0.0001 and raw_aabb.size.z > 0.0001:
		var sx: float = target_size.x / raw_aabb.size.x
		var sy: float = target_size.y / raw_aabb.size.y
		var sz: float = target_size.z / raw_aabb.size.z
		var fit_pivot := Node3D.new()
		fit_pivot.name = "FitPivot"
		fit_pivot.scale = Vector3(sx, sy, sz)
		visual.position -= raw_aabb.get_center()
		fit_pivot.add_child(visual)
		parent_area.add_child(fit_pivot)
	else:
		parent_area.add_child(visual)


func _find_player_node(peer_id: int) -> Node:
	if is_inside_tree() and get_tree() != null:
		var scene: Node = get_tree().current_scene
		if scene != null:
			var p: Node = scene.get_node_or_null("Players/" + str(peer_id))
			if p != null:
				return p
		for candidate in get_tree().get_nodes_in_group("spy_players"):
			if candidate.name == str(peer_id):
				return candidate

	var parent: Node = get_parent()
	while parent != null:
		var p2: Node = parent.get_node_or_null("Players/" + str(peer_id))
		if p2 != null:
			return p2
		var p3: Node = parent.get_node_or_null(str(peer_id))
		if p3 != null and p3.has_method("pickup_item"):
			return p3
		parent = parent.get_parent()
	return null


func _safe_global_pos() -> Vector3:
	return global_position if is_inside_tree() else position


func _is_peer_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
