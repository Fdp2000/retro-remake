extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")

const SPAWN_POINTS: Dictionary = {
	1: Vector3(-3.0, 1.0, 0.0),
	2: Vector3(3.0, 1.0, 0.0)
}

@onready var players_container: Node3D = $Players
@onready var ui_layer: CanvasLayer = $UI
@onready var mode_option_button: OptionButton = $UI/Panel/MatchmakingPanel/ModeOptionButton

# ENet Controls
@onready var enet_controls: VBoxContainer = $UI/Panel/MatchmakingPanel/ENetControls
@onready var enet_address_input: LineEdit = $UI/Panel/MatchmakingPanel/ENetControls/ENetAddressInput
@onready var enet_host_button: Button = $UI/Panel/MatchmakingPanel/ENetControls/ENetHostButton
@onready var enet_join_button: Button = $UI/Panel/MatchmakingPanel/ENetControls/ENetJoinButton

# EOS Controls
@onready var eos_controls: VBoxContainer = $UI/Panel/MatchmakingPanel/EOSControls
@onready var local_puid_label: RichTextLabel = $UI/Panel/MatchmakingPanel/EOSControls/LocalPUIDLabel
@onready var quick_match_button: Button = $UI/Panel/MatchmakingPanel/EOSControls/QuickMatchButton
@onready var host_private_button: Button = $UI/Panel/MatchmakingPanel/EOSControls/HostPrivateButton
@onready var room_code_input: LineEdit = $UI/Panel/MatchmakingPanel/EOSControls/PrivateJoinContainer/RoomCodeInput
@onready var join_private_button: Button = $UI/Panel/MatchmakingPanel/EOSControls/PrivateJoinContainer/JoinPrivateButton
@onready var room_code_display: Label = $UI/Panel/MatchmakingPanel/EOSControls/RoomCodeDisplay
@onready var cancel_match_button: Button = $UI/Panel/MatchmakingPanel/EOSControls/CancelMatchButton

# Status
@onready var status_label: Label = $UI/Panel/MatchmakingPanel/StatusLabel


func _is_peer_active() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _ready() -> void:
	# Network mode setup (EOS P2P vs Local ENet)
	mode_option_button.clear()
	mode_option_button.add_item("Online (EOS P2P)", NetworkManager.NetworkMode.EOS_P2P)
	mode_option_button.add_item("Local (ENet)", NetworkManager.NetworkMode.ENET_LOCAL)

	var default_idx: int = mode_option_button.get_item_index(NetworkManager.current_mode)
	if default_idx != -1:
		mode_option_button.select(default_idx)
	mode_option_button.item_selected.connect(_on_mode_selected)
	_update_mode_ui(NetworkManager.current_mode)

	# EOS Manager bindings
	EOSManager.login_success.connect(_on_eos_login_success)
	EOSManager.login_failed.connect(func(err: String):
		status_label.text = "EOS Login Failed: %s" % err
	)
	if not EOSManager.local_puid.is_empty():
		_on_eos_login_success(EOSManager.local_puid)

	# Session Manager bindings
	SessionManager.matchmaking_status_changed.connect(_on_matchmaking_status_changed)
	SessionManager.matchmaking_failed.connect(_on_matchmaking_failed)
	SessionManager.room_code_created.connect(_on_room_code_created)
	SessionManager.session_closed.connect(_on_session_closed)

	# Network Manager bindings
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_started.connect(_on_network_active)
	NetworkManager.connected_to_server.connect(_on_network_active)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	# ENet button bindings
	enet_host_button.pressed.connect(_on_enet_host_pressed)
	enet_join_button.pressed.connect(_on_enet_join_pressed)

	# EOS button bindings
	quick_match_button.pressed.connect(_on_quick_match_pressed)
	host_private_button.pressed.connect(_on_host_private_pressed)
	join_private_button.pressed.connect(_on_join_private_pressed)
	cancel_match_button.pressed.connect(_on_cancel_match_pressed)

	room_code_input.text_changed.connect(func(new_text: String):
		var upper_text: String = new_text.to_upper()
		if room_code_input.text != upper_text:
			room_code_input.text = upper_text
			room_code_input.caret_column = upper_text.length()
	)

	players_container.child_entered_tree.connect(func(node: Node):
		var is_srv: bool = multiplayer.is_server() if _is_peer_active() else false
		var is_auth: bool = node.is_multiplayer_authority() if _is_peer_active() else false
		print("TestGym [%s]: Child entered Players: %s (auth: %d, is_auth: %s)" % [
			"Server" if is_srv else "Client",
			node.name,
			node.get_multiplayer_authority(),
			is_auth
		])
	)

	players_container.child_exiting_tree.connect(func(node: Node):
		var is_srv: bool = multiplayer.is_server() if _is_peer_active() else false
		print("TestGym [%s]: Child exited Players: %s" % [
			"Server" if is_srv else "Client",
			node.name
		])
	)

	if NetworkManager.is_online():
		_on_network_active()
		if NetworkManager.is_host():
			if not players_container.has_node(str(multiplayer.get_unique_id())):
				_spawn_player(multiplayer.get_unique_id())


func _on_mode_selected(index: int) -> void:
	var mode: int = mode_option_button.get_item_id(index)
	NetworkManager.current_mode = mode as NetworkManager.NetworkMode
	_update_mode_ui(NetworkManager.current_mode)


func _update_mode_ui(mode: NetworkManager.NetworkMode) -> void:
	if mode == NetworkManager.NetworkMode.EOS_P2P:
		eos_controls.visible = true
		enet_controls.visible = false
	else:
		eos_controls.visible = false
		enet_controls.visible = true


func _on_eos_login_success(puid: String) -> void:
	local_puid_label.text = "[center]Local PUID: [b]%s[/b][/center]" % puid
	status_label.text = "EOS Connected"


# ENet Actions
func _on_enet_host_pressed() -> void:
	NetworkManager.current_mode = NetworkManager.NetworkMode.ENET_LOCAL
	var err: Error = NetworkManager.start_host()
	if err == OK:
		_on_network_active()
	else:
		status_label.text = "Failed to start ENet host: %s" % error_string(err)


func _on_enet_join_pressed() -> void:
	NetworkManager.current_mode = NetworkManager.NetworkMode.ENET_LOCAL
	var target_addr: String = enet_address_input.text.strip_edges()
	if target_addr.is_empty():
		target_addr = "127.0.0.1"
	var err: Error = NetworkManager.start_join(target_addr)
	if err == OK:
		status_label.text = "Connecting via ENet to %s:%d..." % [target_addr, NetworkManager.PORT]
	else:
		status_label.text = "Failed to connect: %s" % error_string(err)


# EOS Actions
func _on_quick_match_pressed() -> void:
	cancel_match_button.visible = true
	room_code_display.visible = false
	SessionManager.start_quick_match()


func _on_host_private_pressed() -> void:
	var code: String = SessionManager.generate_room_code()
	DisplayServer.clipboard_set(code)
	room_code_display.text = "Your Room Code: %s (Copied)" % code
	room_code_display.visible = true
	cancel_match_button.visible = true
	SessionManager.create_and_host_session(SessionManager.MatchType.PRIVATE, code)


func _on_join_private_pressed() -> void:
	var code: String = room_code_input.text.strip_edges().to_upper()
	if code.length() != 4:
		status_label.text = "Room code must be exactly 4 characters."
		return
	cancel_match_button.visible = true
	room_code_display.visible = false
	SessionManager.join_private_room(code)


func _on_cancel_match_pressed() -> void:
	cancel_match_button.visible = false
	room_code_display.visible = false
	SessionManager.destroy_active_session()
	NetworkManager._cleanup_peer(false)
	status_label.text = "Matchmaking cancelled / Session left."


# Session Signals
func _on_matchmaking_status_changed(message: String) -> void:
	status_label.text = message


func _on_matchmaking_failed(reason: String) -> void:
	status_label.text = "Error: %s" % reason
	cancel_match_button.visible = false
	room_code_display.visible = false


func _on_room_code_created(code: String) -> void:
	DisplayServer.clipboard_set(code)
	room_code_display.text = "Your Room Code: %s (Copied)" % code
	room_code_display.visible = true


func _on_session_closed() -> void:
	cancel_match_button.visible = false
	room_code_display.visible = false


# Network Status Signals
func _on_network_active() -> void:
	ui_layer.visible = false


func _on_connection_failed() -> void:
	ui_layer.visible = true
	cancel_match_button.visible = false
	room_code_display.visible = false
	status_label.text = "Connection failed."
	for child in players_container.get_children():
		child.queue_free()


func _on_server_disconnected() -> void:
	print("TestGym: Server disconnected.")
	ui_layer.visible = true
	cancel_match_button.visible = false
	room_code_display.visible = false
	status_label.text = "Server disconnected."
	for child in players_container.get_children():
		child.queue_free()


func _on_player_connected(peer_id: int) -> void:
	# Only the server instantiates players in the multiplayer tree
	if not NetworkManager.is_host():
		return
	_spawn_player(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	# Only Peer 1 (Host/Server) handles despawning in the multiplayer tree
	if multiplayer.get_unique_id() != 1:
		return
	var player_node: Node = players_container.get_node_or_null(str(peer_id))
	if player_node:
		print("TestGym: Despawning player for peer %d" % peer_id)
		player_node.queue_free()


func _spawn_player(peer_id: int) -> void:
	if players_container.has_node(str(peer_id)):
		print("TestGym: Player %d already exists, skipping spawn." % peer_id)
		return

	print("TestGym: Spawning player for peer %d" % peer_id)
	var player_instance: CharacterBody3D = PLAYER_SCENE.instantiate()
	player_instance.name = str(peer_id)

	# Place Peer 1 at (-3, 1, 0) and Peer 2 (client) at (3, 1, 0)
	var spawn_pos: Vector3 = Vector3(-3.0, 1.0, 0.0) if peer_id == 1 else Vector3(3.0, 1.0, 0.0)
	player_instance.position = spawn_pos

	players_container.add_child(player_instance)
