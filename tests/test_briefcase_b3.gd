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

	# Packing a duplicate KEY into held Briefcase must fail without touching briefcase contents
	assert_false(p.server_pack_objective_into_briefcase("KEY"), "Duplicate KEY rejected inside Briefcase packing")
	assert_eq(p.briefcase_objectives.size(), 2, "Briefcase count unchanged after duplicate pack attempt")

	# Floor pickup of KEY while holding BRIEFCASE drops BRIEFCASE intact (preserving KEY & MONEY) & equips KEY
	var drop_res: Dictionary = p.pickup_item("KEY")
	assert_true(bool(drop_res["picked"]), "Floor KEY picked up while carrying Briefcase")
	assert_eq(str(drop_res["dropped_item_id"]), "BRIEFCASE", "Briefcase auto-dropped when picking up floor KEY")
	assert_eq((drop_res["dropped_briefcase_items"] as Array).size(), 2, "Auto-dropped Briefcase preserved KEY & MONEY")
	assert_eq(p.left_hand_item_id, "KEY", "Left Hand now holds KEY")

	# Picking up a duplicate KEY while already holding KEY in Left Hand returns picked=false
	var self_dup: Dictionary = p.pickup_item("KEY")
	assert_false(bool(self_dup["picked"]), "Duplicate KEY rejected while already holding KEY in Left Hand")


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
	assert_true(ui._briefcase_felt_canvas != null and is_instance_valid(ui._briefcase_felt_canvas), "Left Open Carried Briefcase uses freeform felt canvas (no 2x2 GridContainer)")
	assert_eq(ui._left_content_box.find_children("*", "GridContainer", true, false).size(), 0, "Zero GridContainer slots in Left Carried Briefcase UI")

	# Freeform rearrangement inside carried Briefcase via request_move_briefcase_item
	p1.request_move_briefcase_item("KEY", Vector2(0.77, 0.28))
	assert_true(p1.briefcase_item_positions["KEY"].is_equal_approx(Vector2(0.77, 0.28)), "request_move_briefcase_item persisted exact normalized position")
	ui.close_view()
	assert_false(ui.visible, "TopDownContainerUI closes cleanly")


func test_floor_objective_auto_drops_briefcase_and_swaps_objectives() -> void:
	MatchManager.start_new_match([1, 2], 7005)
	var host_root: Node = EditorInterface.get_base_control()
	var arena := track(Node3D.new()) as Node3D
	arena.name = "BriefcaseArenaAutoSwap"
	var players_node := Node3D.new()
	players_node.name = "Players"
	arena.add_child(players_node)
	host_root.add_child(arena)

	var p1: CharacterBody3D = _instantiate_live_player("1")
	players_node.add_child(p1)
	p1.pickup_item("BRIEFCASE", ["KEY"], {"KEY": Vector2(0.82, 0.24)})
	p1.set_briefcase_trap_state(true, 2, true, 2, Vector2(0.30, 0.72))

	var money_pickup: StaticBody3D = track(load("res://entities/props/world_item_pickup.gd").new()) as StaticBody3D
	money_pickup.name = "FloorMoneyPickup"
	money_pickup.item_id = "MONEY"
	arena.add_child(money_pickup)

	var prompt: String = money_pickup.get_interaction_prompt_for_player(p1)
	assert_true(prompt.contains("Drops Briefcase"), "Floor Objective prompt informs player that E drops Briefcase")

	# Pressing E on floor MONEY while carrying BRIEFCASE auto-drops BRIEFCASE & equips MONEY in Left Hand
	money_pickup._execute_server_pickup(1)
	assert_true(money_pickup._is_consumed, "Floor MONEY pickup consumed on auto-drop pickup")
	assert_eq(p1.left_hand_item_id, "MONEY", "Player Left Hand now holds MONEY")
	var dropped_bc: StaticBody3D = arena.get_node_or_null("Dropped_1_BRIEFCASE_1") as StaticBody3D
	assert_true(dropped_bc != null, "Auto-dropped Briefcase spawned in arena")
	if dropped_bc != null:
		assert_true("KEY" in dropped_bc.packed_objectives, "Auto-dropped Briefcase preserved packed KEY")
		assert_true((dropped_bc.packed_item_positions["KEY"] as Vector2).is_equal_approx(Vector2(0.82, 0.24)), "Auto-dropped Briefcase preserved custom item XY")
		assert_true(dropped_bc.bomb_norm_pos.is_equal_approx(Vector2(0.30, 0.72)), "Auto-dropped Briefcase preserved custom bomb XY")
		assert_true(dropped_bc.armed_spring and dropped_bc.armed_bomb, "Auto-dropped Briefcase preserved armed traps")

	# Pressing E via player raycast interact dispatch on floor PASSPORT while holding MONEY swaps them and drops MONEY
	var passport_pickup: StaticBody3D = track(load("res://entities/props/world_item_pickup.gd").new()) as StaticBody3D
	passport_pickup.name = "FloorPassportPickup"
	passport_pickup.item_id = "PASSPORT"
	arena.add_child(passport_pickup)
	assert_true(passport_pickup.get_interaction_prompt_for_player(p1).contains("Swap"), "Prompt indicates swapping Left Hand Objectives")
	assert_true(p1._try_trigger_interact_target(passport_pickup, false, 1), "Client E interact dispatch triggers Objective-to-Objective pickup")
	p1._reset_interact_hold()
	assert_true(passport_pickup._is_consumed, "Floor PASSPORT consumed on E swap")
	assert_eq(p1.left_hand_item_id, "PASSPORT", "Player Left Hand swapped to PASSPORT")
	var dropped_money: StaticBody3D = arena.get_node_or_null("Dropped_1_MONEY_2") as StaticBody3D
	assert_true(dropped_money != null and dropped_money.item_id == "MONEY", "Previous MONEY dropped cleanly onto floor")

	# Pressing E on a floor Gadget while holding a loose Objective STILL picks up the Gadget cleanly
	var spring_pickup: StaticBody3D = track(load("res://entities/props/world_item_pickup.gd").new()) as StaticBody3D
	spring_pickup.name = "FloorSpringPickup"
	spring_pickup.item_id = "SPRING"
	arena.add_child(spring_pickup)
	assert_true(p1._try_trigger_interact_target(spring_pickup, false, 1), "Client E interact dispatch picks up floor SPRING while holding PASSPORT")
	p1._reset_interact_hold()
	assert_true(spring_pickup._is_consumed, "Floor SPRING consumed while holding PASSPORT")
	assert_eq(p1.jacket_slots[0], "SPRING", "SPRING stowed into Jacket Slot 1")

	# Pressing E on a floor BRIEFCASE while holding PASSPORT STILL enters Briefcase Focus Mode
	if dropped_bc != null:
		assert_true(p1._try_trigger_interact_target(dropped_bc, false, 1), "Client E interact dispatch focuses Briefcase while holding PASSPORT")
		p1._reset_interact_hold()
		assert_eq(p1.left_hand_item_id, "PASSPORT", "PASSPORT kept in Left Hand on Briefcase Focus Mode")
		var dropped_bc_c: Node = dropped_bc.get_briefcase_container()
		assert_eq(int(dropped_bc_c.get("occupied_by_peer_id")), 1, "Floor Briefcase entered Focus Mode instead of picking up")
		assert_eq(p1.stance_state, GameConfig.Stance.DRAWER_LOCK, "Player entered DRAWER_LOCK on floor Briefcase")
		dropped_bc_c.close_container(1, p1)


func test_briefcase_freeform_xy_persistence_and_disjoint_layers() -> void:
	MatchManager.start_new_match([1, 2], 7004)
	var host_root: Node = EditorInterface.get_base_control()
	var arena := track(Node3D.new()) as Node3D
	arena.name = "BriefcaseArenaFreeform"
	var players_node := Node3D.new()
	players_node.name = "Players"
	arena.add_child(players_node)
	host_root.add_child(arena)

	var p1: CharacterBody3D = _instantiate_live_player("1")
	players_node.add_child(p1)

	var briefcase_pickup: StaticBody3D = _instantiate_floor_briefcase(arena, ["PASSPORT", "MONEY"])
	var bc_container: Node = briefcase_pickup.get_briefcase_container()
	bc_container.open_container(1, false, p1)

	# Verify 3D Briefcase rig has NO 4-slot divider meshes
	var tray: Node3D = bc_container.get_tray_node()
	var rig: Node = tray.get_node_or_null("BriefcaseVisualRig")
	assert_true(rig != null, "BriefcaseVisualRig built")
	# BaseFloor, FeltLiner, 4 BaseWalls, 3 Handle parts, 2 Clasps, LidPivot = 12 children (no 2 divider boxes)
	assert_eq(rig.get_child_count(), 12, "3D Briefcase has zero divider meshes inside interior")

	# Deposit KEY from Left Hand at exact custom normalized spot (0.22, 0.78)
	p1.pickup_item("KEY")
	assert_true(bc_container.deposit_left_hand_item(1, p1, Vector2(0.22, 0.78)), "Deposited KEY at custom freeform spot")
	# Drag KEY freely to (0.81, 0.25) and check disjoint layer heights
	assert_true(bc_container.move_stored_item(1, "KEY", Vector2(0.81, 0.25)), "Moved KEY freely to (0.81, 0.25)")
	# Plant a Bomb at (0.79, 0.27) directly underneath KEY on Layer 0
	p1.pickup_item("BOMB")
	assert_true(bc_container.plant_trap_from_jacket(1, 0, "TRAY", p1, Vector2(0.79, 0.27)), "Planted BOMB freely at (0.79, 0.27)")

	var contents_root: Node3D = tray.get_node_or_null("ContentsRoot") as Node3D
	assert_true(contents_root != null, "ContentsRoot present")
	var bomb_node: Node3D = contents_root.get_node_or_null("TrayTimeBomb") as Node3D
	var passport_node: Node3D = contents_root.get_node_or_null("TrayItem_0_PASSPORT") as Node3D
	var money_node: Node3D = contents_root.get_node_or_null("TrayItem_1_MONEY") as Node3D
	var key_node: Node3D = contents_root.get_node_or_null("TrayItem_2_KEY") as Node3D
	assert_true(bomb_node != null and passport_node != null and money_node != null and key_node != null, "All 3D layered nodes built")
	assert_true(bomb_node.position.y < passport_node.position.y, "Bomb sits below Item Layer 1")
	assert_true(passport_node.position.y < money_node.position.y and money_node.position.y < key_node.position.y, "Each item occupies a strictly disjoint increasing Y layer")

	# Close -> Carry -> Drop -> Re-open preserves exact freeform coordinates!
	bc_container.close_container(1, p1)
	briefcase_pickup._execute_server_pickup(1)
	assert_eq(p1.left_hand_item_id, "BRIEFCASE", "Picked up Briefcase")
	assert_true(p1.briefcase_item_positions["KEY"].is_equal_approx(Vector2(0.81, 0.25)), "Carried Briefcase kept KEY custom pos (0.81, 0.25)")
	assert_true(p1.briefcase_bomb_norm_pos.is_equal_approx(Vector2(0.79, 0.27)), "Carried Briefcase kept Bomb custom pos (0.79, 0.27)")

	p1.server_request_hand_action("DROP_LEFT")
	assert_eq(p1.left_hand_item_id, "NONE", "Dropped Briefcase to floor")
	var dropped_node: StaticBody3D = arena.get_node_or_null("Dropped_1_BRIEFCASE_1") as StaticBody3D
	assert_true(dropped_node != null, "Dropped Briefcase spawned in arena")
	var dropped_container: Node = dropped_node.get_briefcase_container()
	var dropped_positions: Dictionary = dropped_container.get("item_positions") as Dictionary
	assert_true((dropped_positions["KEY"] as Vector2).is_equal_approx(Vector2(0.81, 0.25)), "Re-opened dropped Briefcase preserved KEY pos (0.81, 0.25)")
	assert_true((dropped_container.get("bomb_norm_pos") as Vector2).is_equal_approx(Vector2(0.79, 0.27)), "Re-opened dropped Briefcase preserved Bomb pos (0.79, 0.27)")


func test_container_shove_momentum_wall_bounce_and_persistence() -> void:
	const SHOVE = preload("res://entities/props/container_shove_physics.gd")

	# 1. Pure physics: release velocity, pause cutoff, wall bounce, friction settling
	var flick_samples: Array = []
	SHOVE.record_sample(flick_samples, Vector2(0.30, 0.50), 1.00)
	SHOVE.record_sample(flick_samples, Vector2(0.45, 0.50), 1.05)
	var flick_vel: Vector2 = SHOVE.compute_release_velocity(flick_samples, Vector2(0.54, 0.50), 1.07)
	assert_gt(flick_vel.x, 1.5, "Fast flick produces strong positive X release velocity")

	var pause_vel: Vector2 = SHOVE.compute_release_velocity(flick_samples, Vector2(0.54, 0.50), 1.25)
	assert_true(pause_vel.is_equal_approx(Vector2.ZERO), "Holding cursor stationary before release yields zero shove momentum")

	var bounce_res: Dictionary = SHOVE.step_slide(Vector2(0.90, 0.50), Vector2(3.0, 0.0), 0.05, 0.08, 0.92)
	assert_true(bool(bounce_res["bounced"]), "Fast slide reflects off right interior wall")
	assert_true((bounce_res["vel"] as Vector2).x < 0.0, "Reflected velocity reverses X direction after wall hit")
	assert_true((bounce_res["pos"] as Vector2).x <= 0.92 and (bounce_res["pos"] as Vector2).x >= 0.08, "Position stays clamped within interior bounds")

	var rest_pos: Vector2 = SHOVE.simulate_to_rest(Vector2(0.85, 0.50), Vector2(3.2, -1.0), 0.08, 0.92)
	assert_true(rest_pos.x >= 0.08 and rest_pos.x <= 0.92 and rest_pos.y >= 0.08 and rest_pos.y <= 0.92, "Slide rests cleanly inside bounds")

	# 2. Live 3D Drawer Clutter shove preserves Y stratum & persists final resting position
	MatchManager.start_new_match([1, 2], 7006)
	var host_root: Node = EditorInterface.get_base_control()
	var arena := track(Node3D.new()) as Node3D
	arena.name = "BriefcaseArenaShove"
	var players_node := Node3D.new()
	players_node.name = "Players"
	arena.add_child(players_node)
	host_root.add_child(arena)

	var p1: CharacterBody3D = _instantiate_live_player("1")
	players_node.add_child(p1)

	var drawer: StaticBody3D = _instantiate_drawer()
	arena.add_child(drawer)
	drawer.open_container(1, false, p1)
	var c0: Node3D = drawer.get_clutter_area_node(0)
	var c0_base_y: float = float(c0.get_meta("base_y", c0.position.y))

	p1.launch_3d_container_slide(drawer, "clutter", 0, "", Vector2(0.75, 0.44), Vector2(3.6, -1.2))
	var steps: int = 0
	while not p1._active_3d_slides.is_empty() and steps < 200:
		p1._step_active_3d_slides(0.05)
		steps += 1
	assert_true(p1._active_3d_slides.is_empty(), "Drawer clutter slide settled to rest cleanly")
	var persisted_c0: Vector2 = drawer.clutter_positions[0]
	assert_false(persisted_c0.is_equal_approx(Vector2(0.75, 0.44)), "Drawer clutter slid away from initial drop point")
	assert_true(persisted_c0.x >= 0.05 and persisted_c0.x <= 0.95 and persisted_c0.y >= 0.05 and persisted_c0.y <= 0.95, "Settled drawer clutter stayed inside bounds")
	var c0_after: Node3D = drawer.get_clutter_area_node(0)
	assert_true(is_equal_approx(c0_after.position.y, c0_base_y), "Clutter vertical layer height preserved after shove slide")
	drawer.close_container(1, p1)

	# 3. Live 3D Floor Briefcase item shove persists & preserves disjoint layer
	var briefcase_pickup: StaticBody3D = _instantiate_floor_briefcase(arena, ["KEY", "MONEY"])
	var bc_container: Node = briefcase_pickup.get_briefcase_container()
	bc_container.open_container(1, false, p1)
	var bc_key_node: Node3D = bc_container.get_content_area_node("loot_item", "KEY")
	var bc_key_y: float = float(bc_key_node.get_meta("base_y", bc_key_node.position.y))
	p1.launch_3d_container_slide(bc_container, "loot_item", -1, "KEY", Vector2(0.70, 0.50), Vector2(2.8, 0.5))
	steps = 0
	while not p1._active_3d_slides.is_empty() and steps < 200:
		p1._step_active_3d_slides(0.05)
		steps += 1
	var bc_rest: Vector2 = (bc_container.get("item_positions") as Dictionary)["KEY"] as Vector2
	assert_false(bc_rest.is_equal_approx(Vector2(0.70, 0.50)), "Floor Briefcase item slid with shove momentum")
	assert_true(bc_rest.x >= 0.08 and bc_rest.x <= 0.92 and bc_rest.y >= 0.08 and bc_rest.y <= 0.92, "Floor Briefcase item stayed inside bounds")
	assert_true(is_equal_approx(bc_container.get_content_area_node("loot_item", "KEY").position.y, bc_key_y), "Floor Briefcase item kept disjoint Y layer")
	bc_container.close_container(1, p1)

	# 4. Left-Side Carried Briefcase UI shove persists to player inventory
	p1.pickup_item("BRIEFCASE", ["KEY"], {"KEY": Vector2(0.30, 0.45)})
	var ui: TopDownContainerUI = track(load("res://ui/top_down_container_ui.gd").new()) as TopDownContainerUI
	host_root.add_child(ui)
	drawer.open_container(1, false, p1)
	ui.open_for_container(p1, drawer, 1)
	ui.launch_carried_briefcase_slide("KEY", Vector2(0.30, 0.45), Vector2(2.4, -0.8))
	ui.step_carried_briefcase_slides(0.05)
	ui.flush_active_briefcase_slides()
	var ui_rest: Vector2 = p1.briefcase_item_positions["KEY"]
	assert_true(ui_rest.x > 0.35 and ui_rest.x <= 0.92 and ui_rest.y >= 0.08 and ui_rest.y <= 0.92, "Carried Briefcase UI slide persisted shoved coordinates")
	ui.close_view()
	drawer.close_container(1, p1)
