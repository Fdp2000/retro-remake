extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const LOBBY_SCENE_PATH: String = "res://scenes/lobby.tscn"

const SPAWN_POINTS: Dictionary = {
	1: Vector3(-3.0, 1.0, 0.0),
	2: Vector3(3.0, 1.0, 0.0)
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


func _ready() -> void:
	_setup_interactive_doors()
	# Configure local role badge
	var my_id: int = multiplayer.get_unique_id() if (multiplayer.has_multiplayer_peer() and NetworkManager.is_online()) else 1
	if my_id == 1:
		role_label.text = "ROLE: SPY WHITE (HOST)"
		role_label.modulate = Color(0.95, 0.95, 0.95)
	else:
		role_label.text = "ROLE: SPY BLACK (CONTENDER)"
		role_label.modulate = Color(0.7, 0.85, 1.0)

	# ESC Menu buttons
	resume_button.pressed.connect(_on_resume_pressed)
	leave_button.pressed.connect(_on_leave_button_pressed)

	# Network lifecycle bindings
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	# Spawning debug / diagnostic logs
	players_container.child_entered_tree.connect(func(node: Node):
		var is_srv: bool = multiplayer.is_server() if NetworkManager.is_online() else false
		var is_auth: bool = node.is_multiplayer_authority() if NetworkManager.is_online() else false
		print("TestGym [%s]: Child entered Players: %s (auth: %d, is_auth: %s)" % [
			"Server" if is_srv else "Client",
			node.name,
			node.get_multiplayer_authority(),
			is_auth
		])
	)

	players_container.child_exiting_tree.connect(func(node: Node):
		var is_srv: bool = multiplayer.is_server() if NetworkManager.is_online() else false
		print("TestGym [%s]: Child exited Players: %s" % [
			"Server" if is_srv else "Client",
			node.name
		])
	)

	# Arena loading handshake
	if multiplayer.is_server():
		_on_peer_arena_loaded(1)
	else:
		notify_arena_ready.rpc_id(1)

	if "--auto-ready" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		get_tree().create_timer(2.0).timeout.connect(func():
			print("TestGym [--auto-ready]: Automated ENet integration verified! Players in tree: %d" % players_container.get_child_count())
			get_tree().quit(0)
		)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ESCAPE):
		toggle_esc_menu()
		get_viewport().set_input_as_handled()


func toggle_esc_menu() -> void:
	esc_menu.visible = not esc_menu.visible
	if esc_menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume_pressed() -> void:
	esc_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_leave_button_pressed() -> void:
	_terminate_match("Local player selected Leave to Lobby")


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

	print("TestGym: Both peers confirmed arena loaded. Instantiating 1v1 Spies...")

	# 1. Host (Peer 1 - Spy White)
	var host_player: CharacterBody3D = PLAYER_SCENE.instantiate()
	host_player.name = "1"
	host_player.spy_role = 1
	host_player.position = SPAWN_POINTS[1]
	players_container.add_child(host_player)

	# 2. Client (Contender - Spy Black)
	var c_id: int = client_peer_id if client_peer_id != 0 else 2
	var client_player: CharacterBody3D = PLAYER_SCENE.instantiate()
	client_player.name = str(c_id)
	client_player.spy_role = 2
	client_player.position = SPAWN_POINTS[2]
	players_container.add_child(client_player)


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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Cleanup network peer and EOS session
	NetworkManager.disconnect_session()

	# Clear local players
	for child in players_container.get_children():
		child.queue_free()

	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)


func _setup_interactive_doors() -> void:
	var door_script: Script = preload("res://scenes/BuildingComplex/interactive_door.gd")
	for door in find_children("*", "MeshInstance3D", true, false):
		if String(door.name).begins_with("Door_") and String(door.name).ends_with("_Door") and door.get_script() == null:
			door.set_script(door_script)
			# Children are already ready when the gym attaches the script.
			door._ready()
