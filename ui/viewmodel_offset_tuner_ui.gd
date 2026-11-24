class_name ViewmodelOffsetTunerUI
extends CanvasLayer

## Lightweight F9 in-game debug overlay for live tuning of 1st-person and 3rd-person (outside)
## hand/arm placement, per-item Position/Rotation/Scale offsets, and debug timer pause.

signal preview_changed
signal pose_values_changed

const ITEM_LIST: Array[String] = [
	"BRIEFCASE",
	"KEY",
	"MONEY",
	"PASSPORT",
	"PLANS",
	"CLUB",
	"DART_GUN",
	"BOMB",
	"LIVE_BOMB",
	"BUCKET",
	"TRIPWIRE",
	"SPRING"
]

const TP_MOTION_LIST: Array[String] = ["IDLE", "WALK", "SPRINT", "CROUCH", "CLIMB", "CLUB_CHARGE"]

var _owner_player: Node = null
var _panel: PanelContainer = null
var _mode_fp_btn: Button = null
var _mode_tp_btn: Button = null
var _side_left_btn: Button = null
var _side_right_btn: Button = null
var _item_opt: OptionButton = null
var _preview_chk: CheckBox = null
var _mirror_chk: CheckBox = null
var _timer_pause_chk: CheckBox = null
var _status_lbl: Label = null
var _item_hdr_lbl: Label = null
var _arm_box: VBoxContainer = null
var _arm_toggle_btn: Button = null
var _tp_cam_box: VBoxContainer = null
var _tp_motion_opt: OptionButton = null

var _third_person_mode: bool = false
var _preview_enabled: bool = true
var _editing_left: bool = false
var _selected_item: String = "BRIEFCASE"
var _mirror_lr: bool = true
var _is_syncing_ui: bool = false

var _item_rows: Dictionary = {}
var _arm_rows: Dictionary = {}
var _tp_cam_rows: Dictionary = {}


func setup(player_node: Node) -> void:
	_owner_player = player_node
	layer = 40
	visible = false
	_build_ui()


func toggle_open() -> void:
	set_open(not visible)


func is_third_person_mode() -> bool:
	return visible and _third_person_mode


func set_open(open_now: bool) -> void:
	visible = open_now
	if open_now:
		if _owner_player != null:
			var r_id: String = str(_owner_player.get("right_hand_item_id"))
			var l_id: String = str(_owner_player.get("left_hand_item_id"))
			if r_id != "NONE" and r_id != "" and r_id in ITEM_LIST:
				_editing_left = false
				_selected_item = r_id
			elif l_id != "NONE" and l_id != "" and l_id in ITEM_LIST:
				_editing_left = true
				_selected_item = l_id
		_sync_ui_from_player()
		_push_tp_preview_to_player(_third_person_mode)
		preview_changed.emit()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_push_tp_preview_to_player(false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		preview_changed.emit()


func has_preview_override(is_left: bool) -> bool:
	if not visible or not _preview_enabled:
		return false
	return is_left == _editing_left


func get_preview_item_id(is_left: bool) -> String:
	if is_left == _editing_left:
		return _selected_item
	return "NONE"


func _build_ui() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "TunerPanel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -378.0
	_panel.offset_right = -12.0
	_panel.offset_top = 12.0
	_panel.offset_bottom = -12.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.86)
	style.border_color = Color(0.32, 0.72, 0.95, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# Header
	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)
	var title := Label.new()
	title.text = "Hand & Item Offset Tuner [F9]"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	hdr.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(func(): set_open(false))
	hdr.add_child(close_btn)

	# Debug Match Timer Pause toggle
	_timer_pause_chk = CheckBox.new()
	_timer_pause_chk.text = "Disable Timer Countdown"
	_timer_pause_chk.toggled.connect(_on_timer_pause_toggled)
	vbox.add_child(_timer_pause_chk)

	# View Mode selector: 1st Person vs 3rd Person (Outside)
	var mode_row := HBoxContainer.new()
	vbox.add_child(mode_row)
	_mode_fp_btn = Button.new()
	_mode_fp_btn.text = "1st Person"
	_mode_fp_btn.toggle_mode = true
	_mode_fp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_fp_btn.pressed.connect(func(): _set_view_mode(false))
	mode_row.add_child(_mode_fp_btn)

	_mode_tp_btn = Button.new()
	_mode_tp_btn.text = "3rd Person (Outside)"
	_mode_tp_btn.toggle_mode = true
	_mode_tp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_tp_btn.pressed.connect(func(): _set_view_mode(true))
	mode_row.add_child(_mode_tp_btn)

	# Hand side selector
	var side_row := HBoxContainer.new()
	vbox.add_child(side_row)
	_side_left_btn = Button.new()
	_side_left_btn.text = "Left Hand"
	_side_left_btn.toggle_mode = true
	_side_left_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_left_btn.pressed.connect(func(): _set_side(true))
	side_row.add_child(_side_left_btn)

	_side_right_btn = Button.new()
	_side_right_btn.text = "Right Hand"
	_side_right_btn.toggle_mode = true
	_side_right_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_right_btn.pressed.connect(func(): _set_side(false))
	side_row.add_child(_side_right_btn)

	# Item switcher row
	var item_row := HBoxContainer.new()
	vbox.add_child(item_row)
	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.pressed.connect(func(): _cycle_item(-1))
	item_row.add_child(prev_btn)

	_item_opt = OptionButton.new()
	_item_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item_id in ITEM_LIST:
		_item_opt.add_item(item_id)
	_item_opt.item_selected.connect(_on_item_selected)
	item_row.add_child(_item_opt)

	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.pressed.connect(func(): _cycle_item(1))
	item_row.add_child(next_btn)

	# Options row
	var opt_row := HBoxContainer.new()
	vbox.add_child(opt_row)
	_preview_chk = CheckBox.new()
	_preview_chk.text = "Preview Item"
	_preview_chk.button_pressed = true
	_preview_chk.toggled.connect(func(v: bool):
		_preview_enabled = v
		preview_changed.emit()
	)
	opt_row.add_child(_preview_chk)

	_mirror_chk = CheckBox.new()
	_mirror_chk.text = "Mirror L/R"
	_mirror_chk.button_pressed = true
	_mirror_chk.toggled.connect(func(v: bool):
		_mirror_lr = v
		_push_item_sliders_to_player()
	)
	opt_row.add_child(_mirror_chk)

	vbox.add_child(HSeparator.new())

	# Item Pose Controls
	_item_hdr_lbl = Label.new()
	_item_hdr_lbl.text = "1st-Person Item Offset"
	_item_hdr_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_item_hdr_lbl)

	_add_slider_row(_item_rows, vbox, "pos_x", "Pos X", -0.60, 0.60, 0.005, _on_item_slider_changed)
	_add_slider_row(_item_rows, vbox, "pos_y", "Pos Y", -0.60, 0.60, 0.005, _on_item_slider_changed)
	_add_slider_row(_item_rows, vbox, "pos_z", "Pos Z", -0.60, 0.60, 0.005, _on_item_slider_changed)
	_add_slider_row(_item_rows, vbox, "rot_x", "Rot X (deg)", -180.0, 180.0, 1.0, _on_item_slider_changed)
	_add_slider_row(_item_rows, vbox, "rot_y", "Rot Y (deg)", -180.0, 180.0, 1.0, _on_item_slider_changed)
	_add_slider_row(_item_rows, vbox, "rot_z", "Rot Z (deg)", -180.0, 180.0, 1.0, _on_item_slider_changed)
	_add_slider_row(_item_rows, vbox, "scale", "Item Scale", 0.15, 1.80, 0.01, _on_item_slider_changed)

	vbox.add_child(HSeparator.new())

	# 3rd-Person Outside Camera & Animation Preview section
	_tp_cam_box = VBoxContainer.new()
	_tp_cam_box.visible = false
	_tp_cam_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_tp_cam_box)

	var tp_hdr := Label.new()
	tp_hdr.text = "Outside Preview Camera & Pose"
	tp_hdr.add_theme_font_size_override("font_size", 13)
	_tp_cam_box.add_child(tp_hdr)

	var mot_row := HBoxContainer.new()
	_tp_cam_box.add_child(mot_row)
	var mot_lbl := Label.new()
	mot_lbl.text = "Animation"
	mot_lbl.custom_minimum_size = Vector2(96, 0)
	mot_lbl.add_theme_font_size_override("font_size", 12)
	mot_row.add_child(mot_lbl)
	_tp_motion_opt = OptionButton.new()
	_tp_motion_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m_name in TP_MOTION_LIST:
		_tp_motion_opt.add_item(m_name)
	_tp_motion_opt.item_selected.connect(func(_idx: int): _push_tp_preview_to_player(true))
	mot_row.add_child(_tp_motion_opt)

	_add_slider_row(_tp_cam_rows, _tp_cam_box, "yaw", "Orbit Yaw", -180.0, 180.0, 1.0, _on_tp_cam_changed, 32.0)
	_add_slider_row(_tp_cam_rows, _tp_cam_box, "pitch", "Orbit Pitch", -50.0, 45.0, 1.0, _on_tp_cam_changed, -10.0)
	_add_slider_row(_tp_cam_rows, _tp_cam_box, "dist", "Cam Dist", 0.90, 4.50, 0.05, _on_tp_cam_changed, 2.15)
	_add_slider_row(_tp_cam_rows, _tp_cam_box, "height", "Cam Height", 0.30, 1.70, 0.05, _on_tp_cam_changed, 1.0)

	# Collapsible 1st-Person Arm & Socket Base section
	_arm_toggle_btn = Button.new()
	_arm_toggle_btn.text = "1st-Person Arm & Socket Base [Show]"
	_arm_toggle_btn.pressed.connect(func():
		_arm_box.visible = not _arm_box.visible
		_arm_toggle_btn.text = "1st-Person Arm & Socket Base [%s]" % ("Hide" if _arm_box.visible else "Show")
	)
	vbox.add_child(_arm_toggle_btn)

	_arm_box = VBoxContainer.new()
	_arm_box.visible = false
	_arm_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_arm_box)

	_add_slider_row(_arm_rows, _arm_box, "sock_x", "Socket X (Out)", 0.05, 0.65, 0.005, _on_arm_slider_changed)
	_add_slider_row(_arm_rows, _arm_box, "sock_y", "Socket Y (Up)", -0.60, 0.10, 0.005, _on_arm_slider_changed)
	_add_slider_row(_arm_rows, _arm_box, "sock_z", "Socket Z (Fwd)", -0.95, -0.20, 0.005, _on_arm_slider_changed)
	_add_slider_row(_arm_rows, _arm_box, "arm_x", "Arm Off X", -0.25, 0.25, 0.005, _on_arm_slider_changed)
	_add_slider_row(_arm_rows, _arm_box, "arm_y", "Arm Off Y", -0.25, 0.25, 0.005, _on_arm_slider_changed)
	_add_slider_row(_arm_rows, _arm_box, "arm_z", "Arm Off Z", -0.25, 0.25, 0.005, _on_arm_slider_changed)
	_add_slider_row(_arm_rows, _arm_box, "arm_s", "Arm Scale", 0.30, 1.30, 0.01, _on_arm_slider_changed)

	vbox.add_child(HSeparator.new())

	# Action Buttons
	var btn_row_1 := HBoxContainer.new()
	vbox.add_child(btn_row_1)
	var reset_btn := Button.new()
	reset_btn.text = "Reset Item"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(_on_reset_item)
	btn_row_1.add_child(reset_btn)

	var save_btn := Button.new()
	save_btn.text = "Save File"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save_json)
	btn_row_1.add_child(save_btn)

	var copy_btn := Button.new()
	copy_btn.text = "Copy Both GDScript Tables to Clipboard"
	copy_btn.pressed.connect(_on_copy_gdscript)
	vbox.add_child(copy_btn)

	_status_lbl = Label.new()
	_status_lbl.text = "Switch between 1st Person and 3rd Person (Outside) to align both."
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.modulate = Color(0.75, 0.9, 1.0)
	vbox.add_child(_status_lbl)


func _add_slider_row(store: Dictionary, parent: Container, key: String, label_text: String, min_v: float, max_v: float, step_v: float, cb: Callable, init_val: float = 0.0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(96, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = init_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(120, 0)
	row.add_child(slider)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step_v
	spin.value = init_val
	spin.custom_minimum_size = Vector2(76, 0)
	spin.focus_mode = Control.FOCUS_CLICK
	row.add_child(spin)

	slider.value_changed.connect(func(val: float):
		if _is_syncing_ui:
			return
		_is_syncing_ui = true
		spin.value = val
		_is_syncing_ui = false
		cb.call()
	)
	spin.value_changed.connect(func(val: float):
		if _is_syncing_ui:
			return
		_is_syncing_ui = true
		slider.value = val
		_is_syncing_ui = false
		cb.call()
	)

	store[key] = {"slider": slider, "spin": spin}


func _set_row_val(store: Dictionary, key: String, val: float) -> void:
	if not store.has(key):
		return
	var entry: Dictionary = store[key]
	(entry["slider"] as HSlider).value = val
	(entry["spin"] as SpinBox).value = val


func _get_row_val(store: Dictionary, key: String) -> float:
	if not store.has(key):
		return 0.0
	return float((store[key]["slider"] as HSlider).value)


func _set_view_mode(is_tp: bool) -> void:
	_third_person_mode = is_tp
	_sync_ui_from_player()
	_push_tp_preview_to_player(is_tp)
	preview_changed.emit()


func _set_side(is_left: bool) -> void:
	_editing_left = is_left
	_sync_ui_from_player()
	preview_changed.emit()


func _cycle_item(dir: int) -> void:
	var idx: int = ITEM_LIST.find(_selected_item)
	if idx == -1:
		idx = 0
	idx = posmod(idx + dir, ITEM_LIST.size())
	_selected_item = ITEM_LIST[idx]
	_sync_ui_from_player()
	preview_changed.emit()


func _on_item_selected(index: int) -> void:
	if index >= 0 and index < ITEM_LIST.size():
		_selected_item = ITEM_LIST[index]
		_sync_ui_from_player()
		preview_changed.emit()


func _on_timer_pause_toggled(paused: bool) -> void:
	if _is_syncing_ui:
		return
	if MatchManager != null and MatchManager.has_method("set_debug_timer_disabled"):
		MatchManager.set_debug_timer_disabled(paused)
	elif GameConfig != null:
		GameConfig.debug_disable_match_timer = paused
	if _status_lbl != null:
		_status_lbl.text = "Match timer countdown PAUSED." if paused else "Match timer countdown RESUMED."


func _on_tp_cam_changed() -> void:
	_push_tp_preview_to_player(_third_person_mode)


func _push_tp_preview_to_player(active: bool) -> void:
	if _owner_player == null:
		return
	var mot_idx: int = _tp_motion_opt.selected if _tp_motion_opt != null else 0
	var mot_name: String = TP_MOTION_LIST[clampi(mot_idx, 0, TP_MOTION_LIST.size() - 1)]
	_owner_player.call(
		"set_tp_preview_state",
		active,
		_get_row_val(_tp_cam_rows, "yaw"),
		_get_row_val(_tp_cam_rows, "pitch"),
		_get_row_val(_tp_cam_rows, "dist"),
		_get_row_val(_tp_cam_rows, "height"),
		mot_name
	)


func _sync_ui_from_player() -> void:
	if _panel == null or _owner_player == null:
		return
	_is_syncing_ui = true
	_mode_fp_btn.set_pressed_no_signal(not _third_person_mode)
	_mode_tp_btn.set_pressed_no_signal(_third_person_mode)
	_side_left_btn.set_pressed_no_signal(_editing_left)
	_side_right_btn.set_pressed_no_signal(not _editing_left)
	_tp_cam_box.visible = _third_person_mode
	_arm_toggle_btn.visible = not _third_person_mode
	if _third_person_mode:
		_arm_box.visible = false
	_item_hdr_lbl.text = "3rd-Person (hand Bone) Offset" if _third_person_mode else "1st-Person Item Offset"
	if _timer_pause_chk != null and GameConfig != null:
		_timer_pause_chk.set_pressed_no_signal(GameConfig.debug_disable_match_timer)

	var item_idx: int = ITEM_LIST.find(_selected_item)
	if item_idx >= 0:
		_item_opt.select(item_idx)

	var spec: Dictionary = _owner_player.call("get_hand_item_pose_dict", _selected_item, _third_person_mode)
	var side_sign: float = -1.0 if _editing_left else 1.0
	var pos_key: String = "left_pos" if _editing_left else "right_pos"
	var rot_key: String = "left_rot_deg" if _editing_left else "right_rot_deg"
	_mirror_lr = not (spec.has(pos_key) or spec.has(rot_key))
	_mirror_chk.set_pressed_no_signal(_mirror_lr)

	var vis_pos: Vector3 = Vector3.ZERO
	if spec.has(pos_key):
		vis_pos = spec[pos_key]
	else:
		var p: Vector3 = spec.get("pos", Vector3.ZERO)
		vis_pos = Vector3(p.x * side_sign, p.y, p.z)

	var vis_rot: Vector3 = Vector3.ZERO
	if spec.has(rot_key):
		vis_rot = spec[rot_key]
	else:
		var r: Vector3 = spec.get("rot_deg", Vector3.ZERO)
		vis_rot = Vector3(r.x, r.y * side_sign, r.z * side_sign)

	var sc: Vector3 = spec.get("scale", Vector3.ONE)
	_set_row_val(_item_rows, "pos_x", vis_pos.x)
	_set_row_val(_item_rows, "pos_y", vis_pos.y)
	_set_row_val(_item_rows, "pos_z", vis_pos.z)
	_set_row_val(_item_rows, "rot_x", vis_rot.x)
	_set_row_val(_item_rows, "rot_y", vis_rot.y)
	_set_row_val(_item_rows, "rot_z", vis_rot.z)
	_set_row_val(_item_rows, "scale", sc.x)

	var vm_cfg: Dictionary = _owner_player.call("get_viewmodel_base_config")
	var r_base: Vector3 = vm_cfg.get("right_base_pos", Vector3(0.34, -0.26, -0.52))
	var r_arm: Vector3 = vm_cfg.get("right_arm_offset", Vector3(0.045, -0.02, 0.03))
	var arm_sc: Vector3 = vm_cfg.get("arm_scale", Vector3(0.76, 0.76, 0.76))
	_set_row_val(_arm_rows, "sock_x", r_base.x)
	_set_row_val(_arm_rows, "sock_y", r_base.y)
	_set_row_val(_arm_rows, "sock_z", r_base.z)
	_set_row_val(_arm_rows, "arm_x", r_arm.x)
	_set_row_val(_arm_rows, "arm_y", r_arm.y)
	_set_row_val(_arm_rows, "arm_z", r_arm.z)
	_set_row_val(_arm_rows, "arm_s", arm_sc.x)
	_is_syncing_ui = false


func _on_item_slider_changed() -> void:
	_push_item_sliders_to_player()


func _push_item_sliders_to_player() -> void:
	if _owner_player == null:
		return
	var vis_pos := Vector3(
		_get_row_val(_item_rows, "pos_x"),
		_get_row_val(_item_rows, "pos_y"),
		_get_row_val(_item_rows, "pos_z")
	)
	var vis_rot := Vector3(
		_get_row_val(_item_rows, "rot_x"),
		_get_row_val(_item_rows, "rot_y"),
		_get_row_val(_item_rows, "rot_z")
	)
	var s_val: float = _get_row_val(_item_rows, "scale")
	var sc := Vector3(s_val, s_val, s_val)
	_owner_player.call("set_runtime_hand_item_pose", _selected_item, _editing_left, _mirror_lr, vis_pos, vis_rot, sc, _third_person_mode)
	pose_values_changed.emit()


func _on_arm_slider_changed() -> void:
	if _owner_player == null:
		return
	var r_base := Vector3(
		_get_row_val(_arm_rows, "sock_x"),
		_get_row_val(_arm_rows, "sock_y"),
		_get_row_val(_arm_rows, "sock_z")
	)
	var r_arm := Vector3(
		_get_row_val(_arm_rows, "arm_x"),
		_get_row_val(_arm_rows, "arm_y"),
		_get_row_val(_arm_rows, "arm_z")
	)
	var arm_s: float = _get_row_val(_arm_rows, "arm_s")
	_owner_player.call("set_viewmodel_base_config", r_base, r_arm, Vector3(arm_s, arm_s, arm_s))
	pose_values_changed.emit()


func _on_reset_item() -> void:
	if _owner_player == null:
		return
	_owner_player.call("reset_runtime_hand_item_pose", _selected_item, _third_person_mode)
	_sync_ui_from_player()
	pose_values_changed.emit()
	_status_lbl.text = "Reset %s (%s) to default." % [_selected_item, "3P" if _third_person_mode else "1P"]


func _on_save_json() -> void:
	if _owner_player == null:
		return
	var ok: bool = bool(_owner_player.call("save_viewmodel_poses_override_file"))
	_status_lbl.text = "Saved 1P & 3P poses to res://entities/player/hand_poses_override.json!" if ok else "Failed to save JSON file."


func _on_copy_gdscript() -> void:
	if _owner_player == null:
		return
	var text: String = str(_owner_player.call("export_viewmodel_poses_gdscript"))
	DisplayServer.clipboard_set(text)
	print("\n" + text + "\n")
	_status_lbl.text = "Copied both 1P & 3P GDScript blocks to clipboard!"
