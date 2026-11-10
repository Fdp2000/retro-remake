extends Node

enum NetworkMode {
	ENET_LOCAL,
	EOS_P2P
}

enum RelayControlMode {
	NO_RELAYS = 0,
	ALLOW_RELAYS = 1,  # EOS.P2P.RelayControl.AllowRelays (Default: STUN Direct with TURN fallback)
	FORCE_RELAYS = 2   # EOS.P2P.RelayControl.ForceRelays (Force TURN Relay)
}

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_started()
signal connection_failed()
signal connected_to_server()
signal server_disconnected()
signal peer_connection_established(info: Dictionary)
signal relay_mode_changed(mode: RelayControlMode)
signal p2p_diagnostic_logged(network_type_str: String, is_relay: bool)

const PORT: int = 8910
const SOCKET_NAME: String = "SpyVsSpySocket"
const MAX_PLAYERS: int = 2
const DEFAULT_ENET_HOST: String = "127.0.0.1"

var current_mode: NetworkMode = NetworkMode.EOS_P2P
var current_relay_mode: RelayControlMode = RelayControlMode.ALLOW_RELAYS
var peer: MultiplayerPeer = null
var last_p2p_network_type: String = "NONE"


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	call_deferred("_check_cmdline_args")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if peer:
			peer.close()
			peer = null
		if current_mode == NetworkMode.EOS_P2P:
			SessionManager.destroy_active_session()


func _check_cmdline_args() -> void:
	var args: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--enet" in args:
		current_mode = NetworkMode.ENET_LOCAL
		print("NetworkManager: Selected ENET_LOCAL mode via CLI.")
	elif "--eos" in args:
		current_mode = NetworkMode.EOS_P2P
		print("NetworkManager: Selected EOS_P2P mode via CLI.")

	if "--force-relay" in args:
		current_relay_mode = RelayControlMode.FORCE_RELAYS
	elif "--allow-relay" in args:
		current_relay_mode = RelayControlMode.ALLOW_RELAYS
	elif "--no-relay" in args:
		current_relay_mode = RelayControlMode.NO_RELAYS

	if "--host" in args:
		start_host()
	elif "--join" in args:
		start_join()


func apply_relay_control(mode: RelayControlMode = current_relay_mode) -> Error:
	current_relay_mode = mode
	var eos_relay: int = EOS.P2P.RelayControl.AllowRelays
	match current_relay_mode:
		RelayControlMode.ALLOW_RELAYS:
			eos_relay = EOS.P2P.RelayControl.AllowRelays
		RelayControlMode.FORCE_RELAYS:
			eos_relay = EOS.P2P.RelayControl.ForceRelays
		RelayControlMode.NO_RELAYS:
			eos_relay = EOS.P2P.RelayControl.NoRelays

	var res = EOS.P2P.P2PInterface.set_relay_control(eos_relay)
	if not EOS.is_success(res):
		push_error("NetworkManager: Failed to set EOS P2P relay control: %s (%s)" % [EOS.result_str(res), str(res)])
		return FAILED

	relay_mode_changed.emit(current_relay_mode)
	return OK


func start_host() -> Error:
	_cleanup_peer(false)

	if current_mode == NetworkMode.ENET_LOCAL:
		var enet_peer := ENetMultiplayerPeer.new()
		var err = enet_peer.create_server(PORT, MAX_PLAYERS)
		if err != OK:
			push_error("NetworkManager: Failed to create ENet server on port %d: %s" % [PORT, error_string(err)])
			return err as Error
		peer = enet_peer
		multiplayer.multiplayer_peer = peer
		print("NetworkManager: ENet server started on port %d" % PORT)

	elif current_mode == NetworkMode.EOS_P2P:
		# Apply relay control setting before instantiating or initializing peer
		apply_relay_control()

		var eos_peer := EOSGMultiplayerPeer.new()
		_connect_eos_peer_diagnostics(eos_peer)

		var err = eos_peer.create_server(SOCKET_NAME)
		if err != OK:
			push_error("NetworkManager: Failed to create EOS P2P server on socket %s: %s" % [SOCKET_NAME, error_string(err)])
			return err as Error
		peer = eos_peer
		multiplayer.multiplayer_peer = peer
		print("NetworkManager: EOS P2P server started on socket '%s'" % SOCKET_NAME)

	else:
		return ERR_UNCONFIGURED

	server_started.emit()
	# The host is Peer 1; notify local game systems that Peer 1 has connected.
	player_connected.emit(1)
	return OK


func start_join(target_address_or_puid: String = "") -> Error:
	_cleanup_peer(false)

	if current_mode == NetworkMode.ENET_LOCAL:
		var address: String = target_address_or_puid.strip_edges()
		if address.is_empty():
			address = DEFAULT_ENET_HOST
		var enet_peer := ENetMultiplayerPeer.new()
		var err = enet_peer.create_client(address, PORT)
		if err != OK:
			push_error("NetworkManager: Failed to create ENet client to %s:%d: %s" % [address, PORT, error_string(err)])
			return err as Error
		peer = enet_peer
		multiplayer.multiplayer_peer = peer
		print("NetworkManager: Connecting via ENet to %s:%d..." % [address, PORT])

	elif current_mode == NetworkMode.EOS_P2P:
		var target_puid: String = target_address_or_puid.strip_edges()
		if target_puid.is_empty():
			push_error("NetworkManager: Failed to join EOS P2P: target PUID is empty.")
			return ERR_INVALID_PARAMETER

		# Apply relay control setting before instantiating or initializing peer
		apply_relay_control()

		var eos_peer := EOSGMultiplayerPeer.new()
		_connect_eos_peer_diagnostics(eos_peer)

		var err = eos_peer.create_client(SOCKET_NAME, target_puid)
		if err != OK:
			push_error("NetworkManager: Failed to create EOS P2P client to socket '%s' for PUID '%s': %s" % [SOCKET_NAME, target_puid, error_string(err)])
			return err as Error
		peer = eos_peer
		multiplayer.multiplayer_peer = peer
		print("NetworkManager: Connecting via EOS P2P to host PUID: %s..." % target_puid)

	else:
		return ERR_UNCONFIGURED

	return OK


func _connect_eos_peer_diagnostics(eos_peer: EOSGMultiplayerPeer) -> void:
	eos_peer.peer_connection_established.connect(_on_eos_peer_connection_established)
	eos_peer.peer_connection_interrupted.connect(_on_eos_peer_connection_interrupted)
	eos_peer.peer_connection_closed.connect(_on_eos_peer_connection_closed)


func _on_eos_peer_connection_established(data: Dictionary) -> void:
	var remote_user_id: String = str(data.get("remote_user_id", ""))
	var net_type: int = int(data.get("network_type", -1))
	var type_str: String = "UNKNOWN"
	var is_relay: bool = false

	match net_type:
		EOS.P2P.NetworkType.DirectConnection: # 1
			type_str = "DIRECT (STUN)"
			is_relay = false
		EOS.P2P.NetworkType.RelayedConnection: # 2
			type_str = "RELAY (TURN)"
			is_relay = true
		EOS.P2P.NetworkType.NoConnection: # 0
			type_str = "NO CONNECTION"
			is_relay = false
		_:
			type_str = "UNKNOWN (%d)" % net_type
			is_relay = false

	last_p2p_network_type = type_str
	print("NetworkManager: EOS P2P connection established with peer %s via %s" % [remote_user_id, type_str])
	peer_connection_established.emit(data)
	p2p_diagnostic_logged.emit(type_str, is_relay)


func _on_eos_peer_connection_interrupted(data: Dictionary) -> void:
	print("NetworkManager: Connection interrupted with peer %s" % str(data.get("remote_user_id", "")))


func _on_eos_peer_connection_closed(data: Dictionary) -> void:
	print("NetworkManager: Connection closed with peer %s (reason: %s)" % [
		str(data.get("remote_user_id", "")),
		str(data.get("reason", ""))
	])


func _cleanup_peer(clean_session: bool = true) -> void:
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	if clean_session and current_mode == NetworkMode.EOS_P2P:
		SessionManager.destroy_active_session()


func is_online() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func _on_peer_connected(id: int) -> void:
	print("NetworkManager: Peer connected: %d" % id)
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected: %d" % id)
	player_disconnected.emit(id)
	if current_mode == NetworkMode.EOS_P2P:
		_cleanup_peer(true)


func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server as peer %d" % multiplayer.get_unique_id())
	connected_to_server.emit()


func _on_connection_failed() -> void:
	push_error("NetworkManager: Connection to server failed.")
	_cleanup_peer(true)
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected.")
	_cleanup_peer(true)
	server_disconnected.emit()
