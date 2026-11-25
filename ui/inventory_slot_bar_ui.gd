class_name InventorySlotBarUI
extends PanelContainer

## Bottom-middle 5-slot square inventory bar:
## [Q] Left Hand | [1] [2] [3] Coat Slots | [4] Club / Live Bomb

const ICON_CACHE = preload("res://ui/item_icon_cache.gd")
const SLOT_SIZE := Vector2(64, 64)

const BG_INACTIVE := Color(0.07, 0.09, 0.11, 0.84)
const BG_ACTIVE := Color(0.14, 0.17, 0.21, 0.94)
const BG_DANGER := Color(0.28, 0.09, 0.06, 0.94)

const BORDER_INACTIVE := Color(0.32, 0.36, 0.42, 0.85)
const BORDER_LEFT_FILLED := Color(0.55, 0.72, 0.88, 0.95)
const BORDER_ACTIVE := Color(0.95, 0.78, 0.25, 1.0)
const BORDER_DANGER := Color(1.0, 0.32, 0.14, 1.0)

var _slot_panels: Array[PanelContainer] = []
var _slot_icons: Array[TextureRect] = []
var _slot_badges: Array[Label] = []
var _slot_item_ids: Array[String] = ["NONE", "NONE", "NONE", "NONE", "CLUB"]
var _last_state: Dictionary = {}
var _is_built: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_built()


func setup(host_node: Node) -> void:
	_ensure_built()
	ICON_CACHE.ensure_prebaked(host_node, _on_icon_baked)


func _ensure_built() -> void:
	if _is_built:
		return
	_is_built = true

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.04, 0.05, 0.07, 0.55)
	bar_style.border_color = Color(0.22, 0.25, 0.30, 0.65)
	bar_style.set_border_width_all(1)
	bar_style.set_corner_radius_all(8)
	bar_style.content_margin_left = 8
	bar_style.content_margin_right = 8
	bar_style.content_margin_top = 6
	bar_style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", bar_style)

	var hbox := HBoxContainer.new()
	hbox.name = "SlotHBox"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(hbox)

	var keys: Array[String] = ["Q", "1", "2", "3", "4"]
	for i in range(keys.size()):
		if i == 1:
			var sep := VSeparator.new()
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sep.custom_minimum_size = Vector2(6, 0)
			hbox.add_child(sep)

		var slot := PanelContainer.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", _make_slot_style(BG_INACTIVE, BORDER_INACTIVE, 2))
		hbox.add_child(slot)

		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(root)

		var icon_margin := MarginContainer.new()
		icon_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_margin.add_theme_constant_override("margin_left", 6)
		icon_margin.add_theme_constant_override("margin_right", 6)
		icon_margin.add_theme_constant_override("margin_top", 6)
		icon_margin.add_theme_constant_override("margin_bottom", 6)
		root.add_child(icon_margin)

		var tex_rect := TextureRect.new()
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_margin.add_child(tex_rect)

		var key_lbl := Label.new()
		key_lbl.text = keys[i]
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_lbl.position = Vector2(5, 2)
		key_lbl.add_theme_font_size_override("font_size", 11)
		key_lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 0.9))
		key_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		key_lbl.add_theme_constant_override("outline_size", 2)
		root.add_child(key_lbl)

		var badge_lbl := Label.new()
		badge_lbl.text = ""
		badge_lbl.visible = false
		badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge_lbl.offset_left = -30
		badge_lbl.offset_top = -18
		badge_lbl.offset_right = -4
		badge_lbl.offset_bottom = -2
		badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge_lbl.add_theme_font_size_override("font_size", 11)
		badge_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35, 1.0))
		badge_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
		badge_lbl.add_theme_constant_override("outline_size", 2)
		root.add_child(badge_lbl)

		_slot_panels.append(slot)
		_slot_icons.append(tex_rect)
		_slot_badges.append(badge_lbl)


func update_slots(
	left_item_id: String,
	briefcase_count: int,
	jacket_slots: Array[String],
	active_jacket_slot: int,
	right_hand_mode: int,
	is_charging_club: bool
) -> void:
	_ensure_built()
	_last_state = {
		"left_item_id": left_item_id,
		"briefcase_count": briefcase_count,
		"jacket_slots": jacket_slots.duplicate(),
		"active_jacket_slot": active_jacket_slot,
		"right_hand_mode": right_hand_mode,
		"is_charging_club": is_charging_club,
	}

	# Slot 0: Left Hand [Q]
	var left_upper: String = left_item_id.to_upper()
	_set_slot_item(0, left_upper)
	var left_filled: bool = left_upper != "NONE" and not left_upper.is_empty()
	_apply_slot_style(
		0,
		BG_ACTIVE if left_filled else BG_INACTIVE,
		BORDER_LEFT_FILLED if left_filled else BORDER_INACTIVE,
		2
	)
	_slot_icons[0].modulate = Color.WHITE
	_slot_badges[0].visible = false

	# Slots 1-3: Inner Coat [1-3]
	for i in range(3):
		var slot_idx: int = i + 1
		var item_id: String = jacket_slots[i].to_upper() if i < jacket_slots.size() else "NONE"
		_set_slot_item(slot_idx, item_id)
		var is_active: bool = (right_hand_mode == 0 and i == active_jacket_slot)
		_apply_slot_style(
			slot_idx,
			BG_ACTIVE if is_active else BG_INACTIVE,
			BORDER_ACTIVE if is_active else BORDER_INACTIVE,
			3 if is_active else 2
		)
		_slot_icons[slot_idx].modulate = Color.WHITE
		_slot_badges[slot_idx].visible = false

	# Slot 4: Club / Live Bomb [4/R]
	if right_hand_mode == 2: # LIVE_BOMB
		_set_slot_item(4, "LIVE_BOMB")
		_apply_slot_style(4, BG_DANGER, BORDER_DANGER, 3)
		_slot_icons[4].modulate = Color.WHITE
		_slot_badges[4].text = "!"
		_slot_badges[4].visible = true
	else:
		_set_slot_item(4, "CLUB")
		var is_club_active: bool = (right_hand_mode == 1)
		_apply_slot_style(
			4,
			BG_DANGER if is_charging_club else (BG_ACTIVE if is_club_active else BG_INACTIVE),
			BORDER_DANGER if is_charging_club else (BORDER_ACTIVE if is_club_active else BORDER_INACTIVE),
			3 if is_club_active else 2
		)
		_slot_icons[4].modulate = Color.WHITE if is_club_active else Color(1.0, 1.0, 1.0, 0.55)
		_slot_badges[4].visible = false


func _set_slot_item(slot_idx: int, item_id: String) -> void:
	_slot_item_ids[slot_idx] = item_id
	_slot_icons[slot_idx].texture = ICON_CACHE.get_icon(item_id)


func _on_icon_baked(item_id: String) -> void:
	if not is_inside_tree():
		return
	for i in range(_slot_item_ids.size()):
		if _slot_item_ids[i] == item_id:
			_slot_icons[i].texture = ICON_CACHE.get_icon(item_id)


func _apply_slot_style(slot_idx: int, bg: Color, border: Color, border_w: int) -> void:
	_slot_panels[slot_idx].add_theme_stylebox_override("panel", _make_slot_style(bg, border, border_w))


static func _make_slot_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(5)
	return sb
