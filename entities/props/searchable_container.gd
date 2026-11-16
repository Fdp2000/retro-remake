@tool
class_name SearchableContainer
extends StaticBody3D

## Unified Searchable Container for Desk Drawers, Filing Cabinets & Dropped Briefcases (Doc 3 §3 & §4).
## Enforces single-user lock, +10s first-visit bonus, Tap-E vs Hold-E asymmetric trap triggers,
## draggable clutter persistence, and Top-Down Container View RPC synchronization.

signal state_changed()

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const DEFAULT_CLUTTER_POSITIONS: Array[Vector2] = [
	Vector2(0.36, 0.40),
	Vector2(0.56, 0.44),
	Vector2(0.44, 0.60),
	Vector2(0.62, 0.56),
	Vector2(0.48, 0.34)
]

@export var container_id: String = "Drawer"
@export var is_briefcase_container: bool = false
@export var clutter_count: int = 4
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
var linked_briefcase_pickup: Node = null

var _occupant_player_override: Node = null
var _tray_drawer_node: Node3D = null
var _top_down_vantage: Marker3D = null
var _slide_tween: Tween = null


func _ready() -> void:
	if not is_briefcase_container:
		collision_layer = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3
	else:
		collision_layer = 0
	collision_mask = 0
	_init_clutter_if_empty()
	_tray_drawer_node = get_node_or_null("TrayPivot") as Node3D
	_top_down_vantage = get_node_or_null("TopDownVantage") as Marker3D


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


func get_interaction_prompt() -> String:
	if occupied_by_peer_id != 0:
		return "[IN USE]"
	if is_briefcase_container:
		return "[Hold E] Inspect Briefcase"
	return "[Tap E] Fast Slam Drawer  |  [Hold E] Slow Peek"


func get_hold_interaction_duration() -> float:
	return GameConfig.drawer_slow_peek_hold_time if GameConfig != null else 0.70


func get_top_down_camera_transform() -> Transform3D:
	if _top_down_vantage != null and is_inside_tree():
		return _top_down_vantage.global_transform
	var origin: Vector3 = global_position + Vector3(0.0, 1.45, 0.35)
	var look_target: Vector3 = global_position + Vector3(0.0, 0.55, 0.35)
	return Transform3D(Basis.looking_at((look_target - origin).normalized(), -global_transform.basis.z), origin)


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


func request_loot_item(caller_peer_id: int, item_id: String, target_slot: int = -1) -> void:
	if _is_peer_connected():
		_server_loot_item.rpc_id(1, caller_peer_id, item_id, target_slot)
	else:
		loot_item_to_player(caller_peer_id, item_id, target_slot)


func request_plant_trap(caller_peer_id: int, slot_index: int, target_zone: String) -> void:
	if _is_peer_connected():
		_server_plant_trap.rpc_id(1, caller_peer_id, slot_index, target_zone)
	else:
		plant_trap_from_jacket(caller_peer_id, slot_index, target_zone)


func request_grab_lit_bomb(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_grab_lit_bomb.rpc_id(1, caller_peer_id)
	else:
		grab_lit_bomb(caller_peer_id)


# ==========================================
# Core Authoritative Operations
# ==========================================

func open_container(peer_id: int, is_slow_peek: bool, player_override: Node = null) -> Dictionary:
	_init_clutter_if_empty()
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

	if not is_slow_peek and not is_briefcase_container and AudioBridge != null:
		var slam_rad: float = GameConfig.audio_radius_drawer_fast if GameConfig != null else 10.0
		AudioBridge.request_world_cue("drawer_slam", _safe_global_pos(), slam_rad, peer_id)

	# 1. Armed Spring Check (Doc 3 §3.B)
	if armed_spring and not is_briefcase_container:
		if not is_slow_peek:
			armed_spring = false
			spring_unlatched = false
			var owner_id: int = spring_owner_peer_id
			spring_owner_peer_id = 0
			if AudioBridge != null:
				AudioBridge.request_world_cue("spring_trigger", _safe_global_pos(), 10.0, owner_id)
			if player != null and player.has_method("apply_trap_ko"):
				player.apply_trap_ko("SPRING", owner_id)
			elif player != null and player.has_method("force_drop_all_hands"):
				player.force_drop_all_hands()
			_sync_state_to_peers()
			result["reason"] = "SPRING_KO"
			result["triggered_spring"] = true
			return result
		else:
			spring_unlatched = false

	# 2. Armed Time Bomb Check (Doc 3 §3.B & Doc 4 §3.4)
	if armed_bomb:
		armed_bomb = false
		live_bomb_lit = true
		var min_f: float = GameConfig.time_bomb_fuse_min if GameConfig != null else 2.5
		var max_f: float = GameConfig.time_bomb_fuse_max if GameConfig != null else 4.0
		var base_fuse: float = randf_range(min_f, max_f)
		if is_slow_peek:
			var peek_burn: float = GameConfig.drawer_slow_peek_hold_time if GameConfig != null else 0.70
			live_bomb_fuse_remaining = maxf(base_fuse - peek_burn, 0.5)
		else:
			live_bomb_fuse_remaining = base_fuse
		if AudioBridge != null:
			var fuse_rad: float = GameConfig.audio_radius_bomb_fuse if GameConfig != null else 10.0
			AudioBridge.request_world_cue("bomb_hiss", _safe_global_pos(), fuse_rad, bomb_owner_peer_id)
		result["lit_bomb"] = true

	# 3. First-Visit Exploration Bonus (+10s — Doc 3 §3.A)
	if not is_briefcase_container and not searched_by_peers.has(peer_id):
		searched_by_peers[peer_id] = true
		result["awarded_bonus"] = true
		if MatchManager != null:
			if MatchManager.match_state != MatchManager.MatchState.IN_PROGRESS:
				MatchManager.start_new_match([1, 2])
			MatchManager.award_first_search_bonus(peer_id)

	occupied_by_peer_id = peer_id
	_occupant_player_override = player_override
	_animate_tray_open(true, is_slow_peek)
	_sync_state_to_peers()

	if player != null and player.has_method("enter_container_view"):
		player.enter_container_view(self)

	result["opened"] = true
	result["reason"] = "OK"
	return result


func close_container(peer_id: int, player_override: Node = null) -> void:
	if occupied_by_peer_id != 0 and occupied_by_peer_id != peer_id:
		return

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

	if not live_bomb_lit:
		_animate_tray_open(false, false)

	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()

	var player: Node = cached_player if cached_player != null else _find_player_node(prev_occupant)
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
	if occupied_by_peer_id != peer_id or not spring_unlatched or is_briefcase_container:
		return false
	spring_unlatched = false
	staged_spring_on_lip = true
	spring_owner_peer_id = peer_id
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("trap_arm", _safe_global_pos(), GameConfig.audio_radius_trap_setup, peer_id)
	_sync_state_to_peers()
	return true


func loot_item_to_player(peer_id: int, item_id: String, target_jacket_slot: int = -1, player_override: Node = null) -> bool:
	if occupied_by_peer_id != peer_id:
		return false
	var upper: String = item_id.to_upper()
	var idx: int = stored_items.find(upper)
	if idx == -1:
		return false

	var player: Node = player_override if player_override != null else (_occupant_player_override if _occupant_player_override != null else _find_player_node(peer_id))
	if player == null:
		return false

	if not _give_item_to_player(player, upper, target_jacket_slot):
		return false

	stored_items.remove_at(idx)
	_sync_back_to_briefcase_pickup()
	_sync_state_to_peers()
	return true


func plant_trap_from_jacket(peer_id: int, slot_index: int, target_zone: String, player_override: Node = null) -> bool:
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

	if trap_id == "SPRING" and zone == "LIP" and not is_briefcase_container and not armed_spring and not staged_spring_on_lip and not spring_unlatched:
		_consume_jacket_slot(player, slot_index)
		staged_spring_on_lip = true
		spring_owner_peer_id = peer_id
		if AudioBridge != null and GameConfig != null:
			AudioBridge.request_world_cue("trap_arm", _safe_global_pos(), GameConfig.audio_radius_trap_setup, peer_id)
		_sync_state_to_peers()
		return true

	if trap_id == "BOMB" and zone == "TRAY" and not armed_bomb and not staged_bomb_in_tray and not live_bomb_lit:
		_consume_jacket_slot(player, slot_index)
		staged_bomb_in_tray = true
		bomb_owner_peer_id = peer_id
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
		linked_briefcase_pickup.set("armed_bomb", armed_bomb or staged_bomb_in_tray)
		linked_briefcase_pickup.set("bomb_owner_peer_id", bomb_owner_peer_id)


func _animate_tray_open(open_state: bool, slow: bool) -> void:
	if _tray_drawer_node == null:
		return
	var target_z: float = 0.42 if open_state else 0.0
	var dur: float = 0.0
	if open_state:
		dur = (GameConfig.drawer_slow_peek_hold_time if GameConfig != null else 0.70) if slow else (GameConfig.drawer_fast_slam_duration if GameConfig != null else 0.15)
	else:
		dur = GameConfig.drawer_close_duration if GameConfig != null else 0.25

	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if is_inside_tree() and dur > 0.0:
		_slide_tween = create_tween()
		_slide_tween.tween_property(_tray_drawer_node, "position:z", target_z, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_tray_drawer_node.position.z = target_z


# ==========================================
# RPC Bridge & State Synchronization
# ==========================================

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
func _server_loot_item(caller_peer_id: int, item_id: String, target_slot: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	loot_item_to_player(caller_peer_id, item_id, target_slot)


@rpc("any_peer", "call_local", "reliable")
func _server_plant_trap(caller_peer_id: int, slot_index: int, target_zone: String) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	plant_trap_from_jacket(caller_peer_id, slot_index, target_zone)


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
		"armed_spring": armed_spring,
		"spring_unlatched": spring_unlatched,
		"staged_spring_on_lip": staged_spring_on_lip,
		"armed_bomb": armed_bomb,
		"staged_bomb_in_tray": staged_bomb_in_tray,
		"live_bomb_lit": live_bomb_lit,
		"live_bomb_fuse_remaining": live_bomb_fuse_remaining,
		"occupied_by_peer_id": occupied_by_peer_id,
		"clutter_positions": clutter_positions.duplicate()
	}
	if _is_peer_connected():
		_rpc_sync_container_state.rpc(state_dict)
	else:
		state_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_container_state(state_dict: Dictionary) -> void:
	var prev_occ: int = occupied_by_peer_id
	stored_items.clear()
	for it in state_dict.get("stored_items", []):
		stored_items.append(str(it))
	armed_spring = bool(state_dict.get("armed_spring", false))
	spring_unlatched = bool(state_dict.get("spring_unlatched", false))
	staged_spring_on_lip = bool(state_dict.get("staged_spring_on_lip", false))
	armed_bomb = bool(state_dict.get("armed_bomb", false))
	staged_bomb_in_tray = bool(state_dict.get("staged_bomb_in_tray", false))
	live_bomb_lit = bool(state_dict.get("live_bomb_lit", false))
	live_bomb_fuse_remaining = float(state_dict.get("live_bomb_fuse_remaining", 0.0))
	occupied_by_peer_id = int(state_dict.get("occupied_by_peer_id", 0))

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
		_animate_tray_open(occupied_by_peer_id != 0, false)

	state_changed.emit()


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
