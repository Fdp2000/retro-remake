@tool
class_name SpyInventoryComponent
extends Node

## Physical Left Hand + 3-Slot Inner Trenchcoat Jacket + Personal Club Inventory (Doc 2 v1.2 §4)
## Server-authoritative state component attached to each SpyCharacter.

const JACKET_SLOT_COUNT: int = 3
const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const BRIEFCASE_BUILDER = preload("res://entities/props/briefcase_visual_builder.gd")

enum RightHandMode {
	JACKET_SLOT = 0,
	CLUB = 1,
	LIVE_BOMB = 2
}

var left_hand_item_id: String = "NONE"
var briefcase_objectives: Array[String] = []
var briefcase_item_positions: Dictionary = {} # String item_id -> Vector2 norm [0.08..0.92]
var briefcase_bomb_norm_pos: Vector2 = BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
var briefcase_armed_spring: bool = false
var briefcase_spring_owner_id: int = 0
var briefcase_spring_unlatched: bool = false
var briefcase_staged_spring: bool = false
var briefcase_armed_bomb: bool = false
var briefcase_bomb_owner_id: int = 0
var briefcase_staged_bomb: bool = false
var briefcase_live_bomb_lit: bool = false
var briefcase_live_bomb_fuse_remaining: float = 0.0

var jacket_slots: Array[String] = ["NONE", "NONE", "NONE"]
var active_jacket_slot: int = 0
var right_hand_mode: int = RightHandMode.JACKET_SLOT
var is_charging_club: bool = false


func get_active_right_item_id() -> String:
	if right_hand_mode == RightHandMode.CLUB:
		return "CLUB"
	if right_hand_mode == RightHandMode.LIVE_BOMB:
		return "LIVE_BOMB"
	var idx: int = clampi(active_jacket_slot, 0, JACKET_SLOT_COUNT - 1)
	if idx < jacket_slots.size():
		return jacket_slots[idx]
	return "NONE"


func get_filled_jacket_slot_count() -> int:
	var count: int = 0
	for slot_item in jacket_slots:
		if slot_item != "NONE" and not slot_item.is_empty():
			count += 1
	return count


func ensure_briefcase_item_positions() -> void:
	var next_positions: Dictionary = {}
	for i in range(briefcase_objectives.size()):
		var obj_id: String = str(briefcase_objectives[i]).to_upper()
		if briefcase_item_positions.has(obj_id) and briefcase_item_positions[obj_id] is Vector2:
			next_positions[obj_id] = BRIEFCASE_BUILDER.clamp_norm(briefcase_item_positions[obj_id] as Vector2)
		else:
			next_positions[obj_id] = BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS[i % BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS.size()]
	briefcase_item_positions = next_positions


func set_briefcase_item_position(obj_id: String, norm_pos: Vector2) -> bool:
	var upper: String = obj_id.to_upper()
	if left_hand_item_id != "BRIEFCASE" or not (upper in briefcase_objectives):
		return false
	briefcase_item_positions[upper] = BRIEFCASE_BUILDER.clamp_norm(norm_pos)
	return true


func set_briefcase_bomb_position(norm_pos: Vector2) -> void:
	briefcase_bomb_norm_pos = BRIEFCASE_BUILDER.clamp_norm(norm_pos)


func pack_objective_into_briefcase(obj_id: String, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> bool:
	var upper: String = obj_id.to_upper()
	if left_hand_item_id != "BRIEFCASE" or not PICKUP_SCRIPT.is_objective_item(upper):
		return false
	if (upper in briefcase_objectives) or briefcase_objectives.size() >= 4:
		return false
	briefcase_objectives.append(upper)
	if norm_pos.x >= 0.0 and norm_pos.y >= 0.0:
		briefcase_item_positions[upper] = BRIEFCASE_BUILDER.clamp_norm(norm_pos)
	ensure_briefcase_item_positions()
	return true


func remove_objective_from_briefcase(obj_id: String) -> bool:
	var upper: String = obj_id.to_upper()
	if left_hand_item_id != "BRIEFCASE":
		return false
	var idx: int = briefcase_objectives.find(upper)
	if idx == -1:
		return false
	briefcase_objectives.remove_at(idx)
	briefcase_item_positions.erase(upper)
	return true


func take_left_hand_objective() -> String:
	if not PICKUP_SCRIPT.is_objective_item(left_hand_item_id):
		return "NONE"
	var taken: String = left_hand_item_id
	left_hand_item_id = "NONE"
	return taken


func put_left_hand_objective(obj_id: String) -> bool:
	var upper: String = obj_id.to_upper()
	if left_hand_item_id != "NONE" or not PICKUP_SCRIPT.is_objective_item(upper):
		return false
	left_hand_item_id = upper
	return true


func swap_left_hand_objective(new_obj_id: String) -> String:
	var upper: String = new_obj_id.to_upper()
	if not PICKUP_SCRIPT.is_objective_item(upper):
		return "NONE"
	if not PICKUP_SCRIPT.is_objective_item(left_hand_item_id):
		return "NONE"
	var prev: String = left_hand_item_id
	left_hand_item_id = upper
	return prev


func commit_briefcase_staged_traps() -> void:
	if briefcase_staged_spring:
		briefcase_staged_spring = false
		briefcase_armed_spring = true
	if briefcase_staged_bomb:
		briefcase_staged_bomb = false
		briefcase_armed_bomb = true


func clear_briefcase_trap_state() -> void:
	briefcase_armed_spring = false
	briefcase_spring_owner_id = 0
	briefcase_spring_unlatched = false
	briefcase_staged_spring = false
	briefcase_armed_bomb = false
	briefcase_bomb_owner_id = 0
	briefcase_staged_bomb = false
	briefcase_live_bomb_lit = false
	briefcase_live_bomb_fuse_remaining = 0.0
	briefcase_bomb_norm_pos = BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
	if left_hand_item_id != "BRIEFCASE":
		briefcase_item_positions.clear()


func _extract_briefcase_drop_into_result(result: Dictionary) -> void:
	result["dropped_item_id"] = "BRIEFCASE"
	result["dropped_briefcase_items"] = briefcase_objectives.duplicate()
	result["dropped_briefcase_item_positions"] = briefcase_item_positions.duplicate()
	result["dropped_briefcase_bomb_pos"] = briefcase_bomb_norm_pos
	result["dropped_briefcase_armed_spring"] = briefcase_armed_spring or briefcase_staged_spring
	result["dropped_briefcase_spring_owner"] = briefcase_spring_owner_id
	result["dropped_briefcase_armed_bomb"] = briefcase_armed_bomb or briefcase_staged_bomb
	result["dropped_briefcase_bomb_owner"] = briefcase_bomb_owner_id
	briefcase_objectives = [] as Array[String]
	briefcase_item_positions.clear()
	clear_briefcase_trap_state()


func pickup_item(
	new_item_id: String,
	extra_briefcase_items: Array = [],
	extra_briefcase_positions: Dictionary = {}
) -> Dictionary:
	var id: String = new_item_id.to_upper()
	var result: Dictionary = {
		"picked": false,
		"dropped_item_id": "NONE",
		"dropped_briefcase_items": [] as Array[String],
		"dropped_briefcase_item_positions": {},
		"dropped_briefcase_bomb_pos": BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS,
		"dropped_briefcase_armed_spring": false,
		"dropped_briefcase_spring_owner": 0,
		"dropped_briefcase_armed_bomb": false,
		"dropped_briefcase_bomb_owner": 0
	}

	if PICKUP_SCRIPT.is_objective_item(id):
		if left_hand_item_id == "NONE":
			left_hand_item_id = id
			result["picked"] = true
		elif left_hand_item_id == "BRIEFCASE":
			_extract_briefcase_drop_into_result(result)
			left_hand_item_id = id
			result["picked"] = true
		elif left_hand_item_id == id:
			result["picked"] = false
		else:
			result["dropped_item_id"] = left_hand_item_id
			left_hand_item_id = id
			result["picked"] = true
		return result

	if PICKUP_SCRIPT.is_briefcase_item(id):
		var merged: Array[String] = []
		for obj in extra_briefcase_items:
			var obj_str: String = str(obj).to_upper()
			if PICKUP_SCRIPT.is_objective_item(obj_str) and not (obj_str in merged):
				merged.append(obj_str)

		var incoming_positions: Dictionary = {}
		for k in extra_briefcase_positions.keys():
			var key_upper: String = str(k).to_upper()
			if (key_upper in merged) and extra_briefcase_positions[k] is Vector2:
				incoming_positions[key_upper] = BRIEFCASE_BUILDER.clamp_norm(extra_briefcase_positions[k] as Vector2)

		if left_hand_item_id == "NONE":
			clear_briefcase_trap_state()
			briefcase_objectives = merged
			briefcase_item_positions = incoming_positions
			left_hand_item_id = "BRIEFCASE"
			ensure_briefcase_item_positions()
			result["picked"] = true
		elif PICKUP_SCRIPT.is_objective_item(left_hand_item_id):
			if not (left_hand_item_id in merged) and merged.size() < 4:
				merged.append(left_hand_item_id)
			clear_briefcase_trap_state()
			briefcase_objectives = merged
			briefcase_item_positions = incoming_positions
			left_hand_item_id = "BRIEFCASE"
			ensure_briefcase_item_positions()
			result["picked"] = true
		elif left_hand_item_id == "BRIEFCASE":
			_extract_briefcase_drop_into_result(result)
			briefcase_objectives = merged
			briefcase_item_positions = incoming_positions
			left_hand_item_id = "BRIEFCASE"
			ensure_briefcase_item_positions()
			result["picked"] = true
		return result

	# Hot-Potato Live Time Bomb Exception: cannot be stowed inside Inner Jacket Slots (Doc 2 §4.A, Doc 4 §3.4)
	if id == "LIVE_BOMB":
		is_charging_club = false
		if right_hand_mode == RightHandMode.LIVE_BOMB:
			result["dropped_item_id"] = "LIVE_BOMB"
		right_hand_mode = RightHandMode.LIVE_BOMB
		result["picked"] = true
		return result

	if PICKUP_SCRIPT.is_gadget_item(id):
		is_charging_club = false
		var empty_idx: int = -1
		for i in range(JACKET_SLOT_COUNT):
			if jacket_slots[i] == "NONE":
				empty_idx = i
				break

		if empty_idx != -1:
			jacket_slots[empty_idx] = id
			active_jacket_slot = empty_idx
			if right_hand_mode == RightHandMode.LIVE_BOMB:
				result["dropped_item_id"] = "LIVE_BOMB"
			right_hand_mode = RightHandMode.JACKET_SLOT
			result["picked"] = true
		else:
			var slot_idx: int = clampi(active_jacket_slot, 0, JACKET_SLOT_COUNT - 1)
			result["dropped_item_id"] = jacket_slots[slot_idx]
			jacket_slots[slot_idx] = id
			right_hand_mode = RightHandMode.JACKET_SLOT
			result["picked"] = true
		return result

	return result


func select_jacket_slot(slot_index: int) -> bool:
	if right_hand_mode == RightHandMode.LIVE_BOMB:
		return false
	active_jacket_slot = clampi(slot_index, 0, JACKET_SLOT_COUNT - 1)
	is_charging_club = false
	right_hand_mode = RightHandMode.JACKET_SLOT
	return true


func cycle_jacket_slot(step: int) -> bool:
	return select_jacket_slot(posmod(active_jacket_slot + step, JACKET_SLOT_COUNT))


func toggle_personal_club() -> Dictionary:
	var result: Dictionary = {
		"dropped_item_id": "NONE",
		"dropped_briefcase_items": [] as Array[String]
	}
	if right_hand_mode == RightHandMode.CLUB:
		is_charging_club = false
		right_hand_mode = RightHandMode.JACKET_SLOT
		return result

	if right_hand_mode == RightHandMode.LIVE_BOMB:
		result["dropped_item_id"] = "LIVE_BOMB"

	is_charging_club = false
	right_hand_mode = RightHandMode.CLUB
	return result


func drop_left_hand_item() -> Dictionary:
	var result: Dictionary = {
		"dropped_item_id": "NONE",
		"dropped_briefcase_items": [] as Array[String],
		"dropped_briefcase_item_positions": {},
		"dropped_briefcase_bomb_pos": BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS,
		"dropped_briefcase_armed_spring": false,
		"dropped_briefcase_spring_owner": 0,
		"dropped_briefcase_armed_bomb": false,
		"dropped_briefcase_bomb_owner": 0
	}
	if left_hand_item_id == "NONE":
		return result

	result["dropped_item_id"] = left_hand_item_id
	if left_hand_item_id == "BRIEFCASE":
		_extract_briefcase_drop_into_result(result)
	left_hand_item_id = "NONE"
	return result


func drop_right_hand_item() -> Dictionary:
	var result: Dictionary = {
		"dropped_item_id": "NONE",
		"dropped_briefcase_items": [] as Array[String]
	}
	if right_hand_mode == RightHandMode.CLUB:
		return result
	if right_hand_mode == RightHandMode.LIVE_BOMB:
		result["dropped_item_id"] = "LIVE_BOMB"
		right_hand_mode = RightHandMode.JACKET_SLOT
		return result

	var slot_idx: int = clampi(active_jacket_slot, 0, JACKET_SLOT_COUNT - 1)
	var cur: String = jacket_slots[slot_idx]
	if cur != "NONE":
		jacket_slots[slot_idx] = "NONE"
		result["dropped_item_id"] = cur
	return result


func consume_active_jacket_slot(expected_id: String = "") -> String:
	if right_hand_mode != RightHandMode.JACKET_SLOT:
		return "NONE"
	var slot_idx: int = clampi(active_jacket_slot, 0, JACKET_SLOT_COUNT - 1)
	var cur: String = jacket_slots[slot_idx]
	if cur == "NONE" or cur.is_empty():
		return "NONE"
	if expected_id != "" and cur != expected_id.to_upper():
		return "NONE"
	jacket_slots[slot_idx] = "NONE"
	return cur


func consume_live_bomb() -> bool:
	if right_hand_mode != RightHandMode.LIVE_BOMB:
		return false
	right_hand_mode = RightHandMode.JACKET_SLOT
	return true


func start_club_charge() -> Dictionary:
	var result: Dictionary = {
		"dropped_item_id": "NONE",
		"dropped_briefcase_items": [] as Array[String],
		"dropped_briefcase_item_positions": {},
		"dropped_briefcase_bomb_pos": BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS,
		"dropped_briefcase_armed_spring": false,
		"dropped_briefcase_spring_owner": 0,
		"dropped_briefcase_armed_bomb": false,
		"dropped_briefcase_bomb_owner": 0
	}
	if right_hand_mode != RightHandMode.CLUB:
		return result

	is_charging_club = true
	if left_hand_item_id == "BRIEFCASE":
		result = drop_left_hand_item()
	return result


func stop_club_charge() -> void:
	is_charging_club = false


func force_drop_all_hands() -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	is_charging_club = false

	var left_drop: Dictionary = drop_left_hand_item()
	if str(left_drop["dropped_item_id"]) != "NONE":
		drops.append(left_drop)

	if right_hand_mode == RightHandMode.LIVE_BOMB:
		drops.append({
			"dropped_item_id": "LIVE_BOMB",
			"dropped_briefcase_items": [] as Array[String]
		})

	for i in range(JACKET_SLOT_COUNT):
		if jacket_slots[i] != "NONE":
			drops.append({
				"dropped_item_id": jacket_slots[i],
				"dropped_briefcase_items": [] as Array[String],
				"jacket_slot": i
			})
			jacket_slots[i] = "NONE"

	right_hand_mode = RightHandMode.JACKET_SLOT
	active_jacket_slot = 0
	return drops


func get_briefcase_trap_dict() -> Dictionary:
	return {
		"armed_spring": briefcase_armed_spring,
		"spring_owner": briefcase_spring_owner_id,
		"spring_unlatched": briefcase_spring_unlatched,
		"staged_spring": briefcase_staged_spring,
		"armed_bomb": briefcase_armed_bomb,
		"bomb_owner": briefcase_bomb_owner_id,
		"staged_bomb": briefcase_staged_bomb,
		"live_bomb_lit": briefcase_live_bomb_lit,
		"live_bomb_fuse": briefcase_live_bomb_fuse_remaining,
		"item_positions": briefcase_item_positions.duplicate(),
		"bomb_norm_pos": briefcase_bomb_norm_pos
	}


func apply_sync_state(
	l_item: String,
	b_objs: Array,
	j_slots: Array,
	a_slot: int,
	r_mode: int,
	charging: bool,
	b_traps: Dictionary = {}
) -> void:
	left_hand_item_id = l_item.to_upper() if not l_item.is_empty() else "NONE"

	# Build a brand-new typed Array BEFORE replacing briefcase_objectives so call_local RPC
	# passing inv.briefcase_objectives by reference can NEVER clear its own source array!
	var next_objs: Array[String] = []
	for obj in b_objs:
		next_objs.append(str(obj).to_upper())
	briefcase_objectives = next_objs

	var next_slots: Array[String] = ["NONE", "NONE", "NONE"]
	for i in range(mini(j_slots.size(), JACKET_SLOT_COUNT)):
		var s: String = str(j_slots[i]).to_upper()
		next_slots[i] = s if not s.is_empty() else "NONE"
	jacket_slots = next_slots

	active_jacket_slot = clampi(a_slot, 0, JACKET_SLOT_COUNT - 1)
	right_hand_mode = r_mode
	is_charging_club = charging

	if not b_traps.is_empty():
		briefcase_armed_spring = bool(b_traps.get("armed_spring", false))
		briefcase_spring_owner_id = int(b_traps.get("spring_owner", 0))
		briefcase_spring_unlatched = bool(b_traps.get("spring_unlatched", false))
		briefcase_staged_spring = bool(b_traps.get("staged_spring", false))
		briefcase_armed_bomb = bool(b_traps.get("armed_bomb", false))
		briefcase_bomb_owner_id = int(b_traps.get("bomb_owner", 0))
		briefcase_staged_bomb = bool(b_traps.get("staged_bomb", false))
		briefcase_live_bomb_lit = bool(b_traps.get("live_bomb_lit", false))
		briefcase_live_bomb_fuse_remaining = float(b_traps.get("live_bomb_fuse", 0.0))

		var raw_positions: Variant = b_traps.get("item_positions", {})
		var next_positions: Dictionary = {}
		if raw_positions is Dictionary:
			for k in (raw_positions as Dictionary).keys():
				var pos_val: Variant = (raw_positions as Dictionary)[k]
				if pos_val is Vector2:
					next_positions[str(k).to_upper()] = BRIEFCASE_BUILDER.clamp_norm(pos_val as Vector2)
		briefcase_item_positions = next_positions

		var raw_bomb_pos: Variant = b_traps.get("bomb_norm_pos", BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS)
		if raw_bomb_pos is Vector2:
			briefcase_bomb_norm_pos = BRIEFCASE_BUILDER.clamp_norm(raw_bomb_pos as Vector2)
		else:
			briefcase_bomb_norm_pos = BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
	elif left_hand_item_id != "BRIEFCASE":
		briefcase_item_positions.clear()
		clear_briefcase_trap_state()

	if left_hand_item_id == "BRIEFCASE":
		ensure_briefcase_item_positions()
