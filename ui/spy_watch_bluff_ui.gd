@tool
class_name SpyWatchBluffUI
extends Control

## Wearable Spy Wristwatch / Smart Glasses Comms & Bluff HUD (Doc 6 §3).
## Cycles 4 audio bluff cues ([C]), triggers self-bluffs ([B]), global radio PTT ([Hold V]),
## and opens the top-down Embassy Map Remote Projector ([Hold Tab]).

const BLUFF_CUES: Array[Dictionary] = [
	{"id": "trap_arm", "label": "Trap Arm Click", "radius": 12.0},
	{"id": "drawer_slam", "label": "Drawer Slam", "radius": 12.0},
	{"id": "footstep_sprint", "label": "Sprint Burst", "radius": 12.0},
	{"id": "door_bash", "label": "Door Bash", "radius": 12.0}
]

var _player: Node = null
var _selected_cue_idx: int = 0
var _status_lbl: Label = null
var _radio_lbl: Label = null
var _map_panel: PanelContainer = null
var _floor_maps: BoxContainer = null
var is_map_open: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func setup_for_player(player_node: Node) -> void:
	_player = player_node
	_refresh_labels()


func _build_layout() -> void:
	if _status_lbl != null:
		return

	var pill := PanelContainer.new()
	pill.anchor_left = 0.0
	pill.anchor_right = 0.0
	pill.anchor_top = 1.0
	pill.anchor_bottom = 1.0
	pill.offset_left = 14.0
	pill.offset_right = 410.0
	pill.offset_top = -104.0
	pill.offset_bottom = -64.0
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pill)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	pill.add_child(hbox)

	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(_status_lbl)

	_radio_lbl = Label.new()
	_radio_lbl.text = ""
	_radio_lbl.modulate = Color(0.20, 0.92, 0.95)
	_radio_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(_radio_lbl)

	# Hold Tab Top-Down Room Bluff Projector
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_map_panel = PanelContainer.new()
	_map_panel.visible = false
	center.add_child(_map_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_map_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	_floor_maps = VBoxContainer.new()
	_floor_maps.add_theme_constant_override("separation", 18)
	content.add_child(_floor_maps)


	_refresh_labels()


func cycle_cue() -> String:
	_selected_cue_idx = (_selected_cue_idx + 1) % BLUFF_CUES.size()
	_refresh_labels()
	return get_selected_cue_id()


func get_selected_cue_id() -> String:
	return str(BLUFF_CUES[_selected_cue_idx]["id"])


func get_selected_cue_label() -> String:
	return str(BLUFF_CUES[_selected_cue_idx]["label"])


func set_radio_active(active: bool) -> void:
	if _radio_lbl != null:
		_radio_lbl.text = "[RADIO TX]" if active else ""


func set_map_open(opened: bool) -> void:
	is_map_open = opened
	if _map_panel == null:
		_build_layout()
	_map_panel.visible = opened
	if opened:
		_rebuild_room_buttons()


func _refresh_labels() -> void:
	if _status_lbl != null:
		_status_lbl.text = "WATCH [C]: %s | [B] Bluff | [Tab] Map | [V] Radio" % get_selected_cue_label()


func _rebuild_room_buttons() -> void:
	for child in _floor_maps.get_children():
		_floor_maps.remove_child(child)
		child.queue_free()

	var scene := get_tree().current_scene
	var building: Node = scene if scene != null and scene.has_node("Rooms") else null
	if building == null and scene != null:
		building = scene.get_node_or_null("BuildingComplex3")
		if building == null:
			building = scene.get_node_or_null("BuildingComplex2")
	if building == null:
		_build_floor_map("Ground Floor", null, null, Vector2i(3, 3))
	else:
		var size_in_rooms: Vector2i = building.get_meta("grid_size", Vector2i(4, 4))
		var upstairs := building.get_node_or_null("SecondFloor")
		if upstairs != null:
			_build_floor_map("Upper Floor", upstairs, building, size_in_rooms)
		_build_floor_map("Ground Floor", building, building, size_in_rooms)


func _build_floor_map(title: String, level: Node, ground: Node, size_in_rooms: Vector2i) -> void:
	var floor_panel := VBoxContainer.new()
	floor_panel.add_theme_constant_override("separation", 7)
	_floor_maps.add_child(floor_panel)

	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	floor_panel.add_child(label)

	var grid := GridContainer.new()
	grid.columns = size_in_rooms.x * 2 - 1
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	floor_panel.add_child(grid)

	for row in range(size_in_rooms.y * 2 - 1):
		for column in range(size_in_rooms.x * 2 - 1):
			@warning_ignore("integer_division")
			var room_x := column / 2
			@warning_ignore("integer_division")
			var room_z := row / 2
			if row % 2 == 0 and column % 2 == 0:
				var room_name := "Room_%d_%d" % [room_z + 1, room_x + 1]
				var room := level.get_node_or_null("Rooms/" + room_name) as Node3D if level != null else null
				var has_ladder := ground != null and ground.has_node("Rooms/" + room_name + "/LadderSpawn/AccessLadder")
				var fallback_pos := Vector3((room_x - 1) * 9.0, 0.0, (room_z - 1) * 9.0)
				grid.add_child(_make_room_button(room, has_ladder, fallback_pos))
				continue

			var doorway := ""
			if row % 2 == 0:
				doorway = "Vertical_%d_%d_1" % [room_x + 1, room_z]
			elif column % 2 == 0:
				doorway = "Horizontal_%d_%d_1" % [room_z + 1, room_x]
			var active := level != null and not doorway.is_empty() and level.has_node("Doors/" + doorway)
			var passage := ColorRect.new()
			passage.custom_minimum_size = Vector2(12, 4) if row % 2 == 0 else Vector2(4, 10)
			passage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			passage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			passage.color = Color(0.69, 0.82, 0.78) if active else Color.TRANSPARENT
			passage.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(passage)


func _make_room_button(room: Node3D, has_ladder: bool, fallback_pos: Vector3) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(69, 44)
	if has_ladder:
		btn.text = "↕"
		btn.add_theme_font_size_override("font_size", 17)

	if room != null:
		var tint: Color = room.get("wall_color")
		var card := StyleBoxFlat.new()
		card.bg_color = Color(0.14, 0.17, 0.18).lerp(tint, 0.38)
		card.set_corner_radius_all(5)
		btn.add_theme_stylebox_override("normal", card)
		var hover := card.duplicate() as StyleBoxFlat
		hover.bg_color = card.bg_color.lightened(0.18)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)

	var target := room.global_position if room != null else fallback_pos
	btn.pressed.connect(func():
		if is_instance_valid(_player) and _player.has_method("emit_watch_bluff"):
			_player.emit_watch_bluff(get_selected_cue_id(), target)
		set_map_open(false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)
	return btn
