extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")

const SPAWN_POINTS: Dictionary = {
	1: Vector3(-3.0, 1.0, 0.0),
	2: Vector3(3.0, 1.0, 0.0)
}

@onready var players_container: Node3D = $Players
@onready var ui_layer: CanvasLayer = $UI
@onready var host_button: Button = $UI/Panel/VBoxContainer/HostButton
@onready var join_button: Button = $UI/Panel/VBoxContainer/JoinButton
@onready var status_label: Label = $UI/Panel/VBoxContainer/StatusLabel

func _ready() -> void:
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_started.connect(_on_network_active)
	NetworkManager.connected_to_server.connect(_on_network_active)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	players_container.child_entered_tree.connect(func(node: Node):
		print("TestGym [%s]: Child entered Players: %s (auth: %d, is_auth: %s)" % [
			"Server" if multiplayer.is_server() else "Client",
			node.name,
			node.get_multiplayer_authority(),
			node.is_multiplayer_authority()
		])
	)

	if NetworkManager.is_online():
		_on_network_active()
		if NetworkManager.is_host():
			if not players_container.has_node(str(multiplayer.get_unique_id())):
				_spawn_player(multiplayer.get_unique_id())

func _unhandled_input(event: InputEvent) -> void:
	if ui_layer.visible and not NetworkManager.is_online():
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_H:
				_on_host_pressed()
			elif event.keycode == KEY_J:
				_on_join_pressed()

func _on_host_pressed() -> void:
	var err: Error = NetworkManager.start_host()
	if err == OK:
		_on_network_active()
	else:
		status_label.text = "Failed to start host: %s" % error_string(err)

func _on_join_pressed() -> void:
	var err: Error = NetworkManager.start_join()
	if err == OK:
		status_label.text = "Connecting to 127.0.0.1:8910..."
	else:
		status_label.text = "Failed to connect: %s" % error_string(err)

func _on_network_active() -> void:
	ui_layer.visible = false

func _on_connection_failed() -> void:
	ui_layer.visible = true
	status_label.text = "Connection failed."

func _on_player_connected(peer_id: int) -> void:
	# Only the server instantiates players in the multiplayer tree
	if not NetworkManager.is_host():
		return
	_spawn_player(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	if not NetworkManager.is_host():
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
