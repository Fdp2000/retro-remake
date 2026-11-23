extends Control

const TEST_GYM_SCENE_PATH: String = "res://scenes/test_gym.tscn"
const SPAWNER_CHEATSHEET_UI_SCRIPT = preload("res://ui/spawner_cheatsheet_ui.gd")

# State Dictionary: slot (1..4) -> {"slot": int, "role": int, "peer_id": int, "ready": bool, "name": String}
var lobby_state: Dictionary = {}

var _local_ready: bool = false
var _auto_launch_scheduled: bool = false
var _is_launching: bool = false
var is_in_matchmaking_queue: bool = false
var matchmaking_search_elapsed: float = 0.0
var _spawner_cheatsheet_ui: Control = null
var _slot_cards: Dictionary = {} # slot (1..4) -> {"card": PanelContainer, "title": Label, "swatch": ColorRect, "name": Label, "status": Label}

# UI References
@onready var matchmaking_container: PanelContainer = $MarginContainer/MatchmakingContainer
@onready var searching_container: PanelContainer = $MarginContainer/SearchingContainer
@onready var staging_container: VBoxContainer = $MarginContainer/StagingContainer

# Searching Controls
@onready var search_timer_label: Label = $MarginContainer/SearchingContainer/SearchingPanel/SearchTimerLabel
@onready var search_status_label: Label = $MarginContainer/SearchingContainer/SearchingPanel/SearchStatusLabel
@onready var cancel_search_button: Button = $MarginContainer/SearchingContainer/SearchingPanel/CancelSearchButton

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
@onready var cards_container: HBoxContainer = $MarginContainer/StagingContainer/CardsContainer

@onready var ready_button: Button = $MarginContainer/StagingContainer/ActionsContainer/ReadyButton
@onready var start_button: Button = $MarginContainer/StagingContainer/ActionsContainer/StartButton
@onready var disconnect_button: Button = $MarginContainer/StagingContainer/ActionsContainer/DisconnectButton


func _ready() -> void:
	# Ensure mouse is visible in lobby
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Bind and style all 4 FFA spy staging cards (Green, Purple, Blue, Red)
	_init_slot_cards()

	# Attach per-user Mouse DPI & Sensitivity settings widget + Solo Full Match / Sandbox Gym buttons
	var matchmaking_panel: VBoxContainer = get_node_or_null("MarginContainer/MatchmakingContainer/MatchmakingPanel")
	if matchmaking_panel != null and matchmaking_panel.get_node_or_null("MouseSettingsWidget") == null:
		var solo_match_btn := Button.new()
		solo_match_btn.name = "SoloFullMatchButton"
		solo_match_btn.text = "Solo Full Match (1P Seeded Embassy Round)"
		solo_match_btn.pressed.connect(func():
			if GameConfig != null:
				GameConfig.sandbox_gym_mode = false
			NetworkManager.current_mode = NetworkManager.NetworkMode.ENET_LOCAL
			if NetworkManager.start_host() == OK:
				get_tree().change_scene_to_file(TEST_GYM_SCENE_PATH)
		)
		matchmaking_panel.add_child(solo_match_btn)

		var solo_btn := Button.new()
		solo_btn.name = "SoloTestGymButton"
		solo_btn.text = "Solo Test Gym (1P Sandbox Bench — All Items)"
		solo_btn.pressed.connect(func():
			if GameConfig != null:
				GameConfig.sandbox_gym_mode = true
			NetworkManager.current_mode = NetworkManager.NetworkMode.ENET_LOCAL
			if NetworkManager.start_host() == OK:
				get_tree().change_scene_to_file(TEST_GYM_SCENE_PATH)
		)
		matchmaking_panel.add_child(solo_btn)

		var cheatsheet_btn := Button.new()
		cheatsheet_btn.name = "SpawnerCheatsheetButton"
		cheatsheet_btn.text = "Spawner Cheatsheet & Tuner [F2]"
		cheatsheet_btn.pressed.connect(open_spawner_cheatsheet)
		matchmaking_panel.add_child(cheatsheet_btn)

		var sep := HSeparator.new()
		matchmaking_panel.add_child(sep)
		var mouse_widget: VBoxContainer = preload("res://ui/mouse_settings_widget.gd").new()
		mouse_widget.name = "MouseSettingsWidget"
		matchmaking_panel.add_child(mouse_widget)

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
	quick_match_button.pressed.connect(_on_find_match_pressed)
	cancel_search_button.pressed.connect(_on_cancel_search_pressed)
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


func _process(delta: float) -> void:
	if is_in_matchmaking_queue:
		matchmaking_search_elapsed += delta
		var minutes: int = floori(matchmaking_search_elapsed / 60.0)
		var seconds: int = int(matchmaking_search_elapsed) % 60
		search_timer_label.text = "%02d:%02d" % [minutes, seconds]

		var dot_count: int = (int(matchmaking_search_elapsed * 2.0) % 3) + 1
		search_status_label.text = "Finding match" + ".".repeat(dot_count)


# ==========================================
# UI Mode / View Visibility
# ==========================================

func _init_slot_cards() -> void:
	_slot_cards.clear()
	for slot in range(1, NetworkManager.MAX_PLAYERS + 1):
		var card := cards_container.get_node_or_null("Player%dCard" % slot) as PanelContainer
		if card == null:
			continue
		var vbox := card.get_node_or_null("VBoxContainer")
		if vbox == null:
			continue
		var title_lbl := vbox.get_node_or_null("P%dTitle" % slot) as Label
		var swatch_rect := vbox.get_node_or_null("CenterContainer/P%dSwatch" % slot) as ColorRect
		var name_lbl := vbox.get_node_or_null("P%dNameLabel" % slot) as Label
		var status_lbl := vbox.get_node_or_null("P%dStatusLabel" % slot) as Label
		var role_name: String = GameConfig.get_spy_role_name(slot) if GameConfig != null else ("SPY %d" % slot)
		if title_lbl != null:
			title_lbl.text = ("%s (HOST)" % role_name) if slot == 1 else role_name
		if swatch_rect != null and GameConfig != null:
			swatch_rect.color = GameConfig.get_spy_role_color(slot)
		_slot_cards[slot] = {
			"card": card,
			"title": title_lbl,
			"swatch": swatch_rect,
			"name": name_lbl,
			"status": status_lbl
		}


func _build_default_lobby_state(host_name: String = "Host") -> Dictionary:
	var state: Dictionary = {}
	for slot in range(1, NetworkManager.MAX_PLAYERS + 1):
		state[slot] = {
			"slot": slot,
			"role": slot,
			"peer_id": 1 if slot == 1 else 0,
			"ready": false,
			"name": host_name if slot == 1 else "Open Slot"
		}
	return state


func _ensure_host_lobby_state() -> void:
	if lobby_state.is_empty() or not lobby_state.has(1) or int((lobby_state[1] as Dictionary).get("peer_id", 0)) != 1:
		lobby_state = _build_default_lobby_state(_get_host_name())


func _find_slot_by_peer_id(peer_id: int) -> int:
	for slot in range(1, NetworkManager.MAX_PLAYERS + 1):
		var slot_data: Dictionary = lobby_state.get(slot, {})
		if int(slot_data.get("peer_id", 0)) == peer_id:
			return slot
	return 0


func _find_first_open_slot() -> int:
	for slot in range(2, NetworkManager.MAX_PLAYERS + 1):
		var slot_data: Dictionary = lobby_state.get(slot, {})
		if int(slot_data.get("peer_id", 0)) == 0:
			return slot
	return 0


func _get_occupied_slot_count() -> int:
	var count: int = 0
	for slot in range(1, NetworkManager.MAX_PLAYERS + 1):
		var slot_data: Dictionary = lobby_state.get(slot, {})
		if int(slot_data.get("peer_id", 0)) != 0:
			count += 1
	return count


func _are_all_occupied_ready() -> bool:
	var occupied: int = 0
	for slot in range(1, NetworkManager.MAX_PLAYERS + 1):
		var slot_data: Dictionary = lobby_state.get(slot, {})
		if int(slot_data.get("peer_id", 0)) == 0:
			continue
		occupied += 1
		if not bool(slot_data.get("ready", false)):
			return false
	return occupied > 0


func _get_auto_target_players() -> int:
	var target: int = NetworkManager.MIN_PLAYERS
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var s: String = str(arg)
		if s.begins_with("--auto-players="):
			target = clampi(s.trim_prefix("--auto-players=").to_int(), NetworkManager.MIN_PLAYERS, NetworkManager.MAX_PLAYERS)
	return target


func _show_matchmaking() -> void:
	is_in_matchmaking_queue = false
	_auto_launch_scheduled = false
	_is_launching = false
	lobby_state.clear()
	matchmaking_container.visible = true
	searching_container.visible = false
	staging_container.visible = false
	_local_ready = false
	ready_button.text = "READY UP"


func _show_searching_view() -> void:
	matchmaking_container.visible = false
	searching_container.visible = true
	staging_container.visible = false


func _enter_staging() -> void:
	is_in_matchmaking_queue = false
	_auto_launch_scheduled = false
	_is_launching = false
	matchmaking_container.visible = false
	searching_container.visible = false
	staging_container.visible = true
	_local_ready = false
	ready_button.text = "READY UP"

	if multiplayer.is_server():
		_ensure_host_lobby_state()
		lobby_state[1]["name"] = _get_host_name()
		lobby_state[1]["ready"] = false
		start_button.visible = true
		start_button.disabled = true
	else:
		if lobby_state.is_empty():
			lobby_state = _build_default_lobby_state("Host")
		start_button.visible = false
		var my_name: String = _get_client_name()
		register_client_identity.rpc_id(1, my_name)

	_update_header()
	_update_staging_ui()

	if multiplayer.is_server() and ("--auto-ready" in OS.get_cmdline_args() + OS.get_cmdline_user_args()):
		get_tree().create_timer(0.25).timeout.connect(func():
			if is_inside_tree() and staging_container.visible and not _local_ready:
				_on_ready_pressed()
		)


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
	if _slot_cards.is_empty():
		_init_slot_cards()

	for slot in range(1, NetworkManager.MAX_PLAYERS + 1):
		var card_ui: Dictionary = _slot_cards.get(slot, {})
		if card_ui.is_empty():
			continue
		var slot_data: Dictionary = lobby_state.get(slot, {
			"slot": slot,
			"role": slot,
			"peer_id": 0,
			"ready": false,
			"name": "Open Slot"
		})
		var slot_peer_id: int = int(slot_data.get("peer_id", 0))
		var is_occupied: bool = slot_peer_id != 0
		var is_ready: bool = bool(slot_data.get("ready", false))
		var card_panel := card_ui.get("card") as PanelContainer
		var name_lbl := card_ui.get("name") as Label
		var status_lbl := card_ui.get("status") as Label

		if is_occupied:
			if name_lbl != null:
				name_lbl.text = str(slot_data.get("name", "Player"))
			if status_lbl != null:
				status_lbl.text = "READY" if is_ready else "NOT READY"
				status_lbl.modulate = Color(0.2, 0.85, 0.3) if is_ready else Color(0.65, 0.65, 0.65)
			if card_panel != null:
				card_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			if name_lbl != null:
				name_lbl.text = "Open Slot"
			if status_lbl != null:
				status_lbl.text = "EMPTY"
				status_lbl.modulate = Color(0.45, 0.45, 0.45)
			if card_panel != null:
				card_panel.modulate = Color(0.75, 0.75, 0.75, 0.85)

	var occupied_count: int = _get_occupied_slot_count()
	var all_ready: bool = _are_all_occupied_ready()

	# Update Start Button (Host only)
	if multiplayer.is_server():
		start_button.visible = true
		start_button.text = "LAUNCH MATCH (%d/%d)" % [occupied_count, NetworkManager.MAX_PLAYERS]
		start_button.disabled = not (occupied_count >= NetworkManager.MIN_PLAYERS and all_ready)
		if (
			occupied_count >= _get_auto_target_players()
			and all_ready
			and not _auto_launch_scheduled
			and ("--auto-ready" in OS.get_cmdline_args() + OS.get_cmdline_user_args())
		):
			_auto_launch_scheduled = true
			get_tree().create_timer(0.3).timeout.connect(func():
				if (
					is_inside_tree()
					and multiplayer.is_server()
					and start_button.visible
					and not start_button.disabled
					and _get_occupied_slot_count() >= _get_auto_target_players()
					and _are_all_occupied_ready()
				):
					_on_start_pressed()
				else:
					_auto_launch_scheduled = false
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


func _on_find_match_pressed() -> void:
	is_in_matchmaking_queue = true
	matchmaking_search_elapsed = 0.0
	search_timer_label.text = "00:00"
	search_status_label.text = "Finding match..."
	_show_searching_view()
	SessionManager.start_quick_match()


func _on_cancel_search_pressed() -> void:
	is_in_matchmaking_queue = false
	SessionManager.destroy_active_session()
	NetworkManager.disconnect_session()
	_show_matchmaking()
	status_label.text = "Matchmaking cancelled."


func _on_host_private_pressed() -> void:
	is_in_matchmaking_queue = false
	var code: String = SessionManager.generate_room_code()
	DisplayServer.clipboard_set(code)
	room_code_display.text = "Your Room Code: %s (Copied)" % code
	room_code_display.visible = true
	cancel_match_button.visible = true
	SessionManager.create_and_host_session(SessionManager.MatchType.PRIVATE, code)


func _on_join_private_pressed() -> void:
	is_in_matchmaking_queue = false
	var code: String = room_code_input.text.strip_edges().to_upper()
	if code.length() != 4:
		status_label.text = "Room code must be exactly 4 characters."
		return
	cancel_match_button.visible = true
	room_code_display.visible = false
	SessionManager.join_private_room(code)


func _on_cancel_match_pressed() -> void:
	is_in_matchmaking_queue = false
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
	if is_in_matchmaking_queue:
		if "found" in message.to_lower():
			search_status_label.text = "Match found!"
	else:
		status_label.text = message


func _on_matchmaking_failed(reason: String) -> void:
	if is_in_matchmaking_queue:
		_show_matchmaking()
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
	if is_in_matchmaking_queue:
		return
	_enter_staging()


func _on_connected_to_server() -> void:
	if is_in_matchmaking_queue:
		search_status_label.text = "Match found!"
	_enter_staging()
	if "--auto-ready" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		get_tree().create_timer(0.4).timeout.connect(func():
			if not _local_ready:
				_on_ready_pressed()
		)


func _on_connection_failed() -> void:
	if is_in_matchmaking_queue:
		print("Lobby: Connection failed while in matchmaking queue. Retrying search...")
		search_status_label.text = "Finding match..."
		SessionManager.start_quick_match()
		return

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

	_ensure_host_lobby_state()
	if _find_slot_by_peer_id(peer_id) != 0:
		return

	var open_slot: int = _find_first_open_slot()
	if open_slot == 0:
		print("Lobby: Rejecting peer %d — lobby full (%d/%d)." % [peer_id, NetworkManager.MAX_PLAYERS, NetworkManager.MAX_PLAYERS])
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	print("Lobby: Spy connected with peer ID %d -> Slot %d" % [peer_id, open_slot])
	lobby_state[open_slot] = {
		"slot": open_slot,
		"role": open_slot,
		"peer_id": peer_id,
		"ready": false,
		"name": "Spy (Peer %d)" % peer_id
	}
	sync_lobby_state.rpc(lobby_state)

	# Close quick match advertisement only when all 4 slots are filled
	if NetworkManager.current_mode == NetworkManager.NetworkMode.EOS_P2P and _get_occupied_slot_count() >= NetworkManager.MAX_PLAYERS:
		SessionManager.set_session_matchmaking_open(false)

	if is_in_matchmaking_queue:
		search_status_label.text = "Match found!"
		_enter_staging()
	else:
		_update_staging_ui()

	if "--auto-ready" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		get_tree().create_timer(0.4).timeout.connect(func():
			if is_inside_tree() and not _local_ready:
				_on_ready_pressed()
		)


func _on_player_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == 1:
		return

	var slot: int = _find_slot_by_peer_id(peer_id)
	if slot == 0:
		return

	print("Lobby: Peer %d (Slot %d) disconnected in staging." % [peer_id, slot])
	lobby_state[slot] = {
		"slot": slot,
		"role": slot,
		"peer_id": 0,
		"ready": false,
		"name": "Open Slot"
	}
	# Reset host readiness to avoid accidental start
	_local_ready = false
	_auto_launch_scheduled = false
	ready_button.text = "READY UP"
	if lobby_state.has(1):
		lobby_state[1]["ready"] = false
	sync_lobby_state.rpc(lobby_state)
	_update_staging_ui()

	# Re-open EOS quick match searches while below MAX_PLAYERS
	if NetworkManager.current_mode == NetworkManager.NetworkMode.EOS_P2P and _get_occupied_slot_count() < NetworkManager.MAX_PLAYERS:
		SessionManager.set_session_matchmaking_open(true)


@rpc("any_peer", "call_local", "reliable")
func register_client_identity(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0 or sender_id == 1:
		return

	_ensure_host_lobby_state()
	var slot: int = _find_slot_by_peer_id(sender_id)
	if slot == 0:
		slot = _find_first_open_slot()
		if slot == 0:
			return
		lobby_state[slot]["peer_id"] = sender_id
		lobby_state[slot]["ready"] = false

	lobby_state[slot]["name"] = display_name
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

	_ensure_host_lobby_state()
	var slot: int = _find_slot_by_peer_id(sender_id)
	if slot == 0:
		return

	lobby_state[slot]["ready"] = is_ready
	sync_lobby_state.rpc(lobby_state)
	_update_staging_ui()


@rpc("authority", "call_local", "reliable")
func sync_lobby_state(new_state: Dictionary) -> void:
	lobby_state = new_state
	_update_staging_ui()


func _on_start_pressed() -> void:
	if not multiplayer.is_server() or _is_launching:
		return
	var occupied_count: int = _get_occupied_slot_count()
	if occupied_count < NetworkManager.MIN_PLAYERS or not _are_all_occupied_ready():
		return

	_is_launching = true
	if NetworkManager.current_mode == NetworkManager.NetworkMode.EOS_P2P:
		SessionManager.set_session_matchmaking_open(false)

	var roles_map: Dictionary = {}
	for slot in range(1, NetworkManager.MAX_PLAYERS + 1):
		var slot_data: Dictionary = lobby_state.get(slot, {})
		var pid: int = int(slot_data.get("peer_id", 0))
		if pid != 0:
			roles_map[pid] = int(slot_data.get("role", slot))

	if MatchManager != null and MatchManager.has_method("sync_peer_roles"):
		MatchManager.sync_peer_roles(roles_map)

	if GameConfig != null:
		GameConfig.sandbox_gym_mode = false
	print("Lobby: %d players ready. Launching FFA match into arena..." % occupied_count)
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


func _ensure_spawner_cheatsheet_ui() -> void:
	if _spawner_cheatsheet_ui != null and is_instance_valid(_spawner_cheatsheet_ui):
		return
	var existing: Node = get_node_or_null("SpawnerCheatsheetUI")
	if existing is Control:
		_spawner_cheatsheet_ui = existing as Control
	else:
		_spawner_cheatsheet_ui = SPAWNER_CHEATSHEET_UI_SCRIPT.new() as Control
		_spawner_cheatsheet_ui.name = "SpawnerCheatsheetUI"
		add_child(_spawner_cheatsheet_ui)


func open_spawner_cheatsheet() -> void:
	_ensure_spawner_cheatsheet_ui()
	if _spawner_cheatsheet_ui != null:
		_spawner_cheatsheet_ui.call("open_cheatsheet", false, {})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F2:
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
