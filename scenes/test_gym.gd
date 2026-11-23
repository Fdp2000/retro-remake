extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const PICKUP_SCENE: PackedScene = preload("res://entities/props/world_item_pickup.tscn")
const EMBASSY_DOOR_SCENE: PackedScene = preload("res://entities/props/embassy_door.tscn")
const DRAWER_SCENE: PackedScene = preload("res://entities/props/searchable_drawer.tscn")
const AIRPORT_EXIT_SCENE: PackedScene = preload("res://entities/props/airport_exit_door.tscn")
const MATCH_SPAWNER_SCRIPT = preload("res://core/match_spawner.gd")
const MATCH_END_UI_SCRIPT = preload("res://ui/match_end_overlay_ui.gd")
const SPAWNER_CHEATSHEET_UI_SCRIPT = preload("res://ui/spawner_cheatsheet_ui.gd")
const LOBBY_SCENE_PATH: String = "res://scenes/lobby.tscn"

const SPAWN_POINTS: Dictionary = {
	1: Vector3(-3.0, 1.0, 0.0),
	2: Vector3(3.0, 1.0, 0.0)
}
const FULL_MATCH_SPAWN_POINTS: Dictionary = {
	1: Vector3(-12.0, 1.0, -9.0), # Room_1_1 (NW Corner — Spy Green)
	2: Vector3(15.0, 1.0, 18.0)   # Room_4_4 (SE Corner — Spy Purple)
}
const FULL_MATCH_SPAWN_YAWS: Dictionary = {
	1: PI,
	2: 0.0
}

@onready var players_container: Node3D = $Players
@onready var ui_layer: CanvasLayer = $UI
@onready var role_label: Label = $UI/HUD/RoleBadge/RoleLabel
@onready var esc_menu: PanelContainer = $UI/EscMenu
@onready var resume_button: Button = $UI/EscMenu/VBoxContainer/ResumeButton
@onready var leave_button: Button = $UI/EscMenu/VBoxContainer/LeaveButton

var peers_in_arena: Dictionary = {} # peer_id -> bool
var client_peer_id: int = 0
var has_spawned_all: bool = false
var is_terminating: bool = false
var is_sandbox_mode: bool = false
var _match_end_ui: MatchEndOverlayUI = null
var _spawner_cheatsheet_ui: Control = null
var _last_populate_summary: Dictionary = {}
var _esc_cheatsheet_button: Button = null
var _esc_rematch_button: Button = null
var _esc_switch_mode_button: Button = null


func _ready() -> void:
	is_sandbox_mode = GameConfig.sandbox_gym_mode if GameConfig != null else false
	_clear_playtest_room_furniture()
	_setup_interactive_doors()
	_configure_level_props_for_mode(is_sandbox_mode)

	if MatchManager != null:
		if not MatchManager.match_ended.is_connected(_on_match_ended):
			MatchManager.match_ended.connect(_on_match_ended)
		if not MatchManager.match_started.is_connected(_on_match_started):
			MatchManager.match_started.connect(_on_match_started)

	_ensure_match_end_ui()
	_ensure_spawner_cheatsheet_ui()
	_refresh_role_badge()

	# ESC Menu buttons & Mouse DPI/Sensitivity controls
	var esc_vbox: VBoxContainer = get_node_or_null("UI/EscMenu/VBoxContainer")
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


func _refresh_role_badge() -> void:
	if role_label == null:
		return
	var my_id: int = multiplayer.get_unique_id() if _is_network_active() else 1
	var mode_tag: String = "SANDBOX GYM" if is_sandbox_mode else "FULL MATCH"
	if my_id == 1:
		role_label.text = "ROLE: SPY GREEN (HOST) — %s" % mode_tag
		role_label.modulate = Color(0.45, 0.95, 0.55)
	else:
		role_label.text = "ROLE: SPY PURPLE (CONTENDER) — %s" % mode_tag
		role_label.modulate = Color(0.78, 0.55, 1.0)


func _refresh_esc_mode_button_text() -> void:
	if _esc_switch_mode_button != null:
		_esc_switch_mode_button.text = (
			"Switch to Full Match (New Seed)"
			if is_sandbox_mode
			else "Switch to Dev Sandbox Gym"
		)


func _clear_playtest_room_furniture() -> void:
	var room_2_2: Node = get_node_or_null("BuildingComplex2/Rooms/Room_2_2")
	if room_2_2 == null:
		return
	var spawn_pts: Node = room_2_2.get_node_or_null("FurnitureSpawnPoints")
	if spawn_pts != null:
		room_2_2.remove_child(spawn_pts)
		spawn_pts.queue_free()


func _ensure_shared_airport_exit() -> void:
	if get_node_or_null("SharedAirportExit") != null:
		return
	var exit_door := AIRPORT_EXIT_SCENE.instantiate() as StaticBody3D
	exit_door.name = "SharedAirportExit"
	add_child(exit_door)
	# Room_2_2 West Wall is at X = -9.0 (center Z = -4.5). Place flush against interior West wall facing East (+X).
	exit_door.position = Vector3(-8.82, 0.0, -4.5)
	exit_door.rotation.y = deg_to_rad(90.0)


func _configure_level_props_for_mode(sandbox: bool) -> void:
	_ensure_shared_airport_exit()
	if sandbox:
		_spawn_test_pickups()
		_spawn_test_props()
	else:
		var pickups_node: Node = get_node_or_null("TestPickups")
		if pickups_node != null:
			remove_child(pickups_node)
			pickups_node.queue_free()
		var props_node: Node = get_node_or_null("TestStep1Props")
		if props_node != null:
			remove_child(props_node)
			props_node.queue_free()


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
		var loot_right_items: Array[String] = ["KEY", "SPRING"]
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


func _resolve_spawn_point(slot: int) -> Vector3:
	if not is_inside_tree() or is_sandbox_mode:
		return SPAWN_POINTS.get(slot, Vector3.ZERO)
	return FULL_MATCH_SPAWN_POINTS.get(slot, SPAWN_POINTS.get(slot, Vector3.ZERO))


func _resolve_spawn_yaw(slot: int) -> float:
	if not is_inside_tree() or is_sandbox_mode:
		return 0.0
	return float(FULL_MATCH_SPAWN_YAWS.get(slot, 0.0))


func _on_match_started(seed_value: int) -> void:
	var spawner := MATCH_SPAWNER_SCRIPT.new()
	var active_cfg: Dictionary = MatchManager.active_spawner_config if (MatchManager != null and not MatchManager.active_spawner_config.is_empty()) else {}
	_last_populate_summary = spawner.populate_level(self, seed_value, DRAWER_SCENE, PICKUP_SCENE, ["Room_2_2"], active_cfg)
	if _spawner_cheatsheet_ui != null and is_instance_valid(_spawner_cheatsheet_ui):
		_spawner_cheatsheet_ui.call("set_latest_populate_summary", _last_populate_summary)


func _on_match_ended(winner_peer_id: int, reason: String) -> void:
	if role_label != null:
		role_label.text = reason
		role_label.modulate = Color(0.35, 1.0, 0.45)
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
		var active_seed: int = MatchManager.match_seed if MatchManager != null else 0
		_match_end_ui.show_match_result(winner_peer_id, my_id, reason, is_srv, is_sandbox_mode, active_seed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F2:
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
	esc_menu.visible = not esc_menu.visible
	if esc_menu.visible:
		_refresh_esc_mode_button_text()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume_pressed() -> void:
	esc_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_leave_button_pressed() -> void:
	_terminate_match("Local player selected Leave to Lobby")


func _on_rematch_requested() -> void:
	trigger_rematch(is_sandbox_mode)


func _on_switch_mode_rematch_pressed() -> void:
	trigger_rematch(not is_sandbox_mode)


func trigger_rematch(next_sandbox_mode: bool, custom_seed: int = 0) -> void:
	if _is_network_active() and not multiplayer.is_server():
		return
	if _is_network_active() and is_inside_tree():
		_rpc_prepare_arena_round.rpc(next_sandbox_mode)
	else:
		_rpc_prepare_arena_round(next_sandbox_mode)

	var c_id: int = client_peer_id if client_peer_id != 0 else 2
	if MatchManager != null and is_inside_tree():
		MatchManager.start_new_match([1, c_id], custom_seed)


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
	_refresh_role_badge()

	_clear_dynamic_round_entities()
	_reset_all_doors_for_round()
	_configure_level_props_for_mode(is_sandbox_mode)

	var p_root: Node = players_container if players_container != null else get_node_or_null("Players")
	if p_root != null:
		for child in p_root.get_children():
			var pid: int = child.name.to_int()
			var slot: int = 1 if pid == 1 else 2
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

@rpc("any_peer", "call_local", "reliable")
func notify_arena_ready() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	_on_peer_arena_loaded(sender_id)


func _on_peer_arena_loaded(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	peers_in_arena[peer_id] = true
	print("TestGym: Peer %d confirmed loaded in arena." % peer_id)

	if peer_id != 1:
		client_peer_id = peer_id
		peers_in_arena[2] = true

	# Once both Peer 1 (Host) and Peer 2 (Client) are loaded:
	if peers_in_arena.has(1) and peers_in_arena.has(2):
		_spawn_all_players()


func _spawn_all_players() -> void:
	if has_spawned_all:
		return
	has_spawned_all = true
	if is_inside_tree() and GameConfig != null:
		is_sandbox_mode = GameConfig.sandbox_gym_mode

	print("TestGym: Both peers confirmed arena loaded. Instantiating 1v1 Spies (mode=%s)..." % (
		"Sandbox" if is_sandbox_mode else "FullMatch"
	))

	# 1. Host (Peer 1 - Spy Green)
	var host_player: CharacterBody3D = PLAYER_SCENE.instantiate()
	host_player.name = "1"
	host_player.spy_role = 1
	host_player.position = _resolve_spawn_point(1)
	host_player.rotation.y = _resolve_spawn_yaw(1)
	players_container.add_child(host_player)

	# 2. Client (Peer 2 / Contender - Spy Purple)
	var c_id: int = client_peer_id if client_peer_id != 0 else 2
	var client_player: CharacterBody3D = PLAYER_SCENE.instantiate()
	client_player.name = str(c_id)
	client_player.spy_role = 2
	client_player.position = _resolve_spawn_point(2)
	client_player.rotation.y = _resolve_spawn_yaw(2)
	players_container.add_child(client_player)

	if is_inside_tree() and _is_network_active():
		_rpc_prepare_arena_round.rpc(is_sandbox_mode)
	elif is_inside_tree():
		_refresh_role_badge()

	if MatchManager != null and is_inside_tree():
		MatchManager.start_new_match([1, c_id])


func _is_network_active() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# ==========================================
# Teardown & Return to Lobby
# ==========================================

func _on_player_disconnected(peer_id: int) -> void:
	print("TestGym: Peer %d disconnected during active match." % peer_id)
	_terminate_match("Opponent disconnected.")


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
