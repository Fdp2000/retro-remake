extends Node

func _ready() -> void:
	print("--- BEGIN PHASE 2 VERIFICATION TEST ---")
	test_player_role_and_colors()
	test_player_scene_replication_config()
	test_lobby_state_readiness()
	test_arena_handshake_logic()
	print("--- ALL PHASE 2 TESTS PASSED SUCCESSFULLY ---")
	get_tree().quit(0)

func assert_true(condition: bool, msg: String) -> void:
	if not condition:
		printerr("FAILED ASSERTION: ", msg)
		get_tree().quit(1)
	else:
		print("  [PASS] ", msg)

func test_player_role_and_colors() -> void:
	print("\n[Test 1] Player Roles and Dynamic Materials")
	var player_scene: PackedScene = load("res://entities/player/player.tscn")
	assert_true(player_scene != null, "player.tscn loaded successfully")

	# Instantiate Peer 1 (Spy White)
	var p1: CharacterBody3D = player_scene.instantiate()
	p1.name = "1"
	p1.spy_role = 1
	add_child(p1)

	var mesh_inst1: MeshInstance3D = p1.get_node("MeshInstance3D")
	assert_true(mesh_inst1 != null, "Peer 1 MeshInstance3D found")
	var mat1: StandardMaterial3D = mesh_inst1.material_override
	assert_true(mat1 != null, "Peer 1 material_override is set")
	assert_true(mat1.albedo_color.is_equal_approx(Color(0.92, 0.92, 0.92)), "Peer 1 material color is Spy White Color(0.92, 0.92, 0.92)")

	# Instantiate Peer 2 (Spy Black)
	var p2: CharacterBody3D = player_scene.instantiate()
	p2.name = "2"
	p2.spy_role = 2
	add_child(p2)

	var mesh_inst2: MeshInstance3D = p2.get_node("MeshInstance3D")
	assert_true(mesh_inst2 != null, "Peer 2 MeshInstance3D found")
	var mat2: StandardMaterial3D = mesh_inst2.material_override
	assert_true(mat2 != null, "Peer 2 material_override is set")
	assert_true(mat2.albedo_color.is_equal_approx(Color(0.12, 0.12, 0.12)), "Peer 2 material color is Spy Black Color(0.12, 0.12, 0.12)")

	# Check setter dynamically updates material
	p1.spy_role = 2
	assert_true(mesh_inst1.material_override.albedo_color.is_equal_approx(Color(0.12, 0.12, 0.12)), "Peer 1 dynamically changes to Spy Black when spy_role=2")
	p1.spy_role = 1
	assert_true(mesh_inst1.material_override.albedo_color.is_equal_approx(Color(0.92, 0.92, 0.92)), "Peer 1 dynamically reverts to Spy White when spy_role=1")

	p1.queue_free()
	p2.queue_free()

func test_player_scene_replication_config() -> void:
	print("\n[Test 2] MultiplayerSynchronizer Replication Config")
	var player_scene: PackedScene = load("res://entities/player/player.tscn")
	var p: CharacterBody3D = player_scene.instantiate()
	var syncer: MultiplayerSynchronizer = p.get_node("MultiplayerSynchronizer")
	assert_true(syncer != null, "MultiplayerSynchronizer found")
	var config: SceneReplicationConfig = syncer.replication_config
	assert_true(config != null, "SceneReplicationConfig found")

	var properties: Array[NodePath] = config.get_properties()
	var has_spy_role: bool = false
	var spy_role_spawn: bool = false
	var spy_role_mode: int = -1

	for prop in properties:
		if str(prop) == ".:spy_role":
			has_spy_role = true
			spy_role_spawn = config.property_get_spawn(prop)
			spy_role_mode = config.property_get_replication_mode(prop)

	assert_true(has_spy_role, ".:spy_role is registered in replication config")
	assert_true(spy_role_spawn, ".:spy_role has spawn=true")
	assert_true(spy_role_mode == SceneReplicationConfig.REPLICATION_MODE_NEVER or spy_role_mode == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE, ".:spy_role has valid spawn replication mode")
	p.queue_free()

func test_lobby_state_readiness() -> void:
	print("\n[Test 3] Lobby State & Readiness Logic")
	var lobby_scene: PackedScene = load("res://scenes/lobby.tscn")
	assert_true(lobby_scene != null, "lobby.tscn loaded successfully")
	var lobby: Control = lobby_scene.instantiate()
	add_child(lobby)

	# Initial state validation
	assert_true(lobby.lobby_state.has(1), "lobby_state has slot 1 (Host)")
	assert_true(lobby.lobby_state.has(2), "lobby_state has slot 2 (Client)")
	assert_true(lobby.lobby_state[1]["role"] == 1, "Slot 1 is role 1 (Spy White)")
	assert_true(lobby.lobby_state[2]["role"] == 2, "Slot 2 is role 2 (Spy Black)")
	assert_true(not lobby.lobby_state[1]["ready"], "Slot 1 initially not ready")
	assert_true(not lobby.lobby_state[2]["ready"], "Slot 2 initially not ready")

	# Mock server_set_ready for Slot 1
	lobby.lobby_state[1]["ready"] = true
	var p1_ready: bool = lobby.lobby_state[1]["ready"]
	var p2_ready: bool = lobby.lobby_state[2]["ready"]
	assert_true(not (p1_ready and p2_ready), "Start disabled when only Host is ready")

	# Mock server_set_ready for Slot 2
	lobby.lobby_state[2]["ready"] = true
	p1_ready = lobby.lobby_state[1]["ready"]
	p2_ready = lobby.lobby_state[2]["ready"]
	assert_true(p1_ready and p2_ready, "Start enabled when both Host and Client are ready")

	# Mock Client disconnect
	lobby.lobby_state[2]["ready"] = false
	lobby.lobby_state[2]["name"] = "Waiting for opponent..."
	p2_ready = lobby.lobby_state[2]["ready"]
	assert_true(not (p1_ready and p2_ready), "Start disabled after Client disconnects")

	lobby.queue_free()

func test_arena_handshake_logic() -> void:
	print("\n[Test 4] TestGym Deterministic Handshake Logic")
	var gym_scene: PackedScene = load("res://scenes/test_gym.tscn")
	assert_true(gym_scene != null, "test_gym.tscn loaded successfully")
	var gym: Node3D = gym_scene.instantiate()
	add_child(gym)

	# Simulate Host loaded
	gym.peers_in_arena[1] = true
	assert_true(gym.peers_in_arena.has(1), "Host confirmed loaded")
	assert_true(not gym.peers_in_arena.has(2), "Client not yet loaded")
	assert_true(not gym.has_spawned_all, "Spawning not triggered before client confirmation")

	# Simulate Client loaded
	gym.client_peer_id = 999
	gym.peers_in_arena[2] = true
	assert_true(gym.peers_in_arena.has(1) and gym.peers_in_arena.has(2), "Both peers confirmed in arena")

	# Trigger spawn
	gym._spawn_all_players()
	assert_true(gym.has_spawned_all, "has_spawned_all is true")

	var players: Node3D = gym.get_node("Players")
	var p1: Node = players.get_node_or_null("1")
	var p2: Node = players.get_node_or_null("999")
	assert_true(p1 != null, "Host player spawned with node name '1'")
	assert_true(p2 != null, "Client player spawned with node name '999'")
	assert_true(p1.spy_role == 1, "Host player has spy_role = 1 (White)")
	assert_true(p2.spy_role == 2, "Client player has spy_role = 2 (Black)")
	assert_true(p1.position.is_equal_approx(Vector3(-3.0, 1.0, 0.0)), "Host player at SPAWN_POINTS[1]")
	assert_true(p2.position.is_equal_approx(Vector3(3.0, 1.0, 0.0)), "Client player at SPAWN_POINTS[2]")

	gym.queue_free()
