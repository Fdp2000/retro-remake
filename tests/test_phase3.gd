@tool
extends "res://addons/godot_ai/testing/test_suite.gd"


func suite_name() -> String:
	return "phase3_doors_containers_and_exit"


func teardown() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if MatchManager != null:
		MatchManager.match_state = MatchManager.MatchState.INACTIVE
	if AudioBridge != null:
		AudioBridge.clear_recent_cues()


func _instantiate_live_player(peer_name: String = "1") -> CharacterBody3D:
	var packed: PackedScene = load("res://entities/player/player.tscn")
	var placeholder_root: Node = packed.instantiate()
	var live_player: CharacterBody3D = track(load("res://entities/player/player.gd").new()) as CharacterBody3D
	live_player.name = peer_name
	for child in placeholder_root.get_children():
		placeholder_root.remove_child(child)
		for desc in child.find_children("*", "", true, false):
			if desc.owner == placeholder_root:
				desc.owner = null
		child.owner = null
		live_player.add_child(child)
	placeholder_root.free()
	live_player.inventory = live_player.get_node_or_null("Inventory") as SpyInventoryComponent
	live_player.collision_shape = live_player.get_node("CollisionShape3D")
	live_player.mesh_instance = live_player.get_node("MeshInstance3D")
	live_player.head = live_player.get_node("Head")
	live_player.camera = live_player.get_node("Head/Camera3D")
	live_player.raycast = live_player.get_node("Head/Camera3D/RayCast3D")
	return live_player


func _instantiate_container() -> StaticBody3D:
	var packed: PackedScene = load("res://entities/props/searchable_drawer.tscn")
	var placeholder_root: Node = packed.instantiate()
	var container: StaticBody3D = track(load("res://entities/props/searchable_container.gd").new()) as StaticBody3D
	container.name = "TestDrawer"
	for child in placeholder_root.get_children():
		placeholder_root.remove_child(child)
		for desc in child.find_children("*", "", true, false):
			if desc.owner == placeholder_root:
				desc.owner = null
		child.owner = null
		container.add_child(child)
	placeholder_root.free()
	return container


func test_bidirectional_embassy_door_modes_and_audio() -> void:
	var door: Node3D = track(load("res://entities/props/embassy_door.gd").new()) as Node3D
	door._ensure_nodes()

	# 1. Opposite side approaches produce opposite swing directions (+90 vs -90 deg)
	var angle_from_front: float = door.compute_away_angle_rad(Vector3(0.0, 0.0, -2.0))
	var angle_from_back: float = door.compute_away_angle_rad(Vector3(0.0, 0.0, 2.0))
	assert_true(is_equal_approx(angle_from_front, deg_to_rad(-90.0)), "Approaching from -Z swings -90 deg (into +Z)")
	assert_true(is_equal_approx(angle_from_back, deg_to_rad(90.0)), "Approaching from +Z swings +90 deg (into -Z)")

	# 2. Tap E (FAST_TOGGLE) opens door and emits door_open (8.0m)
	AudioBridge.clear_recent_cues()
	door._execute_door_action(1, "FAST_TOGGLE", Vector3(0.0, 0.0, 2.0))
	assert_true(door.is_open, "Door opened via FAST_TOGGLE")
	var cues: Array[Dictionary] = AudioBridge.get_recent_cues()
	assert_eq(cues.size(), 1, "FAST_TOGGLE emits 1 audio cue")
	assert_eq(cues[0]["cue_id"], "door_open", "Emitted door_open cue")
	assert_true(is_equal_approx(float(cues[0]["radius"]), 8.0), "door_open radius is 8.0m")

	# Close silently via SLOW_PEEK
	AudioBridge.clear_recent_cues()
	door._execute_door_action(1, "SLOW_PEEK", Vector3(0.0, 0.0, 2.0))
	assert_false(door.is_open, "Door closed")
	assert_eq(AudioBridge.get_recent_cues().size(), 0, "SLOW_PEEK close emits 0 audio cues")

	# 3. Hold E (SLOW_PEEK) opens door silently (0 audio cues)
	AudioBridge.clear_recent_cues()
	door._execute_door_action(1, "SLOW_PEEK", Vector3(0.0, 0.0, -2.0))
	assert_true(door.is_open, "Door opened via SLOW_PEEK")
	assert_eq(AudioBridge.get_recent_cues().size(), 0, "SLOW_PEEK open is silent (0 cues)")

	# Close again so Sprint Bash can trigger
	door._execute_door_action(1, "FAST_TOGGLE", Vector3(0.0, 0.0, -2.0))
	assert_false(door.is_open, "Door closed before bash test")

	# 4. Sprint Auto-Bash opens closed door and emits door_bash (14.0m)
	AudioBridge.clear_recent_cues()
	door.request_sprint_bash(1, Vector3(0.0, 0.0, 1.5))
	assert_true(door.is_open, "Door bashed open by sprint")
	cues = AudioBridge.get_recent_cues()
	assert_eq(cues.size(), 1, "Sprint bash emits 1 audio cue")
	assert_eq(cues[0]["cue_id"], "door_bash", "Emitted door_bash cue")
	assert_true(is_equal_approx(float(cues[0]["radius"]), 14.0), "door_bash radius is 14.0m")


func test_drawer_first_search_clock_bonus_and_single_user_lock() -> void:
	MatchManager.start_new_match([1, 2], 777)
	var p1: CharacterBody3D = _instantiate_live_player("1")
	var p2: CharacterBody3D = _instantiate_live_player("2")
	var drawer: StaticBody3D = _instantiate_container()
	drawer.set("stored_items", ["KEY"] as Array[String])

	# Peer 1 opens drawer -> +10s bonus (190.0s) and single-user lock
	var open1: Dictionary = drawer.open_container(1, false, p1)
	assert_true(bool(open1["opened"]), "Peer 1 opened drawer")
	assert_true(bool(open1["awarded_bonus"]), "Peer 1 received first-search bonus")
	assert_true(is_equal_approx(MatchManager.get_private_clock(1), 190.0), "Peer 1 clock increased to 190.0s")
	assert_eq(drawer.occupied_by_peer_id, 1, "Drawer locked by Peer 1")
	assert_eq(p1.stance_state, GameConfig.Stance.DRAWER_LOCK, "Peer 1 entered DRAWER_LOCK")

	# Drag clutter persists
	assert_true(drawer.move_clutter(1, 0, Vector2(0.85, 0.20)), "Peer 1 dragged clutter folder")
	assert_true(drawer.clutter_positions[0].is_equal_approx(Vector2(0.85, 0.20)), "Moved clutter position persisted")

	# Peer 2 rejected while Peer 1 is inside
	var open2_blocked: Dictionary = drawer.open_container(2, false, p2)
	assert_false(bool(open2_blocked["opened"]), "Peer 2 blocked while Peer 1 occupies drawer")
	assert_eq(str(open2_blocked["reason"]), "IN_USE", "Rejection reason is IN_USE")

	# Peer 1 closes drawer -> lock released and stance restored
	drawer.close_container(1, p1)
	assert_eq(drawer.occupied_by_peer_id, 0, "Drawer lock cleared on close")
	assert_eq(p1.stance_state, GameConfig.Stance.WALK, "Peer 1 exited DRAWER_LOCK to WALK")

	# Peer 1 re-opens same drawer -> 0s bonus
	var reopen1: Dictionary = drawer.open_container(1, true, p1)
	assert_true(bool(reopen1["opened"]), "Peer 1 reopened drawer")
	assert_false(bool(reopen1["awarded_bonus"]), "Peer 1 does not get second +10s bonus")
	assert_true(is_equal_approx(MatchManager.get_private_clock(1), 190.0), "Peer 1 clock still 190.0s")
	drawer.close_container(1, p1)

	# Peer 2 opens same drawer for first time -> receives +10s bonus independently
	var open2: Dictionary = drawer.open_container(2, false, p2)
	assert_true(bool(open2["opened"]), "Peer 2 opened drawer after release")
	assert_true(bool(open2["awarded_bonus"]), "Peer 2 awarded own +10s bonus")
	assert_true(is_equal_approx(MatchManager.get_private_clock(2), 190.0), "Peer 2 clock increased to 190.0s")
	drawer.close_container(2, p2)


func test_drawer_spring_trap_asymmetric_gamble_unlatch_and_steal() -> void:
	MatchManager.start_new_match([1, 2], 888)
	var p1: CharacterBody3D = _instantiate_live_player("1")
	p1.pickup_item("KEY")
	p1.pickup_item("BUCKET")

	var drawer: StaticBody3D = _instantiate_container()
	drawer.set("armed_spring", true)
	drawer.set("spring_owner_peer_id", 2)

	# 1. Fast Slam (Tap E) triggers armed Spring -> KO + full scatter, does not enter Top-Down View
	var slam_res: Dictionary = drawer.open_container(1, false, p1)
	assert_false(bool(slam_res["opened"]), "Fast slam on armed Spring does not open Top-Down View")
	assert_true(bool(slam_res["triggered_spring"]), "Fast slam triggered armed Spring")
	assert_eq(p1.stance_state, GameConfig.Stance.KO, "Victim entered KO stance")
	assert_eq(p1.left_hand_item_id, "NONE", "KO scattered Left Hand KEY")
	assert_eq(p1.jacket_slots[0], "NONE", "KO scattered Inner Jacket BUCKET")
	assert_false(drawer.armed_spring, "Spring consumed after trigger")

	# 2. Re-arm Spring & test Slow Peek (Hold E) -> Safe bypass -> Unlatch -> Steal to Jacket -> Re-plant
	p1.stance_state = GameConfig.Stance.WALK
	drawer.set("armed_spring", true)
	drawer.set("spring_owner_peer_id", 2)

	var peek_res: Dictionary = drawer.open_container(1, true, p1)
	assert_true(bool(peek_res["opened"]), "Slow Peek safely opened drawer without triggering Spring")
	assert_false(bool(peek_res["triggered_spring"]), "Spring did not trigger on Slow Peek")
	assert_true(drawer.unlatch_spring(1), "Clicked Spring to unlatch")
	assert_true(drawer.spring_unlatched, "Spring is now unlatched")
	assert_false(drawer.armed_spring, "Spring is no longer armed")

	assert_true(drawer.steal_unlatched_spring_to_jacket(1, -1, p1), "Stole unlatched Spring into Inner Jacket")
	assert_eq(p1.jacket_slots[0], "SPRING", "SPRING stowed into Jacket Slot 1")
	assert_false(drawer.spring_unlatched, "Drawer spring_unlatched cleared after steal")

	assert_true(drawer.plant_trap_from_jacket(1, 0, "LIP", p1), "Planted SPRING from Coat Slot 1 onto Drawer Lip")
	assert_eq(p1.jacket_slots[0], "NONE", "Coat Slot 1 emptied after planting")
	assert_true(drawer.staged_spring_on_lip, "Spring staged on lip while drawer open")
	drawer.close_container(1, p1)
	assert_true(drawer.armed_spring, "Spring arms automatically on drawer close")


func test_drawer_time_bomb_ignition_and_hot_potato_grab() -> void:
	MatchManager.start_new_match([1, 2], 999)
	var p1: CharacterBody3D = _instantiate_live_player("1")
	p1.pickup_item("BOMB")
	p1.pickup_item("TRIPWIRE")
	assert_eq(p1.jacket_slots[0], "BOMB", "Slot 1 holds unlit BOMB")
	assert_eq(p1.jacket_slots[1], "TRIPWIRE", "Slot 2 holds TRIPWIRE")

	var drawer: StaticBody3D = _instantiate_container()
	assert_true(bool(drawer.open_container(1, false, p1)["opened"]), "Opened clean drawer")
	assert_true(drawer.plant_trap_from_jacket(1, 0, "TRAY", p1), "Planted BOMB from Slot 1 into tray")
	assert_eq(p1.jacket_slots[0], "NONE", "Slot 1 cleared after planting bomb")
	drawer.close_container(1, p1)
	assert_true(drawer.armed_bomb, "Time Bomb armed upon closing drawer")

	# Any open ignites fuse (2.5s - 4.0s)
	var open_bomb: Dictionary = drawer.open_container(1, false, p1)
	assert_true(bool(open_bomb["opened"]), "Opened rigged drawer")
	assert_true(bool(open_bomb["lit_bomb"]), "Time Bomb fuse ignited on open")
	assert_true(drawer.live_bomb_lit, "live_bomb_lit is true")
	assert_gt(drawer.live_bomb_fuse_remaining, 2.0, "Fuse remaining within expected range")

	# Left-Click lit Bomb -> auto-closes container, snaps to WALK, equips LIVE_BOMB in active hand, keeps TRIPWIRE in coat!
	assert_true(drawer.grab_lit_bomb(1, p1), "Grabbed lit Time Bomb")
	assert_false(drawer.live_bomb_lit, "Container live_bomb_lit cleared")
	assert_eq(drawer.occupied_by_peer_id, 0, "Container auto-closed")
	assert_eq(p1.stance_state, GameConfig.Stance.WALK, "Player snapped out of DRAWER_LOCK back to FPS WALK")
	assert_eq(p1.right_hand_item_id, "LIVE_BOMB", "Active hand holds LIVE_BOMB")
	assert_eq(p1.jacket_slots[1], "TRIPWIRE", "Coat Slot 2 TRIPWIRE stayed safely tucked")


func test_airport_exit_door_victory_validation() -> void:
	MatchManager.start_new_match([1, 2], 555)
	var p1: CharacterBody3D = _instantiate_live_player("1")
	var exit_door: StaticBody3D = track(load("res://entities/props/airport_exit_door.gd").new()) as StaticBody3D
	exit_door._ensure_nodes()

	# 3/4 Objectives -> rejected
	p1.pickup_item("BRIEFCASE", ["KEY", "MONEY", "PASSPORT"])
	assert_false(exit_door.try_trigger_exit_victory(p1), "Airport Exit rejects Briefcase with 3/4 Objectives")
	assert_eq(MatchManager.match_state, MatchManager.MatchState.IN_PROGRESS, "Match remains IN_PROGRESS")

	# Pack 4th Objective -> instant victory
	p1.pickup_item("PLANS")
	assert_eq(p1.briefcase_objectives.size(), 4, "Briefcase holds 4/4 Objectives")
	assert_true(exit_door.try_trigger_exit_victory(p1), "Airport Exit accepts 4/4 Briefcase")
	assert_eq(MatchManager.match_state, MatchManager.MatchState.ENDED, "Match transitioned to ENDED")
	assert_eq(MatchManager.winner_peer_id, 1, "Peer 1 declared winner")
