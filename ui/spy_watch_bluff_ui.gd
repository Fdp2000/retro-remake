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

const MAP_AMBER := Color("#e4af62")
const MAP_TEXT := Color("#efe5cc")
const MAP_MUTED := Color("#a3b4ad")
const MAP_PASSAGE := Color("#7ca49a")

class PlayerMapMarker extends Control:
	const RADIUS := 5.0
	const DOT_COLOR := Color(1.0, 0.19, 0.23)
	const OUTLINE_COLOR := Color(0.12, 0.03, 0.04)

	var level: Node3D
	var first_button: Button
	var last_button: Button
	var first_room_center: Vector2
	var room_size: Vector2
	var room_count: Vector2i
	var facing := Vector2.UP

	func _draw() -> void:
		var across := facing.orthogonal()
		draw_circle(Vector2.ZERO, 11.0, Color(1.0, 0.19, 0.23, 0.18), true, -1.0, true)
		draw_colored_polygon(PackedVector2Array([facing * 15.0, across * 6.0, -across * 6.0]), OUTLINE_COLOR)
		draw_colored_polygon(PackedVector2Array([facing * 12.0, across * 4.0, -across * 4.0]), DOT_COLOR)
		draw_circle(Vector2.ZERO, RADIUS + 1.5, OUTLINE_COLOR, true, -1.0, true)
		draw_circle(Vector2.ZERO, RADIUS, DOT_COLOR, true, -1.0, true)

	func update_position(world_position: Vector3, world_forward: Vector3, on_floor: bool) -> void:
		if not on_floor or first_button.size.x <= 0.0:
			hide()
			return

		var local := level.to_local(world_position) if level != null else world_position
		var room_coords := (Vector2(local.x, local.z) - first_room_center) / room_size
		var map_bounds := Rect2(-Vector2.ONE * 0.5, Vector2(room_count))
		if not map_bounds.has_point(room_coords):
			hide()
			return

		var first_center := first_button.position + first_button.size * 0.5
		var last_center := last_button.position + last_button.size * 0.5
		var steps := room_count - Vector2i.ONE
		var pitch := Vector2(
			(last_center.x - first_center.x) / steps.x if steps.x > 0 else first_button.size.x,
			(last_center.y - first_center.y) / steps.y if steps.y > 0 else first_button.size.y
		)
		var local_forward := level.global_transform.basis.inverse() * world_forward if level != null else world_forward
		var map_forward := (Vector2(local_forward.x, local_forward.z) * pitch / room_size).normalized()
		if not map_forward.is_zero_approx() and not facing.is_equal_approx(map_forward):
			facing = map_forward
			queue_redraw()
		position = (first_center + room_coords * pitch).clamp(
			first_button.position + Vector2.ONE * RADIUS,
			last_button.position + last_button.size - Vector2.ONE * RADIUS
		)
		show()


class RoomInk extends Control:
	var strokes: Array
	var _drawing := false

	func _draw() -> void:
		for stroke: PackedVector2Array in strokes:
			var points := PackedVector2Array()
			for point in stroke:
				points.append(point * size)
			if points.size() == 1:
				draw_circle(points[0], 1.8, Color("#111416"), true, -1.0, true)
			elif points.size() > 1:
				draw_polyline(points, Color("#111416"), 2.8, true)

	func handle_input(event: InputEvent) -> bool:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_drawing = false
				strokes.clear()
				queue_redraw()
				return true
			if event.button_index == MOUSE_BUTTON_LEFT:
				_drawing = event.pressed
				if _drawing:
					strokes.append(PackedVector2Array())
					_append_point(event.position)
				return true
		elif event is InputEventMouseMotion and _drawing:
			if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				_drawing = false
				return false
			_append_point(event.position)
			return true
		return false

	func _append_point(local_position: Vector2) -> void:
		var point := (local_position / size.max(Vector2.ONE)).clamp(Vector2.ZERO, Vector2.ONE)
		var index := strokes.size() - 1
		var stroke: PackedVector2Array = strokes[index]
		if stroke.is_empty() or ((stroke[-1] - point) * size).length_squared() >= 2.25:
			stroke.append(point)
			strokes[index] = stroke
			queue_redraw()


var _room_ink: Dictionary[String, Array] = {}
var _ink_layers: Array[RoomInk] = []
var _active_ink: RoomInk
var _player: Node = null
var _selected_cue_idx: int = 0
var _status_lbl: Label = null
var _radio_lbl: Label = null
var _map_panel: PanelContainer = null
var _floor_maps: BoxContainer = null
var is_map_open: bool = false
var _player_markers: Array[PlayerMapMarker] = []
var _upper_floor: Node3D
var _map_shade: ColorRect
var _ladder_hint: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	set_process(is_map_open)
	set_process_input(is_map_open)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return
		for ink in _ink_layers:
			var local_event := ink.make_input_local(event) as InputEventMouseButton
			if Rect2(Vector2.ZERO, ink.size).has_point(local_event.position):
				ink.handle_input(local_event)
				_active_ink = ink if event.button_index == MOUSE_BUTTON_LEFT else null
				get_viewport().set_input_as_handled()
				return
	elif _active_ink != null and event is InputEventMouse:
		if _active_ink.handle_input(_active_ink.make_input_local(event)):
			get_viewport().set_input_as_handled()
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_active_ink = null


func _process(_delta: float) -> void:
	if not is_instance_valid(_player) or not _player is Node3D:
		for marker in _player_markers:
			marker.hide()
		return

	var player_transform := (_player as Node3D).global_transform
	var world_position := player_transform.origin
	# Use the player’s feet to switch floors near the top of a ladder.
	var is_upstairs := is_instance_valid(_upper_floor) and _upper_floor.to_local(world_position).y >= -0.15
	for marker in _player_markers:
		var active := not is_instance_valid(_upper_floor) or (marker.level == _upper_floor) == is_upstairs
		marker.update_position(world_position, -player_transform.basis.z, active)


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

	_map_shade = ColorRect.new()
	_map_shade.color = Color(0.025, 0.05, 0.05, 0.36)
	_map_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_shade.hide()
	add_child(_map_shade)
	_map_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_map_panel = PanelContainer.new()
	_map_panel.visible = false
	center.add_child(_map_panel)

	var frame := _map_style(Color(0.059, 0.089, 0.091, 0.96), Color("#78654a"), 20, 16)
	frame.border_width_left = 2
	_map_panel.add_theme_stylebox_override("panel", frame)

	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "DejaVu Sans Mono"])
	var map_theme := Theme.new()
	map_theme.default_font = mono
	map_theme.default_font_size = 13
	map_theme.set_color("font_color", "Label", MAP_TEXT)
	map_theme.set_color("font_color", "Button", MAP_TEXT)
	map_theme.set_color("font_hover_color", "Button", Color.WHITE)
	_map_panel.theme = map_theme

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_map_panel.add_child(content)

	var heading := Label.new()
	heading.text = "Embassy floor plan"
	heading.add_theme_font_size_override("font_size", 23)
	content.add_child(heading)

	_floor_maps = VBoxContainer.new()
	_floor_maps.add_theme_constant_override("separation", 12)
	content.add_child(_floor_maps)
	get_viewport().size_changed.connect(_fit_floor_maps)

	var ink_hint := Label.new()
	ink_hint.text = "Left-drag  Draw    ·    Right-click  Clear"
	ink_hint.add_theme_color_override("font_color", MAP_MUTED)
	ink_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(ink_hint)
	_ladder_hint = Label.new()
	_ladder_hint.text = "↕  Ladder"
	_ladder_hint.add_theme_color_override("font_color", MAP_AMBER)
	content.add_child(_ladder_hint)

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
	_map_shade.visible = opened
	set_process(opened)
	set_process_input(opened)
	_active_ink = null
	if opened:
		_rebuild_room_buttons()


func _refresh_labels() -> void:
	if _status_lbl != null:
		_status_lbl.text = "WATCH [C]: %s | [B] Bluff | [Tab] Map | [V] Radio" % get_selected_cue_label()


func _rebuild_room_buttons() -> void:
	_player_markers.clear()
	_ink_layers.clear()
	_upper_floor = null
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
		_upper_floor = building.get_node_or_null("SecondFloor") as Node3D
		if _upper_floor != null:
			_build_floor_map("Upper Floor", _upper_floor, building, size_in_rooms)
		_build_floor_map("Ground Floor", building, building, size_in_rooms)
	_ladder_hint.visible = _upper_floor != null
	_fit_floor_maps()


func _fit_floor_maps() -> void:
	var viewport_size := get_viewport_rect().size
	var floor_count := _player_markers.size()
	if floor_count == 0:
		return

	var rooms := _player_markers[0].room_count
	# Reserve room for the headers, map borders, and the passages between tiles.
	var floor_width := viewport_size.x - 84.0
	var floor_height := (viewport_size.y - 144.0 - (floor_count - 1) * 12.0) / floor_count
	var room_width := (floor_width - 20.0 - (rooms.x - 1) * 14.0) / rooms.x
	var room_height := (floor_height - 46.0 - (rooms.y - 1) * 12.0) / rooms.y
	var tile_size := Vector2(clampf(floorf(room_width), 42.0, 112.0), clampf(floorf(room_height), 26.0, 68.0))
	for ink in _ink_layers:
		(ink.get_parent() as Control).custom_minimum_size = tile_size


func _map_style(fill: Color, border: Color, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style


func _build_floor_map(title: String, level: Node, ground: Node, size_in_rooms: Vector2i) -> void:
	var floor_frame := PanelContainer.new()
	floor_frame.add_theme_stylebox_override("panel", _map_style(Color("#111b1d"), Color("#405754"), 10, 8))
	_floor_maps.add_child(floor_frame)

	var floor_panel := VBoxContainer.new()
	floor_panel.add_theme_constant_override("separation", 8)
	floor_frame.add_child(floor_panel)

	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	floor_panel.add_child(label)

	var map_area := Control.new()
	map_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_panel.add_child(map_area)

	var grid := GridContainer.new()
	grid.columns = size_in_rooms.x * 2 - 1
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	map_area.add_child(grid)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.minimum_size_changed.connect(func():
		map_area.custom_minimum_size = grid.get_combined_minimum_size()
	)

	var marker := PlayerMapMarker.new()
	marker.name = "PlayerLocation"
	marker.level = level as Node3D
	marker.room_size = level.get_meta("room_size", Vector2(9.0, 9.0)) if level != null else Vector2(9.0, 9.0)
	marker.room_count = size_in_rooms
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.hide()
	map_area.add_child(marker)
	_player_markers.append(marker)

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
				var button := _make_room_button(level, room, has_ladder, title + "/" + room_name)
				grid.add_child(button)
				if marker.first_button == null:
					marker.first_button = button
					var anchor := marker.level.to_local(room.global_position) if room != null else fallback_pos
					marker.first_room_center = Vector2(anchor.x, anchor.z)
				marker.last_button = button
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
			passage.color = MAP_PASSAGE if active else Color.TRANSPARENT
			passage.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(passage)

	map_area.custom_minimum_size = grid.get_combined_minimum_size()


func _make_room_button(level: Node, room: Node3D, has_ladder: bool, ink_key: String) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	if has_ladder:
		btn.text = "↕"
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_color_override("font_color", MAP_AMBER)
		btn.add_theme_color_override("font_outline_color", Color("#181511"))
		btn.add_theme_constant_override("outline_size", 4)

	var tile_color := Color("#546c65")
	if room != null and level != null and level.has_method("get_room_wall_swatch"):
		tile_color = level.get_room_wall_swatch(room)
	elif room != null:
		tile_color = room.get("wall_color")
	var tile := _map_style(tile_color, Color("#52706a"), 4, 2)
	var hover := _map_style(tile_color.lightened(0.13), MAP_AMBER, 4, 2)
	btn.add_theme_stylebox_override("normal", tile)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

	if not _room_ink.has(ink_key):
		_room_ink[ink_key] = []
	var ink := RoomInk.new()
	ink.name = "RoomInk"
	ink.strokes = _room_ink[ink_key]
	ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ink.clip_contents = true
	btn.add_child(ink)
	ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ink_layers.append(ink)

	return btn
