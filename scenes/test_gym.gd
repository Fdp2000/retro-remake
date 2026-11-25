extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const PICKUP_SCENE: PackedScene = preload("res://entities/props/world_item_pickup.tscn")
const EMBASSY_DOOR_SCENE: PackedScene = preload("res://entities/props/embassy_door.tscn")
const DRAWER_SCENE: PackedScene = preload("res://entities/props/searchable_drawer.tscn")
const SMALL_DRAWER_SCENE: PackedScene = preload("res://entities/props/searchable_drawer_small.tscn")
const AIRPORT_EXIT_SCENE: PackedScene = preload("res://entities/props/airport_exit_door.tscn")
const MATCH_SPAWNER_SCRIPT = preload("res://core/match_spawner.gd")
const MATCH_END_UI_SCRIPT = preload("res://ui/match_end_overlay_ui.gd")
const SPAWNER_CHEATSHEET_UI_SCRIPT = preload("res://ui/spawner_cheatsheet_ui.gd")
const ACOUSTIC_ZONE_SCRIPT = preload("res://core/audio/acoustic_zone_3d.gd")
const OCCLUSION_EMITTER_SCRIPT = preload("res://core/audio/occlusion_emitter.gd")
const LOBBY_SCENE_PATH: String = "res://scenes/lobby.tscn"

const SPAWN_POINTS: Dictionary = {
	1: Vector3(-3.0, 1.0, 0.0),
	2: Vector3(3.0, 1.0, 0.0),
	3: Vector3(-3.0, 1.0, 1.8),
	4: Vector3(3.0, 1.0, 1.8)
}
const FULL_MATCH_SPAWN_POINTS: Dictionary = {
	1: Vector3(-12.0, 0.012, -9.0), # Ground Room_1_1 (NW Corner)
	2: Vector3(15.0, 0.012, 9.0),   # Ground Room_3_4 (SE Corner)
	3: Vector3(15.0, 3.232, -9.0),  # Upper Room_1_4 (NE Corner)
	4: Vector3(-12.0, 3.232, 9.0)   # Upper Room_3_1 (SW Corner)
}
const FULL_MATCH_SPAWN_YAWS: Dictionary = {
	1: PI,
	2: 0.0,
	3: PI,
	4: 0.0
}

@onready var players_container: Node3D = $Players
@onready var ui_layer: CanvasLayer = $UI
@onready var esc_menu: PanelContainer = $UI/EscMenu
@onready var match_menu: VBoxContainer = $UI/EscMenu/VBoxContainer
@onready var settings_menu: VBoxContainer = $UI/EscMenu/SettingsMenu
@onready var close_settings_button: Button = $UI/EscMenu/SettingsMenu/CloseButton
@onready var resume_button: Button = $UI/EscMenu/VBoxContainer/ResumeButton
@onready var leave_button: Button = $UI/EscMenu/VBoxContainer/LeaveButton

var peers_in_arena: Dictionary = {} # peer_id -> bool
var expected_peers: Array[int] = []
var peer_roles: Dictionary = {} # peer_id -> role (1..4)
var _disconnect_drop_counter: int = 0
var has_spawned_all: bool = false
var is_terminating: bool = false
var is_sandbox_mode: bool = false
var _match_end_ui: MatchEndOverlayUI = null
var _spawner_cheatsheet_ui: Control = null
var _last_populate_summary: Dictionary = {}
var _esc_cheatsheet_button: Button = null
var _esc_rematch_button: Button = null
var _esc_switch_mode_button: Button = null
var _esc_debug_bomb_fuse_button: Button = null
var _esc_debug_airport_exit_button: Button = null
var _esc_debug_simulate_win_button: Button = null
var _airport_exit_debug_hud_label: Label = null
var _airport_exit_placement: Dictionary = {}
var active_player_spawn_indices: Dictionary = {} # slot (1..4) -> spawn_index (0..3)
var _cached_player_spawn_transforms: Array[Transform3D] = []


func _ready() -> void:
	is_sandbox_mode = GameConfig.sandbox_gym_mode if GameConfig != null else false
	_setup_interactive_doors()
	_configure_level_props_for_mode(is_sandbox_mode)

	if MatchManager != null:
		if not MatchManager.match_ended.is_connected(_on_match_ended):
			MatchManager.match_ended.connect(_on_match_ended)
		if not MatchManager.match_started.is_connected(_on_match_started):
			MatchManager.match_started.connect(_on_match_started)

	_ensure_match_end_ui()
	_ensure_spawner_cheatsheet_ui()

	# ESC Menu buttons & Mouse DPI/Sensitivity controls
	var esc_vbox: VBoxContainer = settings_menu
	if esc_vbox != null:
		if esc_vbox.get_node_or_null("MouseSettingsWidget") == null:
			var mouse_widget: VBoxContainer = preload("res://ui/mouse_settings_widget.gd").new()
			mouse_widget.name = "MouseSettingsWidget"
			esc_vbox.add_child(mouse_widget)
			esc_vbox.move_child(mouse_widget, 1)

		var is_host_or_offline: bool = (not _is_network_active()) or multiplayer.is_server()
		if _esc_cheatsheet_button == null and esc_vbox.get_node_or_null("SpawnerCheatsheetButton") == null:
			_esc_cheatsheet_button = Button.new()
			_esc_cheatsheet_button.name = "SpawnerCheatsheetButton"
			_esc_cheatsheet_button.text = "Spawner Cheatsheet & Tuner [F2]"
			_esc_cheatsheet_button.visible = is_host_or_offline
			_esc_cheatsheet_button.pressed.connect(open_spawner_cheatsheet)
			esc_vbox.add_child(_esc_cheatsheet_button)

		if _esc_rematch_button == null and esc_vbox.get_node_or_null("RestartRoundButton") == null:
			_esc_rematch_button = Button.new()
			_esc_rematch_button.name = "RestartRoundButton"
			_esc_rematch_button.text = "Restart Round (New Seed)"
			_esc_rematch_button.visible = is_host_or_offline
			_esc_rematch_button.pressed.connect(func() -> void: trigger_rematch(is_sandbox_mode))
			esc_vbox.add_child(_esc_rematch_button)

		if _esc_switch_mode_button == null and esc_vbox.get_node_or_null("SwitchModeButton") == null:
			_esc_switch_mode_button = Button.new()
			_esc_switch_mode_button.name = "SwitchModeButton"
			_esc_switch_mode_button.visible = is_host_or_offline
			_esc_switch_mode_button.pressed.connect(_on_switch_mode_rematch_pressed)
			esc_vbox.add_child(_esc_switch_mode_button)
		_refresh_esc_mode_button_text()

		if _esc_debug_bomb_fuse_button == null and esc_vbox.get_node_or_null("DebugBombFuseButton") == null:
			_esc_debug_bomb_fuse_button = Button.new()
			_esc_debug_bomb_fuse_button.name = "DebugBombFuseButton"
			_esc_debug_bomb_fuse_button.visible = is_host_or_offline
			_esc_debug_bomb_fuse_button.pressed.connect(_on_debug_bomb_fuse_toggled)
			esc_vbox.add_child(_esc_debug_bomb_fuse_button)
		_refresh_debug_bomb_fuse_button_text()

		if _esc_debug_airport_exit_button == null and esc_vbox.get_node_or_null("DebugAirportExitButton") == null:
			_esc_debug_airport_exit_button = Button.new()
			_esc_debug_airport_exit_button.name = "DebugAirportExitButton"
			_esc_debug_airport_exit_button.visible = is_host_or_offline
			_esc_debug_airport_exit_button.pressed.connect(_on_debug_airport_exit_toggled)
			esc_vbox.add_child(_esc_debug_airport_exit_button)
		_refresh_debug_airport_exit_button_text()

		if _esc_debug_simulate_win_button == null and esc_vbox.get_node_or_null("DebugSimulateWinButton") == null:
			_esc_debug_simulate_win_button = Button.new()
			_esc_debug_simulate_win_button.name = "DebugSimulateWinButton"
			_esc_debug_simulate_win_button.text = "Debug: Simulate Win [F4]"
			_esc_debug_simulate_win_button.visible = is_host_or_offline
			_esc_debug_simulate_win_button.pressed.connect(_on_debug_simulate_win_pressed)
			esc_vbox.add_child(_esc_debug_simulate_win_button)
		esc_vbox.move_child(close_settings_button, -1)

	esc_menu.resized.connect(_center_match_menu)
	close_settings_button.pressed.connect(_on_resume_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	leave_button.pressed.connect(_on_leave_button_pressed)

	# Network lifecycle bindings
	if not Engine.is_editor_hint() and NetworkManager != null:
		NetworkManager.player_disconnected.connect(_on_player_disconnected)
		NetworkManager.server_disconnected.connect(_on_server_disconnected)

	# Spawning debug / diagnostic logs
	players_container.child_entered_tree.connect(func(node: Node):
		var online_now: bool = not Engine.is_editor_hint() and NetworkManager != null and NetworkManager.is_online()
		var is_srv: bool = multiplayer.is_server() if online_now else false
		var is_auth: bool = node.is_multiplayer_authority() if online_now else false
		print("TestGym [%s]: Child entered Players: %s (auth: %d, is_auth: %s)" % [
			"Server" if is_srv else "Client",
			node.name,
			node.get_multiplayer_authority(),
			is_auth
		])
	)

	players_container.child_exiting_tree.connect(func(node: Node):
		var online_now: bool = not Engine.is_editor_hint() and NetworkManager != null and NetworkManager.is_online()
		var is_srv: bool = multiplayer.is_server() if online_now else false
		print("TestGym [%s]: Child exited Players: %s" % [
			"Server" if is_srv else "Client",
			node.name
		])
	)

	# Arena loading handshake
	if multiplayer.is_server():
		_init_expected_peers_and_roles()
		_on_peer_arena_loaded(1)
		# If launched via Solo Playtest (0 remote peers connected), mark slot 2 ready so Peer 1 spawns immediately
		if not Engine.is_editor_hint() and NetworkManager != null and NetworkManager.is_online() and multiplayer.get_peers().is_empty():
			_on_peer_arena_loaded(2)
	else:
		notify_arena_ready.rpc_id(1)

	if "--auto-ready" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		get_tree().create_timer(2.0).timeout.connect(func():
			print("TestGym [--auto-ready]: Automated ENet integration verified! Players in tree: %d" % players_container.get_child_count())
			get_tree().quit(0)
		)


func _ensure_match_end_ui() -> void:
	if _match_end_ui != null and is_instance_valid(_match_end_ui):
		return
	var target_ui: CanvasLayer = ui_layer if ui_layer != null else get_node_or_null("UI") as CanvasLayer
	if target_ui == null:
		return
	var existing: Node = target_ui.get_node_or_null("MatchEndOverlayUI")
	if existing is MatchEndOverlayUI:
		_match_end_ui = existing as MatchEndOverlayUI
	else:
		_match_end_ui = MATCH_END_UI_SCRIPT.new() as MatchEndOverlayUI
		_match_end_ui.name = "MatchEndOverlayUI"
		target_ui.add_child(_match_end_ui)
	if not _match_end_ui.rematch_requested.is_connected(_on_rematch_requested):
		_match_end_ui.rematch_requested.connect(_on_rematch_requested)
	if not _match_end_ui.switch_mode_requested.is_connected(_on_switch_mode_rematch_pressed):
		_match_end_ui.switch_mode_requested.connect(_on_switch_mode_rematch_pressed)
	if not _match_end_ui.return_to_lobby_requested.is_connected(_on_leave_button_pressed):
		_match_end_ui.return_to_lobby_requested.connect(_on_leave_button_pressed)


func _ensure_spawner_cheatsheet_ui() -> void:
	if _spawner_cheatsheet_ui != null and is_instance_valid(_spawner_cheatsheet_ui):
		return
	var target_ui: CanvasLayer = ui_layer if ui_layer != null else get_node_or_null("UI") as CanvasLayer
	if target_ui == null:
		return
	var existing: Node = target_ui.get_node_or_null("SpawnerCheatsheetUI")
	if existing is Control:
		_spawner_cheatsheet_ui = existing as Control
	else:
		_spawner_cheatsheet_ui = SPAWNER_CHEATSHEET_UI_SCRIPT.new() as Control
		_spawner_cheatsheet_ui.name = "SpawnerCheatsheetUI"
		target_ui.add_child(_spawner_cheatsheet_ui)
	if not _spawner_cheatsheet_ui.is_connected("apply_and_reroll_requested", _on_cheatsheet_apply_and_reroll):
		_spawner_cheatsheet_ui.connect("apply_and_reroll_requested", _on_cheatsheet_apply_and_reroll)
	if not _spawner_cheatsheet_ui.is_connected("closed", _on_cheatsheet_closed):
		_spawner_cheatsheet_ui.connect("closed", _on_cheatsheet_closed)


func open_spawner_cheatsheet() -> void:
	_ensure_spawner_cheatsheet_ui()
	if _spawner_cheatsheet_ui == null:
		return
	if esc_menu != null:
		esc_menu.visible = false
	_spawner_cheatsheet_ui.call("open_cheatsheet", true, _last_populate_summary)
	if not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_cheatsheet_apply_and_reroll() -> void:
	trigger_rematch(is_sandbox_mode)
	if _spawner_cheatsheet_ui != null and _spawner_cheatsheet_ui.visible:
		_spawner_cheatsheet_ui.call("set_latest_populate_summary", _last_populate_summary)
		if not Engine.is_editor_hint():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_cheatsheet_closed() -> void:
	if not Engine.is_editor_hint():
		var end_vis: bool = _match_end_ui != null and _match_end_ui.visible
		var esc_vis: bool = esc_menu != null and esc_menu.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (end_vis or esc_vis) else Input.MOUSE_MODE_CAPTURED


func _refresh_esc_mode_button_text() -> void:
	if _esc_switch_mode_button != null:
		_esc_switch_mode_button.text = (
			"Switch to Full Match (New Seed)"
			if is_sandbox_mode
			else "Switch to Dev Sandbox Gym"
		)


func _on_debug_bomb_fuse_toggled() -> void:
	if GameConfig == null:
		return
	GameConfig.debug_long_bomb_fuse = not GameConfig.debug_long_bomb_fuse
	_refresh_debug_bomb_fuse_button_text()


func _refresh_debug_bomb_fuse_button_text() -> void:
	if _esc_debug_bomb_fuse_button == null:
		return
	var enabled: bool = GameConfig != null and GameConfig.debug_long_bomb_fuse
	var secs: float = GameConfig.debug_long_bomb_fuse_seconds if GameConfig != null else 8.0
	_esc_debug_bomb_fuse_button.text = "Debug Bomb Fuse (%.1fs): %s" % [secs, "ON" if enabled else "OFF"]


func _on_debug_airport_exit_toggled() -> void:
	if GameConfig == null:
		return
	GameConfig.debug_show_airport_exit = not GameConfig.debug_show_airport_exit
	_refresh_debug_airport_exit_button_text()
	_refresh_airport_exit_debug_visuals()


func _refresh_debug_airport_exit_button_text() -> void:
	if _esc_debug_airport_exit_button == null:
		return
	var enabled: bool = GameConfig != null and GameConfig.debug_show_airport_exit
	_esc_debug_airport_exit_button.text = "Debug Airport Exit [F3]: %s" % ("ON" if enabled else "OFF")


func _on_debug_simulate_win_pressed() -> void:
	if _is_network_active() and not multiplayer.is_server():
		return
	if MatchManager == null:
		return
	if MatchManager.match_state == MatchManager.MatchState.ENDED:
		return
	if MatchManager.match_state != MatchManager.MatchState.IN_PROGRESS:
		MatchManager.start_new_match(_get_active_match_peer_ids())
	var winner_peer_id: int = multiplayer.get_unique_id() if _is_network_active() else 1
	if MatchManager.eliminated_peers.get(winner_peer_id, false):
		for pid in _get_active_match_peer_ids():
			if not MatchManager.eliminated_peers.get(pid, false):
				winner_peer_id = pid
				break
	var req_count: int = GameConfig.required_objectives_count if GameConfig != null else 4
	MatchManager.report_airport_exit_reached(winner_peer_id, req_count)


func _ensure_shared_airport_exit() -> void:
	var exit_door := get_node_or_null("SharedAirportExit") as StaticBody3D
	if exit_door == null:
		exit_door = AIRPORT_EXIT_SCENE.instantiate() as StaticBody3D
		exit_door.name = "SharedAirportExit"
		add_child(exit_door)

	var ladder_layout := get_node_or_null("BuildingComplex3/LadderLayout")
	if ladder_layout != null:
		if ladder_layout.has_signal("airport_exit_placed") and not ladder_layout.is_connected("airport_exit_placed", _on_airport_exit_placed):
			ladder_layout.connect("airport_exit_placed", _on_airport_exit_placed)
		if ladder_layout.has_method("get_airport_exit_placement"):
			var placement: Dictionary = ladder_layout.call("get_airport_exit_placement")
			if not placement.is_empty():
				_on_airport_exit_placed(placement)
				return
	_refresh_airport_exit_debug_visuals()


func _on_airport_exit_placed(placement: Dictionary) -> void:
	_airport_exit_placement = placement.duplicate()
	var exit_door := get_node_or_null("SharedAirportExit") as StaticBody3D
	if exit_door != null and placement.has("world_transform"):
		exit_door.global_transform = placement["world_transform"] as Transform3D
	_refresh_airport_exit_debug_visuals()


func _refresh_airport_exit_debug_visuals() -> void:
	var enabled: bool = GameConfig != null and GameConfig.debug_show_airport_exit
	var summary := "%s | %s (%s)" % [
		String(_airport_exit_placement.get("room_name", "Pending")),
		String(_airport_exit_placement.get("boundary", "?")),
		String(_airport_exit_placement.get("facing", "?")),
	]

	var exit_door := get_node_or_null("SharedAirportExit") as Node3D
	if exit_door != null:
		var beacon := exit_door.get_node_or_null("AirportExitDebugBeacon") as Node3D
		if enabled:
			if beacon == null:
				beacon = Node3D.new()
				beacon.name = "AirportExitDebugBeacon"
				exit_door.add_child(beacon)

				var pillar := MeshInstance3D.new()
				pillar.name = "Pillar"
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.14
				cyl.bottom_radius = 0.22
				cyl.height = 4.5
				pillar.mesh = cyl
				pillar.position = Vector3(0.0, 2.25, 0.25)
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(1.0, 0.85, 0.15, 0.55)
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.78, 0.10, 1.0)
				mat.emission_energy_multiplier = 2.0
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.no_depth_test = true
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				pillar.material_override = mat
				beacon.add_child(pillar)

				var lbl := Label3D.new()
				lbl.name = "BeaconLabel"
				lbl.position = Vector3(0.0, 3.2, 0.25)
				lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lbl.no_depth_test = true
				lbl.fixed_size = true
				lbl.pixel_size = 0.0045
				lbl.font_size = 36
				lbl.outline_size = 10
				lbl.modulate = Color(1.0, 0.90, 0.22, 1.0)
				beacon.add_child(lbl)

			var lbl_node := beacon.get_node_or_null("BeaconLabel") as Label3D
			if lbl_node != null:
				lbl_node.text = "AIRPORT EXIT\n" + summary
			beacon.visible = true
		elif beacon != null:
			beacon.visible = false

	var target_ui: CanvasLayer = ui_layer if ui_layer != null else get_node_or_null("UI") as CanvasLayer
	if target_ui != null:
		if _airport_exit_debug_hud_label == null or not is_instance_valid(_airport_exit_debug_hud_label):
			_airport_exit_debug_hud_label = target_ui.get_node_or_null("AirportExitDebugHUDLabel") as Label
		if enabled:
			if _airport_exit_debug_hud_label == null:
				_airport_exit_debug_hud_label = Label.new()
				_airport_exit_debug_hud_label.name = "AirportExitDebugHUDLabel"
				_airport_exit_debug_hud_label.anchor_left = 0.5
				_airport_exit_debug_hud_label.anchor_right = 0.5
				_airport_exit_debug_hud_label.offset_left = -220.0
				_airport_exit_debug_hud_label.offset_right = 220.0
				_airport_exit_debug_hud_label.offset_top = 14.0
				_airport_exit_debug_hud_label.offset_bottom = 42.0
				_airport_exit_debug_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				_airport_exit_debug_hud_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.22, 1.0))
				_airport_exit_debug_hud_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 1.0))
				_airport_exit_debug_hud_label.add_theme_constant_override("outline_size", 4)
				target_ui.add_child(_airport_exit_debug_hud_label)
			_airport_exit_debug_hud_label.text = "[DEBUG F3] Airport Exit: " + summary
			_airport_exit_debug_hud_label.visible = true
		elif _airport_exit_debug_hud_label != null:
			_airport_exit_debug_hud_label.visible = false


func _configure_level_props_for_mode(sandbox: bool) -> void:
	_ensure_shared_airport_exit()
	if sandbox:
		_spawn_test_pickups()
		_spawn_test_props()
		_spawn_audio_test_harness()
	else:
		var pickups_node: Node = get_node_or_null("TestPickups")
		if pickups_node != null:
			remove_child(pickups_node)
			pickups_node.queue_free()
		var props_node: Node = get_node_or_null("TestStep1Props")
		if props_node != null:
			remove_child(props_node)
			props_node.queue_free()
		var audio_node: Node = get_node_or_null("TestAudioGym")
		if audio_node != null:
			remove_child(audio_node)
			audio_node.queue_free()


func _spawn_test_pickups() -> void:
	if get_node_or_null("TestPickups") != null:
		return
	var container := Node3D.new()
	container.name = "TestPickups"
	add_child(container)

	var test_items: Array[Dictionary] = [
		{"id": "BRIEFCASE", "pos": Vector3(-6.9, 0.0, -2.5)},
		{"id": "KEY", "pos": Vector3(-6.1, 0.0, -2.5)},
		{"id": "MONEY", "pos": Vector3(-5.3, 0.0, -2.5)},
		{"id": "PASSPORT", "pos": Vector3(-4.5, 0.0, -2.5)},
		{"id": "PLANS", "pos": Vector3(-3.7, 0.0, -2.5)},
		{"id": "BUCKET", "pos": Vector3(-2.9, 0.0, -2.5)},
		{"id": "TRIPWIRE", "pos": Vector3(-2.1, 0.0, -2.5)},
		{"id": "SPRING", "pos": Vector3(-1.3, 0.0, -2.5)},
		{"id": "BOMB", "pos": Vector3(-0.5, 0.0, -2.5)},
		{"id": "DART_GUN", "pos": Vector3(0.3, 0.0, -2.5)}
	]
	for i in range(test_items.size()):
		var entry: Dictionary = test_items[i]
		var pickup: StaticBody3D = PICKUP_SCENE.instantiate() as StaticBody3D
		pickup.name = "TestPickup_%d_%s" % [i, str(entry["id"])]
		pickup.set("item_id", str(entry["id"]))
		container.add_child(pickup)
		pickup.position = entry["pos"]


func _spawn_test_props() -> void:
	if get_node_or_null("TestStep1Props") != null:
		return
	var props_root := Node3D.new()
	props_root.name = "TestStep1Props"
	add_child(props_root)

	var loot_drawer := DRAWER_SCENE.instantiate() as StaticBody3D
	loot_drawer.name = "TestDrawer_Loot"
	loot_drawer.set("container_id", "Loot Desk (Left)")
	var loot_items: Array[String] = ["KEY", "SPRING", "BOMB"]
	loot_drawer.set("stored_items", loot_items)
	var loot_right: Node = loot_drawer.get_node_or_null("RightUpperDrawer")
	if loot_right != null:
		loot_right.set("container_id", "Loot Desk (Right)")
		var loot_right_items: Array[String] = ["BRIEFCASE", "KEY", "SPRING"]
		loot_right.set("stored_items", loot_right_items)
	props_root.add_child(loot_drawer)
	loot_drawer.position = Vector3(-7.0, 0.0, -6.5)

	var rigged_drawer := DRAWER_SCENE.instantiate() as StaticBody3D
	rigged_drawer.name = "TestDrawer_Rigged"
	rigged_drawer.set("container_id", "Rigged Desk (Left)")
	rigged_drawer.set("armed_spring", true)
	var rigged_items: Array[String] = ["PASSPORT"]
	rigged_drawer.set("stored_items", rigged_items)
	var rigged_right: Node = rigged_drawer.get_node_or_null("RightUpperDrawer")
	if rigged_right != null:
		rigged_right.set("container_id", "Rigged Desk (Right)")
		rigged_right.set("armed_spring", false)
		var rigged_right_items: Array[String] = ["KEY"]
		rigged_right.set("stored_items", rigged_right_items)
	props_root.add_child(rigged_drawer)
	rigged_drawer.position = Vector3(-4.2, 0.0, -6.5)

	var door := EMBASSY_DOOR_SCENE.instantiate() as Node3D
	door.name = "TestEmbassyDoor"
	props_root.add_child(door)
	door.position = Vector3(-1.8, 0.0, -6.5)

	var small_drawer := SMALL_DRAWER_SCENE.instantiate() as StaticBody3D
	small_drawer.name = "TestDrawer_Small"
	small_drawer.set("container_id", "Small Desk (Middle)")
	var small_items: Array[String] = ["BRIEFCASE"]
	small_drawer.set("stored_items", small_items)
	props_root.add_child(small_drawer)
	small_drawer.position = Vector3(-0.3, 0.0, -6.5)


func _spawn_audio_test_harness() -> void:
	if get_node_or_null("TestAudioGym") != null:
		return
	var audio_root := Node3D.new()
	audio_root.name = "TestAudioGym"
	add_child(audio_root)

	var env_layer: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
	var patch_specs: Array[Dictionary] = [
		{"name": "Wood", "surface": "wood", "pos": Vector3(-6.5, 0.015, -4.5), "color": Color(0.55, 0.34, 0.18)},
		{"name": "Tile", "surface": "tile", "pos": Vector3(-4.7, 0.015, -4.5), "color": Color(0.78, 0.80, 0.84)},
		{"name": "Carpet", "surface": "carpet", "pos": Vector3(-2.9, 0.015, -4.5), "color": Color(0.58, 0.18, 0.22)},
		{"name": "Metal", "surface": "metal", "pos": Vector3(-1.1, 0.015, -4.5), "color": Color(0.42, 0.46, 0.52)},
	]
	for spec in patch_specs:
		var patch_body := StaticBody3D.new()
		patch_body.name = "SurfacePatch_%s" % str(spec["name"])
		patch_body.collision_layer = env_layer
		patch_body.collision_mask = 0
		patch_body.position = spec["pos"]
		patch_body.set_meta("surface", str(spec["surface"]))
		var phys_mat := PhysicsMaterial.new()
		phys_mat.resource_name = str(spec["surface"])
		patch_body.physics_material_override = phys_mat

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.5, 0.03, 1.5)
		col.shape = box
		patch_body.add_child(col)

		var mesh_inst := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(1.5, 0.03, 1.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec["color"]
		mesh_inst.mesh = box_mesh
		mesh_inst.material_override = mat
		patch_body.add_child(mesh_inst)

		var lbl := Label3D.new()
		lbl.text = str(spec["name"]).to_upper()
		lbl.position = Vector3(0.0, 0.45, 0.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 36
		patch_body.add_child(lbl)

		audio_root.add_child(patch_body)

	var hall_zone: Area3D = ACOUSTIC_ZONE_SCRIPT.new()
	hall_zone.name = "AcousticZone_LargeHall"
	hall_zone.reverb_preset = ACOUSTIC_ZONE_SCRIPT.ReverbPreset.LARGE_HALL
	hall_zone.zone_priority = 1
	hall_zone.position = Vector3(-4.5, 1.5, -4.5)
	var hall_col := CollisionShape3D.new()
	var hall_shape := BoxShape3D.new()
	hall_shape.size = Vector3(8.5, 3.0, 8.5)
	hall_col.shape = hall_shape
	hall_zone.add_child(hall_col)
	audio_root.add_child(hall_zone)

	# Test walled acoustic room with openable door & looping dummy emitter
	var room_root := Node3D.new()
	room_root.name = "TestAcousticRoom"
	audio_root.add_child(room_root)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.68, 0.70, 0.74)

	var wall_parts: Array[Dictionary] = [
		{"name": "BackWall", "pos": Vector3(4.5, 1.35, -6.1), "size": Vector3(3.36, 2.7, 0.16)},
		{"name": "LeftWall", "pos": Vector3(2.9, 1.35, -4.5), "size": Vector3(0.16, 2.7, 3.2)},
		{"name": "RightWall", "pos": Vector3(6.1, 1.35, -4.5), "size": Vector3(0.16, 2.7, 3.2)},
		{"name": "Ceiling", "pos": Vector3(4.5, 2.7, -4.5), "size": Vector3(3.36, 0.16, 3.36)},
		{"name": "FrontWallLeft", "pos": Vector3(3.37, 1.35, -2.9), "size": Vector3(0.94, 2.7, 0.16)},
		{"name": "FrontWallRight", "pos": Vector3(5.63, 1.35, -2.9), "size": Vector3(0.94, 2.7, 0.16)},
		{"name": "FrontTransom", "pos": Vector3(4.5, 2.425, -2.9), "size": Vector3(1.32, 0.55, 0.16)},
	]
	for part in wall_parts:
		var wall_body := StaticBody3D.new()
		wall_body.name = str(part["name"])
		wall_body.collision_layer = env_layer
		wall_body.collision_mask = 0
		wall_body.position = part["pos"]

		var wcol := CollisionShape3D.new()
		var wbox := BoxShape3D.new()
		wbox.size = part["size"]
		wcol.shape = wbox
		wall_body.add_child(wcol)

		var wmesh := MeshInstance3D.new()
		var wbox_mesh := BoxMesh.new()
		wbox_mesh.size = part["size"]
		wmesh.mesh = wbox_mesh
		wmesh.material_override = wall_mat
		wall_body.add_child(wmesh)

		room_root.add_child(wall_body)

	var test_door := EMBASSY_DOOR_SCENE.instantiate() as Node3D
	test_door.name = "TestAcousticDoor"
	room_root.add_child(test_door)
	test_door.position = Vector3(4.5, 0.0, -2.9)

	var small_zone: Area3D = ACOUSTIC_ZONE_SCRIPT.new()
	small_zone.name = "AcousticZone_SmallRoom"
	small_zone.reverb_preset = ACOUSTIC_ZONE_SCRIPT.ReverbPreset.SMALL_ROOM
	small_zone.zone_priority = 2
	small_zone.position = Vector3(4.5, 1.25, -4.5)
	var small_col := CollisionShape3D.new()
	var small_shape := BoxShape3D.new()
	small_shape.size = Vector3(3.0, 2.5, 3.0)
	small_col.shape = small_shape
	small_zone.add_child(small_col)
	room_root.add_child(small_zone)

	var dummy_emitter: AudioStreamPlayer3D = OCCLUSION_EMITTER_SCRIPT.new()
	dummy_emitter.name = "OcclusionDummyEmitter"
	dummy_emitter.position = Vector3(4.5, 1.35, -5.0)
	dummy_emitter.max_distance = 16.0
	dummy_emitter.unit_size = 4.0
	dummy_emitter.parent_bus = &"SFX"
	dummy_emitter.always_evaluate_occlusion = true

	var emitter_vis := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.16
	sph.height = 0.32
	var sph_mat := StandardMaterial3D.new()
	sph_mat.albedo_color = Color(0.2, 0.85, 0.95)
	sph_mat.emission_enabled = true
	sph_mat.emission = Color(0.15, 0.65, 0.85)
	emitter_vis.mesh = sph
	emitter_vis.material_override = sph_mat
	dummy_emitter.add_child(emitter_vis)

	var emitter_lbl := Label3D.new()
	emitter_lbl.text = "Occlusion Dummy Emitter"
	emitter_lbl.position = Vector3(0.0, 0.35, 0.0)
	emitter_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	emitter_lbl.font_size = 32
	dummy_emitter.add_child(emitter_lbl)

	room_root.add_child(dummy_emitter)


func _is_upper_floor_enabled() -> bool:
	if MatchManager != null and not MatchManager.active_spawner_config.is_empty():
		var cfg: Dictionary = MatchManager.active_spawner_config
		if cfg.has("enable_upper_floor"):
			return bool(cfg["enable_upper_floor"])
		if cfg.has("active_preset_players"):
			return int(cfg["active_preset_players"]) > 2
	if GameConfig != null:
		return GameConfig.spawner_enable_upper_floor
	return true


func _collect_building_player_spawn_transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var building: Node = get_node_or_null("BuildingComplex3")
	if building == null:
		building = get_node_or_null("BuildingComplex2")
	if building == null:
		return result

	var markers: Array[Dictionary] = []
	var room_paths: Array[String] = ["Rooms"]
	if _is_upper_floor_enabled():
		room_paths.append("SecondFloor/Rooms")
	for room_path in room_paths:
		var room_root: Node = building.get_node_or_null(room_path)
		if room_root == null:
			continue
		for room in room_root.get_children():
			var pts: Node = room.get_node_or_null("MatchPlayerSpawnPoints")
			if pts == null:
				continue
			for child in pts.get_children():
				if child is Marker3D:
					markers.append({
						"sort_key": "%s/%s/%s" % [room_path, String(room.name), String(child.name)],
						"marker": child as Marker3D
					})

	markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["sort_key"]) < str(b["sort_key"])
	)

	var p_root: Node3D = players_container if players_container != null else get_node_or_null("Players") as Node3D
	var inv_players_xform: Transform3D = Transform3D.IDENTITY
	if p_root != null:
		inv_players_xform = p_root.global_transform.affine_inverse() if p_root.is_inside_tree() else Transform3D(Basis.IDENTITY, -p_root.position)

	for entry in markers:
		var marker: Marker3D = entry["marker"] as Marker3D
		if marker != null and marker.is_inside_tree():
			result.append(inv_players_xform * marker.global_transform)
	return result


func _assign_random_player_spawns(seed_value: int) -> void:
	_cached_player_spawn_transforms = _collect_building_player_spawn_transforms()
	var count: int = _cached_player_spawn_transforms.size()
	if count <= 0:
		count = FULL_MATCH_SPAWN_POINTS.size()

	var indices: Array[int] = []
	for i in range(count):
		indices.append(i)

	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value ^ 0x53504157
	else:
		rng.randomize()

	for i in range(indices.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp

	active_player_spawn_indices.clear()
	for slot in range(1, 5):
		active_player_spawn_indices[slot] = indices[(slot - 1) % count]


func _resolve_spawn_point(slot: int) -> Vector3:
	if not is_inside_tree() or is_sandbox_mode:
		return SPAWN_POINTS.get(slot, Vector3.ZERO)
	if _cached_player_spawn_transforms.is_empty():
		_cached_player_spawn_transforms = _collect_building_player_spawn_transforms()
	if active_player_spawn_indices.is_empty():
		var fallback_seed: int = MatchManager.match_seed if (MatchManager != null and MatchManager.match_seed != 0) else 0
		_assign_random_player_spawns(fallback_seed)
	var idx: int = int(active_player_spawn_indices.get(slot, slot - 1))
	if idx >= 0 and idx < _cached_player_spawn_transforms.size():
		return _cached_player_spawn_transforms[idx].origin
	return FULL_MATCH_SPAWN_POINTS.get(slot, SPAWN_POINTS.get(slot, Vector3.ZERO))


func _resolve_spawn_yaw(slot: int) -> float:
	if not is_inside_tree() or is_sandbox_mode:
		return 0.0
	if _cached_player_spawn_transforms.is_empty():
		_cached_player_spawn_transforms = _collect_building_player_spawn_transforms()
	if active_player_spawn_indices.is_empty():
		var fallback_seed: int = MatchManager.match_seed if (MatchManager != null and MatchManager.match_seed != 0) else 0
		_assign_random_player_spawns(fallback_seed)
	var idx: int = int(active_player_spawn_indices.get(slot, slot - 1))
	if idx >= 0 and idx < _cached_player_spawn_transforms.size():
		return _cached_player_spawn_transforms[idx].basis.get_euler().y
	return float(FULL_MATCH_SPAWN_YAWS.get(slot, 0.0))


func _on_match_started(seed_value: int) -> void:
	var ladder_layout := get_node_or_null("BuildingComplex3/LadderLayout")
	if ladder_layout != null and ladder_layout.has_method("relocate_airport_exit_for_seed"):
		ladder_layout.call("relocate_airport_exit_for_seed", seed_value)
	_assign_random_player_spawns(seed_value)
	if not is_sandbox_mode:
		var p_root: Node = players_container if players_container != null else get_node_or_null("Players")
		if p_root != null:
			for child in p_root.get_children():
				var pid: int = child.name.to_int()
				var slot: int = int(child.get("spy_role"))
				if slot <= 0 and MatchManager != null and MatchManager.has_method("get_peer_role"):
					slot = MatchManager.get_peer_role(pid)
				if slot <= 0:
					slot = 1 if pid == 1 else 2
				var sp_pos: Vector3 = _resolve_spawn_point(slot)
				var sp_yaw: float = _resolve_spawn_yaw(slot)
				if child.has_method("reset_for_rematch"):
					child.call("reset_for_rematch", sp_pos, sp_yaw)
				elif child is Node3D:
					(child as Node3D).position = sp_pos
					(child as Node3D).rotation.y = sp_yaw

	var spawner := MATCH_SPAWNER_SCRIPT.new()
	var active_cfg: Dictionary = MatchManager.active_spawner_config if (MatchManager != null and not MatchManager.active_spawner_config.is_empty()) else {}
	var skip_rooms: Array[String] = []
	if is_sandbox_mode:
		skip_rooms.append("Room_2_2")
	_last_populate_summary = spawner.populate_level(self, seed_value, DRAWER_SCENE, PICKUP_SCENE, skip_rooms, active_cfg)
	if _spawner_cheatsheet_ui != null and is_instance_valid(_spawner_cheatsheet_ui):
		_spawner_cheatsheet_ui.call("set_latest_populate_summary", _last_populate_summary)


func _on_match_ended(winner_peer_id: int, reason: String) -> void:
	if players_container != null:
		for child in players_container.get_children():
			var container: Variant = child.get("active_container")
			if container != null and is_instance_valid(container) and container.has_method("close_container"):
				container.call("close_container", child.name.to_int(), child, true)
	if esc_menu != null:
		esc_menu.visible = false
	if not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ensure_match_end_ui()
	if _match_end_ui != null:
		var my_id: int = multiplayer.get_unique_id() if _is_network_active() else 1
		var is_srv: bool = (not _is_network_active()) or multiplayer.is_server()
		var actions := MatchEndOverlayUI.Actions.LEAVE_ONLY
		if is_srv:
			if NetworkManager.current_mode == NetworkManager.NetworkMode.ENET_LOCAL or not _is_network_active():
				actions = MatchEndOverlayUI.Actions.LOCAL_HOST
			elif SessionManager.current_room_code not in ["", "NONE"]:
				actions = MatchEndOverlayUI.Actions.PRIVATE_HOST
		var totg_clips: Array[Dictionary] = []
		for p in get_tree().get_nodes_in_group("spy_players"):
			if p != null and is_instance_valid(p) and (not _is_network_active() or p.is_multiplayer_authority()):
				if p.has_method("get_crt_replay_ui"):
					var crt_ui: CRTReplayMonitorUI = p.get_crt_replay_ui()
					if crt_ui != null:
						totg_clips = crt_ui.get_match_archive()
				break
		_match_end_ui.show_match_result(winner_peer_id, my_id, reason, actions, is_sandbox_mode, totg_clips)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F3:
		_on_debug_airport_exit_toggled()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F4:
		if not _is_network_active() or multiplayer.is_server():
			_on_debug_simulate_win_pressed()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F12:
		if _is_network_active() and not multiplayer.is_server():
			return
		if MatchManager != null and MatchManager.match_state == MatchManager.MatchState.ENDED:
			return
		if _spawner_cheatsheet_ui != null and _spawner_cheatsheet_ui.visible:
			_spawner_cheatsheet_ui.call("close_cheatsheet")
		if settings_menu.is_visible_in_tree():
			_on_resume_pressed()
		else:
			_open_match_menu(true)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F2 and (settings_menu.is_visible_in_tree() or (_spawner_cheatsheet_ui != null and _spawner_cheatsheet_ui.visible)):
		var is_host_or_offline: bool = (not _is_network_active()) or multiplayer.is_server()
		if is_host_or_offline:
			_ensure_spawner_cheatsheet_ui()
			if _spawner_cheatsheet_ui != null:
				if _spawner_cheatsheet_ui.visible:
					_spawner_cheatsheet_ui.call("close_cheatsheet")
				else:
					open_spawner_cheatsheet()
				get_viewport().set_input_as_handled()
				return
	if _spawner_cheatsheet_ui != null and _spawner_cheatsheet_ui.visible:
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ESCAPE):
			_spawner_cheatsheet_ui.call("close_cheatsheet")
			get_viewport().set_input_as_handled()
			return
	if MatchManager != null and MatchManager.match_state == MatchManager.MatchState.ENDED:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ESCAPE):
		toggle_esc_menu()
		get_viewport().set_input_as_handled()


func toggle_esc_menu() -> void:
	if esc_menu.visible:
		_on_resume_pressed()
	else:
		_open_match_menu(false)


func _open_match_menu(show_settings: bool) -> void:
	match_menu.visible = not show_settings
	settings_menu.visible = show_settings
	if show_settings:
		_refresh_esc_mode_button_text()
		_refresh_debug_bomb_fuse_button_text()
		_refresh_debug_airport_exit_button_text()
	esc_menu.show()
	esc_menu.reset_size()
	_center_match_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _center_match_menu() -> void:
	var viewport_size := esc_menu.get_viewport_rect().size
	esc_menu.position = (viewport_size - esc_menu.size) * 0.5


func _on_resume_pressed() -> void:
	esc_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_leave_button_pressed() -> void:
	_terminate_match("Local player selected Leave to Lobby")


func _on_rematch_requested() -> void:
	trigger_rematch(is_sandbox_mode)


func _on_switch_mode_rematch_pressed() -> void:
	trigger_rematch(not is_sandbox_mode)


func _get_active_match_peer_ids() -> Array[int]:
	var active_peers: Array[int] = []
	var p_root: Node = players_container if players_container != null else get_node_or_null("Players")
	if p_root != null:
		for child in p_root.get_children():
			if child.name.is_valid_int():
				active_peers.append(child.name.to_int())
	if active_peers.is_empty():
		if not expected_peers.is_empty():
			return expected_peers.duplicate()
		return [1, 2]
	return active_peers


func trigger_rematch(next_sandbox_mode: bool, custom_seed: int = 0) -> void:
	if _is_network_active() and not multiplayer.is_server():
		return
	if _is_network_active() and is_inside_tree():
		_rpc_prepare_arena_round.rpc(next_sandbox_mode)
	else:
		_rpc_prepare_arena_round(next_sandbox_mode)

	var active_peers: Array[int] = _get_active_match_peer_ids()
	if MatchManager != null and is_inside_tree():
		MatchManager.start_new_match(active_peers, custom_seed)


@rpc("authority", "call_local", "reliable")
func _rpc_prepare_arena_round(next_sandbox_mode: bool) -> void:
	is_sandbox_mode = next_sandbox_mode
	if GameConfig != null:
		GameConfig.sandbox_gym_mode = next_sandbox_mode

	_ensure_match_end_ui()
	if _match_end_ui != null:
		_match_end_ui.hide_overlay()
	if esc_menu != null:
		esc_menu.visible = false
	_refresh_esc_mode_button_text()

	_clear_dynamic_round_entities()
	_reset_all_doors_for_round()
	_configure_level_props_for_mode(is_sandbox_mode)

	var p_root: Node = players_container if players_container != null else get_node_or_null("Players")
	if p_root != null:
		for child in p_root.get_children():
			var pid: int = child.name.to_int()
			var slot: int = int(child.get("spy_role"))
			if slot <= 0 and MatchManager != null and MatchManager.has_method("get_peer_role"):
				slot = MatchManager.get_peer_role(pid)
			if slot <= 0:
				slot = 1 if pid == 1 else 2
			if child.has_method("reset_for_rematch"):
				child.call("reset_for_rematch", _resolve_spawn_point(slot), _resolve_spawn_yaw(slot))

	if not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _clear_dynamic_round_entities() -> void:
	for child in get_children():
		var c_name: String = String(child.name)
		if (
			c_name.begins_with("Dropped_")
			or c_name.begins_with("Tripwire_")
			or c_name.begins_with("ThrownBomb_")
			or (child is StaticBody3D and child.has_method("get_briefcase_container"))
		):
			remove_child(child)
			child.queue_free()


func _reset_all_doors_for_round() -> void:
	for node in find_children("*", "", true, false):
		if node.has_method("rig_water_bucket") and node.get("is_open") != null:
			node.set("has_rigged_bucket", false)
			node.set("bucket_owner_peer_id", 0)
			node.set("is_open", false)
			if node.get("_swing_tween") != null:
				var tw: Variant = node.get("_swing_tween")
				if tw is Tween and (tw as Tween).is_valid():
					(tw as Tween).kill()
			if node.get("_swing") != null:
				var sw: Variant = node.get("_swing")
				if sw is Tween and (sw as Tween).is_valid():
					(sw as Tween).kill()
			var bv: Variant = node.get("_bucket_visual")
			if bv is CanvasItem:
				(bv as CanvasItem).visible = false
			elif bv is Node3D:
				(bv as Node3D).visible = false
			if bv is Node:
				var hcol: CollisionShape3D = (bv as Node).get_node_or_null("BucketHitbox/CollisionShape3D") as CollisionShape3D
				if hcol != null:
					hcol.disabled = true
			if node.get("open_fraction") != null:
				node.set("open_fraction", 0.0)
				node.set("current_target_angle_rad", 0.0)
				var hp: Variant = node.get("_hinge_pivot")
				if hp is Node3D:
					(hp as Node3D).rotation.y = 0.0
			elif node.get("_open_fraction") != null and node is Node3D:
				node.set("_busy", false)
				node.set("_open_fraction", 0.0)
				var closed_rot: Variant = node.get("_closed_rotation")
				if closed_rot != null:
					(node as Node3D).rotation.y = float(closed_rot)


# ==========================================
# Arena Loading Handshake (Host Authority)
# ==========================================

func _init_expected_peers_and_roles() -> void:
	expected_peers.clear()
	peer_roles.clear()

	if not Engine.is_editor_hint() and NetworkManager != null and NetworkManager.is_online():
		var remote_peers: PackedInt32Array = multiplayer.get_peers()
		if remote_peers.is_empty():
			# Solo Playtest / Solo Full Match: Peer 1 + dummy Peer 2
			expected_peers = [1, 2]
			peer_roles = {1: 1, 2: 2}
		else:
			expected_peers.append(1)
			for r_pid in remote_peers:
				expected_peers.append(int(r_pid))

			var used_roles: Dictionary = {}
			for pid in expected_peers:
				var existing_role: int = MatchManager.get_peer_role(pid) if (MatchManager != null and MatchManager.has_method("get_peer_role")) else 0
				if existing_role >= 1 and existing_role <= NetworkManager.MAX_PLAYERS and not used_roles.has(existing_role):
					peer_roles[pid] = existing_role
					used_roles[existing_role] = true

			for pid in expected_peers:
				if peer_roles.has(pid):
					continue
				for candidate_role in range(1, NetworkManager.MAX_PLAYERS + 1):
					if not used_roles.has(candidate_role):
						peer_roles[pid] = candidate_role
						used_roles[candidate_role] = true
						break

			expected_peers.sort_custom(func(a: int, b: int) -> bool:
				return int(peer_roles.get(a, 99)) < int(peer_roles.get(b, 99))
			)
	else:
		expected_peers = [1, 2]
		peer_roles = {1: 1, 2: 2}

	if MatchManager != null and MatchManager.has_method("sync_peer_roles"):
		MatchManager.sync_peer_roles(peer_roles)


@rpc("any_peer", "call_local", "reliable")
func notify_arena_ready() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	_on_peer_arena_loaded(sender_id)


func _on_peer_arena_loaded(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	peers_in_arena[peer_id] = true
	print("TestGym: Peer %d confirmed loaded in arena." % peer_id)

	if expected_peers.is_empty():
		_init_expected_peers_and_roles()

	for pid in expected_peers:
		if not peers_in_arena.get(pid, false):
			return

	_spawn_all_players()


func _spawn_all_players() -> void:
	if has_spawned_all:
		return
	has_spawned_all = true
	if is_inside_tree() and GameConfig != null:
		is_sandbox_mode = GameConfig.sandbox_gym_mode

	var participants: Array[int] = expected_peers.duplicate()
	if participants.is_empty():
		participants = [1, 2]
		peer_roles = {1: 1, 2: 2}

	participants.sort_custom(func(a: int, b: int) -> bool:
		return int(peer_roles.get(a, 99)) < int(peer_roles.get(b, 99))
	)

	if MatchManager != null and MatchManager.has_method("sync_peer_roles"):
		MatchManager.sync_peer_roles(peer_roles)

	print("TestGym: All %d peers confirmed arena loaded. Instantiating FFA Spies (mode=%s)..." % [
		participants.size(),
		"Sandbox" if is_sandbox_mode else "FullMatch"
	])

	if not is_sandbox_mode and active_player_spawn_indices.is_empty():
		_assign_random_player_spawns(0)

	for pid in participants:
		var role: int = int(peer_roles.get(pid, 1 if pid == 1 else 2))
		var player_node: CharacterBody3D = PLAYER_SCENE.instantiate()
		player_node.name = str(pid)
		player_node.spy_role = role
		player_node.position = _resolve_spawn_point(role)
		player_node.rotation.y = _resolve_spawn_yaw(role)
		players_container.add_child(player_node)

	if is_inside_tree() and _is_network_active():
		_rpc_prepare_arena_round.rpc(is_sandbox_mode)

	if MatchManager != null and is_inside_tree():
		MatchManager.start_new_match(participants)


func _is_network_active() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# ==========================================
# Teardown & Return to Lobby
# ==========================================

func _scatter_disconnected_player_inventory(player_node: Node, peer_id: int) -> void:
	if player_node == null or not is_instance_valid(player_node):
		return
	var active_c: Variant = player_node.get("active_container")
	if active_c != null and is_instance_valid(active_c) and active_c.has_method("close_container"):
		active_c.call("close_container", peer_id, player_node, true)
	if not player_node.has_method("force_drop_all_hands"):
		return
	var drops: Array = player_node.call("force_drop_all_hands")
	for i in range(drops.size()):
		var entry: Dictionary = drops[i]
		var dropped_id: String = str(entry.get("dropped_item_id", "NONE"))
		if dropped_id == "NONE":
			continue
		var angle: float = (TAU * float(i)) / float(maxi(drops.size(), 1))
		var offset := Vector3(cos(angle) * 0.65, 0.0, sin(angle) * 0.65)
		var drop_pos: Vector3 = (player_node as Node3D).global_position + offset
		if player_node.has_method("_compute_safe_drop_position"):
			drop_pos = player_node.call("_compute_safe_drop_position", offset)
		_disconnect_drop_counter += 1
		var drop_name: String = "Dropped_DC_%d_%s_%d" % [peer_id, dropped_id, _disconnect_drop_counter]
		var b_objs: Array = entry.get("dropped_briefcase_items", [])
		var b_armed_bomb: bool = bool(entry.get("dropped_briefcase_armed_bomb", false))
		var b_bomb_owner: int = int(entry.get("dropped_briefcase_bomb_owner", 0))
		var b_armed_spring: bool = bool(entry.get("dropped_briefcase_armed_spring", false))
		var b_spring_owner: int = int(entry.get("dropped_briefcase_spring_owner", 0))
		var b_item_positions: Dictionary = entry.get("dropped_briefcase_item_positions", {})
		var b_bomb_pos: Vector2 = entry.get("dropped_briefcase_bomb_pos", Vector2(0.5, 0.5))
		if _is_network_active():
			_rpc_spawn_disconnect_drop.rpc(
				dropped_id,
				b_objs.duplicate(),
				drop_pos,
				drop_name,
				b_armed_bomb,
				b_bomb_owner,
				b_armed_spring,
				b_spring_owner,
				b_item_positions.duplicate(),
				b_bomb_pos
			)
		else:
			_rpc_spawn_disconnect_drop(
				dropped_id,
				b_objs.duplicate(),
				drop_pos,
				drop_name,
				b_armed_bomb,
				b_bomb_owner,
				b_armed_spring,
				b_spring_owner,
				b_item_positions.duplicate(),
				b_bomb_pos
			)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_disconnect_drop(
	dropped_id: String,
	b_objs: Array,
	world_pos: Vector3,
	drop_name: String,
	b_armed_bomb: bool = false,
	b_bomb_owner: int = 0,
	b_armed_spring: bool = false,
	b_spring_owner: int = 0,
	b_item_positions: Dictionary = {},
	b_bomb_pos: Vector2 = Vector2(0.5, 0.5)
) -> void:
	var pickup: StaticBody3D = PICKUP_SCENE.instantiate() as StaticBody3D
	if pickup == null:
		return
	pickup.name = drop_name
	pickup.set("item_id", dropped_id)
	var typed_objs: Array[String] = []
	for item in b_objs:
		typed_objs.append(str(item))
	pickup.set("packed_objectives", typed_objs)
	pickup.set("packed_item_positions", b_item_positions.duplicate())
	pickup.set("bomb_norm_pos", b_bomb_pos)
	pickup.set("armed_spring", b_armed_spring)
	pickup.set("spring_owner_peer_id", b_spring_owner)
	pickup.set("armed_bomb", b_armed_bomb)
	pickup.set("bomb_owner_peer_id", b_bomb_owner)
	add_child(pickup)
	pickup.global_position = Vector3(world_pos.x, maxf(world_pos.y, 0.0), world_pos.z)


func _on_player_disconnected(peer_id: int) -> void:
	print("TestGym: Peer %d disconnected during active match." % peer_id)
	if _is_network_active() and not multiplayer.is_server():
		return

	expected_peers.erase(peer_id)
	peers_in_arena.erase(peer_id)

	if not has_spawned_all:
		if multiplayer.get_peers().is_empty():
			_terminate_match("All opponents disconnected.")
			return
		for pid in expected_peers:
			if not peers_in_arena.get(pid, false):
				return
		_spawn_all_players()
		return

	if players_container != null:
		var dc_player: Node = players_container.get_node_or_null(str(peer_id))
		if dc_player != null and is_instance_valid(dc_player):
			_scatter_disconnected_player_inventory(dc_player, peer_id)
			dc_player.queue_free()

	if MatchManager != null and MatchManager.has_method("eliminate_disconnected_peer"):
		MatchManager.eliminate_disconnected_peer(peer_id)

	if _is_network_active() and multiplayer.get_peers().is_empty():
		_terminate_match("All opponents disconnected.")


func _on_server_disconnected() -> void:
	print("TestGym: Host disconnected.")
	_terminate_match("Host disconnected.")


func _terminate_match(reason: String = "") -> void:
	if is_terminating:
		return
	is_terminating = true

	print("TestGym: Terminating match (%s) -> Returning to lobby." % reason)
	if not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Cleanup network peer and EOS session
	NetworkManager.disconnect_session()

	# Clear local players
	for child in players_container.get_children():
		child.queue_free()

	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)


func _setup_interactive_doors() -> void:
	var door_script: Script = preload("res://scenes/BuildingComplex2/interactive_door.gd")
	for door in find_children("*", "MeshInstance3D", true, false):
		if String(door.name).begins_with("Door_") and String(door.name).ends_with("_Door") and door.get_script() == null:
			door.set_script(door_script)
			# Children are already ready when the gym attaches the script.
			door._ready()
