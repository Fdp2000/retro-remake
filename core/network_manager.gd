extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_started()
signal connection_failed()
signal connected_to_server()
signal server_disconnected()

const DEFAULT_PORT: int = 8910
const MAX_PLAYERS: int = 2
const DEFAULT_HOST: String = "127.0.0.1"

var peer: ENetMultiplayerPeer = null

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
	if "--host" in args:
		print("NetworkManager: Found --host flag in command-line arguments.")
		start_host()
	elif "--join" in args:
		print("NetworkManager: Found --join flag in command-line arguments.")
		start_join()

func start_host(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: Failed to create server on port %d: %s" % [port, error_string(err)])
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	print("NetworkManager: Server started on port %d" % port)
	server_started.emit()
	# The host is Peer 1; notify local game systems that Peer 1 has connected.
	player_connected.emit(1)
	return OK

func start_join(address: String = DEFAULT_HOST, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		push_error("NetworkManager: Failed to create client to %s:%d: %s" % [address, port, error_string(err)])
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	print("NetworkManager: Connecting to %s:%d..." % [address, port])
	return OK

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
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected.")
	peer = null
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()
