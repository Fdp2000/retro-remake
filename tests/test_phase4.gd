@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

const CONTAINER_SCRIPT = preload("res://entities/props/searchable_container.gd")
const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const PICKUP_SCENE: PackedScene = preload("res://entities/props/world_item_pickup.tscn")
const TRIPWIRE_SCRIPT = preload("res://entities/traps/tripwire_trap.gd")
const TRIPWIRE_PLACEMENT_SCRIPT = preload("res://entities/player/tripwire_placement_controller.gd")
const THROWN_BOMB_SCRIPT = preload("res://entities/traps/thrown_time_bomb.gd")
const EMBASSY_DOOR_SCRIPT = preload("res://entities/props/embassy_door.gd")
const INTERACTIVE_DOOR_SCRIPT = preload("res://scenes/BuildingComplex2/interactive_door.gd")
const DVD_RETICLE_SCRIPT = preload("res://ui/dvd_dart_reticle_ui.gd")
const CLUB_QTE_SCRIPT = preload("res://ui/club_qte_bar_ui.gd")
const WATCH_BLUFF_SCRIPT = preload("res://ui/spy_watch_bluff_ui.gd")
const CRT_REPLAY_SCRIPT = preload("res://ui/crt_replay_monitor_ui.gd")
const MATCH_SPAWNER_SCRIPT = preload("res://core/match_spawner.gd")

var _saved_game_config: Dictionary = {}


func suite_name() -> String:
	return "phase4_traps_combat_watch_crt"


func setup() -> void:
	_sync_game_config_from_disk()
	if AudioBridge != null:
		AudioBridge.clear_recent_cues()


func teardown() -> void:
	_restore_game_config()
	if MatchManager != null:
		MatchManager.match_state = MatchManager.MatchState.INACTIVE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _sync_game_config_from_disk() -> void:
	if GameConfig == null:
		return
	var fresh_cfg: Node = load("res://core/game_config.gd").new()
	for prop in fresh_cfg.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var p_name: String = str(prop["name"])
			_saved_game_config[p_name] = GameConfig.get(p_name)
			GameConfig.set(p_name, fresh_cfg.get(p_name))
	fresh_cfg.free()


func _restore_game_config() -> void:
	if GameConfig == null or _saved_game_config.is_empty():
		return
	for p_name in _saved_game_config.keys():
		GameConfig.set(p_name, _saved_game_config[p_name])
	_saved_game_config.clear()


func _instantiate_live_scene(scene_path: String, script_path: String) -> Node:
	var packed: PackedScene = load(scene_path)
	var placeholder_root: Node = packed.instantiate()
	var live_root: Node = track(load(script_path).new()) as Node
	live_root.name = placeholder_root.name
	for child in placeholder_root.get_children():
		placeholder_root.remove_child(child)
		for desc in child.find_children("*", "", true, false):
			if desc.owner == placeholder_root:
				desc.owner = null
		child.owner = null
		live_root.add_child(child)
	placeholder_root.free()
	return live_root


func _spawn_spy(peer_id: int, pos: Vector3) -> CharacterBody3D:
	var host_root: Node = EditorInterface.get_base_control()
	var spy: CharacterBody3D = _instantiate_live_scene("res://entities/player/player.tscn", "res://entities/player/player.gd") as CharacterBody3D
	spy.name = str(peer_id)
	spy.spy_role = 1 if peer_id == 1 else 2
	host_root.add_child(spy)
	spy.global_position = pos
	spy.wakeup_immunity_remaining = 0.0
	spy.ensure_overlay_uis()
	return spy


func test_objective_glint_particles_floor_and_drawer() -> void:
	var host_root: Node = EditorInterface.get_base_control()
	var key_pickup: StaticBody3D = _instantiate_live_scene("res://entities/props/world_item_pickup.tscn", "res://entities/props/world_item_pickup.gd") as StaticBody3D
	key_pickup.set("item_id", "KEY")
	host_root.add_child(key_pickup)
	var key_glint: Node = key_pickup.get_node_or_null("ObjectiveGlintParticles")
	assert_true(key_glint is CPUParticles3D, "Floor Objective pickup mounts ObjectiveGlintParticles")
	assert_true(bool((key_glint as CPUParticles3D).emitting), "Floor Objective glint particles are actively emitting")

	var bucket_pickup: StaticBody3D = _instantiate_live_scene("res://entities/props/world_item_pickup.tscn", "res://entities/props/world_item_pickup.gd") as StaticBody3D
	bucket_pickup.set("item_id", "BUCKET")
	host_root.add_child(bucket_pickup)
	assert_true(bucket_pickup.get_node_or_null("ObjectiveGlintParticles") == null, "Non-objective traps do not emit objective glint particles")

	var spy1: CharacterBody3D = _spawn_spy(1, Vector3(0.0, 0.0, 1.0))
	var drawer: Node3D = _instantiate_live_scene("res://entities/props/searchable_drawer.tscn", "res://entities/props/searchable_container.gd") as Node3D
	drawer.set("stored_items", ["PASSPORT", "TRIPWIRE"] as Array[String])
	drawer.set("container_seed", 42)
	host_root.add_child(drawer)
	drawer.call("_rebuild_3d_interior")
	drawer.call("focus_container", 1, spy1)
	drawer.call("open_container", 1, false, spy1)

	var tray: Node3D = drawer.call("get_tray_node") as Node3D
	assert_true(tray != null, "Drawer tray node exists")
	var obj_node: Node3D = tray.find_child("TrayItem_0_PASSPORT", true, false) as Node3D
	var trap_node: Node3D = tray.find_child("TrayItem_1_TRIPWIRE", true, false) as Node3D
	assert_true(obj_node != null and trap_node != null, "Tray items rendered inside 3D drawer")
	if obj_node != null and trap_node != null:
		var drawer_glint: CPUParticles3D = obj_node.get_node_or_null("ObjectiveGlintParticles") as CPUParticles3D
		assert_true(drawer_glint != null, "Objective item in drawer has subtle ObjectiveGlintParticles")
		assert_true(trap_node.get_node_or_null("ObjectiveGlintParticles") == null, "Trap in drawer does not have objective glint")
		if drawer_glint != null:
			assert_true(obj_node.position.y + drawer_glint.position.y < -0.036, "Drawer glint stays strictly below bottom clutter layer height")


func test_water_bucket_door_rig_tell_ko_and_steal() -> void:
	var host_root: Node = EditorInterface.get_base_control()
	var spy1: CharacterBody3D = _spawn_spy(1, Vector3(0.0, 0.0, 0.0))
	var spy2: CharacterBody3D = _spawn_spy(2, Vector3(0.0, 0.0, 0.6))
	spy2.pickup_item("KEY")

	var e_door: Node3D = _instantiate_live_scene("res://entities/props/embassy_door.tscn", "res://entities/props/embassy_door.gd") as Node3D
	assert_true(e_door != null, "EmbassyDoor instantiated cleanly")
	host_root.add_child(e_door)
	e_door.global_position = Vector3(0.0, 0.0, 0.0)
	assert_true(bool(e_door.call("rig_water_bucket", 1)), "EmbassyDoor accepts rigged water bucket")
	assert_true(bool(e_door.get("has_rigged_bucket")), "EmbassyDoor exposes has_rigged_bucket=true")
	var ajar_pivot: Node3D = e_door.get_node("HingePivot")
	assert_true(absf(ajar_pivot.rotation_degrees.y) >= 4.0, "Rigged EmbassyDoor cracks ajar ~5 deg as visual tell")

	assert_true(bool(e_door.call("steal_water_bucket", 2, spy2)), "Thief can steal rigged bucket from EmbassyDoor")
	assert_true("BUCKET" in spy2.jacket_slots, "Stolen bucket enters thief's 3-slot Inner Jacket")
	assert_true(not bool(e_door.get("has_rigged_bucket")), "Stealing clears has_rigged_bucket on EmbassyDoor")

	# Re-rig and swing past 25 deg on interactive_door too
	var maze_door: MeshInstance3D = track(INTERACTIVE_DOOR_SCRIPT.new()) as MeshInstance3D
	host_root.add_child(maze_door)
	maze_door.global_position = Vector3(0.0, 0.0, 0.0)

	assert_true(bool(maze_door.call("rig_water_bucket", 1)), "Maze interactive_door supports rig_water_bucket")
	assert_true(absf(maze_door.rotation_degrees.y) >= 4.0, "Maze interactive_door cracks ~5 deg ajar with bucket")
	maze_door.set("_open_fraction", 0.35)
	maze_door.call("_trigger_rigged_bucket_drop", 2, 0.0)
	assert_eq(int(spy2.get("stance_state")), int(GameConfig.Stance.KO), "Swinging rigged maze door past 25 deg inflicts Water Bucket KO")
	assert_eq(spy2.left_hand_item_id, "NONE", "Water Bucket KO drops Left Hand items")
	assert_eq(spy1.get_meta("dummy", 0), 0, "Spy1 remains intact")


func test_tripwire_trip_jump_crouch_and_steal() -> void:
	var host_root: Node = EditorInterface.get_base_control()
	var spy1: CharacterBody3D = _spawn_spy(1, Vector3(0.0, 0.0, 0.0))
	var spy2: CharacterBody3D = _spawn_spy(2, Vector3(0.0, 0.0, 0.0))
	spy1.pickup_item("MONEY")

	var trap: StaticBody3D = track(TRIPWIRE_SCRIPT.new()) as StaticBody3D
	trap.set("owner_peer_id", 1)
	host_root.add_child(trap)
	trap.global_position = Vector3(0.0, 0.0, 0.0)

	# Owner crouch & high jump bypass
	spy1.stance_state = GameConfig.Stance.CROUCH
	assert_true(not bool(trap.call("try_trip_spy", spy1)), "Crouching passes safely under 0.35m Tripwire")
	spy1.stance_state = GameConfig.Stance.WALK
	spy1.global_position = Vector3(0.0, 0.40, 0.0)
	assert_true(not bool(trap.call("try_trip_spy", spy1)), "Jumping >= 0.35m clears Tripwire safely")

	# Owner-trigger parity while walking
	spy1.global_position = Vector3(0.0, 0.0, 0.0)
	assert_true(bool(trap.call("try_trip_spy", spy1)), "Walking through own Tripwire triggers owner-parity KO")
	assert_eq(int(spy1.get("stance_state")), int(GameConfig.Stance.KO), "Tripwire puts victim into 15s KO stance")
	assert_eq(spy1.left_hand_item_id, "NONE", "Tripwire KO forces Left Hand drop")

	# Separate Tripwire stolen by crouching spy2
	var trap2: StaticBody3D = track(TRIPWIRE_SCRIPT.new()) as StaticBody3D
	trap2.set("owner_peer_id", 1)
	host_root.add_child(trap2)
	spy2.stance_state = GameConfig.Stance.CROUCH
	assert_true(bool(trap2.call("try_steal_tripwire", 2, spy2)), "Spy2 steals Tripwire cleanly into jacket")
	assert_true("TRIPWIRE" in spy2.jacket_slots, "Stolen Tripwire stored in Jacket Slot")


func test_tripwire_two_point_pole_and_wire_placement() -> void:
	var host_root: Node = EditorInterface.get_base_control()
	var arena: Node3D = track(Node3D.new()) as Node3D
	arena.name = "TripwirePlacementTestArena"
	host_root.add_child(arena)

	var floor_body: StaticBody3D = track(StaticBody3D.new()) as StaticBody3D
	floor_body.collision_layer = GameConfig.LAYER_ENVIRONMENT
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20.0, 0.2, 20.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.1, 0.0)
	floor_body.add_child(floor_col)
	arena.add_child(floor_body)

	var wall_body: StaticBody3D = track(StaticBody3D.new()) as StaticBody3D
	wall_body.collision_layer = GameConfig.LAYER_ENVIRONMENT
	var wall_col := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.2, 2.0, 4.0)
	wall_col.shape = wall_box
	wall_col.position = Vector3(5.0, 1.0, 0.0)
	wall_body.add_child(wall_col)
	arena.add_child(wall_body)

	var interactable_body: StaticBody3D = track(StaticBody3D.new()) as StaticBody3D
	interactable_body.collision_layer = GameConfig.LAYER_INTERACTABLE

	var spy1: CharacterBody3D = _instantiate_live_scene("res://entities/player/player.tscn", "res://entities/player/player.gd") as CharacterBody3D
	spy1.name = "1"
	spy1.spy_role = 1
	arena.add_child(spy1)
	spy1.global_position = Vector3(0.0, 0.0, 0.0)
	spy1.wakeup_immunity_remaining = 0.0
	spy1.ensure_overlay_uis()

	var spy2: CharacterBody3D = _instantiate_live_scene("res://entities/player/player.tscn", "res://entities/player/player.gd") as CharacterBody3D
	spy2.name = "2"
	spy2.spy_role = 2
	arena.add_child(spy2)
	spy2.global_position = Vector3(0.0, 0.0, -3.0)
	spy2.wakeup_immunity_remaining = 0.0
	spy2.ensure_overlay_uis()

	spy1.pickup_item("TRIPWIRE")
	spy1.pickup_item("SPRING")
	spy1.select_jacket_slot(0)
	assert_eq(spy1.right_hand_item_id, "TRIPWIRE", "Slot 0 equips TRIPWIRE")

	var ctrl: TripwirePlacementController = spy1.call("_ensure_tripwire_controller") as TripwirePlacementController
	assert_true(ctrl != null, "Player creates TripwirePlacementController")

	# Step 1: Initialize into PLACING_FIRST_POLE and validate surface tints
	ctrl.step(0.016, true, false, true, false)
	assert_eq(ctrl.current_step, TripwirePlacementController.Step.PLACING_FIRST_POLE, "Equipping TRIPWIRE enters Step 1")

	# Invalid wall normal (red)
	assert_false(ctrl.evaluate_aim_from_hit(true, Vector3(0.0, 0.5, -1.0), Vector3(1.0, 0.0, 0.0), wall_body, 1.0), "Vertical wall is invalid for Pole 1")
	ctrl._update_visuals(true)
	assert_true(ctrl._ghost_pole_node.visible and ctrl._ghost_pole_node.material_override == ctrl._mat_invalid, "Ghost pole 1 tints red on wall")

	# Invalid out of reach (red)
	assert_false(ctrl.evaluate_aim_from_hit(true, Vector3(0.0, 0.0, -3.5), Vector3.UP, floor_body, 3.5), "Floor beyond interact_reach is invalid for Pole 1")
	ctrl._update_visuals(true)
	assert_eq(ctrl.invalid_reason, TripwirePlacementController.InvalidReason.OUT_OF_REACH, "Reports OUT_OF_REACH beyond interact_reach")
	assert_true(ctrl._ghost_pole_node.material_override == ctrl._mat_invalid, "Ghost pole 1 tints red out of reach")

	# Invalid non-environment layer (red)
	assert_false(ctrl.evaluate_aim_from_hit(true, Vector3(0.0, 0.0, -1.0), Vector3.UP, interactable_body, 1.2), "LAYER_INTERACTABLE surface is invalid for Pole 1")

	# Valid flat floor within reach (green)
	var p1 := Vector3(-0.9, 0.0, -1.0)
	assert_true(ctrl.evaluate_aim_from_hit(true, p1, Vector3.UP, floor_body, 1.5), "Flat LAYER_ENVIRONMENT floor within reach is valid")
	ctrl._update_visuals(true)
	assert_true(ctrl._ghost_pole_node.visible and ctrl._ghost_pole_node.material_override == ctrl._mat_valid, "Ghost pole 1 tints green on valid floor")

	# Hold LMB < 0.4s does not place Pole 1
	ctrl.begin_lmb_hold()
	ctrl.step(0.25, true, true, true, false)
	assert_false(ctrl.has_placed_first_pole(), "Holding < 0.4s does not place first pole")

	# Hold LMB >= 0.4s places Pole 1 without consuming TRIPWIRE
	ctrl.step(0.20, true, true, true, false)
	assert_true(ctrl.has_placed_first_pole(), "Holding 0.4s places first pole")
	assert_eq(ctrl.current_step, TripwirePlacementController.Step.PLACING_SECOND_POLE, "Transitions to Step 2")
	assert_true(ctrl.first_pole_pos.is_equal_approx(p1), "First pole anchored at exact aim point")
	assert_eq(spy1.jacket_slots[0], "TRIPWIRE", "Placing first pole does not consume TRIPWIRE")
	assert_true(ctrl._placed_pole_node.visible, "Temporary placed first pole visual is visible")

	# Still holding same LMB press does NOT start Pole 2 hold until released
	ctrl.step(0.50, true, true, true, false)
	assert_false(ctrl.is_holding_lmb(), "Must release LMB before charging second pole")
	ctrl.step(0.016, true, false, true, false)

	# Step 2: Distance checks (< 0.4m red, > 2.5m red)
	var p2_close := p1 + Vector3(0.25, 0.0, 0.0)
	assert_false(ctrl.evaluate_aim_from_hit(true, p2_close, Vector3.UP, floor_body, 1.4), "Span < 0.4m rejected")
	assert_eq(ctrl.invalid_reason, TripwirePlacementController.InvalidReason.TOO_CLOSE, "Span < 0.4m reports TOO_CLOSE")
	ctrl._update_visuals(true)
	assert_true(ctrl._ghost_pole_node.material_override == ctrl._mat_invalid and ctrl._ghost_wire_node.material_override == ctrl._mat_invalid, "Ghost pole 2 & wire tint red when too close")

	var p2_far := p1 + Vector3(2.8, 0.0, 0.0)
	assert_false(ctrl.evaluate_aim_from_hit(true, p2_far, Vector3.UP, floor_body, 1.8), "Span > 2.5m rejected")
	assert_eq(ctrl.invalid_reason, TripwirePlacementController.InvalidReason.TOO_FAR, "Span > 2.5m reports TOO_FAR")
	ctrl._update_visuals(true)
	assert_true(ctrl._ghost_pole_node.material_override == ctrl._mat_invalid and ctrl._ghost_wire_node.material_override == ctrl._mat_invalid, "Ghost pole 2 & wire tint red when too far")

	# Step 2: Obstruction check through wall (unconditional assertion)
	var wall_res: Dictionary = TripwirePlacementController.validate_second_pole(Vector3(4.2, 0.0, 0.0), Vector3(5.8, 0.0, 0.0), spy1.get_world_3d())
	assert_false(bool(wall_res["valid"]), "Wall between poles fails validation")
	assert_eq(int(wall_res["reason"]), TripwirePlacementController.InvalidReason.OBSTRUCTED, "Wall between poles reports OBSTRUCTED")
	ctrl.first_pole_pos = Vector3(4.2, 0.0, 0.0)
	assert_false(ctrl.evaluate_aim_from_hit(true, Vector3(5.8, 0.0, 0.0), Vector3.UP, floor_body, 1.5, spy1.get_world_3d()), "Controller Step 2 rejects obstructed path")
	ctrl._update_visuals(true)
	assert_true(ctrl._ghost_pole_node.material_override == ctrl._mat_invalid and ctrl._ghost_wire_node.material_override == ctrl._mat_invalid, "Ghost pole 2 & wire tint red when obstructed")
	ctrl.first_pole_pos = p1

	# Step 2: Valid angled span (1.8m X, -0.5m Z -> ~1.868m) -> green & deploy on 0.4s hold
	var p2 := Vector3(0.9, 0.0, -1.5)
	var expected_span: float = p1.distance_to(p2)
	assert_true(ctrl.evaluate_aim_from_hit(true, p2, Vector3.UP, floor_body, 1.7, spy1.get_world_3d()), "Valid unobstructed span within 0.4m..2.5m passes")
	ctrl._update_visuals(true)
	assert_true(ctrl._ghost_pole_node.visible and ctrl._ghost_pole_node.material_override == ctrl._mat_valid, "Ghost pole 2 tints green when valid")
	assert_true(ctrl._ghost_wire_node.visible and ctrl._ghost_wire_node.material_override == ctrl._mat_valid, "Ghost wire tints green when valid")
	assert_true(ctrl.get_prompt_text().contains("Connect Wire"), "Step 2 prompt offers Connect Wire when valid")

	ctrl.begin_lmb_hold()
	ctrl.step(0.45, true, true, true, false)
	assert_false(ctrl.has_placed_first_pole(), "Completing Step 2 clears temporary placement state")
	assert_false(ctrl._placed_pole_node.visible, "Temporary first pole hidden after deployment")
	assert_eq(spy1.jacket_slots[0], "NONE", "Completing Step 2 consumes TRIPWIRE from jacket slot")

	var spawned_trap: StaticBody3D = null
	for child in arena.get_children():
		if String(child.name).begins_with("Tripwire_"):
			spawned_trap = child as StaticBody3D
			break
	assert_true(spawned_trap != null, "Active TripwireTrap spawned in scene")
	if spawned_trap != null:
		track(spawned_trap)
		assert_true(spawned_trap.global_position.is_equal_approx((p1 + p2) * 0.5), "Dynamic TripwireTrap positioned at exact midpoint")
		assert_true(is_equal_approx(float(spawned_trap.get("span_width")), expected_span), "Dynamic TripwireTrap span_width matches exact pole distance")
		var trig_area: Area3D = spawned_trap.get_node_or_null("TriggerArea") as Area3D
		var trig_col: CollisionShape3D = trig_area.get_child(0) as CollisionShape3D
		assert_true(is_equal_approx((trig_col.shape as BoxShape3D).size.x, expected_span), "TriggerArea BoxShape3D width matches dynamic pole distance")
		var int_col: CollisionShape3D = spawned_trap.get_node_or_null("CollisionShape3D") as CollisionShape3D
		assert_true(is_equal_approx((int_col.shape as BoxShape3D).size.x, expected_span + 0.16), "Interaction BoxShape3D width matches dynamic pole distance")

		# Jump, crouch, and KO parity on dynamic trap
		spy2.stance_state = GameConfig.Stance.CROUCH
		spy2.global_position = (p1 + p2) * 0.5
		assert_false(bool(spawned_trap.call("try_trip_spy", spy2)), "Crouching passes under dynamic Tripwire")
		spy2.stance_state = GameConfig.Stance.WALK
		spy2.global_position = (p1 + p2) * 0.5 + Vector3(0.0, 0.40, 0.0)
		assert_false(bool(spawned_trap.call("try_trip_spy", spy2)), "Jumping clears dynamic Tripwire")
		spy2.global_position = (p1 + p2) * 0.5
		assert_true(bool(spawned_trap.call("try_trip_spy", spy2)), "Walking triggers dynamic Tripwire KO")
		assert_eq(spy2.stance_state, GameConfig.Stance.KO, "Dynamic Tripwire inflicts 15s KO")

	# Crouch-steal a dynamically configured TripwireTrap
	var dyn_trap2: StaticBody3D = track(TRIPWIRE_SCRIPT.new()) as StaticBody3D
	dyn_trap2.set("owner_peer_id", 1)
	dyn_trap2.call("configure_endpoints", p1, p2)
	arena.add_child(dyn_trap2)
	spy2.wake_up_from_ko()
	spy2.wakeup_immunity_remaining = 0.0
	spy2.stance_state = GameConfig.Stance.CROUCH
	assert_true(bool(dyn_trap2.call("try_steal_tripwire", 2, spy2)), "Crouching spy steals dynamically configured TripwireTrap")
	assert_true("TRIPWIRE" in spy2.jacket_slots, "Stolen dynamic Tripwire stored in Jacket Slot")

	# Cancellation paths keep TRIPWIRE unconsumed and clean up temporary pole
	spy1.pickup_item("TRIPWIRE")
	spy1.select_jacket_slot(0)
	var cancel_checks: Array[String] = ["SLOT_SWITCH", "CLUB", "RMB_CANCEL", "ESC_CANCEL", "CONTAINER", "DROP", "KO"]
	for check_name in cancel_checks:
		ctrl.step(0.016, true, false, true, false)
		ctrl.evaluate_aim_from_hit(true, p1, Vector3.UP, floor_body, 1.5)
		ctrl.begin_lmb_hold()
		ctrl.step(0.45, true, true, true, false)
		ctrl.step(0.016, true, false, true, false)
		assert_true(ctrl.has_placed_first_pole(), "First pole placed before %s cancel check" % check_name)

		match check_name:
			"SLOT_SWITCH":
				spy1.select_jacket_slot(1)
				assert_eq(spy1.jacket_slots[0], "TRIPWIRE", "Slot switch keeps TRIPWIRE unconsumed")
				spy1.select_jacket_slot(0)
			"CLUB":
				spy1.toggle_personal_club()
				assert_eq(spy1.jacket_slots[0], "TRIPWIRE", "Equipping Club keeps TRIPWIRE unconsumed")
				spy1.toggle_personal_club()
			"RMB_CANCEL":
				assert_true(bool(spy1.call("handle_tripwire_cancel_input", true, false)), "RMB input handler consumes cancel mid-placement")
				assert_eq(spy1.jacket_slots[0], "TRIPWIRE", "RMB/cancel keeps TRIPWIRE unconsumed")
			"ESC_CANCEL":
				assert_true(bool(spy1.call("handle_tripwire_cancel_input", false, true)), "Cancel/ESC handler consumes cancel mid-placement")
				assert_eq(spy1.jacket_slots[0], "TRIPWIRE", "ESC/cancel keeps TRIPWIRE unconsumed")
			"CONTAINER":
				spy1.enter_container_view(null)
				spy1.exit_container_view()
				assert_eq(spy1.jacket_slots[0], "TRIPWIRE", "Container focus keeps TRIPWIRE unconsumed")
			"DROP":
				var drop_res: Dictionary = spy1.drop_right_hand_item()
				assert_eq(str(drop_res["dropped_item_id"]), "TRIPWIRE", "Drop cleans up pole and drops TRIPWIRE")
				spy1.pickup_item("TRIPWIRE")
				spy1.select_jacket_slot(0)
			"KO":
				spy1.wakeup_immunity_remaining = 0.0
				spy1.apply_trap_ko("SPRING", 2)
				spy1.wake_up_from_ko()
				spy1.wakeup_immunity_remaining = 0.0
				spy1.pickup_item("TRIPWIRE")
				spy1.select_jacket_slot(0)

		assert_false(ctrl.has_placed_first_pole(), "Cancel (%s) clears first pole" % check_name)
		assert_false(ctrl._placed_pole_node.visible, "Cancel (%s) hides first pole visual" % check_name)

	# Host-authority server validation rejects out-of-range span
	var pre_count: int = arena.get_child_count()
	spy1._rpc_server_deploy_tripwire(Vector3.ZERO, Vector3(0.15, 0.0, 0.0))
	spy1._rpc_server_deploy_tripwire(Vector3.ZERO, Vector3(3.10, 0.0, 0.0))
	assert_eq(arena.get_child_count(), pre_count, "Server rejects invalid tripwire spans")
	assert_eq(spy1.jacket_slots[0], "TRIPWIRE", "Server rejection does not consume TRIPWIRE")


func test_thrown_time_bomb_midair_catch_and_occluded_blast() -> void:
	var host_root: Node = EditorInterface.get_base_control()
	var spy_far: CharacterBody3D = _spawn_spy(1, Vector3(6.2, 0.0, 0.0))
	var spy_exposed: CharacterBody3D = _spawn_spy(2, Vector3(-2.0, 0.0, 0.0))

	# Mid-air catch test
	var bomb: StaticBody3D = track(THROWN_BOMB_SCRIPT.new()) as StaticBody3D
	bomb.set("owner_peer_id", 1)
	bomb.set("thrower_peer_id", 1)
	bomb.set("fuse_remaining", 2.6)
	bomb.set("elapsed", 0.4)
	host_root.add_child(bomb)
	bomb.global_position = Vector3(-2.0, 0.95, 0.0)
	var candidate: Node = bomb.call("check_midair_catch_candidate") as Node
	assert_eq(candidate, spy_exposed, "ThrownTimeBomb detects mid-air catch against rival torso")
	assert_true(bool(bomb.call("catch_by_spy", spy_exposed)), "catch_by_spy transfers bomb into rival's active hand")
	assert_eq(spy_exposed.right_hand_item_id, "LIVE_BOMB", "Caught Time Bomb equips as LIVE_BOMB in active hand")
	assert_true(spy_exposed.live_bomb_remaining >= 2.4, "Caught Time Bomb preserves remaining fuse timer")

	# Synchronous 5.0m blast test (<= 5.0m KO + scatter; > 5.0m unharmed)
	spy_exposed.pickup_item("DART_GUN")
	THROWN_BOMB_SCRIPT.detonate_blast_at(EditorInterface.get_base_control().get_tree(), spy_exposed.get_world_3d(), Vector3(-0.2, 0.5, 0.0), 1)
	assert_eq(int(spy_exposed.get("stance_state")), int(GameConfig.Stance.KO), "Exposed rival within 5.0m gets KO'd by Time Bomb blast")
	assert_eq(int(spy_far.get("stance_state")), int(GameConfig.Stance.WALK), "Spy beyond 5.0m blast radius remains unharmed")


func test_dvd_dart_gun_reticle_bounce_and_shot() -> void:
	var host_root: Node = EditorInterface.get_base_control()
	var ret: Control = track(DVD_RETICLE_SCRIPT.new()) as Control
	host_root.add_child(ret)
	ret.call("set_active", true)
	var p0: Vector2 = ret.call("get_reticle_screen_center")
	for _i in range(4):
		ret.call("step_bounce", 0.25, Vector2(640.0, 360.0))
	var p1: Vector2 = ret.call("get_reticle_screen_center")
	assert_true(p1 != p0, "DVD Dart reticle bounces continuously across viewport")
	assert_true(p1.x >= 0.0 and p1.x <= 640.0 and p1.y >= 0.0 and p1.y <= 360.0, "DVD reticle stays inside screen bounds")

	var shooter: CharacterBody3D = _spawn_spy(1, Vector3(0.0, 0.0, 0.0))
	var target: CharacterBody3D = _spawn_spy(2, Vector3(0.0, 0.0, -5.0))
	shooter.pickup_item("DART_GUN")
	# Synchronous physics frame (no await allowed in test runner)
	var fired_hit: bool = shooter.fire_dart_gun(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
	assert_true(fired_hit, "DVD Dart Gun raycast hits rival Spy in line of sight")
	assert_eq(int(target.get("stance_state")), int(GameConfig.Stance.KO), "DVD Dart Gun hit inflicts instant 15s KO")
	assert_eq(shooter.right_hand_item_id, "NONE", "1-shot plastic Dart Gun breaks/consumes slot after firing")


func test_club_qte_feint_whiff_slam_and_overcharge() -> void:
	var attacker: CharacterBody3D = _spawn_spy(1, Vector3(0.0, 0.0, 0.0))
	var victim: CharacterBody3D = _spawn_spy(2, Vector3(0.0, 0.0, -1.4))
	attacker.toggle_personal_club()
	assert_eq(attacker.right_hand_item_id, "CLUB", "Personal Club toggles ready in active hand")

	# 1. Quick Tap Feint (< 0.20s)
	assert_true(attacker.begin_club_qte_charge(0.60), "Start Club QTE for Feint test")
	attacker._club_qte_ui.update_charge(0.10)
	assert_eq(attacker.evaluate_club_release(), "FEINT", "Release < 0.20s evaluates to harmless FEINT")
	attacker._club_feint_cooldown = 0.0

	# 2. Early Release Whiff (< green start 0.60)
	assert_true(attacker.begin_club_qte_charge(0.60), "Start Club QTE for Whiff test")
	assert_true(is_equal_approx(attacker.get_current_move_speed(), GameConfig.walk_speed), "Move speed starts at walk_speed at QTE start")
	attacker._club_qte_ui.update_charge(0.48) # 0.48 / 3.20 = 0.15 -> half way to (green_start * 0.5 = 0.30)
	var mid_expected: float = GameConfig.walk_speed * lerpf(GameConfig.speed_mult_normal, GameConfig.speed_mult_club_charge, 0.5)
	assert_true(is_equal_approx(attacker.get_current_move_speed(), mid_expected), "Move speed linearly lerps toward speed_mult_club_charge over half of green_start")
	attacker._club_qte_ui.update_charge(0.48) # 0.96 / 3.20 = 0.30 -> reaches speed_mult_club_charge at halfway to green_start
	assert_true(is_equal_approx(attacker.get_current_move_speed(), GameConfig.walk_speed * GameConfig.speed_mult_club_charge), "Move speed reaches speed_mult_club_charge at halfway to green_start")
	assert_eq(attacker.evaluate_club_release(), "WHIFF", "Release before green window evaluates to WHIFF")
	attacker._club_whiff_recovery = 0.0

	# 3. Green-Zone Release -> 2.0m KO Slam
	assert_true(attacker.begin_club_qte_charge(0.60), "Start Club QTE for Green Slam test")
	attacker._club_qte_ui.update_charge(2.05) # 2.05 / 3.20 = 0.640625 in [0.60, 0.69]
	assert_true(is_equal_approx(attacker.get_current_move_speed(), GameConfig.walk_speed * GameConfig.speed_mult_club_charge), "Move speed reaches speed_mult_club_charge at green_start")
	# Synchronous physics frame (no await allowed in test runner)
	assert_eq(attacker.evaluate_club_release(), "KO_SLAM", "Release inside green window evaluates to KO_SLAM")
	assert_eq(int(victim.get("stance_state")), int(GameConfig.Stance.KO), "Club KO_SLAM inflicts 15s KO on rival within 2.0m")

	# 4. 100% Overcharge Self-Ragdoll (2.5s)
	assert_true(attacker.begin_club_qte_charge(0.60), "Start Club QTE for Overcharge test")
	var tick_res: String = attacker._club_qte_ui.update_charge(3.30)
	assert_eq(tick_res, "OVERCHARGED", "Holding to 100% reports OVERCHARGED")
	assert_eq(attacker.evaluate_club_release(), "OVERCHARGE", "Overcharge resolves self-ragdoll")
	assert_eq(int(attacker.get("stance_state")), int(GameConfig.Stance.KO), "Overcharge enters minor ragdoll KO state")
	assert_true(is_equal_approx(attacker.ko_remaining_seconds, 2.5), "Overcharge ragdoll lasts 2.5s")


func test_watch_bluffs_anti_camp_sneeze_and_crt_replay() -> void:
	var spy1: CharacterBody3D = _spawn_spy(1, Vector3(0.0, 0.0, 0.0))
	var spy2: CharacterBody3D = _spawn_spy(2, Vector3(3.0, 0.0, 0.0))

	var cycled: String = spy1._watch_bluff_ui.cycle_cue()
	assert_eq(cycled, "drawer_slam", "SpyWatchBluffUI [C] cycles to drawer_slam")
	spy1.emit_watch_bluff(cycled, Vector3(6.0, 0.0, 6.0))
	var cues: Array[Dictionary] = AudioBridge.get_recent_cues()
	assert_true(not cues.is_empty() and str(cues[-1]["cue_id"]) == "drawer_slam" and is_equal_approx(float(cues[-1]["radius"]), 12.0), "Spy Watch bluff emits 12.0m cue at target position")

	# Anti-camp progression: 15s Sniffle -> 20s 22m Sneeze -> Reset on room change
	var s1: String = spy1.step_anti_camp(15.2, "Room_1_1")
	assert_eq(s1, "SNIFFLE", "15s in one room emits Sniffle warning")
	var s2: String = spy1.step_anti_camp(5.0, "Room_1_1")
	assert_eq(s2, "SNEEZE", "20s in one room triggers Anti-Camp Sneeze")
	var cues_after: Array[Dictionary] = AudioBridge.get_recent_cues()
	assert_true(str(cues_after[-1]["cue_id"]) == "sneeze" and is_equal_approx(float(cues_after[-1]["radius"]), 22.0), "Sneeze broadcasts 22.0m acoustic reveal")
	spy1.step_anti_camp(1.0, "Room_1_2")
	assert_eq(spy1.anti_camp_timer, 0.0, "Changing rooms resets Anti-Camp timer")

	# Zero-Bandwidth CRT Replay trigger when trap hits rival
	spy2.apply_trap_ko("SPRING", 1)
	assert_true(spy1._crt_replay_ui.is_replaying(), "Attacker CRT Trap-Cam Monitor automatically plays 3.0s replay when trap hits rival")


func test_match_spawner_deterministic_manifest_and_zero_prearmed() -> void:
	var spawner := MATCH_SPAWNER_SCRIPT.new()
	var m1: Dictionary = spawner.generate_spawn_manifest(77777)
	var m2: Dictionary = spawner.generate_spawn_manifest(77777)
	assert_eq(int(m1["starting_prearmed_traps"]), 0, "Match starts with strictly 0 pre-armed traps")
	assert_eq(int(m1["drawer_count"]), 12, "Spawner produces 12 searchable drawers")
	assert_eq(int(m1["floor_buckets_count"]), 3, "Spawner places 3 open-world Water Buckets")
	assert_eq(m1["drawer_loot_slots"], m2["drawer_loot_slots"], "Identical match_seed produces deterministic drawer loot layout")
	assert_eq(m1["slot_roles"], m2["slot_roles"], "Identical match_seed produces deterministic furniture slot roles")

	var flat_loot: Array[String] = []
	for slot in m1["drawer_loot_slots"]:
		for item in (slot as Array):
			flat_loot.append(str(item))
	for req_item in ["KEY", "MONEY", "PASSPORT", "PLANS", "BRIEFCASE", "SPRING", "BOMB", "TRIPWIRE", "DART_GUN"]:
		assert_true(req_item in flat_loot, "Spawn manifest contains %s" % req_item)


func test_ragdoll_skeleton_head_camera_pelvis_sync_and_secondary_hit() -> void:
	var spy1: CharacterBody3D = _spawn_spy(1, Vector3(0.0, 0.0, 0.0))
	var spy2: CharacterBody3D = _spawn_spy(2, Vector3(0.0, 0.0, -3.0))
	spy1._ensure_ragdoll_controller()
	spy2._ensure_ragdoll_controller()

	assert_true(spy1._ragdoll_ctrl != null and spy1._ragdoll_ctrl.skeleton != null, "Spy 1 mounts AgentGreen Skeleton3D")
	assert_true(spy2._ragdoll_ctrl != null and spy2._ragdoll_ctrl.skeleton != null, "Spy 2 mounts AgentPurple Skeleton3D")
	assert_eq(spy2._ragdoll_ctrl.physical_bones.size(), 13, "13 continuous PhysicalBone3D nodes built on Agent Skeleton3D")

	# Verify local first-person isolates Head, Eyes, and Body onto VISUAL_LAYER_LOCAL_SPY_BODY
	# so local FPS camera never clips its own head while rival CRT Trap-Cam can still render this spy.
	spy1._ragdoll_ctrl.set_first_person_local(true)
	var fp_head_mesh: MeshInstance3D = spy1._ragdoll_ctrl.skeleton.get_node("Head") as MeshInstance3D
	var fp_body_mesh: MeshInstance3D = spy1._ragdoll_ctrl.skeleton.get_node("Body") as MeshInstance3D
	assert_true(fp_head_mesh.visible and fp_body_mesh.visible, "Local 3D Head and Body remain visible on dedicated layer so rival CRT Trap-Cam can render the trap owner")
	assert_eq(fp_head_mesh.layers, GameConfig.VISUAL_LAYER_LOCAL_SPY_BODY, "Local Head mesh isolated onto VISUAL_LAYER_LOCAL_SPY_BODY")
	assert_eq(fp_body_mesh.layers, GameConfig.VISUAL_LAYER_LOCAL_SPY_BODY, "Local Body mesh isolated onto VISUAL_LAYER_LOCAL_SPY_BODY")
	assert_eq(spy1.camera.cull_mask & GameConfig.VISUAL_LAYER_LOCAL_SPY_BODY, 0, "Local Camera3D excludes VISUAL_LAYER_LOCAL_SPY_BODY so FPS view is never obstructed")

	# Verify permanent head-bone camera starts at exact standing neck position (0, 1.6, -3.0) with zero jump on KO
	var pre_ko_cam_pos: Vector3 = spy2._ragdoll_ctrl.get_head_camera_world_transform().origin
	assert_true(pre_ko_cam_pos.distance_to(Vector3(0.0, 1.6, -3.0)) < 0.02, "Permanent spine.006 camera anchor matches standing first-person eye position")

	var pelvis_pb: PhysicalBone3D = spy2._ragdoll_ctrl.physical_bones.get("spine") as PhysicalBone3D
	var chest_pb: PhysicalBone3D = spy2._ragdoll_ctrl.physical_bones.get("spine.002") as PhysicalBone3D
	assert_true(pelvis_pb != null and chest_pb != null, "Pelvis (spine) and Chest (spine.002) PhysicalBone3D exist")
	assert_eq(pelvis_pb.collision_layer, GameConfig.LAYER_RAGDOLL_KO, "PhysicalBone3D uses Layer 4 (Ragdoll_KO)")
	assert_eq(pelvis_pb.collision_mask, GameConfig.LAYER_ENVIRONMENT, "PhysicalBone3D collides only with Layer 1 (Environment)")

	# Trigger Dart Gun KO with strong kick
	var dart_kick := Vector3(0.0, 5.5, -15.5)
	spy2.apply_trap_ko("DART_GUN", 1, dart_kick)
	assert_true(spy2._ragdoll_ctrl.is_ragdoll_active, "KO activates PhysicalBoneSimulator3D ragdoll")
	assert_true(chest_pb.linear_velocity.length() > 14.0, "Dart Gun KO applies strong knockback kick to chest bone")

	# Verify camera locks onto spine.006 head bone world transform
	var expected_cam_xform: Transform3D = spy2._ragdoll_ctrl.get_head_camera_world_transform()
	var cam_node: Camera3D = spy2.get_node("Head/Camera3D") as Camera3D
	assert_true(cam_node.global_transform.origin.distance_to(expected_cam_xform.origin) < 0.05, "Victim Camera3D locks onto spine.006 head bone during KO")

	# Verify secondary hit on already-KO'd body kicks ragdoll without resetting 15s timer
	spy2.ko_remaining_seconds = 9.5
	spy2.apply_trap_ko("BOMB", 1, Vector3(12.0, 6.0, 0.0))
	assert_true(is_equal_approx(spy2.ko_remaining_seconds, 9.5), "Secondary hit on KO'd spy does not reset KO timer")
	assert_eq(spy2._last_ko_reason, "BOMB", "Secondary hit broadcasts new ragdoll impulse")

	# Verify 5 Hz pelvis sync & gentle pull
	spy2._rpc_sync_ragdoll_pelvis(Vector3(1.2, 0.5, -3.5))
	assert_true(spy2._ragdoll_ctrl._has_pelvis_sync_target, "Remote pelvis sync target registered")
	spy2._ragdoll_ctrl.step_remote_pelvis_pull(0.05)

	# Verify wake-up at pelvis position & restoration
	spy2.wake_up_from_ko()
	assert_true(not spy2._ragdoll_ctrl.is_ragdoll_active, "Wake-up stops ragdoll simulation")
	assert_eq(spy2.stance_state, GameConfig.Stance.WALK, "Wake-up restores WALK stance")
	assert_true(spy2.wakeup_immunity_remaining > 1.5, "Wake-up grants 2.0s blink immunity")


func test_crt_trap_cam_rival_subviewport_layers_and_post_hit_tail() -> void:
	var spy1: CharacterBody3D = _spawn_spy(1, Vector3(0.0, 0.0, 0.0))
	var spy2: CharacterBody3D = _spawn_spy(2, Vector3(0.0, 0.0, -3.0))
	spy1._ensure_ragdoll_controller()
	spy2._ensure_ragdoll_controller()
	spy1._ragdoll_ctrl.set_first_person_local(true)
	spy2._ragdoll_ctrl.set_first_person_local(false)

	var crt: CRTReplayMonitorUI = spy1._crt_replay_ui
	assert_true(crt != null, "Local spy mounts CRTReplayMonitorUI")
	crt.sync_rival_rigs()
	crt.update_rival_camera_transforms()

	assert_true(crt.get_rival_rig(1).is_empty(), "CRT monitor never builds a SubViewport for owner self")
	var rig2: Dictionary = crt.get_rival_rig(2)
	assert_true(not rig2.is_empty(), "CRT monitor creates a dedicated SubViewport rig for remote rival Spy 2")

	var vp2: SubViewport = rig2.get("viewport") as SubViewport
	var cam2: Camera3D = rig2.get("camera") as Camera3D
	assert_true(vp2 != null and cam2 != null, "Rival SubViewport and Camera3D exist")
	assert_eq(vp2.size, Vector2i(240, 135), "Rival CRT SubViewport renders at low-res 240x135")
	assert_true(vp2.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Rival CRT SubViewport never runs UPDATE_ALWAYS")
	assert_true(cam2.current, "Rival CRT Camera3D is active inside its SubViewport")

	var expected_pov: Transform3D = spy2.get_crt_pov_transform()
	assert_true(cam2.global_transform.origin.distance_to(expected_pov.origin) < 0.02, "Rival CRT Camera3D tracks rival spine.006 head anchor")

	var rival_layer: int = spy2.get_crt_body_visual_layer()
	assert_true(rival_layer != GameConfig.VISUAL_LAYER_LOCAL_SPY_BODY, "Remote rival body uses a distinct visual layer from local player")
	assert_eq(cam2.cull_mask & rival_layer, 0, "Rival CRT SubViewport excludes rival's own Head/Eyes/Body meshes")
	assert_true((cam2.cull_mask & GameConfig.VISUAL_LAYER_LOCAL_SPY_BODY) != 0, "Rival CRT SubViewport includes local trap owner's body layer")
	assert_true((spy1.camera.cull_mask & rival_layer) != 0, "Local FPS Camera3D renders remote rival body layer normally")

	# Push 40 synthetic 240x135 images and confirm 36-frame ring buffer cap
	for _i in range(40):
		var frame := Image.create(240, 135, false, Image.FORMAT_RGB8)
		crt.push_frame(frame, 2)
	assert_eq(crt.get_buffer_size(2), 36, "Rival CRT ring buffer enforces 36-frame circular cap")

	# Self-inflicted trap must NOT trigger CRT replay
	spy1.apply_trap_ko("SPRING", 1)
	assert_false(crt.is_replaying(), "Self-inflicted trap KO does not open CRT Trap-Cam replay")
	spy1.wake_up_from_ko()
	spy1.wakeup_immunity_remaining = 0.0

	# Trap hitting rival opens 2.0s pre-impact + 1.0s post-impact CRT replay
	AudioBridge.clear_recent_cues()
	spy2.apply_trap_ko("SPRING", 1)
	assert_true(crt.is_replaying(), "Rival trap KO triggers CRT Trap-Cam replay on trap owner's HUD")
	assert_eq(crt.get_active_victim_peer_id(), 2, "CRT replay locks onto hit rival peer ID")
	assert_eq(crt.get_playback_frame_count(), 24, "CRT replay slices 24 pre-impact frames (2.0s at 12 FPS)")
	assert_eq(crt.get_post_capture_remaining(), 12, "CRT replay reserves 12 post-impact frames (1.0s ragdoll tail)")

	# Verify camera continues tracking rival head bone during active ragdoll KO
	crt.update_rival_camera_transforms()
	var ko_head_xform: Transform3D = spy2._ragdoll_ctrl.get_head_camera_world_transform()
	assert_true(cam2.global_transform.origin.distance_to(ko_head_xform.origin) < 0.02, "CRT Camera3D tracks rival spine.006 bone during KO ragdoll")

	# Feed 12 live post-impact frames and confirm seamless append to 36 total frames
	for _j in range(12):
		var tail_frame := Image.create(240, 135, false, Image.FORMAT_RGB8)
		crt.push_frame(tail_frame, 2)
	assert_eq(crt.get_playback_frame_count(), 36, "Post-impact frames append up to full 36-frame 3.0s CRT replay")
	assert_eq(crt.get_post_capture_remaining(), 0, "Post-impact capture counter reaches 0 after 12 frames")

	# Advancing 3.1s closes replay and emits crt_click_off
	crt.step_replay_playback(3.1)
	assert_false(crt.is_replaying(), "CRT Trap-Cam closes automatically after 3.0s duration")
	var cues: Array[Dictionary] = AudioBridge.get_recent_cues()
	var saw_click_off: bool = false
	for c in cues:
		if str(c.get("cue_id", "")) == "crt_click_off":
			saw_click_off = true
			break
	assert_true(saw_click_off, "Closing CRT replay emits crt_click_off local audio cue")


func test_full_round_loop_drawer_furniture_non_overlap_clock_elimination_and_rematch() -> void:
	var host_root: Node = EditorInterface.get_base_control()
	GameConfig.sandbox_gym_mode = false

	var gym: Node3D = _instantiate_live_scene("res://scenes/test_gym.tscn", "res://scenes/test_gym.gd") as Node3D
	assert_true(gym != null, "Live TestGym instantiated")
	host_root.add_child(gym)

	# Full Match Mode omits dev floor pickup row while keeping SharedAirportExit
	assert_true(gym.get_node_or_null("TestPickups") == null, "Full Match Mode skips dev TestPickups table in Room_2_2")
	assert_true(gym.get_node_or_null("TestStep1Props") == null, "Full Match Mode skips dev TestStep1Props in Room_2_2")
	assert_true(gym.get_node_or_null("SharedAirportExit") != null, "SharedAirportExit exists in Room_2_2")

	# Complete simulated 2-player handshake to spawn corner spies and seeded match props
	gym.peers_in_arena[1] = true
	gym.peers_in_arena[2] = true
	gym._spawn_all_players()

	var players_node: Node = gym.get_node("Players")
	var p1_raw: Node3D = players_node.get_node_or_null("1") as Node3D
	var p2_raw: Node3D = players_node.get_node_or_null("2") as Node3D
	assert_true(p1_raw != null and p2_raw != null, "Both Spy 1 and Spy 2 spawned")
	assert_true(p1_raw.position.is_equal_approx(Vector3(-12.0, 1.0, -9.0)), "Full Match spawns Spy 1 in Room_1_1 (NW corner)")
	assert_true(p2_raw.position.is_equal_approx(Vector3(15.0, 1.0, 18.0)), "Full Match spawns Spy 2 in Room_4_4 (SE corner)")

	# Replace editor-placeholder players instantiated from PackedScene with live player.gd instances at identical transforms
	var p1_pos: Vector3 = p1_raw.position
	var p2_pos: Vector3 = p2_raw.position
	players_node.remove_child(p1_raw)
	p1_raw.free()
	players_node.remove_child(p2_raw)
	p2_raw.free()

	var p1: CharacterBody3D = _instantiate_live_scene("res://entities/player/player.tscn", "res://entities/player/player.gd") as CharacterBody3D
	p1.name = "1"
	p1.spy_role = 1
	p1.position = p1_pos
	players_node.add_child(p1)
	p1.wakeup_immunity_remaining = 0.0

	var p2: CharacterBody3D = _instantiate_live_scene("res://entities/player/player.tscn", "res://entities/player/player.gd") as CharacterBody3D
	p2.name = "2"
	p2.spy_role = 2
	p2.position = p2_pos
	players_node.add_child(p2)
	p2.wakeup_immunity_remaining = 0.0

	# Verify MatchSpawner created 12 drawers + 3 floor buckets and FurnitureSpawner never overlaps occupied drawer markers
	var match_props: Node = gym.get_node_or_null("MatchSpawnedProps")
	assert_true(match_props != null, "MatchSpawnedProps spawned on match start")
	var drawer_count: int = 0
	var bucket_count: int = 0
	for child in match_props.get_children():
		if String(child.name).begins_with("MatchDrawer_"):
			drawer_count += 1
		elif String(child.name).begins_with("MatchFloorBucket_"):
			bucket_count += 1
	assert_eq(drawer_count, 12, "Full Match spawns 12 searchable drawers")
	assert_eq(bucket_count, 3, "Full Match spawns 3 floor Water Buckets")

	var f_spawner: Node = gym.get_node_or_null("BuildingComplex2/FurnitureSpawner")
	assert_true(f_spawner != null, "FurnitureSpawner exists on BuildingComplex2")
	if f_spawner != null:
		f_spawner.call("reset_and_populate", MatchManager.match_seed)
		var rooms_root: Node = gym.get_node("BuildingComplex2/Rooms")
		var occupied_markers: int = 0
		var occupied_with_furniture: int = 0
		var free_with_furniture: int = 0
		for room in rooms_root.get_children():
			var pts: Node = room.get_node_or_null("FurnitureSpawnPoints")
			if pts == null:
				continue
			for marker in pts.get_children():
				if not (marker is Marker3D):
					continue
				if bool(marker.get_meta("occupied_by_match_drawer", false)):
					occupied_markers += 1
					if marker.get_child_count() > 0:
						occupied_with_furniture += 1
				elif marker.get_child_count() > 0:
					free_with_furniture += 1
		assert_eq(occupied_markers, 12, "All 12 drawer markers are tagged occupied_by_match_drawer")
		assert_eq(occupied_with_furniture, 0, "FurnitureSpawner skips all 12 occupied drawer markers (zero overlap)")
		assert_gt(free_with_furniture, 0, "FurnitureSpawner still populates unoccupied markers")

	# J2 Clock Elimination: Spy 1 expires at 00:00 while Spy 2 retains time -> Spy 1 scatters items and locks KO
	p1.pickup_item("KEY")
	p1.pickup_item("BUCKET")
	MatchManager.peer_clocks[2] = 200.0
	MatchManager.tick_match_clocks(181.0)
	assert_true(MatchManager.is_peer_eliminated(1), "MatchManager marks Peer 1 eliminated at 00:00")
	assert_true(p1.is_clock_eliminated, "Player 1 sets is_clock_eliminated=true")
	assert_eq(p1.stance_state, GameConfig.Stance.KO, "Eliminated Spy 1 enters locked KO stance")
	assert_eq(p1.left_hand_item_id, "NONE", "Eliminated Spy 1 drops Left Hand Objective onto floor")
	assert_eq(p1.jacket_slots[0], "NONE", "Eliminated Spy 1 drops Jacket Gadget onto floor")
	p1.tick_ko_and_immunity(20.0)
	assert_eq(p1.stance_state, GameConfig.Stance.KO, "Clock-eliminated Spy cannot wake up after 15s")

	# J1 / J5 Escape Victory & Match-End Overlay
	p2.pickup_item("BRIEFCASE", ["KEY", "MONEY", "PASSPORT", "PLANS"])
	assert_true(MatchManager.report_airport_exit_reached(2, 4), "Surviving Spy 2 escapes with 4/4 Briefcase")
	assert_eq(MatchManager.match_state, MatchManager.MatchState.ENDED, "Match transitions to ENDED on exit")
	var end_ui: Control = gym.get("_match_end_ui") as Control
	assert_true(end_ui != null and end_ui.visible, "MatchEndOverlayUI opens automatically on match_ended")
	assert_eq(int(end_ui.get("last_winner_peer_id")), 2, "MatchEndOverlayUI records Spy 2 victory")

	# J5 Instant In-Game Rematch (New Seed)
	gym.call("trigger_rematch", false, 42424)
	assert_false(end_ui.visible, "Rematch hides MatchEndOverlayUI")
	assert_eq(MatchManager.match_state, MatchManager.MatchState.IN_PROGRESS, "Rematch resets MatchManager to IN_PROGRESS")
	assert_eq(MatchManager.match_seed, 42424, "Rematch applies new deterministic match_seed")
	assert_false(p1.is_clock_eliminated, "Rematch clears clock elimination flag on Spy 1")
	assert_eq(p1.stance_state, GameConfig.Stance.WALK, "Rematch restores Spy 1 to WALK stance")
	assert_true(p1.position.is_equal_approx(Vector3(-12.0, 1.0, -9.0)), "Rematch returns Spy 1 to NW corner spawn")
	assert_true(p2.position.is_equal_approx(Vector3(15.0, 1.0, 18.0)), "Rematch returns Spy 2 to SE corner spawn")
	assert_eq(p2.left_hand_item_id, "NONE", "Rematch clears player inventories")
