extends Node

const SESSION_NAME: String = "SpyVsSpySession"
const BUCKET_ID: String = "1:SpyVsSpy"
const ATTR_HOST_PUID: String = "HOST_PUID"
const ATTR_MATCH_TYPE: String = "MATCH_TYPE"
const ATTR_ROOM_CODE: String = "ROOM_CODE"
const CHAR_SET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # Excludes 0, O, 1, I to avoid visual ambiguity

enum MatchType { QUICK, PRIVATE }

signal matchmaking_status_changed(message: String)
signal matchmaking_failed(reason: String)
signal room_code_created(code: String)
signal session_closed()

var active_session_name: String = ""
var is_hosting_session: bool = false
var current_room_code: String = ""
var is_searching: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		is_searching = false
		if not active_session_name.is_empty():
			var opts := EOS.Sessions.DestroySessionOptions.new()
			opts.session_name = active_session_name
			active_session_name = ""
			is_hosting_session = false
			current_room_code = ""
			EOS.Sessions.SessionsInterface.destroy_session(opts)
			if EOSManager.is_initialized:
				EOS.Platform.platform_tick()


func generate_room_code() -> String:
	var code: String = ""
	for i in range(4):
		var idx: int = randi() % CHAR_SET.length()
		code += CHAR_SET[idx]
	return code


func create_and_host_session(match_type: MatchType, custom_code: String = "") -> bool:
	if EOSManager.local_puid.is_empty():
		var err_msg: String = "Cannot host session: EOS user is not authenticated."
		push_error("[SessionManager] %s" % err_msg)
		matchmaking_failed.emit(err_msg)
		return false

	if not active_session_name.is_empty():
		await destroy_active_session()

	var opts := EOS.Sessions.CreateSessionModificationOptions.new()
	opts.session_name = SESSION_NAME
	opts.bucket_id = BUCKET_ID
	opts.max_players = 2
	opts.presence_enabled = false
	opts.sanctions_enabled = false

	var mod_res: Dictionary = EOS.Sessions.SessionsInterface.create_session_modification(opts)
	if not EOS.is_success(mod_res) or not mod_res.has("session_modification"):
		var err_msg: String = "Failed to create session modification: %s" % EOS.result_str(mod_res)
		push_error("[SessionManager] %s" % err_msg)
		matchmaking_failed.emit(err_msg)
		return false

	var session_mod: EOSGSessionModification = mod_res.session_modification
	session_mod.set_bucket_id(BUCKET_ID)
	session_mod.set_max_players(2)
	session_mod.set_permission_level(EOS.Sessions.OnlineSessionPermissionLevel.PublicAdvertised)
	session_mod.set_join_in_progress_allowed(true)
	session_mod.set_invites_allowed(false)
	session_mod.set_host_address(EOSManager.local_puid)
	session_mod.add_attribute(ATTR_HOST_PUID, EOSManager.local_puid, EOS.Sessions.SessionAttributeAdvertisementType.Advertise)
	session_mod.add_attribute(ATTR_MATCH_TYPE, "QUICK" if match_type == MatchType.QUICK else "PRIVATE", EOS.Sessions.SessionAttributeAdvertisementType.Advertise)
	session_mod.add_attribute(ATTR_ROOM_CODE, custom_code if match_type == MatchType.PRIVATE else "NONE", EOS.Sessions.SessionAttributeAdvertisementType.Advertise)

	var update_opts := EOS.Sessions.UpdateSessionOptions.new()
	update_opts.session_modification = session_mod
	EOS.Sessions.SessionsInterface.update_session(update_opts)

	var update_res: Dictionary = await IEOS.sessions_interface_update_session_callback
	if not EOS.is_success(update_res):
		var err_msg: String = "Failed to register session with Epic backend: %s" % EOS.result_str(update_res)
		push_error("[SessionManager] %s" % err_msg)
		matchmaking_failed.emit("Failed to register session with Epic backend.")
		return false

	active_session_name = SESSION_NAME
	is_hosting_session = true
	current_room_code = custom_code

	NetworkManager.current_mode = NetworkManager.NetworkMode.EOS_P2P
	var host_err: Error = NetworkManager.start_host()
	if host_err != OK:
		var err_msg: String = "Failed to start network host: %s" % error_string(host_err)
		push_error("[SessionManager] %s" % err_msg)
		matchmaking_failed.emit(err_msg)
		await destroy_active_session()
		return false

	if match_type == MatchType.PRIVATE:
		DisplayServer.clipboard_set(custom_code)
		room_code_created.emit(custom_code)
		matchmaking_status_changed.emit("Private room created. Code: %s (copied to clipboard)" % custom_code)
	else:
		matchmaking_status_changed.emit("Quick Match session hosted. Waiting for opponent...")

	return true


func start_quick_match() -> void:
	is_searching = true
	matchmaking_status_changed.emit("Searching for available match...")

	if EOSManager.local_puid.is_empty():
		is_searching = false
		var err_msg: String = "Cannot search: EOS user is not authenticated."
		push_error("[SessionManager] %s" % err_msg)
		matchmaking_failed.emit(err_msg)
		return

	if not active_session_name.is_empty():
		await destroy_active_session()
		if not is_searching:
			return

	var session_search: EOSGSessionSearch = _create_session_search()
	if not session_search:
		is_searching = false
		matchmaking_failed.emit("Failed to create session search.")
		return

	session_search.set_parameter(EOS.Sessions.SEARCH_BUCKET_ID, BUCKET_ID, EOS.ComparisonOp.Equal)
	session_search.set_parameter(ATTR_MATCH_TYPE, "QUICK", EOS.ComparisonOp.Equal)
	session_search.set_parameter(EOS.Sessions.SEARCH_MINSLOTSAVAILABLE, 1, EOS.ComparisonOp.GreaterThanOrEqual)

	session_search.find(EOSManager.local_puid)
	await IEOS.session_search_find_callback

	if not is_searching:
		return

	var found_host_puid: String = _find_foreign_host_in_search(session_search)
	if not found_host_puid.is_empty():
		matchmaking_status_changed.emit("Found host. Connecting...")
		active_session_name = SESSION_NAME
		is_hosting_session = false
		is_searching = false
		NetworkManager.current_mode = NetworkManager.NetworkMode.EOS_P2P
		NetworkManager.start_join(found_host_puid)
		return

	# Anti-Race Jitter Window (If 0 results or only own host found)
	matchmaking_status_changed.emit("No active game found. Checking for concurrent hosts...")
	var jitter_delay: float = randf_range(0.5, 1.5)
	await get_tree().create_timer(jitter_delay).timeout

	if not is_searching:
		return

	session_search.find(EOSManager.local_puid)
	await IEOS.session_search_find_callback

	if not is_searching:
		return

	found_host_puid = _find_foreign_host_in_search(session_search)
	if not found_host_puid.is_empty():
		matchmaking_status_changed.emit("Found host. Connecting...")
		active_session_name = SESSION_NAME
		is_hosting_session = false
		is_searching = false
		NetworkManager.current_mode = NetworkManager.NetworkMode.EOS_P2P
		NetworkManager.start_join(found_host_puid)
		return

	# Still 0 results after jitter delay: become the host
	matchmaking_status_changed.emit("Hosting new Quick Match session...")
	is_searching = false
	await create_and_host_session(MatchType.QUICK)


func join_private_room(code: String) -> void:
	var sanitized_code: String = code.strip_edges().to_upper()
	if sanitized_code.length() != 4:
		matchmaking_failed.emit("Room code must be exactly 4 characters.")
		return

	if EOSManager.local_puid.is_empty():
		matchmaking_failed.emit("Cannot join room: EOS user is not authenticated.")
		return

	if not active_session_name.is_empty():
		await destroy_active_session()

	is_searching = true
	matchmaking_status_changed.emit("Locating room %s..." % sanitized_code)

	var session_search: EOSGSessionSearch = _create_session_search()
	if not session_search:
		is_searching = false
		matchmaking_failed.emit("Failed to create session search.")
		return

	session_search.set_parameter(EOS.Sessions.SEARCH_BUCKET_ID, BUCKET_ID, EOS.ComparisonOp.Equal)
	session_search.set_parameter(ATTR_ROOM_CODE, sanitized_code, EOS.ComparisonOp.Equal)

	session_search.find(EOSManager.local_puid)
	await IEOS.session_search_find_callback

	if not is_searching:
		return

	is_searching = false

	var count: int = session_search.get_search_result_count()
	if count == 0:
		matchmaking_failed.emit("Room code '%s' not found or match is full." % sanitized_code)
		return

	var host_puid: String = _extract_host_puid(session_search, 0)
	if host_puid.is_empty():
		matchmaking_failed.emit("Unable to resolve host address for room '%s'." % sanitized_code)
		return

	if host_puid == EOSManager.local_puid:
		matchmaking_failed.emit("Cannot join your own hosted room.")
		return

	matchmaking_status_changed.emit("Room found! Connecting to host...")
	active_session_name = SESSION_NAME
	is_hosting_session = false
	current_room_code = sanitized_code

	NetworkManager.current_mode = NetworkManager.NetworkMode.EOS_P2P
	NetworkManager.start_join(host_puid)


func destroy_active_session() -> void:
	is_searching = false
	if active_session_name.is_empty():
		return

	var session_name_to_destroy: String = active_session_name
	active_session_name = ""
	is_hosting_session = false
	current_room_code = ""

	var opts := EOS.Sessions.DestroySessionOptions.new()
	opts.session_name = session_name_to_destroy
	EOS.Sessions.SessionsInterface.destroy_session(opts)
	await IEOS.sessions_interface_destroy_session_callback

	session_closed.emit()


func _create_session_search() -> EOSGSessionSearch:
	var opts := EOS.Sessions.CreateSessionSearchOptions.new()
	opts.max_search_results = 10
	var ret: Dictionary = EOS.Sessions.SessionsInterface.create_session_search(opts)
	if not EOS.is_success(ret) or not ret.has("session_search"):
		return null
	return ret.session_search


func _find_foreign_host_in_search(session_search: EOSGSessionSearch) -> String:
	var count: int = session_search.get_search_result_count()
	for i in range(count):
		var puid: String = _extract_host_puid(session_search, i)
		if not puid.is_empty() and puid != EOSManager.local_puid:
			return puid
	return ""


func _extract_host_puid(session_search: EOSGSessionSearch, index: int) -> String:
	var copy_res: Dictionary = session_search.copy_search_result_by_index(index)
	if not EOS.is_success(copy_res) or not copy_res.has("session_details"):
		return ""

	var session_details: EOSGSessionDetails = copy_res.session_details
	if not session_details:
		return ""

	# Check ATTR_HOST_PUID attribute
	var attr_res: Dictionary = session_details.copy_session_attribute_by_key(ATTR_HOST_PUID)
	if EOS.is_success(attr_res) and attr_res.has("session_attribute"):
		var sa = attr_res.session_attribute
		if sa is Dictionary:
			if sa.has("data"):
				var data = sa.data
				if data is Dictionary and data.has("value"):
					return str(data.value)
				elif data is String:
					return data
			if sa.has("value"):
				return str(sa.value)

	# Fallback to copy_info().info.host_address
	var info_res: Dictionary = session_details.copy_info()
	if EOS.is_success(info_res) and info_res.has("info"):
		var info = info_res.info
		if info is Dictionary and info.has("host_address"):
			return str(info.host_address)

	return ""

