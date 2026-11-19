@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

## Dedicated verification suite for B3 (Compact Briefcase) & D7 (Dropped Briefcase Container):
## - Self-aliased RPC sync never clears briefcase_objectives
## - Duplicate objective pickup never destroys world/drawer items
## - Pressing E on floor Briefcase while holding an Objective enters Closed (0%) Focus Mode
## - Drag-depositing Objective into Briefcase frees Left Hand so Tap E carries the Briefcase
## - Both Spring Traps and Time Bombs arm, slow-peek, trigger KO / ignite inside Briefcases
## - Simultaneous Drawer + Carried Briefcase opening, packing/unpacking, and trap triggers


func suite_name() -> String:
	return "briefcase_b3"


func teardown() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _instantiate_live_player(peer_name: String = "1") -> CharacterBody3D:
	var packed: PackedScene = load("res://entities/player/player.tscn")
	var placeholder_root: Node = packed.instantiate()
	var live_root: CharacterBody3D = track(load("res://entities/player/player.gd").new()) as CharacterBody3D
	live_root.name = peer_name
	for child in placeholder_root.get_children():
		placeholder_root.remove_child(child)
		for desc in child.find_children("*", "", true, false):
			if desc.owner == placeholder_root:
				desc.owner = null
		child.owner = null
		live_root.add_child(child)
	placeholder_root.free()

	live_root.collision_shape = live_root.get_node("CollisionShape3D")
	live_root.mesh_instance = live_root.get_node("MeshInstance3D")
	live_root.head = live_root.get_node("Head")
	live_root.camera = live_root.get_node("Head/Camera3D")
	live_root.hud = live_root.get_node("HUD")
	live_root.prompt_label = live_root.get_node("HUD/PromptLabel")
	live_root.left_hand_label = live_root.get_node("HUD/StatusBar/HBox/LeftHandLabel")
	live_root.stance_label = live_root.get_node("HUD/StatusBar/HBox/StanceLabel")
	live_root.right_hand_label = live_root.get_node("HUD/StatusBar/HBox/RightHandLabel")
	return live_root


func _instantiate_drawer() -> StaticBody3D:
	var packed: PackedScene = load("res://entities/props/searchable_drawer.tscn")
	var placeholder: Node = packed.instantiate()
	var live: StaticBody3D = track(load("res://entities/props/searchable_container.gd").new()) as StaticBody3D
	live.name = "BriefcaseTestDrawer"
	for child in placeholder.get_children():
		placeholder.remove_child(child)
		for desc in child.find_children("*", "", true, false):
			if desc.owner == placeholder:
				desc.owner = null
		child.owner = null
		live.add_child(child)
	placeholder.free()
	return live


func _instantiate_floor_briefcase(host_root: Node, initial_items: Array[String] = []) -> StaticBody3D:
	var pickup: StaticBody3D = track(load("res://entities/props/world_item_pickup.gd").new()) as StaticBody3D
	pickup.name = "FloorBriefcaseTest"
	pickup.item_id = "BRIEFCASE"
	pickup.packed_objectives = initial_items.duplicate()
	host_root.add_child(pickup)
	return pickup


func test_sync_aliasing_and_duplicate_objective_protection() -> void:
	var p: CharacterBody3D = _instantiate_live_player("1")
	p.pickup_item("BRIEFCASE", ["KEY", "MONEY"])
	assert_eq(p.briefcase_objectives.size(), 2, "Briefcase starts with KEY and MONEY")

	# Simulate call_local RPC passing the exact same Array reference back into apply_sync_state
	var inv: SpyInventoryComponent = p._inv()
	inv.apply_sync_state("BRIEFCASE", inv.briefcase_objectives, inv.jacket_slots, 0, 0, false, inv.get_briefcase_trap_dict())
	assert_eq(p.briefcase_objectives.size(), 2, "Self-aliased apply_sync_state preserves all briefcase objectives")
	assert_true("KEY" in p.briefcase_objectives and "MONEY" in p.briefcase_objectives, "KEY and MONEY intact after self-aliased sync")

	# Trying to pick up a duplicate KEY must NOT return picked=true (must not delete floor pickup)
	var dup_res: Dictionary = p.pickup_item("KEY")
	assert_false(bool(dup_res["picked"]), "Duplicate KEY rejected instead of deleted")
	assert_eq(p.briefcase_objectives.size(), 2, "Briefcase count unchanged after duplicate attempt")


func test_floor_briefcase_focus_deposit_free_hand_and_carry() -> void:
	MatchManager.start_new_match([1, 2], 7001)
	var host_root: Node = EditorInterface.get_base_control()
	var arena := track(Node3D.new()) as Node3D
	arena.name = "BriefcaseArena1"
	var players_node := Node3D.new()
	players_node.name = "Players"
	arena.add_child(players_node)
	host_root.add_child(arena)

	var p1: CharacterBody3D = _instantiate_live_player("1")
	players_node.add_child(p1)
	p1.pickup_item("KEY")
	assert_eq(p1.left_hand_item_id, "KEY", "Player holds KEY in Left Hand")

	var briefcase_pickup: StaticBody3D = _instantiate_floor_briefcase(arena, ["PASSPORT"])
	var bc_container: Node = briefcase_pickup.get_briefcase_container()
	assert_true(bc_container != null, "Floor Briefcase created its unified BriefcaseContainer")
	assert_true(briefcase_pickup.get_interaction_prompt_for_player(p1).contains("Open"), "Prompt tells player holding KEY that E opens Briefcase to pack")

	# 1. Pressing E on floor Briefcase while holding KEY enters Stage 1 Closed (0%) Focus Mode (does NOT pick up or delete KEY!)
	briefcase_pickup._execute_server_pickup(1)
	assert_eq(p1.left_hand_item_id, "KEY", "KEY was NOT deleted when pressing E on Briefcase")
	assert_eq(int(bc_container.get("occupied_by_peer_id")), 1, "Player 1 focused floor Briefcase container")
	assert_eq(p1.stance_state, GameConfig.Stance.DRAWER_LOCK, "Player entered Top-Down Search Mode on Briefcase")
	assert_true(is_equal_approx(float(bc_container.get("drawer_visual_ratio")), 0.0), "Stage 1 starts with Briefcase lid CLOSED (0%)")

	# 2. Fast-open Briefcase (Tap E) -> lid opens 100%
	var open_res: Dictionary = bc_container.open_container(1, false, p1)
	assert_true(bool(open_res["opened"]), "Briefcase opened cleanly")
	assert_true(is_equal_approx(float(bc_container.get("drawer_visual_ratio")), 1.0), "Briefcase lid fully open (100%)")

	# 3. Drag/Deposit KEY from Left Hand into open Briefcase -> packs KEY and frees Left Hand!
	assert_true(bc_container.deposit_left_hand_item(1, p1), "Deposited KEY from Left Hand into Briefcase")
	assert_eq(p1.left_hand_item_id, "NONE", "Left Hand is now FREE after packing KEY")
	var stored: Array = bc_container.get("stored_items") as Array
	assert_eq(stored.size(), 2, "Briefcase now holds PASSPORT + KEY")
	assert_true("KEY" in stored and "PASSPORT" in stored, "Both KEY and PASSPORT inside Briefcase")

	# 4. Exit Briefcase Search Mode -> lid closes & updates pickup packed_objectives
	bc_container.close_container(1, p1)
	assert_eq(int(bc_container.get("occupied_by_peer_id")), 0, "Briefcase released lock")
	assert_eq(p1.stance_state, GameConfig.Stance.WALK, "Player returned to FPS WALK")
	assert_eq(briefcase_pickup.packed_objectives.size(), 2, "Floor Briefcase pickup synced packed_objectives [2/4]")

	# 5. Now with empty Left Hand, Tap E carries the Briefcase with BOTH Objectives intact!
	briefcase_pickup._execute_server_pickup(1)
	assert_eq(p1.left_hand_item_id, "BRIEFCASE", "Player is now carrying BRIEFCASE")
	assert_eq(p1.briefcase_objectives.size(), 2, "Carried Briefcase has both PASSPORT and KEY (2/4)")
	assert_true("KEY" in p1.briefcase_objectives and "PASSPORT" in p1.briefcase_objectives, "Both objectives preserved when carrying")
	assert_true(is_equal_approx(p1.get_current_move_speed(), 4.5 * 0.90), "Briefcase 0.90x speed multiplier active")


func test_briefcase_spring_and_bomb_traps_arm_and_trigger() -> void:
	MatchManager.start_new_match([1, 2], 7002)
	var host_root: Node = EditorInterface.get_base_control()
	var arena := track(Node3D.new()) as Node3D
	arena.name = "BriefcaseArena2"
	var players_node := Node3D.new()
	players_node.name = "Players"
	arena.add_child(players_node)
	host_root.add_child(arena)

	var p1: CharacterBody3D = _instantiate_live_player("1")
	players_node.add_child(p1)
	p1.pickup_item("SPRING")
	p1.pickup_item("BOMB")

	var briefcase_pickup: StaticBody3D = _instantiate_floor_briefcase(arena, ["MONEY"])
	var bc_container: Node = briefcase_pickup.get_briefcase_container()

	# Plant BOTH Spring Trap AND Time Bomb inside Floor Briefcase
	bc_container.open_container(1, false, p1)
	assert_true(bc_container.plant_trap_from_jacket(1, 0, "LIP", p1), "Planted SPRING from Coat Slot 1 onto Briefcase latch")
	assert_true(bc_container.plant_trap_from_jacket(1, 1, "TRAY", p1), "Planted BOMB from Coat Slot 2 into Briefcase tray")
	assert_eq(p1.jacket_slots[0], "NONE", "Coat Slot 1 cleared")
	assert_eq(p1.jacket_slots[1], "NONE", "Coat Slot 2 cleared")
	bc_container.close_container(1, p1)

	assert_true(bool(bc_container.get("armed_spring")), "Spring armed on Briefcase close")
	assert_true(bool(bc_container.get("armed_bomb")), "Bomb armed on Briefcase close")
	assert_true(briefcase_pickup.armed_spring, "Floor pickup synced armed_spring=true")
	assert_true(briefcase_pickup.armed_bomb, "Floor pickup synced armed_bomb=true")

	# Fast-open Briefcase triggers Spring KO!
	var fast_res: Dictionary = bc_container.open_container(1, false, p1)
	assert_false(bool(fast_res["opened"]), "Fast-open on Spring-rigged Briefcase blocked by KO")
	assert_true(bool(fast_res["triggered_spring"]), "Briefcase Spring triggered KO")
	assert_eq(p1.stance_state, GameConfig.Stance.KO, "Victim entered 15s KO from Briefcase Spring")

	# Wake up & expire immunity
	p1.tick_ko_and_immunity(15.1)
	p1.tick_ko_and_immunity(2.1)

	# Re-arm Spring on Briefcase & verify Slow Peek safely bypasses Spring AND ignites Bomb
	bc_container.set("armed_spring", true)
	bc_container.set("spring_owner_peer_id", 2)
	var slow_res: Dictionary = bc_container.open_container(1, true, p1)
	assert_true(bool(slow_res["opened"]), "Slow Peek opened Spring+Bomb Briefcase without Spring KO")
	assert_true(bool(slow_res["lit_bomb"]), "Briefcase Time Bomb fuse ignited on Slow Peek")
	assert_true(bc_container.unlatch_spring(1), "Unlatched Briefcase Spring during Slow Peek")
	assert_true(bc_container.steal_unlatched_spring_to_jacket(1, 0, p1), "Stole Briefcase Spring into Coat Slot 1")
	assert_eq(p1.jacket_slots[0], "SPRING", "Stolen Spring in Coat Slot 1")
	assert_true(bc_container.grab_lit_bomb(1, p1), "Grabbed lit Briefcase Bomb into active FPS hand")
	assert_eq(p1.right_hand_item_id, "LIVE_BOMB", "Active hand holds LIVE_BOMB")


func test_simultaneous_drawer_and_carried_briefcase_opening() -> void:
	MatchManager.start_new_match([1, 2], 7003)
	var p1: CharacterBody3D = _instantiate_live_player("1")
	p1.pickup_item("BRIEFCASE", ["KEY"])
	p1.pickup_item("SPRING")
	p1.pickup_item("BOMB")

	var drawer: StaticBody3D = _instantiate_drawer()
	drawer.set("stored_items", ["MONEY"] as Array[String])

	# 1. Open Drawer while holding Briefcase -> loot MONEY directly into Briefcase, and stash KEY back into Drawer
	assert_true(bool(drawer.open_container(1, false, p1)["opened"]), "Opened Drawer while holding Briefcase")
	assert_true(drawer.loot_item_to_player(1, "MONEY", -1, p1), "Dragged MONEY from Drawer into carried Briefcase")
	assert_true("MONEY" in p1.briefcase_objectives and "KEY" in p1.briefcase_objectives, "Carried Briefcase now holds KEY + MONEY")
	assert_true(drawer.deposit_briefcase_item(1, "KEY", p1), "Dragged KEY from carried Briefcase into Drawer")
	assert_false("KEY" in p1.briefcase_objectives, "KEY removed from carried Briefcase")
	assert_true("KEY" in (drawer.get("stored_items") as Array), "KEY stashed inside Drawer")

	# 2. Plant Spring & Bomb from Coat into carried Briefcase while Drawer is open -> close arms both!
	p1._rpc_server_briefcase_trap_action("PLANT_SPRING", 0)
	p1._rpc_server_briefcase_trap_action("PLANT_BOMB", 1)
	drawer.close_container(1, p1)
	assert_true(p1.has_held_briefcase_armed_spring(), "Carried Briefcase armed Spring on simultaneous Drawer close")
	assert_true(p1.has_held_briefcase_armed_bomb(), "Carried Briefcase armed Bomb on simultaneous Drawer close")

	# 3. Fast-opening a Drawer while carrying a Spring-rigged Briefcase triggers simultaneous Briefcase Spring KO!
	var ko_open: Dictionary = drawer.open_container(1, false, p1)
	assert_false(bool(ko_open["opened"]), "Simultaneous fast-open triggered carried Briefcase Spring KO")
	assert_true(bool(ko_open["triggered_spring"]), "Carried Briefcase Spring flagged triggered_spring")
	assert_eq(p1.stance_state, GameConfig.Stance.KO, "Player KO'd by carried Briefcase Spring when fast-opening Drawer")


func test_top_down_ui_three_zone_layout_and_carried_briefcase_lid() -> void:
	var host_root: Node = EditorInterface.get_base_control()
	var ui: TopDownContainerUI = track(load("res://ui/top_down_container_ui.gd").new()) as TopDownContainerUI
	host_root.add_child(ui)

	var p1: CharacterBody3D = _instantiate_live_player("1")
	p1.pickup_item("BRIEFCASE", ["KEY"])
	p1.pickup_item("SPRING")

	var drawer: StaticBody3D = _instantiate_drawer()
	drawer.set("drawer_visual_ratio", 0.0)
	ui.open_for_container(p1, drawer, 1)
	assert_true(ui.visible, "TopDownContainerUI opens cleanly")
	assert_true(ui._left_panel != null and ui._right_panel != null, "Both Left Hand/Briefcase and Right 3-Slot Coat panels exist")
	assert_true(ui._briefcase_lid_cover.visible, "Carried Briefcase lid cover is CLOSED (visible) when drawer is at 0%")
	assert_true(is_equal_approx(ui._briefcase_lid_cover.anchor_bottom, 1.0), "Carried Briefcase lid fully covers interior at 0%")

	# Open Drawer -> Carried Briefcase lid retracts simultaneously
	drawer.set("drawer_visual_ratio", 0.50)
	ui.refresh_view()
	assert_true(is_equal_approx(ui._briefcase_lid_cover.anchor_bottom, 0.50), "Carried Briefcase lid opens simultaneously to 50%")

	drawer.set("drawer_visual_ratio", 1.0)
	ui.refresh_view()
	assert_false(ui._briefcase_lid_cover.visible, "Carried Briefcase lid fully open at 100%")
	ui.close_view()
	assert_false(ui.visible, "TopDownContainerUI closes cleanly")
