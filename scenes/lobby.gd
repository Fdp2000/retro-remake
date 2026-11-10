extends Control

const TEST_GYM_SCENE_PATH: String = "res://scenes/test_gym.tscn"

# State Dictionary (1 = Host/Spy White, 2 = Client/Spy Black)
var lobby_state: Dictionary = {
	1: {"role": 1, "ready": false, "name": "Host"},
	2: {"role": 2, "ready": false, "name": "Waiting for opponent..."}
}

var _local_ready: bool = false
var client_peer_id: int = 0

# UI References
@onready var matchmaking_container: PanelContainer = $MarginContainer/MatchmakingContainer
@onready var staging_container: VBoxContainer = $MarginContainer/StagingContainer

# Matchmaking Controls
@onready var mode_option_button: OptionButton = $MarginContainer/MatchmakingContainer/MatchmakingPanel/ModeOptionButton
@onready var enet_controls: VBoxContainer = $MarginContainer/MatchmakingContainer/MatchmakingPanel/ENetControls
@onready var enet_address_input: LineEdit = $MarginContainer/MatchmakingContainer/MatchmakingPanel/ENetControls/ENetAddressInput
@onready var enet_host_button: Button = $MarginContainer/MatchmakingContainer/MatchmakingPanel/ENetControls/ENetHostButton
@onready var enet_join_button: Button = $MarginContainer/MatchmakingContainer/MatchmakingPanel/ENetControls/ENetJoinButton

@onready var eos_controls: VBoxContainer = $MarginContainer/MatchmakingContainer/MatchmakingPanel/EOSControls
@onready var local_puid_label: RichTextLabel = $MarginContainer/MatchmakingContainer/MatchmakingPanel/EOSControls/LocalPUIDLabel
@onready var quick_match_button: Button = $MarginContainer/MatchmakingContainer/MatchmakingPanel/EOSControls/QuickMatchButton
@onready var host_private_button: Button = $MarginContainer/MatchmakingContainer/MatchmakingPanel/EOSControls/HostPrivateButton
@onready var room_code_input: LineEdit = $MarginContainer/MatchmakingContainer/MatchmakingPanel/EOSControls/PrivateJoinContainer/RoomCodeInput
@onready var join_private_button: Button = $MarginContainer/MatchmakingContainer/MatchmakingPanel/EOSControls/PrivateJoinContainer/JoinPrivateButton
@onready var room_code_display: Label = $MarginContainer/MatchmakingContainer/MatchmakingPanel/EOSControls/RoomCodeDisplay
@onready var cancel_match_button: Button = $MarginContainer/MatchmakingContainer/MatchmakingPanel/EOSControls/CancelMatchButton
@onready var status_label: Label = $MarginContainer/MatchmakingContainer/MatchmakingPanel/StatusLabel

# Staging Controls
@onready var header_label: Label = $MarginContainer/StagingContainer/HeaderLabel
@onready var p1_name_label: Label = $MarginContainer/StagingContainer/CardsContainer/Player1Card/VBoxContainer/P1NameLabel
@onready var p1_status_label: Label = $MarginContainer/StagingContainer/CardsContainer/Player1Card/VBoxContainer/P1StatusLabel
@onready var p2_name_label: Label = $MarginContainer/StagingContainer/CardsContainer/Player2Card/VBoxContainer/P2NameLabel
@onready var p2_status_label: Label = $MarginContainer/StagingContainer/CardsContainer/Player2Card/VBoxContainer/P2StatusLabel

@onready var ready_button: Button = $MarginContainer/StagingContainer/ActionsContainer/ReadyButton
@onready var start_button: Button = $MarginContainer/StagingContainer/ActionsContainer/StartButton
@onready var disconnect_button: Button = $MarginContainer/StagingContainer/ActionsContainer/DisconnectButton


func _ready() -> void:
	# Ensure mouse is visible in lobby
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Setup Mode OptionButton
	mode_option_button.clear()
	mode_option_button.add_item("Local (ENet)", NetworkManager.NetworkMode.ENET_LOCAL)
	mode_option_button.add_item("Online (EOS P2P)", NetworkManager.NetworkMode.EOS_P2P)

	var default_idx: int = mode_option_button.get_item_index(NetworkManager.current_mode)
	if default_idx != -1:
		mode_option_button.select(default_idx)
	mode_option_button.item_selected.connect(_on_mode_selected)
	_update_mode_ui(NetworkManager.current_mode)

	# ENet button bindings
	enet_host_button.pressed.connect(_on_enet_host_pressed)
	enet_join_button.pressed.connect(_on_enet_join_pressed)

	# EOS button bindings
	quick_match_button.pressed.connect(_on_quick_match_pressed)
	host_private_button.pressed.connect(_on_host_private_pressed)
	join_private_button.pressed.connect(_on_join_private_pressed)
	cancel_match_button.pressed.connect(_on_cancel_match_pressed)

	# Sanitization for 4-letter room code
	room_code_input.text_changed.connect(func(new_text: String):
		var upper_text: String = new_text.to_upper()
		if room_code_input.text != upper_text:
			room_code_input.text = upper_text
			room_code_input.caret_column = upper_text.length()
	)

	# Staging Actions
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)

	# NetworkManager signal bindings
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	# SessionManager signal bindings
	SessionManager.matchmaking_status_changed.connect(_on_matchmaking_status_changed)
	SessionManager.matchmaking_failed.connect(_on_matchmaking_failed)
	SessionManager.room_code_created.connect(_on_room_code_created)
	SessionManager.session_closed.connect(_on_session_closed)

	# EOSManager bindings
	EOSManager.login_success.connect(_on_eos_login_success)
	EOSManager.login_failed.connect(_on_eos_login_failed)
	if not EOSManager.local_puid.is_empty():
		_on_eos_login_success(EOSManager.local_puid)

	# Check if already connected on startup (e.g., via CLI args)
	if NetworkManager.is_online():
		_enter_staging()
	else:
		_show_matchmaking()


# ==========================================
# UI Mode / View Visibility
# ==========================================

func _show_matchmaking() -> void:
	matchmaking_container.visible = true
	staging_container.visible = false
	_local_ready = false
	ready_button.text = "READY UP"


func _enter_staging() -> void:
	matchmaking_container.visible = false
	staging_container.visible = true
	_local_ready = false
	ready_button.text = "READY UP"

	if multiplayer.is_server():
		lobby_state = {
			1: {"role": 1, "ready": false, "name": _get_host_name()},
			2: {"role": 2, "ready": false, "name": "Waiting for opponent..."}
		}
		client_peer_id = 0
		start_button.visible = true
		start_button.disabled = true
	else:
		start_button.visible = false
		var my_name: String = _get_client_name()
		register_client_identity.rpc_id(1, my_name)

	_update_header()
	_update_staging_ui()


func _update_mode_ui(mode: NetworkManager.NetworkMode) -> void:
	if mode == NetworkManager.NetworkMode.EOS_P2P:
		eos_controls.visible = true
		enet_controls.visible = false
	else:
		eos_controls.visible = false
		enet_controls.visible = true


func _on_mode_selected(index: int) -> void:
	var mode: int = mode_option_button.get_item_id(index)
	NetworkManager.current_mode = mode as NetworkManager.NetworkMode
	_update_mode_ui(NetworkManager.current_mode)


func _update_header() -> void:
	var mode_name: String = "LOCAL ENET" if NetworkManager.current_mode == NetworkManager.NetworkMode.ENET_LOCAL else "EOS P2P"
	var details: String = ""

	if NetworkManager.current_mode == NetworkManager.NetworkMode.ENET_LOCAL:
		details = "Port: %d" % NetworkManager.PORT
	else:
		if not SessionManager.current_room_code.is_empty() and SessionManager.current_room_code != "NONE":
			details = "Room Code: %s" % SessionManager.current_room_code
		else:
			details = "Quick Match"
		if multiplayer.is_server() and not EOSManager.local_puid.is_empty():
			details += " | Host: %s" % EOSManager.local_puid

	header_label.text = "[ %s ]  —  %s" % [mode_name, details]


func _update_staging_ui() -> void:
	# Update Player 1 (Spy White - Host)
	var p1_data: Dictionary = lobby_state.get(1, {"name": "Host", "ready": false})
	p1_name_label.text = str(p1_data.get("name", "Host"))
	var p1_ready: bool = bool(p1_data.get("ready", false))
	p1_status_label.text = "READY" if p1_ready else "NOT READY"
	p1_status_label.modulate = Color(0.2, 0.85, 0.3) if p1_ready else Color(0.65, 0.65, 0.65)

	# Update Player 2 (Spy Black - Contender)
	var p2_data: Dictionary = lobby_state.get(2, {"name": "Waiting for opponent...", "ready": false})
	p2_name_label.text = str(p2_data.get("name", "Waiting for opponent..."))
	var p2_ready: bool = bool(p2_data.get("ready", false))
	p2_status_label.text = "READY" if p2_ready else "NOT READY"
	p2_status_label.modulate = Color(0.2, 0.85, 0.3) if p2_ready else Color(0.65, 0.65, 0.65)

	# Update Start Button (Host only)
	if multiplayer.is_server():
		start_button.visible = true
		start_button.disabled = not (p1_ready and p2_ready)
		if p1_ready and p2_ready and ("--auto-ready" in OS.get_cmdline_args() + OS.get_cmdline_user_args()):
			get_tree().create_timer(0.3).timeout.connect(func():
				if is_inside_tree() and multiplayer.is_server() and start_button.visible and not start_button.disabled:
					_on_start_pressed()
			)
	else:
		start_button.visible = false


func _get_host_name() -> String:
	if NetworkManager.current_mode == NetworkManager.NetworkMode.EOS_P2P and not EOSManager.local_puid.is_empty():
		return "Host (%s...)" % EOSManager.local_puid.substr(0, 8)
	return "Host (Peer 1)"


func _get_client_name() -> String:
	if NetworkManager.current_mode == NetworkManager.NetworkMode.EOS_P2P and not EOSManager.local_puid.is_empty():
		return "Contender (%s...)" % EOSManager.local_puid.substr(0, 8)
	return "Contender (Peer %d)" % multiplayer.get_unique_id()


# ==========================================
# Matchmaking Actions (ENet & EOS)
# ==========================================

func _on_enet_host_pressed() -> void:
	NetworkManager.current_mode = NetworkManager.NetworkMode.ENET_LOCAL
	var err: Error = NetworkManager.start_host()
	if err == OK:
		status_label.text = "ENet server started."
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
	NetworkManager.disconnect_session()
	status_label.text = "Matchmaking cancelled."


# ==========================================
# EOS Callbacks
# ==========================================

func _on_eos_login_success(puid: String) -> void:
	local_puid_label.text = "[center]Local PUID: [b]%s[/b][/center]" % puid
	status_label.text = "EOS Connected"


func _on_eos_login_failed(err: String) -> void:
	status_label.text = "EOS Login Failed: %s" % err


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


# ==========================================
# Network Lifecycle & RPCs
# ==========================================

func _on_server_started() -> void:
	_enter_staging()


func _on_connected_to_server() -> void:
	_enter_staging()
	if "--auto-ready" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		get_tree().create_timer(0.4).timeout.connect(func():
			if not _local_ready:
				_on_ready_pressed()
		)


func _on_connection_failed() -> void:
	_show_matchmaking()
	cancel_match_button.visible = false
	room_code_display.visible = false
	status_label.text = "Connection failed."


func _on_server_disconnected() -> void:
	print("Lobby: Server disconnected.")
	_leave_lobby("Host disconnected.")


func _on_player_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == 1:
		return

	print("Lobby: Contender connected with peer ID %d" % peer_id)
	client_peer_id = peer_id
	lobby_state[2] = {
		"role": 2,
		"ready": false,
		"name": "Contender (Peer %d)" % peer_id
	}
	sync_lobby_state.rpc(lobby_state)
	_update_staging_ui()

	if "--auto-ready" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		get_tree().create_timer(0.4).timeout.connect(func():
			if not _local_ready:
				_on_ready_pressed()
		)


func _on_player_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	print("Lobby: Peer %d disconnected in staging." % peer_id)
	if peer_id == client_peer_id or peer_id != 1:
		client_peer_id = 0
		lobby_state[2] = {
			"role": 2,
			"ready": false,
			"name": "Waiting for opponent..."
		}
		# Reset host readiness to avoid accidental start
		_local_ready = false
		ready_button.text = "READY UP"
		lobby_state[1]["ready"] = false
		sync_lobby_state.rpc(lobby_state)
		_update_staging_ui()


@rpc("any_peer", "call_local", "reliable")
func register_client_identity(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0 or sender_id == 1:
		return

	client_peer_id = sender_id
	lobby_state[2]["name"] = display_name
	sync_lobby_state.rpc(lobby_state)
	_update_staging_ui()


# ==========================================
# Readiness Flow & Launch
# ==========================================

func _on_ready_pressed() -> void:
	_local_ready = not _local_ready
	ready_button.text = "UNREADY" if _local_ready else "READY UP"
	server_set_ready.rpc_id(1, _local_ready)


@rpc("any_peer", "call_local", "reliable")
func server_set_ready(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if sender_id == 1:
		lobby_state[1]["ready"] = is_ready
	else:
		lobby_state[2]["ready"] = is_ready

	sync_lobby_state.rpc(lobby_state)
	_update_staging_ui()


@rpc("authority", "call_local", "reliable")
func sync_lobby_state(new_state: Dictionary) -> void:
	lobby_state = new_state
	_update_staging_ui()


func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	var p1_ready: bool = bool(lobby_state.get(1, {}).get("ready", false))
	var p2_ready: bool = bool(lobby_state.get(2, {}).get("ready", false))
	if not (p1_ready and p2_ready):
		return

	print("Lobby: Both players ready. Launching match into arena...")
	rpc_load_arena.rpc(TEST_GYM_SCENE_PATH)


@rpc("authority", "call_local", "reliable")
func rpc_load_arena(scene_path: String) -> void:
	print("Lobby: Transitioning to arena: %s" % scene_path)
	get_tree().change_scene_to_file(scene_path)


func _on_disconnect_pressed() -> void:
	_leave_lobby("Left lobby.")


func _leave_lobby(reason: String = "") -> void:
	NetworkManager.disconnect_session()
	_show_matchmaking()
	if not reason.is_empty():
		status_label.text = reason
