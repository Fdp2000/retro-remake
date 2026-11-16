@tool
class_name TopDownContainerUI
extends Control

## Shared Top-Down Container View Overlay for Drawers & Dropped Briefcases (Doc 3 §4).
## Displays Left Hand (Left), Draggable Clutter & Tray Contents (Center), and 3-Slot Inner Jacket (Right).

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const CLUTTER_LABELS: Array[String] = [
	"Manila Folder",
	"Classified Envelope",
	"Embassy Ledger",
	"Steel Ruler",
	"Memo Pad"
]
const ITEM_TRAY_POSITIONS: Array[Vector2] = [
	Vector2(0.32, 0.38),
	Vector2(0.62, 0.40),
	Vector2(0.36, 0.68),
	Vector2(0.64, 0.68)
]
const TRAY_SIZE: Vector2 = Vector2(440.0, 290.0)
const CLUTTER_CARD_SIZE: Vector2 = Vector2(126.0, 74.0)

var _player: Node = null
var _container: Node = null
var _local_peer_id: int = 1

var _title_label: Label = null
var _left_item_label: Label = null
var _lip_bar: HBoxContainer = null
var _items_layer: Control = null
var _clutter_layer: Control = null
var _jacket_slots_box: VBoxContainer = null
var _live_bomb_btn: Button = null

var _dragging_clutter_idx: int = -1
var _drag_mouse_offset: Vector2 = Vector2.ZERO
var _clutter_cards: Array[PanelContainer] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func _process(_delta: float) -> void:
	if not visible or _container == null or not is_instance_valid(_container):
		return
	if _live_bomb_btn != null and is_instance_valid(_live_bomb_btn) and bool(_container.get("live_bomb_lit")):
		var rem: float = float(_container.get("live_bomb_fuse_remaining"))
		_live_bomb_btn.text = "LIT TIME BOMB! (%.1fs) — CLICK TO GRAB & THROW!" % rem


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

	_dragging_clutter_idx = -1
	visible = true
	refresh_view()


func close_view() -> void:
	if _container != null and is_instance_valid(_container) and _container.has_signal("state_changed"):
		if _container.state_changed.is_connected(refresh_view):
			_container.state_changed.disconnect(refresh_view)
	_container = null
	_dragging_clutter_idx = -1
	visible = false


func refresh_view() -> void:
	if not visible or _container == null or not is_instance_valid(_container):
		return
	if _title_label == null:
		_build_layout()

	var is_briefcase: bool = bool(_container.get("is_briefcase_container"))
	var c_id: String = str(_container.get("container_id"))
	_title_label.text = "%s  —  [Press A / S / D or ESC to Close]" % ("COMPACT BRIEFCASE" if is_briefcase else c_id.to_upper())

	_refresh_left_hand_panel()
	_refresh_lip_bar(is_briefcase)
	_refresh_tray_items()
	if _dragging_clutter_idx == -1:
		_refresh_clutter_cards()
	_refresh_jacket_panel(is_briefcase)


func _build_layout() -> void:
	if get_child_count() > 0:
		return

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.07, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(960.0, 440.0)
	center.add_child(frame)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	frame.add_child(root_vbox)

	# Header
	var header_row := HBoxContainer.new()
	root_vbox.add_child(header_row)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.text = "DRAWER  —  [Press A / S / D or ESC to Close]"
	header_row.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "Close [S]"
	close_btn.pressed.connect(func():
		if _container != null and is_instance_valid(_container) and _container.has_method("request_close_container"):
			_container.request_close_container(_local_peer_id)
	)
	header_row.add_child(close_btn)

	# 3-Column Body
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(cols)

	# Left Column: Left Hand
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(210.0, 0.0)
	cols.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)

	var left_hdr := Label.new()
	left_hdr.text = "LEFT HAND [Q]"
	left_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_hdr.add_theme_font_size_override("font_size", 15)
	left_vbox.add_child(left_hdr)

	_left_item_label = Label.new()
	_left_item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_item_label.text = "Empty"
	left_vbox.add_child(_left_item_label)

	# Center Column: Container Lip + Interactive Clutter Tray
	var center_vbox := VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.add_theme_constant_override("separation", 8)
	cols.add_child(center_vbox)

	_lip_bar = HBoxContainer.new()
	_lip_bar.custom_minimum_size = Vector2(0.0, 38.0)
	_lip_bar.add_theme_constant_override("separation", 8)
	center_vbox.add_child(_lip_bar)

	var tray_bg := Panel.new()
	tray_bg.custom_minimum_size = TRAY_SIZE
	tray_bg.clip_contents = true
	center_vbox.add_child(tray_bg)

	_items_layer = Control.new()
	_items_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tray_bg.add_child(_items_layer)

	_clutter_layer = Control.new()
	_clutter_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clutter_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray_bg.add_child(_clutter_layer)

	# Right Column: 3-Slot Inner Trenchcoat Jacket
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(250.0, 0.0)
	cols.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_vbox)

	var right_hdr := Label.new()
	right_hdr.text = "3-SLOT INNER JACKET"
	right_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_hdr.add_theme_font_size_override("font_size", 15)
	right_vbox.add_child(right_hdr)

	_jacket_slots_box = VBoxContainer.new()
	_jacket_slots_box.add_theme_constant_override("separation", 8)
	right_vbox.add_child(_jacket_slots_box)


func _refresh_left_hand_panel() -> void:
	if _player == null or _left_item_label == null:
		return
	var l_id: String = str(_player.get("left_hand_item_id"))
	var b_objs: Array = _player.get("briefcase_objectives") as Array
	var disp: String = PICKUP_SCRIPT.get_display_name(l_id, b_objs if b_objs != null else [])
	if l_id == "BRIEFCASE" and b_objs != null and not b_objs.is_empty():
		var names: Array[String] = []
		for obj in b_objs:
			names.append(PICKUP_SCRIPT.get_display_name(str(obj)))
		_left_item_label.text = "%s\n\nPacked:\n- %s" % [disp, "\n- ".join(names)]
	else:
		_left_item_label.text = disp


func _refresh_lip_bar(is_briefcase: bool) -> void:
	for c in _lip_bar.get_children():
		c.queue_free()
	_lip_bar.visible = not is_briefcase
	if is_briefcase:
		return

	var armed_spring: bool = bool(_container.get("armed_spring"))
	var spring_unlatched: bool = bool(_container.get("spring_unlatched"))
	var staged_spring: bool = bool(_container.get("staged_spring_on_lip"))

	if armed_spring:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.modulate = Color(1.0, 0.35, 0.30)
		btn.text = "SPRING TRAP ARMED ON LIP! — Click to Unlatch"
		btn.pressed.connect(func():
			_container.request_unlatch_spring(_local_peer_id)
		)
		_lip_bar.add_child(btn)
	elif spring_unlatched:
		var lbl := Label.new()
		lbl.text = "Spring Unlatched:"
		_lip_bar.add_child(lbl)

		var steal_btn := Button.new()
		steal_btn.text = "Steal to Coat [1-3]"
		steal_btn.pressed.connect(func():
			_container.request_steal_spring(_local_peer_id, -1)
		)
		_lip_bar.add_child(steal_btn)

		var rearm_btn := Button.new()
		rearm_btn.text = "Re-Arm on Lip"
		rearm_btn.pressed.connect(func():
			_container.request_rearm_spring(_local_peer_id)
		)
		_lip_bar.add_child(rearm_btn)
	elif staged_spring:
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.modulate = Color(1.0, 0.75, 0.25)
		lbl.text = "Spring Staged on Lip (Arms on Close)"
		_lip_bar.add_child(lbl)
	else:
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.modulate = Color(0.75, 0.80, 0.85)
		lbl.text = "Front Lip: Clear"
		_lip_bar.add_child(lbl)


func _refresh_tray_items() -> void:
	for c in _items_layer.get_children():
		c.queue_free()
	_live_bomb_btn = null

	var live_lit: bool = bool(_container.get("live_bomb_lit"))
	var armed_b: bool = bool(_container.get("armed_bomb"))
	var staged_b: bool = bool(_container.get("staged_bomb_in_tray"))

	if live_lit:
		_live_bomb_btn = Button.new()
		_live_bomb_btn.position = Vector2(30.0, 12.0)
		_live_bomb_btn.size = Vector2(TRAY_SIZE.x - 60.0, 56.0)
		_live_bomb_btn.modulate = Color(1.0, 0.30, 0.15)
		var rem: float = float(_container.get("live_bomb_fuse_remaining"))
		_live_bomb_btn.text = "LIT TIME BOMB! (%.1fs) — CLICK TO GRAB & THROW!" % rem
		_live_bomb_btn.pressed.connect(func():
			_container.request_grab_lit_bomb(_local_peer_id)
		)
		_items_layer.add_child(_live_bomb_btn)
	elif armed_b or staged_b:
		var lbl := Label.new()
		lbl.position = Vector2(20.0, 12.0)
		lbl.modulate = Color(1.0, 0.65, 0.20)
		lbl.text = "TIME BOMB PLANTED IN TRAY (Arms on Close)"
		_items_layer.add_child(lbl)

	var items: Array = _container.get("stored_items") as Array
	if items == null:
		return
	for i in range(items.size()):
		var item_id: String = str(items[i])
		var btn := Button.new()
		var norm: Vector2 = ITEM_TRAY_POSITIONS[i % ITEM_TRAY_POSITIONS.size()]
		var btn_size := Vector2(148.0, 44.0)
		btn.position = Vector2(
			clampf(norm.x * TRAY_SIZE.x - btn_size.x * 0.5, 10.0, TRAY_SIZE.x - btn_size.x - 10.0),
			clampf(norm.y * TRAY_SIZE.y - btn_size.y * 0.5, 65.0, TRAY_SIZE.y - btn_size.y - 10.0)
		)
		btn.size = btn_size
		btn.text = PICKUP_SCRIPT.get_display_name(item_id)
		var tint: Color = PICKUP_SCRIPT.ITEM_COLORS.get(item_id.to_upper(), Color.WHITE)
		btn.modulate = tint.lightened(0.35)
		btn.pressed.connect(func():
			_container.request_loot_item(_local_peer_id, item_id, -1)
		)
		_items_layer.add_child(btn)


func _refresh_clutter_cards() -> void:
	for c in _clutter_layer.get_children():
		c.queue_free()
	_clutter_cards.clear()

	var positions: Array = _container.get("clutter_positions") as Array
	if positions == null:
		return

	for i in range(positions.size()):
		var norm: Vector2 = positions[i] as Vector2
		var card := PanelContainer.new()
		card.size = CLUTTER_CARD_SIZE
		card.position = _norm_to_card_pos(norm)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.modulate = Color(0.92, 0.86, 0.72, 0.96)

		var lbl := Label.new()
		lbl.text = CLUTTER_LABELS[i % CLUTTER_LABELS.size()] + "\n(Drag)"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lbl)

		var idx: int = i
		card.gui_input.connect(func(event: InputEvent):
			_on_clutter_card_gui_input(event, idx, card)
		)
		_clutter_layer.add_child(card)
		_clutter_cards.append(card)


func _on_clutter_card_gui_input(event: InputEvent, idx: int, card: PanelContainer) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging_clutter_idx = idx
			_drag_mouse_offset = event.position
			card.move_to_front()
		elif _dragging_clutter_idx == idx:
			_dragging_clutter_idx = -1
			var center_norm: Vector2 = _card_pos_to_norm(card.position)
			_container.request_move_clutter(_local_peer_id, idx, center_norm)
	elif event is InputEventMouseMotion and _dragging_clutter_idx == idx:
		var next_pos: Vector2 = card.position + (event.position - _drag_mouse_offset)
		next_pos.x = clampf(next_pos.x, 4.0, TRAY_SIZE.x - CLUTTER_CARD_SIZE.x - 4.0)
		next_pos.y = clampf(next_pos.y, 4.0, TRAY_SIZE.y - CLUTTER_CARD_SIZE.y - 4.0)
		card.position = next_pos


func _norm_to_card_pos(norm: Vector2) -> Vector2:
	var pos := Vector2(
		norm.x * TRAY_SIZE.x - CLUTTER_CARD_SIZE.x * 0.5,
		norm.y * TRAY_SIZE.y - CLUTTER_CARD_SIZE.y * 0.5
	)
	pos.x = clampf(pos.x, 4.0, TRAY_SIZE.x - CLUTTER_CARD_SIZE.x - 4.0)
	pos.y = clampf(pos.y, 4.0, TRAY_SIZE.y - CLUTTER_CARD_SIZE.y - 4.0)
	return pos


func _card_pos_to_norm(card_pos: Vector2) -> Vector2:
	return Vector2(
		clampf((card_pos.x + CLUTTER_CARD_SIZE.x * 0.5) / TRAY_SIZE.x, 0.05, 0.95),
		clampf((card_pos.y + CLUTTER_CARD_SIZE.y * 0.5) / TRAY_SIZE.y, 0.05, 0.95)
	)


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
		row.add_theme_constant_override("separation", 4)
		card.add_child(row)

		var lbl := Label.new()
		var item_disp: String = "-- Empty --" if slot_item == "NONE" else PICKUP_SCRIPT.get_display_name(slot_item)
		lbl.text = "Slot %d: %s" % [i + 1, item_disp]
		row.add_child(lbl)

		var slot_idx: int = i
		if spring_unlatched and slot_item == "NONE":
			var stow_btn := Button.new()
			stow_btn.text = "Stow Unlatched Spring Here"
			stow_btn.pressed.connect(func():
				_container.request_steal_spring(_local_peer_id, slot_idx)
			)
			row.add_child(stow_btn)
		elif slot_item == "SPRING" and can_arm_spring:
			var plant_btn := Button.new()
			plant_btn.text = "Plant Spring on Lip"
			plant_btn.pressed.connect(func():
				_container.request_plant_trap(_local_peer_id, slot_idx, "LIP")
			)
			row.add_child(plant_btn)
		elif slot_item == "BOMB" and can_arm_bomb:
			var bomb_btn := Button.new()
			bomb_btn.text = "Plant Bomb in %s" % ("Briefcase" if is_briefcase else "Drawer")
			bomb_btn.pressed.connect(func():
				_container.request_plant_trap(_local_peer_id, slot_idx, "TRAY")
			)
			row.add_child(bomb_btn)
