@tool
class_name SpyInventoryComponent
extends Node

## Physical Left Hand + 3-Slot Inner Trenchcoat Jacket + Personal Club Inventory (Doc 2 v1.2 §4).
## Server-authoritative state component attached to each SpyCharacter.

const JACKET_SLOT_COUNT: int = 3
const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")

enum RightHandMode {
	JACKET_SLOT = 0,
	CLUB = 1,
	LIVE_BOMB = 2
}

var left_hand_item_id: String = "NONE"
var briefcase_objectives: Array[String] = []
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


func pickup_item(new_item_id: String, extra_briefcase_items: Array = []) -> Dictionary:
	var id: String = new_item_id.to_upper()
	var result: Dictionary = {
		"picked": false,
		"dropped_item_id": "NONE",
		"dropped_briefcase_items": [] as Array[String]
	}

	if PICKUP_SCRIPT.is_objective_item(id):
		if left_hand_item_id == "NONE":
			left_hand_item_id = id
			result["picked"] = true
		elif left_hand_item_id == "BRIEFCASE":
			if not (id in briefcase_objectives) and briefcase_objectives.size() < 4:
				briefcase_objectives.append(id)
			result["picked"] = true
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

		if left_hand_item_id == "NONE":
			briefcase_objectives = merged
			left_hand_item_id = "BRIEFCASE"
			result["picked"] = true
		elif PICKUP_SCRIPT.is_objective_item(left_hand_item_id):
			if not (left_hand_item_id in merged) and merged.size() < 4:
				merged.append(left_hand_item_id)
			briefcase_objectives = merged
			left_hand_item_id = "BRIEFCASE"
			result["picked"] = true
		elif left_hand_item_id == "BRIEFCASE":
			result["dropped_item_id"] = "BRIEFCASE"
			result["dropped_briefcase_items"] = briefcase_objectives.duplicate()
			briefcase_objectives = merged
			left_hand_item_id = "BRIEFCASE"
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
		"dropped_briefcase_items": [] as Array[String]
	}
	if left_hand_item_id == "NONE":
		return result

	result["dropped_item_id"] = left_hand_item_id
	if left_hand_item_id == "BRIEFCASE":
		result["dropped_briefcase_items"] = briefcase_objectives.duplicate()
		briefcase_objectives.clear()
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


func start_club_charge() -> Dictionary:
	var result: Dictionary = {
		"dropped_item_id": "NONE",
		"dropped_briefcase_items": [] as Array[String]
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


func apply_sync_state(l_item: String, b_objs: Array, j_slots: Array, a_slot: int, r_mode: int, charging: bool) -> void:
	left_hand_item_id = l_item.to_upper() if not l_item.is_empty() else "NONE"
	briefcase_objectives.clear()
	for obj in b_objs:
		briefcase_objectives.append(str(obj).to_upper())

	jacket_slots = ["NONE", "NONE", "NONE"]
	for i in range(mini(j_slots.size(), JACKET_SLOT_COUNT)):
		var s: String = str(j_slots[i]).to_upper()
		jacket_slots[i] = s if not s.is_empty() else "NONE"

	active_jacket_slot = clampi(a_slot, 0, JACKET_SLOT_COUNT - 1)
	right_hand_mode = r_mode
	is_charging_club = charging
