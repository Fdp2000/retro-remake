extends Control

const PROFILE_PATH := "user://lobby_profile.cfg"
const MAX_NAME_LENGTH := 24

const TEST_GYM_SCENE_PATH: String = "res://scenes/test_gym.tscn"
const SPAWNER_CHEATSHEET_UI_SCRIPT = preload("res://ui/spawner_cheatsheet_ui.gd")
const MAIN_MENU_OPTIONS_UI_SCRIPT = preload("res://ui/main_menu_options_ui.gd")

# State Dictionary: slot (1..4) -> {"slot": int, "role": int, "peer_id": int, "ready": bool, "name": String}
var lobby_state: Dictionary = {}

const FAN_AUDIO := "res://Assets/SFX/Lobby/Ambience Ceiling Fan 01.wav"
const RELAY_AUDIO := "res://Assets/SFX/Lobby/Cartoon Metal Clinks 01.wav"
const READY_AUDIO := "res://Assets/SFX/Lobby/Cartoon Bell Hit 01.wav"

var _profile := ConfigFile.new()
var _relay_audio: AudioStreamPlayer
var _ready_audio: AudioStreamPlayer
var _room_was_ready := false
var _creating_private_room := false
var _free_for_all := false
var _room_free_for_all := false
var _developer_from_play_options := false

var _local_ready: bool = false
var _auto_launch_scheduled: bool = false
var _is_launching: bool = false
var is_in_matchmaking_queue: bool = false
var matchmaking_search_elapsed: float = 0.0
var _spawner_cheatsheet_ui: Control = null
var _options_ui: MainMenuOptionsUI = null
var _slot_cards: Dictionary = {} # slot (1..4) -> {"card": PanelContainer, "title": Label, "swatch": ColorRect, "name": Label, "status": Label}

# UI References
@onready var matchmaking_container: PanelContainer = $MarginContainer/MatchmakingContainer
@onready var play_options_container: PanelContainer = $MarginContainer/PlayOptionsContainer
@onready var play_options_title: Label = $MarginContainer/PlayOptionsContainer/PlayOptionsPanel/ModeLabel
@onready var play_options_back: Button = $MarginContainer/PlayOptionsContainer/PlayOptionsPanel/BackButton
@onready var developer_container: PanelContainer = $MarginContainer/DeveloperContainer
@onready var developer_panel: VBoxContainer = $MarginContainer/DeveloperContainer/DeveloperPanel
@onready var developer_status: Label = $MarginContainer/DeveloperContainer/DeveloperPanel/StatusLabel
@onready var searching_container: PanelContainer = $MarginContainer/SearchingContainer
@onready var staging_container: VBoxContainer = $MarginContainer/StagingContainer

# Searching Controls
@onready var search_timer_label: Label = $MarginContainer/SearchingContainer/SearchingPanel/SearchTimerLabel
@onready var search_status_label: Label = $MarginContainer/SearchingContainer/SearchingPanel/SearchStatusLabel
@onready var cancel_search_button: Button = $MarginContainer/SearchingContainer/SearchingPanel/CancelSearchButton

# Matchmaking Controls
@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var enet_address_input: LineEdit = $MarginContainer/DeveloperContainer/DeveloperPanel/ENetControls/ENetAddressInput
@onready var enet_host_button: Button = $MarginContainer/DeveloperContainer/DeveloperPanel/ENetControls/ENetHostButton
@onready var enet_join_button: Button = $MarginContainer/DeveloperContainer/DeveloperPanel/ENetControls/ENetJoinButton

@onready var quick_match_button: Button = $MarginContainer/PlayOptionsContainer/PlayOptionsPanel/EOSControls/QuickMatchButton
@onready var host_private_button: Button = $MarginContainer/PlayOptionsContainer/PlayOptionsPanel/EOSControls/HostPrivateButton
@onready var room_code_input: LineEdit = $MarginContainer/PlayOptionsContainer/PlayOptionsPanel/EOSControls/PrivateJoinContainer/RoomCodeInput
@onready var join_private_button: Button = $MarginContainer/PlayOptionsContainer/PlayOptionsPanel/EOSControls/PrivateJoinContainer/JoinPrivateButton
@onready var cancel_match_button: Button = $MarginContainer/PlayOptionsContainer/PlayOptionsPanel/EOSControls/CancelMatchButton
@onready var status_label: Label = $MarginContainer/PlayOptionsContainer/PlayOptionsPanel/StatusLabel

# Staging Controls
@onready var header_label: Label = $MarginContainer/StagingContainer/HeaderLabel
@onready var room_code_strip: PanelContainer = $MarginContainer/StagingContainer/RoomCodeStrip
@onready var staging_room_code: Label = $MarginContainer/StagingContainer/RoomCodeStrip/RoomCodeRow/RoomCodeLabel
@onready var copy_room_code_button: Button = $MarginContainer/StagingContainer/RoomCodeStrip/RoomCodeRow/CopyButton
@onready var cards_container: HBoxContainer = $MarginContainer/StagingContainer/CardsContainer

@onready var ready_button: Button = $MarginContainer/StagingContainer/ActionsContainer/ReadyButton
@onready var start_button: Button = $MarginContainer/StagingContainer/ActionsContainer/StartButton
@onready var disconnect_button: Button = $MarginContainer/StagingContainer/ActionsContainer/DisconnectButton


func _ready() -> void:
	# Ensure mouse is visible in lobby
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Bind and style all 4 FFA spy staging cards (Green, Purple, Blue, Red)
	_init_slot_cards()
	_setup_console_audio()
	copy_room_code_button.pressed.connect(_copy_staging_room_code)

	_setup_developer_tools()
	_setup_options_menu()

	_profile.load(PROFILE_PATH)
	player_name_input.text = str(_profile.get_value("player", "name", "")).left(MAX_NAME_LENGTH)
	player_name_input.text_changed.connect(_save_player_name)
	_free_for_all = _get_auto_target_players() >= 3
	_room_free_for_all = _free_for_all
	$MarginContainer/MatchmakingContainer/MatchmakingPanel/GameModeRow/DuelButton.pressed.connect(_open_play_options.bind(false))
	$MarginContainer/MatchmakingContainer/MatchmakingPanel/GameModeRow/FFAButton.pressed.connect(_open_play_options.bind(true))
	$MarginContainer/MatchmakingContainer/MatchmakingPanel/OptionsButton.pressed.connect(_on_options_pressed)
	$MarginContainer/MatchmakingContainer/MatchmakingPanel/QuitButton.pressed.connect(_on_quit_pressed)
	play_options_back.pressed.connect(_close_play_options)
	cancel_match_button.visibility_changed.connect(func(): play_options_back.disabled = cancel_match_button.visible or _creating_private_room)
	$MarginContainer/DeveloperContainer/DeveloperPanel/CloseButton.pressed.connect(_toggle_developer_tools)

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
		search_status_label.text = "Finding %s match%s" % [_game_mode_name(), ".".repeat(dot_count)]


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
		var status_lbl := vbox.get_node_or_null("P%dStatusLabel" % slot) as Label
		if swatch_rect != null and GameConfig != null:
			swatch_rect.color = GameConfig.get_spy_role_color(slot)
		_slot_cards[slot] = {
			"card": card,
			"title": title_lbl,
			"swatch": swatch_rect,
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
	for slot in range(2, _room_capacity() + 1):
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
	_room_was_ready = false
	is_in_matchmaking_queue = false
	_auto_launch_scheduled = false
	_is_launching = false
	lobby_state.clear()
	matchmaking_container.visible = true
	play_options_container.hide()
	developer_container.hide()
	searching_container.visible = false
	staging_container.visible = false
	_local_ready = false
	ready_button.text = "READY UP"


func _show_searching_view() -> void:
	matchmaking_container.visible = false
	play_options_container.hide()
	developer_container.hide()
	searching_container.visible = true
	staging_container.visible = false


func _enter_staging() -> void:
	is_in_matchmaking_queue = false
	_auto_launch_scheduled = false
	_is_launching = false
	matchmaking_container.visible = false
	play_options_container.hide()
	developer_container.hide()
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


func _on_quit_pressed() -> void:
	var quit_btn: Button = get_node_or_null("MarginContainer/MatchmakingContainer/MatchmakingPanel/QuitButton") as Button
	if quit_btn != null:
		quit_btn.disabled = true
	if get_tree() != null:
		await get_tree().create_timer(0.08).timeout
		if get_tree() != null:
			if get_tree().root != null:
				get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			get_tree().quit()


func _open_play_options(free_for_all: bool) -> void:
	_free_for_all = free_for_all
	play_options_title.text = "Free-for-All · 3–4 agents" if free_for_all else "1v1 · Two agents"
	_relay_audio.play()
	matchmaking_container.hide()
	play_options_container.show()
	quick_match_button.grab_focus()


func _close_play_options() -> void:
	play_options_container.hide()
	matchmaking_container.show()
	var mode_button: Button = $MarginContainer/MatchmakingContainer/MatchmakingPanel/GameModeRow/FFAButton if _free_for_all else $MarginContainer/MatchmakingContainer/MatchmakingPanel/GameModeRow/DuelButton
	mode_button.grab_focus()


func _toggle_developer_tools() -> void:
	if searching_container.visible or staging_container.visible or cancel_match_button.visible or _creating_private_room:
		return
	if developer_container.visible:
		if is_instance_valid(_spawner_cheatsheet_ui) and _spawner_cheatsheet_ui.visible:
			_spawner_cheatsheet_ui.call("close_cheatsheet")
		developer_container.hide()
		if _developer_from_play_options:
			_open_play_options(_free_for_all)
		else:
			matchmaking_container.show()
	else:
		_developer_from_play_options = play_options_container.visible
		play_options_container.hide()
		matchmaking_container.hide()
		developer_container.show()


func _setup_developer_tools() -> void:
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
	developer_panel.add_child(solo_match_btn)

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
	developer_panel.add_child(solo_btn)

	var cheatsheet_btn := Button.new()
	cheatsheet_btn.name = "SpawnerCheatsheetButton"
	cheatsheet_btn.text = "Spawner Cheatsheet & Tuner [F2]"
	cheatsheet_btn.pressed.connect(open_spawner_cheatsheet)
	developer_panel.add_child(cheatsheet_btn)

	var sep := HSeparator.new()
	developer_panel.add_child(sep)
	var mouse_widget: VBoxContainer = preload("res://ui/mouse_settings_widget.gd").new()
	mouse_widget.name = "MouseSettingsWidget"
	developer_panel.add_child(mouse_widget)
	developer_panel.move_child($MarginContainer/DeveloperContainer/DeveloperPanel/CloseButton, -1)

func _update_header() -> void:
	header_label.text = _game_mode_name()
	var code := SessionManager.current_room_code
	room_code_strip.visible = not code.is_empty() and code != "NONE"
	staging_room_code.text = "Room Code  %s" % code if room_code_strip.visible else ""


func _copy_staging_room_code() -> void:
	DisplayServer.clipboard_set(SessionManager.current_room_code)
	copy_room_code_button.text = "Copied"
	_relay_audio.play()
	await get_tree().create_timer(1.2).timeout
	copy_room_code_button.text = "Copy"


func _setup_console_audio() -> void:
	_relay_audio = _add_console_audio(RELAY_AUDIO, -25.0)
	_ready_audio = _add_console_audio(READY_AUDIO, -24.0)
	var fan_player := _add_console_audio(FAN_AUDIO, -35.0)
	if fan_player.stream is AudioStreamWAV:
		var fan := fan_player.stream.duplicate() as AudioStreamWAV
		fan.loop_mode = AudioStreamWAV.LOOP_FORWARD
		fan.loop_end = roundi(fan.get_length() * fan.mix_rate)
		fan_player.stream = fan
		fan_player.play()


func _add_console_audio(path: String, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = volume
	if AudioServer.get_bus_index(&"SFX") != -1:
		player.bus = &"SFX"
	if ResourceLoader.exists(path):
		player.stream = load(path) as AudioStream
	add_child(player)
	return player


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
		var name_lbl := card_ui.get("title") as Label
		var status_lbl := card_ui.get("status") as Label
		if card_panel != null:
			card_panel.visible = slot <= _room_capacity()
		if name_lbl != null:
			name_lbl.text = str(slot_data.get("name", "Player")) if is_occupied else "Open Slot"
			if slot_peer_id == 1:
				name_lbl.text += " (Host)"
		if status_lbl != null:
			status_lbl.self_modulate.a = 1.0 if is_occupied else 0.0

		if is_occupied:
			if status_lbl != null:
				status_lbl.text = "● READY" if is_ready else "● NOT READY"
				status_lbl.modulate = Color(0.53, 0.89, 0.65) if is_ready else Color(0.94, 0.73, 0.42)
			if card_panel != null:
				card_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			if card_panel != null:
				card_panel.modulate = Color(0.75, 0.75, 0.75, 0.85)

	var occupied_count: int = _get_occupied_slot_count()
	var all_ready: bool = _are_all_occupied_ready()
	var room_ready := occupied_count >= _room_minimum() and all_ready
	if room_ready and not _room_was_ready and staging_container.visible:
		_ready_audio.play()
	_room_was_ready = room_ready

	# Update Start Button (Host only)
	if multiplayer.is_server():
		start_button.visible = true
		start_button.text = "LAUNCH MATCH (%d/%d)" % [occupied_count, _room_capacity()]
		start_button.disabled = not room_ready
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


func _game_mode_name() -> String:
	return "Free-for-All" if _room_free_for_all else "1v1"


func _room_capacity() -> int:
	return 4 if _room_free_for_all else 2


func _room_minimum() -> int:
	return 3 if _room_free_for_all else 2


func _save_player_name(value: String) -> void:
	_profile.set_value("player", "name", value.strip_edges())
	var error := _profile.save(PROFILE_PATH)
	if error != OK:
		push_warning("Could not save lobby player name: %s" % error_string(error))


func _get_host_name() -> String:
	var chosen_name := player_name_input.text.strip_edges()
	if not chosen_name.is_empty():
		return chosen_name
	return "Player"


func _get_client_name() -> String:
	var chosen_name := player_name_input.text.strip_edges()
	if not chosen_name.is_empty():
		return chosen_name
	return "Player"


# ==========================================
# Matchmaking Actions (ENet & EOS)
# ==========================================

func _on_enet_host_pressed() -> void:
	_room_free_for_all = _free_for_all
	NetworkManager.current_mode = NetworkManager.NetworkMode.ENET_LOCAL
	var err: Error = NetworkManager.start_host()
	if err == OK:
		developer_status.text = "ENet server started."
	else:
		developer_status.text = "Failed to start ENet host: %s" % error_string(err)


func _on_enet_join_pressed() -> void:
	NetworkManager.current_mode = NetworkManager.NetworkMode.ENET_LOCAL
	var target_addr: String = enet_address_input.text.strip_edges()
	if target_addr.is_empty():
		target_addr = "127.0.0.1"
	var err: Error = NetworkManager.start_join(target_addr)
	if err == OK:
		developer_status.text = "Connecting via ENet to %s:%d..." % [target_addr, NetworkManager.PORT]
	else:
		developer_status.text = "Failed to connect: %s" % error_string(err)


func _on_find_match_pressed() -> void:
	NetworkManager.current_mode = NetworkManager.NetworkMode.EOS_P2P
	_room_free_for_all = _free_for_all
	is_in_matchmaking_queue = true
	matchmaking_search_elapsed = 0.0
	search_timer_label.text = "00:00"
	search_status_label.text = "Finding %s match..." % _game_mode_name()
	_show_searching_view()
	SessionManager.start_quick_match(_room_free_for_all)


func _on_cancel_search_pressed() -> void:
	is_in_matchmaking_queue = false
	SessionManager.destroy_active_session()
	NetworkManager.disconnect_session()
	_show_matchmaking()
	_open_play_options(_free_for_all)
	status_label.text = "Matchmaking cancelled."


func _on_host_private_pressed() -> void:
	NetworkManager.current_mode = NetworkManager.NetworkMode.EOS_P2P
	_room_free_for_all = _free_for_all
	is_in_matchmaking_queue = false
	_set_private_room_pending(true)
	status_label.text = "Creating private room…"
	var code: String = SessionManager.generate_room_code()
	await SessionManager.create_and_host_session(SessionManager.MatchType.PRIVATE, code, _room_free_for_all)
	_set_private_room_pending(false)


func _set_private_room_pending(pending: bool) -> void:
	_creating_private_room = pending
	quick_match_button.disabled = pending
	host_private_button.disabled = pending
	join_private_button.disabled = pending
	play_options_back.disabled = pending or cancel_match_button.visible


func _on_join_private_pressed() -> void:
	NetworkManager.current_mode = NetworkManager.NetworkMode.EOS_P2P
	is_in_matchmaking_queue = false
	var code: String = room_code_input.text.strip_edges().to_upper()
	if code.length() != 4:
		status_label.text = "Room code must be exactly 4 characters."
		return
	cancel_match_button.visible = true
	SessionManager.join_private_room(code)


func _on_cancel_match_pressed() -> void:
	is_in_matchmaking_queue = false
	cancel_match_button.visible = false
	SessionManager.destroy_active_session()
	NetworkManager.disconnect_session()
	status_label.text = "Matchmaking cancelled."


# ==========================================
# EOS Callbacks
# ==========================================

func _on_eos_login_success(_puid: String) -> void:
	status_label.text = ""


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
		_open_play_options(_free_for_all)
	status_label.text = "Error: %s" % reason
	cancel_match_button.visible = false


func _on_session_closed() -> void:
	cancel_match_button.visible = false


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
		search_status_label.text = "Finding %s match..." % _game_mode_name()
		SessionManager.start_quick_match(_room_free_for_all)
		return

	if developer_container.visible:
		developer_status.text = "Connection failed."
		return
	_show_matchmaking()
	_open_play_options(_free_for_all)
	cancel_match_button.visible = false
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
		print("Lobby: Rejecting peer %d — lobby full (%d/%d)." % [peer_id, _room_capacity(), _room_capacity()])
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	print("Lobby: Spy connected with peer ID %d -> Slot %d" % [peer_id, open_slot])
	lobby_state[open_slot] = {
		"slot": open_slot,
		"role": open_slot,
		"peer_id": peer_id,
		"ready": false,
		"name": "Player"
	}
	sync_lobby_state.rpc(lobby_state, _room_free_for_all)

	# Update quick match player count and close advertisement when the room is full
	if NetworkManager.current_mode == NetworkManager.NetworkMode.EOS_P2P and SessionManager.current_room_code.is_empty():
		var occupied: int = _get_occupied_slot_count()
		SessionManager.set_session_matchmaking_open(occupied < _room_capacity(), occupied)

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
	sync_lobby_state.rpc(lobby_state, _room_free_for_all)
	_update_staging_ui()

	# Re-open quick match searches and update player count when a slot frees up.
	if NetworkManager.current_mode == NetworkManager.NetworkMode.EOS_P2P and SessionManager.current_room_code.is_empty():
		var occupied: int = _get_occupied_slot_count()
		SessionManager.set_session_matchmaking_open(occupied < _room_capacity(), occupied)


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

	var safe_name := display_name.strip_edges().left(MAX_NAME_LENGTH)
	if not safe_name.is_empty():
		lobby_state[slot]["name"] = safe_name
	sync_lobby_state.rpc(lobby_state, _room_free_for_all)
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
	sync_lobby_state.rpc(lobby_state, _room_free_for_all)
	_update_staging_ui()


@rpc("authority", "call_local", "reliable")
func sync_lobby_state(new_state: Dictionary, free_for_all: bool) -> void:
	_room_free_for_all = free_for_all
	lobby_state = new_state
	_update_header()
	_update_staging_ui()


func _on_start_pressed() -> void:
	if not multiplayer.is_server() or _is_launching:
		return
	var occupied_count: int = _get_occupied_slot_count()
	if occupied_count < _room_minimum() or not _are_all_occupied_ready():
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
	print("Lobby: %d players ready. Launching match into arena..." % occupied_count)
	rpc_load_arena.rpc(TEST_GYM_SCENE_PATH)


@rpc("authority", "call_local", "reliable")
func rpc_load_arena(scene_path: String) -> void:
	print("Lobby: Transitioning to arena: %s" % scene_path)
	get_tree().change_scene_to_file(scene_path)


func _on_disconnect_pressed() -> void:
	_leave_lobby("Left lobby.")


func _leave_lobby(reason: String = "") -> void:
	var departed_mode := _room_free_for_all
	NetworkManager.disconnect_session()
	_show_matchmaking()
	cancel_match_button.hide()
	_open_play_options(departed_mode)
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


func _setup_options_menu() -> void:
	if _options_ui == null:
		_options_ui = MAIN_MENU_OPTIONS_UI_SCRIPT.new()
		_options_ui.name = "MainMenuOptionsUI"
		add_child(_options_ui)


func _on_options_pressed() -> void:
	if _options_ui != null:
		_options_ui.open_options()


func open_spawner_cheatsheet() -> void:
	_ensure_spawner_cheatsheet_ui()
	if _spawner_cheatsheet_ui != null:
		_spawner_cheatsheet_ui.call("open_cheatsheet", false, {})


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F12:
		_toggle_developer_tools()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _options_ui != null and _options_ui.visible:
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ESCAPE):
			_options_ui.close_options()
			get_viewport().set_input_as_handled()
			return
	if developer_container.visible and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F2:
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
