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
var _rooms_grid: GridContainer = null
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
	_map_panel = PanelContainer.new()
	_map_panel.anchor_left = 0.5
	_map_panel.anchor_right = 0.5
	_map_panel.anchor_top = 0.5
	_map_panel.anchor_bottom = 0.5
	_map_panel.offset_left = -210.0
	_map_panel.offset_right = 210.0
	_map_panel.offset_top = -220.0
	_map_panel.offset_bottom = 220.0
	_map_panel.modulate = Color(0.85, 1.0, 0.88, 0.96)
	_map_panel.visible = false
	add_child(_map_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_map_panel.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "SPY WATCH BLUFF PROJECTOR [Click Room]"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 14)
	vbox.add_child(hdr)

	_rooms_grid = GridContainer.new()
	_rooms_grid.columns = 4
	_rooms_grid.add_theme_constant_override("h_separation", 6)
	_rooms_grid.add_theme_constant_override("v_separation", 6)
	_rooms_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_rooms_grid)

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
	if _rooms_grid == null:
		return
	for child in _rooms_grid.get_children():
		_rooms_grid.remove_child(child)
		child.queue_free()

	var rooms: Array[Dictionary] = _collect_scene_rooms()
	_rooms_grid.columns = 4 if rooms.size() >= 12 else 3
	for room_info in rooms:
		var r_name: String = str(room_info["name"])
		var r_pos: Vector3 = room_info["pos"] as Vector3
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(90.0, 74.0)
		btn.text = r_name
		btn.pressed.connect(func():
			if _player != null and _player.has_method("emit_watch_bluff"):
				_player.emit_watch_bluff(get_selected_cue_id(), r_pos)
			set_map_open(false)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		)
		_rooms_grid.add_child(btn)


func _collect_scene_rooms() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var scene: Node = get_tree().current_scene if (is_inside_tree() and get_tree() != null) else null
	var rooms_root: Node = scene.get_node_or_null("BuildingComplex2/Rooms") if scene != null else null
	if rooms_root != null:
		for c in rooms_root.get_children():
			if c is Node3D:
				out.append({"name": c.name, "pos": (c as Node3D).global_position})
	if out.is_empty():
		for rz in range(3):
			for rx in range(3):
				out.append({
					"name": "Room_%d_%d" % [rx + 1, rz + 1],
					"pos": Vector3(-9.0 + float(rx) * 9.0, 0.0, -9.0 + float(rz) * 9.0)
				})
	return out
