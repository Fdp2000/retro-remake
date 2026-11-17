@tool
class_name TopDownContainerUI
extends Control

## Minimal Non-Blocking HUD Strip for 3D Top-Down Container View (Doc 3 §4).
## Leaves the 3D drawer completely unobstructed for direct 3D raycast dragging & looting,
## while showing Left Hand status, instructions, Push All Clutter Aside, and 3-Slot Jacket trap actions.

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")

var _player: Node = null
var _container: Node = null
var _local_peer_id: int = 1

var _title_label: Label = null
var _push_clutter_btn: Button = null
var _left_item_label: Label = null
var _container_status_label: Label = null
var _jacket_slots_box: VBoxContainer = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func _process(_delta: float) -> void:
	if not visible or _container == null or not is_instance_valid(_container):
		return
	if _container_status_label != null and bool(_container.get("live_bomb_lit")):
		var rem: float = float(_container.get("live_bomb_fuse_remaining"))
		_container_status_label.modulate = Color(1.0, 0.30, 0.15)
		_container_status_label.text = "LIT BOMB! (%.1fs) — Click 3D Bomb to Grab!" % rem


func open_for_container(player_node: Node, container_node: Node, peer_id: int) -> void:
	_player = player_node
	_local_peer_id = peer_id
	if _container != null and is_instance_valid(_container) and _container.has_signal("state_changed"):
		if _container.state_changed.is_connected(refresh_view):
			_container.state_changed.disconnect(refresh_view)

	_container = container_node
	if _container != null and _container.has_signal("state_changed"):
		if not _container.state_changed.is_connected(refresh_view):
			_container.state_changed.connect(refresh_view)

	visible = true
	refresh_view()


func close_view() -> void:
	if _container != null and is_instance_valid(_container) and _container.has_signal("state_changed"):
		if _container.state_changed.is_connected(refresh_view):
			_container.state_changed.disconnect(refresh_view)
	_container = null
	visible = false


func refresh_view() -> void:
	if not visible or _container == null or not is_instance_valid(_container):
		return
	if _title_label == null:
		_build_layout()

	var is_briefcase: bool = bool(_container.get("is_briefcase_container"))
	var c_id: String = str(_container.get("container_id"))
	var vis_ratio: float = float(_container.get("drawer_visual_ratio"))
	if is_briefcase:
		_title_label.text = "COMPACT BRIEFCASE — Click 3D item/bomb to take | [A / S / D / ESC] Close"
	elif vis_ratio < 0.90:
		_title_label.text = "%s (%d%% Open) — [Tap E] Fast Yank Open | [Hold E] Slowly Ease Open | [A / S / D / ESC] Step Back" % [c_id.to_upper(), int(round(vis_ratio * 100.0))]
	else:
		_title_label.text = "%s — Drag 3D junk aside (LMB) to uncover items | Click item to take | [A / S / D / ESC] Close" % c_id.to_upper()

	if _push_clutter_btn != null:
		var clutter_arr: Array = _container.get("clutter_positions") as Array
		_push_clutter_btn.visible = (not is_briefcase) and vis_ratio >= 0.55 and clutter_arr != null and not clutter_arr.is_empty()

	_refresh_left_hand_panel()
	_refresh_status_label(is_briefcase)
	_refresh_jacket_panel(is_briefcase)


func _build_layout() -> void:
	if get_child_count() > 0:
		return

	# Top Non-Blocking Instruction Banner
	var top_bar := PanelContainer.new()
	top_bar.anchor_left = 0.06
	top_bar.anchor_right = 0.94
	top_bar.anchor_top = 0.0
	top_bar.anchor_bottom = 0.0
	top_bar.offset_top = 12.0
	top_bar.offset_bottom = 58.0
	top_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(top_bar)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	top_bar.add_child(header_row)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.text = "DRAWER — Drag 3D junk aside (LMB) to uncover items | [A / S / D / ESC] Close"
	header_row.add_child(_title_label)

	_push_clutter_btn = Button.new()
	_push_clutter_btn.focus_mode = Control.FOCUS_NONE
	_push_clutter_btn.text = "Push All Clutter Aside"
	_push_clutter_btn.pressed.connect(func():
		if _container == null or not is_instance_valid(_container):
			return
		var pos_arr: Array = _container.get("clutter_positions") as Array
		if pos_arr == null:
			return
		var corners: Array[Vector2] = [
			Vector2(0.08, 0.12),
			Vector2(0.92, 0.12),
			Vector2(0.08, 0.88),
			Vector2(0.92, 0.88),
			Vector2(0.08, 0.50),
			Vector2(0.92, 0.50)
		]
		for i in range(pos_arr.size()):
			_container.request_move_clutter(_local_peer_id, i, corners[i % corners.size()])
	)
	header_row.add_child(_push_clutter_btn)

	var close_btn := Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.text = "Close [S]"
	close_btn.pressed.connect(func():
		if _container != null and is_instance_valid(_container) and _container.has_method("request_close_container"):
			_container.request_close_container(_local_peer_id)
	)
	header_row.add_child(close_btn)

	# Compact Bottom-Right Trap & Jacket Strip (leaves center 3D drawer unobstructed)
	var side_panel := PanelContainer.new()
	side_panel.anchor_left = 1.0
	side_panel.anchor_right = 1.0
	side_panel.anchor_top = 1.0
	side_panel.anchor_bottom = 1.0
	side_panel.offset_left = -270.0
	side_panel.offset_right = -14.0
	side_panel.offset_top = -340.0
	side_panel.offset_bottom = -64.0
	side_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(side_panel)

	var side_vbox := VBoxContainer.new()
	side_vbox.add_theme_constant_override("separation", 6)
	side_panel.add_child(side_vbox)

	_container_status_label = Label.new()
	_container_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_container_status_label.text = "Front Lip: Clear"
	side_vbox.add_child(_container_status_label)

	_left_item_label = Label.new()
	_left_item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_item_label.text = "LEFT [Q]: Empty"
	side_vbox.add_child(_left_item_label)

	var right_hdr := Label.new()
	right_hdr.text = "3-SLOT INNER JACKET"
	right_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_hdr.add_theme_font_size_override("font_size", 14)
	side_vbox.add_child(right_hdr)

	_jacket_slots_box = VBoxContainer.new()
	_jacket_slots_box.add_theme_constant_override("separation", 6)
	side_vbox.add_child(_jacket_slots_box)


func _refresh_left_hand_panel() -> void:
	if _player == null or _left_item_label == null:
		return
	var l_id: String = str(_player.get("left_hand_item_id"))
	var b_objs: Array = _player.get("briefcase_objectives") as Array
	var disp: String = PICKUP_SCRIPT.get_display_name(l_id, b_objs if b_objs != null else [])
	_left_item_label.text = "LEFT [Q]: %s" % disp


func _refresh_status_label(is_briefcase: bool) -> void:
	if _container_status_label == null or _container == null:
		return
	var vis_ratio: float = float(_container.get("drawer_visual_ratio"))
	if bool(_container.get("live_bomb_lit")):
		var rem: float = float(_container.get("live_bomb_fuse_remaining"))
		_container_status_label.modulate = Color(1.0, 0.30, 0.15)
		_container_status_label.text = "LIT BOMB! (%.1fs) — Click 3D Bomb to Grab!" % rem
	elif bool(_container.get("armed_spring")) and not is_briefcase and vis_ratio >= 0.15:
		_container_status_label.modulate = Color(1.0, 0.35, 0.30)
		_container_status_label.text = "SPRING VISIBLE! — Release E & Click Trap to Unlatch!"
	elif bool(_container.get("spring_unlatched")):
		_container_status_label.modulate = Color(0.35, 0.95, 0.85)
		_container_status_label.text = "Spring Unlatched — LMB Steal | RMB Re-Arm"
	elif bool(_container.get("staged_spring_on_lip")):
		_container_status_label.modulate = Color(1.0, 0.78, 0.30)
		_container_status_label.text = "Spring Staged (Arms on Close)"
	elif bool(_container.get("staged_bomb_in_tray")):
		_container_status_label.modulate = Color(1.0, 0.70, 0.25)
		_container_status_label.text = "Bomb Planted in Tray (Arms on Close)"
	elif not is_briefcase and vis_ratio < 0.15:
		_container_status_label.modulate = Color(0.78, 0.84, 0.88)
		_container_status_label.text = "Drawer Closed (0%) — Tap E or Hold E"
	else:
		_container_status_label.modulate = Color(0.78, 0.84, 0.88)
		_container_status_label.text = "3D Tray: Ready"


func _refresh_jacket_panel(is_briefcase: bool) -> void:
	for c in _jacket_slots_box.get_children():
		c.queue_free()
	if _player == null:
		return

	var slots: Array = _player.get("jacket_slots") as Array
	if slots == null:
		return

	var spring_unlatched: bool = bool(_container.get("spring_unlatched"))
	var can_arm_spring: bool = (not is_briefcase) and (not bool(_container.get("armed_spring"))) and (not bool(_container.get("staged_spring_on_lip"))) and (not spring_unlatched)
	var can_arm_bomb: bool = (not bool(_container.get("armed_bomb"))) and (not bool(_container.get("staged_bomb_in_tray"))) and (not bool(_container.get("live_bomb_lit")))

	for i in range(slots.size()):
		var slot_item: String = str(slots[i]).to_upper()
		var card := PanelContainer.new()
		_jacket_slots_box.add_child(card)

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		card.add_child(row)

		var lbl := Label.new()
		var item_disp: String = "-- Empty --" if slot_item == "NONE" else PICKUP_SCRIPT.get_display_name(slot_item)
		lbl.text = "Slot %d: %s" % [i + 1, item_disp]
		row.add_child(lbl)

		var slot_idx: int = i
		if spring_unlatched and slot_item == "NONE":
			var stow_btn := Button.new()
			stow_btn.focus_mode = Control.FOCUS_NONE
			stow_btn.text = "Stow Unlatched Spring"
			stow_btn.pressed.connect(func():
				_container.request_steal_spring(_local_peer_id, slot_idx)
			)
			row.add_child(stow_btn)
		elif slot_item == "SPRING" and can_arm_spring:
			var plant_btn := Button.new()
			plant_btn.focus_mode = Control.FOCUS_NONE
			plant_btn.text = "Plant Spring on Lip"
			plant_btn.pressed.connect(func():
				_container.request_plant_trap(_local_peer_id, slot_idx, "LIP")
			)
			row.add_child(plant_btn)
		elif slot_item == "BOMB" and can_arm_bomb:
			var bomb_btn := Button.new()
			bomb_btn.focus_mode = Control.FOCUS_NONE
			bomb_btn.text = "Plant Bomb in %s" % ("Briefcase" if is_briefcase else "Drawer")
			bomb_btn.pressed.connect(func():
				_container.request_plant_trap(_local_peer_id, slot_idx, "TRAY")
			)
			row.add_child(bomb_btn)
