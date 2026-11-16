@tool
extends "res://addons/godot_ai/testing/test_suite.gd"


func suite_name() -> String:
	return "phase1_locomotion_and_inventory"


func _instantiate_live_player() -> CharacterBody3D:
	var packed: PackedScene = load("res://entities/player/player.tscn")
	var placeholder_root: Node = packed.instantiate()
	var live_player: CharacterBody3D = track(load("res://entities/player/player.gd").new()) as CharacterBody3D
	live_player.name = "1"
	for child in placeholder_root.get_children():
		placeholder_root.remove_child(child)
		live_player.add_child(child)
	placeholder_root.free()
	live_player.collision_shape = live_player.get_node("CollisionShape3D")
	live_player.mesh_instance = live_player.get_node("MeshInstance3D")
	live_player.head = live_player.get_node("Head")
	live_player.camera = live_player.get_node("Head/Camera3D")
	live_player.raycast = live_player.get_node("Head/Camera3D/RayCast3D")
	return live_player


func test_player_scene_nodes_and_replication_schema() -> void:
	var packed: PackedScene = load("res://entities/player/player.tscn")
	var p: CharacterBody3D = track(packed.instantiate()) as CharacterBody3D

	assert_eq(p.collision_layer, 4, "Player collision_layer is 4 (Layer 3 Player)")
	var ray: RayCast3D = p.get_node("Head/Camera3D/RayCast3D")
	assert_true(ray != null, "InteractRayCast exists")
	assert_true(is_equal_approx(ray.target_position.z, -2.2), "InteractRayCast reach is -2.2m")

	var bash_det: Area3D = p.get_node_or_null("DoorBashDetector")
	assert_true(bash_det != null, "DoorBashDetector Area3D exists")
	assert_eq(bash_det.collision_layer, 16, "DoorBashDetector is on Layer 5 (Triggers_And_Zones = 16)")

	assert_true(p.get_node_or_null("VisualRig/BackClubSocket") != null, "BackClubSocket exists")
	assert_true(p.get_node_or_null("VisualRig/SpyWearableSocket") != null, "SpyWearableSocket exists")
	assert_true(p.get_node_or_null("Head/Camera3D/LeftHandSocket") != null, "LeftHandSocket exists")
	assert_true(p.get_node_or_null("Head/Camera3D/RightHandSocket") != null, "RightHandSocket exists")

	var syncer: MultiplayerSynchronizer = p.get_node("MultiplayerSynchronizer")
	var config: SceneReplicationConfig = syncer.replication_config
	var props: Array[NodePath] = config.get_properties()
	var required_props: Array[String] = [
		".:position",
		".:rotation:y",
		".:head_pitch",
		".:spy_role",
		".:stance_state",
		".:left_hand_item_id",
		".:right_hand_item_id",
		".:is_charging_club"
	]
	for req in required_props:
		assert_true(NodePath(req) in props, "MultiplayerSynchronizer replicates " + req)


func test_stances_capsule_height_and_footstep_radii() -> void:
	var p: CharacterBody3D = _instantiate_live_player()

	# Default Quiet Walk
	p.update_stance_from_inputs(false, false)
	assert_eq(p.stance_state, GameConfig.Stance.WALK, "Default stance is WALK")
	assert_true(is_equal_approx(p.get_current_move_speed(), 4.5), "Walk speed is 4.5 m/s")
	assert_true(is_equal_approx(p.get_current_footstep_radius(), 3.0), "Walk footstep radius is 3.0m")
	var cap: CapsuleShape3D = p.collision_shape.shape as CapsuleShape3D
	assert_true(is_equal_approx(cap.height, 1.8), "Standing capsule height is 1.8m")

	# Loud Sprint (Shift)
	p.update_stance_from_inputs(true, false)
	assert_eq(p.stance_state, GameConfig.Stance.SPRINT, "Shift activates SPRINT")
	assert_true(is_equal_approx(p.get_current_move_speed(), 6.8), "Sprint speed is 6.8 m/s")
	assert_true(is_equal_approx(p.get_current_footstep_radius(), 14.0), "Sprint footstep radius is 14.0m")

	# Silent Crouch (Ctrl overrides Shift)
	p.update_stance_from_inputs(true, true)
	assert_eq(p.stance_state, GameConfig.Stance.CROUCH, "Ctrl activates CROUCH (overriding Sprint)")
	assert_true(is_equal_approx(p.get_current_move_speed(), 3.4), "Crouch speed is 3.4 m/s (75%)")
	assert_true(is_equal_approx(p.get_current_footstep_radius(), 0.0), "Crouch footstep radius is 0.0m (Silent)")
	cap = p.collision_shape.shape as CapsuleShape3D
	assert_true(is_equal_approx(cap.height, 1.0), "Crouched capsule height shrinks to 1.0m")
	assert_true(is_equal_approx(p.head.position.y, 0.85), "Crouched Neck height lowers to 0.85m")


func test_left_hand_objectives_and_briefcase_packing() -> void:
	var p: CharacterBody3D = _instantiate_live_player()

	# 1. Pick up KEY into empty Left Hand
	var r1: Dictionary = p.pickup_item("KEY")
	assert_true(bool(r1["picked"]), "KEY picked up")
	assert_eq(p.left_hand_item_id, "KEY", "Left Hand holds KEY")
	assert_eq(str(r1["dropped_item_id"]), "NONE", "Nothing dropped")

	# 2. Pick up MONEY while holding KEY -> Swaps and drops KEY
	var r2: Dictionary = p.pickup_item("MONEY")
	assert_true(bool(r2["picked"]), "MONEY picked up")
	assert_eq(p.left_hand_item_id, "MONEY", "Left Hand swapped to MONEY")
	assert_eq(str(r2["dropped_item_id"]), "KEY", "KEY was dropped on swap")

	# 3. Pick up BRIEFCASE while holding MONEY -> Auto-packs MONEY inside Briefcase & equips Briefcase
	var r3: Dictionary = p.pickup_item("BRIEFCASE", ["PASSPORT"])
	assert_true(bool(r3["picked"]), "BRIEFCASE picked up")
	assert_eq(p.left_hand_item_id, "BRIEFCASE", "Left Hand now holds BRIEFCASE")
	assert_eq(p.briefcase_objectives.size(), 2, "Briefcase contains existing PASSPORT + auto-packed MONEY (2/4)")
	assert_true("PASSPORT" in p.briefcase_objectives and "MONEY" in p.briefcase_objectives, "Both PASSPORT and MONEY packed")
	assert_true(is_equal_approx(p.get_current_move_speed(), 4.5 * 0.90), "Briefcase applies 0.90x move speed multiplier")

	# 4. Pick up PLANS while holding BRIEFCASE -> Auto-packs PLANS into Briefcase
	var r4: Dictionary = p.pickup_item("PLANS")
	assert_true(bool(r4["picked"]), "PLANS auto-packed into held Briefcase")
	assert_eq(p.left_hand_item_id, "BRIEFCASE", "Still holding BRIEFCASE")
	assert_eq(p.briefcase_objectives.size(), 3, "Briefcase now holds 3/4 Objectives")

	# 5. Press Q to drop Briefcase -> Preserves packed objectives in drop data
	var drop_q: Dictionary = p.drop_left_hand_item()
	assert_eq(str(drop_q["dropped_item_id"]), "BRIEFCASE", "Q dropped BRIEFCASE")
	assert_eq((drop_q["dropped_briefcase_items"] as Array).size(), 3, "Dropped Briefcase retains 3 packed Objectives")
	assert_eq(p.left_hand_item_id, "NONE", "Left Hand is now empty")
	assert_eq(p.briefcase_objectives.size(), 0, "Player briefcase array cleared")


func test_right_hand_club_and_briefcase_charge_drop_rule() -> void:
	var p: CharacterBody3D = _instantiate_live_player()

	# Equip Briefcase in Left Hand and Bucket in Right Hand
	p.pickup_item("BRIEFCASE", ["KEY"])
	p.pickup_item("BUCKET")
	assert_eq(p.left_hand_item_id, "BRIEFCASE", "Left Hand holds BRIEFCASE")
	assert_eq(p.right_hand_item_id, "BUCKET", "Right Hand holds BUCKET")

	# Press 1 (Toggle Club): Drops BUCKET from Right Hand, draws CLUB, keeps BRIEFCASE in Left Hand!
	var draw_res: Dictionary = p.toggle_personal_club()
	assert_eq(str(draw_res["dropped_item_id"]), "BUCKET", "Drawing Club drops held BUCKET")
	assert_eq(p.right_hand_item_id, "CLUB", "Right Hand holds CLUB")
	assert_eq(p.left_hand_item_id, "BRIEFCASE", "Simply drawing Club does NOT drop Briefcase")

	# Hold LMB (Start Club Charge): Immediately drops Briefcase from Left Hand and slows to 35%!
	var charge_res: Dictionary = p.start_club_charge()
	assert_true(p.is_charging_club, "is_charging_club is true")
	assert_eq(str(charge_res["dropped_item_id"]), "BRIEFCASE", "Starting Club charge auto-drops BRIEFCASE")
	assert_eq(p.left_hand_item_id, "NONE", "Left Hand is now empty after Briefcase charge-drop")
	assert_true(is_equal_approx(p.get_current_move_speed(), 4.5 * 0.35), "Charging Club slows move speed to 35%")
	p.stop_club_charge()

	# Loose Objective is NOT dropped when charging Club (Doc 2 §4.B Row 10)
	p.pickup_item("KEY")
	var charge_loose: Dictionary = p.start_club_charge()
	assert_eq(str(charge_loose["dropped_item_id"]), "NONE", "Charging Club does NOT drop Loose Objective")
	assert_eq(p.left_hand_item_id, "KEY", "Left Hand still holds KEY while charging Club")
	p.stop_club_charge()

	# Press G with Club does NOT drop Club permanently
	var drop_g_club: Dictionary = p.drop_right_hand_item()
	assert_eq(str(drop_g_club["dropped_item_id"]), "NONE", "Cannot drop personal Club with G")
	assert_eq(p.right_hand_item_id, "CLUB", "Still holding CLUB")

	# Knockout Full-Drop Rule drops everything in both hands and re-holsters Club
	p.pickup_item("TRIPWIRE")
	var ko_drops: Array[Dictionary] = p.force_drop_all_hands()
	assert_eq(ko_drops.size(), 2, "KO force-dropped both Left Hand (KEY) and Right Hand (TRIPWIRE)")
	assert_eq(p.left_hand_item_id, "NONE", "Left Hand empty after KO")
	assert_eq(p.right_hand_item_id, "NONE", "Right Hand empty after KO")
