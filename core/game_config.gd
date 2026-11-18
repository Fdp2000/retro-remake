@tool
extends Node

## Centralized gameplay tunables and architectural constants (AGENTS.md §1).
## All [TUNABLE] baselines from Master GDD v3.2 and Docs 2–7 are exposed here.

signal mouse_settings_changed(effective_sensitivity: float)

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
@export var crouch_speed: float = 3.4
@export var jump_velocity: float = 4.2
@export var standing_capsule_height: float = 1.8
@export var crouched_capsule_height: float = 1.0
@export var standing_neck_y: float = 1.6
@export var crouched_neck_y: float = 0.85
@export var stance_transition_speed: float = 12.0
@export var interact_reach: float = 2.2

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
@export var door_bucket_ajar_angle_deg: float = 5.0
@export var door_bucket_release_angle_deg: float = 25.0
@export var bucket_hit_radius: float = 1.2
@export var bucket_max_safe_reach: float = 1.8

@export var drawer_fast_slam_duration: float = 0.22
@export var drawer_slow_peek_hold_time: float = 2.80
@export var drawer_close_duration: float = 0.30
@export var top_down_cam_lerp_duration: float = 0.65

# ==========================================
# Doc 4: The 5-Trap & Gadget Ecosystem [TUNABLE]
# ==========================================
@export_group("Traps & Gadgets")
@export var trap_setup_hold_time: float = 0.80
@export var trap_steal_hold_time: float = 1.00
@export var tripwire_height: float = 0.35
@export var time_bomb_fuse_min: float = 2.5
@export var time_bomb_fuse_max: float = 4.0
@export var time_bomb_throw_distance: float = 9.0
@export var time_bomb_throw_speed: float = 9.5
@export var time_bomb_blast_radius: float = 5.0
@export var time_bomb_self_catch_ignore_time: float = 0.25
@export var dvd_reticle_speed_px: float = 320.0

# ==========================================
# Doc 5: Club Combat QTE & 15s Ragdoll KO [TUNABLE]
# ==========================================
@export_group("Combat & Ragdoll KO")
@export var club_quick_tap_threshold: float = 0.20
@export var club_feint_cooldown: float = 0.40
@export var club_whiff_recovery_time: float = 0.60
@export var club_charge_fill_duration: float = 1.60
@export var club_green_zone_width: float = 0.18
@export var club_green_zone_min_start: float = 0.55
@export var club_green_zone_max_start: float = 0.75
@export var club_melee_range: float = 2.0
@export var club_overcharge_stumble_duration: float = 2.0

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

@export var anti_camp_warning_seconds: float = 15.0
@export var anti_camp_sneeze_seconds: float = 20.0
@export var anti_camp_repeat_seconds: float = 15.0

# ==========================================
# Doc 7: Modular Greybox Level & Spawner [TUNABLE]
# ==========================================
@export_group("Level & Match Randomizer")
@export var room_dimensions: Vector3 = Vector3(6.0, 3.2, 6.0)
@export var grid_dimensions: Vector2i = Vector2i(3, 3)
@export var spawner_searchable_drawers_count: int = 12
@export var spawner_cover_props_count: int = 6
@export var spawner_floor_buckets_count: int = 3


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


func compute_final_move_speed(stance: int, has_briefcase: bool, is_charging_club: bool) -> float:
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
	var action_mult: float = speed_mult_club_charge if is_charging_club else speed_mult_normal
	return base_speed * hand_mult * action_mult
