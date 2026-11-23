@tool
class_name SpawnerCheatsheetUI
extends Control

## In-Game & Lobby Spawner Tuning Cheatsheet Overlay (J3).
## Allows tuning Min/Max Drawers, Max Drawers per Room, Spawn Room Drawer rules,
## Total Gadgets Min/Max, Individual Gadget/Trap Min/Max, and Floor Water Buckets Min/Max.
## Also displays a live breakdown of the active round's spawned drawers & items per room.

signal apply_and_reroll_requested()
signal closed()

var is_in_arena: bool = false
var _updating_ui: bool = false
var _last_populate_summary: Dictionary = {}

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _seed_label: Label = null

var _min_drawers_spin: SpinBox = null
var _max_drawers_spin: SpinBox = null
var _max_per_room_spin: SpinBox = null
var _allow_spawn_rooms_check: CheckBox = null
var _max_in_spawn_room_spin: SpinBox = null
var _isolate_briefcase_check: CheckBox = null

var _min_total_gadgets_spin: SpinBox = null
var _max_total_gadgets_spin: SpinBox = null

var _spring_min_spin: SpinBox = null
var _spring_max_spin: SpinBox = null
var _bomb_min_spin: SpinBox = null
var _bomb_max_spin: SpinBox = null
var _tripwire_min_spin: SpinBox = null
var _tripwire_max_spin: SpinBox = null
var _dart_gun_min_spin: SpinBox = null
var _dart_gun_max_spin: SpinBox = null

var _floor_buckets_min_spin: SpinBox = null
var _floor_buckets_max_spin: SpinBox = null

var _summary_box: RichTextLabel = null
var _apply_reroll_btn: Button = null
var _reset_defaults_btn: Button = null
var _close_btn: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	refresh_from_config()
	visible = false


func open_cheatsheet(in_arena: bool = false, latest_summary: Dictionary = {}) -> void:
	is_in_arena = in_arena
	if not latest_summary.is_empty():
		_last_populate_summary = latest_summary.duplicate(true)
	_build_layout()
	refresh_from_config()
	_refresh_live_summary()
	if _apply_reroll_btn != null:
		_apply_reroll_btn.text = "Apply & Re-Roll Round Now (New Seed)" if is_in_arena else "Apply Rules for Match Start"
	visible = true


func close_cheatsheet() -> void:
	visible = false
	closed.emit()


func set_latest_populate_summary(summary: Dictionary) -> void:
	_last_populate_summary = summary.duplicate(true)
	if visible:
		_refresh_live_summary()


func _build_layout() -> void:
	if _panel != null:
		return

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.02, 0.03, 0.04, 0.78)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "CheatsheetPanel"
	_panel.custom_minimum_size = Vector2(820.0, 560.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12, 0.98)
	style.border_color = Color(0.32, 0.58, 0.42, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	style.shadow_size = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(root_vbox)

	# Header Row
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header_hbox)

	_title_label = Label.new()
	_title_label.text = "MATCH SPAWNER CHEATSHEET & TUNER [F2]"
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.modulate = Color(0.55, 0.96, 0.68)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(_title_label)

	_seed_label = Label.new()
	_seed_label.text = "Seed: #--"
	_seed_label.add_theme_font_size_override("font_size", 14)
	_seed_label.modulate = Color(0.75, 0.82, 0.88)
	header_hbox.add_child(_seed_label)

	root_vbox.add_child(HSeparator.new())

	# Two-Column Body: Left = Controls, Right = Live Manifest / Room Breakdown
	var body_hbox := HBoxContainer.new()
	body_hbox.add_theme_constant_override("separation", 16)
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body_hbox)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(440.0, 410.0)
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_child(left_scroll)

	var controls_vbox := VBoxContainer.new()
	controls_vbox.add_theme_constant_override("separation", 8)
	controls_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(controls_vbox)

	# Section 1: Containers & Room Rules
	_add_section_header(controls_vbox, "1. Searchable Containers (Big Drawer = 2, Small Drawer = 1)")
	var drawers_row := _create_min_max_row(controls_vbox, "Total Containers (Min / Max):", 5, 64, 24, 32)
	_min_drawers_spin = drawers_row["min"]
	_max_drawers_spin = drawers_row["max"]

	_max_per_room_spin = _create_single_spin_row(controls_vbox, "Max Drawer Props Per Contested Room (Min 1):", 1, 8, 2)

	var spawn_room_row := HBoxContainer.new()
	spawn_room_row.add_theme_constant_override("separation", 8)
	controls_vbox.add_child(spawn_room_row)
	_allow_spawn_rooms_check = CheckBox.new()
	_allow_spawn_rooms_check.text = "Allow Drawers in Spawn Rooms"
	_allow_spawn_rooms_check.button_pressed = true
	_allow_spawn_rooms_check.toggled.connect(func(_v: bool) -> void: _on_any_control_changed())
	spawn_room_row.add_child(_allow_spawn_rooms_check)

	_max_in_spawn_room_spin = _create_single_spin_row(controls_vbox, "Max Drawer Props Per Spawn Room:", 0, 4, 1)

	var isolate_row := HBoxContainer.new()
	isolate_row.add_theme_constant_override("separation", 8)
	controls_vbox.add_child(isolate_row)
	_isolate_briefcase_check = CheckBox.new()
	_isolate_briefcase_check.text = "Never Spawn Briefcase in Same Room as an Objective"
	_isolate_briefcase_check.button_pressed = true
	_isolate_briefcase_check.toggled.connect(func(_v: bool) -> void: _on_any_control_changed())
	isolate_row.add_child(_isolate_briefcase_check)

	controls_vbox.add_child(HSeparator.new())

	# Section 2: Total Traps / Gadgets Cap inside Drawers
	_add_section_header(controls_vbox, "2. Drawer Traps & Gadgets Pool (~70% of Drawers)")
	var total_gadgets_row := _create_min_max_row(controls_vbox, "Total Drawer Gadgets (Min / Max):", 0, 40, 11, 14)
	_min_total_gadgets_spin = total_gadgets_row["min"]
	_max_total_gadgets_spin = total_gadgets_row["max"]

	var spring_row := _create_min_max_row(controls_vbox, "Spring Trap (Min / Max):", 0, 20, 1, 6)
	_spring_min_spin = spring_row["min"]
	_spring_max_spin = spring_row["max"]

	var bomb_row := _create_min_max_row(controls_vbox, "Time Bomb (Min / Max):", 0, 20, 1, 6)
	_bomb_min_spin = bomb_row["min"]
	_bomb_max_spin = bomb_row["max"]

	var tripwire_row := _create_min_max_row(controls_vbox, "Tripwire Coil (Min / Max):", 0, 20, 1, 6)
	_tripwire_min_spin = tripwire_row["min"]
	_tripwire_max_spin = tripwire_row["max"]

	var dart_row := _create_min_max_row(controls_vbox, "DVD Dart Gun (Min / Max):", 0, 20, 0, 4)
	_dart_gun_min_spin = dart_row["min"]
	_dart_gun_max_spin = dart_row["max"]

	controls_vbox.add_child(HSeparator.new())

	# Section 3: Open-World Floor Water Buckets (separate from Drawer Gadgets)
	_add_section_header(controls_vbox, "3. Floor Water Buckets (Separate from Drawer Gadgets)")
	var floor_bucket_row := _create_min_max_row(controls_vbox, "Floor Water Buckets (Min / Max):", 0, 15, 3, 5)
	_floor_buckets_min_spin = floor_bucket_row["min"]
	_floor_buckets_max_spin = floor_bucket_row["max"]

	# Right Column: Live Preview & Active Map Summary
	var right_vbox := VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(325.0, 0.0)
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 6)
	body_hbox.add_child(right_vbox)

	var summary_hdr := Label.new()
	summary_hdr.text = "Live Spawner Breakdown & Room Audit"
	summary_hdr.add_theme_font_size_override("font_size", 14)
	summary_hdr.modulate = Color(0.85, 0.92, 1.0)
	right_vbox.add_child(summary_hdr)

	_summary_box = RichTextLabel.new()
	_summary_box.bbcode_enabled = true
	_summary_box.fit_content = false
	_summary_box.scroll_active = true
	_summary_box.selection_enabled = true
	_summary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sum_style := StyleBoxFlat.new()
	sum_style.bg_color = Color(0.05, 0.06, 0.08, 0.95)
	sum_style.border_color = Color(0.22, 0.28, 0.34, 1.0)
	sum_style.set_border_width_all(1)
	sum_style.set_corner_radius_all(6)
	sum_style.set_content_margin_all(10)
	_summary_box.add_theme_stylebox_override("normal", sum_style)
	right_vbox.add_child(_summary_box)

	root_vbox.add_child(HSeparator.new())

	# Footer Action Buttons
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 12)
	footer_hbox.alignment = BoxContainer.ALIGNMENT_END
	root_vbox.add_child(footer_hbox)

	_reset_defaults_btn = Button.new()
	_reset_defaults_btn.name = "ResetDefaultsButton"
	_reset_defaults_btn.text = "Reset Defaults"
	_reset_defaults_btn.pressed.connect(_on_reset_defaults_pressed)
	footer_hbox.add_child(_reset_defaults_btn)

	_apply_reroll_btn = Button.new()
	_apply_reroll_btn.name = "ApplyRerollButton"
	_apply_reroll_btn.text = "Apply & Re-Roll Round Now (New Seed)"
	_apply_reroll_btn.pressed.connect(_on_apply_reroll_pressed)
	footer_hbox.add_child(_apply_reroll_btn)

	_close_btn = Button.new()
	_close_btn.name = "CloseCheatsheetButton"
	_close_btn.text = "Close [F2 / ESC]"
	_close_btn.pressed.connect(close_cheatsheet)
	footer_hbox.add_child(_close_btn)


func _add_section_header(parent: VBoxContainer, title_text: String) -> void:
	var lbl := Label.new()
	lbl.text = title_text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(0.95, 0.84, 0.45)
	parent.add_child(lbl)


func _create_single_spin_row(parent: VBoxContainer, label_text: String, min_v: int, max_v: int, default_v: int) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 1
	spin.value = default_v
	spin.custom_minimum_size = Vector2(88.0, 0.0)
	spin.value_changed.connect(func(_v: float) -> void: _on_any_control_changed())
	row.add_child(spin)
	return spin


func _create_min_max_row(parent: VBoxContainer, label_text: String, min_limit: int, max_limit: int, def_min: int, def_max: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var min_lbl := Label.new()
	min_lbl.text = "Min"
	min_lbl.modulate = Color(0.7, 0.78, 0.86)
	row.add_child(min_lbl)

	var spin_min := SpinBox.new()
	spin_min.min_value = min_limit
	spin_min.max_value = max_limit
	spin_min.step = 1
	spin_min.value = def_min
	spin_min.custom_minimum_size = Vector2(74.0, 0.0)
	row.add_child(spin_min)

	var max_lbl := Label.new()
	max_lbl.text = "Max"
	max_lbl.modulate = Color(0.7, 0.78, 0.86)
	row.add_child(max_lbl)

	var spin_max := SpinBox.new()
	spin_max.min_value = min_limit
	spin_max.max_value = max_limit
	spin_max.step = 1
	spin_max.value = def_max
	spin_max.custom_minimum_size = Vector2(74.0, 0.0)
	row.add_child(spin_max)

	spin_min.value_changed.connect(func(new_min: float) -> void:
		if not _updating_ui and spin_max.value < new_min:
			spin_max.value = new_min
		_on_any_control_changed()
	)
	spin_max.value_changed.connect(func(new_max: float) -> void:
		if not _updating_ui and spin_min.value > new_max:
			spin_min.value = new_max
		_on_any_control_changed()
	)

	return {"min": spin_min, "max": spin_max}


func refresh_from_config() -> void:
	if _min_drawers_spin == null or GameConfig == null:
		return
	_updating_ui = true
	_min_drawers_spin.value = GameConfig.spawner_min_containers
	_max_drawers_spin.value = GameConfig.spawner_max_containers
	_max_per_room_spin.value = GameConfig.spawner_max_drawers_per_room
	_allow_spawn_rooms_check.button_pressed = GameConfig.spawner_allow_drawers_in_spawn_rooms
	if _max_in_spawn_room_spin != null:
		_max_in_spawn_room_spin.value = GameConfig.spawner_max_drawers_in_spawn_room
	if _isolate_briefcase_check != null:
		_isolate_briefcase_check.button_pressed = GameConfig.spawner_isolate_briefcase_from_objectives

	_min_total_gadgets_spin.value = GameConfig.spawner_min_total_gadgets
	_max_total_gadgets_spin.value = GameConfig.spawner_max_total_gadgets

	_spring_min_spin.value = GameConfig.spawner_spring_min
	_spring_max_spin.value = GameConfig.spawner_spring_max
	_bomb_min_spin.value = GameConfig.spawner_bomb_min
	_bomb_max_spin.value = GameConfig.spawner_bomb_max
	_tripwire_min_spin.value = GameConfig.spawner_tripwire_min
	_tripwire_max_spin.value = GameConfig.spawner_tripwire_max
	_dart_gun_min_spin.value = GameConfig.spawner_dart_gun_min
	_dart_gun_max_spin.value = GameConfig.spawner_dart_gun_max

	_floor_buckets_min_spin.value = GameConfig.spawner_floor_buckets_min
	_floor_buckets_max_spin.value = GameConfig.spawner_floor_buckets_max
	_updating_ui = false
	_refresh_live_summary()


func collect_ui_config_dict() -> Dictionary:
	if _min_drawers_spin == null:
		return GameConfig.get_spawner_config_dict() if GameConfig != null else {}
	var min_c: int = int(_min_drawers_spin.value)
	var max_c: int = int(_max_drawers_spin.value)
	return {
		"min_containers": min_c,
		"max_containers": max_c,
		"min_drawers": min_c,
		"max_drawers": max_c,
		"max_drawers_per_room": int(_max_per_room_spin.value),
		"allow_drawers_in_spawn_rooms": _allow_spawn_rooms_check.button_pressed,
		"max_drawers_in_spawn_room": int(_max_in_spawn_room_spin.value) if _max_in_spawn_room_spin != null else 1,
		"isolate_briefcase_from_objectives": _isolate_briefcase_check.button_pressed if _isolate_briefcase_check != null else true,
		"min_total_gadgets": int(_min_total_gadgets_spin.value),
		"max_total_gadgets": int(_max_total_gadgets_spin.value),
		"spring_min": int(_spring_min_spin.value),
		"spring_max": int(_spring_max_spin.value),
		"bomb_min": int(_bomb_min_spin.value),
		"bomb_max": int(_bomb_max_spin.value),
		"tripwire_min": int(_tripwire_min_spin.value),
		"tripwire_max": int(_tripwire_max_spin.value),
		"dart_gun_min": int(_dart_gun_min_spin.value),
		"dart_gun_max": int(_dart_gun_max_spin.value),
		"floor_buckets_min": int(_floor_buckets_min_spin.value),
		"floor_buckets_max": int(_floor_buckets_max_spin.value)
	}


func apply_ui_to_game_config() -> void:
	if GameConfig != null and GameConfig.has_method("apply_spawner_config_dict"):
		GameConfig.apply_spawner_config_dict(collect_ui_config_dict())


func _on_any_control_changed() -> void:
	if _updating_ui:
		return
	apply_ui_to_game_config()
	_refresh_live_summary()


func _on_reset_defaults_pressed() -> void:
	if GameConfig != null and GameConfig.has_method("reset_spawner_defaults"):
		GameConfig.reset_spawner_defaults()
	refresh_from_config()


func _on_apply_reroll_pressed() -> void:
	apply_ui_to_game_config()
	apply_and_reroll_requested.emit()
	_refresh_live_summary()


func _refresh_live_summary() -> void:
	if _summary_box == null:
		return
	var active_seed: int = MatchManager.match_seed if (MatchManager != null and MatchManager.match_seed != 0) else 7321
	if _seed_label != null:
		_seed_label.text = "Active Seed: #%d" % active_seed

	var cfg: Dictionary = collect_ui_config_dict()
	var allow_spawns: bool = bool(cfg.get("allow_drawers_in_spawn_rooms", true))
	var spawn_cap: int = int(cfg.get("max_drawers_in_spawn_room", 1)) if allow_spawns else 0
	var contested_rooms: int = 13
	var max_room_cap: int = contested_rooms * int(cfg.get("max_drawers_per_room", 2)) + 2 * spawn_cap

	var lines: Array[String] = []
	lines.append("[b][color=#8cf2a8]Current Rules Summary[/color][/b]")
	lines.append("• Contested Rooms: [b]13[/b] (Min 1, Max %d/room)" % int(cfg.get("max_drawers_per_room", 2)))
	lines.append("• Spawn Rooms (1_1 & 4_4): [b]%s[/b]" % ("Max %d/room" % spawn_cap if spawn_cap > 0 else "0 drawers"))
	lines.append("• Total Room Prop Capacity: [b]%d drawer props[/b]" % max_room_cap)
	lines.append("• Target Searchable Containers: [b]%d – %d[/b] (5 core + gadgets + empty)" % [int(cfg.get("min_containers", 24)), int(cfg.get("max_containers", 32))])
	lines.append("• Briefcase Isolation: [b]%s[/b]" % ("Never with Objective" if bool(cfg.get("isolate_briefcase_from_objectives", true)) else "Unrestricted"))
	lines.append("• Target Drawer Gadgets: [b]%d – %d[/b]" % [int(cfg.get("min_total_gadgets", 11)), int(cfg.get("max_total_gadgets", 14))])
	lines.append("• Target Floor Water Buckets: [b]%d – %d[/b]" % [int(cfg.get("floor_buckets_min", 3)), int(cfg.get("floor_buckets_max", 5))])

	if not _last_populate_summary.is_empty():
		lines.append("")
		lines.append("[b][color=#ffd875]Active Arena Spawn Audit (Seed #%d)[/color][/b]" % int(_last_populate_summary.get("seed", active_seed)))
		lines.append("• Containers Spawned: [b]%d[/b] (Big=%d [2 ea], Small=%d [1 ea])" % [
			int(_last_populate_summary.get("containers_spawned", 0)),
			int(_last_populate_summary.get("big_drawers_spawned", 0)),
			int(_last_populate_summary.get("small_drawers_spawned", 0))
		])
		lines.append("• Drawer Props Placed: [b]%d[/b]" % int(_last_populate_summary.get("drawers_spawned", 0)))
		lines.append("• Floor Buckets Spawned: [b]%d[/b]" % int(_last_populate_summary.get("floor_buckets_spawned", 0)))
		var manifest: Dictionary = _last_populate_summary.get("manifest", {})
		var g_counts: Dictionary = manifest.get("gadget_counts", {})
		if not g_counts.is_empty():
			lines.append("• Drawer Gadgets: Spring=%d | Bomb=%d | Tripwire=%d | Dart=%d" % [
				int(g_counts.get("SPRING", 0)),
				int(g_counts.get("BOMB", 0)),
				int(g_counts.get("TRIPWIRE", 0)),
				int(g_counts.get("DART_GUN", 0))
			])
		var per_room_containers: Dictionary = _last_populate_summary.get("containers_per_room", {})
		var per_room: Dictionary = _last_populate_summary.get("drawers_per_room", {})
		if not per_room.is_empty():
			lines.append("")
			lines.append("[b]Containers & Drawers Per Room:[/b]")
			var r_keys: Array = per_room.keys()
			r_keys.sort()
			for r_name in r_keys:
				var c_cnt: int = int(per_room_containers.get(r_name, per_room[r_name]))
				lines.append("  - %s: [b]%d[/b] container(s) (%d prop(s))" % [str(r_name), c_cnt, int(per_room[r_name])])

	_summary_box.text = "\n".join(lines)
