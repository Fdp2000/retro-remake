extends Node

enum NetworkMode {
	ENET_LOCAL,
	EOS_P2P
}

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_started()
signal connection_failed()
signal connected_to_server()
signal server_disconnected()

const PORT: int = 8910
const SOCKET_NAME: String = "SpyVsSpySocket"
const MAX_PLAYERS: int = 2
const DEFAULT_ENET_HOST: String = "127.0.0.1"

var current_mode: NetworkMode = NetworkMode.EOS_P2P
var peer: MultiplayerPeer = null


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


func _check_cmdline_args() -> void:
	var args: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--enet" in args:
		current_mode = NetworkMode.ENET_LOCAL
		print("NetworkManager: Selected ENET_LOCAL mode via CLI.")
	elif "--eos" in args:
		current_mode = NetworkMode.EOS_P2P
		print("NetworkManager: Selected EOS_P2P mode via CLI.")

	if "--host" in args:
		print("NetworkManager: Found --host flag in command-line arguments.")
		start_host()
	elif "--join" in args:
		print("NetworkManager: Found --join flag in command-line arguments.")
		start_join()


func start_host() -> Error:
	_cleanup_peer()

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
		var eos_peer := EOSGMultiplayerPeer.new()
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
	_cleanup_peer()

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
		var eos_peer := EOSGMultiplayerPeer.new()
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


func _cleanup_peer() -> void:
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null


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


func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server as peer %d" % multiplayer.get_unique_id())
	connected_to_server.emit()


func _on_connection_failed() -> void:
	push_error("NetworkManager: Connection to server failed.")
	_cleanup_peer()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected.")
	_cleanup_peer()
	server_disconnected.emit()
