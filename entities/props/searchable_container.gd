@tool
class_name SearchableContainer
extends StaticBody3D

## Unified Searchable Container for Desk Drawers, Filing Cabinets & Dropped Briefcases (Doc 3 §3 & §4).
## Enforces single-user lock, +10s first-visit bonus, Tap-E vs Hold-E asymmetric trap triggers,
## draggable clutter persistence, and Top-Down Container View RPC synchronization.

signal state_changed()

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const BRIEFCASE_BUILDER = preload("res://entities/props/briefcase_visual_builder.gd")
const DRAWER_CONTENTS_MASK: int = 32
const DRAWER_CLOSED_Z: float = 0.08
const DRAWER_OPEN_Z: float = 0.56
const SPRING_TRIGGER_VISUAL_RATIO: float = 0.42
const DRAWER_EASE_EXPONENT: float = 1.85
const DEFAULT_CLUTTER_POSITIONS: Array[Vector2] = [
	Vector2(0.34, 0.40), # Layer 1: Manila Folder
	Vector2(0.62, 0.42), # Layer 1: Embassy Ledger
	Vector2(0.38, 0.66), # Layer 2: Classified Envelope
	Vector2(0.64, 0.66), # Layer 2: Folded Newspaper
	Vector2(0.48, 0.50), # Layer 3: Heavy Stapler
	Vector2(0.52, 0.36)  # Layer 3: Wooden Clipboard
]
const ITEM_TRAY_POSITIONS: Array[Vector2] = [
	Vector2(0.32, 0.38),
	Vector2(0.62, 0.40),
	Vector2(0.36, 0.68),
	Vector2(0.64, 0.68)
]
const CLUTTER_PROP_SPECS: Array[Dictionary] = [
	{ # 0: Manila Folder
		"base_y": -0.030, "size": Vector3(0.26, 0.006, 0.19), "color": Color(0.84, 0.72, 0.48),
		"acc_size": Vector3(0.08, 0.006, 0.035), "acc_color": Color(0.88, 0.76, 0.52), "acc_pos": Vector3(-0.07, 0.0, -0.105)
	},
	{ # 1: Embassy Ledger
		"base_y": -0.019, "size": Vector3(0.21, 0.010, 0.25), "color": Color(0.45, 0.14, 0.16),
		"acc_size": Vector3(0.032, 0.011, 0.25), "acc_color": Color(0.85, 0.72, 0.25), "acc_pos": Vector3(-0.09, 0.0005, 0.0)
	},
	{ # 2: Classified Envelope
		"base_y": -0.008, "size": Vector3(0.23, 0.006, 0.14), "color": Color(0.92, 0.90, 0.82),
		"acc_size": Vector3(0.10, 0.002, 0.035), "acc_color": Color(0.82, 0.16, 0.16), "acc_pos": Vector3(0.0, 0.004, 0.0)
	},
	{ # 3: Folded Newspaper
		"base_y": 0.002, "size": Vector3(0.24, 0.008, 0.20), "color": Color(0.76, 0.77, 0.75),
		"acc_size": Vector3(0.20, 0.002, 0.035), "acc_color": Color(0.18, 0.20, 0.22), "acc_pos": Vector3(0.0, 0.005, -0.055)
	},
	{ # 4: Wooden Clipboard
		"base_y": 0.013, "size": Vector3(0.19, 0.008, 0.25), "color": Color(0.56, 0.38, 0.22),
		"acc_size": Vector3(0.15, 0.003, 0.19), "acc_color": Color(0.95, 0.95, 0.92), "acc_pos": Vector3(0.0, 0.0055, 0.015)
	},
	{ # 5: Heavy Stapler
		"base_y": 0.028, "size": Vector3(0.20, 0.016, 0.065), "color": Color(0.24, 0.26, 0.30),
		"acc_size": Vector3(0.16, 0.008, 0.045), "acc_color": Color(0.78, 0.22, 0.20), "acc_pos": Vector3(-0.01, 0.010, 0.0)
	}
]

@export var container_id: String = "Drawer"
@export var is_briefcase_container: bool = false
@export var clutter_count: int = 6
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
var _is_preview_sliding: bool = false
var _opened_effects_applied: bool = false
var drawer_open_progress: float = 0.0
var drawer_visual_ratio: float = 0.0
var _hollow_built: bool = false
var _contents_root: Node3D = null
var _clutter_area_nodes: Dictionary = {}
var _briefcase_lid_pivot: Node3D = null
var _briefcase_interior_light: OmniLight3D = null
var _lid_tween: Tween = null


func _ready() -> void:
	if not is_briefcase_container:
		collision_layer = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3
	else:
		collision_layer = 0
	collision_mask = 0
	_init_clutter_if_empty()
	_ensure_item_positions()
	_tray_drawer_node = get_node_or_null("TrayPivot") as Node3D
	_top_down_vantage = get_node_or_null("TopDownVantage") as Marker3D
	if not Engine.is_editor_hint():
		_ensure_3d_tray_structure()
		_rebuild_3d_interior()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not live_bomb_lit:
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


func _init_clutter_if_empty() -> void:
	if clutter_positions.size() == clutter_count:
		return
	clutter_positions.clear()
	for i in range(maxi(clutter_count, 0)):
		var base_pos: Vector2 = DEFAULT_CLUTTER_POSITIONS[i % DEFAULT_CLUTTER_POSITIONS.size()]
		clutter_positions.append(base_pos)


func _ensure_item_positions() -> void:
	var next_positions: Dictionary = {}
	for i in range(stored_items.size()):
		var item_id: String = str(stored_items[i]).to_upper()
		if item_positions.has(item_id) and item_positions[item_id] is Vector2:
			next_positions[item_id] = BRIEFCASE_BUILDER.clamp_norm(item_positions[item_id] as Vector2)
		else:
			next_positions[item_id] = BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS[i % BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS.size()]
	item_positions = next_positions


func get_interaction_prompt() -> String:
	if occupied_by_peer_id != 0:
		return "[IN USE]"
	if is_briefcase_container:
		return "[Hold E] Inspect Briefcase"
	return "[E] Look Inside Drawer"


func get_hold_interaction_duration() -> float:
	return GameConfig.drawer_slow_peek_hold_time if GameConfig != null else 2.80


func get_top_down_camera_transform() -> Transform3D:
	if _top_down_vantage != null and is_inside_tree():
		return _top_down_vantage.global_transform
	var xform: Transform3D = global_transform if is_inside_tree() else transform
	var up_dir: Vector3 = -xform.basis.z
	up_dir.y = 0.0
	up_dir = Vector3.FORWARD if up_dir.length_squared() < 0.0001 else up_dir.normalized()
	if is_briefcase_container:
		var b_origin: Vector3 = xform.origin + Vector3(0.0, 0.96, 0.02)
		var b_target: Vector3 = xform.origin + Vector3(0.0, 0.04, 0.0)
		return Transform3D(Basis.looking_at((b_target - b_origin).normalized(), up_dir), b_origin)
	var origin: Vector3 = xform * Vector3(0.0, 1.42, 0.52)
	var look_target: Vector3 = xform * Vector3(0.0, 0.55, 0.52)
	return Transform3D(Basis.looking_at((look_target - origin).normalized(), up_dir), origin)


func request_focus_container(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_focus_container.rpc_id(1, caller_peer_id)
	else:
		focus_container(caller_peer_id)


func request_step_open_drawer(caller_peer_id: int, delta: float) -> void:
	if _is_peer_connected():
		_server_step_open_drawer.rpc_id(1, caller_peer_id, delta)
	else:
		step_open_drawer(caller_peer_id, delta)


func request_begin_open(caller_peer_id: int) -> void:
	request_focus_container(caller_peer_id)


func request_interaction(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_open_container.rpc_id(1, caller_peer_id, false)
	else:
		open_container(caller_peer_id, false)


func request_hold_interaction(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_open_container.rpc_id(1, caller_peer_id, true)
	else:
		open_container(caller_peer_id, true)


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


func request_deposit_briefcase_item(caller_peer_id: int, obj_id: String) -> void:
	if _is_peer_connected():
		_server_deposit_briefcase_item.rpc_id(1, caller_peer_id, obj_id)
	else:
		deposit_briefcase_item(caller_peer_id, obj_id)


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
	_is_preview_sliding = false

	if not already_this_occupant:
		# Both Drawers and Floor Briefcases start at Stage 1 Closed (0%) so player chooses Fast (Tap E) vs Slow (Hold E)
		drawer_open_progress = 0.0
		drawer_visual_ratio = 0.0
		_opened_effects_applied = false
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.kill()
		if _lid_tween != null and _lid_tween.is_valid():
			_lid_tween.kill()
		if _tray_drawer_node != null:
			_tray_drawer_node.position.z = 0.0 if is_briefcase_container else DRAWER_CLOSED_Z
			_tray_target_z = _tray_drawer_node.position.z
		if is_briefcase_container:
			_apply_briefcase_lid_ratio(0.0)

	_sync_state_to_peers()
	if player != null and player.has_method("enter_container_view"):
		player.enter_container_view(self)
	return true


func step_open_drawer(peer_id: int, delta: float, player_override: Node = null) -> void:
	if occupied_by_peer_id != peer_id:
		return

	var slow_dur: float = GameConfig.drawer_slow_peek_hold_time if GameConfig != null else 2.80
	drawer_open_progress = clampf(drawer_open_progress + delta / maxf(slow_dur, 0.5), 0.0, 1.0)
	drawer_visual_ratio = pow(drawer_open_progress, DRAWER_EASE_EXPONENT)

	if is_briefcase_container:
		if _lid_tween != null and _lid_tween.is_valid():
			_lid_tween.kill()
		_apply_briefcase_lid_ratio(drawer_visual_ratio)
	else:
		_tray_target_z = lerpf(DRAWER_CLOSED_Z, DRAWER_OPEN_Z, drawer_visual_ratio)
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.kill()
		if _tray_drawer_node != null:
			_tray_drawer_node.position.z = _tray_target_z

	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))

	if armed_spring and drawer_visual_ratio >= SPRING_TRIGGER_VISUAL_RATIO:
		_trigger_spring_trap_ko(peer_id, player)
		return

	# Simultaneous carried-Briefcase Spring check when slow-opening a Drawer while holding Briefcase
	if not is_briefcase_container and player != null and player.has_method("has_held_briefcase_armed_spring") and bool(player.has_held_briefcase_armed_spring()):
		if drawer_visual_ratio >= SPRING_TRIGGER_VISUAL_RATIO:
			_trigger_held_briefcase_spring_from_drawer(peer_id, player)
			return

	if drawer_visual_ratio >= 0.65 and not _opened_effects_applied:
		_activate_opened_drawer_effects(peer_id, true, player)
		_sync_state_to_peers()
		return

	if _is_peer_connected():
		_rpc_sync_drawer_slide.rpc(drawer_open_progress, drawer_visual_ratio)
	else:
		state_changed.emit()


func begin_open_preview(peer_id: int, player_override: Node = null) -> bool:
	return focus_container(peer_id, player_override)


func _activate_opened_drawer_effects(peer_id: int, is_slow_peek: bool, player: Node = null) -> Dictionary:
	var out: Dictionary = {"lit_bomb": false, "awarded_bonus": false}
	if _opened_effects_applied:
		return out
	_opened_effects_applied = true

	if armed_bomb:
		armed_bomb = false
		live_bomb_lit = true
		var min_f: float = GameConfig.time_bomb_fuse_min if GameConfig != null else 2.5
		var max_f: float = GameConfig.time_bomb_fuse_max if GameConfig != null else 4.0
		var base_fuse: float = randf_range(min_f, max_f)
		if is_slow_peek:
			live_bomb_fuse_remaining = maxf(base_fuse - 0.70, 0.5)
		else:
			live_bomb_fuse_remaining = base_fuse
		if AudioBridge != null:
			var fuse_rad: float = GameConfig.audio_radius_bomb_fuse if GameConfig != null else 10.0
			AudioBridge.request_world_cue("bomb_hiss", _safe_global_pos(), fuse_rad, bomb_owner_peer_id)
		out["lit_bomb"] = true

	# Simultaneous carried-Briefcase Time Bomb ignition when opening a Drawer while holding Briefcase
	var resolved_player: Node = player if player != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if not is_briefcase_container and resolved_player != null and resolved_player.has_method("has_held_briefcase_armed_bomb") and bool(resolved_player.has_held_briefcase_armed_bomb()):
		if resolved_player.has_method("ignite_held_briefcase_bomb"):
			resolved_player.ignite_held_briefcase_bomb(is_slow_peek)
			out["lit_bomb"] = true

	if not is_briefcase_container and not searched_by_peers.has(peer_id):
		searched_by_peers[peer_id] = true
		out["awarded_bonus"] = true
		if MatchManager != null:
			if MatchManager.match_state != MatchManager.MatchState.IN_PROGRESS:
				MatchManager.start_new_match([1, 2])
			MatchManager.award_first_search_bonus(peer_id)

	return out


func _trigger_held_briefcase_spring_from_drawer(_peer_id: int, player: Node) -> void:
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

	var player: Node = player_override if player_override != null else _find_player_node(peer_id)
	_is_preview_sliding = false

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
	if armed_spring:
		if not is_slow_peek:
			_trigger_spring_trap_ko(peer_id, player)
			result["reason"] = "SPRING_KO"
			result["triggered_spring"] = true
			return result
		else:
			spring_unlatched = false
			drawer_open_progress = 0.56
			drawer_visual_ratio = pow(drawer_open_progress, DRAWER_EASE_EXPONENT)
	elif held_briefcase_spring:
		if not is_slow_peek:
			_trigger_held_briefcase_spring_from_drawer(peer_id, player)
			result["reason"] = "SPRING_KO"
			result["triggered_spring"] = true
			return result
		else:
			drawer_open_progress = 0.56
			drawer_visual_ratio = pow(drawer_open_progress, DRAWER_EASE_EXPONENT)
	else:
		drawer_open_progress = 1.0
		drawer_visual_ratio = 1.0

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


func close_container(peer_id: int, player_override: Node = null) -> void:
	if occupied_by_peer_id != 0 and occupied_by_peer_id != peer_id:
		return

	_is_preview_sliding = false
	_opened_effects_applied = false
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


func move_clutter(peer_id: int, clutter_idx: int, new_norm_pos: Vector2) -> bool:
	if occupied_by_peer_id != peer_id:
		return false
	_init_clutter_if_empty()
	if clutter_idx < 0 or clutter_idx >= clutter_positions.size():
		return false
	clutter_positions[clutter_idx] = Vector2(
		clampf(new_norm_pos.x, 0.05, 0.95),
		clampf(new_norm_pos.y, 0.05, 0.95)
	)
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
				_ensure_item_positions()
				_sync_back_to_briefcase_pickup()
				_sync_state_to_peers()
				return true

	if not _give_item_to_player(player, upper, target_jacket_slot):
		return false

	stored_items.remove_at(idx)
	item_positions.erase(upper)
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
	if is_briefcase_container and norm_pos.x >= 0.0 and norm_pos.y >= 0.0:
		item_positions[taken] = BRIEFCASE_BUILDER.clamp_norm(norm_pos)
	_ensure_item_positions()
	if AudioBridge != null:
		AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, peer_id)
	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()
	return true


func deposit_briefcase_item(peer_id: int, obj_id: String, player_override: Node = null) -> bool:
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
	_ensure_item_positions()
	if AudioBridge != null:
		AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, peer_id)
	_sync_state_to_peers()
	return true


func move_stored_item(peer_id: int, item_id: String, new_norm_pos: Vector2) -> bool:
	if occupied_by_peer_id != peer_id:
		return false
	var upper: String = item_id.to_upper()
	if not (upper in stored_items):
		return false
	item_positions[upper] = BRIEFCASE_BUILDER.clamp_norm(new_norm_pos)
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
	bomb_norm_pos = BRIEFCASE_BUILDER.clamp_norm(new_norm_pos)
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
			bomb_norm_pos = BRIEFCASE_BUILDER.clamp_norm(norm_pos)
		else:
			bomb_norm_pos = BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
		if AudioBridge != null and GameConfig != null:
			AudioBridge.request_world_cue("trap_arm", _safe_global_pos(), GameConfig.audio_radius_trap_setup, peer_id)
		_sync_back_to_briefcase_pickup()
		_sync_state_to_peers()
		return true

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

	close_container(peer_id, player)

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
		close_container(occ, occ_player)

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
	var slots: Array = player.get("jacket_slots")
	if slots is Array and slot_index >= 0 and slot_index < slots.size():
		slots[slot_index] = "NONE"
		player.set("jacket_slots", slots)
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


func _animate_tray_open(open_state: bool, slow: bool) -> void:
	_animate_tray_to_ratio(1.0 if open_state else 0.0, slow)


func _animate_tray_to_ratio(ratio: float, slow: bool) -> void:
	if _tray_drawer_node == null:
		return
	var clamped_ratio: float = clampf(ratio, 0.0, 1.0)

	var base_dur: float = 0.0
	if clamped_ratio > 0.01:
		base_dur = (GameConfig.drawer_slow_peek_hold_time if GameConfig != null else 2.80) if slow else (GameConfig.drawer_fast_slam_duration if GameConfig != null else 0.22)
	else:
		base_dur = GameConfig.drawer_close_duration if GameConfig != null else 0.30

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
			_lid_tween.tween_property(_briefcase_lid_pivot, "rotation:x", target_rot_x, base_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if clamped_ratio <= 0.03:
				_lid_tween.tween_callback(func():
					_apply_briefcase_lid_ratio(0.0)
				)
		else:
			_apply_briefcase_lid_ratio(clamped_ratio)
		return

	var target_z: float = lerpf(DRAWER_CLOSED_Z, DRAWER_OPEN_Z, clamped_ratio)
	var current_z: float = _tray_drawer_node.position.z
	if slow and is_equal_approx(_tray_target_z, target_z) and _slide_tween != null and _slide_tween.is_valid() and _slide_tween.is_running():
		return

	var travel: float = maxf(DRAWER_OPEN_Z - DRAWER_CLOSED_Z, 0.01)
	var frac: float = clampf(absf(target_z - current_z) / travel, 0.12, 1.0)
	var dur: float = base_dur * frac
	_tray_target_z = target_z

	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if is_inside_tree() and dur > 0.01 and not is_equal_approx(current_z, target_z):
		_slide_tween = create_tween()
		_slide_tween.tween_property(_tray_drawer_node, "position:z", target_z, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
func _server_step_open_drawer(caller_peer_id: int, delta: float) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	step_open_drawer(caller_peer_id, delta)


@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_sync_drawer_slide(open_prog: float, vis_ratio: float) -> void:
	drawer_open_progress = clampf(open_prog, 0.0, 1.0)
	drawer_visual_ratio = clampf(vis_ratio, 0.0, 1.0)
	if is_briefcase_container:
		if _lid_tween != null and _lid_tween.is_valid():
			_lid_tween.kill()
		_apply_briefcase_lid_ratio(drawer_visual_ratio)
	else:
		_tray_target_z = lerpf(DRAWER_CLOSED_Z, DRAWER_OPEN_Z, drawer_visual_ratio)
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.kill()
		if _tray_drawer_node != null:
			_tray_drawer_node.position.z = _tray_target_z
	state_changed.emit()

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
func _server_deposit_briefcase_item(caller_peer_id: int, obj_id: String) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender != 0:
		caller_peer_id = sender
	deposit_briefcase_item(caller_peer_id, obj_id)


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
	var state_dict: Dictionary = {
		"stored_items": stored_items.duplicate(),
		"item_positions": item_positions.duplicate(),
		"bomb_norm_pos": bomb_norm_pos,
		"armed_spring": armed_spring,
		"spring_unlatched": spring_unlatched,
		"staged_spring_on_lip": staged_spring_on_lip,
		"armed_bomb": armed_bomb,
		"staged_bomb_in_tray": staged_bomb_in_tray,
		"live_bomb_lit": live_bomb_lit,
		"live_bomb_fuse_remaining": live_bomb_fuse_remaining,
		"occupied_by_peer_id": occupied_by_peer_id,
		"drawer_open_progress": drawer_open_progress,
		"drawer_visual_ratio": drawer_visual_ratio,
		"clutter_positions": clutter_positions.duplicate()
	}
	if _is_peer_connected():
		_rpc_sync_container_state.rpc(state_dict)
	else:
		_rebuild_3d_interior()
		state_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_container_state(state_dict: Dictionary) -> void:
	var prev_occ: int = occupied_by_peer_id
	var next_items: Array[String] = []
	for it in state_dict.get("stored_items", []):
		next_items.append(str(it))
	stored_items = next_items

	var raw_positions: Variant = state_dict.get("item_positions", {})
	var next_positions: Dictionary = {}
	if raw_positions is Dictionary:
		for k in (raw_positions as Dictionary).keys():
			var pos_val: Variant = (raw_positions as Dictionary)[k]
			if pos_val is Vector2:
				next_positions[str(k).to_upper()] = BRIEFCASE_BUILDER.clamp_norm(pos_val as Vector2)
	item_positions = next_positions
	_ensure_item_positions()

	var raw_bpos: Variant = state_dict.get("bomb_norm_pos", BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS)
	bomb_norm_pos = BRIEFCASE_BUILDER.clamp_norm(raw_bpos as Vector2) if raw_bpos is Vector2 else BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS

	armed_spring = bool(state_dict.get("armed_spring", false))
	spring_unlatched = bool(state_dict.get("spring_unlatched", false))
	staged_spring_on_lip = bool(state_dict.get("staged_spring_on_lip", false))
	armed_bomb = bool(state_dict.get("armed_bomb", false))
	staged_bomb_in_tray = bool(state_dict.get("staged_bomb_in_tray", false))
	live_bomb_lit = bool(state_dict.get("live_bomb_lit", false))
	live_bomb_fuse_remaining = float(state_dict.get("live_bomb_fuse_remaining", 0.0))
	occupied_by_peer_id = int(state_dict.get("occupied_by_peer_id", 0))
	drawer_open_progress = float(state_dict.get("drawer_open_progress", 0.0))
	drawer_visual_ratio = float(state_dict.get("drawer_visual_ratio", 0.0))

	var raw_clutter: Array = state_dict.get("clutter_positions", [])
	if not raw_clutter.is_empty():
		clutter_positions.clear()
		for p in raw_clutter:
			clutter_positions.append(p as Vector2)

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
		elif drawer_visual_ratio > 0.0:
			_animate_tray_to_ratio(drawer_visual_ratio, false)
	elif occupied_by_peer_id != 0:
		if is_briefcase_container:
			_animate_tray_to_ratio(drawer_visual_ratio, false)
		else:
			var desired_z: float = lerpf(DRAWER_CLOSED_Z, DRAWER_OPEN_Z, drawer_visual_ratio)
			if not is_equal_approx(_tray_target_z, desired_z):
				_animate_tray_to_ratio(drawer_visual_ratio, false)

	_sync_back_to_briefcase_pickup()
	_rebuild_3d_interior()
	state_changed.emit()


# ==========================================
# Physical 3D Hollow Drawer & Multi-Layer Clutter Interior
# ==========================================

func norm_to_tray_local_xz(norm: Vector2) -> Vector2:
	return Vector2(
		lerpf(-0.33, 0.33, clampf(norm.x, 0.0, 1.0)),
		lerpf(-0.17, 0.17, clampf(norm.y, 0.0, 1.0))
	)


func tray_local_xz_to_norm(local_x: float, local_z: float) -> Vector2:
	return Vector2(
		clampf((local_x + 0.33) / 0.66, 0.05, 0.95),
		clampf((local_z + 0.17) / 0.34, 0.05, 0.95)
	)


func get_tray_node() -> Node3D:
	return _tray_drawer_node


func get_clutter_area_node(clutter_idx: int) -> Node3D:
	return _clutter_area_nodes.get(clutter_idx, null) as Node3D


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

			var light := OmniLight3D.new()
			light.name = "DrawerInteriorLight"
			light.position = Vector3(0.0, 0.55, 0.0)
			light.omni_range = 1.6
			light.light_energy = 0.85
			_tray_drawer_node.add_child(light)

	_contents_root = _tray_drawer_node.get_node_or_null("ContentsRoot") as Node3D
	if _contents_root == null:
		_contents_root = Node3D.new()
		_contents_root.name = "ContentsRoot"
		_tray_drawer_node.add_child(_contents_root)
	if is_briefcase_container:
		_apply_briefcase_lid_ratio(drawer_visual_ratio)


func _get_stored_item_tray_layout(item_id: String) -> Dictionary:
	match item_id.to_upper():
		"KEY":
			return {"scale": Vector3(0.70, 0.25, 0.55), "size": Vector3(0.126, 0.015, 0.165)}
		"MONEY":
			return {"scale": Vector3(0.50, 0.06, 0.50), "size": Vector3(0.160, 0.017, 0.160)}
		"PASSPORT":
			return {"scale": Vector3(0.72, 0.38, 0.72), "size": Vector3(0.130, 0.015, 0.173)}
		"PLANS":
			return {"scale": Vector3(0.16, 0.55, 0.55), "size": Vector3(0.198, 0.016, 0.055)}
		"BUCKET":
			return {"scale": Vector3(0.45, 0.06, 0.45), "size": Vector3(0.144, 0.017, 0.144)}
		"BOMB", "LIVE_BOMB":
			return {"scale": Vector3(0.50, 0.06, 0.50), "size": Vector3(0.140, 0.017, 0.140)}
		_:
			return {"scale": Vector3(0.72, 0.11, 0.72), "size": Vector3(0.158, 0.016, 0.158)}


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
		if not is_briefcase_container and to_local(world_hit).z < 0.34:
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
	_ensure_item_positions()
	_ensure_3d_tray_structure()
	if _contents_root == null:
		return

	_clutter_area_nodes.clear()
	for child in _contents_root.get_children():
		_contents_root.remove_child(child)
		child.queue_free()

	# 1. Front-Inside Lip Spring Trap (Both Drawers AND Briefcases!)
	if armed_spring or spring_unlatched or staged_spring_on_lip:
		var lip_area := Area3D.new()
		lip_area.name = "LipSpringTrap"
		lip_area.collision_layer = DRAWER_CONTENTS_MASK
		lip_area.collision_mask = 0
		lip_area.position = Vector3(0.0, 0.010, 0.145) if is_briefcase_container else Vector3(0.0, 0.055, 0.16)
		lip_area.set_meta("container_role", "lip_spring")
		var lip_size := Vector3(0.20, 0.055, 0.080) if is_briefcase_container else Vector3(0.242, 0.059, 0.092)
		lip_area.set_meta("exact_aabb", AABB(-lip_size * 0.5, lip_size))

		var lip_col := CollisionShape3D.new()
		var lip_shape := BoxShape3D.new()
		lip_shape.size = lip_size
		lip_col.shape = lip_shape
		lip_area.add_child(lip_col)

		var spring_mesh := PICKUP_SCRIPT.build_item_mesh("SPRING")
		spring_mesh.scale = Vector3(0.88, 0.38, 0.36) if is_briefcase_container else Vector3(1.10, 0.42, 0.42)
		var mat: StandardMaterial3D = spring_mesh.material_override as StandardMaterial3D
		if mat != null:
			if armed_spring:
				mat.albedo_color = Color(0.95, 0.18, 0.18)
			elif spring_unlatched:
				mat.albedo_color = Color(0.22, 0.82, 0.72)
			else:
				mat.albedo_color = Color(0.95, 0.65, 0.18)
		lip_area.add_child(spring_mesh)
		_contents_root.add_child(lip_area)

	# 2. Lit or Planted Time Bomb in Tray (Layer 0 in Briefcase so Objectives can layer cleanly above)
	if live_bomb_lit or armed_bomb or staged_bomb_in_tray:
		var bomb_area := Area3D.new()
		bomb_area.name = "TrayTimeBomb"
		bomb_area.collision_layer = DRAWER_CONTENTS_MASK
		bomb_area.collision_mask = 0
		if is_briefcase_container:
			var b_xz: Vector2 = BRIEFCASE_BUILDER.norm_to_briefcase_local_xz(bomb_norm_pos)
			bomb_area.position = Vector3(b_xz.x, BRIEFCASE_BUILDER.BOMB_LAYER_Y, b_xz.y)
		else:
			bomb_area.position = Vector3(0.0, -0.015, -0.04)
		bomb_area.set_meta("container_role", "lit_bomb" if live_bomb_lit else "planted_bomb")
		bomb_area.set_meta("base_y", bomb_area.position.y)
		var bomb_size := Vector3(0.14, 0.018, 0.14) if is_briefcase_container else Vector3(0.16, 0.16, 0.16)
		bomb_area.set_meta("exact_aabb", AABB(-bomb_size * 0.5, bomb_size))

		var bomb_col := CollisionShape3D.new()
		var bomb_shape := BoxShape3D.new()
		bomb_shape.size = bomb_size
		bomb_col.shape = bomb_shape
		bomb_area.add_child(bomb_col)

		var bomb_mesh := PICKUP_SCRIPT.build_item_mesh("LIVE_BOMB" if live_bomb_lit else "BOMB")
		bomb_mesh.scale = Vector3(0.48, 0.06, 0.48) if is_briefcase_container else Vector3(0.55, 0.55, 0.55)
		bomb_area.add_child(bomb_mesh)
		_contents_root.add_child(bomb_area)

	# 3. Stored Objectives & Gadgets — Freeform XZ + Disjoint Vertical Layers in Briefcase
	for i in range(stored_items.size()):
		var item_id: String = str(stored_items[i]).to_upper()
		var xz := Vector2.ZERO
		var item_y: float = -0.048
		if is_briefcase_container:
			var fallback_norm: Vector2 = BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS[i % BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS.size()]
			var norm_pos: Vector2 = item_positions.get(item_id, fallback_norm) as Vector2
			xz = BRIEFCASE_BUILDER.norm_to_briefcase_local_xz(norm_pos)
			item_y = BRIEFCASE_BUILDER.get_item_layer_y(i)
		else:
			xz = norm_to_tray_local_xz(ITEM_TRAY_POSITIONS[i % ITEM_TRAY_POSITIONS.size()])
		var layout: Dictionary = _get_stored_item_tray_layout(item_id)
		var exact_size: Vector3 = layout["size"] as Vector3

		var item_area := Area3D.new()
		item_area.name = "TrayItem_%d_%s" % [i, item_id]
		item_area.collision_layer = DRAWER_CONTENTS_MASK
		item_area.collision_mask = 0
		item_area.position = Vector3(xz.x, item_y, xz.y)
		item_area.set_meta("container_role", "loot_item")
		item_area.set_meta("item_id", item_id)
		item_area.set_meta("base_y", item_y)
		item_area.set_meta("exact_aabb", AABB(-exact_size * 0.5, exact_size))

		var item_col := CollisionShape3D.new()
		var item_shape := BoxShape3D.new()
		item_shape.size = exact_size
		item_col.shape = item_shape
		item_area.add_child(item_col)

		var item_mesh := PICKUP_SCRIPT.build_item_mesh(item_id)
		item_mesh.scale = layout["scale"] as Vector3
		item_area.add_child(item_mesh)
		if PICKUP_SCRIPT.is_objective_item(item_id):
			var glint: CPUParticles3D = PICKUP_SCRIPT.create_objective_glint_particles(true)
			glint.position = Vector3(0.0, 0.007, 0.0)
			item_area.add_child(glint)
		_contents_root.add_child(item_area)

	# 4. Upper Layers — Strictly Disjoint Vertical Y Strata (Zero Clipping)
	for i in range(clutter_positions.size()):
		var spec: Dictionary = CLUTTER_PROP_SPECS[i % CLUTTER_PROP_SPECS.size()]
		@warning_ignore("integer_division")
		var stack_pass: int = i / CLUTTER_PROP_SPECS.size()
		var base_y: float = float(spec["base_y"]) + float(stack_pass) * 0.055
		var c_size: Vector3 = spec["size"] as Vector3
		var xz: Vector2 = norm_to_tray_local_xz(clutter_positions[i])

		var clutter_area := Area3D.new()
		clutter_area.name = "ClutterProp_%d" % i
		clutter_area.collision_layer = DRAWER_CONTENTS_MASK
		clutter_area.collision_mask = 0
		clutter_area.position = Vector3(xz.x, base_y, xz.y)
		var yaw_deg: float = [-7.0, 6.0, 11.0, -9.0, 4.0, -12.0][i % 6]
		clutter_area.rotation.y = deg_to_rad(yaw_deg)
		clutter_area.set_meta("container_role", "clutter")
		clutter_area.set_meta("clutter_idx", i)
		clutter_area.set_meta("base_y", base_y)
		clutter_area.set_meta("exact_aabb", AABB(-c_size * 0.5, c_size))

		var c_col := CollisionShape3D.new()
		var c_shape := BoxShape3D.new()
		c_shape.size = c_size
		c_col.shape = c_shape
		clutter_area.add_child(c_col)

		_build_3d_clutter_prop(clutter_area, i)
		_contents_root.add_child(clutter_area)
		_clutter_area_nodes[i] = clutter_area

	if is_briefcase_container:
		_apply_briefcase_lid_ratio(drawer_visual_ratio)


func _build_3d_clutter_prop(parent_area: Area3D, idx: int) -> void:
	var spec: Dictionary = CLUTTER_PROP_SPECS[idx % CLUTTER_PROP_SPECS.size()]
	var main_box := BoxMesh.new()
	main_box.size = spec["size"] as Vector3
	var main_mat := StandardMaterial3D.new()
	main_mat.albedo_color = spec["color"] as Color

	var base_mi := MeshInstance3D.new()
	base_mi.mesh = main_box
	base_mi.material_override = main_mat
	parent_area.add_child(base_mi)

	var accent_box := BoxMesh.new()
	accent_box.size = spec["acc_size"] as Vector3
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = spec["acc_color"] as Color

	var acc_mi := MeshInstance3D.new()
	acc_mi.mesh = accent_box
	acc_mi.material_override = accent_mat
	acc_mi.position = spec["acc_pos"] as Vector3
	parent_area.add_child(acc_mi)


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
