extends Node

const CREDENTIALS_PATH: String = "res://config/eos_credentials.cfg"

var product_id: String = ""
var sandbox_id: String = ""
var deployment_id: String = ""
var client_id: String = ""
var client_secret: String = ""
var encryption_key: String = ""

# Signals
signal eos_initialized()
signal login_success(product_user_id: String)
signal login_failed(error_message: String)

# Cached local Product User ID
var local_puid: String = ""
var is_initialized: bool = false


func _load_credentials() -> bool:
	var config := ConfigFile.new()
	var err := config.load(CREDENTIALS_PATH)
	if err != OK:
		printerr("[EOSManager] CRITICAL: Missing credentials file at: ", CREDENTIALS_PATH)
		printerr("[EOSManager] Copy 'res://config/eos_credentials.template.cfg' to 'eos_credentials.cfg' and add valid keys.")
		return false

	product_id = config.get_value("eos", "product_id", "")
	sandbox_id = config.get_value("eos", "sandbox_id", "")
	deployment_id = config.get_value("eos", "deployment_id", "")
	client_id = config.get_value("eos", "client_id", "")
	client_secret = config.get_value("eos", "client_secret", "")
	encryption_key = config.get_value("eos", "encryption_key", "")

	if product_id.is_empty() or client_id.is_empty() or client_secret.is_empty():
		printerr("[EOSManager] CRITICAL: Required credentials missing in: ", CREDENTIALS_PATH)
		return false

	print("[EOSManager] Credentials successfully loaded from config.")
	return true


func _ready() -> void:
	# 1. Check if IEOS singleton is registered
	if not Engine.has_singleton("IEOS"):
		var err_msg: String = "[EOSManager] Error: IEOS singleton is not registered. Verify epic-online-services-godot plugin is enabled."
		printerr(err_msg)
		login_failed.emit(err_msg)
		return

	if not _load_credentials():
		printerr("[EOSManager] Aborting initialization due to missing credentials.")
		return

	# 2. Configure platform creation options with verified credentials & tick budget
	var create_opts := EOS.Platform.CreateOptions.new()
	create_opts.product_id = product_id
	create_opts.sandbox_id = sandbox_id
	create_opts.deployment_id = deployment_id
	create_opts.client_id = client_id
	create_opts.client_secret = client_secret
	create_opts.encryption_key = encryption_key
	
	# Configure tick budget based on target frame rate (at least 2ms, target ~10ms for 60fps)
	var max_fps: float = max(Engine.get_max_fps() * 1.0, 60.0)
	var budget_ms: int = maxi(floori((0.3 * 1000.0) / max_fps), 2)
	create_opts.tick_budget_in_milliseconds = budget_ms

	if OS.get_name() == "Windows":
		create_opts.flags = EOS.Platform.PlatformFlags.WindowsEnableOverlayOpengl

	# 3. Initialize platform
	var create_success: bool = EOS.Platform.platform_create(create_opts)
	if not create_success:
		var err_msg: String = "[EOSManager] Failed to create EOS platform."
		printerr(err_msg)
		login_failed.emit(err_msg)
		return

	is_initialized = true
	print("[EOSManager] EOS platform initialized successfully.")
	eos_initialized.emit()

	# 4. Initiate silent Device ID login flow
	_login_device_id()


func _process(_delta: float) -> void:
	# Call EOS.Platform.platform_tick() every frame to pump async network callbacks
	if is_initialized:
		EOS.Platform.platform_tick()


func _login_device_id(allow_create_device: bool = true) -> void:
	var login_options := EOS.Connect.LoginOptions.new()
	login_options.credentials = EOS.Connect.Credentials.new()
	login_options.credentials.type = EOS.ExternalCredentialType.DEVICEID_ACCESS_TOKEN
	login_options.credentials.token = null
	login_options.user_login_info = EOS.Connect.UserLoginInfo.new()
	
	var user_name: String = OS.get_environment("USERNAME")
	if user_name.is_empty():
		user_name = "Player"
	login_options.user_login_info.display_name = user_name

	EOS.Connect.ConnectInterface.login(login_options)
	var login_ret: Dictionary = await IEOS.connect_interface_login_callback
	var result_code: int = login_ret.get("result_code", EOS.Result.UnexpectedError)

	# If account/device ID is not found on first boot, create device ID and retry
	if result_code == EOS.Result.NotFound:
		if allow_create_device:
			print("[EOSManager] Device ID not found on first boot. Creating device ID...")
			var device_opts := EOS.Connect.CreateDeviceIdOptions.new()
			device_opts.device_model = OS.get_name() + "_" + OS.get_model_name()
			EOS.Connect.ConnectInterface.create_device_id(device_opts)

			var create_device_ret: Dictionary = await IEOS.connect_interface_create_device_id_callback
			var create_dev_res: int = create_device_ret.get("result_code", EOS.Result.UnexpectedError)
			if not (EOS.is_success(create_dev_res) or create_dev_res == EOS.Result.DuplicateNotAllowed):
				var err_msg: String = "[EOSManager] Failed to create Device ID: %s (%d)" % [EOS.result_str(create_dev_res), create_dev_res]
				printerr(err_msg)
				login_failed.emit(err_msg)
				return

			print("[EOSManager] Device ID created successfully. Retrying login...")
			_login_device_id(false)
			return
		else:
			var err_msg: String = "[EOSManager] Device ID login failed after creation attempt (NotFound)."
			printerr(err_msg)
			login_failed.emit(err_msg)
			return

	# If device ID exists but user mapping is needed (EOS.Result.InvalidUser)
	if result_code == EOS.Result.InvalidUser:
		var continuance_token = login_ret.get("continuance_token")
		if continuance_token != null:
			print("[EOSManager] User not registered for Device ID. Creating Connect user...")
			var create_user_opts := EOS.Connect.CreateUserOptions.new()
			create_user_opts.continuance_token = continuance_token
			EOS.Connect.ConnectInterface.create_user(create_user_opts)

			var create_user_ret: Dictionary = await IEOS.connect_interface_create_user_callback
			var create_user_res: int = create_user_ret.get("result_code", EOS.Result.UnexpectedError)
			if not EOS.is_success(create_user_res):
				var err_msg: String = "[EOSManager] Failed to create EOS user: %s (%d)" % [EOS.result_str(create_user_res), create_user_res]
				printerr(err_msg)
				login_failed.emit(err_msg)
				return

			local_puid = str(create_user_ret.get("local_user_id", ""))
			print("[EOS] Logged in successfully. PUID: " + local_puid)
			login_success.emit(local_puid)
			return

	# Successful login
	if EOS.is_success(result_code):
		local_puid = str(login_ret.get("local_user_id", ""))
		print("[EOS] Logged in successfully. PUID: " + local_puid)
		login_success.emit(local_puid)
		return

	# Failure case
	var err_str: String = "[EOSManager] Login failed with error: %s (code: %d)" % [EOS.result_str(result_code), result_code]
	printerr(err_str)
	login_failed.emit(err_str)

