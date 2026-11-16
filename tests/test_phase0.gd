@tool
extends "res://addons/godot_ai/testing/test_suite.gd"


func suite_name() -> String:
	return "phase0_foundation"


func test_autoloads_registered() -> void:
	assert_true(ProjectSettings.has_setting("autoload/GameConfig"), "GameConfig autoload registered in ProjectSettings")
	assert_true(ProjectSettings.has_setting("autoload/AudioBridge"), "AudioBridge autoload registered in ProjectSettings")
	assert_true(ProjectSettings.has_setting("autoload/MatchManager"), "MatchManager autoload registered in ProjectSettings")
	assert_true(ProjectSettings.has_setting("autoload/NetworkManager"), "NetworkManager autoload registered in ProjectSettings")
	assert_true(ProjectSettings.has_setting("autoload/EOSManager"), "EOSManager autoload registered in ProjectSettings")
	assert_true(ProjectSettings.has_setting("autoload/SessionManager"), "SessionManager autoload registered in ProjectSettings")


func test_physics_layers_configured() -> void:
	assert_eq(ProjectSettings.get_setting("layer_names/3d_physics/layer_1"), "Environment", "Layer 1 is Environment")
	assert_eq(ProjectSettings.get_setting("layer_names/3d_physics/layer_2"), "Interactable", "Layer 2 is Interactable")
	assert_eq(ProjectSettings.get_setting("layer_names/3d_physics/layer_3"), "Player", "Layer 3 is Player")
	assert_eq(ProjectSettings.get_setting("layer_names/3d_physics/layer_4"), "Ragdoll_KO", "Layer 4 is Ragdoll_KO")
	assert_eq(ProjectSettings.get_setting("layer_names/3d_physics/layer_5"), "Triggers_And_Zones", "Layer 5 is Triggers_And_Zones")

	var cfg: Node = track(load("res://core/game_config.gd").new()) as Node
	assert_eq(cfg.LAYER_ENVIRONMENT, 1, "Bitmask for Layer 1 is 1")
	assert_eq(cfg.LAYER_INTERACTABLE, 2, "Bitmask for Layer 2 is 2")
	assert_eq(cfg.LAYER_PLAYER, 4, "Bitmask for Layer 3 is 4")
	assert_eq(cfg.LAYER_RAGDOLL_KO, 8, "Bitmask for Layer 4 is 8")
	assert_eq(cfg.LAYER_TRIGGERS, 16, "Bitmask for Layer 5 is 16")


func test_input_map_actions_registered() -> void:
	var required_actions: Array[String] = [
		"move_forward",
		"move_back",
		"move_left",
		"move_right",
		"sprint",
		"crouch",
		"jump",
		"interact_primary",
		"primary_action",
		"toggle_club",
		"drop_left_hand",
		"drop_right_hand",
		"spy_gadget_ptt",
		"spy_gadget_bluff",
		"cycle_bluff_cue"
	]
	for action in required_actions:
		var exists: bool = InputMap.has_action(action) or ProjectSettings.has_setting("input/" + action)
		assert_true(exists, "Project input configuration has action: " + action)


func test_mouse_dpi_normalization_and_persistence() -> void:
	var cfg: Node = track(load("res://core/game_config.gd").new()) as Node
	var test_cfg_path: String = "user://test_spy_mouse_settings.cfg"

	# 800 DPI at 1.0x multiplier equals base_mouse_sensitivity_800dpi (0.0022)
	cfg.set_mouse_settings(800, 1.0, false)
	var sens_800: float = cfg.get_effective_mouse_sensitivity()
	assert_true(is_equal_approx(sens_800, 0.0022), "800 DPI at 1.0x produces 0.0022 rad/px")

	# 1600 DPI at 1.0x multiplier automatically halves rad/px (0.0011) so physical 360 turn distance is identical
	cfg.set_mouse_settings(1600, 1.0, false)
	var sens_1600: float = cfg.get_effective_mouse_sensitivity()
	assert_true(is_equal_approx(sens_1600, 0.0011), "1600 DPI at 1.0x halves rad/px to 0.0011 for identical physical turn feel")

	# Save and reload from user:// config
	assert_eq(cfg.save_user_settings(test_cfg_path), OK, "Saved user mouse settings to user://")
	cfg.set_mouse_settings(800, 2.0, false)
	assert_true(cfg.load_user_settings(test_cfg_path), "Loaded user mouse settings from user://")
	assert_eq(cfg.mouse_dpi, 1600, "Loaded mouse_dpi is 1600")
	assert_true(is_equal_approx(cfg.mouse_sensitivity_multiplier, 1.0), "Loaded multiplier is 1.0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_cfg_path))


func test_game_config_tunables_and_speed_formula() -> void:
	var cfg: Node = track(load("res://core/game_config.gd").new()) as Node
	assert_true(is_equal_approx(cfg.walk_speed, 4.5), "Walk speed baseline is 4.5 m/s")
	assert_true(is_equal_approx(cfg.sprint_speed, 6.8), "Sprint speed baseline is 6.8 m/s")
	assert_true(is_equal_approx(cfg.crouch_speed, 3.4), "Crouch speed baseline is 3.4 m/s")
	assert_eq(cfg.starting_prearmed_traps, 0, "starting_prearmed_traps is 0")

	# Normal walk
	assert_true(is_equal_approx(
		cfg.compute_final_move_speed(cfg.Stance.WALK, false, false),
		4.5
	), "Walk speed without encumbrance is 4.5")

	# Briefcase sprint: 6.8 * 0.90 = 6.12
	assert_true(is_equal_approx(
		cfg.compute_final_move_speed(cfg.Stance.SPRINT, true, false),
		6.8 * 0.90
	), "Sprint speed with Briefcase is 6.12 m/s")

	# Club overhead charge overrides Sprint and applies 0.35x: 4.5 * 0.35 = 1.575
	assert_true(is_equal_approx(
		cfg.compute_final_move_speed(cfg.Stance.SPRINT, false, true),
		4.5 * 0.35
	), "Club charge overrides Sprint and slows to 35% of walk speed")

	# Drawer lock or KO forces 0.0 speed
	assert_true(is_equal_approx(
		cfg.compute_final_move_speed(cfg.Stance.DRAWER_LOCK, false, false),
		0.0
	), "Drawer lock stance forces 0.0 m/s")
	assert_true(is_equal_approx(
		cfg.compute_final_move_speed(cfg.Stance.KO, false, false),
		0.0
	), "KO stance forces 0.0 m/s")


func test_audio_bridge_cue_routing() -> void:
	var bridge: Node = track(load("res://core/audio_bridge.gd").new()) as Node
	bridge.clear_recent_cues()

	# Silent cue (radius = 0.0) should not emit
	bridge.play_world_cue("footstep_walk", Vector3(1, 0, 1), 0.0, 1)
	assert_eq(bridge.get_recent_cues().size(), 0, "Zero-radius cue does not emit")

	# Audible world cue should emit and record in history
	bridge.play_world_cue("door_bash", Vector3(2, 1, -3), 14.0, 1)
	var cues: Array[Dictionary] = bridge.get_recent_cues()
	assert_eq(cues.size(), 1, "Audible world cue recorded in AudioBridge")
	assert_eq(cues[0]["cue_id"], "door_bash", "Recorded cue_id matches door_bash")
	assert_true(is_equal_approx(float(cues[0]["radius"]), 14.0), "Recorded radius matches 14.0m")


func test_match_manager_clock_and_og_win_rules() -> void:
	var mm: Node = track(load("res://core/match_manager.gd").new()) as Node
	mm.start_new_match([1, 2], 424242)
	assert_eq(mm.match_seed, 424242, "MatchManager sets deterministic match_seed")
	assert_true(is_equal_approx(mm.get_private_clock(1), 180.0), "Spy 1 starts at 180s")
	assert_true(is_equal_approx(mm.get_private_clock(2), 180.0), "Spy 2 starts at 180s")

	# Award +10s first search bonus to Spy 1 only
	mm.award_first_search_bonus(1)
	assert_true(is_equal_approx(mm.get_private_clock(1), 190.0), "Spy 1 receives +10s bonus (190s)")
	assert_true(is_equal_approx(mm.get_private_clock(2), 180.0), "Spy 2 clock unchanged at 180s")

	# OG Clock Elimination rule: If Spy 1's clock expires, Spy 1 is eliminated,
	# but match continues so Spy 2 must still complete the 4-item Briefcase escape!
	mm.peer_clocks[1] = 0.05
	mm.tick_match_clocks(0.10)
	assert_true(mm.is_peer_eliminated(1), "Spy 1 eliminated at 0:00")
	assert_false(mm.is_peer_eliminated(2), "Spy 2 still active")
	assert_eq(mm.match_state, mm.MatchState.IN_PROGRESS, "Match stays IN_PROGRESS for surviving Spy 2")

	# Incomplete Briefcase (<4 items) rejected at Airport Exit
	assert_false(mm.report_airport_exit_reached(2, 3), "Airport Exit rejects Briefcase with 3/4 Objectives")
	assert_eq(mm.match_state, mm.MatchState.IN_PROGRESS, "Match still in progress")

	# Complete Briefcase (4 items) triggers instant Escape Victory
	assert_true(mm.report_airport_exit_reached(2, 4), "Airport Exit accepts Briefcase with 4/4 Objectives")
	assert_eq(mm.match_state, mm.MatchState.ENDED, "Match transitions to ENDED")
	assert_eq(mm.winner_peer_id, 2, "Spy 2 recorded as winner")
