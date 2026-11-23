@tool
extends Node

## Centralized gameplay tunables and architectural constants (AGENTS.md §1).
## All [TUNABLE] baselines from Master GDD v3.2 and Docs 2–7 are exposed here.

signal mouse_settings_changed(effective_sensitivity: float)
signal spawner_settings_changed()

const USER_SETTINGS_PATH: String = "user://spy_user_settings.cfg"
const REFERENCE_DPI: float = 800.0

enum Stance {
	WALK = 0,
	SPRINT = 1,
	CROUCH = 2,
	DRAWER_LOCK = 3,
	KO = 4
}

enum BluffMode {
	SELF_ONLY = 0,
	MAP_PROJECTOR = 1
}

enum BluffCue {
	TRAP_ARM = 0,
	DRAWER_SLAM = 1,
	SPRINT_BURST = 2,
	DOOR_BASH = 3
}

# ==========================================
# 3D Physics Collision Layer Bitmasks (AGENTS.md §3)
# ==========================================
const LAYER_ENVIRONMENT: int = 1 << 0        # Layer 1: Solid walls, floors, ceilings, closed door leaves
const LAYER_INTERACTABLE: int = 1 << 1       # Layer 2: Doors, drawers, dropped Briefcase, objectives, traps
const LAYER_PLAYER: int = 1 << 2             # Layer 3: Active standing/crouching SpyCharacter capsules
const LAYER_RAGDOLL_KO: int = 1 << 3         # Layer 4: Active during 15.0s PhysicalBoneSimulator3D KO state
const LAYER_TRIGGERS: int = 1 << 4           # Layer 5: RoomZones, DoorBashDetector, Tripwire, Splash, Bomb Catch

# ==========================================
# 3D Visual Render Layer Bitmasks (Camera3D.cull_mask / VisualInstance3D.layers)
# ==========================================
const VISUAL_LAYER_ALL: int = 0xFFFFF                 # All 20 Godot visual layers
const VISUAL_LAYER_WORLD: int = 1 << 0                # Layer 1: World geometry, doors, props, traps, held items
const VISUAL_LAYER_LOCAL_SPY_BODY: int = 1 << 10      # Layer 11: Local spy's own Head/Eyes/Body (hidden from local cam, visible to rival CRT cam)
const VISUAL_LAYER_REMOTE_SPY_BASE_BIT: int = 11      # Layers 12-14 (bits 11..13): Up to 3 remote rivals' Head/Eyes/Body
const VISUAL_LAYER_REMOTE_SPY_SLOTS: int = 3


static func get_remote_spy_visual_layer(slot_index: int) -> int:
	return 1 << (VISUAL_LAYER_REMOTE_SPY_BASE_BIT + posmod(slot_index, VISUAL_LAYER_REMOTE_SPY_SLOTS))

# ==========================================
# 4-Player Free-For-All Spy Role Definitions (Slots 1..4)
# ==========================================
const SPY_ROLE_NAMES: Dictionary = {
	1: "SPY GREEN",
	2: "SPY PURPLE",
	3: "SPY BLUE",
	4: "SPY RED"
}

const SPY_ROLE_COLORS: Dictionary = {
	1: Color(0.22, 0.68, 0.32, 1.0),
	2: Color(0.52, 0.24, 0.76, 1.0),
	3: Color(0.20, 0.48, 0.88, 1.0),
	4: Color(0.84, 0.22, 0.24, 1.0)
}

const SPY_ROLE_BADGE_COLORS: Dictionary = {
	1: Color(0.45, 0.95, 0.55, 1.0),
	2: Color(0.78, 0.55, 1.00, 1.0),
	3: Color(0.45, 0.75, 1.00, 1.0),
	4: Color(1.00, 0.48, 0.48, 1.0)
}


static func get_spy_role_name(role: int) -> String:
	return str(SPY_ROLE_NAMES.get(role, "SPY %d" % role))


static func get_spy_role_color(role: int) -> Color:
	return SPY_ROLE_COLORS.get(role, Color(0.92, 0.92, 0.92, 1.0)) as Color


static func get_spy_role_badge_color(role: int) -> Color:
	return SPY_ROLE_BADGE_COLORS.get(role, Color(0.92, 0.92, 0.92, 1.0)) as Color

# ==========================================
# Mouse Sensitivity & Per-User DPI Normalization
# ==========================================
@export_group("Mouse & Look Controls")
## Baseline radians-per-pixel sensitivity calibrated for a standard 800 DPI mouse.
@export var base_mouse_sensitivity_800dpi: float = 0.0022
## Hardware DPI of the local player's mouse (saved per-PC in user://spy_user_settings.cfg so it never conflicts in Git).
@export var mouse_dpi: int = 800:
	set(value):
		mouse_dpi = clampi(value, 200, 12800)
		mouse_settings_changed.emit(get_effective_mouse_sensitivity())
## Personal sensitivity multiplier (1.0 = standard feel for the selected DPI).
@export var mouse_sensitivity_multiplier: float = 1.0:
	set(value):
		mouse_sensitivity_multiplier = clampf(value, 0.10, 4.00)
		mouse_settings_changed.emit(get_effective_mouse_sensitivity())

# ==========================================
# Doc 2: Locomotion, Stances & Reach [TUNABLE]
# ==========================================
@export_group("Locomotion & Stances")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 6.8
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 4.2
@export var standing_capsule_height: float = 1.8
@export var crouched_capsule_height: float = 1.0
@export var standing_neck_y: float = 1.6
@export var crouched_neck_y: float = 0.85
@export var stance_transition_speed: float = 12.0
@export var interact_reach: float = 1.75

@export_group("Speed Multipliers")
@export var speed_mult_normal: float = 1.00
@export var speed_mult_briefcase: float = 0.90
@export var speed_mult_club_charge: float = 0.35
@export var speed_mult_locked: float = 0.00

# ==========================================
# Master GDD & Doc 3: Match & Timer Economy [TUNABLE]
# ==========================================
@export_group("Match & Timer Economy")
@export var starting_clock_seconds: float = 180.0
@export var drawer_first_search_bonus_seconds: float = 10.0
@export var starting_prearmed_traps: int = 0
@export var required_objectives_count: int = 4

# ==========================================
# Doc 3: Doors & Searchable Containers [TUNABLE]
# ==========================================
@export_group("Doors & Drawers")
@export var door_fast_open_duration: float = 0.25
@export var door_sprint_bash_duration: float = 0.12
@export var door_slow_peek_hold_time: float = 2.80
@export var door_slow_peek_swing_duration: float = 2.80
@export var door_close_duration: float = 0.30
@export var door_bucket_ajar_angle_deg: float = 10.0
@export var door_bucket_release_angle_deg: float = 28.0
@export var door_bucket_same_side_release_delta_deg: float = 4.0
@export var bucket_hit_radius: float = 1.45
@export var bucket_max_safe_reach: float = 1.8
@export var bucket_fall_impact_delay: float = 0.10

@export var drawer_fast_slam_duration: float = 0.22
@export var drawer_slow_peek_hold_time: float = 2.20
@export var drawer_slow_open_exp_steepness: float = 4.5
@export var drawer_close_duration: float = 0.30
@export var top_down_cam_lerp_duration: float = 0.65
@export var drawer_interior_mesh_scale: float = 1.10
@export var drawer_max_clutter_layers: int = 3
@export var container_drag_momentum_scale: float = 1.00
@export var container_drag_friction: float = 6.5
@export var container_drag_wall_bounce: float = 0.42
@export var container_drag_max_speed: float = 4.5
@export var container_drag_stop_speed: float = 0.04
@export var briefcase_camera_height: float = 0.88
@export var briefcase_camera_front_offset: float = 0.30
@export var briefcase_camera_target_y: float = 0.04
@export var briefcase_camera_target_z: float = -0.02

# ==========================================
# Doc 4: The 5-Trap & Gadget Ecosystem [TUNABLE]
# ==========================================
@export_group("Traps & Gadgets")
@export var trap_setup_hold_time: float = 0.80
@export var trap_steal_hold_time: float = 1.00
@export var tripwire_pole_hold_time: float = 0.40
@export var tripwire_min_span: float = 0.40
@export var tripwire_max_span: float = 2.50
@export var tripwire_height: float = 0.35
@export var tripwire_ladder_safe_radius: float = 1.90
@export var time_bomb_fuse_min: float = 3.0
@export var time_bomb_fuse_max: float = 3.6
@export var debug_long_bomb_fuse: bool = false
@export var debug_long_bomb_fuse_seconds: float = 8.0
@export var time_bomb_throw_distance: float = 9.0
@export var time_bomb_throw_speed: float = 9.5
@export var time_bomb_blast_radius: float = 5.7
@export var time_bomb_self_catch_ignore_time: float = 0.25
@export var dvd_reticle_speed_px: float = 320.0

# ==========================================
# Doc 5: Club Combat QTE & 15s Ragdoll KO [TUNABLE]
# ==========================================
@export_group("Combat & Ragdoll KO")
@export var club_quick_tap_threshold: float = 0.20
@export var club_feint_cooldown: float = 0.40
@export var club_whiff_recovery_time: float = 0.60
@export var club_charge_fill_duration: float = 3.20
@export var club_green_zone_width: float = 0.09
@export var club_green_zone_min_start: float = 0.55
@export var club_green_zone_max_start: float = 0.75
@export var club_melee_range: float = 2.0
@export var club_overcharge_stumble_duration: float = 2.5
@export var club_charge_exit_lerp_duration: float = 0.40
@export var debug_club_hit_gizmo: bool = false

@export var ko_ragdoll_duration: float = 15.0
@export var ko_wakeup_blend_duration: float = 0.35
@export var ko_wakeup_immunity_duration: float = 2.0
@export var ko_drop_scatter_speed: float = 1.5

# ==========================================
# Doc 6: Spatial Audio Radii, Deception & CRT Replay [TUNABLE]
# ==========================================
@export_group("Audio Radii & Deception")
@export var audio_radius_walk: float = 3.0
@export var audio_radius_sprint: float = 14.0
@export var audio_radius_crouch: float = 0.0
@export var audio_radius_jump_land: float = 5.0
@export var audio_radius_door_fast: float = 8.0
@export var audio_radius_door_bash: float = 14.0
@export var audio_radius_door_close: float = 5.0
@export var audio_radius_bucket_spill: float = 12.0
@export var audio_radius_drawer_fast: float = 10.0
@export var audio_radius_trap_setup: float = 5.0
@export var audio_radius_bomb_fuse: float = 10.0
@export var audio_radius_bomb_explosion: float = 20.0
@export var audio_radius_proximity_voice: float = 12.0
@export var audio_radius_bluff: float = 12.0
@export var audio_radius_sneeze: float = 22.0

@export var bluff_mode: int = BluffMode.MAP_PROJECTOR
@export var show_enemy_room_blip: bool = false

@export var crt_replay_fps: int = 12
@export var crt_replay_duration: float = 3.0
@export var crt_replay_frame_count: int = 36
@export var crt_viewport_size: Vector2i = Vector2i(240, 135)
## Seconds of live post-impact ragdoll footage appended onto the 3.0s CRT replay after the trap hits.
@export var crt_replay_post_hit_seconds: float = 1.0

@export var anti_camp_warning_seconds: float = 15.0
@export var anti_camp_sneeze_seconds: float = 20.0
@export var anti_camp_repeat_seconds: float = 15.0

# ==========================================
# Doc 7: Modular Greybox Level & Spawner [TUNABLE]
# ==========================================
@export_group("Level & Match Randomizer")
@export var room_dimensions: Vector3 = Vector3(6.0, 3.2, 6.0)
@export var grid_dimensions: Vector2i = Vector2i(3, 3)
@export var spawner_searchable_drawers_count: int = 32
@export var spawner_min_containers: int = 24
@export var spawner_max_containers: int = 32
@export var spawner_min_drawers: int = 24
@export var spawner_max_drawers: int = 32
@export var spawner_max_drawers_per_room: int = 2
@export var spawner_allow_drawers_in_spawn_rooms: bool = true
@export var spawner_max_drawers_in_spawn_room: int = 1
@export var spawner_isolate_briefcase_from_objectives: bool = true
@export var spawner_min_total_gadgets: int = 11
@export var spawner_max_total_gadgets: int = 14
@export var spawner_spring_min: int = 1
@export var spawner_spring_max: int = 6
@export var spawner_bomb_min: int = 1
@export var spawner_bomb_max: int = 6
@export var spawner_tripwire_min: int = 1
@export var spawner_tripwire_max: int = 6
@export var spawner_dart_gun_min: int = 0
@export var spawner_dart_gun_max: int = 4
@export var spawner_floor_buckets_count: int = 6
@export var spawner_floor_buckets_min: int = 4
@export var spawner_floor_buckets_max: int = 6
@export var spawner_cover_props_count: int = 6
@export var spawner_active_preset_players: int = 2
@export var spawner_auto_preset_by_player_count: bool = true
## When false (default), launches a real seeded round (corner room spawns, no free pickup table in Room_2_2).
## When true, spawns the Room_2_2 dev test bench with all pickups/traps/drawers laid out for quick testing.
@export var sandbox_gym_mode: bool = false

const PLAYER_COUNT_SPAWNER_PRESETS: Dictionary = {
	2: {
		"starting_clock_seconds": 180.0,
		"drawer_first_search_bonus_seconds": 10.0,
		"min_containers": 24,
		"max_containers": 32,
		"max_drawers_per_room": 2,
		"allow_drawers_in_spawn_rooms": true,
		"max_drawers_in_spawn_room": 1,
		"isolate_briefcase_from_objectives": true,
		"min_total_gadgets": 11,
		"max_total_gadgets": 14,
		"spring_min": 1,
		"spring_max": 6,
		"bomb_min": 1,
		"bomb_max": 6,
		"tripwire_min": 1,
		"tripwire_max": 6,
		"dart_gun_min": 0,
		"dart_gun_max": 4,
		"floor_buckets_min": 4,
		"floor_buckets_max": 6,
		"cover_props_count": 6
	},
	3: {
		"starting_clock_seconds": 210.0,
		"drawer_first_search_bonus_seconds": 10.0,
		"min_containers": 30,
		"max_containers": 38,
		"max_drawers_per_room": 2,
		"allow_drawers_in_spawn_rooms": true,
		"max_drawers_in_spawn_room": 1,
		"isolate_briefcase_from_objectives": true,
		"min_total_gadgets": 14,
		"max_total_gadgets": 18,
		"spring_min": 2,
		"spring_max": 7,
		"bomb_min": 2,
		"bomb_max": 7,
		"tripwire_min": 2,
		"tripwire_max": 7,
		"dart_gun_min": 1,
		"dart_gun_max": 5,
		"floor_buckets_min": 6,
		"floor_buckets_max": 8,
		"cover_props_count": 6
	},
	4: {
		"starting_clock_seconds": 240.0,
		"drawer_first_search_bonus_seconds": 12.0,
		"min_containers": 36,
		"max_containers": 44,
		"max_drawers_per_room": 3,
		"allow_drawers_in_spawn_rooms": true,
		"max_drawers_in_spawn_room": 1,
		"isolate_briefcase_from_objectives": true,
		"min_total_gadgets": 18,
		"max_total_gadgets": 22,
		"spring_min": 3,
		"spring_max": 8,
		"bomb_min": 3,
		"bomb_max": 8,
		"tripwire_min": 3,
		"tripwire_max": 8,
		"dart_gun_min": 1,
		"dart_gun_max": 6,
		"floor_buckets_min": 8,
		"floor_buckets_max": 10,
		"cover_props_count": 6
	}
}

var _player_count_presets: Dictionary = {}


func _ensure_presets_initialized() -> void:
	if _player_count_presets.is_empty():
		for p_count in PLAYER_COUNT_SPAWNER_PRESETS.keys():
			_player_count_presets[p_count] = (PLAYER_COUNT_SPAWNER_PRESETS[p_count] as Dictionary).duplicate(true)


func _ready() -> void:
	if not Engine.is_editor_hint():
		load_user_settings()


## Returns the DPI-normalized radians-per-pixel sensitivity so 1600 DPI and 800 DPI feel identical at 1.0x multiplier.
func get_effective_mouse_sensitivity() -> float:
	var safe_dpi: float = maxf(float(mouse_dpi), 100.0)
	return base_mouse_sensitivity_800dpi * (REFERENCE_DPI / safe_dpi) * mouse_sensitivity_multiplier


func set_mouse_settings(new_dpi: int, new_multiplier: float, persist: bool = true) -> void:
	mouse_dpi = clampi(new_dpi, 200, 12800)
	mouse_sensitivity_multiplier = clampf(new_multiplier, 0.10, 4.00)
	if persist:
		save_user_settings()
	mouse_settings_changed.emit(get_effective_mouse_sensitivity())


func save_user_settings(path: String = USER_SETTINGS_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("mouse", "dpi", mouse_dpi)
	cfg.set_value("mouse", "sensitivity_multiplier", mouse_sensitivity_multiplier)
	return cfg.save(path)


func load_user_settings(path: String = USER_SETTINGS_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	mouse_dpi = int(cfg.get_value("mouse", "dpi", 800))
	mouse_sensitivity_multiplier = float(cfg.get_value("mouse", "sensitivity_multiplier", 1.0))
	mouse_settings_changed.emit(get_effective_mouse_sensitivity())
	return true


func get_spawner_config_dict() -> Dictionary:
	return {
		"active_preset_players": spawner_active_preset_players,
		"auto_preset_by_player_count": spawner_auto_preset_by_player_count,
		"starting_clock_seconds": starting_clock_seconds,
		"drawer_first_search_bonus_seconds": drawer_first_search_bonus_seconds,
		"min_containers": spawner_min_containers,
		"max_containers": spawner_max_containers,
		"min_drawers": spawner_min_containers,
		"max_drawers": spawner_max_containers,
		"max_drawers_per_room": spawner_max_drawers_per_room,
		"allow_drawers_in_spawn_rooms": spawner_allow_drawers_in_spawn_rooms,
		"max_drawers_in_spawn_room": spawner_max_drawers_in_spawn_room,
		"isolate_briefcase_from_objectives": spawner_isolate_briefcase_from_objectives,
		"min_total_gadgets": spawner_min_total_gadgets,
		"max_total_gadgets": spawner_max_total_gadgets,
		"spring_min": spawner_spring_min,
		"spring_max": spawner_spring_max,
		"bomb_min": spawner_bomb_min,
		"bomb_max": spawner_bomb_max,
		"tripwire_min": spawner_tripwire_min,
		"tripwire_max": spawner_tripwire_max,
		"dart_gun_min": spawner_dart_gun_min,
		"dart_gun_max": spawner_dart_gun_max,
		"floor_buckets_min": spawner_floor_buckets_min,
		"floor_buckets_max": spawner_floor_buckets_max,
		"cover_props_count": spawner_cover_props_count
	}


func get_preset_config_dict(player_count: int) -> Dictionary:
	_ensure_presets_initialized()
	var key: int = clampi(player_count, 2, 4)
	return (_player_count_presets[key] as Dictionary).duplicate(true)


func apply_player_count_preset(player_count: int) -> void:
	_ensure_presets_initialized()
	var key: int = clampi(player_count, 2, 4)
	spawner_active_preset_players = key
	apply_spawner_config_dict(get_preset_config_dict(key))


func apply_spawner_config_dict(cfg_dict: Dictionary) -> void:
	_ensure_presets_initialized()
	if cfg_dict.has("active_preset_players"):
		spawner_active_preset_players = clampi(int(cfg_dict["active_preset_players"]), 2, 4)
	if cfg_dict.has("auto_preset_by_player_count"):
		spawner_auto_preset_by_player_count = bool(cfg_dict["auto_preset_by_player_count"])
	if cfg_dict.has("starting_clock_seconds"):
		starting_clock_seconds = clampf(float(cfg_dict["starting_clock_seconds"]), 30.0, 900.0)
	if cfg_dict.has("drawer_first_search_bonus_seconds"):
		drawer_first_search_bonus_seconds = clampf(float(cfg_dict["drawer_first_search_bonus_seconds"]), 0.0, 120.0)

	if cfg_dict.has("min_containers"):
		spawner_min_containers = maxi(int(cfg_dict["min_containers"]), 5)
	elif cfg_dict.has("min_drawers"):
		spawner_min_containers = maxi(int(cfg_dict["min_drawers"]), 5)
	if cfg_dict.has("max_containers"):
		spawner_max_containers = maxi(int(cfg_dict["max_containers"]), spawner_min_containers)
	elif cfg_dict.has("max_drawers"):
		spawner_max_containers = maxi(int(cfg_dict["max_drawers"]), spawner_min_containers)
	else:
		spawner_max_containers = maxi(spawner_max_containers, spawner_min_containers)
	spawner_min_drawers = spawner_min_containers
	spawner_max_drawers = spawner_max_containers
	spawner_searchable_drawers_count = spawner_max_containers

	if cfg_dict.has("max_drawers_per_room"):
		spawner_max_drawers_per_room = clampi(int(cfg_dict["max_drawers_per_room"]), 1, 8)
	if cfg_dict.has("allow_drawers_in_spawn_rooms"):
		spawner_allow_drawers_in_spawn_rooms = bool(cfg_dict["allow_drawers_in_spawn_rooms"])
	if cfg_dict.has("max_drawers_in_spawn_room"):
		spawner_max_drawers_in_spawn_room = clampi(int(cfg_dict["max_drawers_in_spawn_room"]), 0, 8)
	if cfg_dict.has("isolate_briefcase_from_objectives"):
		spawner_isolate_briefcase_from_objectives = bool(cfg_dict["isolate_briefcase_from_objectives"])

	if cfg_dict.has("min_total_gadgets"):
		spawner_min_total_gadgets = maxi(int(cfg_dict["min_total_gadgets"]), 0)
	if cfg_dict.has("max_total_gadgets"):
		spawner_max_total_gadgets = maxi(int(cfg_dict["max_total_gadgets"]), spawner_min_total_gadgets)
	else:
		spawner_max_total_gadgets = maxi(spawner_max_total_gadgets, spawner_min_total_gadgets)

	if cfg_dict.has("spring_min"):
		spawner_spring_min = maxi(int(cfg_dict["spring_min"]), 0)
	if cfg_dict.has("spring_max"):
		spawner_spring_max = maxi(int(cfg_dict["spring_max"]), spawner_spring_min)
	else:
		spawner_spring_max = maxi(spawner_spring_max, spawner_spring_min)

	if cfg_dict.has("bomb_min"):
		spawner_bomb_min = maxi(int(cfg_dict["bomb_min"]), 0)
	if cfg_dict.has("bomb_max"):
		spawner_bomb_max = maxi(int(cfg_dict["bomb_max"]), spawner_bomb_min)
	else:
		spawner_bomb_max = maxi(spawner_bomb_max, spawner_bomb_min)

	if cfg_dict.has("tripwire_min"):
		spawner_tripwire_min = maxi(int(cfg_dict["tripwire_min"]), 0)
	if cfg_dict.has("tripwire_max"):
		spawner_tripwire_max = maxi(int(cfg_dict["tripwire_max"]), spawner_tripwire_min)
	else:
		spawner_tripwire_max = maxi(spawner_tripwire_max, spawner_tripwire_min)

	if cfg_dict.has("dart_gun_min"):
		spawner_dart_gun_min = maxi(int(cfg_dict["dart_gun_min"]), 0)
	if cfg_dict.has("dart_gun_max"):
		spawner_dart_gun_max = maxi(int(cfg_dict["dart_gun_max"]), spawner_dart_gun_min)
	else:
		spawner_dart_gun_max = maxi(spawner_dart_gun_max, spawner_dart_gun_min)

	if cfg_dict.has("floor_buckets_min"):
		spawner_floor_buckets_min = maxi(int(cfg_dict["floor_buckets_min"]), 0)
	if cfg_dict.has("floor_buckets_max"):
		spawner_floor_buckets_max = maxi(int(cfg_dict["floor_buckets_max"]), spawner_floor_buckets_min)
	else:
		spawner_floor_buckets_max = maxi(spawner_floor_buckets_max, spawner_floor_buckets_min)
	spawner_floor_buckets_count = spawner_floor_buckets_max

	if cfg_dict.has("cover_props_count"):
		spawner_cover_props_count = maxi(int(cfg_dict["cover_props_count"]), 0)

	var preset_key: int = clampi(spawner_active_preset_players, 2, 4)
	_player_count_presets[preset_key] = {
		"starting_clock_seconds": starting_clock_seconds,
		"drawer_first_search_bonus_seconds": drawer_first_search_bonus_seconds,
		"min_containers": spawner_min_containers,
		"max_containers": spawner_max_containers,
		"max_drawers_per_room": spawner_max_drawers_per_room,
		"allow_drawers_in_spawn_rooms": spawner_allow_drawers_in_spawn_rooms,
		"max_drawers_in_spawn_room": spawner_max_drawers_in_spawn_room,
		"isolate_briefcase_from_objectives": spawner_isolate_briefcase_from_objectives,
		"min_total_gadgets": spawner_min_total_gadgets,
		"max_total_gadgets": spawner_max_total_gadgets,
		"spring_min": spawner_spring_min,
		"spring_max": spawner_spring_max,
		"bomb_min": spawner_bomb_min,
		"bomb_max": spawner_bomb_max,
		"tripwire_min": spawner_tripwire_min,
		"tripwire_max": spawner_tripwire_max,
		"dart_gun_min": spawner_dart_gun_min,
		"dart_gun_max": spawner_dart_gun_max,
		"floor_buckets_min": spawner_floor_buckets_min,
		"floor_buckets_max": spawner_floor_buckets_max,
		"cover_props_count": spawner_cover_props_count
	}

	spawner_settings_changed.emit()


func reset_spawner_defaults(player_count: int = 0) -> void:
	_ensure_presets_initialized()
	if player_count == -1:
		for p_key in PLAYER_COUNT_SPAWNER_PRESETS.keys():
			_player_count_presets[p_key] = (PLAYER_COUNT_SPAWNER_PRESETS[p_key] as Dictionary).duplicate(true)
		apply_spawner_config_dict(get_preset_config_dict(spawner_active_preset_players))
		return
	var target_preset: int = clampi(player_count if player_count > 0 else spawner_active_preset_players, 2, 4)
	var default_dict: Dictionary = (PLAYER_COUNT_SPAWNER_PRESETS[target_preset] as Dictionary).duplicate(true)
	_player_count_presets[target_preset] = default_dict
	spawner_active_preset_players = target_preset
	apply_spawner_config_dict(default_dict)


func compute_final_move_speed(stance: int, has_briefcase: bool, is_charging_club: bool, club_charge_progress: float = 1.0) -> float:
	if stance == Stance.DRAWER_LOCK or stance == Stance.KO:
		return 0.0

	var base_speed: float = walk_speed
	match stance:
		Stance.WALK:
			base_speed = walk_speed
		Stance.SPRINT:
			# Charging Club overrides Sprint (Doc 2 §2.B)
			base_speed = walk_speed if is_charging_club else sprint_speed
		Stance.CROUCH:
			base_speed = crouch_speed

	var hand_mult: float = speed_mult_briefcase if has_briefcase else speed_mult_normal
	var action_mult: float = lerpf(speed_mult_normal, speed_mult_club_charge, clampf(club_charge_progress, 0.0, 1.0)) if is_charging_club else speed_mult_normal
	var final_speed: float = base_speed * hand_mult * action_mult
	if is_charging_club:
		final_speed = maxf(final_speed, walk_speed * speed_mult_club_charge * hand_mult)
	return final_speed


func get_effective_bomb_fuse_range() -> Vector2:
	if debug_long_bomb_fuse:
		return Vector2(debug_long_bomb_fuse_seconds, debug_long_bomb_fuse_seconds)
	return Vector2(time_bomb_fuse_min, time_bomb_fuse_max)
