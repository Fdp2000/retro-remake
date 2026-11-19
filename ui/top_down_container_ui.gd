@tool
class_name TopDownContainerUI
extends Control

## Tactile 3-Zone Top-Down Container Search UI (Doc 3 §4 + Playtest Briefcase Spec).
## - Center: Unobstructed 3D Drawer or 3D Hinged Briefcase (direct 3D clutter dragging, item/trap interaction).
## - Left Side: Visual Left Hand (empty / loose Objective) OR Simultaneous Open Carried Briefcase (when searching a Drawer).
## - Right Side: Visual 3-Slot Inner Trenchcoat Jacket (drag traps into Drawer/Briefcase; drop looted gadgets into Slots 1-3).

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const BRIEFCASE_BUILDER = preload("res://entities/props/briefcase_visual_builder.gd")
const SHOVE_PHYSICS = preload("res://entities/props/container_shove_physics.gd")
const DRAG_THRESHOLD_PX: float = 12.0

var _player: Node = null
var _container: Node = null
var _local_peer_id: int = 1

var _top_bar: PanelContainer = null
var _title_label: Label = null
var _push_clutter_btn: Button = null

var _left_panel: PanelContainer = null
var _left_title_label: Label = null
var _left_content_box: VBoxContainer = null
var _briefcase_felt_panel: PanelContainer = null
var _briefcase_felt_canvas: Control = null
var _briefcase_lid_cover: ColorRect = null
var _briefcase_lid_label: Label = null
var _carried_briefcase_bomb_btn: Button = null

var _right_panel: PanelContainer = null
var _container_status_label: Label = null
var _jacket_slots_box: VBoxContainer = null
var _coat_slot_panels: Array[PanelContainer] = []

var _center_drop_frame: Panel = null
var _center_drop_label: Label = null
var _drag_ghost: PanelContainer = null
var _drag_ghost_label: Label = null

# Active drag payload
var _drag_active: bool = false
var _drag_moved: bool = false
var _drag_source: String = ""      # LEFT_HAND | CARRIED_BRIEFCASE_OBJ | CARRIED_BRIEFCASE_BOMB | CARRIED_BRIEFCASE_SPRING | COAT_SLOT | CONTAINER_ITEM | CONTAINER_SPRING
var _drag_item_id: String = ""
var _drag_slot_index: int = -1
var _drag_start_pos: Vector2 = Vector2.ZERO
var _ui_drag_samples: Array = []
var _active_briefcase_slides: Dictionary = {} # key -> {"item_id": String, "pos": Vector2, "vel": Vector2}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func _process(delta: float) -> void:
	if not visible or _container == null or not is_instance_valid(_container):
		return

	if not _active_briefcase_slides.is_empty():
		step_carried_briefcase_slides(delta)

	if _container_status_label != null and bool(_container.get("live_bomb_lit")):
		var rem: float = float(_container.get("live_bomb_fuse_remaining"))
		_container_status_label.modulate = Color(1.0, 0.30, 0.15)
		_container_status_label.text = "LIT BOMB! (%.1fs) — Click 3D Bomb to Grab!" % rem

	if _carried_briefcase_bomb_btn != null and is_instance_valid(_carried_briefcase_bomb_btn) and _player != null and _player.has_method("get_held_briefcase_trap_dict"):
		var t_dict: Dictionary = _player.get_held_briefcase_trap_dict()
		if bool(t_dict.get("live_bomb_lit", false)):
			_carried_briefcase_bomb_btn.text = "LIT BOMB (%.1fs)!" % float(t_dict.get("live_bomb_fuse", 0.0))

	# Keep simultaneous Left-Side Briefcase lid visual synced smoothly during slow-peek hold
	_update_carried_briefcase_lid_overlay()

	if _drag_active and _drag_ghost != null and _drag_ghost.visible:
		var mpos: Vector2 = get_viewport().get_mouse_position()
		_drag_ghost.position = mpos + Vector2(14.0, -18.0)
		_update_drop_zone_highlights(mpos)


func _input(event: InputEvent) -> void:
	if not visible or not _drag_active:
		return
	if event is InputEventMouseMotion:
		var mpos: Vector2 = (event as InputEventMouseMotion).position
		if not _drag_moved and mpos.distance_to(_drag_start_pos) >= DRAG_THRESHOLD_PX:
			_drag_moved = true
			_show_drag_ghost(mpos)
		if _drag_moved:
			if (
				_drag_source in ["CARRIED_BRIEFCASE_OBJ", "CARRIED_BRIEFCASE_BOMB"]
				and _briefcase_felt_canvas != null
				and is_instance_valid(_briefcase_felt_canvas)
				and _briefcase_felt_canvas.is_visible_in_tree()
				and _briefcase_felt_canvas.get_global_rect().has_point(mpos)
			):
				var canvas_norm: Vector2 = _get_briefcase_canvas_norm_pos(mpos)
				var live_id: String = "BOMB" if _drag_source == "CARRIED_BRIEFCASE_BOMB" else _drag_item_id
				_apply_card_norm_pos(live_id, canvas_norm)
				SHOVE_PHYSICS.record_sample(_ui_drag_samples, canvas_norm, Time.get_ticks_usec() * 1e-6)
				if _drag_ghost != null:
					_drag_ghost.visible = false
			elif _drag_ghost != null:
				_show_drag_ghost(mpos)
			if _drag_ghost != null and _drag_ghost.visible:
				_drag_ghost.position = mpos + Vector2(14.0, -18.0)
			_update_drop_zone_highlights(mpos)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (event as InputEventMouseButton).pressed:
		var release_pos: Vector2 = (event as InputEventMouseButton).position
		_finish_drag(release_pos)
		get_viewport().set_input_as_handled()


func open_for_container(player_node: Node, container_node: Node, peer_id: int) -> void:
	cancel_drag()
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
	flush_active_briefcase_slides()
	cancel_drag()
	if _container != null and is_instance_valid(_container) and _container.has_signal("state_changed"):
		if _container.state_changed.is_connected(refresh_view):
			_container.state_changed.disconnect(refresh_view)
	_container = null
	visible = false


func is_dragging_item() -> bool:
	return _drag_active


func is_point_over_ui_panel(screen_pos: Vector2) -> bool:
	for panel in [_top_bar, _left_panel, _right_panel]:
		if panel != null and panel.is_visible_in_tree() and panel.get_global_rect().has_point(screen_pos):
			return true
	return false


func is_point_over_left_panel(screen_pos: Vector2) -> bool:
	return _left_panel != null and _left_panel.is_visible_in_tree() and _left_panel.get_global_rect().has_point(screen_pos)


func is_point_over_right_panel(screen_pos: Vector2) -> bool:
	return _right_panel != null and _right_panel.is_visible_in_tree() and _right_panel.get_global_rect().has_point(screen_pos)


func find_coat_slot_at_screen_pos(screen_pos: Vector2) -> int:
	return _find_coat_slot_at_pos(screen_pos)


func get_briefcase_canvas_norm_pos_if_over(screen_pos: Vector2) -> Vector2:
	if _briefcase_felt_canvas != null and is_instance_valid(_briefcase_felt_canvas) and _briefcase_felt_canvas.is_visible_in_tree() and _briefcase_felt_canvas.get_global_rect().has_point(screen_pos):
		return _get_briefcase_canvas_norm_pos(screen_pos)
	return Vector2(-1.0, -1.0)


func update_external_3d_item_drag(item_id: String, screen_pos: Vector2) -> void:
	var upper: String = item_id.to_upper()
	if _drag_ghost != null and _drag_ghost_label != null:
		var col: Color = PICKUP_SCRIPT.ITEM_COLORS.get(upper, Color(0.95, 0.85, 0.35))
		_apply_panel_style(_drag_ghost, Color(0.12, 0.14, 0.18, 0.96), col)
		_drag_ghost_label.text = PICKUP_SCRIPT.get_display_name(upper)
		_drag_ghost.position = screen_pos + Vector2(14.0, -18.0)
		_drag_ghost.visible = true
	_reset_panel_highlights()
	if PICKUP_SCRIPT.is_gadget_item(upper):
		if _right_panel != null:
			var over_right: bool = is_point_over_right_panel(screen_pos)
			var r_border: Color = Color(0.35, 1.0, 0.55, 1.0) if over_right else Color(0.45, 0.78, 1.0, 0.90)
			_apply_panel_style(_right_panel, Color(0.12, 0.16, 0.22, 0.94), r_border)
			for p in _coat_slot_panels:
				if p != null and is_instance_valid(p) and p.get_global_rect().has_point(screen_pos):
					_apply_panel_style(p, Color(0.18, 0.30, 0.24, 0.98), Color(0.35, 1.0, 0.55, 1.0))
	else:
		var over_left: bool = is_point_over_left_panel(screen_pos)
		var l_border: Color = Color(0.35, 1.0, 0.55, 1.0) if over_left else Color(0.95, 0.82, 0.30, 0.90)
		if _left_panel != null:
			_apply_panel_style(_left_panel, Color(0.14, 0.22, 0.16, 0.95), l_border)
		if _briefcase_felt_panel != null and is_instance_valid(_briefcase_felt_panel):
			var over_felt: bool = _briefcase_felt_canvas != null and is_instance_valid(_briefcase_felt_canvas) and _briefcase_felt_canvas.is_visible_in_tree() and _briefcase_felt_canvas.get_global_rect().has_point(screen_pos)
			var f_border: Color = Color(0.35, 1.0, 0.55, 1.0) if over_felt else Color(0.95, 0.82, 0.30, 0.90)
			_apply_panel_style(_briefcase_felt_panel, Color(0.16, 0.24, 0.20, 0.98), f_border)


func clear_external_3d_item_drag() -> void:
	if not _drag_active and _drag_ghost != null:
		_drag_ghost.visible = false
	if not _drag_active:
		_reset_panel_highlights()


func update_external_3d_briefcase_drag(item_id: String, screen_pos: Vector2) -> void:
	update_external_3d_item_drag(item_id, screen_pos)


func clear_external_3d_briefcase_drag() -> void:
	clear_external_3d_item_drag()


func launch_carried_briefcase_slide(item_id: String, start_norm: Vector2, vel: Vector2) -> void:
	var upper: String = item_id.to_upper()
	var norm: Vector2 = BRIEFCASE_BUILDER.clamp_norm(start_norm)
	var cfg: Dictionary = SHOVE_PHYSICS.get_config_dict()
	var stop_speed: float = float(cfg.get("stop_speed", 0.04))
	_apply_card_norm_pos(upper, norm)
	if vel.length() > stop_speed:
		_active_briefcase_slides[upper] = {
			"item_id": upper,
			"pos": norm,
			"vel": vel
		}
	else:
		_active_briefcase_slides.erase(upper)
		if _player != null and _player.has_method("request_move_briefcase_item"):
			_player.request_move_briefcase_item(upper, norm)


func step_carried_briefcase_slides(delta: float) -> void:
	if _active_briefcase_slides.is_empty():
		return
	var cfg: Dictionary = SHOVE_PHYSICS.get_config_dict()
	var to_commit: Array[Dictionary] = []
	for key in _active_briefcase_slides.keys():
		var entry: Dictionary = _active_briefcase_slides[key] as Dictionary
		var res: Dictionary = SHOVE_PHYSICS.step_slide(
			entry["pos"] as Vector2,
			entry["vel"] as Vector2,
			delta,
			BRIEFCASE_BUILDER.NORM_MIN,
			BRIEFCASE_BUILDER.NORM_MAX,
			cfg
		)
		var next_pos: Vector2 = res["pos"] as Vector2
		var next_vel: Vector2 = res["vel"] as Vector2
		entry["pos"] = next_pos
		entry["vel"] = next_vel
		_apply_card_norm_pos(str(entry["item_id"]), next_pos)
		if bool(res["bounced"]) and float(res["impact_speed"]) >= 0.35 and AudioBridge != null and _player != null:
			var ppos: Vector3 = (_player as Node3D).global_position if _player is Node3D else Vector3.ZERO
			AudioBridge.request_world_cue("paper_rustle", ppos, 3.0, _local_peer_id)
		if bool(res["settled"]):
			to_commit.append({"key": key, "item_id": str(entry["item_id"]), "pos": next_pos})
	for c in to_commit:
		_active_briefcase_slides.erase(c["key"])
		if _player != null and _player.has_method("request_move_briefcase_item"):
			_player.request_move_briefcase_item(str(c["item_id"]), c["pos"] as Vector2)


func flush_active_briefcase_slides() -> void:
	if _active_briefcase_slides.is_empty():
		return
	var cfg: Dictionary = SHOVE_PHYSICS.get_config_dict()
	var keys: Array = _active_briefcase_slides.keys()
	for key in keys:
		var entry: Dictionary = _active_briefcase_slides[key] as Dictionary
		var rest_pos: Vector2 = SHOVE_PHYSICS.simulate_to_rest(
			entry["pos"] as Vector2,
			entry["vel"] as Vector2,
			BRIEFCASE_BUILDER.NORM_MIN,
			BRIEFCASE_BUILDER.NORM_MAX,
			cfg
		)
		_apply_card_norm_pos(str(entry["item_id"]), rest_pos)
		_active_briefcase_slides.erase(key)
		if _player != null and _player.has_method("request_move_briefcase_item"):
			_player.request_move_briefcase_item(str(entry["item_id"]), rest_pos)


func _apply_card_norm_pos(item_id: String, norm_pos: Vector2) -> void:
	if _briefcase_felt_canvas == null or not is_instance_valid(_briefcase_felt_canvas):
		return
	var target_name: String = "BriefcaseBombCard" if item_id.to_upper() == "BOMB" else "BriefcaseItemCard_%s" % item_id.to_upper()
	for child in _briefcase_felt_canvas.get_children():
		if child is Control and not child.is_queued_for_deletion() and child.name == target_name:
			var ctrl: Control = child as Control
			var p: Vector2 = BRIEFCASE_BUILDER.clamp_norm(norm_pos)
			ctrl.anchor_left = p.x
			ctrl.anchor_right = p.x
			ctrl.anchor_top = p.y
			ctrl.anchor_bottom = p.y


func begin_external_drag(source: String, item_id: String, screen_pos: Vector2, slot_idx: int = -1) -> void:
	_start_drag(source, item_id, screen_pos, slot_idx)


func cancel_drag() -> void:
	_drag_active = false
	_drag_moved = false
	_drag_source = ""
	_drag_item_id = ""
	_drag_slot_index = -1
	_ui_drag_samples.clear()
	if _drag_ghost != null:
		_drag_ghost.visible = false
	if _center_drop_frame != null:
		_center_drop_frame.visible = false
	_reset_panel_highlights()


func refresh_view() -> void:
	if not visible or _container == null or not is_instance_valid(_container):
		return
	if _title_label == null:
		_build_layout()

	var is_briefcase: bool = bool(_container.get("is_briefcase_container"))
	var c_id: String = str(_container.get("container_id"))
	var vis_ratio: float = float(_container.get("drawer_visual_ratio"))
	var holding_briefcase: bool = (_player != null and str(_player.get("left_hand_item_id")).to_upper() == "BRIEFCASE")

	if vis_ratio < 0.15:
		if is_briefcase:
			_title_label.text = "BRIEFCASE (0%% Open) — [Tap E] Fast Snap Open | [Hold E] Slowly Ease Open | [A / S / D / ESC] Step Back"
		elif holding_briefcase:
			_title_label.text = "%s + BRIEFCASE (0%% Open) — [Tap E] Fast Open Both | [Hold E] Slowly Ease Open Both | [A / S / D / ESC] Step Back" % c_id.to_upper()
		else:
			_title_label.text = "%s (0%% Open) — [Tap E] Fast Yank Open | [Hold E] Slowly Ease Open | [A / S / D / ESC] Step Back" % c_id.to_upper()
	elif vis_ratio < 0.88:
		var pct: int = int(round(vis_ratio * 100.0))
		var label_name: String = "BRIEFCASE" if is_briefcase else (c_id.to_upper() + (" + BRIEFCASE" if holding_briefcase else ""))
		_title_label.text = "%s (%d%% Open) — Hold E to open further | Release E to inspect traps | [A / S / D / ESC] Close" % [label_name, pct]
	else:
		if is_briefcase:
			_title_label.text = "COMPACT BRIEFCASE — Drag items anywhere inside or drag to Left Hand | [A / S / D / ESC] Close"
		elif holding_briefcase:
			_title_label.text = "%s + BRIEFCASE — Drag Objectives ↔ Open Briefcase (Left) anywhere & Traps ↔ Coat (Right) | [A / S / D / ESC] Close" % c_id.to_upper()
		else:
			_title_label.text = "%s — Drag 3D junk aside | Drag Objectives → Left Hand & Gadgets ↔ Inner Coat | [A / S / D / ESC] Close" % c_id.to_upper()

	if _push_clutter_btn != null:
		var clutter_arr: Array = _container.get("clutter_positions") as Array
		_push_clutter_btn.visible = (not is_briefcase) and vis_ratio >= 0.55 and clutter_arr != null and not clutter_arr.is_empty()

	_refresh_left_panel(is_briefcase, vis_ratio)
	_refresh_status_label(is_briefcase, vis_ratio)
	_refresh_jacket_panel(is_briefcase, vis_ratio)
	_update_carried_briefcase_lid_overlay()


# ==========================================
# Layout Construction
# ==========================================

func _build_layout() -> void:
	if get_child_count() > 0:
		return

	# 1. Center Drop-Zone Indicator (shown only while dragging an item toward the 3D prop)
	_center_drop_frame = Panel.new()
	_center_drop_frame.name = "CenterDropFrame"
	_center_drop_frame.anchor_left = 0.27
	_center_drop_frame.anchor_right = 0.73
	_center_drop_frame.anchor_top = 0.16
	_center_drop_frame.anchor_bottom = 0.86
	_center_drop_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_drop_frame.visible = false
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = Color(0.95, 0.82, 0.30, 0.08)
	frame_sb.border_color = Color(1.0, 0.85, 0.32, 0.85)
	frame_sb.set_border_width_all(3)
	frame_sb.set_corner_radius_all(10)
	_center_drop_frame.add_theme_stylebox_override("panel", frame_sb)
	add_child(_center_drop_frame)

	_center_drop_label = Label.new()
	_center_drop_label.anchor_left = 0.0
	_center_drop_label.anchor_right = 1.0
	_center_drop_label.anchor_top = 1.0
	_center_drop_label.anchor_bottom = 1.0
	_center_drop_label.offset_top = -34.0
	_center_drop_label.offset_bottom = -6.0
	_center_drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_drop_label.add_theme_font_size_override("font_size", 15)
	_center_drop_label.modulate = Color(1.0, 0.92, 0.55)
	_center_drop_label.text = "Drop into Container"
	_center_drop_frame.add_child(_center_drop_label)

	# 2. Top Non-Blocking Instruction Banner
	_top_bar = PanelContainer.new()
	_top_bar.name = "TopBanner"
	_top_bar.anchor_left = 0.03
	_top_bar.anchor_right = 0.97
	_top_bar.anchor_top = 0.0
	_top_bar.anchor_bottom = 0.0
	_top_bar.offset_top = 10.0
	_top_bar.offset_bottom = 56.0
	_top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_top_bar)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	_top_bar.add_child(header_row)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.text = "SEARCH MODE"
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
		if _player != null and _player.has_method("flush_active_3d_slides"):
			_player.flush_active_3d_slides(true)
		flush_active_briefcase_slides()
		if _container != null and is_instance_valid(_container) and _container.has_method("request_close_container"):
			_container.request_close_container(_local_peer_id)
	)
	header_row.add_child(close_btn)

	# 3. LEFT SIDE PANEL — Visual Left Hand OR Simultaneous Open Carried Briefcase
	_left_panel = PanelContainer.new()
	_left_panel.name = "LeftHandPanel"
	_left_panel.anchor_left = 0.0
	_left_panel.anchor_right = 0.0
	_left_panel.anchor_top = 0.15
	_left_panel.anchor_bottom = 0.86
	_left_panel.offset_left = 14.0
	_left_panel.offset_right = 294.0
	_left_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_panel_style(_left_panel, Color(0.11, 0.12, 0.15, 0.90), Color(0.42, 0.34, 0.24, 0.85))
	add_child(_left_panel)

	var left_outer := VBoxContainer.new()
	left_outer.add_theme_constant_override("separation", 8)
	_left_panel.add_child(left_outer)

	_left_title_label = Label.new()
	_left_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left_title_label.add_theme_font_size_override("font_size", 15)
	_left_title_label.text = "LEFT HAND [Q]"
	left_outer.add_child(_left_title_label)

	var left_stage := Control.new()
	left_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_stage.clip_contents = true
	left_outer.add_child(left_stage)

	_left_content_box = VBoxContainer.new()
	_left_content_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left_content_box.add_theme_constant_override("separation", 8)
	left_stage.add_child(_left_content_box)

	# Animated leather lid flap over the Left-Side Carried Briefcase (opens in lockstep with Drawer!)
	_briefcase_lid_cover = ColorRect.new()
	_briefcase_lid_cover.name = "CarriedBriefcaseLidCover"
	_briefcase_lid_cover.color = Color(0.32, 0.18, 0.09, 0.98)
	_briefcase_lid_cover.anchor_left = 0.0
	_briefcase_lid_cover.anchor_right = 1.0
	_briefcase_lid_cover.anchor_top = 0.0
	_briefcase_lid_cover.anchor_bottom = 1.0
	_briefcase_lid_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_briefcase_lid_cover.visible = false
	left_stage.add_child(_briefcase_lid_cover)

	_briefcase_lid_label = Label.new()
	_briefcase_lid_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_briefcase_lid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_briefcase_lid_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_briefcase_lid_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_briefcase_lid_label.add_theme_font_size_override("font_size", 14)
	_briefcase_lid_label.modulate = Color(0.95, 0.84, 0.56)
	_briefcase_lid_label.text = "BRIEFCASE CLOSED (0%)\nOpens with Drawer\n[Tap E] Fast  |  [Hold E] Slow"
	_briefcase_lid_cover.add_child(_briefcase_lid_label)

	# 4. RIGHT SIDE PANEL — Visual 3-Slot Inner Trenchcoat Jacket
	_right_panel = PanelContainer.new()
	_right_panel.name = "InnerCoatPanel"
	_right_panel.anchor_left = 1.0
	_right_panel.anchor_right = 1.0
	_right_panel.anchor_top = 0.15
	_right_panel.anchor_bottom = 0.86
	_right_panel.offset_left = -294.0
	_right_panel.offset_right = -14.0
	_right_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_panel_style(_right_panel, Color(0.10, 0.11, 0.14, 0.90), Color(0.36, 0.42, 0.52, 0.85))
	add_child(_right_panel)

	var side_vbox := VBoxContainer.new()
	side_vbox.add_theme_constant_override("separation", 8)
	_right_panel.add_child(side_vbox)

	var right_hdr := Label.new()
	right_hdr.text = "INNER COAT (3 SLOTS)"
	right_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_hdr.add_theme_font_size_override("font_size", 15)
	side_vbox.add_child(right_hdr)

	_container_status_label = Label.new()
	_container_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_container_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_container_status_label.add_theme_font_size_override("font_size", 12)
	_container_status_label.text = "Front Lip: Clear"
	side_vbox.add_child(_container_status_label)

	var sep := HSeparator.new()
	side_vbox.add_child(sep)

	_jacket_slots_box = VBoxContainer.new()
	_jacket_slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_jacket_slots_box.add_theme_constant_override("separation", 8)
	side_vbox.add_child(_jacket_slots_box)

	# 5. Floating Drag Ghost
	_drag_ghost = PanelContainer.new()
	_drag_ghost.name = "DragGhost"
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.visible = false
	_drag_ghost.z_index = 100
	_apply_panel_style(_drag_ghost, Color(0.14, 0.16, 0.22, 0.96), Color(1.0, 0.86, 0.35, 1.0))
	add_child(_drag_ghost)

	_drag_ghost_label = Label.new()
	_drag_ghost_label.add_theme_font_size_override("font_size", 14)
	_drag_ghost_label.text = "Dragging..."
	_drag_ghost.add_child(_drag_ghost_label)


# ==========================================
# Left Panel Refresh (Left Hand OR Carried Briefcase)
# ==========================================

func _refresh_left_panel(is_briefcase: bool, vis_ratio: float) -> void:
	if _left_content_box == null or _player == null:
		return
	_carried_briefcase_bomb_btn = null
	_briefcase_felt_panel = null
	_briefcase_felt_canvas = null
	for c in _left_content_box.get_children():
		c.queue_free()

	var l_id: String = str(_player.get("left_hand_item_id")).to_upper()
	var can_transfer: bool = vis_ratio >= 0.40

	# Mode B: Carrying Briefcase while searching a Drawer -> Freeform Layered Briefcase Canvas on Left!
	if l_id == "BRIEFCASE" and not is_briefcase:
		var b_objs: Array = _player.get("briefcase_objectives") as Array
		var objs: Array = b_objs if b_objs != null else []
		var raw_positions: Variant = _player.get("briefcase_item_positions")
		var item_positions: Dictionary = raw_positions as Dictionary if raw_positions is Dictionary else {}
		var trap_state: Dictionary = _player.get_held_briefcase_trap_dict() if _player.has_method("get_held_briefcase_trap_dict") else {}
		var b_armed_bomb: bool = bool(trap_state.get("armed_bomb", false))
		var b_staged_bomb: bool = bool(trap_state.get("staged_bomb", false))
		var b_lit_bomb: bool = bool(trap_state.get("live_bomb_lit", false))
		var b_fuse: float = float(trap_state.get("live_bomb_fuse", 0.0))
		var raw_bomb_pos: Variant = trap_state.get("bomb_norm_pos", BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS)
		var b_bomb_pos: Vector2 = BRIEFCASE_BUILDER.clamp_norm(raw_bomb_pos as Vector2) if raw_bomb_pos is Vector2 else BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
		if _active_briefcase_slides.has("BOMB"):
			b_bomb_pos = (_active_briefcase_slides["BOMB"] as Dictionary).get("pos", b_bomb_pos) as Vector2

		_left_title_label.text = "BRIEFCASE [%d/4] (LEFT)" % objs.size()

		var hint := Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 12)
		hint.modulate = Color(0.92, 0.84, 0.62)
		hint.text = "Drag items anywhere inside (layered)\nDrag to Drawer center to stash" if can_transfer else "Open Drawer to open Briefcase"
		_left_content_box.add_child(hint)

		# Freeform Dark-Felt Briefcase Tray (zero rigid grid slots!)
		_briefcase_felt_panel = PanelContainer.new()
		_briefcase_felt_panel.name = "FreeformBriefcaseFeltPanel"
		_briefcase_felt_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_briefcase_felt_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_briefcase_felt_panel.custom_minimum_size = Vector2(240.0, 210.0)
		_apply_panel_style(_briefcase_felt_panel, Color(0.14, 0.21, 0.18, 0.98), Color(0.46, 0.28, 0.14, 0.95))
		_left_content_box.add_child(_briefcase_felt_panel)

		_briefcase_felt_canvas = Control.new()
		_briefcase_felt_canvas.name = "BriefcaseFeltCanvas"
		_briefcase_felt_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_briefcase_felt_canvas.clip_contents = true
		_briefcase_felt_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
		_briefcase_felt_panel.add_child(_briefcase_felt_canvas)

		if objs.is_empty() and not (b_armed_bomb or b_staged_bomb or b_lit_bomb):
			var empty_hint := Label.new()
			empty_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty_hint.add_theme_font_size_override("font_size", 12)
			empty_hint.modulate = Color(0.62, 0.72, 0.68, 0.80)
			empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_hint.text = "Open Briefcase Interior\nDrop Objectives or Bombs anywhere"
			_briefcase_felt_canvas.add_child(empty_hint)

		# Bottom Layer (Layer 0): Bomb inside Carried Briefcase (can be covered by Objectives layered on top!)
		if b_lit_bomb:
			var bomb_btn := Button.new()
			bomb_btn.name = "BriefcaseBombCard"
			bomb_btn.focus_mode = Control.FOCUS_NONE
			bomb_btn.modulate = Color(1.0, 0.38, 0.22)
			bomb_btn.text = "LIT BOMB (%.1fs)!" % b_fuse
			bomb_btn.anchor_left = b_bomb_pos.x
			bomb_btn.anchor_right = b_bomb_pos.x
			bomb_btn.anchor_top = b_bomb_pos.y
			bomb_btn.anchor_bottom = b_bomb_pos.y
			bomb_btn.offset_left = -64.0
			bomb_btn.offset_right = 64.0
			bomb_btn.offset_top = -18.0
			bomb_btn.offset_bottom = 18.0
			bomb_btn.pressed.connect(func():
				if _player != null and _player.has_method("request_briefcase_trap_action"):
					_player.request_briefcase_trap_action("GRAB_LIT_BOMB", 0)
			)
			_briefcase_felt_canvas.add_child(bomb_btn)
			_carried_briefcase_bomb_btn = bomb_btn
		elif b_staged_bomb or b_armed_bomb:
			var bomb_card := PanelContainer.new()
			bomb_card.name = "BriefcaseBombCard"
			bomb_card.anchor_left = b_bomb_pos.x
			bomb_card.anchor_right = b_bomb_pos.x
			bomb_card.anchor_top = b_bomb_pos.y
			bomb_card.anchor_bottom = b_bomb_pos.y
			bomb_card.offset_left = -46.0
			bomb_card.offset_right = 46.0
			bomb_card.offset_top = -18.0
			bomb_card.offset_bottom = 18.0
			_apply_panel_style(bomb_card, Color(0.18, 0.14, 0.14, 0.96), Color(0.95, 0.52, 0.20))
			var b_lbl := Label.new()
			b_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			b_lbl.add_theme_font_size_override("font_size", 11)
			b_lbl.text = "Time Bomb" if b_staged_bomb else "Armed Bomb"
			b_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bomb_card.add_child(b_lbl)
			if can_transfer:
				bomb_card.mouse_default_cursor_shape = Control.CURSOR_DRAG
				bomb_card.gui_input.connect(func(ev: InputEvent):
					if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (ev as InputEventMouseButton).pressed:
						_start_drag("CARRIED_BRIEFCASE_BOMB", "BOMB", get_viewport().get_mouse_position(), -1)
				)
			_briefcase_felt_canvas.add_child(bomb_card)

		# Stacked Freeform Layers 1..4: Packed Objectives
		for i in range(objs.size()):
			var obj_id: String = str(objs[i]).to_upper()
			var fallback_pos: Vector2 = BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS[i % BRIEFCASE_BUILDER.DEFAULT_ITEM_NORM_POSITIONS.size()]
			var raw_p: Variant = item_positions.get(obj_id, fallback_pos)
			var norm_pos: Vector2 = BRIEFCASE_BUILDER.clamp_norm(raw_p as Vector2) if raw_p is Vector2 else fallback_pos
			if _active_briefcase_slides.has(obj_id):
				norm_pos = (_active_briefcase_slides[obj_id] as Dictionary).get("pos", norm_pos) as Vector2
			var col: Color = PICKUP_SCRIPT.ITEM_COLORS.get(obj_id, Color(0.85, 0.75, 0.35))

			var item_card := PanelContainer.new()
			item_card.name = "BriefcaseItemCard_%s" % obj_id
			item_card.anchor_left = norm_pos.x
			item_card.anchor_right = norm_pos.x
			item_card.anchor_top = norm_pos.y
			item_card.anchor_bottom = norm_pos.y
			item_card.offset_left = -52.0
			item_card.offset_right = 52.0
			item_card.offset_top = -22.0
			item_card.offset_bottom = 22.0
			_apply_panel_style(item_card, Color(0.18, 0.24, 0.20, 0.98), col)

			var cv := VBoxContainer.new()
			cv.alignment = BoxContainer.ALIGNMENT_CENTER
			cv.add_theme_constant_override("separation", 2)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			item_card.add_child(cv)

			var swatch := ColorRect.new()
			swatch.custom_minimum_size = Vector2(30.0, 6.0)
			swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			swatch.color = col
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(swatch)

			var name_lbl := Label.new()
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.add_theme_font_size_override("font_size", 11)
			name_lbl.text = PICKUP_SCRIPT.get_display_name(obj_id)
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(name_lbl)

			if can_transfer:
				item_card.mouse_default_cursor_shape = Control.CURSOR_DRAG
				var captured_obj: String = obj_id
				var captured_idx: int = i
				item_card.gui_input.connect(func(ev: InputEvent):
					if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (ev as InputEventMouseButton).pressed:
						_start_drag("CARRIED_BRIEFCASE_OBJ", captured_obj, get_viewport().get_mouse_position(), captured_idx)
				)
			_briefcase_felt_canvas.add_child(item_card)

		# Carried Briefcase Latch Spring Strip (Bomb is already inside the freeform tray above)
		_build_carried_briefcase_trap_strip(vis_ratio)
		return

	# Mode A: Visual Left Hand (Empty OR holding a Loose Objective)
	_left_title_label.text = "LEFT HAND [Q]"
	if _briefcase_lid_cover != null:
		_briefcase_lid_cover.visible = false

	var hand_card := PanelContainer.new()
	hand_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_card.custom_minimum_size = Vector2(220.0, 160.0)
	_left_content_box.add_child(hand_card)

	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_theme_constant_override("separation", 10)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_card.add_child(hv)

	if PICKUP_SCRIPT.is_objective_item(l_id):
		var obj_col: Color = PICKUP_SCRIPT.ITEM_COLORS.get(l_id, Color(0.95, 0.80, 0.20))
		_apply_panel_style(hand_card, Color(0.18, 0.16, 0.12, 0.95), obj_col)

		var badge := ColorRect.new()
		badge.custom_minimum_size = Vector2(76.0, 40.0)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		badge.color = obj_col
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hv.add_child(badge)

		var item_lbl := Label.new()
		item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_lbl.add_theme_font_size_override("font_size", 16)
		item_lbl.text = PICKUP_SCRIPT.get_display_name(l_id)
		item_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hv.add_child(item_lbl)

		var sub_lbl := Label.new()
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub_lbl.add_theme_font_size_override("font_size", 12)
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if can_transfer:
			sub_lbl.modulate = Color(0.45, 0.96, 0.60)
			sub_lbl.text = "DRAG → into open %s!" % ("Briefcase" if is_briefcase else "Drawer")
			hand_card.mouse_default_cursor_shape = Control.CURSOR_DRAG
			hand_card.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (ev as InputEventMouseButton).pressed:
					_start_drag("LEFT_HAND", l_id, get_viewport().get_mouse_position(), -1)
			)
		else:
			sub_lbl.modulate = Color(0.88, 0.82, 0.62)
			sub_lbl.text = "Open %s first\n([Tap E] Fast or [Hold E] Slow)" % ("Briefcase" if is_briefcase else "Drawer")
		hv.add_child(sub_lbl)
	else:
		_apply_panel_style(hand_card, Color(0.12, 0.13, 0.16, 0.90), Color(0.38, 0.42, 0.48, 0.70))
		var empty_lbl := Label.new()
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.modulate = Color(0.75, 0.80, 0.86)
		empty_lbl.text = "EMPTY LEFT HAND\n\nDrag an Objective here\nfrom the %s" % ("Briefcase" if is_briefcase else "Drawer")
		hv.add_child(empty_lbl)

	if is_briefcase:
		var packed_arr: Array = _container.get("stored_items") as Array
		var count: int = packed_arr.size() if packed_arr != null else 0
		var info := Label.new()
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_font_size_override("font_size", 12)
		info.modulate = Color(0.82, 0.86, 0.90)
		if l_id == "NONE":
			info.text = "Briefcase: %d/4 Objectives\nClose [S], then [Tap E] to carry!" % count
		else:
			info.text = "Briefcase: %d/4 Objectives\nFree Left Hand to carry it!" % count
		_left_content_box.add_child(info)


func _build_carried_briefcase_trap_strip(vis_ratio: float) -> void:
	if _player == null:
		return
	var trap_state: Dictionary = _player.get_held_briefcase_trap_dict() if _player.has_method("get_held_briefcase_trap_dict") else {}
	var b_armed_spring: bool = bool(trap_state.get("armed_spring", false))
	var b_unlatched_spring: bool = bool(trap_state.get("spring_unlatched", false))
	var b_staged_spring: bool = bool(trap_state.get("staged_spring", false))
	var b_staged_bomb: bool = bool(trap_state.get("staged_bomb", false))
	var b_lit_bomb: bool = bool(trap_state.get("live_bomb_lit", false))

	var trap_box := PanelContainer.new()
	_apply_panel_style(trap_box, Color(0.14, 0.12, 0.12, 0.94), Color(0.55, 0.35, 0.25, 0.80))
	_left_content_box.add_child(trap_box)

	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	trap_box.add_child(tv)

	if b_lit_bomb:
		var lit_lbl := Label.new()
		lit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lit_lbl.add_theme_font_size_override("font_size", 12)
		lit_lbl.modulate = Color(1.0, 0.35, 0.20)
		lit_lbl.text = "Click pulsing Bomb inside Briefcase to grab!"
		tv.add_child(lit_lbl)
	elif b_armed_spring and vis_ratio >= 0.15:
		var unlatch_btn := Button.new()
		unlatch_btn.focus_mode = Control.FOCUS_NONE
		unlatch_btn.modulate = Color(1.0, 0.35, 0.30)
		unlatch_btn.text = "BRIEFCASE SPRING! Click to Unlatch"
		unlatch_btn.pressed.connect(func():
			if _player != null and _player.has_method("request_briefcase_trap_action"):
				_player.request_briefcase_trap_action("UNLATCH_SPRING", 0)
		)
		tv.add_child(unlatch_btn)
	elif b_unlatched_spring:
		var sp_lbl := Label.new()
		sp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sp_lbl.add_theme_font_size_override("font_size", 12)
		sp_lbl.modulate = Color(0.35, 0.95, 0.85)
		sp_lbl.text = "Spring Unlatched — Drag → Coat or Re-Arm"
		tv.add_child(sp_lbl)
		trap_box.mouse_default_cursor_shape = Control.CURSOR_DRAG
		trap_box.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (ev as InputEventMouseButton).pressed:
				_start_drag("CARRIED_BRIEFCASE_SPRING", "SPRING", get_viewport().get_mouse_position(), -1)
		)
		var rearm_btn := Button.new()
		rearm_btn.focus_mode = Control.FOCUS_NONE
		rearm_btn.text = "Re-Arm Spring on Briefcase"
		rearm_btn.pressed.connect(func():
			if _player != null and _player.has_method("request_briefcase_trap_action"):
				_player.request_briefcase_trap_action("REARM_SPRING", 0)
		)
		tv.add_child(rearm_btn)
	elif b_staged_spring or b_staged_bomb:
		var st_lbl := Label.new()
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st_lbl.add_theme_font_size_override("font_size", 12)
		st_lbl.modulate = Color(1.0, 0.78, 0.30)
		var parts: Array[String] = []
		if b_staged_spring:
			parts.append("Spring")
		if b_staged_bomb:
			parts.append("Bomb")
		st_lbl.text = "Staged in Briefcase: %s (Arms on Close)" % " + ".join(parts)
		tv.add_child(st_lbl)
	else:
		var clr_lbl := Label.new()
		clr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		clr_lbl.add_theme_font_size_override("font_size", 11)
		clr_lbl.modulate = Color(0.72, 0.78, 0.76)
		clr_lbl.text = "Briefcase Latch: Clear\n(Drag Spring/Bomb from Coat here to rig!)"
		tv.add_child(clr_lbl)


func _update_carried_briefcase_lid_overlay() -> void:
	if _briefcase_lid_cover == null or _container == null or not is_instance_valid(_container) or _player == null:
		return
	var is_briefcase: bool = bool(_container.get("is_briefcase_container"))
	var holding_briefcase: bool = (str(_player.get("left_hand_item_id")).to_upper() == "BRIEFCASE")
	if is_briefcase or not holding_briefcase:
		_briefcase_lid_cover.visible = false
		return

	var vis_ratio: float = clampf(float(_container.get("drawer_visual_ratio")), 0.0, 1.0)
	if vis_ratio >= 0.85:
		_briefcase_lid_cover.visible = false
		return

	_briefcase_lid_cover.visible = true
	_briefcase_lid_cover.anchor_bottom = clampf(1.0 - vis_ratio, 0.0, 1.0)
	if _briefcase_lid_label != null:
		var pct: int = int(round(vis_ratio * 100.0))
		_briefcase_lid_label.visible = (1.0 - vis_ratio) > 0.25
		_briefcase_lid_label.text = "BRIEFCASE (%d%% Open)\nOpens with Drawer\n[Tap E] Fast  |  [Hold E] Slow" % pct


# ==========================================
# Right Panel Refresh (3-Slot Inner Trenchcoat)
# ==========================================

func _refresh_status_label(is_briefcase: bool, vis_ratio: float) -> void:
	if _container_status_label == null or _container == null:
		return
	var label_name: String = "Briefcase" if is_briefcase else "Drawer"
	if bool(_container.get("live_bomb_lit")):
		var rem: float = float(_container.get("live_bomb_fuse_remaining"))
		_container_status_label.modulate = Color(1.0, 0.30, 0.15)
		_container_status_label.text = "LIT BOMB! (%.1fs) — Click 3D Bomb to Grab!" % rem
	elif bool(_container.get("armed_spring")) and vis_ratio >= 0.15:
		_container_status_label.modulate = Color(1.0, 0.35, 0.30)
		_container_status_label.text = "SPRING VISIBLE! Release E & Click Trap to Unlatch!"
	elif bool(_container.get("spring_unlatched")):
		_container_status_label.modulate = Color(0.35, 0.95, 0.85)
		_container_status_label.text = "Spring Unlatched — Drag → Coat or RMB Re-Arm"
	elif bool(_container.get("staged_spring_on_lip")) and bool(_container.get("staged_bomb_in_tray")):
		_container_status_label.modulate = Color(1.0, 0.78, 0.30)
		_container_status_label.text = "Spring + Bomb Staged (Arm on Close)"
	elif bool(_container.get("staged_spring_on_lip")):
		_container_status_label.modulate = Color(1.0, 0.78, 0.30)
		_container_status_label.text = "Spring Staged on Latch (Arms on Close)"
	elif bool(_container.get("staged_bomb_in_tray")):
		_container_status_label.modulate = Color(1.0, 0.70, 0.25)
		_container_status_label.text = "Bomb Planted Inside (Arms on Close)"
	elif vis_ratio < 0.15:
		_container_status_label.modulate = Color(0.78, 0.84, 0.88)
		_container_status_label.text = "%s Closed (0%%) — Tap E or Hold E" % label_name
	else:
		_container_status_label.modulate = Color(0.78, 0.84, 0.88)
		_container_status_label.text = "Drag Spring / Bomb ← into %s to rig!" % label_name


func _refresh_jacket_panel(is_briefcase: bool, vis_ratio: float) -> void:
	_coat_slot_panels.clear()
	for c in _jacket_slots_box.get_children():
		c.queue_free()
	if _player == null:
		return

	var slots: Array = _player.get("jacket_slots") as Array
	if slots == null:
		return

	var can_plant: bool = vis_ratio >= 0.40
	var spring_unlatched: bool = bool(_container.get("spring_unlatched"))
	var can_arm_spring: bool = can_plant and (not bool(_container.get("armed_spring"))) and (not bool(_container.get("staged_spring_on_lip"))) and (not spring_unlatched)
	var can_arm_bomb: bool = can_plant and (not bool(_container.get("armed_bomb"))) and (not bool(_container.get("staged_bomb_in_tray"))) and (not bool(_container.get("live_bomb_lit")))

	for i in range(slots.size()):
		var slot_item: String = str(slots[i]).to_upper()
		var card := PanelContainer.new()
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(220.0, 86.0)
		_jacket_slots_box.add_child(card)
		_coat_slot_panels.append(card)

		var row := VBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		card.add_child(row)

		var slot_idx: int = i
		if slot_item != "NONE" and not slot_item.is_empty():
			var item_col: Color = PICKUP_SCRIPT.ITEM_COLORS.get(slot_item, Color(0.75, 0.75, 0.80))
			_apply_panel_style(card, Color(0.15, 0.16, 0.20, 0.95), item_col)

			var top_row := HBoxContainer.new()
			top_row.alignment = BoxContainer.ALIGNMENT_CENTER
			top_row.add_theme_constant_override("separation", 8)
			top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(top_row)

			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(14.0, 14.0)
			dot.color = item_col
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top_row.add_child(dot)

			var lbl := Label.new()
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.text = "Pocket %d: %s" % [i + 1, PICKUP_SCRIPT.get_display_name(slot_item)]
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top_row.add_child(lbl)

			if (slot_item == "SPRING" or slot_item == "BOMB") and can_plant:
				var drag_hint := Label.new()
				drag_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				drag_hint.add_theme_font_size_override("font_size", 11)
				drag_hint.modulate = Color(1.0, 0.84, 0.45)
				drag_hint.text = "← Drag into %s to arm" % ("Briefcase" if is_briefcase else "Drawer / Briefcase")
				drag_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(drag_hint)

				card.mouse_default_cursor_shape = Control.CURSOR_DRAG
				var captured_item: String = slot_item
				card.gui_input.connect(func(ev: InputEvent):
					if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (ev as InputEventMouseButton).pressed:
						_start_drag("COAT_SLOT", captured_item, get_viewport().get_mouse_position(), slot_idx)
				)
			elif slot_item == "SPRING" and not can_plant:
				var wait_lbl := Label.new()
				wait_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				wait_lbl.add_theme_font_size_override("font_size", 11)
				wait_lbl.modulate = Color(0.70, 0.74, 0.78)
				wait_lbl.text = "Open container to plant Spring"
				row.add_child(wait_lbl)
			elif slot_item == "BOMB" and not can_plant:
				var wait_lbl := Label.new()
				wait_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				wait_lbl.add_theme_font_size_override("font_size", 11)
				wait_lbl.modulate = Color(0.70, 0.74, 0.78)
				wait_lbl.text = "Open container to plant Bomb"
				row.add_child(wait_lbl)

			# Keep crisp one-click fallback button too for rapid arming
			if slot_item == "SPRING" and can_arm_spring:
				var plant_btn := Button.new()
				plant_btn.focus_mode = Control.FOCUS_NONE
				plant_btn.text = "Arm Spring on %s" % ("Briefcase Latch" if is_briefcase else "Drawer Lip")
				plant_btn.pressed.connect(func():
					_container.request_plant_trap(_local_peer_id, slot_idx, "LIP")
				)
				row.add_child(plant_btn)
			elif slot_item == "BOMB" and can_arm_bomb:
				var bomb_btn := Button.new()
				bomb_btn.focus_mode = Control.FOCUS_NONE
				bomb_btn.text = "Arm Bomb in %s" % ("Briefcase" if is_briefcase else "Drawer")
				bomb_btn.pressed.connect(func():
					_container.request_plant_trap(_local_peer_id, slot_idx, "TRAY")
				)
				row.add_child(bomb_btn)
		else:
			_apply_panel_style(card, Color(0.11, 0.12, 0.15, 0.88), Color(0.32, 0.36, 0.42, 0.65))
			var empty_lbl := Label.new()
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.add_theme_font_size_override("font_size", 13)
			empty_lbl.modulate = Color(0.66, 0.70, 0.76)
			empty_lbl.text = "Pocket %d: -- Empty --" % (i + 1)
			row.add_child(empty_lbl)

			if spring_unlatched:
				var stow_btn := Button.new()
				stow_btn.focus_mode = Control.FOCUS_NONE
				stow_btn.text = "Stow Unlatched Spring Here"
				stow_btn.pressed.connect(func():
					_container.request_steal_spring(_local_peer_id, slot_idx)
				)
				row.add_child(stow_btn)


# ==========================================
# Universal Drag-and-Drop Engine
# ==========================================

func _start_drag(source: String, item_id: String, screen_pos: Vector2, slot_idx: int) -> void:
	_drag_active = true
	_drag_moved = false
	_drag_source = source
	_drag_item_id = item_id.to_upper()
	_drag_slot_index = slot_idx
	_drag_start_pos = screen_pos
	_ui_drag_samples.clear()
	if source in ["CARRIED_BRIEFCASE_OBJ", "CARRIED_BRIEFCASE_BOMB"]:
		var live_key: String = "BOMB" if source == "CARRIED_BRIEFCASE_BOMB" else _drag_item_id
		_active_briefcase_slides.erase(live_key)
		if _briefcase_felt_canvas != null and is_instance_valid(_briefcase_felt_canvas) and _briefcase_felt_canvas.is_visible_in_tree():
			SHOVE_PHYSICS.record_sample(_ui_drag_samples, _get_briefcase_canvas_norm_pos(screen_pos), Time.get_ticks_usec() * 1e-6)


func _show_drag_ghost(screen_pos: Vector2) -> void:
	if _drag_ghost == null or _drag_ghost_label == null:
		return
	var col: Color = PICKUP_SCRIPT.ITEM_COLORS.get(_drag_item_id, Color(0.95, 0.85, 0.35))
	_apply_panel_style(_drag_ghost, Color(0.12, 0.14, 0.18, 0.96), col)
	_drag_ghost_label.text = PICKUP_SCRIPT.get_display_name(_drag_item_id)
	_drag_ghost.position = screen_pos + Vector2(14.0, -18.0)
	_drag_ghost.visible = true
	_update_drop_zone_highlights(screen_pos)


func _update_drop_zone_highlights(screen_pos: Vector2) -> void:
	_reset_panel_highlights()
	if _container == null or not is_instance_valid(_container):
		return

	var is_briefcase: bool = bool(_container.get("is_briefcase_container"))
	var holding_briefcase: bool = (_player != null and str(_player.get("left_hand_item_id")).to_upper() == "BRIEFCASE")
	var over_left: bool = _left_panel != null and _left_panel.get_global_rect().has_point(screen_pos)
	var over_felt: bool = _briefcase_felt_canvas != null and is_instance_valid(_briefcase_felt_canvas) and _briefcase_felt_canvas.is_visible_in_tree() and _briefcase_felt_canvas.get_global_rect().has_point(screen_pos)
	var over_right: bool = _right_panel != null and _right_panel.get_global_rect().has_point(screen_pos)
	var over_center: bool = not over_left and not over_right and not (_top_bar != null and _top_bar.get_global_rect().has_point(screen_pos))

	# Show center drop guide whenever dragging INTO the 3D container
	var wants_center: bool = _drag_source in ["LEFT_HAND", "CARRIED_BRIEFCASE_OBJ", "COAT_SLOT", "CONTAINER_SPRING"]
	if _center_drop_frame != null:
		_center_drop_frame.visible = wants_center and not (over_felt and _drag_source == "CARRIED_BRIEFCASE_OBJ")
		if _center_drop_frame.visible and _center_drop_label != null:
			if _drag_source == "LEFT_HAND":
				_center_drop_label.text = "Drop to Pack into %s" % ("Briefcase" if is_briefcase else "Drawer")
			elif _drag_source == "CARRIED_BRIEFCASE_OBJ":
				_center_drop_label.text = "Drop to Stash inside Drawer"
			elif _drag_source == "COAT_SLOT":
				_center_drop_label.text = "Drop to Arm %s in %s" % [PICKUP_SCRIPT.get_display_name(_drag_item_id), "Briefcase" if is_briefcase else "Drawer"]
			elif _drag_source == "CONTAINER_SPRING":
				_center_drop_label.text = "Drop back on Latch to Re-Arm Spring"
		_center_drop_frame.modulate = Color(1.0, 1.0, 1.0, 1.0) if over_center else Color(0.85, 0.85, 0.85, 0.55)

	# Highlight Left Panel / Felt Canvas when rearranging or dropping into Open Briefcase
	if _briefcase_felt_panel != null and is_instance_valid(_briefcase_felt_panel):
		var felt_valid: bool = (
			_drag_source in ["CARRIED_BRIEFCASE_OBJ", "CARRIED_BRIEFCASE_BOMB"]
			or (_drag_source == "CONTAINER_ITEM" and holding_briefcase and not is_briefcase and PICKUP_SCRIPT.is_objective_item(_drag_item_id))
			or (_drag_source == "COAT_SLOT" and holding_briefcase and not is_briefcase and _drag_item_id == "BOMB")
		)
		if felt_valid:
			var border: Color = Color(0.35, 1.0, 0.55, 1.0) if over_felt else Color(0.95, 0.82, 0.30, 0.90)
			_apply_panel_style(_briefcase_felt_panel, Color(0.16, 0.24, 0.20, 0.98), border)

	if _left_panel != null:
		var left_valid: bool = (
			(_drag_source == "CONTAINER_ITEM" and PICKUP_SCRIPT.is_objective_item(_drag_item_id))
			or (_drag_source == "COAT_SLOT" and holding_briefcase and not is_briefcase and (_drag_item_id == "SPRING" or _drag_item_id == "BOMB"))
		)
		if left_valid:
			var border: Color = Color(0.35, 1.0, 0.55, 1.0) if over_left else Color(0.95, 0.82, 0.30, 0.90)
			_apply_panel_style(_left_panel, Color(0.14, 0.20, 0.16, 0.94), border)

	# Highlight Right Coat Pockets when dragging a Gadget or Unlatched Spring
	if _right_panel != null:
		var right_valid: bool = (
			(_drag_source == "CONTAINER_ITEM" and PICKUP_SCRIPT.is_gadget_item(_drag_item_id))
			or _drag_source == "CONTAINER_SPRING"
			or _drag_source == "CARRIED_BRIEFCASE_SPRING"
		)
		if right_valid:
			var border: Color = Color(0.35, 1.0, 0.55, 1.0) if over_right else Color(0.45, 0.78, 1.0, 0.90)
			_apply_panel_style(_right_panel, Color(0.12, 0.16, 0.22, 0.94), border)
			for p in _coat_slot_panels:
				if p != null and is_instance_valid(p) and p.get_global_rect().has_point(screen_pos):
					_apply_panel_style(p, Color(0.18, 0.30, 0.24, 0.98), Color(0.35, 1.0, 0.55, 1.0))


func _reset_panel_highlights() -> void:
	if _left_panel != null:
		_apply_panel_style(_left_panel, Color(0.11, 0.12, 0.15, 0.90), Color(0.42, 0.34, 0.24, 0.85))
	if _briefcase_felt_panel != null and is_instance_valid(_briefcase_felt_panel):
		_apply_panel_style(_briefcase_felt_panel, Color(0.14, 0.21, 0.18, 0.98), Color(0.46, 0.28, 0.14, 0.95))
	if _right_panel != null:
		_apply_panel_style(_right_panel, Color(0.10, 0.11, 0.14, 0.90), Color(0.36, 0.42, 0.52, 0.85))


func _get_briefcase_canvas_norm_pos(screen_pos: Vector2) -> Vector2:
	if _briefcase_felt_canvas == null or not is_instance_valid(_briefcase_felt_canvas):
		return BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
	var rect: Rect2 = _briefcase_felt_canvas.get_global_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
	var rel: Vector2 = (screen_pos - rect.position) / rect.size
	return BRIEFCASE_BUILDER.clamp_norm(rel)


func _finish_drag(release_pos: Vector2) -> void:
	var src: String = _drag_source
	var item_id: String = _drag_item_id
	var slot_idx: int = _drag_slot_index
	var was_dragged: bool = _drag_moved
	var drag_samples: Array = _ui_drag_samples.duplicate()
	var over_felt: bool = _briefcase_felt_canvas != null and is_instance_valid(_briefcase_felt_canvas) and _briefcase_felt_canvas.is_visible_in_tree() and _briefcase_felt_canvas.get_global_rect().has_point(release_pos)
	var felt_norm: Vector2 = _get_briefcase_canvas_norm_pos(release_pos) if over_felt else Vector2(-1.0, -1.0)
	cancel_drag()

	if _container == null or not is_instance_valid(_container) or _player == null:
		return

	var is_briefcase: bool = bool(_container.get("is_briefcase_container"))
	var holding_briefcase: bool = (str(_player.get("left_hand_item_id")).to_upper() == "BRIEFCASE")
	var over_left: bool = _left_panel != null and _left_panel.get_global_rect().has_point(release_pos)
	var over_right: bool = _right_panel != null and _right_panel.get_global_rect().has_point(release_pos)
	var over_top: bool = _top_bar != null and _top_bar.get_global_rect().has_point(release_pos)
	var over_center: bool = not over_left and not over_right and not over_top
	var target_coat_slot: int = _find_coat_slot_at_pos(release_pos)

	match src:
		"LEFT_HAND":
			# Dragging held loose Objective -> drop onto exact spot inside 3D Briefcase / Drawer!
			if over_center and _container.has_method("request_deposit_left_hand_item"):
				var drop_norm := Vector2(-1.0, -1.0)
				if _player.has_method("project_screen_pos_to_container_norm"):
					drop_norm = _player.project_screen_pos_to_container_norm(release_pos)
				elif is_briefcase and _player.has_method("project_screen_pos_to_briefcase_norm"):
					drop_norm = _player.project_screen_pos_to_briefcase_norm(release_pos)
				_container.request_deposit_left_hand_item(_local_peer_id, drop_norm)

		"CARRIED_BRIEFCASE_OBJ":
			# Dragging packed Objective inside Left Briefcase -> shove-momentum freeform move; or drop into Center 3D Drawer to stash
			if over_felt and was_dragged:
				var vel: Vector2 = SHOVE_PHYSICS.compute_release_velocity(drag_samples, felt_norm, Time.get_ticks_usec() * 1e-6)
				launch_carried_briefcase_slide(item_id, felt_norm, vel)
			elif over_center and not is_briefcase and _container.has_method("request_deposit_briefcase_item"):
				var drawer_norm := Vector2(-1.0, -1.0)
				if _player.has_method("project_screen_pos_to_container_norm"):
					drawer_norm = _player.project_screen_pos_to_container_norm(release_pos)
				_container.request_deposit_briefcase_item(_local_peer_id, item_id, drawer_norm)

		"CARRIED_BRIEFCASE_BOMB":
			if over_felt and was_dragged:
				var b_vel: Vector2 = SHOVE_PHYSICS.compute_release_velocity(drag_samples, felt_norm, Time.get_ticks_usec() * 1e-6)
				launch_carried_briefcase_slide("BOMB", felt_norm, b_vel)

		"CARRIED_BRIEFCASE_SPRING":
			# Dragging unlatched Spring out of Left Open Briefcase -> steal into Right Inner Coat!
			if over_right and _player.has_method("request_briefcase_trap_action"):
				_player.request_briefcase_trap_action("STEAL_SPRING", target_coat_slot)

		"COAT_SLOT":
			if over_center:
				if item_id == "SPRING":
					_container.request_plant_trap(_local_peer_id, slot_idx, "LIP")
				elif item_id == "BOMB":
					var bomb_norm := Vector2(-1.0, -1.0)
					if _player.has_method("project_screen_pos_to_container_norm"):
						bomb_norm = _player.project_screen_pos_to_container_norm(release_pos)
					elif is_briefcase and _player.has_method("project_screen_pos_to_briefcase_norm"):
						bomb_norm = _player.project_screen_pos_to_briefcase_norm(release_pos)
					_container.request_plant_trap(_local_peer_id, slot_idx, "TRAY", bomb_norm)
			elif over_left and holding_briefcase and not is_briefcase and _player.has_method("request_briefcase_trap_action"):
				if item_id == "SPRING":
					_player.request_briefcase_trap_action("PLANT_SPRING", slot_idx)
				elif item_id == "BOMB":
					_player.request_briefcase_trap_action("PLANT_BOMB", slot_idx, felt_norm)

		"CONTAINER_ITEM":
			if PICKUP_SCRIPT.is_objective_item(item_id):
				if over_left:
					_container.request_loot_item(_local_peer_id, item_id, -1, felt_norm)
				elif not was_dragged:
					# Quick-click convenience: loot cleanly when Left Hand is empty or holding Briefcase
					var held_left: String = str(_player.get("left_hand_item_id")).to_upper()
					if held_left == "NONE" or (held_left == "BRIEFCASE" and not is_briefcase):
						_container.request_loot_item(_local_peer_id, item_id, -1)
			elif PICKUP_SCRIPT.is_gadget_item(item_id):
				if over_right:
					_container.request_loot_item(_local_peer_id, item_id, target_coat_slot)
				elif not was_dragged:
					_container.request_loot_item(_local_peer_id, item_id, -1)
			elif not was_dragged or over_left:
				# Briefcase inside a drawer
				_container.request_loot_item(_local_peer_id, item_id, -1)

		"CONTAINER_SPRING":
			if over_right:
				_container.request_steal_spring(_local_peer_id, target_coat_slot)
			elif was_dragged and over_center:
				_container.request_rearm_spring(_local_peer_id)
			elif not was_dragged:
				_container.request_steal_spring(_local_peer_id, -1)


func _find_coat_slot_at_pos(screen_pos: Vector2) -> int:
	for i in range(_coat_slot_panels.size()):
		var p: PanelContainer = _coat_slot_panels[i]
		if p != null and is_instance_valid(p) and p.get_global_rect().has_point(screen_pos):
			return i
	return -1


func _apply_panel_style(panel: PanelContainer, bg: Color, border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
