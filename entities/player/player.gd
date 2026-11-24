extends CharacterBody3D

## SpyCharacter Controller — Dual Movement, Stances & 3-Slot Inner Trenchcoat Jacket Inventory (Doc 2 v1.2).
## Client-authoritative FPS locomotion + Server-authoritative Left-Hand & 3-Slot Jacket Inventory.

enum SpyRole {
	SPY_WHITE = 1,
	SPY_BLACK = 2,
	SPY_GREEN = 1,
	SPY_PURPLE = 2,
	SPY_BLUE = 3,
	SPY_RED = 4
}

const INTERACTIVE_LADDER := preload("res://scenes/BuildingComplex3/interactive_ladder.gd")
const LADDER_CLIMB_SPEED := 2.4
const LADDER_AUTO_MOUNT_DEPTH := 1.14
const LADDER_LOOK_DEAD_ZONE := 0.10
const LADDER_LANDING_CLEARANCE := 0.06

const COLOR_SPY_WHITE: Color = Color(0.92, 0.92, 0.92)
const COLOR_SPY_BLACK: Color = Color(0.12, 0.12, 0.12)
const PICKUP_SCENE: PackedScene = preload("res://entities/props/world_item_pickup.tscn")
const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const BRIEFCASE_BUILDER = preload("res://entities/props/briefcase_visual_builder.gd")
const SHOVE_PHYSICS = preload("res://entities/props/container_shove_physics.gd")
const TOP_DOWN_UI_SCRIPT = preload("res://ui/top_down_container_ui.gd")
const DVD_RETICLE_UI_SCRIPT = preload("res://ui/dvd_dart_reticle_ui.gd")
const CLUB_QTE_UI_SCRIPT = preload("res://ui/club_qte_bar_ui.gd")
const CLUB_HIT_GIZMO_SCRIPT = preload("res://entities/player/club_hit_gizmo.gd")
const WATCH_BLUFF_UI_SCRIPT = preload("res://ui/spy_watch_bluff_ui.gd")
const CRT_REPLAY_UI_SCRIPT = preload("res://ui/crt_replay_monitor_ui.gd")
const VM_TUNER_UI_SCRIPT = preload("res://ui/viewmodel_offset_tuner_ui.gd")
const RAGDOLL_CTRL_SCRIPT = preload("res://entities/player/spy_ragdoll_controller.gd")
const TRIPWIRE_SCRIPT = preload("res://entities/traps/tripwire_trap.gd")
const TRIPWIRE_PLACEMENT_SCRIPT = preload("res://entities/player/tripwire_placement_controller.gd")
const THROWN_BOMB_SCRIPT = preload("res://entities/traps/thrown_time_bomb.gd")
const TAP_RELEASE_THRESHOLD: float = 0.20
const PELVIS_SYNC_INTERVAL: float = 0.20

# ==========================================
# Replicated Properties (MultiplayerSynchronizer — Client Locomotion/Stance Authority)
# ==========================================
@export var spy_role: int = 0:
	set(value):
		spy_role = value
		_update_mesh_color()

@export var head_pitch: float = 0.0

@export var stance_state: int = 0: # GameConfig.Stance
	set(value):
		stance_state = value
		_apply_stance_collision_and_visuals()
		_update_hud_status()

@export var is_climbing_ladder: bool = false
var _climb_vertical_speed: float = 0.0

# ==========================================
# Server-Authoritative Inventory Facade (Backed by SpyInventoryComponent)
# ==========================================
var left_hand_item_id: String:
	get:
		return _inv().left_hand_item_id
	set(value):
		_inv().left_hand_item_id = value.to_upper() if not value.is_empty() else "NONE"
		_refresh_hand_and_back_sockets()
		_update_hud_status()

var right_hand_item_id: String:
	get:
		return _inv().get_active_right_item_id()
	set(value):
		var id: String = value.to_upper() if not value.is_empty() else "NONE"
		var inv: SpyInventoryComponent = _inv()
		if id == "CLUB":
			inv.right_hand_mode = SpyInventoryComponent.RightHandMode.CLUB
		elif id == "LIVE_BOMB":
			inv.right_hand_mode = SpyInventoryComponent.RightHandMode.LIVE_BOMB
		else:
			inv.right_hand_mode = SpyInventoryComponent.RightHandMode.JACKET_SLOT
			var slot_idx: int = clampi(inv.active_jacket_slot, 0, SpyInventoryComponent.JACKET_SLOT_COUNT - 1)
			inv.jacket_slots[slot_idx] = id
		_refresh_hand_and_back_sockets()
		_update_hud_status()

var briefcase_objectives: Array[String]:
	get:
		return _inv().briefcase_objectives
	set(value):
		_inv().briefcase_objectives = value
		_update_hud_status()

var briefcase_item_positions: Dictionary:
	get:
		return _inv().briefcase_item_positions

var briefcase_bomb_norm_pos: Vector2:
	get:
		return _inv().briefcase_bomb_norm_pos

var jacket_slots: Array[String]:
	get:
		return _inv().jacket_slots
	set(value):
		_inv().jacket_slots = value
		_refresh_hand_and_back_sockets()
		_update_hud_status()

var active_jacket_slot: int:
	get:
		return _inv().active_jacket_slot
	set(value):
		_inv().active_jacket_slot = clampi(value, 0, SpyInventoryComponent.JACKET_SLOT_COUNT - 1)
		_refresh_hand_and_back_sockets()
		_update_hud_status()

var right_hand_mode: int:
	get:
		return _inv().right_hand_mode
	set(value):
		_inv().right_hand_mode = value
		_refresh_hand_and_back_sockets()
		_update_hud_status()

var is_charging_club: bool:
	get:
		return _inv().is_charging_club
	set(value):
		_inv().is_charging_club = value
		_refresh_hand_and_back_sockets()
		_update_hud_status()

@export var speed: float = 4.5
@export var jump_velocity: float = 4.2
@export var mouse_sensitivity: float = 0.0022

# ==========================================
# Node References
# ==========================================
@onready var inventory: SpyInventoryComponent = get_node_or_null("Inventory") as SpyInventoryComponent
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var door_bash_detector: Area3D = get_node_or_null("DoorBashDetector")
@onready var visual_rig: Node3D = get_node_or_null("VisualRig")
@onready var back_club_socket: Marker3D = get_node_or_null("VisualRig/BackClubSocket")
@onready var spy_wearable_socket: Marker3D = get_node_or_null("VisualRig/SpyWearableSocket")
@onready var tp_left_hand_socket: Marker3D = get_node_or_null("VisualRig/ThirdPersonLeftHandSocket")
@onready var tp_right_hand_socket: Marker3D = get_node_or_null("VisualRig/ThirdPersonRightHandSocket")
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var left_hand_socket: Marker3D = get_node_or_null("Head/Camera3D/LeftHandSocket")
@onready var right_hand_socket: Marker3D = get_node_or_null("Head/Camera3D/RightHandSocket")
@onready var hud: CanvasLayer = $HUD
@onready var prompt_label: Label = $HUD/PromptLabel
@onready var hold_progress_bar: ProgressBar = get_node_or_null("HUD/HoldProgressBar")
@onready var left_hand_label: Label = get_node_or_null("HUD/StatusBar/HBox/LeftHandLabel")
@onready var stance_label: Label = get_node_or_null("HUD/StatusBar/HBox/StanceLabel")
@onready var right_hand_label: Label = get_node_or_null("HUD/StatusBar/HBox/RightHandLabel")
@onready var clock_label: Label = get_node_or_null("HUD/ClockPanel/ClockLabel") as Label
@onready var bonus_toast_label: Label = get_node_or_null("HUD/BonusToastLabel") as Label

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# Puppet smoothing variables
var _requested_ladder: INTERACTIVE_LADDER
var _active_ladder: INTERACTIVE_LADDER
var _ladder_side := 1.0
var _ladder_level_forward := 1
var _last_dismounted_ladder: INTERACTIVE_LADDER

var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _initial_pos_set: bool = false
var _initial_yaw_set: bool = false

# Interaction Tap vs Hold tracking
var _interact_key_down: bool = false
var _interact_hold_elapsed: float = 0.0
var _interact_hold_triggered: bool = false
var _interact_target: Object = null

# Container View, KO Recovery & Clock HUD
var active_container: Node = null
var _container_ui: TopDownContainerUI = null
var _dvd_reticle_ui: DVDDartReticleUI = null
var _club_qte_ui: ClubQTEBarUI = null
var _club_hit_gizmo: ClubHitGizmo = null
var _watch_bluff_ui: SpyWatchBluffUI = null
var _crt_replay_ui: CRTReplayMonitorUI = null
var _vm_tuner_ui: VM_TUNER_UI_SCRIPT = null
var _tp_preview_camera: Camera3D = null
var _tp_preview_active: bool = false
var _tp_sim_motion: String = "IDLE"
var _ragdoll_ctrl: SpyRagdollController = null
var _back_club_bone_offset: Transform3D = Transform3D.IDENTITY
var _wearable_bone_offset: Transform3D = Transform3D.IDENTITY
var _socket_offsets_calibrated: bool = false
var _tripwire_ctrl: TripwirePlacementController = null
var _crt_body_visual_layer: int = 1
var _camera_tween: Tween = null
var _bonus_toast_timer: float = 0.0
var ko_remaining_seconds: float = 0.0
var is_clock_eliminated: bool = false
var wakeup_immunity_remaining: float = 0.0
var _pelvis_sync_accum: float = 0.0
var _last_ko_reason: String = ""
var _last_ko_impulse: Vector3 = Vector3.ZERO
var _drag_3d_active: bool = false
var _drag_3d_role: String = ""
var _drag_3d_clutter_idx: int = -1
var _drag_3d_item_id: String = ""
var _drag_3d_node: Node3D = null
var _drag_3d_plane_y: float = 0.0
var _drag_3d_offset_xz: Vector2 = Vector2.ZERO
var _drag_3d_start_screen_pos: Vector2 = Vector2.ZERO
var _drag_3d_moved: bool = false
var _drag_3d_samples: Array = []
var _active_3d_slides: Dictionary = {} # key -> {"container": Node, "role": String, "clutter_idx": int, "item_id": String, "pos": Vector2, "vel": Vector2, "bounds_min_v": Vector2, "bounds_max_v": Vector2, "bounce_sfx_cd": float}
var _drawer_focus_just_entered: bool = false
var _drawer_e_held: bool = false
var _drawer_e_hold_elapsed: float = 0.0
var _interact_steal_bucket: bool = false
var _interact_step_push_want_open: int = -1

# Doc 4, 5 & 6 Combat, Trap Setup, Hot-Potato Bomb & Anti-Camp State
var live_bomb_remaining: float = 0.0
var live_bomb_owner_peer_id: int = 0
var club_overcharge_stumble_remaining: float = 0.0
var _club_feint_cooldown: float = 0.0
var _club_whiff_recovery: float = 0.0
var _club_charge_exit_lerp_active: bool = false
var _club_charge_exit_lerp_elapsed: float = 0.0
var _club_charge_exit_start_speed: float = 0.0
var _lmb_trap_hold_active: bool = false
var _lmb_trap_hold_elapsed: float = 0.0
var _lmb_trap_mode: String = ""
var _lmb_trap_target: Object = null
var _lmb_trap_bucket_other_side: bool = false
var anti_camp_timer: float = 0.0
var anti_camp_sniffle_warned: bool = false
var _last_room_key: String = ""
var _action_counter: int = 0

# Footstep & airborne tracking
var _footstep_timer: float = 0.0
var _was_on_floor: bool = true
var _sens_toast_timer: float = 0.0
var _drop_counter: int = 0

# First-person viewmodel procedural animation state
const _VM_LEFT_BASE_POS: Vector3 = Vector3(-0.34, -0.26, -0.52)
const _VM_RIGHT_BASE_POS: Vector3 = Vector3(0.34, -0.26, -0.52)
const _VM_ARM_SCALE: Vector3 = Vector3(0.76, 0.76, 0.76)
const _VM_ARM_LEFT_OFFSET: Vector3 = Vector3(-0.045, -0.02, 0.03)
const _VM_ARM_RIGHT_OFFSET: Vector3 = Vector3(0.045, -0.02, 0.03)
const _HAND_POSES_OVERRIDE_PATH: String = "res://entities/player/hand_poses_override.json"

var _vm_left_base_pos: Vector3 = _VM_LEFT_BASE_POS
var _vm_right_base_pos: Vector3 = _VM_RIGHT_BASE_POS
var _vm_arm_scale: Vector3 = _VM_ARM_SCALE
var _vm_arm_left_offset: Vector3 = _VM_ARM_LEFT_OFFSET
var _vm_arm_right_offset: Vector3 = _VM_ARM_RIGHT_OFFSET
var _runtime_hand_item_poses: Dictionary = {}
var _runtime_tp_hand_item_poses: Dictionary = {}
var _runtime_poses_loaded: bool = false

# Custom per-item offsets in hand-local space (authored for Right hand; Left hand mirrors X, Yaw-Y, and Roll-Z automatically).
# Optional "left_pos"/"left_rot_deg"/"right_pos"/"right_rot_deg" keys override mirroring per side if needed.
const _HAND_ITEM_POSES: Dictionary = {
	"BRIEFCASE": {
		"pos": Vector3(-0.02, -0.19, -0.03),
		"rot_deg": Vector3(8.0, 78.0, -8.0),
		"scale": Vector3(0.60, 0.60, 0.60)
	},
	"KEY": {
		"pos": Vector3(-0.025, 0.02, -0.07),
		"rot_deg": Vector3(18.0, 16.0, -28.0),
		"scale": Vector3(0.95, 0.95, 0.95)
	},
	"MONEY": {
		"pos": Vector3(-0.035, 0.015, -0.04),
		"rot_deg": Vector3(16.0, 22.0, -12.0),
		"scale": Vector3(0.90, 0.90, 0.90)
	},
	"PASSPORT": {
		"pos": Vector3(-0.03, 0.02, -0.06),
		"rot_deg": Vector3(48.0, 24.0, -18.0),
		"scale": Vector3(0.95, 0.95, 0.95)
	},
	"PLANS": {
		"pos": Vector3(-0.04, 0.03, -0.07),
		"rot_deg": Vector3(52.0, 20.0, -14.0),
		"scale": Vector3(0.85, 0.85, 0.85)
	},
	"CLUB": {
		"pos": Vector3(-0.015, 0.15, -0.03),
		"rot_deg": Vector3(-22.0, 8.0, 10.0),
		"scale": Vector3(0.92, 0.92, 0.92)
	},
	"DART_GUN": {
		"pos": Vector3(-0.015, 0.065, -0.07),
		"rot_deg": Vector3(3.0, 4.0, 0.0),
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	"BOMB": {
		"pos": Vector3(-0.03, 0.01, -0.05),
		"rot_deg": Vector3(12.0, 15.0, -6.0),
		"scale": Vector3(0.85, 0.85, 0.85)
	},
	"LIVE_BOMB": {
		"pos": Vector3(-0.03, 0.025, -0.06),
		"rot_deg": Vector3(14.0, 12.0, -6.0),
		"scale": Vector3(0.85, 0.85, 0.85)
	},
	"BUCKET": {
		"pos": Vector3(-0.03, -0.04, -0.06),
		"rot_deg": Vector3(10.0, 15.0, -10.0),
		"scale": Vector3(0.72, 0.72, 0.72)
	},
	"TRIPWIRE": {
		"pos": Vector3(-0.02, 0.02, -0.05),
		"rot_deg": Vector3(18.0, 35.0, -10.0),
		"scale": Vector3(0.95, 0.95, 0.95)
	},
	"SPRING": {
		"pos": Vector3(-0.025, 0.015, -0.05),
		"rot_deg": Vector3(16.0, 18.0, -8.0),
		"scale": Vector3(0.88, 0.88, 0.88)
	}
}

# Third-person outside-view carry offsets in hand.R bone-local space (+Y = down along fingers, +Z = forward, -X = inward palm).
# Left hand (hand.L) automatically mirrors X, Yaw-Y, and Roll-Z.
const _TP_HAND_ITEM_POSES: Dictionary = {
	"BRIEFCASE": {
		"pos": Vector3(0.05, 0.42, 0.0),
		"rot_deg": Vector3(180.0, 90.0, 0.0),
		"scale": Vector3(0.75, 0.75, 0.75)
	},
	"KEY": {
		"pos": Vector3(-0.02, 0.19, 0.05),
		"rot_deg": Vector3(165.0, 15.0, 0.0),
		"scale": Vector3(0.95, 0.95, 0.95)
	},
	"MONEY": {
		"pos": Vector3(-0.025, 0.18, 0.04),
		"rot_deg": Vector3(165.0, 15.0, 0.0),
		"scale": Vector3(0.90, 0.90, 0.90)
	},
	"PASSPORT": {
		"pos": Vector3(-0.025, 0.19, 0.04),
		"rot_deg": Vector3(165.0, 20.0, 0.0),
		"scale": Vector3(0.95, 0.95, 0.95)
	},
	"PLANS": {
		"pos": Vector3(-0.03, 0.19, 0.04),
		"rot_deg": Vector3(165.0, 20.0, 0.0),
		"scale": Vector3(0.85, 0.85, 0.85)
	},
	"CLUB": {
		"pos": Vector3(-0.02, 0.17, 0.14),
		"rot_deg": Vector3(110.0, 0.0, 0.0),
		"scale": Vector3(0.88, 0.88, 0.88)
	},
	"DART_GUN": {
		"pos": Vector3(-0.02, 0.16, 0.04),
		"rot_deg": Vector3(165.0, 0.0, 0.0),
		"scale": Vector3(0.95, 0.95, 0.95)
	},
	"BOMB": {
		"pos": Vector3(0.02, 0.24, 0.03),
		"rot_deg": Vector3(180.0, 0.0, 0.0),
		"scale": Vector3(0.85, 0.85, 0.85)
	},
	"LIVE_BOMB": {
		"pos": Vector3(0.02, 0.24, 0.03),
		"rot_deg": Vector3(180.0, 0.0, 0.0),
		"scale": Vector3(0.85, 0.85, 0.85)
	},
	"BUCKET": {
		"pos": Vector3(0.06, 0.28, 0.02),
		"rot_deg": Vector3(180.0, 0.0, 0.0),
		"scale": Vector3(0.75, 0.75, 0.75)
	},
	"TRIPWIRE": {
		"pos": Vector3(0.0, 0.19, 0.04),
		"rot_deg": Vector3(180.0, 35.0, 0.0),
		"scale": Vector3(0.90, 0.90, 0.90)
	},
	"SPRING": {
		"pos": Vector3(0.01, 0.20, 0.03),
		"rot_deg": Vector3(180.0, 0.0, 0.0),
		"scale": Vector3(0.85, 0.85, 0.85)
	}
}
var _vm_idle_time: float = 0.0
var _vm_walk_phase: float = 0.0
var _vm_sway_vel: Vector2 = Vector2.ZERO
var _vm_sway_pos: Vector2 = Vector2.ZERO
var _vm_left_equip: float = 0.0
var _vm_right_equip: float = 0.0
var _vm_last_left_id: String = "NONE"
var _vm_last_right_id: String = "NONE"
var _vm_club_charge_blend: float = 0.0
var _vm_dart_aim_blend: float = 0.0
var _vm_sprint_blend: float = 0.0
var _vm_right_action: String = ""
var _vm_right_action_timer: float = 0.0
var _vm_right_action_dur: float = 0.0


func _enter_tree() -> void:
	add_to_group("spy_players")
	if name.is_valid_int():
		var pid: int = name.to_int()
		var assigned_role: int = MatchManager.get_peer_role(pid) if (MatchManager != null and MatchManager.has_method("get_peer_role")) else 0
		if assigned_role > 0:
			spy_role = assigned_role
		elif spy_role <= 0:
			spy_role = SpyRole.SPY_GREEN if pid == 1 else SpyRole.SPY_PURPLE
	if Engine.is_editor_hint():
		return
	set_multiplayer_authority(name.to_int())
	_target_position = position
	_target_yaw = rotation.y


func _ready() -> void:
	add_to_group("spy_players")
	collision_layer = GameConfig.LAYER_PLAYER if GameConfig != null else 4
	collision_mask = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_PLAYER) if GameConfig != null else 5

	if raycast != null:
		raycast.add_exception(self)
		raycast.target_position = Vector3(0.0, 0.0, -(GameConfig.interact_reach if GameConfig != null else 2.2))

	if door_bash_detector != null:
		door_bash_detector.body_entered.connect(_on_door_bash_body_entered)
		door_bash_detector.area_entered.connect(_on_door_bash_area_entered)

	_update_mesh_color()
	_clear_legacy_wearable_placeholder()
	_refresh_hand_and_back_sockets()
	_apply_stance_collision_and_visuals()
	_update_hud_status()

	if GameConfig != null:
		speed = GameConfig.walk_speed
		jump_velocity = GameConfig.jump_velocity
		mouse_sensitivity = GameConfig.get_effective_mouse_sensitivity()

	if MatchManager != null and not MatchManager.spy_eliminated_by_clock.is_connected(_on_match_spy_eliminated_by_clock):
		MatchManager.spy_eliminated_by_clock.connect(_on_match_spy_eliminated_by_clock)

	# Never capture mouse or enable HUD/camera when instantiated inside the Godot Editor (e.g. during MCP tests)!
	if Engine.is_editor_hint():
		if camera != null:
			camera.current = false
		if hud != null:
			hud.visible = false
		set_process_input(false)
		set_process_unhandled_input(false)
		set_process(false)
		set_physics_process(false)
		return

	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		set_process_input(true)
		set_process_unhandled_input(true)
		set_process(true)
		hud.visible = true
		if _ragdoll_ctrl != null:
			_ragdoll_ctrl.set_first_person_local(true)
		apply_local_camera_cull_mask()
		_sync_camera_to_ragdoll_head()
		_sync_visual_rig_sockets_to_skeleton()
		ensure_overlay_uis()
		_ensure_tripwire_controller()
		if MatchManager != null:
			if not MatchManager.clock_updated.is_connected(_on_match_clock_updated):
				MatchManager.clock_updated.connect(_on_match_clock_updated)
			_on_match_clock_updated(name.to_int(), MatchManager.get_private_clock(name.to_int()), 0.0)
	else:
		camera.current = false
		if left_hand_socket != null:
			left_hand_socket.visible = false
		if right_hand_socket != null:
			right_hand_socket.visible = false
		set_process_input(false)
		set_process_unhandled_input(false)
		set_process(false)
		hud.visible = false
		if _ragdoll_ctrl != null:
			_ragdoll_ctrl.set_first_person_local(false)


func ensure_overlay_uis() -> void:
	var target_hud: CanvasLayer = hud if hud != null else get_node_or_null("HUD") as CanvasLayer
	if target_hud == null:
		return
	if _container_ui == null:
		_container_ui = TOP_DOWN_UI_SCRIPT.new()
		_container_ui.name = "TopDownContainerUI"
		target_hud.add_child(_container_ui)
	if _dvd_reticle_ui == null:
		_dvd_reticle_ui = DVD_RETICLE_UI_SCRIPT.new()
		_dvd_reticle_ui.name = "DVDDartReticleUI"
		target_hud.add_child(_dvd_reticle_ui)
	if _club_qte_ui == null:
		_club_qte_ui = CLUB_QTE_UI_SCRIPT.new()
		_club_qte_ui.name = "ClubQTEBarUI"
		target_hud.add_child(_club_qte_ui)
	if _watch_bluff_ui == null:
		_watch_bluff_ui = WATCH_BLUFF_UI_SCRIPT.new()
		_watch_bluff_ui.name = "SpyWatchBluffUI"
		target_hud.add_child(_watch_bluff_ui)
		_watch_bluff_ui.setup_for_player(self)
	if _crt_replay_ui == null:
		_crt_replay_ui = CRT_REPLAY_UI_SCRIPT.new()
		_crt_replay_ui.name = "CRTReplayMonitorUI"
		target_hud.add_child(_crt_replay_ui)
	if _crt_replay_ui != null:
		_crt_replay_ui.setup_for_owner(self)


# ==========================================
# Stance & Speed Stack (Doc 2 §2)
# ==========================================

func update_stance_from_inputs(wants_sprint: bool, wants_crouch: bool) -> int:
	var cfg_stance_lock: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	var cfg_stance_ko: int = GameConfig.Stance.KO if GameConfig != null else 4
	if stance_state == cfg_stance_lock or stance_state == cfg_stance_ko:
		return stance_state

	if wants_crouch:
		stance_state = GameConfig.Stance.CROUCH if GameConfig != null else 2
	elif wants_sprint and not is_charging_club and club_overcharge_stumble_remaining <= 0.0:
		stance_state = GameConfig.Stance.SPRINT if GameConfig != null else 1
	else:
		stance_state = GameConfig.Stance.WALK if GameConfig != null else 0
	return stance_state


func get_current_move_speed() -> float:
	var target_speed: float = speed * (0.30 if club_overcharge_stumble_remaining > 0.0 else 1.0)
	if GameConfig != null:
		var charge_progress: float = _club_qte_ui.get_charge_to_green_progress() if (_club_qte_ui != null and is_charging_club) else 1.0
		var base: float = GameConfig.compute_final_move_speed(
			stance_state,
			left_hand_item_id == "BRIEFCASE",
			is_charging_club,
			charge_progress
		)
		target_speed = base * (0.30 if club_overcharge_stumble_remaining > 0.0 else 1.0)
	if _club_charge_exit_lerp_active and not is_charging_club:
		var exit_dur: float = GameConfig.club_charge_exit_lerp_duration if GameConfig != null else 0.40
		var t: float = clampf(_club_charge_exit_lerp_elapsed / maxf(exit_dur, 0.001), 0.0, 1.0)
		var exp_t: float = (exp(3.0 * t) - 1.0) / (exp(3.0) - 1.0)
		return lerpf(_club_charge_exit_start_speed, target_speed, exp_t)
	return target_speed


func get_current_footstep_radius() -> float:
	if GameConfig == null:
		return 3.0
	match stance_state:
		GameConfig.Stance.CROUCH, GameConfig.Stance.DRAWER_LOCK, GameConfig.Stance.KO:
			return GameConfig.audio_radius_crouch # 0.0m (Silent)
		GameConfig.Stance.SPRINT:
			return GameConfig.audio_radius_sprint # 14.0m (Loud)
		_:
			return GameConfig.audio_radius_walk   # 3.0m (Quiet Walk)


func _apply_stance_collision_and_visuals() -> void:
	var is_crouching: bool = (stance_state == (GameConfig.Stance.CROUCH if GameConfig != null else 2))
	var target_h: float = (
		(GameConfig.crouched_capsule_height if GameConfig != null else 1.0)
		if is_crouching
		else (GameConfig.standing_capsule_height if GameConfig != null else 1.8)
	)
	var target_neck_y: float = (
		(GameConfig.crouched_neck_y if GameConfig != null else 0.85)
		if is_crouching
		else (GameConfig.standing_neck_y if GameConfig != null else 1.6)
	)

	var col_node: CollisionShape3D = collision_shape if collision_shape != null else get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_node != null and col_node.shape is CapsuleShape3D:
		if not col_node.has_meta("unique_shape"):
			col_node.shape = col_node.shape.duplicate()
			col_node.set_meta("unique_shape", true)
		var cap: CapsuleShape3D = col_node.shape as CapsuleShape3D
		cap.height = target_h
		col_node.position.y = target_h * 0.5

	var mesh_node: MeshInstance3D = mesh_instance if mesh_instance != null else get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_node != null:
		var scale_y: float = target_h / 1.8
		mesh_node.scale.y = scale_y
		mesh_node.position.y = target_h * 0.5

	var head_node: Node3D = head if head != null else get_node_or_null("Head") as Node3D
	if head_node != null and not is_inside_tree():
		head_node.position.y = target_neck_y


# ==========================================
# Left Hand & 3-Slot Inner Trenchcoat Jacket Inventory (Doc 2 §4.B)
# ==========================================

func _inv() -> SpyInventoryComponent:
	if inventory == null:
		inventory = get_node_or_null("Inventory") as SpyInventoryComponent
	if inventory == null:
		inventory = SpyInventoryComponent.new()
		inventory.name = "Inventory"
		add_child(inventory)
	return inventory


func _ensure_tripwire_controller() -> TripwirePlacementController:
	if _tripwire_ctrl == null or not is_instance_valid(_tripwire_ctrl):
		var existing: Node = get_node_or_null("TripwirePlacementController")
		if existing is TripwirePlacementController:
			_tripwire_ctrl = existing as TripwirePlacementController
		else:
			_tripwire_ctrl = TRIPWIRE_PLACEMENT_SCRIPT.new() as TripwirePlacementController
			_tripwire_ctrl.name = "TripwirePlacementController"
			add_child(_tripwire_ctrl)
	_tripwire_ctrl.setup(self)
	return _tripwire_ctrl


func handle_tripwire_cancel_input(is_rmb_pressed: bool, is_cancel_pressed: bool) -> bool:
	if _tripwire_ctrl == null or not is_instance_valid(_tripwire_ctrl):
		return false
	if is_rmb_pressed:
		if _tripwire_ctrl.has_placed_first_pole():
			cancel_tripwire_placement()
			return true
		elif _tripwire_ctrl.is_holding_lmb():
			_tripwire_ctrl.cancel_lmb_hold()
			if hold_progress_bar != null and not _lmb_trap_hold_active and not _interact_key_down:
				hold_progress_bar.visible = false
			return true
	if is_cancel_pressed and _tripwire_ctrl.has_placed_first_pole():
		cancel_tripwire_placement()
		return true
	return false


func cancel_tripwire_placement(require_lmb_release: bool = false) -> void:
	if _tripwire_ctrl != null and is_instance_valid(_tripwire_ctrl):
		_tripwire_ctrl.cancel_placement(require_lmb_release)
	if hold_progress_bar != null and not _lmb_trap_hold_active and not _interact_key_down:
		hold_progress_bar.visible = false


func pickup_item(new_item_id: String, extra_briefcase_items: Array = [], extra_briefcase_positions: Dictionary = {}) -> Dictionary:
	var upper_id: String = new_item_id.to_upper()
	var res: Dictionary = _inv().pickup_item(new_item_id, extra_briefcase_items, extra_briefcase_positions)
	if bool(res["picked"]):
		if PICKUP_SCRIPT.is_gadget_item(upper_id) or upper_id == "LIVE_BOMB":
			cancel_tripwire_placement()
		_refresh_hand_and_back_sockets()
		_update_hud_status()
	return res


func select_jacket_slot(slot_index: int) -> bool:
	var clamped_idx: int = clampi(slot_index, 0, SpyInventoryComponent.JACKET_SLOT_COUNT - 1)
	var changed: bool = (clamped_idx != active_jacket_slot or right_hand_mode != SpyInventoryComponent.RightHandMode.JACKET_SLOT)
	var ok: bool = _inv().select_jacket_slot(slot_index)
	if ok:
		if changed:
			cancel_tripwire_placement()
		_refresh_hand_and_back_sockets()
		_update_hud_status()
	return ok


func cycle_jacket_slot(step: int) -> bool:
	var ok: bool = _inv().cycle_jacket_slot(step)
	if ok:
		cancel_tripwire_placement()
		_refresh_hand_and_back_sockets()
		_update_hud_status()
	return ok


func drop_left_hand_item() -> Dictionary:
	var res: Dictionary = _inv().drop_left_hand_item()
	if str(res["dropped_item_id"]) != "NONE":
		_refresh_hand_and_back_sockets()
		_update_hud_status()
	return res


func drop_right_hand_item() -> Dictionary:
	var res: Dictionary = _inv().drop_right_hand_item()
	if str(res["dropped_item_id"]) != "NONE":
		cancel_tripwire_placement()
		_refresh_hand_and_back_sockets()
		_update_hud_status()
	return res


func _begin_club_charge_exit_lerp() -> void:
	_club_charge_exit_start_speed = get_current_move_speed()
	_club_charge_exit_lerp_elapsed = 0.0
	_club_charge_exit_lerp_active = true


func toggle_personal_club() -> Dictionary:
	cancel_tripwire_placement()
	var was_charging: bool = _inv().is_charging_club
	if was_charging:
		_begin_club_charge_exit_lerp()
	var res: Dictionary = _inv().toggle_personal_club()
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	return res


func start_club_charge() -> Dictionary:
	cancel_tripwire_placement()
	_club_charge_exit_lerp_active = false
	_club_charge_exit_lerp_elapsed = 0.0
	var res: Dictionary = _inv().start_club_charge()
	if _inv().is_charging_club and stance_state == (GameConfig.Stance.SPRINT if GameConfig != null else 1):
		stance_state = GameConfig.Stance.WALK if GameConfig != null else 0
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	return res


func stop_club_charge() -> void:
	if _inv().is_charging_club:
		_begin_club_charge_exit_lerp()
		_inv().stop_club_charge()
		_refresh_hand_and_back_sockets()
		_update_hud_status()


func force_drop_all_hands() -> Array[Dictionary]:
	cancel_tripwire_placement()
	var drops: Array[Dictionary] = _inv().force_drop_all_hands()
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	return drops


func set_briefcase_bomb_state(armed: bool, owner_id: int) -> void:
	_inv().briefcase_armed_bomb = armed
	_inv().briefcase_bomb_owner_id = owner_id
	_sync_inventory_state_to_peers()


func set_briefcase_trap_state(
	armed_spring: bool,
	spring_owner: int,
	armed_bomb: bool,
	bomb_owner: int,
	b_bomb_pos: Vector2 = BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
) -> void:
	var inv: SpyInventoryComponent = _inv()
	inv.briefcase_armed_spring = armed_spring
	inv.briefcase_spring_owner_id = spring_owner
	inv.briefcase_spring_unlatched = false
	inv.briefcase_staged_spring = false
	inv.briefcase_armed_bomb = armed_bomb
	inv.briefcase_bomb_owner_id = bomb_owner
	inv.briefcase_staged_bomb = false
	inv.briefcase_live_bomb_lit = false
	inv.briefcase_live_bomb_fuse_remaining = 0.0
	inv.set_briefcase_bomb_position(b_bomb_pos)
	_sync_inventory_state_to_peers()


func get_held_briefcase_trap_dict() -> Dictionary:
	return _inv().get_briefcase_trap_dict()


func has_held_briefcase_armed_spring() -> bool:
	return left_hand_item_id == "BRIEFCASE" and _inv().briefcase_armed_spring


func has_held_briefcase_armed_bomb() -> bool:
	return left_hand_item_id == "BRIEFCASE" and _inv().briefcase_armed_bomb


func commit_held_briefcase_traps() -> void:
	if left_hand_item_id != "BRIEFCASE":
		return
	var inv: SpyInventoryComponent = _inv()
	var had_staged: bool = inv.briefcase_staged_spring or inv.briefcase_staged_bomb
	inv.commit_briefcase_staged_traps()
	if had_staged:
		_sync_inventory_state_to_peers()


func trigger_held_briefcase_spring_ko() -> void:
	var inv: SpyInventoryComponent = _inv()
	if left_hand_item_id != "BRIEFCASE" or not inv.briefcase_armed_spring:
		return
	var owner_id: int = inv.briefcase_spring_owner_id
	inv.briefcase_armed_spring = false
	inv.briefcase_spring_unlatched = false
	inv.briefcase_spring_owner_id = 0
	if AudioBridge != null:
		AudioBridge.request_world_cue("spring_trigger", _safe_global_pos(), 10.0, owner_id)
	var back_dir: Vector3 = global_transform.basis.z.normalized() if is_inside_tree() else Vector3(0.0, 0.0, 1.0)
	apply_trap_ko("SPRING", owner_id, back_dir * 13.5 + Vector3(0.0, 6.0, 0.0))


func ignite_held_briefcase_bomb(_is_slow_peek: bool = false) -> void:
	var inv: SpyInventoryComponent = _inv()
	if left_hand_item_id != "BRIEFCASE" or not inv.briefcase_armed_bomb:
		return
	inv.briefcase_armed_bomb = false
	inv.briefcase_live_bomb_lit = true
	var fuse_range: Vector2 = GameConfig.get_effective_bomb_fuse_range() if GameConfig != null else Vector2(2.5, 4.0)
	inv.briefcase_live_bomb_fuse_remaining = randf_range(fuse_range.x, fuse_range.y)
	if AudioBridge != null:
		var fuse_rad: float = GameConfig.audio_radius_bomb_fuse if GameConfig != null else 10.0
		AudioBridge.request_world_cue("bomb_hiss", _safe_global_pos(), fuse_rad, inv.briefcase_bomb_owner_id)
	_sync_inventory_state_to_peers()


func step_held_briefcase_live_bomb(delta: float) -> bool:
	var inv: SpyInventoryComponent = _inv()
	if left_hand_item_id != "BRIEFCASE" or not inv.briefcase_live_bomb_lit:
		return false
	inv.briefcase_live_bomb_fuse_remaining = maxf(inv.briefcase_live_bomb_fuse_remaining - delta, 0.0)
	if inv.briefcase_live_bomb_fuse_remaining <= 0.0:
		if not _is_peer_connected() or multiplayer.is_server():
			var owner_id: int = inv.briefcase_bomb_owner_id
			inv.briefcase_live_bomb_lit = false
			inv.briefcase_bomb_owner_id = 0
			_sync_inventory_state_to_peers()
			var blast_origin: Vector3 = _safe_global_pos() + Vector3(0.0, 0.85, 0.0)
			var w3d: World3D = get_world_3d() if is_inside_tree() else null
			var tree: SceneTree = get_tree() if is_inside_tree() else null
			THROWN_BOMB_SCRIPT.detonate_blast_at(tree, w3d, blast_origin, owner_id)
		return true
	return false


func server_pack_objective_into_briefcase(obj_id: String, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> bool:
	if not _inv().pack_objective_into_briefcase(obj_id, norm_pos):
		return false
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	_sync_inventory_state_to_peers()
	return true


func request_move_briefcase_item(item_id: String, norm_pos: Vector2) -> void:
	if _is_peer_connected():
		_rpc_server_move_briefcase_item.rpc_id(1, item_id, norm_pos)
	else:
		_rpc_server_move_briefcase_item(item_id, norm_pos)


@rpc("any_peer", "call_local", "reliable")
func _rpc_server_move_briefcase_item(item_id: String, norm_pos: Vector2) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender_id != 0 and sender_id != name.to_int():
		return
	var inv: SpyInventoryComponent = _inv()
	if inv.left_hand_item_id != "BRIEFCASE":
		return
	var upper: String = item_id.to_upper()
	var moved: bool = false
	if upper == "BOMB":
		if inv.briefcase_staged_bomb or inv.briefcase_armed_bomb or inv.briefcase_live_bomb_lit:
			inv.set_briefcase_bomb_position(norm_pos)
			moved = true
	else:
		moved = inv.set_briefcase_item_position(upper, norm_pos)
	if not moved:
		return
	if AudioBridge != null:
		AudioBridge.request_world_cue("paper_rustle", _safe_global_pos(), 4.0, name.to_int())
	_sync_inventory_state_to_peers()


func server_remove_objective_from_briefcase(obj_id: String) -> bool:
	if not _inv().remove_objective_from_briefcase(obj_id):
		return false
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	_sync_inventory_state_to_peers()
	return true


func server_take_left_hand_objective() -> String:
	var taken: String = _inv().take_left_hand_objective()
	if taken != "NONE":
		_refresh_hand_and_back_sockets()
		_update_hud_status()
		_sync_inventory_state_to_peers()
	return taken


func server_swap_left_hand_objective(new_obj_id: String) -> String:
	var prev: String = _inv().swap_left_hand_objective(new_obj_id)
	if prev != "NONE":
		_refresh_hand_and_back_sockets()
		_update_hud_status()
		_sync_inventory_state_to_peers()
	return prev


func request_briefcase_trap_action(action: String, slot_arg: int = 0, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected():
		_rpc_server_briefcase_trap_action.rpc_id(1, action, slot_arg, norm_pos)
	else:
		_rpc_server_briefcase_trap_action(action, slot_arg, norm_pos)


@rpc("any_peer", "call_local", "reliable")
func _rpc_server_briefcase_trap_action(action: String, slot_arg: int = 0, norm_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id() if (_is_peer_connected() and multiplayer != null) else 0
	if sender_id != 0 and sender_id != name.to_int():
		return
	var inv: SpyInventoryComponent = _inv()
	if inv.left_hand_item_id != "BRIEFCASE":
		return
	var peer_id: int = name.to_int()
	match action.to_upper():
		"UNLATCH_SPRING":
			if inv.briefcase_armed_spring and not inv.briefcase_spring_unlatched:
				inv.briefcase_armed_spring = false
				inv.briefcase_spring_unlatched = true
				if AudioBridge != null:
					AudioBridge.request_world_cue("spring_unlatch", _safe_global_pos(), 5.0, peer_id)
		"REARM_SPRING":
			if inv.briefcase_spring_unlatched:
				inv.briefcase_spring_unlatched = false
				inv.briefcase_staged_spring = true
				inv.briefcase_spring_owner_id = peer_id
				if AudioBridge != null and GameConfig != null:
					AudioBridge.request_world_cue("trap_arm", _safe_global_pos(), GameConfig.audio_radius_trap_setup, peer_id)
		"STEAL_SPRING":
			if inv.briefcase_spring_unlatched:
				var placed: bool = false
				if slot_arg >= 0 and slot_arg < SpyInventoryComponent.JACKET_SLOT_COUNT and inv.jacket_slots[slot_arg] == "NONE":
					inv.jacket_slots[slot_arg] = "SPRING"
					inv.active_jacket_slot = slot_arg
					inv.right_hand_mode = SpyInventoryComponent.RightHandMode.JACKET_SLOT
					placed = true
				else:
					var res: Dictionary = inv.pickup_item("SPRING")
					placed = bool(res.get("picked", false))
					if str(res.get("dropped_item_id", "NONE")) != "NONE":
						_server_spawn_floor_drop(str(res["dropped_item_id"]), [], _compute_safe_drop_position(Vector3(0.0, 0.0, -0.5)))
				if placed:
					inv.briefcase_spring_unlatched = false
					inv.briefcase_spring_owner_id = 0
		"PLANT_SPRING":
			if slot_arg >= 0 and slot_arg < inv.jacket_slots.size() and inv.jacket_slots[slot_arg] == "SPRING":
				if not inv.briefcase_armed_spring and not inv.briefcase_staged_spring and not inv.briefcase_spring_unlatched:
					inv.jacket_slots[slot_arg] = "NONE"
					inv.briefcase_staged_spring = true
					inv.briefcase_spring_owner_id = peer_id
					if AudioBridge != null and GameConfig != null:
						AudioBridge.request_world_cue("trap_arm", _safe_global_pos(), GameConfig.audio_radius_trap_setup, peer_id)
		"PLANT_BOMB":
			if slot_arg >= 0 and slot_arg < inv.jacket_slots.size() and inv.jacket_slots[slot_arg] == "BOMB":
				if not inv.briefcase_armed_bomb and not inv.briefcase_staged_bomb and not inv.briefcase_live_bomb_lit:
					inv.jacket_slots[slot_arg] = "NONE"
					inv.briefcase_staged_bomb = true
					inv.briefcase_bomb_owner_id = peer_id
					if norm_pos.x >= 0.0 and norm_pos.y >= 0.0:
						inv.set_briefcase_bomb_position(norm_pos)
					else:
						inv.set_briefcase_bomb_position(BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS)
					if AudioBridge != null and GameConfig != null:
						AudioBridge.request_world_cue("trap_arm", _safe_global_pos(), GameConfig.audio_radius_trap_setup, peer_id)
		"GRAB_LIT_BOMB":
			if inv.briefcase_live_bomb_lit:
				var rem: float = inv.briefcase_live_bomb_fuse_remaining
				var b_owner: int = inv.briefcase_bomb_owner_id
				inv.briefcase_live_bomb_lit = false
				inv.briefcase_live_bomb_fuse_remaining = 0.0
				inv.briefcase_bomb_owner_id = 0
				if active_container != null and is_instance_valid(active_container) and active_container.has_method("close_container"):
					active_container.close_container(peer_id, self, true)
				server_pickup_world_item("LIVE_BOMB", [], _safe_global_pos())
				if _is_peer_connected():
					_rpc_sync_live_bomb_timer.rpc(rem, b_owner)
				else:
					set_live_bomb_timer(rem, b_owner)
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	_sync_inventory_state_to_peers()


func enter_container_view(container: Node) -> void:
	var already_same_container: bool = (active_container == container)
	if not already_same_container:
		_flush_active_3d_slides(true)
	active_container = container
	stance_state = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	_clear_drag_3d_state()
	_lmb_trap_hold_active = false
	_lmb_trap_hold_elapsed = 0.0
	cancel_tripwire_placement()
	if _dvd_reticle_ui != null:
		_dvd_reticle_ui.set_active(false)
	if _club_qte_ui != null:
		_club_qte_ui.cancel_charge()
	if _watch_bluff_ui != null and _watch_bluff_ui.is_map_open:
		_watch_bluff_ui.set_map_open(false)
	reset_anti_camp()
	if not already_same_container:
		_drawer_focus_just_entered = (not Engine.is_editor_hint() and is_inside_tree() and _is_e_key_pressed())
		_drawer_e_held = false
		_drawer_e_hold_elapsed = 0.0
	_reset_interact_hold()
	if prompt_label != null:
		prompt_label.visible = false

	if is_inside_tree() and is_multiplayer_authority() and not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not already_same_container and camera != null and container != null and container.has_method("get_top_down_camera_transform"):
			if _camera_tween != null and _camera_tween.is_valid():
				_camera_tween.kill()
			var target_xform: Transform3D = container.get_top_down_camera_transform()
			var dur: float = GameConfig.top_down_cam_lerp_duration if GameConfig != null else 0.65
			_camera_tween = create_tween()
			_camera_tween.tween_property(camera, "global_transform", target_xform, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		ensure_overlay_uis()
		if _container_ui != null:
			var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
			_container_ui.open_for_container(self, container, my_id)


func exit_container_view() -> void:
	active_container = null
	_clear_drag_3d_state()
	_active_3d_slides.clear()
	_drawer_focus_just_entered = false
	_drawer_e_held = false
	_drawer_e_hold_elapsed = 0.0
	var lock_stance: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	if stance_state == lock_stance:
		stance_state = GameConfig.Stance.WALK if GameConfig != null else 0

	if _container_ui != null:
		_container_ui.close_view()

	if camera != null:
		if _camera_tween != null and _camera_tween.is_valid():
			_camera_tween.kill()
		if is_inside_tree() and is_multiplayer_authority() and not Engine.is_editor_hint():
			var dur: float = GameConfig.top_down_cam_lerp_duration if GameConfig != null else 0.65
			_camera_tween = create_tween()
			_camera_tween.tween_property(camera, "transform", Transform3D.IDENTITY, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		else:
			camera.transform = Transform3D.IDENTITY

	if not Engine.is_editor_hint() and is_inside_tree() and is_multiplayer_authority():
		var scene: Node = get_tree().current_scene if get_tree() != null else null
		var esc_menu_node: Variant = scene.get("esc_menu") if scene != null else null
		var esc_open: bool = esc_menu_node is CanvasItem and (esc_menu_node as CanvasItem).visible
		if not esc_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func apply_trap_ko(_reason: String, _attacker_peer_id: int = 0, custom_impulse: Vector3 = Vector3.ZERO) -> Array[Dictionary]:
	var ko_stance: int = GameConfig.Stance.KO if GameConfig != null else 4
	if wakeup_immunity_remaining > 0.0:
		return [] as Array[Dictionary]

	var kick_impulse: Vector3 = _compute_ko_kick_impulse(_reason, _attacker_peer_id, custom_impulse)

	# Secondary hits on already-KO'd bodies launch the ragdoll without resetting the 15s timer (Decision 5)
	if stance_state == ko_stance:
		if _is_peer_connected():
			_rpc_apply_secondary_ragdoll_hit.rpc(kick_impulse, _reason)
		else:
			_rpc_apply_secondary_ragdoll_hit(kick_impulse, _reason)
		return [] as Array[Dictionary]

	if active_container != null and is_instance_valid(active_container) and active_container.has_method("close_container"):
		active_container.close_container(name.to_int(), self, true)
	elif stance_state == (GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3):
		exit_container_view()

	live_bomb_remaining = 0.0
	live_bomb_owner_peer_id = 0
	_lmb_trap_hold_active = false
	_lmb_trap_hold_elapsed = 0.0
	cancel_tripwire_placement()
	if _dvd_reticle_ui != null:
		_dvd_reticle_ui.set_active(false)
	if _club_qte_ui != null:
		_club_qte_ui.cancel_charge()
	if _watch_bluff_ui != null and _watch_bluff_ui.is_map_open:
		_watch_bluff_ui.set_map_open(false)

	var drops: Array[Dictionary] = force_drop_all_hands()
	if is_inside_tree() and (not _is_peer_connected() or multiplayer.is_server()):
		for i in range(drops.size()):
			var entry: Dictionary = drops[i]
			var dropped_id: String = str(entry.get("dropped_item_id", "NONE"))
			if dropped_id == "NONE":
				continue
			var angle: float = (TAU * float(i)) / float(maxi(drops.size(), 1))
			var offset := Vector3(cos(angle) * 0.65, 0.0, sin(angle) * 0.65)
			_server_spawn_floor_drop(
				dropped_id,
				entry.get("dropped_briefcase_items", []),
				_compute_safe_drop_position(offset),
				bool(entry.get("dropped_briefcase_armed_bomb", false)),
				int(entry.get("dropped_briefcase_bomb_owner", 0)),
				bool(entry.get("dropped_briefcase_armed_spring", false)),
				int(entry.get("dropped_briefcase_spring_owner", 0)),
				entry.get("dropped_briefcase_item_positions", {}),
				entry.get("dropped_briefcase_bomb_pos", BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS)
			)

	var ko_dur: float = GameConfig.ko_ragdoll_duration if GameConfig != null else 15.0
	var start_pos: Vector3 = _safe_global_pos()
	if _is_peer_connected():
		_rpc_apply_ko_state.rpc(ko_dur, 0.0, true, start_pos, rotation.y, kick_impulse, _reason)
	else:
		_rpc_apply_ko_state(ko_dur, 0.0, true, start_pos, rotation.y, kick_impulse, _reason)
	_sync_inventory_state_to_peers()

	var victim_id: int = name.to_int()
	if _attacker_peer_id > 0 and _attacker_peer_id != victim_id and _reason != "CLUB":
		_dispatch_crt_replay_to_attacker(_attacker_peer_id, _reason, victim_id)
	return drops


func _compute_ko_kick_impulse(reason: String, attacker_peer_id: int, custom_impulse: Vector3 = Vector3.ZERO) -> Vector3:
	if custom_impulse.length_squared() > 0.01:
		return custom_impulse

	var my_pos: Vector3 = _safe_global_pos()
	var away_dir: Vector3 = global_transform.basis.z.normalized() if is_inside_tree() else Vector3(0.0, 0.0, 1.0)
	if attacker_peer_id > 0 and attacker_peer_id != name.to_int() and is_inside_tree() and get_tree() != null:
		for p in get_tree().get_nodes_in_group("spy_players"):
			if p.name.to_int() == attacker_peer_id and p is Node3D:
				var delta_v: Vector3 = my_pos - (p as Node3D).global_position
				delta_v.y = 0.0
				if delta_v.length_squared() > 0.01:
					away_dir = delta_v.normalized()
				break

	match reason.to_upper():
		"DART_GUN":
			return away_dir * 15.5 + Vector3(0.0, 5.5, 0.0)
		"BOMB":
			return away_dir * 16.5 + Vector3(0.0, 7.5, 0.0)
		"SPRING":
			return away_dir * 13.5 + Vector3(0.0, 6.0, 0.0)
		"CLUB":
			return away_dir * 14.5 + Vector3(0.0, 4.8, 0.0)
		"TRIPWIRE":
			var fwd: Vector3 = (-global_transform.basis.z).normalized() if is_inside_tree() else Vector3(0.0, 0.0, -1.0)
			return fwd * 8.5
		"BUCKET":
			return away_dir * 4.5 + Vector3(0.0, -7.0, 0.0)
		_:
			return away_dir * 11.0 + Vector3(0.0, 4.5, 0.0)


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_secondary_ragdoll_hit(kick_impulse: Vector3, reason: String) -> void:
	if not _is_authorized_state_rpc():
		return
	_last_ko_reason = reason
	_last_ko_impulse = kick_impulse
	if _ragdoll_ctrl != null and _ragdoll_ctrl.is_ragdoll_active:
		_ragdoll_ctrl.apply_ragdoll_impulse(kick_impulse, reason)


func _dispatch_crt_replay_to_attacker(attacker_id: int, reason: String, victim_id: int) -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	for p in get_tree().get_nodes_in_group("spy_players"):
		if p.name.to_int() == attacker_id and p.has_method("notify_crt_replay"):
			if _is_peer_connected() and multiplayer.is_server():
				p.notify_crt_replay.rpc_id(attacker_id, reason, victim_id)
			else:
				p.notify_crt_replay(reason, victim_id)
			return


@rpc("any_peer", "call_local", "reliable")
func notify_crt_replay(reason: String, victim_peer_id: int) -> void:
	if _is_peer_connected():
		var sender_id: int = multiplayer.get_remote_sender_id()
		if sender_id != 0 and sender_id != 1:
			return
		if not is_multiplayer_authority():
			return
	ensure_overlay_uis()
	if _crt_replay_ui != null:
		_crt_replay_ui.trigger_replay(reason, victim_peer_id)
	if AudioBridge != null:
		AudioBridge.play_local_cue("crt_static")


func _is_authorized_state_rpc() -> bool:
	if not is_inside_tree() or not _is_peer_connected():
		return true
	var sender_id: int = multiplayer.get_remote_sender_id()
	return sender_id == 0 or sender_id == 1 or sender_id == name.to_int()


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_ko_state(
	ko_sec: float,
	imm_sec: float,
	enter_ko: bool,
	sync_pos: Vector3 = Vector3.INF,
	sync_yaw: float = INF,
	kick_impulse: Vector3 = Vector3.ZERO,
	reason: String = ""
) -> void:
	if not _is_authorized_state_rpc():
		return
	_ensure_ragdoll_controller()
	var col_node: CollisionShape3D = collision_shape if collision_shape != null else get_node_or_null("CollisionShape3D") as CollisionShape3D

	if enter_ko:
		if sync_pos != Vector3.INF:
			if is_inside_tree():
				global_position = sync_pos
			else:
				position = sync_pos
			_target_position = sync_pos
		if sync_yaw != INF:
			rotation.y = sync_yaw
			_target_yaw = sync_yaw
		velocity = Vector3.ZERO
		ko_remaining_seconds = 9999.0 if is_clock_eliminated else ko_sec
		wakeup_immunity_remaining = 0.0
		_pelvis_sync_accum = 0.0
		_last_ko_reason = reason
		_last_ko_impulse = kick_impulse
		stance_state = GameConfig.Stance.KO if GameConfig != null else 4
		collision_layer = GameConfig.LAYER_RAGDOLL_KO if GameConfig != null else 8
		collision_mask = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
		if col_node != null:
			col_node.disabled = true
		var is_bucket_ko: bool = (reason.to_upper() == "BUCKET")
		if _ragdoll_ctrl != null:
			_ragdoll_ctrl.set_bucket_on_head(is_bucket_ko)
			_ragdoll_ctrl.start_ragdoll(kick_impulse, reason)
		if left_hand_socket != null:
			left_hand_socket.visible = false
		if right_hand_socket != null:
			right_hand_socket.visible = false
		_sync_camera_to_ragdoll_head()
		_sync_visual_rig_sockets_to_skeleton()
	else:
		if _ragdoll_ctrl != null:
			_ragdoll_ctrl.stop_ragdoll()
		if sync_pos != Vector3.INF:
			if is_inside_tree():
				global_position = sync_pos
			else:
				position = sync_pos
			_target_position = sync_pos
		velocity = Vector3.ZERO
		ko_remaining_seconds = 0.0
		wakeup_immunity_remaining = imm_sec
		_pelvis_sync_accum = 0.0
		stance_state = GameConfig.Stance.WALK if GameConfig != null else 0
		collision_layer = GameConfig.LAYER_PLAYER if GameConfig != null else 4
		collision_mask = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_PLAYER) if GameConfig != null else 5
		if col_node != null:
			col_node.disabled = false
		if head != null:
			head.rotation = Vector3(head_pitch, 0.0, 0.0)
			head.position = Vector3(0.0, GameConfig.standing_neck_y if GameConfig != null else 1.6, 0.0)
		if camera != null:
			camera.transform = Transform3D.IDENTITY
		if left_hand_socket != null:
			left_hand_socket.visible = true
		if right_hand_socket != null:
			right_hand_socket.visible = true
		_sync_camera_to_ragdoll_head()
		_sync_visual_rig_sockets_to_skeleton()
	_update_hud_status()


func _sync_camera_to_ragdoll_head() -> void:
	if head == null or _ragdoll_ctrl == null:
		return
	if is_inside_tree() and _ragdoll_ctrl.skeleton != null:
		head.global_transform = _ragdoll_ctrl.get_head_camera_world_transform()
		var lock_stance: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
		if camera != null and stance_state != lock_stance:
			camera.transform = Transform3D.IDENTITY


func _sync_visual_rig_sockets_to_skeleton() -> void:
	if _ragdoll_ctrl == null or _ragdoll_ctrl.skeleton == null or not is_inside_tree():
		return
	var b_socket: Marker3D = back_club_socket if back_club_socket != null else get_node_or_null("VisualRig/BackClubSocket") as Marker3D
	var w_socket: Marker3D = spy_wearable_socket if spy_wearable_socket != null else get_node_or_null("VisualRig/SpyWearableSocket") as Marker3D
	var tp_l_socket: Marker3D = tp_left_hand_socket if tp_left_hand_socket != null else get_node_or_null("VisualRig/ThirdPersonLeftHandSocket") as Marker3D
	var tp_r_socket: Marker3D = tp_right_hand_socket if tp_right_hand_socket != null else get_node_or_null("VisualRig/ThirdPersonRightHandSocket") as Marker3D
	if not _socket_offsets_calibrated:
		_socket_offsets_calibrated = true
		if b_socket != null:
			_back_club_bone_offset = _ragdoll_ctrl.compute_bone_local_offset("spine.002", b_socket.transform)
		_wearable_bone_offset = Transform3D(Basis.IDENTITY, Vector3(-0.038, 0.185, 0.0))
	if b_socket != null and b_socket.is_inside_tree():
		b_socket.global_transform = _ragdoll_ctrl.get_bone_world_transform("spine.002") * _back_club_bone_offset
	if w_socket != null and w_socket.is_inside_tree():
		w_socket.global_transform = _ragdoll_ctrl.get_bone_world_transform("forearm.L") * _wearable_bone_offset
	if tp_l_socket != null and tp_l_socket.is_inside_tree():
		tp_l_socket.global_transform = _ragdoll_ctrl.get_bone_world_transform("hand.L")
	if tp_r_socket != null and tp_r_socket.is_inside_tree():
		tp_r_socket.global_transform = _ragdoll_ctrl.get_bone_world_transform("hand.R")


func get_ragdoll_pelvis_world_position() -> Vector3:
	if _ragdoll_ctrl != null:
		return _ragdoll_ctrl.get_pelvis_world_position()
	return _safe_global_pos()


func _compute_safe_wakeup_position(raw_pelvis_pos: Vector3) -> Vector3:
	if not is_inside_tree() or get_world_3d() == null or get_world_3d().direct_space_state == null:
		return Vector3(raw_pelvis_pos.x, maxf(raw_pelvis_pos.y - 0.55, 0.0), raw_pelvis_pos.z)

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
	var interact_mask: int = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3

	var floor_y: float = maxf(raw_pelvis_pos.y - 0.55, 0.0)
	var down_q := PhysicsRayQueryParameters3D.create(
		raw_pelvis_pos + Vector3(0.0, 1.2, 0.0),
		raw_pelvis_pos + Vector3(0.0, -3.5, 0.0),
		env_mask,
		[get_rid()]
	)
	var down_hit: Dictionary = space.intersect_ray(down_q)
	if not down_hit.is_empty():
		floor_y = float((down_hit["position"] as Vector3).y)

	# Radial wall/door clearance push so the standing capsule never wakes up clipped inside geometry
	var safe_xz := Vector3(raw_pelvis_pos.x, floor_y, raw_pelvis_pos.z)
	var clearance_radius: float = 0.45
	for dir_i in range(8):
		var ang: float = (TAU * float(dir_i)) / 8.0
		var dir_vec := Vector3(cos(ang), 0.0, sin(ang))
		var ray_from: Vector3 = safe_xz + Vector3(0.0, 0.75, 0.0)
		var ray_to: Vector3 = ray_from + dir_vec * clearance_radius
		var w_q := PhysicsRayQueryParameters3D.create(ray_from, ray_to, interact_mask, [get_rid()])
		var w_hit: Dictionary = space.intersect_ray(w_q)
		if not w_hit.is_empty():
			var hit_pt: Vector3 = w_hit["position"]
			var dist: float = Vector2(hit_pt.x - safe_xz.x, hit_pt.z - safe_xz.z).length()
			var push_back: float = maxf(clearance_radius - dist + 0.04, 0.0)
			safe_xz -= dir_vec * push_back

	return Vector3(safe_xz.x, floor_y, safe_xz.z)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_sync_ragdoll_pelvis(pelvis_world_pos: Vector3) -> void:
	if _ragdoll_ctrl != null and stance_state == (GameConfig.Stance.KO if GameConfig != null else 4):
		_ragdoll_ctrl.set_remote_pelvis_sync_target(pelvis_world_pos)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_wakeup_at_pelvis(requested_pelvis_pos: Vector3) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != 1 and sender_id != name.to_int():
		return
	var safe_pos: Vector3 = _compute_safe_wakeup_position(requested_pelvis_pos)
	var imm_dur: float = GameConfig.ko_wakeup_immunity_duration if GameConfig != null else 2.0
	if _is_peer_connected():
		_rpc_apply_ko_state.rpc(0.0, imm_dur, false, safe_pos)
	else:
		_rpc_apply_ko_state(0.0, imm_dur, false, safe_pos)


func _on_match_spy_eliminated_by_clock(eliminated_peer_id: int) -> void:
	var my_peer_id: int = name.to_int() if name.is_valid_int() else 1
	if eliminated_peer_id != my_peer_id:
		return
	apply_clock_elimination()


func apply_clock_elimination() -> Array[Dictionary]:
	if is_clock_eliminated:
		return [] as Array[Dictionary]
	is_clock_eliminated = true
	wakeup_immunity_remaining = 0.0
	var drops: Array[Dictionary] = []
	var ko_stance: int = GameConfig.Stance.KO if GameConfig != null else 4
	if stance_state != ko_stance and (not _is_peer_connected() or multiplayer.is_server()):
		drops = apply_trap_ko("CLOCK_EXPIRED", 0, Vector3(0.0, -4.0, 0.0))
	ko_remaining_seconds = 9999.0
	if is_inside_tree() and is_multiplayer_authority():
		if stance_label != null:
			stance_label.text = "ELIMINATED (00:00)"
		if prompt_label != null:
			prompt_label.text = "CLOCK EXPIRED — ELIMINATED! Waiting for remaining spies..."
			prompt_label.visible = true
		if clock_label != null:
			clock_label.text = "CLOCK: 00:00 [OUT]"
			clock_label.modulate = Color(1.0, 0.25, 0.25)
	return drops


func reset_for_rematch(spawn_local_pos: Vector3, spawn_yaw: float = 0.0) -> void:
	_requested_ladder = null
	_release_ladder()
	is_clock_eliminated = false
	ko_remaining_seconds = 0.0
	wakeup_immunity_remaining = 0.0
	live_bomb_remaining = 0.0
	live_bomb_owner_peer_id = 0
	club_overcharge_stumble_remaining = 0.0
	_club_feint_cooldown = 0.0
	_club_whiff_recovery = 0.0
	_club_charge_exit_lerp_active = false
	_club_charge_exit_lerp_elapsed = 0.0
	_club_charge_exit_start_speed = 0.0
	_lmb_trap_hold_active = false
	_lmb_trap_hold_elapsed = 0.0
	cancel_tripwire_placement()
	anti_camp_timer = 0.0
	anti_camp_sniffle_warned = false
	head_pitch = 0.0

	if active_container != null and is_instance_valid(active_container) and active_container.has_method("close_container"):
		active_container.close_container(name.to_int(), self, true)
	elif stance_state == (GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3):
		exit_container_view()

	if _dvd_reticle_ui != null:
		_dvd_reticle_ui.set_active(false)
	if _club_qte_ui != null:
		_club_qte_ui.cancel_charge()
	if _watch_bluff_ui != null and _watch_bluff_ui.is_map_open:
		_watch_bluff_ui.set_map_open(false)
	if _crt_replay_ui != null:
		_crt_replay_ui.stop_replay(false)

	force_drop_all_hands()
	_sync_inventory_state_to_peers()

	if _ragdoll_ctrl != null:
		_ragdoll_ctrl.stop_ragdoll()
		if _ragdoll_ctrl.agent_instance != null:
			_ragdoll_ctrl.agent_instance.visible = true

	position = spawn_local_pos
	_target_position = spawn_local_pos
	rotation.y = spawn_yaw
	_target_yaw = spawn_yaw
	velocity = Vector3.ZERO
	stance_state = GameConfig.Stance.WALK if GameConfig != null else 0
	collision_layer = GameConfig.LAYER_PLAYER if GameConfig != null else 4
	collision_mask = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_PLAYER) if GameConfig != null else 5
	var col_node: CollisionShape3D = collision_shape if collision_shape != null else get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_node != null:
		col_node.disabled = false
	if head != null:
		head.rotation = Vector3.ZERO
		head.position = Vector3(0.0, GameConfig.standing_neck_y if GameConfig != null else 1.6, 0.0)
	if camera != null:
		camera.transform = Transform3D.IDENTITY
	if left_hand_socket != null:
		left_hand_socket.visible = true
	if right_hand_socket != null:
		right_hand_socket.visible = true
	if prompt_label != null:
		prompt_label.visible = false
	if clock_label != null:
		clock_label.modulate = Color(1.0, 1.0, 1.0)
	_refresh_hand_and_back_sockets()
	_apply_stance_collision_and_visuals()
	_sync_camera_to_ragdoll_head()
	_update_hud_status()


func wake_up_from_ko() -> void:
	var raw_pelvis: Vector3 = get_ragdoll_pelvis_world_position()
	var safe_pos: Vector3 = _compute_safe_wakeup_position(raw_pelvis)
	var imm_dur: float = GameConfig.ko_wakeup_immunity_duration if GameConfig != null else 2.0
	if _is_peer_connected():
		if multiplayer.is_server():
			_rpc_apply_ko_state.rpc(0.0, imm_dur, false, safe_pos)
		elif is_multiplayer_authority():
			_rpc_request_wakeup_at_pelvis.rpc_id(1, safe_pos)
	else:
		_rpc_apply_ko_state(0.0, imm_dur, false, safe_pos)
	if is_inside_tree() and is_multiplayer_authority() and prompt_label != null:
		prompt_label.visible = false


func tick_ko_and_immunity(delta: float) -> void:
	var is_local_auth: bool = is_inside_tree() and is_multiplayer_authority()
	var ko_stance: int = GameConfig.Stance.KO if GameConfig != null else 4
	if stance_state == ko_stance:
		if is_clock_eliminated:
			ko_remaining_seconds = 9999.0
			if is_local_auth:
				_sync_camera_to_ragdoll_head()
				if _is_peer_connected():
					_pelvis_sync_accum += delta
					if _pelvis_sync_accum >= PELVIS_SYNC_INTERVAL:
						_pelvis_sync_accum = 0.0
						_rpc_sync_ragdoll_pelvis.rpc(get_ragdoll_pelvis_world_position())
				if stance_label != null:
					stance_label.text = "ELIMINATED (00:00)"
				if prompt_label != null:
					prompt_label.text = "CLOCK EXPIRED — ELIMINATED! Waiting for rival..."
					prompt_label.visible = true
			return
		ko_remaining_seconds -= delta
		var clamped_ko: float = maxf(ko_remaining_seconds, 0.0)
		if is_local_auth:
			_sync_camera_to_ragdoll_head()
			if _is_peer_connected():
				_pelvis_sync_accum += delta
				if _pelvis_sync_accum >= PELVIS_SYNC_INTERVAL:
					_pelvis_sync_accum = 0.0
					_rpc_sync_ragdoll_pelvis.rpc(get_ragdoll_pelvis_world_position())
			if stance_label != null:
				stance_label.text = "KNOCKED OUT! (%.1fs)" % clamped_ko
			if prompt_label != null:
				prompt_label.text = "KNOCKED OUT — Waking up in %.1fs..." % clamped_ko
				prompt_label.visible = true
		if ko_remaining_seconds <= 0.0:
			if not _is_peer_connected() or is_local_auth or (is_inside_tree() and multiplayer.is_server()):
				wake_up_from_ko()
		return

	if wakeup_immunity_remaining > 0.0:
		wakeup_immunity_remaining = maxf(wakeup_immunity_remaining - delta, 0.0)
		var blink_vis: bool = true if wakeup_immunity_remaining <= 0.0 else (int(wakeup_immunity_remaining * 10.0) % 2 == 0)
		if _ragdoll_ctrl != null and _ragdoll_ctrl.agent_instance != null:
			_ragdoll_ctrl.agent_instance.visible = blink_vis
			if mesh_instance != null:
				mesh_instance.visible = false
		elif mesh_instance != null:
			mesh_instance.visible = blink_vis
		if is_local_auth and stance_label != null:
			if wakeup_immunity_remaining > 0.0:
				stance_label.text = "IMMUNE! (%.1fs)" % wakeup_immunity_remaining
			else:
				_update_hud_status()


func _on_match_clock_updated(peer_id: int, remaining_seconds: float, delta_bonus: float) -> void:
	var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
	if peer_id != my_id:
		return
	if clock_label != null:
		var clamped_sec: int = maxi(ceili(remaining_seconds), 0)
		@warning_ignore("integer_division")
		var mins: int = clamped_sec / 60
		var secs: int = clamped_sec % 60
		var timer_paused: bool = GameConfig != null and GameConfig.debug_disable_match_timer
		clock_label.text = "CLOCK: %02d:%02d%s" % [mins, secs, " [PAUSED]" if timer_paused else ""]
		if timer_paused:
			clock_label.modulate = Color(0.55, 0.90, 1.0)
		else:
			clock_label.modulate = Color(1.0, 0.35, 0.30) if clamped_sec <= 30 else Color(1.0, 1.0, 1.0)
	if delta_bonus > 0.0 and bonus_toast_label != null:
		bonus_toast_label.text = "+%ds FIRST SEARCH!" % int(round(delta_bonus))
		bonus_toast_label.visible = true
		_bonus_toast_timer = 2.2


# ==========================================
# Server-Authoritative Hand & Pickup RPCs
# ==========================================

func server_pickup_world_item(
	item_id: String,
	extra_briefcase_items: Array,
	pickup_pos: Vector3,
	extra_briefcase_positions: Dictionary = {}
) -> bool:
	var res: Dictionary = pickup_item(item_id, extra_briefcase_items, extra_briefcase_positions)
	if not bool(res["picked"]):
		return false

	if str(res["dropped_item_id"]) != "NONE":
		var safe_drop_pos: Vector3 = pickup_pos
		if is_inside_tree() and get_world_3d() != null:
			var desired_offset := Vector3(pickup_pos.x - global_position.x, 0.0, pickup_pos.z - global_position.z)
			safe_drop_pos = _compute_safe_drop_position(desired_offset, true)
		_server_spawn_floor_drop(
			str(res["dropped_item_id"]),
			res["dropped_briefcase_items"],
			safe_drop_pos,
			bool(res.get("dropped_briefcase_armed_bomb", false)),
			int(res.get("dropped_briefcase_bomb_owner", 0)),
			bool(res.get("dropped_briefcase_armed_spring", false)),
			int(res.get("dropped_briefcase_spring_owner", 0)),
			res.get("dropped_briefcase_item_positions", {}),
			res.get("dropped_briefcase_bomb_pos", BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS)
		)

	_sync_inventory_state_to_peers()
	return true


@rpc("any_peer", "call_local", "reliable")
func server_request_hand_action(action_type: String, slot_arg: int = 0) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != name.to_int():
		return

	var res: Dictionary = {"dropped_item_id": "NONE", "dropped_briefcase_items": [] as Array[String]}
	match action_type:
		"SELECT_SLOT":
			select_jacket_slot(slot_arg)
		"CYCLE_SLOT":
			cycle_jacket_slot(slot_arg)
		"DROP_LEFT":
			res = drop_left_hand_item()
		"DROP_RIGHT":
			res = drop_right_hand_item()
		"TOGGLE_CLUB":
			res = toggle_personal_club()
		"START_CLUB_CHARGE":
			res = start_club_charge()
			if str(res["dropped_item_id"]) == "BRIEFCASE" and AudioBridge != null:
				AudioBridge.request_world_cue("door_bash", global_position, 8.0, name.to_int())
		"STOP_CLUB_CHARGE":
			stop_club_charge()
		"KO_SCATTER":
			var drops: Array[Dictionary] = force_drop_all_hands()
			for i in range(drops.size()):
				var entry: Dictionary = drops[i]
				var dropped_id: String = str(entry.get("dropped_item_id", "NONE"))
				if dropped_id == "NONE":
					continue
				var angle: float = (TAU * float(i)) / float(maxi(drops.size(), 1))
				var offset := Vector3(cos(angle) * 0.65, 0.0, sin(angle) * 0.65)
				_server_spawn_floor_drop(
					dropped_id,
					entry.get("dropped_briefcase_items", []),
					_compute_safe_drop_position(offset),
					bool(entry.get("dropped_briefcase_armed_bomb", false)),
					int(entry.get("dropped_briefcase_bomb_owner", 0)),
					bool(entry.get("dropped_briefcase_armed_spring", false)),
					int(entry.get("dropped_briefcase_spring_owner", 0)),
					entry.get("dropped_briefcase_item_positions", {}),
					entry.get("dropped_briefcase_bomb_pos", BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS)
				)

	if str(res["dropped_item_id"]) != "NONE":
		var forward_offset: Vector3 = (-global_transform.basis.z * 0.75) if is_inside_tree() else Vector3(0.0, 0.0, -0.75)
		var drop_pos: Vector3 = _compute_safe_drop_position(forward_offset)
		_server_spawn_floor_drop(
			str(res["dropped_item_id"]),
			res["dropped_briefcase_items"],
			drop_pos,
			bool(res.get("dropped_briefcase_armed_bomb", false)),
			int(res.get("dropped_briefcase_bomb_owner", 0)),
			bool(res.get("dropped_briefcase_armed_spring", false)),
			int(res.get("dropped_briefcase_spring_owner", 0)),
			res.get("dropped_briefcase_item_positions", {}),
			res.get("dropped_briefcase_bomb_pos", BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS)
		)

	_sync_inventory_state_to_peers()


func _compute_safe_drop_position(desired_offset: Vector3, ignore_interactables_for_horiz: bool = false) -> Vector3:
	var origin_base: Vector3 = global_position if is_inside_tree() else position
	if not is_inside_tree() or get_world_3d() == null:
		return origin_base + desired_offset
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return origin_base + desired_offset

	var horiz_offset := Vector3(desired_offset.x, 0.0, desired_offset.z)
	var ray_start: Vector3 = origin_base + Vector3(0.0, 0.6, 0.0)
	var safe_xz: Vector3 = origin_base + horiz_offset
	if horiz_offset.length_squared() > 0.0001:
		var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
		var horiz_mask: int = env_mask if ignore_interactables_for_horiz else ((GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3)
		var h_query := PhysicsRayQueryParameters3D.create(ray_start, ray_start + horiz_offset, horiz_mask, [get_rid()])
		var h_hit: Dictionary = space.intersect_ray(h_query)
		if not h_hit.is_empty():
			var hit_pos: Vector3 = h_hit["position"]
			var hit_dist: float = Vector2(hit_pos.x - origin_base.x, hit_pos.z - origin_base.z).length()
			var clamped_dist: float = maxf(hit_dist - 0.30, 0.12)
			safe_xz = origin_base + horiz_offset.normalized() * clamped_dist

	var floor_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
	var down_start: Vector3 = safe_xz + Vector3(0.0, 0.8, 0.0)
	var down_end: Vector3 = safe_xz + Vector3(0.0, -2.0, 0.0)
	var d_query := PhysicsRayQueryParameters3D.create(down_start, down_end, floor_mask, [get_rid()])
	var d_hit: Dictionary = space.intersect_ray(d_query)
	if not d_hit.is_empty():
		return Vector3(safe_xz.x, float((d_hit["position"] as Vector3).y), safe_xz.z)
	return Vector3(safe_xz.x, maxf(origin_base.y, 0.0), safe_xz.z)


func _sync_inventory_state_to_peers() -> void:
	if _is_peer_connected():
		var inv: SpyInventoryComponent = _inv()
		_rpc_sync_inventory.rpc(
			inv.left_hand_item_id,
			inv.briefcase_objectives.duplicate(),
			inv.jacket_slots.duplicate(),
			inv.active_jacket_slot,
			inv.right_hand_mode,
			inv.is_charging_club,
			inv.get_briefcase_trap_dict()
		)
	elif _container_ui != null and _container_ui.visible:
		_container_ui.refresh_view()


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_inventory(l_item: String, b_objs: Array, j_slots: Array, a_slot: int, r_mode: int, charging: bool, b_traps: Dictionary = {}) -> void:
	if not _is_authorized_state_rpc():
		return
	var prev_slot: int = active_jacket_slot
	var prev_mode: int = right_hand_mode
	_inv().apply_sync_state(l_item, b_objs, j_slots, a_slot, r_mode, charging, b_traps)
	if right_hand_item_id != "TRIPWIRE" or active_jacket_slot != prev_slot or right_hand_mode != prev_mode:
		cancel_tripwire_placement()
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	if _container_ui != null and _container_ui.visible:
		_container_ui.refresh_view()


func _server_spawn_floor_drop(
	dropped_id: String,
	b_objs: Array,
	world_pos: Vector3,
	b_armed_bomb: bool = false,
	b_bomb_owner: int = 0,
	b_armed_spring: bool = false,
	b_spring_owner: int = 0,
	b_item_positions: Dictionary = {},
	b_bomb_pos: Vector2 = BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
) -> void:
	_drop_counter += 1
	var drop_name: String = "Dropped_%s_%s_%d" % [name, dropped_id, _drop_counter]
	if _is_peer_connected():
		_rpc_spawn_dropped_pickup.rpc(dropped_id, b_objs.duplicate(), world_pos, drop_name, b_armed_bomb, b_bomb_owner, b_armed_spring, b_spring_owner, b_item_positions.duplicate(), b_bomb_pos)
	else:
		_rpc_spawn_dropped_pickup(dropped_id, b_objs.duplicate(), world_pos, drop_name, b_armed_bomb, b_bomb_owner, b_armed_spring, b_spring_owner, b_item_positions.duplicate(), b_bomb_pos)


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_dropped_pickup(
	dropped_id: String,
	b_objs: Array,
	world_pos: Vector3,
	drop_name: String,
	b_armed_bomb: bool = false,
	b_bomb_owner: int = 0,
	b_armed_spring: bool = false,
	b_spring_owner: int = 0,
	b_item_positions: Dictionary = {},
	b_bomb_pos: Vector2 = BRIEFCASE_BUILDER.DEFAULT_BOMB_NORM_POS
) -> void:
	if not _is_authorized_state_rpc():
		return
	var target_root: Node = get_tree().current_scene if get_tree() != null else null
	if target_root == null:
		var parent_node: Node = get_parent()
		if parent_node != null and parent_node.name == "Players" and parent_node.get_parent() != null:
			target_root = parent_node.get_parent()
		else:
			target_root = parent_node
	if target_root == null:
		return

	var pickup: StaticBody3D = PICKUP_SCENE.instantiate() as StaticBody3D
	pickup.name = drop_name
	pickup.set("item_id", dropped_id)
	var typed_objs: Array[String] = []
	for item in b_objs:
		typed_objs.append(str(item))
	pickup.set("packed_objectives", typed_objs)
	pickup.set("packed_item_positions", b_item_positions.duplicate())
	pickup.set("bomb_norm_pos", BRIEFCASE_BUILDER.clamp_norm(b_bomb_pos))
	pickup.set("armed_spring", b_armed_spring)
	pickup.set("spring_owner_peer_id", b_spring_owner)
	pickup.set("armed_bomb", b_armed_bomb)
	pickup.set("bomb_owner_peer_id", b_bomb_owner)
	target_root.add_child(pickup)
	pickup.global_position = Vector3(world_pos.x, maxf(world_pos.y, 0.0), world_pos.z)


# ==========================================
# Doc 4, 5 & 6: Traps, Club QTE, Watch Bluffs & Anti-Camp
# ==========================================

func set_live_bomb_timer(fuse_sec: float, owner_id: int) -> void:
	live_bomb_remaining = maxf(fuse_sec, 0.05)
	live_bomb_owner_peer_id = owner_id
	_update_hud_status()


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_live_bomb_timer(fuse_sec: float, owner_id: int) -> void:
	if not _is_authorized_state_rpc():
		return
	set_live_bomb_timer(fuse_sec, owner_id)


func catch_live_bomb(fuse_sec: float, owner_id: int) -> void:
	pickup_item("LIVE_BOMB")
	_sync_inventory_state_to_peers()
	var clamped: float = maxf(fuse_sec, 0.15)
	if _is_peer_connected():
		_rpc_sync_live_bomb_timer.rpc(clamped, owner_id)
	else:
		set_live_bomb_timer(clamped, owner_id)
	if AudioBridge != null:
		AudioBridge.request_world_cue("bomb_hiss", _safe_global_pos(), 6.0, name.to_int())


func step_live_bomb_fuse(delta: float) -> bool:
	if right_hand_mode != SpyInventoryComponent.RightHandMode.LIVE_BOMB:
		live_bomb_remaining = 0.0
		return false
	if live_bomb_remaining <= 0.0:
		return false
	live_bomb_remaining -= delta
	if is_inside_tree() and is_multiplayer_authority() and prompt_label != null and stance_state != (GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3):
		prompt_label.text = "HOT POTATO! [LMB] THROW! (%.1fs)" % maxf(live_bomb_remaining, 0.0)
		prompt_label.visible = true
	if live_bomb_remaining <= 0.0:
		if not _is_peer_connected() or multiplayer.is_server():
			var owner_id: int = live_bomb_owner_peer_id
			live_bomb_remaining = 0.0
			live_bomb_owner_peer_id = 0
			_inv().consume_live_bomb()
			_sync_inventory_state_to_peers()
			var blast_origin: Vector3 = _safe_global_pos() + Vector3(0.0, 0.85, 0.0)
			var w3d: World3D = get_world_3d() if is_inside_tree() else null
			var tree: SceneTree = get_tree() if is_inside_tree() else null
			THROWN_BOMB_SCRIPT.detonate_blast_at(tree, w3d, blast_origin, owner_id)
		return true
	return false


func throw_live_bomb(custom_origin: Vector3 = Vector3.ZERO, custom_dir: Vector3 = Vector3.ZERO) -> Node:
	if right_hand_mode != SpyInventoryComponent.RightHandMode.LIVE_BOMB:
		return null
	reset_anti_camp()
	var origin: Vector3 = custom_origin
	var dir: Vector3 = custom_dir
	if origin == Vector3.ZERO:
		if camera != null and camera.is_inside_tree():
			origin = camera.global_position + (-camera.global_transform.basis.z * 0.60)
		else:
			origin = _safe_global_pos() + Vector3(0.0, 1.45, -0.6)
	if dir == Vector3.ZERO:
		if camera != null and camera.is_inside_tree():
			dir = -camera.global_transform.basis.z.normalized()
		else:
			dir = Vector3(0.0, 0.0, -1.0)
	dir = dir.normalized()
	_trigger_vm_right_action("THROW")
	if _ragdoll_ctrl != null:
		_ragdoll_ctrl.trigger_right_hand_action("THROW")
	var fuse_now: float = maxf(live_bomb_remaining, 0.20)
	var orig_owner: int = live_bomb_owner_peer_id if live_bomb_owner_peer_id > 0 else name.to_int()
	live_bomb_remaining = 0.0
	live_bomb_owner_peer_id = 0
	if _is_peer_connected() and not multiplayer.is_server():
		_rpc_server_throw_live_bomb.rpc_id(1, origin, dir, fuse_now, orig_owner)
		return null
	return _server_execute_throw_live_bomb(origin, dir, fuse_now, orig_owner)


@rpc("any_peer", "call_local", "reliable")
func _rpc_server_throw_live_bomb(origin: Vector3, dir: Vector3, fuse_sec: float, orig_owner: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != name.to_int():
		return
	_server_execute_throw_live_bomb(origin, dir, fuse_sec, orig_owner)


func _server_execute_throw_live_bomb(origin: Vector3, dir: Vector3, fuse_sec: float, orig_owner: int) -> Node:
	if not _inv().consume_live_bomb():
		return null
	_sync_inventory_state_to_peers()
	_action_counter += 1
	var throw_speed: float = GameConfig.time_bomb_throw_speed if GameConfig != null else 9.5
	var launch_vel: Vector3 = dir.normalized() * throw_speed + Vector3(0.0, 2.8, 0.0)
	var bomb_name: String = "ThrownBomb_%s_%d" % [name, _action_counter]
	var resolved_fuse: float = maxf(fuse_sec, 0.25)
	if AudioBridge != null:
		AudioBridge.request_world_cue("club_whoosh", origin, 6.0, name.to_int())
	if _is_peer_connected():
		_rpc_spawn_thrown_bomb.rpc(bomb_name, origin, launch_vel, resolved_fuse, orig_owner, name.to_int())
		return _find_spawned_node_in_scene(bomb_name)
	return _spawn_thrown_bomb_local(bomb_name, origin, launch_vel, resolved_fuse, orig_owner, name.to_int())


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_thrown_bomb(bomb_name: String, spawn_pos: Vector3, launch_vel: Vector3, fuse_sec: float, owner_id: int, thrower_id: int) -> void:
	if not _is_authorized_state_rpc():
		return
	_spawn_thrown_bomb_local(bomb_name, spawn_pos, launch_vel, fuse_sec, owner_id, thrower_id)


func _spawn_thrown_bomb_local(bomb_name: String, spawn_pos: Vector3, launch_vel: Vector3, fuse_sec: float, owner_id: int, thrower_id: int) -> Node:
	var target_root: Node = (get_tree().current_scene if get_tree() != null else null)
	if target_root == null:
		target_root = get_parent()
	if target_root == null:
		return null
	var bomb: StaticBody3D = THROWN_BOMB_SCRIPT.new() as StaticBody3D
	bomb.name = bomb_name
	bomb.set("owner_peer_id", owner_id)
	bomb.set("thrower_peer_id", thrower_id)
	bomb.set("fuse_remaining", fuse_sec)
	bomb.set("velocity", launch_vel)
	target_root.add_child(bomb)
	if bomb.is_inside_tree():
		bomb.global_position = spawn_pos
	else:
		bomb.position = spawn_pos
	return bomb


func _find_spawned_node_in_scene(node_name: String) -> Node:
	var target_root: Node = get_tree().current_scene if (is_inside_tree() and get_tree() != null) else get_parent()
	return target_root.get_node_or_null(node_name) if target_root != null else null


@rpc("any_peer", "call_local", "reliable")
func _rpc_server_rig_bucket_on_door(door_path: NodePath, other_side: bool = false) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != name.to_int():
		return
	var door_node: Node = get_node_or_null(door_path)
	if door_node == null and is_inside_tree() and get_tree() != null:
		door_node = get_tree().root.get_node_or_null(door_path)
	if door_node == null or not door_node.has_method("rig_water_bucket"):
		return
	if _inv().get_active_right_item_id() != "BUCKET":
		return
	if bool(door_node.call("rig_water_bucket", name.to_int(), other_side)):
		_inv().consume_active_jacket_slot("BUCKET")
		_sync_inventory_state_to_peers()
		if AudioBridge != null and door_node is Node3D:
			AudioBridge.request_world_cue("trap_arm", (door_node as Node3D).global_position, 6.0, name.to_int())


func deploy_tripwire_between(pole1_pos: Vector3, pole2_pos: Vector3) -> void:
	reset_anti_camp()
	if _is_peer_connected() and not multiplayer.is_server():
		_rpc_server_deploy_tripwire.rpc_id(1, pole1_pos, pole2_pos)
	else:
		_rpc_server_deploy_tripwire(pole1_pos, pole2_pos)


@rpc("any_peer", "call_local", "reliable")
func _rpc_server_deploy_tripwire(pole1_pos: Vector3, pole2_pos: Vector3) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != name.to_int():
		return
	var ko_stance: int = GameConfig.Stance.KO if GameConfig != null else 4
	var lock_stance: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	if stance_state == ko_stance or stance_state == lock_stance or is_clock_eliminated:
		return
	var min_span: float = GameConfig.tripwire_min_span if GameConfig != null else 0.40
	var max_span: float = GameConfig.tripwire_max_span if GameConfig != null else 2.50
	var span: float = pole1_pos.distance_to(pole2_pos)
	if span < min_span - 0.02 or span > max_span + 0.02:
		return
	var horiz_span: float = Vector2(pole2_pos.x - pole1_pos.x, pole2_pos.z - pole1_pos.z).length()
	if absf(pole2_pos.y - pole1_pos.y) > TripwirePlacementController.MAX_POLE_HEIGHT_DELTA or horiz_span < TripwirePlacementController.MIN_HORIZ_SPAN:
		return
	if is_inside_tree():
		if TripwirePlacementController.is_point_in_ladder_safezone(pole1_pos, self) or TripwirePlacementController.is_span_in_ladder_safezone(pole1_pos, pole2_pos, self):
			return
	if is_inside_tree() and get_world_3d() != null:
		var exclude: Array[RID] = [get_rid()]
		if TripwirePlacementController.is_wire_obstructed(pole1_pos, pole2_pos, get_world_3d(), exclude):
			return
	if _inv().consume_active_jacket_slot("TRIPWIRE") == "NONE":
		return
	_sync_inventory_state_to_peers()
	_action_counter += 1
	var trap_name: String = "Tripwire_%s_%d" % [name, _action_counter]
	var mid_pos: Vector3 = (pole1_pos + pole2_pos) * 0.5
	if AudioBridge != null:
		AudioBridge.request_world_cue("trap_arm", mid_pos, 6.0, name.to_int())
	if _is_peer_connected():
		_rpc_spawn_tripwire.rpc(trap_name, pole1_pos, pole2_pos, name.to_int())
	else:
		_spawn_tripwire_local(trap_name, pole1_pos, pole2_pos, name.to_int())


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_tripwire(trap_name: String, pole1_pos: Vector3, pole2_pos: Vector3, owner_id: int) -> void:
	if not _is_authorized_state_rpc():
		return
	_spawn_tripwire_local(trap_name, pole1_pos, pole2_pos, owner_id)


func _spawn_tripwire_local(trap_name: String, pole1_pos: Vector3, pole2_pos: Vector3, owner_id: int) -> Node:
	var target_root: Node = get_tree().current_scene if (is_inside_tree() and get_tree() != null) else null
	if target_root == null:
		var parent_node: Node = get_parent()
		if parent_node != null and parent_node.name == "Players" and parent_node.get_parent() != null:
			target_root = parent_node.get_parent()
		else:
			target_root = parent_node
	if target_root == null:
		return null
	var trap: StaticBody3D = TRIPWIRE_SCRIPT.new() as StaticBody3D
	trap.name = trap_name
	trap.set("owner_peer_id", owner_id)
	trap.call("configure_endpoints", pole1_pos, pole2_pos)
	target_root.add_child(trap)
	return trap


func fire_dart_gun(custom_origin: Vector3 = Vector3.ZERO, custom_dir: Vector3 = Vector3.ZERO) -> bool:
	if _inv().get_active_right_item_id() != "DART_GUN":
		return false
	reset_anti_camp()
	ensure_overlay_uis()
	var ray_origin: Vector3 = custom_origin
	var ray_dir: Vector3 = custom_dir
	if ray_origin == Vector3.ZERO or ray_dir == Vector3.ZERO:
		if camera != null and camera.is_inside_tree():
			var ret_pos: Vector2 = _dvd_reticle_ui.get_reticle_screen_center() if _dvd_reticle_ui != null else (get_viewport().get_visible_rect().size * 0.5)
			ray_origin = camera.project_ray_origin(ret_pos)
			ray_dir = camera.project_ray_normal(ret_pos)
		else:
			ray_origin = _safe_global_pos() + Vector3(0.0, 1.5, 0.0)
			ray_dir = -global_transform.basis.z
	ray_dir = ray_dir.normalized()
	if _dvd_reticle_ui != null:
		_dvd_reticle_ui.set_active(false)
	_trigger_vm_right_action("DART_RECOIL")
	if _ragdoll_ctrl != null:
		_ragdoll_ctrl.trigger_right_hand_action("DART_RECOIL")
	if _is_peer_connected() and not multiplayer.is_server():
		_rpc_server_fire_dart_gun.rpc_id(1, ray_origin, ray_dir)
		return true
	return _execute_dart_shot(ray_origin, ray_dir)


@rpc("any_peer", "call_local", "reliable")
func _rpc_server_fire_dart_gun(ray_origin: Vector3, ray_dir: Vector3) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != name.to_int():
		return
	_execute_dart_shot(ray_origin, ray_dir)


func _execute_dart_shot(ray_origin: Vector3, ray_dir: Vector3) -> bool:
	if _inv().consume_active_jacket_slot("DART_GUN") == "NONE":
		return false
	_sync_inventory_state_to_peers()
	var shooter_id: int = name.to_int()
	if AudioBridge != null:
		var dart_rad: float = GameConfig.audio_radius_trap_setup if GameConfig != null else 5.0
		AudioBridge.request_world_cue("dart_fire", ray_origin, dart_rad, shooter_id)
	if not is_inside_tree() or get_world_3d() == null or get_world_3d().direct_space_state == null:
		return false
	var ray_end: Vector3 = ray_origin + ray_dir.normalized() * 24.0
	var mask: int = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_PLAYER) if GameConfig != null else 5
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, mask, [get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider is Node and (collider as Node).is_in_group("spy_players"):
			if collider.has_method("apply_trap_ko"):
				var dart_kick: Vector3 = ray_dir.normalized() * 15.5 + Vector3(0.0, 5.5, 0.0)
				collider.apply_trap_ko("DART_GUN", shooter_id, dart_kick)
			return true
		return false

	# Fallback capsule-segment check along the ray segment (ensures hit resolution before broadphase flush)
	if get_tree() == null:
		return false
	var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
	var crouch_val: int = GameConfig.Stance.CROUCH if GameConfig != null else 2
	var closest_rival: Node = null
	var closest_dist_sq: float = INF
	for p in get_tree().get_nodes_in_group("spy_players"):
		if p == self or not (p is Node3D):
			continue
		var p_stance: int = int(p.get("stance_state"))
		if float(p.get("wakeup_immunity_remaining")) > 0.0:
			continue
		var p_pos: Vector3 = (p as Node3D).global_position
		var top_y: float = (GameConfig.crouched_capsule_height if GameConfig != null else 1.0) if p_stance == crouch_val else (GameConfig.standing_capsule_height if GameConfig != null else 1.8)
		var pts: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
			ray_origin, ray_end,
			p_pos + Vector3(0.0, 0.25, 0.0),
			p_pos + Vector3(0.0, top_y, 0.0)
		)
		if pts.size() == 2 and pts[0].distance_to(pts[1]) <= 0.45:
			var env_q := PhysicsRayQueryParameters3D.create(ray_origin, pts[0], env_mask, [get_rid()])
			if not space.intersect_ray(env_q).is_empty():
				continue
			var d_sq: float = ray_origin.distance_squared_to(pts[0])
			if d_sq < closest_dist_sq:
				closest_dist_sq = d_sq
				closest_rival = p
	if closest_rival != null and closest_rival.has_method("apply_trap_ko"):
		var dart_kick: Vector3 = ray_dir.normalized() * 15.5 + Vector3(0.0, 5.5, 0.0)
		closest_rival.apply_trap_ko("DART_GUN", shooter_id, dart_kick)
		return true
	return false


func begin_club_qte_charge(fixed_green_start: float = -1.0) -> bool:
	if right_hand_mode != SpyInventoryComponent.RightHandMode.CLUB or is_charging_club:
		return false
	if _club_feint_cooldown > 0.0 or _club_whiff_recovery > 0.0 or club_overcharge_stumble_remaining > 0.0:
		return false
	reset_anti_camp()
	ensure_overlay_uis()
	_trigger_hand_action("START_CLUB_CHARGE")
	if not is_charging_club:
		start_club_charge()
	if _club_qte_ui != null:
		_club_qte_ui.begin_charge(fixed_green_start)
	return true


func evaluate_club_release() -> String:
	ensure_overlay_uis()
	var outcome: String = _club_qte_ui.evaluate_release() if _club_qte_ui != null else "WHIFF"
	_trigger_hand_action("STOP_CLUB_CHARGE")
	if is_charging_club:
		stop_club_charge()
	reset_anti_camp()

	var cam_origin: Vector3 = camera.global_position if (camera != null and camera.is_inside_tree()) else (_safe_global_pos() + Vector3(0.0, 1.5, 0.0))
	var cam_forward: Vector3 = (-camera.global_transform.basis.z.normalized()) if (camera != null and camera.is_inside_tree()) else (-global_transform.basis.z.normalized())

	match outcome:
		"FEINT":
			_club_feint_cooldown = GameConfig.club_feint_cooldown if GameConfig != null else 0.40
			_trigger_vm_right_action("CLUB_FEINT")
			if _club_qte_ui != null:
				_club_qte_ui.show_outcome("FEINT!", Color(0.85, 0.85, 0.90))
		"WHIFF":
			_club_whiff_recovery = GameConfig.club_whiff_recovery_time if GameConfig != null else 0.60
			_trigger_vm_right_action("CLUB_WHIFF")
			if _ragdoll_ctrl != null:
				_ragdoll_ctrl.trigger_right_hand_action("CLUB_WHIFF")
			if _club_qte_ui != null:
				_club_qte_ui.show_outcome("WHIFF! (0.6s recovery)", Color(0.95, 0.45, 0.25))
			if AudioBridge != null:
				AudioBridge.request_world_cue("club_whoosh", cam_origin, 4.0, name.to_int())
		"KO_SLAM":
			_trigger_vm_right_action("CLUB_SWING")
			if _ragdoll_ctrl != null:
				_ragdoll_ctrl.trigger_right_hand_action("CLUB_SWING")
			if _club_qte_ui != null:
				_club_qte_ui.show_outcome("CLUB SLAM!", Color(0.30, 0.95, 0.45))
			if _is_peer_connected() and not multiplayer.is_server():
				_rpc_server_club_slam.rpc_id(1, cam_origin, cam_forward)
			else:
				_server_execute_club_slam(cam_origin, cam_forward)
		"OVERCHARGE":
			var stumble_dur: float = GameConfig.club_overcharge_stumble_duration if GameConfig != null else 2.5
			club_overcharge_stumble_remaining = stumble_dur
			if _club_qte_ui != null:
				_club_qte_ui.show_outcome("OVERCHARGED! STUMBLE (2.5s)", Color(1.0, 0.25, 0.22))
			if _is_peer_connected() and not multiplayer.is_server():
				_rpc_server_club_overcharge.rpc_id(1)
			else:
				_server_execute_club_overcharge()
	return outcome


@rpc("any_peer", "call_local", "reliable")
func _rpc_server_club_slam(cam_origin: Vector3, cam_forward: Vector3) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != name.to_int():
		return
	_server_execute_club_slam(cam_origin, cam_forward)


func _server_execute_club_slam(cam_origin: Vector3, cam_forward: Vector3) -> void:
	var my_id: int = name.to_int()
	if AudioBridge != null:
		AudioBridge.request_world_cue("club_slam", cam_origin, 8.0, my_id)
	if not is_inside_tree() or get_tree() == null:
		return
	var melee_range: float = GameConfig.club_melee_range if GameConfig != null else 2.0
	var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if get_world_3d() != null else null
	var fwd_flat: Vector3 = Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()

	var show_gizmo: bool = GameConfig != null and GameConfig.debug_club_hit_gizmo
	var gizmo_rays: Array[Dictionary] = []

	for p in get_tree().get_nodes_in_group("spy_players"):
		if p == self or not (p is Node3D):
			continue
		var target_pos: Vector3 = (p as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		var delta_vec: Vector3 = target_pos - cam_origin
		var dist: float = delta_vec.length()
		if dist > melee_range:
			continue
		var dir_flat: Vector3 = Vector3(delta_vec.x, 0.0, delta_vec.z).normalized()
		if dist > 0.75 and fwd_flat.length_squared() > 0.01 and fwd_flat.dot(dir_flat) < 0.25:
			if show_gizmo:
				gizmo_rays.append({"to": target_pos, "hit": false})
			continue
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(cam_origin, target_pos, env_mask, [get_rid()])
			var env_hit: Dictionary = space.intersect_ray(query)
			if not env_hit.is_empty():
				if show_gizmo:
					gizmo_rays.append({"to": env_hit.get("position", target_pos), "hit": false})
				continue
		if show_gizmo:
			gizmo_rays.append({"to": target_pos, "hit": true})
		if p.has_method("apply_trap_ko"):
			var club_kick: Vector3 = fwd_flat * 14.5 + Vector3(0.0, 4.8, 0.0)
			p.apply_trap_ko("CLUB", my_id, club_kick)

	if show_gizmo:
		if _club_hit_gizmo == null or not is_instance_valid(_club_hit_gizmo):
			_club_hit_gizmo = CLUB_HIT_GIZMO_SCRIPT.new()
			_club_hit_gizmo.name = "ClubHitGizmo"
			add_child(_club_hit_gizmo)
		_club_hit_gizmo.show_slam_impact(cam_origin, fwd_flat, melee_range, 0.25, gizmo_rays)


@rpc("any_peer", "call_local", "reliable")
func _rpc_server_club_overcharge() -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != name.to_int():
		return
	_server_execute_club_overcharge()


func _server_execute_club_overcharge() -> void:
	var ragdoll_dur: float = GameConfig.club_overcharge_stumble_duration if GameConfig != null else 2.5
	club_overcharge_stumble_remaining = ragdoll_dur
	if AudioBridge != null:
		AudioBridge.request_world_cue("club_stumble", _safe_global_pos(), 8.0, name.to_int())
	var back_dir: Vector3 = Vector3(global_transform.basis.z.x, 0.0, global_transform.basis.z.z).normalized() if is_inside_tree() else Vector3(0.0, 0.0, 1.0)
	if back_dir.length_squared() < 0.01:
		back_dir = Vector3(0.0, 0.0, 1.0)
	var fall_impulse: Vector3 = back_dir * 4.0 + Vector3(0.0, 1.5, 0.0)
	var start_pos: Vector3 = _safe_global_pos()
	if _is_peer_connected():
		_rpc_apply_ko_state.rpc(ragdoll_dur, 0.0, true, start_pos, rotation.y, fall_impulse, "CLUB_OVERCHARGE")
	else:
		_rpc_apply_ko_state(ragdoll_dur, 0.0, true, start_pos, rotation.y, fall_impulse, "CLUB_OVERCHARGE")


func emit_watch_bluff(cue_id: String, target_pos: Vector3) -> void:
	reset_anti_camp()
	var radius: float = GameConfig.audio_radius_bluff if GameConfig != null else 12.0
	if AudioBridge != null:
		AudioBridge.request_world_cue(cue_id, target_pos, radius, name.to_int())


func get_current_room_name() -> String:
	var pos_now: Vector3 = _safe_global_pos()
	if is_inside_tree() and get_tree() != null and get_tree().current_scene != null:
		var rooms_root: Node = get_tree().current_scene.get_node_or_null("BuildingComplex2/Rooms")
		if rooms_root != null:
			var best_name: String = ""
			var best_dist_sq: float = INF
			for r in rooms_root.get_children():
				if r is Node3D:
					var d2: float = (r as Node3D).global_position.distance_squared_to(pos_now)
					if d2 < best_dist_sq:
						best_dist_sq = d2
						best_name = r.name
			if not best_name.is_empty():
				return best_name
	return "Grid_%d_%d" % [int(floor(pos_now.x / 6.0)), int(floor(pos_now.z / 6.0))]


func reset_anti_camp() -> void:
	anti_camp_timer = 0.0
	anti_camp_sniffle_warned = false


func step_anti_camp(delta: float, room_override: String = "") -> String:
	var ko_val: int = GameConfig.Stance.KO if GameConfig != null else 4
	if stance_state == ko_val:
		return ""
	var room_key: String = room_override if not room_override.is_empty() else get_current_room_name()
	if _last_room_key.is_empty():
		_last_room_key = room_key
	elif room_key != _last_room_key:
		_last_room_key = room_key
		reset_anti_camp()
		return ""

	anti_camp_timer += delta
	var warn_sec: float = GameConfig.anti_camp_warning_seconds if GameConfig != null else 15.0
	var sneeze_sec: float = GameConfig.anti_camp_sneeze_seconds if GameConfig != null else 20.0
	var repeat_sec: float = GameConfig.anti_camp_repeat_seconds if GameConfig != null else 15.0

	if anti_camp_timer >= sneeze_sec:
		anti_camp_timer = maxf(sneeze_sec - repeat_sec, 0.0)
		anti_camp_sniffle_warned = false
		var sneeze_rad: float = GameConfig.audio_radius_sneeze if GameConfig != null else 22.0
		if AudioBridge != null:
			AudioBridge.request_world_cue("sneeze", _safe_global_pos(), sneeze_rad, name.to_int())
		if bonus_toast_label != null:
			bonus_toast_label.text = "ACHOO! (Position Revealed 22m)"
			bonus_toast_label.visible = true
			_bonus_toast_timer = 2.0
		return "SNEEZE"

	if anti_camp_timer >= warn_sec and not anti_camp_sniffle_warned:
		anti_camp_sniffle_warned = true
		if AudioBridge != null:
			AudioBridge.play_local_cue("sniffle_warning")
		if bonus_toast_label != null:
			bonus_toast_label.text = "*Sniffle* Move rooms soon!"
			bonus_toast_label.visible = true
			_bonus_toast_timer = 1.8
		return "SNIFFLE"

	return ""


func _is_aiming_for_bucket_steal(target: Object, _hit_point: Vector3, direct_bucket_hit: bool = false) -> bool:
	if target == null or not target.has_method("request_steal_bucket"):
		return false
	if not bool(target.get("has_rigged_bucket")):
		return false
	return direct_bucket_hit


func _try_begin_primary_action() -> void:
	if club_overcharge_stumble_remaining > 0.0:
		return
	var active_right: String = right_hand_item_id
	match active_right:
		"CLUB":
			begin_club_qte_charge()
		"LIVE_BOMB":
			throw_live_bomb()
		"DART_GUN":
			fire_dart_gun()
		"BUCKET":
			_try_begin_bucket_rig_hold(false)
		"TRIPWIRE":
			var tw_ctrl: TripwirePlacementController = _ensure_tripwire_controller()
			tw_ctrl.begin_lmb_hold()


func _try_begin_bucket_rig_hold(other_side: bool) -> void:
	if raycast != null and raycast.is_colliding():
		var col: Object = raycast.get_collider()
		while col is Node and not col.has_method("rig_water_bucket"):
			col = col.get_parent()
		if col != null and col.has_method("rig_water_bucket") and not bool(col.get("is_open")) and not bool(col.get("has_rigged_bucket")):
			_lmb_trap_hold_active = true
			_lmb_trap_hold_elapsed = 0.0
			_lmb_trap_mode = "BUCKET"
			_lmb_trap_target = col
			_lmb_trap_bucket_other_side = other_side


func _update_lmb_trap_hold(delta: float) -> void:
	if not _lmb_trap_hold_active:
		return
	var hold_pressed: bool = (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		if (_lmb_trap_mode == "BUCKET" and _lmb_trap_bucket_other_side)
		else Input.is_action_pressed("primary_action")
	)
	if not hold_pressed or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_lmb_trap_hold_active = false
		_lmb_trap_hold_elapsed = 0.0
		_lmb_trap_bucket_other_side = false
		if hold_progress_bar != null:
			hold_progress_bar.visible = false
		return
	var hold_req: float = GameConfig.trap_setup_hold_time if GameConfig != null else 0.80
	_lmb_trap_hold_elapsed += delta
	if hold_progress_bar != null:
		hold_progress_bar.visible = true
		hold_progress_bar.value = clampf((_lmb_trap_hold_elapsed / maxf(hold_req, 0.05)) * 100.0, 0.0, 100.0)
	if _lmb_trap_hold_elapsed >= hold_req:
		_complete_lmb_trap_rig()


func _complete_lmb_trap_rig() -> void:
	var mode: String = _lmb_trap_mode
	var target_obj: Object = _lmb_trap_target
	var other_side: bool = _lmb_trap_bucket_other_side
	_lmb_trap_hold_active = false
	_lmb_trap_hold_elapsed = 0.0
	_lmb_trap_mode = ""
	_lmb_trap_target = null
	_lmb_trap_bucket_other_side = false
	if hold_progress_bar != null:
		hold_progress_bar.visible = false
	reset_anti_camp()
	if mode == "BUCKET" and target_obj is Node and is_instance_valid(target_obj):
		var door_path: NodePath = (target_obj as Node).get_path()
		if _is_peer_connected() and not multiplayer.is_server():
			_rpc_server_rig_bucket_on_door.rpc_id(1, door_path, other_side)
		else:
			_rpc_server_rig_bucket_on_door(door_path, other_side)


func _safe_global_pos() -> Vector3:
	return global_position if is_inside_tree() else position


# ==========================================
# Visual Sockets & HUD Updates
# ==========================================

func _ensure_ragdoll_controller() -> SpyRagdollController:
	if _ragdoll_ctrl != null and is_instance_valid(_ragdoll_ctrl):
		return _ragdoll_ctrl
	var v_rig: Node3D = visual_rig if visual_rig != null else get_node_or_null("VisualRig") as Node3D
	if v_rig == null:
		v_rig = Node3D.new()
		v_rig.name = "VisualRig"
		add_child(v_rig)
		visual_rig = v_rig
	var existing: Node = v_rig.get_node_or_null("SpyRagdollController")
	if existing is SpyRagdollController:
		_ragdoll_ctrl = existing as SpyRagdollController
	else:
		_ragdoll_ctrl = RAGDOLL_CTRL_SCRIPT.new() as SpyRagdollController
		_ragdoll_ctrl.name = "SpyRagdollController"
		v_rig.add_child(_ragdoll_ctrl)
	var is_local_fp: bool = is_inside_tree() and not Engine.is_editor_hint() and is_multiplayer_authority()
	_ragdoll_ctrl.setup_for_role(spy_role, is_local_fp)
	if mesh_instance != null and _ragdoll_ctrl.agent_instance != null:
		mesh_instance.visible = false
	return _ragdoll_ctrl


func _update_mesh_color() -> void:
	if not is_inside_tree():
		return
	if mesh_instance != null:
		var mat := StandardMaterial3D.new()
		if GameConfig != null:
			mat.albedo_color = GameConfig.get_spy_role_color(spy_role)
		else:
			mat.albedo_color = COLOR_SPY_BLACK if spy_role == SpyRole.SPY_BLACK else COLOR_SPY_WHITE
		mesh_instance.material_override = mat
	_ensure_ragdoll_controller()
	if _ragdoll_ctrl != null:
		var is_local_fp: bool = not Engine.is_editor_hint() and is_multiplayer_authority()
		_ragdoll_ctrl.setup_for_role(spy_role, is_local_fp)
		if mesh_instance != null and _ragdoll_ctrl.agent_instance != null:
			mesh_instance.visible = false
	_refresh_hand_and_back_sockets()


func _set_visual_layer_recursive(node: Node, layer_mask: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer_mask
	for child in node.get_children():
		_set_visual_layer_recursive(child, layer_mask)


func apply_local_camera_cull_mask() -> void:
	var cam: Camera3D = camera if camera != null else get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null:
		return
	var all_layers: int = GameConfig.VISUAL_LAYER_ALL if GameConfig != null else 0xFFFFF
	var local_bit: int = GameConfig.VISUAL_LAYER_LOCAL_SPY_BODY if GameConfig != null else (1 << 10)
	var fp_only_bit: int = GameConfig.VISUAL_LAYER_LOCAL_FP_BODY if GameConfig != null else (1 << 14)
	var is_local_fp: bool = _ragdoll_ctrl.is_first_person_local if _ragdoll_ctrl != null else (is_inside_tree() and not Engine.is_editor_hint() and is_multiplayer_authority())
	cam.cull_mask = (all_layers & ~local_bit) if is_local_fp else (all_layers & ~fp_only_bit)


func set_crt_body_visual_layer(layer_mask: int) -> void:
	_crt_body_visual_layer = layer_mask if layer_mask > 0 else 1
	_ensure_ragdoll_controller()
	if _ragdoll_ctrl != null:
		_ragdoll_ctrl.set_body_visual_layer(_crt_body_visual_layer)
	var b_socket: Marker3D = back_club_socket if back_club_socket != null else get_node_or_null("VisualRig/BackClubSocket") as Marker3D
	if b_socket != null:
		_set_visual_layer_recursive(b_socket, _crt_body_visual_layer)
	var w_socket: Marker3D = spy_wearable_socket if spy_wearable_socket != null else get_node_or_null("VisualRig/SpyWearableSocket") as Marker3D
	if w_socket != null:
		_set_visual_layer_recursive(w_socket, _crt_body_visual_layer)
	var tp_l_socket: Marker3D = tp_left_hand_socket if tp_left_hand_socket != null else get_node_or_null("VisualRig/ThirdPersonLeftHandSocket") as Marker3D
	if tp_l_socket != null:
		_set_visual_layer_recursive(tp_l_socket, _crt_body_visual_layer)
	var tp_r_socket: Marker3D = tp_right_hand_socket if tp_right_hand_socket != null else get_node_or_null("VisualRig/ThirdPersonRightHandSocket") as Marker3D
	if tp_r_socket != null:
		_set_visual_layer_recursive(tp_r_socket, _crt_body_visual_layer)


func get_crt_body_visual_layer() -> int:
	if _ragdoll_ctrl != null:
		return _ragdoll_ctrl.body_visual_layer
	return _crt_body_visual_layer


func get_crt_pov_transform() -> Transform3D:
	if _ragdoll_ctrl != null and _ragdoll_ctrl.skeleton != null:
		return _ragdoll_ctrl.get_head_camera_world_transform()
	if head != null and head.is_inside_tree():
		return head.global_transform
	var stand_y: float = GameConfig.standing_neck_y if GameConfig != null else 1.6
	return Transform3D(Basis.from_euler(Vector3(head_pitch, rotation.y, 0.0)), _safe_global_pos() + Vector3(0.0, stand_y, 0.0))


func _clear_legacy_wearable_placeholder() -> void:
	var w_socket: Marker3D = spy_wearable_socket if spy_wearable_socket != null else get_node_or_null("VisualRig/SpyWearableSocket") as Marker3D
	if w_socket == null:
		return
	for c in w_socket.get_children():
		c.queue_free()


func _get_effective_fp_left_item_id() -> String:
	if _vm_tuner_ui != null and _vm_tuner_ui.has_preview_override(true) and not _vm_tuner_ui.is_third_person_mode():
		return _vm_tuner_ui.get_preview_item_id(true)
	return left_hand_item_id


func _get_effective_fp_right_item_id() -> String:
	if _vm_tuner_ui != null and _vm_tuner_ui.has_preview_override(false) and not _vm_tuner_ui.is_third_person_mode():
		return _vm_tuner_ui.get_preview_item_id(false)
	return right_hand_item_id


func _get_effective_tp_left_item_id() -> String:
	if _vm_tuner_ui != null and _vm_tuner_ui.has_preview_override(true) and _vm_tuner_ui.is_third_person_mode():
		return _vm_tuner_ui.get_preview_item_id(true)
	return left_hand_item_id


func _get_effective_tp_right_item_id() -> String:
	if _vm_tuner_ui != null and _vm_tuner_ui.has_preview_override(false) and _vm_tuner_ui.is_third_person_mode():
		return _vm_tuner_ui.get_preview_item_id(false)
	return right_hand_item_id


func _refresh_hand_and_back_sockets() -> void:
	_ensure_runtime_hand_poses_loaded()
	var b_socket: Marker3D = back_club_socket if back_club_socket != null else get_node_or_null("VisualRig/BackClubSocket") as Marker3D
	var tp_l_socket: Marker3D = tp_left_hand_socket if tp_left_hand_socket != null else get_node_or_null("VisualRig/ThirdPersonLeftHandSocket") as Marker3D
	var tp_r_socket: Marker3D = tp_right_hand_socket if tp_right_hand_socket != null else get_node_or_null("VisualRig/ThirdPersonRightHandSocket") as Marker3D
	var l_socket: Marker3D = left_hand_socket if left_hand_socket != null else get_node_or_null("Head/Camera3D/LeftHandSocket") as Marker3D
	var r_socket: Marker3D = right_hand_socket if right_hand_socket != null else get_node_or_null("Head/Camera3D/RightHandSocket") as Marker3D

	var eff_fp_left: String = _get_effective_fp_left_item_id()
	var eff_fp_right: String = _get_effective_fp_right_item_id()
	var eff_tp_left: String = _get_effective_tp_left_item_id()
	var eff_tp_right: String = _get_effective_tp_right_item_id()

	if b_socket != null:
		for c in b_socket.get_children():
			c.queue_free()
		if eff_tp_right != "CLUB":
			var club_back: Node3D = PICKUP_SCRIPT.build_item_visual("CLUB")
			club_back.name = "HolsteredClubMesh"
			_set_visual_layer_recursive(club_back, get_crt_body_visual_layer())
			b_socket.add_child(club_back)

	_rebuild_third_person_hand_socket(tp_l_socket, true, eff_tp_left)
	_rebuild_third_person_hand_socket(tp_r_socket, false, eff_tp_right)

	var is_local_fp: bool = _ragdoll_ctrl.is_first_person_local if _ragdoll_ctrl != null else (is_inside_tree() and not Engine.is_editor_hint() and is_multiplayer_authority())
	if _ragdoll_ctrl != null:
		_ragdoll_ctrl.set_fp_body_arm_occupancy(eff_fp_left != "NONE" and eff_fp_left != "", eff_fp_right != "NONE" and eff_fp_right != "")
	_rebuild_camera_hand_socket(l_socket, true, eff_fp_left, is_local_fp)
	_rebuild_camera_hand_socket(r_socket, false, eff_fp_right, is_local_fp)


func _rebuild_third_person_hand_socket(socket: Marker3D, is_left: bool, item_id: String) -> void:
	if socket == null:
		return
	for c in socket.get_children():
		c.queue_free()
	if item_id == "NONE" or item_id == "":
		return
	_ensure_runtime_hand_poses_loaded()
	var tp_mesh: Node3D = PICKUP_SCRIPT.build_item_visual(item_id)
	tp_mesh.name = "ThirdPersonLeftHeldMesh" if is_left else "ThirdPersonRightHeldMesh"
	var spec: Dictionary = _runtime_tp_hand_item_poses.get(item_id, {})
	_apply_mirrored_pose_spec(tp_mesh, spec, is_left)
	_set_visual_layer_recursive(tp_mesh, get_crt_body_visual_layer())
	socket.add_child(tp_mesh)


func _rebuild_camera_hand_socket(socket: Marker3D, is_left: bool, item_id: String, is_local_fp: bool) -> void:
	if socket == null:
		return
	for c in socket.get_children():
		c.queue_free()
	# Remote puppets never render first-person camera viewmodel items (prevent duplicate neck/hat props)
	if not is_local_fp:
		socket.visible = false
		return
	if item_id == "NONE" or item_id == "":
		return
	var fp_layer: int = GameConfig.VISUAL_LAYER_LOCAL_FP_BODY if GameConfig != null else (1 << 14)
	var arm_mesh: ArrayMesh = SpyRagdollController.get_camera_arm_mesh(is_left)
	if arm_mesh != null:
		var arm_mi := MeshInstance3D.new()
		arm_mi.name = "LeftCameraArm" if is_left else "RightCameraArm"
		arm_mi.mesh = arm_mesh
		arm_mi.material_override = SpyRagdollController.get_body_material_for_role(spy_role)
		arm_mi.position = _vm_arm_left_offset if is_left else _vm_arm_right_offset
		arm_mi.scale = _vm_arm_scale
		arm_mi.layers = fp_layer
		arm_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm_mi.extra_cull_margin = 16384.0
		socket.add_child(arm_mi)

	var held_mesh: Node3D = PICKUP_SCRIPT.build_item_visual(item_id)
	held_mesh.name = "LeftHeldMesh" if is_left else "RightHeldMesh"
	_apply_hand_item_pose(held_mesh, item_id, is_left)
	_set_visual_layer_recursive(held_mesh, fp_layer)
	_disable_shadows_recursive(held_mesh)
	socket.add_child(held_mesh)


func _disable_shadows_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows_recursive(child)


func _apply_hand_item_pose(mesh_node: Node3D, item_id: String, is_left: bool) -> void:
	if mesh_node == null:
		return
	_ensure_runtime_hand_poses_loaded()
	var spec: Dictionary = _runtime_hand_item_poses.get(item_id, {})
	_apply_mirrored_pose_spec(mesh_node, spec, is_left)


func _apply_mirrored_pose_spec(mesh_node: Node3D, spec: Dictionary, is_left: bool) -> void:
	if mesh_node == null or spec.is_empty():
		return
	var side_sign: float = -1.0 if is_left else 1.0
	var pos_key: String = "left_pos" if is_left else "right_pos"
	var rot_key: String = "left_rot_deg" if is_left else "right_rot_deg"
	if spec.has(pos_key):
		mesh_node.position = spec[pos_key]
	else:
		var p: Vector3 = spec.get("pos", Vector3.ZERO)
		mesh_node.position = Vector3(p.x * side_sign, p.y, p.z)
	if spec.has(rot_key):
		var rd: Vector3 = spec[rot_key]
		mesh_node.rotation = Vector3(deg_to_rad(rd.x), deg_to_rad(rd.y), deg_to_rad(rd.z))
	else:
		var r: Vector3 = spec.get("rot_deg", Vector3.ZERO)
		mesh_node.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y * side_sign), deg_to_rad(r.z * side_sign))
	mesh_node.scale = spec.get("scale", Vector3.ONE)


func _ensure_runtime_hand_poses_loaded() -> void:
	if _runtime_poses_loaded:
		return
	_runtime_poses_loaded = true
	_runtime_hand_item_poses.clear()
	_runtime_tp_hand_item_poses.clear()
	for k in _HAND_ITEM_POSES.keys():
		_runtime_hand_item_poses[k] = (_HAND_ITEM_POSES[k] as Dictionary).duplicate(true)
	for k in _TP_HAND_ITEM_POSES.keys():
		_runtime_tp_hand_item_poses[k] = (_TP_HAND_ITEM_POSES[k] as Dictionary).duplicate(true)
	if FileAccess.file_exists(_HAND_POSES_OVERRIDE_PATH):
		var f: FileAccess = FileAccess.open(_HAND_POSES_OVERRIDE_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				var d: Dictionary = parsed
				if d.has("right_base_pos"):
					var rb: Variant = d["right_base_pos"]
					if rb is Array and rb.size() >= 3:
						_vm_right_base_pos = Vector3(float(rb[0]), float(rb[1]), float(rb[2]))
						_vm_left_base_pos = Vector3(-_vm_right_base_pos.x, _vm_right_base_pos.y, _vm_right_base_pos.z)
				if d.has("right_arm_offset"):
					var ra: Variant = d["right_arm_offset"]
					if ra is Array and ra.size() >= 3:
						_vm_arm_right_offset = Vector3(float(ra[0]), float(ra[1]), float(ra[2]))
						_vm_arm_left_offset = Vector3(-_vm_arm_right_offset.x, _vm_arm_right_offset.y, _vm_arm_right_offset.z)
				if d.has("arm_scale"):
					var asc: Variant = d["arm_scale"]
					if asc is Array and asc.size() >= 3:
						_vm_arm_scale = Vector3(float(asc[0]), float(asc[1]), float(asc[2]))
				if d.has("items") and d["items"] is Dictionary:
					var items_d: Dictionary = d["items"]
					for item_k in items_d.keys():
						var raw_spec: Variant = items_d[item_k]
						if raw_spec is Dictionary:
							_runtime_hand_item_poses[str(item_k)] = _decode_json_pose_dict(raw_spec as Dictionary)
				if d.has("tp_items") and d["tp_items"] is Dictionary:
					var tp_d: Dictionary = d["tp_items"]
					for item_k in tp_d.keys():
						var raw_spec: Variant = tp_d[item_k]
						if raw_spec is Dictionary:
							_runtime_tp_hand_item_poses[str(item_k)] = _decode_json_pose_dict(raw_spec as Dictionary)


func _decode_json_pose_dict(raw_spec: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in raw_spec.keys():
		var val: Variant = raw_spec[key]
		if val is Array and (val as Array).size() >= 3:
			out[key] = Vector3(float(val[0]), float(val[1]), float(val[2]))
	return out


func _encode_json_pose_dict(spec: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in spec.keys():
		if spec[key] is Vector3:
			var v: Vector3 = spec[key]
			out[key] = [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
	return out


func get_hand_item_pose_dict(item_id: String, is_third_person: bool = false) -> Dictionary:
	_ensure_runtime_hand_poses_loaded()
	var table: Dictionary = _runtime_tp_hand_item_poses if is_third_person else _runtime_hand_item_poses
	return (table.get(item_id, {}) as Dictionary).duplicate(true)


func set_runtime_hand_item_pose(item_id: String, is_left: bool, mirror_lr: bool, vis_pos: Vector3, vis_rot_deg: Vector3, sc: Vector3, is_third_person: bool = false) -> void:
	_ensure_runtime_hand_poses_loaded()
	var table: Dictionary = _runtime_tp_hand_item_poses if is_third_person else _runtime_hand_item_poses
	var spec: Dictionary = (table.get(item_id, {}) as Dictionary).duplicate(true)
	if mirror_lr:
		var side_sign: float = -1.0 if is_left else 1.0
		spec["pos"] = Vector3(vis_pos.x * side_sign, vis_pos.y, vis_pos.z)
		spec["rot_deg"] = Vector3(vis_rot_deg.x, vis_rot_deg.y * side_sign, vis_rot_deg.z * side_sign)
		spec.erase("left_pos")
		spec.erase("left_rot_deg")
		spec.erase("right_pos")
		spec.erase("right_rot_deg")
	else:
		if not spec.has("pos"):
			spec["pos"] = Vector3.ZERO
		if not spec.has("rot_deg"):
			spec["rot_deg"] = Vector3.ZERO
		if is_left:
			spec["left_pos"] = vis_pos
			spec["left_rot_deg"] = vis_rot_deg
		else:
			spec["right_pos"] = vis_pos
			spec["right_rot_deg"] = vis_rot_deg
	spec["scale"] = sc
	table[item_id] = spec
	_apply_live_socket_transforms()


func reset_runtime_hand_item_pose(item_id: String, is_third_person: bool = false) -> void:
	_ensure_runtime_hand_poses_loaded()
	var table: Dictionary = _runtime_tp_hand_item_poses if is_third_person else _runtime_hand_item_poses
	var defaults: Dictionary = _TP_HAND_ITEM_POSES if is_third_person else _HAND_ITEM_POSES
	if defaults.has(item_id):
		table[item_id] = (defaults[item_id] as Dictionary).duplicate(true)
	else:
		table.erase(item_id)
	_apply_live_socket_transforms()


func set_tp_preview_state(active: bool, yaw_deg: float, pitch_deg: float, dist: float, height: float, sim_motion: String) -> void:
	_tp_preview_active = active
	_tp_sim_motion = sim_motion
	var fp_cam: Camera3D = camera if camera != null else get_node_or_null("Head/Camera3D") as Camera3D
	if active:
		if _tp_preview_camera == null:
			_tp_preview_camera = Camera3D.new()
			_tp_preview_camera.name = "ThirdPersonPreviewCamera"
			add_child(_tp_preview_camera)
		var all_layers: int = GameConfig.VISUAL_LAYER_ALL if GameConfig != null else 0xFFFFF
		var fp_only_bit: int = GameConfig.VISUAL_LAYER_LOCAL_FP_BODY if GameConfig != null else (1 << 14)
		_tp_preview_camera.cull_mask = all_layers & ~fp_only_bit
		var target := Vector3(0.0, height, 0.0)
		var orbit_rot := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
		var cam_pos: Vector3 = target + orbit_rot * Vector3(0.0, 0.0, -dist)
		var look_dir: Vector3 = (target - cam_pos).normalized()
		_tp_preview_camera.transform = Transform3D(Basis.looking_at(look_dir, Vector3.UP), cam_pos)
		_tp_preview_camera.current = true
		if fp_cam != null:
			fp_cam.current = false
	else:
		if _tp_preview_camera != null:
			_tp_preview_camera.current = false
		if fp_cam != null:
			fp_cam.current = true
		apply_local_camera_cull_mask()


func get_viewmodel_base_config() -> Dictionary:
	_ensure_runtime_hand_poses_loaded()
	return {
		"right_base_pos": _vm_right_base_pos,
		"right_arm_offset": _vm_arm_right_offset,
		"arm_scale": _vm_arm_scale
	}


func set_viewmodel_base_config(right_base: Vector3, right_arm_off: Vector3, arm_sc: Vector3) -> void:
	_vm_right_base_pos = right_base
	_vm_left_base_pos = Vector3(-right_base.x, right_base.y, right_base.z)
	_vm_arm_right_offset = right_arm_off
	_vm_arm_left_offset = Vector3(-right_arm_off.x, right_arm_off.y, right_arm_off.z)
	_vm_arm_scale = arm_sc
	_apply_live_socket_transforms()


func _apply_live_socket_transforms() -> void:
	var l_socket: Marker3D = left_hand_socket if left_hand_socket != null else get_node_or_null("Head/Camera3D/LeftHandSocket") as Marker3D
	var r_socket: Marker3D = right_hand_socket if right_hand_socket != null else get_node_or_null("Head/Camera3D/RightHandSocket") as Marker3D
	var eff_fp_left: String = _get_effective_fp_left_item_id()
	var eff_fp_right: String = _get_effective_fp_right_item_id()
	if l_socket != null:
		var l_arm: Node3D = l_socket.get_node_or_null("LeftCameraArm") as Node3D
		if l_arm != null:
			l_arm.position = _vm_arm_left_offset
			l_arm.scale = _vm_arm_scale
		var l_mesh: Node3D = l_socket.get_node_or_null("LeftHeldMesh") as Node3D
		if l_mesh != null:
			_apply_hand_item_pose(l_mesh, eff_fp_left, true)
	if r_socket != null:
		var r_arm: Node3D = r_socket.get_node_or_null("RightCameraArm") as Node3D
		if r_arm != null:
			r_arm.position = _vm_arm_right_offset
			r_arm.scale = _vm_arm_scale
		var r_mesh: Node3D = r_socket.get_node_or_null("RightHeldMesh") as Node3D
		if r_mesh != null:
			_apply_hand_item_pose(r_mesh, eff_fp_right, false)

	var tp_l_socket: Marker3D = tp_left_hand_socket if tp_left_hand_socket != null else get_node_or_null("VisualRig/ThirdPersonLeftHandSocket") as Marker3D
	var tp_r_socket: Marker3D = tp_right_hand_socket if tp_right_hand_socket != null else get_node_or_null("VisualRig/ThirdPersonRightHandSocket") as Marker3D
	var eff_tp_left: String = _get_effective_tp_left_item_id()
	var eff_tp_right: String = _get_effective_tp_right_item_id()
	if tp_l_socket != null:
		var tp_l_mesh: Node3D = tp_l_socket.get_node_or_null("ThirdPersonLeftHeldMesh") as Node3D
		if tp_l_mesh != null:
			_apply_mirrored_pose_spec(tp_l_mesh, _runtime_tp_hand_item_poses.get(eff_tp_left, {}), true)
	if tp_r_socket != null:
		var tp_r_mesh: Node3D = tp_r_socket.get_node_or_null("ThirdPersonRightHeldMesh") as Node3D
		if tp_r_mesh != null:
			_apply_mirrored_pose_spec(tp_r_mesh, _runtime_tp_hand_item_poses.get(eff_tp_right, {}), false)


func save_viewmodel_poses_override_file() -> bool:
	_ensure_runtime_hand_poses_loaded()
	var items_out: Dictionary = {}
	for k in _runtime_hand_item_poses.keys():
		items_out[k] = _encode_json_pose_dict(_runtime_hand_item_poses[k] as Dictionary)
	var tp_items_out: Dictionary = {}
	for k in _runtime_tp_hand_item_poses.keys():
		tp_items_out[k] = _encode_json_pose_dict(_runtime_tp_hand_item_poses[k] as Dictionary)
	var payload: Dictionary = {
		"right_base_pos": [snappedf(_vm_right_base_pos.x, 0.0001), snappedf(_vm_right_base_pos.y, 0.0001), snappedf(_vm_right_base_pos.z, 0.0001)],
		"right_arm_offset": [snappedf(_vm_arm_right_offset.x, 0.0001), snappedf(_vm_arm_right_offset.y, 0.0001), snappedf(_vm_arm_right_offset.z, 0.0001)],
		"arm_scale": [snappedf(_vm_arm_scale.x, 0.0001), snappedf(_vm_arm_scale.y, 0.0001), snappedf(_vm_arm_scale.z, 0.0001)],
		"items": items_out,
		"tp_items": tp_items_out
	}
	var f: FileAccess = FileAccess.open(_HAND_POSES_OVERRIDE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return true


func _export_pose_dict_block(const_name: String, table: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("const %s: Dictionary = {" % const_name)
	var item_order: Array[String] = ["BRIEFCASE", "KEY", "MONEY", "PASSPORT", "PLANS", "CLUB", "DART_GUN", "BOMB", "LIVE_BOMB", "BUCKET", "TRIPWIRE", "SPRING"]
	for idx in range(item_order.size()):
		var k: String = item_order[idx]
		var spec: Dictionary = table.get(k, {})
		var sub: Array[String] = []
		for sub_k in ["pos", "rot_deg", "scale", "left_pos", "left_rot_deg", "right_pos", "right_rot_deg"]:
			if spec.has(sub_k) and spec[sub_k] is Vector3:
				var v: Vector3 = spec[sub_k]
				sub.append("\t\t\"%s\": Vector3(%.3f, %.3f, %.3f)" % [sub_k, v.x, v.y, v.z])
		lines.append("\t\"%s\": {" % k)
		lines.append(",\n".join(sub))
		var comma: String = "," if idx < item_order.size() - 1 else ""
		lines.append("\t}%s" % comma)
	lines.append("}")
	return "\n".join(lines)


func export_viewmodel_poses_gdscript() -> String:
	_ensure_runtime_hand_poses_loaded()
	var lines: Array[String] = []
	lines.append("const _VM_LEFT_BASE_POS: Vector3 = Vector3(%.3f, %.3f, %.3f)" % [_vm_left_base_pos.x, _vm_left_base_pos.y, _vm_left_base_pos.z])
	lines.append("const _VM_RIGHT_BASE_POS: Vector3 = Vector3(%.3f, %.3f, %.3f)" % [_vm_right_base_pos.x, _vm_right_base_pos.y, _vm_right_base_pos.z])
	lines.append("const _VM_ARM_SCALE: Vector3 = Vector3(%.3f, %.3f, %.3f)" % [_vm_arm_scale.x, _vm_arm_scale.y, _vm_arm_scale.z])
	lines.append("const _VM_ARM_LEFT_OFFSET: Vector3 = Vector3(%.3f, %.3f, %.3f)" % [_vm_arm_left_offset.x, _vm_arm_left_offset.y, _vm_arm_left_offset.z])
	lines.append("const _VM_ARM_RIGHT_OFFSET: Vector3 = Vector3(%.3f, %.3f, %.3f)" % [_vm_arm_right_offset.x, _vm_arm_right_offset.y, _vm_arm_right_offset.z])
	lines.append(_export_pose_dict_block("_HAND_ITEM_POSES", _runtime_hand_item_poses))
	lines.append("")
	lines.append(_export_pose_dict_block("_TP_HAND_ITEM_POSES", _runtime_tp_hand_item_poses))
	return "\n".join(lines)


func _toggle_viewmodel_tuner() -> void:
	if _vm_tuner_ui == null:
		var target_hud: CanvasLayer = hud if hud != null else get_node_or_null("HUD") as CanvasLayer
		var parent_node: Node = target_hud if target_hud != null else self
		_vm_tuner_ui = VM_TUNER_UI_SCRIPT.new()
		_vm_tuner_ui.name = "ViewmodelOffsetTunerUI"
		parent_node.add_child(_vm_tuner_ui)
		_vm_tuner_ui.setup(self)
		_vm_tuner_ui.preview_changed.connect(_refresh_hand_and_back_sockets)
	_vm_tuner_ui.toggle_open()


func _trigger_vm_right_action(action_type: String) -> void:
	match action_type.to_upper():
		"CLUB_SWING":
			_vm_right_action = "CLUB_SWING"
			_vm_right_action_dur = 0.26
			_vm_right_action_timer = 0.26
		"CLUB_WHIFF":
			_vm_right_action = "CLUB_WHIFF"
			_vm_right_action_dur = 0.34
			_vm_right_action_timer = 0.34
		"CLUB_FEINT":
			_vm_right_action = "CLUB_FEINT"
			_vm_right_action_dur = 0.20
			_vm_right_action_timer = 0.20
		"DART_RECOIL":
			_vm_right_action = "DART_RECOIL"
			_vm_right_action_dur = 0.22
			_vm_right_action_timer = 0.22
		"THROW":
			_vm_right_action = "THROW"
			_vm_right_action_dur = 0.24
			_vm_right_action_timer = 0.24


func _update_first_person_viewmodel(delta: float) -> void:
	var l_socket: Marker3D = left_hand_socket if left_hand_socket != null else get_node_or_null("Head/Camera3D/LeftHandSocket") as Marker3D
	var r_socket: Marker3D = right_hand_socket if right_hand_socket != null else get_node_or_null("Head/Camera3D/RightHandSocket") as Marker3D
	if l_socket == null and r_socket == null:
		return

	var ko_val: int = GameConfig.Stance.KO if GameConfig != null else 4
	var lock_val: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	var sprint_val: int = GameConfig.Stance.SPRINT if GameConfig != null else 1
	var hide_hands: bool = (stance_state == ko_val or stance_state == lock_val)
	var eff_left: String = _get_effective_fp_left_item_id()
	var eff_right: String = _get_effective_fp_right_item_id()
	if _ragdoll_ctrl != null:
		_ragdoll_ctrl.set_fp_body_visible(not hide_hands)
	if l_socket != null:
		l_socket.visible = not hide_hands and (eff_left != "NONE" and eff_left != "")
	if r_socket != null:
		r_socket.visible = not hide_hands and (eff_right != "NONE" and eff_right != "")
	if hide_hands:
		return

	var cur_left: String = eff_left
	var cur_right: String = eff_right
	if cur_left != _vm_last_left_id:
		_vm_last_left_id = cur_left
		_vm_left_equip = 1.0
	if cur_right != _vm_last_right_id:
		_vm_last_right_id = cur_right
		_vm_right_equip = 1.0

	_vm_left_equip = move_toward(_vm_left_equip, 0.0, delta * 4.5)
	_vm_right_equip = move_toward(_vm_right_equip, 0.0, delta * 4.5)
	_vm_idle_time += delta

	var horiz_spd: float = Vector2(velocity.x, velocity.z).length()
	var climb_spd: float = absf(_climb_vertical_speed) if is_climbing_ladder else 0.0
	var move_norm: float = clampf(climb_spd / LADDER_CLIMB_SPEED, 0.0, 1.0) * 0.75 if is_climbing_ladder else clampf(horiz_spd / 6.8, 0.0, 1.0)
	if is_climbing_ladder:
		if climb_spd > 0.12:
			_vm_walk_phase = wrapf(_vm_walk_phase + delta * _climb_vertical_speed * 3.6, 0.0, TAU)
	elif horiz_spd > 0.25 and is_on_floor():
		_vm_walk_phase = fmod(_vm_walk_phase + delta * horiz_spd * 2.2, TAU)
	else:
		_vm_walk_phase = move_toward(_vm_walk_phase, 0.0, delta * 8.0)

	_vm_sprint_blend = lerpf(_vm_sprint_blend, 1.0 if (stance_state == sprint_val and horiz_spd > 1.0) else 0.0, clampf(delta * 10.0, 0.0, 1.0))
	_vm_club_charge_blend = lerpf(_vm_club_charge_blend, 1.0 if (cur_right == "CLUB" and is_charging_club) else 0.0, clampf(delta * 12.0, 0.0, 1.0))
	_vm_dart_aim_blend = lerpf(_vm_dart_aim_blend, 1.0 if _is_aiming_dart_gun() else 0.0, clampf(delta * 12.0, 0.0, 1.0))

	_vm_sway_pos = _vm_sway_pos.lerp(_vm_sway_vel, clampf(delta * 18.0, 0.0, 1.0))
	_vm_sway_vel = _vm_sway_vel.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))

	if _vm_right_action_timer > 0.0:
		_vm_right_action_timer = maxf(_vm_right_action_timer - delta, 0.0)
		if _vm_right_action_timer <= 0.0:
			_vm_right_action = ""

	var idle_y: float = sin(_vm_idle_time * 2.1) * 0.0045
	var idle_rx: float = cos(_vm_idle_time * 1.6) * 0.012
	var bob_x: float = cos(_vm_walk_phase) * 0.018 * move_norm
	var bob_y: float = -absf(sin(_vm_walk_phase)) * 0.022 * move_norm
	var sway_x: float = clampf(-_vm_sway_pos.x * 0.0018, -0.045, 0.045)
	var sway_y: float = clampf(_vm_sway_pos.y * 0.0018, -0.045, 0.045)

	if l_socket != null:
		var equip_dip_l: float = _vm_left_equip * _vm_left_equip
		var l_pos: Vector3 = _vm_left_base_pos + Vector3(
			bob_x + sway_x - _vm_sprint_blend * 0.03,
			idle_y + bob_y + sway_y - equip_dip_l * 0.20 - _vm_sprint_blend * 0.04,
			_vm_sprint_blend * 0.04
		)
		var l_rot := Vector3(
			idle_rx - equip_dip_l * 0.65 - _vm_sprint_blend * 0.18 + sway_y * 1.4,
			-sway_x * 1.6 + _vm_sprint_blend * 0.15,
			bob_x * 1.8
		)
		l_socket.position = l_pos
		l_socket.rotation = l_rot

	if r_socket != null:
		var equip_dip_r: float = _vm_right_equip * _vm_right_equip
		var r_pos: Vector3 = _vm_right_base_pos + Vector3(
			-bob_x + sway_x + _vm_sprint_blend * 0.03,
			idle_y + bob_y + sway_y - equip_dip_r * 0.20 - _vm_sprint_blend * 0.04,
			_vm_sprint_blend * 0.04
		)
		var r_rot := Vector3(
			idle_rx - equip_dip_r * 0.65 - _vm_sprint_blend * 0.22 + sway_y * 1.4,
			-sway_x * 1.6 - _vm_sprint_blend * 0.18,
			-bob_x * 1.8
		)

		if _vm_club_charge_blend > 0.001:
			var jitter: float = sin(_vm_idle_time * 38.0) * 0.003 * _vm_club_charge_blend
			r_pos = r_pos.lerp(Vector3(0.24 + jitter, 0.04 + jitter, -0.44), _vm_club_charge_blend)
			r_rot = r_rot.lerp(Vector3(deg_to_rad(28.0), deg_to_rad(14.0), deg_to_rad(-18.0)), _vm_club_charge_blend)

		if _vm_dart_aim_blend > 0.001:
			r_pos = r_pos.lerp(Vector3(0.22, -0.18, -0.46), _vm_dart_aim_blend)
			r_rot = r_rot.lerp(Vector3(0.0, deg_to_rad(6.0), 0.0), _vm_dart_aim_blend)

		if _vm_right_action_timer > 0.0 and _vm_right_action_dur > 0.001:
			var prog: float = 1.0 - clampf(_vm_right_action_timer / _vm_right_action_dur, 0.0, 1.0)
			var arc: float = sin(prog * PI)
			match _vm_right_action:
				"CLUB_SWING", "CLUB_WHIFF":
					r_pos = r_pos.lerp(Vector3(-0.22, -0.32, -0.62), arc)
					r_rot = r_rot.lerp(Vector3(deg_to_rad(-78.0), deg_to_rad(32.0), deg_to_rad(52.0)), arc)
				"CLUB_FEINT":
					r_pos = r_pos.lerp(Vector3(0.26, -0.32, -0.46), arc)
					r_rot = r_rot.lerp(Vector3(deg_to_rad(-20.0), 0.0, deg_to_rad(10.0)), arc)
				"DART_RECOIL":
					r_pos += Vector3(0.0, 0.03 * arc, 0.12 * arc)
					r_rot.x += deg_to_rad(24.0) * arc
				"THROW":
					r_pos = r_pos.lerp(Vector3(0.14, -0.14, -0.68), arc)
					r_rot = r_rot.lerp(Vector3(deg_to_rad(-42.0), deg_to_rad(12.0), 0.0), arc)

		r_socket.position = r_pos
		r_socket.rotation = r_rot


func _update_hud_status() -> void:
	var l_lbl: Label = left_hand_label if left_hand_label != null else get_node_or_null("HUD/StatusBar/HBox/LeftHandLabel") as Label
	var s_lbl: Label = stance_label if stance_label != null else get_node_or_null("HUD/StatusBar/HBox/StanceLabel") as Label
	var r_lbl: Label = right_hand_label if right_hand_label != null else get_node_or_null("HUD/StatusBar/HBox/RightHandLabel") as Label

	if l_lbl != null:
		l_lbl.text = "LEFT [Q]: %s" % PICKUP_SCRIPT.get_display_name(left_hand_item_id, briefcase_objectives)

	if r_lbl != null:
		var inv: SpyInventoryComponent = _inv()
		var slot_parts: Array[String] = []
		for i in range(SpyInventoryComponent.JACKET_SLOT_COUNT):
			var item_str: String = inv.jacket_slots[i] if i < inv.jacket_slots.size() else "NONE"
			var short_name: String = "--" if item_str == "NONE" else PICKUP_SCRIPT.get_display_name(item_str)
			if inv.right_hand_mode == SpyInventoryComponent.RightHandMode.JACKET_SLOT and i == inv.active_jacket_slot:
				slot_parts.append("[%d:%s]" % [i + 1, short_name])
			else:
				slot_parts.append("%d:%s" % [i + 1, short_name])
		var coat_text: String = "COAT [1-3/G]: " + " | ".join(slot_parts)
		if inv.right_hand_mode == SpyInventoryComponent.RightHandMode.LIVE_BOMB:
			r_lbl.text = "ACTIVE: LIVE BOMB! (Throw LMB)  |  " + coat_text
		elif inv.right_hand_mode == SpyInventoryComponent.RightHandMode.CLUB:
			var club_state: String = "CHARGE!" if inv.is_charging_club else "Two-Handed Club"
			r_lbl.text = "%s  |  CLUB [4/R]: %s" % [coat_text, club_state]
		else:
			r_lbl.text = "%s  |  [4/R]: Club (Back)" % coat_text

	if s_lbl != null:
		var spd: float = get_current_move_speed()
		if is_charging_club:
			s_lbl.text = "CLUB CHARGE (%.1f m/s)" % spd
		else:
			match stance_state:
				1:
					s_lbl.text = "SPRINT (%.1f m/s - LOUD)" % spd
				2:
					s_lbl.text = "CROUCH (%.1f m/s - SILENT)" % spd
				3:
					s_lbl.text = "SEARCHING DRAWER"
				4:
					s_lbl.text = "KNOCKED OUT (15s)"
				_:
					s_lbl.text = "WALK (%.1f m/s)" % spd


# ==========================================
# Sprint Door Auto-Bash (Doc 2 §2.A & Doc 3 §2.A)
# ==========================================

func _on_door_bash_body_entered(body: Node) -> void:
	_try_sprint_bash_target(body)


func _on_door_bash_area_entered(area: Area3D) -> void:
	_try_sprint_bash_target(area)


func _try_sprint_bash_target(node: Node) -> void:
	if not is_multiplayer_authority():
		return
	if stance_state != (GameConfig.Stance.SPRINT if GameConfig != null else 1):
		return

	var cursor: Node = node
	while cursor != null:
		if cursor.has_method("request_sprint_bash"):
			cursor.request_sprint_bash(multiplayer.get_unique_id() if _is_peer_connected() else 1, global_position)
			return
		elif cursor.has_method("request_interaction") and String(cursor.name).contains("Door"):
			if not bool(cursor.get("is_open")):
				cursor.request_interaction(multiplayer.get_unique_id() if _is_peer_connected() else 1)
				if AudioBridge != null:
					AudioBridge.request_world_cue("door_bash", cursor.global_position, GameConfig.audio_radius_door_bash, name.to_int())
			return
		cursor = cursor.get_parent()


# ==========================================
# Frame Processing & Input Handling
# ==========================================

func _set(property: StringName, value: Variant) -> bool:
	if not is_inside_tree():
		return false
	if not is_multiplayer_authority():
		if property == &"position":
			_target_position = value
			if not _initial_pos_set:
				_initial_pos_set = true
				return false
			return true
		elif property == &"rotation:y":
			_target_yaw = value
			if not _initial_yaw_set:
				_initial_yaw_set = true
				return false
			return true
		elif property == &"rotation":
			_target_yaw = (value as Vector3).y
			if not _initial_yaw_set:
				_initial_yaw_set = true
				return false
			return true
	return false


func _is_aiming_dart_gun() -> bool:
	var ko_val: int = GameConfig.Stance.KO if GameConfig != null else 4
	var lock_val: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	return (
		right_hand_item_id == "DART_GUN"
		and stance_state != ko_val
		and stance_state != lock_val
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	)


func _is_peer_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or (_is_peer_connected() and not is_multiplayer_authority()):
		return

	if _club_feint_cooldown > 0.0:
		_club_feint_cooldown = maxf(_club_feint_cooldown - delta, 0.0)
	if _club_whiff_recovery > 0.0:
		_club_whiff_recovery = maxf(_club_whiff_recovery - delta, 0.0)
	if club_overcharge_stumble_remaining > 0.0:
		club_overcharge_stumble_remaining = maxf(club_overcharge_stumble_remaining - delta, 0.0)
	if _club_charge_exit_lerp_active:
		var exit_dur: float = GameConfig.club_charge_exit_lerp_duration if GameConfig != null else 0.40
		_club_charge_exit_lerp_elapsed += delta
		if _club_charge_exit_lerp_elapsed >= exit_dur:
			_club_charge_exit_lerp_active = false
			_club_charge_exit_lerp_elapsed = 0.0

	if _bonus_toast_timer > 0.0:
		_bonus_toast_timer -= delta
		if _bonus_toast_timer <= 0.0 and bonus_toast_label != null:
			bonus_toast_label.visible = false

	if _sens_toast_timer > 0.0:
		_sens_toast_timer -= delta
		if _sens_toast_timer <= 0.0:
			prompt_label.visible = false
		return

	var lock_stance: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	var ko_stance: int = GameConfig.Stance.KO if GameConfig != null else 4
	if stance_state == ko_stance:
		_reset_interact_hold()
		cancel_tripwire_placement()
		if _dvd_reticle_ui != null:
			_dvd_reticle_ui.set_active(false)
		_sync_camera_to_ragdoll_head()
		return

	step_live_bomb_fuse(delta)
	step_anti_camp(delta)

	if _interact_key_down:
		_tick_active_interact_hold(delta)
	if stance_state == lock_stance:
		prompt_label.visible = false
		cancel_tripwire_placement()
		if _dvd_reticle_ui != null:
			_dvd_reticle_ui.set_active(false)
		if not _active_3d_slides.is_empty():
			_step_active_3d_slides(delta)
		_tick_drawer_open_input(delta)
		return

	if _dvd_reticle_ui != null:
		_dvd_reticle_ui.set_active(_is_aiming_dart_gun())

	if is_charging_club and _club_qte_ui != null:
		if _club_qte_ui.update_charge(delta) == "OVERCHARGED":
			evaluate_club_release()

	_update_lmb_trap_hold(delta)
	var tw_ctrl: TripwirePlacementController = _ensure_tripwire_controller()
	var tw_equipped: bool = (
		right_hand_item_id == "TRIPWIRE"
		and not is_clock_eliminated
		and club_overcharge_stumble_remaining <= 0.0
	)
	tw_ctrl.step(
		delta,
		tw_equipped,
		Input.is_action_pressed("primary_action"),
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		true
	)
	if tw_ctrl.is_holding_lmb() and hold_progress_bar != null:
		hold_progress_bar.visible = true
		hold_progress_bar.value = tw_ctrl.get_hold_progress() * 100.0
	_process_interaction_raycast()
	_update_first_person_viewmodel(delta)


func _is_e_key_pressed() -> bool:
	return (
		Input.is_action_pressed("interact_primary")
		or Input.is_action_pressed("interact")
		or Input.is_key_pressed(KEY_E)
	)


func _tick_drawer_open_input(delta: float) -> void:
	if active_container == null or not is_instance_valid(active_container):
		return
	if bool(active_container.get("is_slow_opening")):
		_drawer_e_held = false
		_drawer_e_hold_elapsed = 0.0
		return
	var e_down: bool = _is_e_key_pressed()
	if _drawer_focus_just_entered:
		if not e_down:
			_drawer_focus_just_entered = false
		return

	var my_peer_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
	var open_prog: float = float(active_container.get("drawer_open_progress"))
	if e_down:
		if open_prog >= 0.999:
			return
		if not _drawer_e_held:
			_drawer_e_held = true
			_drawer_e_hold_elapsed = 0.0
		_drawer_e_hold_elapsed += delta
		if _drawer_e_hold_elapsed >= TAP_RELEASE_THRESHOLD:
			_drawer_e_held = false
			_drawer_e_hold_elapsed = 0.0
			if active_container.has_method("request_start_slow_open"):
				active_container.request_start_slow_open(my_peer_id)
			elif active_container.has_method("request_hold_interaction"):
				active_container.request_hold_interaction(my_peer_id)
	elif _drawer_e_held:
		if _drawer_e_hold_elapsed < TAP_RELEASE_THRESHOLD and open_prog < 0.999:
			active_container.request_interaction(my_peer_id)
		_drawer_e_held = false
		_drawer_e_hold_elapsed = 0.0


func _tick_active_interact_hold(delta: float) -> void:
	var e_down: bool = _is_e_key_pressed()
	if _interact_target == null or not is_instance_valid(_interact_target):
		if not e_down:
			_reset_interact_hold()
		return

	var my_peer_id: int = multiplayer.get_unique_id() if _is_peer_connected() else 1
	if _interact_steal_bucket:
		var steal_dur: float = GameConfig.trap_steal_hold_time if GameConfig != null else 1.00
		if e_down:
			if not _interact_hold_triggered:
				_interact_hold_elapsed += delta
				if hold_progress_bar != null:
					hold_progress_bar.visible = true
					hold_progress_bar.value = clampf((_interact_hold_elapsed / maxf(steal_dur, 0.05)) * 100.0, 0.0, 100.0)
				if _interact_hold_elapsed >= steal_dur:
					_interact_hold_triggered = true
					_interact_target.request_steal_bucket(my_peer_id)
					if hold_progress_bar != null:
						hold_progress_bar.visible = false
		else:
			if not _interact_hold_triggered and _interact_hold_elapsed < TAP_RELEASE_THRESHOLD:
				_interact_target.request_interaction(my_peer_id)
			_reset_interact_hold()
		return

	var supports_hold: bool = (
		_interact_target.has_method("request_hold_interaction")
		and (not _interact_target.has_method("supports_hold_interaction") or bool(_interact_target.supports_hold_interaction()))
	)
	if not supports_hold:
		if not e_down:
			_reset_interact_hold()
		return

	if _interact_target.has_method("request_step_push"):
		if e_down:
			_interact_hold_elapsed += delta
			if _interact_hold_elapsed >= TAP_RELEASE_THRESHOLD:
				_interact_hold_triggered = true
				var cur_open_i: int = 1 if (_interact_target.get("is_open") == true) else 0
				if _interact_step_push_want_open == -1 or cur_open_i != _interact_step_push_want_open:
					_interact_target.request_step_push(my_peer_id, delta, _interact_step_push_want_open)
		else:
			if not _interact_hold_triggered:
				_interact_target.request_interaction(my_peer_id)
			_reset_interact_hold()
		return

	var hold_dur: float = (
		float(_interact_target.get_hold_interaction_duration())
		if _interact_target.has_method("get_hold_interaction_duration")
		else (GameConfig.door_slow_peek_hold_time if GameConfig != null else 2.80)
	)
	if e_down:
		if not _interact_hold_triggered:
			_interact_hold_elapsed += delta
			if hold_progress_bar != null:
				hold_progress_bar.visible = true
				hold_progress_bar.value = clampf((_interact_hold_elapsed / maxf(hold_dur, 0.05)) * 100.0, 0.0, 100.0)
			if _interact_hold_elapsed >= hold_dur:
				_interact_hold_triggered = true
				_interact_target.request_hold_interaction(my_peer_id)
				if hold_progress_bar != null:
					hold_progress_bar.visible = false
	else:
		if not _interact_hold_triggered:
			_interact_target.request_interaction(my_peer_id)
		_reset_interact_hold()


func _process_interaction_raycast() -> void:
	if is_instance_valid(_active_ladder):
		prompt_label.hide()
		return

	var is_interactable: bool = false
	var target_collider: Object = null
	var hit_point: Vector3 = Vector3.ZERO
	var aiming_bucket_steal: bool = false

	if raycast != null and raycast.is_colliding():
		hit_point = raycast.get_collision_point()
		var collider: Object = raycast.get_collider()
		var direct_bucket_hit: bool = false
		if collider is Node and (collider as Node).has_meta("bucket_door"):
			var door_ref: Object = (collider as Node).get_meta("bucket_door")
			if door_ref != null and is_instance_valid(door_ref) and door_ref.has_method("request_interaction"):
				collider = door_ref
				direct_bucket_hit = true
		while collider is Node and not collider.has_method("request_interaction"):
			collider = collider.get_parent()
		if collider and collider.has_method("request_interaction"):
			is_interactable = true
			target_collider = collider
			aiming_bucket_steal = _is_aiming_for_bucket_steal(target_collider, hit_point, direct_bucket_hit)

	if live_bomb_remaining <= 0.0:
		var tw_active_step2: bool = (_tripwire_ctrl != null and _tripwire_ctrl.has_placed_first_pole())
		if is_interactable:
			var p_text: String = "[Hold E 1.0s] Steal Rigged Water Bucket" if aiming_bucket_steal else (
				target_collider.get_interaction_prompt_for_player(self) if target_collider.has_method("get_interaction_prompt_for_player") else (
					target_collider.get_interaction_prompt() if target_collider.has_method("get_interaction_prompt") else "[E] Interact"
				)
			)
			if right_hand_item_id == "BUCKET" and target_collider.has_method("rig_water_bucket") and not bool(target_collider.get("is_open")) and not bool(target_collider.get("has_rigged_bucket")):
				p_text += "  |  [Hold LMB] Rig Bucket (This Side)  |  [Hold RMB] Rig Bucket (Other Side)"
			elif tw_active_step2:
				p_text += "  |  [RMB] Cancel Tripwire"
			prompt_label.text = p_text
			prompt_label.visible = not p_text.is_empty()
		elif right_hand_item_id == "TRIPWIRE" and _tripwire_ctrl != null:
			var tw_prompt: String = _tripwire_ctrl.get_prompt_text()
			prompt_label.text = tw_prompt
			prompt_label.visible = not tw_prompt.is_empty()
		else:
			prompt_label.visible = false

	var tw_holding: bool = (_tripwire_ctrl != null and _tripwire_ctrl.is_holding_lmb())
	if hold_progress_bar != null and not _lmb_trap_hold_active and not tw_holding and not _interact_key_down:
		hold_progress_bar.visible = false

	var e_down: bool = _is_e_key_pressed()
	var e_just_pressed: bool = (
		Input.is_action_just_pressed("interact_primary")
		or Input.is_action_just_pressed("interact")
		or (e_down and not _interact_key_down)
	)

	var my_peer_id: int = multiplayer.get_unique_id() if _is_peer_connected() else 1
	if is_interactable and target_collider != null and e_just_pressed and not _interact_key_down:
		_try_trigger_interact_target(target_collider, aiming_bucket_steal, my_peer_id)


func _try_trigger_interact_target(target_collider: Object, aiming_bucket_steal: bool, my_peer_id: int) -> bool:
	if target_collider == null or not is_instance_valid(target_collider):
		return false
	reset_anti_camp()
	if target_collider.has_method("request_focus_container"):
		_drawer_focus_just_entered = true
		target_collider.request_focus_container(my_peer_id)
		return true
	# Playtest Briefcase rule: ONLY when target pickup IS a floor Briefcase and player holds a loose Objective,
	# pressing E enters two-stage Briefcase Focus/Search Mode instead of picking it up!
	var target_item_id_v: Variant = target_collider.get("item_id")
	var is_target_briefcase: bool = (target_item_id_v is String and PICKUP_SCRIPT.is_briefcase_item(str(target_item_id_v)))
	if is_target_briefcase and target_collider.has_method("request_focus_briefcase") and PICKUP_SCRIPT.is_objective_item(left_hand_item_id):
		_drawer_focus_just_entered = true
		target_collider.request_focus_briefcase(my_peer_id)
		return true
	var supports_hold: bool = aiming_bucket_steal or (
		target_collider.has_method("request_hold_interaction")
		and (not target_collider.has_method("supports_hold_interaction") or bool(target_collider.supports_hold_interaction()))
	)
	_interact_key_down = true
	_interact_hold_elapsed = 0.0
	_interact_hold_triggered = false
	_interact_target = target_collider
	_interact_steal_bucket = aiming_bucket_steal
	_interact_step_push_want_open = (0 if (target_collider.get("is_open") == true) else 1) if target_collider.has_method("request_step_push") else -1
	if not supports_hold:
		_interact_hold_triggered = true
		target_collider.request_interaction(my_peer_id)
	return true


func _reset_interact_hold() -> void:
	_interact_key_down = false
	_interact_hold_elapsed = 0.0
	_interact_hold_triggered = false
	_interact_target = null
	_interact_steal_bucket = false
	_interact_step_push_want_open = -1
	var tw_holding: bool = (_tripwire_ctrl != null and _tripwire_ctrl.is_holding_lmb())
	if hold_progress_bar != null and not _lmb_trap_hold_active and not tw_holding:
		hold_progress_bar.visible = false


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_multiplayer_authority():
		return

	var lock_stance: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	if stance_state == lock_stance:
		var is_slow_opening_now: bool = (active_container != null and is_instance_valid(active_container) and bool(active_container.get("is_slow_opening")))
		var is_exit_key: bool = (
			event.is_action_pressed("move_left")
			or event.is_action_pressed("move_back")
			or event.is_action_pressed("move_right")
			or event.is_action_pressed("ui_cancel")
			or (event is InputEventKey and event.pressed and not event.is_echo() and (event.keycode in [KEY_A, KEY_S, KEY_D, KEY_ESCAPE]))
		)
		if is_exit_key:
			if is_slow_opening_now:
				get_viewport().set_input_as_handled()
				return
			if _drag_3d_active and get_viewport() != null:
				_finish_container_3d_drag(get_viewport().get_mouse_position())
			else:
				_clear_drag_3d_state()
			_flush_active_3d_slides(true)
			if _container_ui != null and _container_ui.has_method("flush_active_briefcase_slides"):
				_container_ui.flush_active_briefcase_slides()
			var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
			if active_container != null and is_instance_valid(active_container) and active_container.has_method("request_close_container"):
				active_container.request_close_container(my_id)
			else:
				exit_container_view()
			get_viewport().set_input_as_handled()
			return

		if active_container != null and is_instance_valid(active_container) and camera != null:
			if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
				if event.pressed:
					if not _is_point_over_interactive_ui(event.position):
						if _handle_container_3d_mouse_down(event.position, event.button_index):
							get_viewport().set_input_as_handled()
				elif event.button_index == MOUSE_BUTTON_LEFT:
					if _drag_3d_active:
						_finish_container_3d_drag(event.position)
						get_viewport().set_input_as_handled()
			elif event is InputEventMouseMotion:
				if _drag_3d_active:
					_update_container_3d_drag(event.position)
					get_viewport().set_input_as_handled()


func _is_point_over_interactive_ui(screen_pos: Vector2) -> bool:
	if _container_ui == null or not is_instance_valid(_container_ui):
		return false
	if _container_ui.has_method("is_point_over_ui_panel") and bool(_container_ui.is_point_over_ui_panel(screen_pos)):
		return true
	for btn in _container_ui.find_children("*", "Button", true, false):
		if btn is Control and (btn as Control).is_visible_in_tree():
			if (btn as Control).get_global_rect().has_point(screen_pos):
				return true
	return false


func _raycast_container_3d(screen_pos: Vector2) -> Dictionary:
	if camera == null or active_container == null or not is_instance_valid(active_container):
		return {}
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	if active_container.has_method("pick_drawer_object_at_ray"):
		return active_container.pick_drawer_object_at_ray(ray_origin, ray_dir)
	if get_world_3d() == null:
		return {}
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 4.0, 32)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider_node: Node = hit.get("collider") as Node
	if collider_node == null or not active_container.is_ancestor_of(collider_node):
		return {}
	if not bool(active_container.get("is_briefcase_container")) and active_container is Node3D:
		var local_hit: Vector3 = (active_container as Node3D).to_local(hit["position"])
		if local_hit.z < 0.34:
			return {}
	return hit


func _clear_drag_3d_state() -> void:
	_drag_3d_active = false
	_drag_3d_role = ""
	_drag_3d_clutter_idx = -1
	_drag_3d_item_id = ""
	_drag_3d_node = null
	_drag_3d_plane_y = 0.0
	_drag_3d_offset_xz = Vector2.ZERO
	_drag_3d_start_screen_pos = Vector2.ZERO
	_drag_3d_moved = false
	_drag_3d_samples.clear()
	if _container_ui != null and _container_ui.has_method("clear_external_3d_item_drag"):
		_container_ui.clear_external_3d_item_drag()


func _make_3d_slide_key(role: String, clutter_idx: int, item_id: String) -> String:
	if role == "clutter":
		return "clutter:%d" % clutter_idx
	if role == "planted_bomb":
		return "planted_bomb:BOMB"
	return "%s:%s" % [role, item_id.to_upper()]


func _handle_container_3d_mouse_down(screen_pos: Vector2, button_index: int) -> bool:
	var hit: Dictionary = _raycast_container_3d(screen_pos)
	if hit.is_empty():
		return false
	var hit_area: Node3D = hit["collider"] as Node3D
	var hit_pos: Vector3 = hit["position"]
	var role: String = str(hit_area.get_meta("container_role", ""))
	var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
	var is_slow_opening_now: bool = bool(active_container.get("is_slow_opening"))
	if is_slow_opening_now:
		if role == "lip_spring" and bool(active_container.get("armed_spring")) and button_index == MOUSE_BUTTON_LEFT:
			active_container.request_unlatch_spring(my_id)
			return true
		return false

	if role in ["clutter", "loot_item", "planted_bomb"]:
		if button_index != MOUSE_BUTTON_LEFT:
			return false
		var tray: Node3D = active_container.get_tray_node() if active_container.has_method("get_tray_node") else null
		if tray == null:
			return false
		var local_hit: Vector3 = tray.to_local(hit_pos)
		if camera != null:
			var drag_orig: Vector3 = camera.project_ray_origin(screen_pos)
			var drag_dir: Vector3 = camera.project_ray_normal(screen_pos)
			var plane_hit: Variant = Plane(Vector3.UP, hit_area.global_position.y).intersects_ray(drag_orig, drag_dir)
			if plane_hit is Vector3:
				local_hit = tray.to_local(plane_hit as Vector3)
		var c_idx: int = int(hit_area.get_meta("clutter_idx", -1)) if role == "clutter" else -1
		var item_id: String = "BOMB" if role == "planted_bomb" else (str(hit_area.get_meta("item_id", "")).to_upper() if role == "loot_item" else "")
		_active_3d_slides.erase(_make_3d_slide_key(role, c_idx, item_id))
		_drag_3d_active = true
		_drag_3d_role = role
		_drag_3d_clutter_idx = c_idx
		_drag_3d_item_id = item_id
		_drag_3d_node = hit_area
		_drag_3d_plane_y = hit_area.global_position.y
		_drag_3d_offset_xz = Vector2(hit_area.position.x - local_hit.x, hit_area.position.z - local_hit.z)
		_drag_3d_start_screen_pos = screen_pos
		_drag_3d_moved = false
		_drag_3d_samples.clear()
		hit_area.position.y = float(hit_area.get_meta("base_y", hit_area.position.y))
		var start_norm: Vector2 = (
			active_container.container_local_xz_to_norm(hit_area.position.x, hit_area.position.z)
			if active_container.has_method("container_local_xz_to_norm")
			else Vector2(0.5, 0.5)
		)
		SHOVE_PHYSICS.record_sample(_drag_3d_samples, start_norm, Time.get_ticks_usec() * 1e-6)
		return true

	match role:
		"lip_spring":
			if bool(active_container.get("armed_spring")) and button_index == MOUSE_BUTTON_LEFT:
				active_container.request_unlatch_spring(my_id)
				return true
			elif bool(active_container.get("spring_unlatched")):
				if button_index == MOUSE_BUTTON_RIGHT:
					active_container.request_rearm_spring(my_id)
				elif _container_ui != null and _container_ui.has_method("begin_external_drag"):
					_container_ui.begin_external_drag("CONTAINER_SPRING", "SPRING", screen_pos, -1)
				else:
					active_container.request_steal_spring(my_id, -1)
				return true
		"lit_bomb":
			if button_index == MOUSE_BUTTON_LEFT and active_container.has_method("request_grab_lit_bomb"):
				active_container.request_grab_lit_bomb(my_id)
				return true
	return false


func _rebind_active_drag_3d_node() -> Node3D:
	if not _drag_3d_active or active_container == null or not is_instance_valid(active_container):
		return null
	if _drag_3d_node != null and is_instance_valid(_drag_3d_node):
		return _drag_3d_node
	if active_container.has_method("get_content_area_node"):
		var lookup_key: Variant = _drag_3d_clutter_idx if _drag_3d_role == "clutter" else _drag_3d_item_id
		_drag_3d_node = active_container.get_content_area_node(_drag_3d_role, lookup_key)
	return _drag_3d_node


func _update_container_3d_drag(screen_pos: Vector2) -> void:
	if active_container == null or not is_instance_valid(active_container):
		_clear_drag_3d_state()
		return
	var drag_node: Node3D = _rebind_active_drag_3d_node()
	if drag_node == null or not is_instance_valid(drag_node):
		_clear_drag_3d_state()
		return
	if not _drag_3d_moved and screen_pos.distance_to(_drag_3d_start_screen_pos) >= 12.0:
		_drag_3d_moved = true

	if _drag_3d_moved and _drag_3d_role == "loot_item" and _container_ui != null:
		var wants_left: bool = _drag_3d_item_id == "BRIEFCASE" or PICKUP_SCRIPT.is_objective_item(_drag_3d_item_id)
		var wants_right: bool = PICKUP_SCRIPT.is_gadget_item(_drag_3d_item_id)
		var over_left: bool = _container_ui.has_method("is_point_over_left_panel") and bool(_container_ui.is_point_over_left_panel(screen_pos))
		var over_right: bool = _container_ui.has_method("is_point_over_right_panel") and bool(_container_ui.is_point_over_right_panel(screen_pos))
		if (wants_left and over_left) or (wants_right and over_right):
			if _container_ui.has_method("update_external_3d_item_drag"):
				_container_ui.update_external_3d_item_drag(_drag_3d_item_id, screen_pos)
			return
		if _container_ui.has_method("clear_external_3d_item_drag"):
			_container_ui.clear_external_3d_item_drag()

	var tray: Node3D = active_container.get_tray_node() if active_container.has_method("get_tray_node") else null
	if tray == null or camera == null:
		return
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var world_hit: Variant = Plane(Vector3.UP, _drag_3d_plane_y).intersects_ray(ray_origin, ray_dir)
	if world_hit is Vector3:
		var local_pt: Vector3 = tray.to_local(world_hit as Vector3)
		var raw_x: float = local_pt.x + _drag_3d_offset_xz.x
		var raw_z: float = local_pt.z + _drag_3d_offset_xz.y
		if active_container.has_method("container_local_xz_to_norm") and active_container.has_method("norm_to_container_local_xz"):
			var norm_pos: Vector2 = active_container.container_local_xz_to_norm(raw_x, raw_z)
			if active_container.has_method("clamp_item_norm_to_tray_walls"):
				norm_pos = active_container.clamp_item_norm_to_tray_walls(norm_pos, _drag_3d_role, _drag_3d_clutter_idx, _drag_3d_item_id)
			var clamped_xz: Vector2 = active_container.norm_to_container_local_xz(norm_pos)
			drag_node.position.x = clamped_xz.x
			drag_node.position.z = clamped_xz.y
			drag_node.position.y = float(drag_node.get_meta("base_y", drag_node.position.y))
			SHOVE_PHYSICS.record_sample(_drag_3d_samples, norm_pos, Time.get_ticks_usec() * 1e-6)
		else:
			drag_node.position.x = clampf(raw_x, -0.33, 0.33)
			drag_node.position.z = clampf(raw_z, -0.17, 0.17)
			drag_node.position.y = float(drag_node.get_meta("base_y", drag_node.position.y))


func _finish_container_3d_drag(release_pos: Vector2) -> void:
	var role: String = _drag_3d_role
	var c_idx: int = _drag_3d_clutter_idx
	var item_id: String = _drag_3d_item_id
	var node: Node3D = _rebind_active_drag_3d_node()
	var moved: bool = _drag_3d_moved
	var samples: Array = _drag_3d_samples.duplicate()
	var container_ref: Node = active_container
	_clear_drag_3d_state()
	if node == null or not is_instance_valid(node) or container_ref == null or not is_instance_valid(container_ref):
		return
	node.position.y = float(node.get_meta("base_y", node.position.y))
	var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
	var is_briefcase: bool = bool(container_ref.get("is_briefcase_container"))

	if role == "loot_item":
		if _container_ui != null:
			var over_left: bool = _container_ui.has_method("is_point_over_left_panel") and bool(_container_ui.is_point_over_left_panel(release_pos))
			if over_left and (item_id == "BRIEFCASE" or PICKUP_SCRIPT.is_objective_item(item_id)):
				var felt_norm: Vector2 = _container_ui.get_briefcase_canvas_norm_pos_if_over(release_pos) if _container_ui.has_method("get_briefcase_canvas_norm_pos_if_over") else Vector2(-1.0, -1.0)
				if container_ref.has_method("request_loot_item"):
					container_ref.request_loot_item(my_id, item_id, -1, felt_norm)
				return
			var over_right: bool = _container_ui.has_method("is_point_over_right_panel") and bool(_container_ui.is_point_over_right_panel(release_pos))
			if over_right and PICKUP_SCRIPT.is_gadget_item(item_id):
				var coat_slot: int = int(_container_ui.find_coat_slot_at_screen_pos(release_pos)) if _container_ui.has_method("find_coat_slot_at_screen_pos") else -1
				if container_ref.has_method("request_loot_item"):
					container_ref.request_loot_item(my_id, item_id, coat_slot)
				return
		if not moved and not is_briefcase:
			var held_left: String = left_hand_item_id.to_upper()
			var quick_loot_ok: bool = (
				PICKUP_SCRIPT.is_gadget_item(item_id)
				or item_id == "BRIEFCASE"
				or (PICKUP_SCRIPT.is_objective_item(item_id) and (held_left == "NONE" or held_left == "BRIEFCASE"))
			)
			if quick_loot_ok and container_ref.has_method("request_loot_item"):
				container_ref.request_loot_item(my_id, item_id, -1)
				return

	var norm_pos: Vector2 = (
		container_ref.container_local_xz_to_norm(node.position.x, node.position.z)
		if container_ref.has_method("container_local_xz_to_norm")
		else Vector2(0.5, 0.5)
	)
	if container_ref.has_method("clamp_item_norm_to_tray_walls"):
		norm_pos = container_ref.clamp_item_norm_to_tray_walls(norm_pos, role, c_idx, item_id)
	var vel: Vector2 = SHOVE_PHYSICS.compute_release_velocity(samples, norm_pos, Time.get_ticks_usec() * 1e-6)
	launch_3d_container_slide(container_ref, role, c_idx, item_id, norm_pos, vel)


func _get_3d_slide_norm_rect(container: Node, role: String, clutter_idx: int, item_id: String) -> Dictionary:
	if container != null and container.has_method("clamp_item_norm_to_tray_walls"):
		var min_v: Vector2 = container.clamp_item_norm_to_tray_walls(Vector2(0.0, 0.0), role, clutter_idx, item_id)
		var max_v: Vector2 = container.clamp_item_norm_to_tray_walls(Vector2(1.0, 1.0), role, clutter_idx, item_id)
		return {"min": min_v, "max": Vector2(maxf(max_v.x, min_v.x), maxf(max_v.y, min_v.y))}
	var bounds: Vector2 = container.get_norm_bounds() if (container != null and container.has_method("get_norm_bounds")) else Vector2(0.02, 0.98)
	return {"min": Vector2(bounds.x, bounds.x), "max": Vector2(bounds.y, bounds.y)}


func launch_3d_container_slide(
	container: Node,
	role: String,
	clutter_idx: int,
	item_id: String,
	start_norm: Vector2,
	vel: Vector2
) -> void:
	if container == null or not is_instance_valid(container):
		return
	var rect: Dictionary = _get_3d_slide_norm_rect(container, role, clutter_idx, item_id)
	var min_v: Vector2 = rect["min"] as Vector2
	var max_v: Vector2 = rect["max"] as Vector2
	var clamped: Vector2 = Vector2(clampf(start_norm.x, min_v.x, max_v.x), clampf(start_norm.y, min_v.y, max_v.y))
	var key: String = _make_3d_slide_key(role, clutter_idx, item_id)
	var cfg: Dictionary = SHOVE_PHYSICS.get_config_dict()
	var stop_speed: float = float(cfg.get("stop_speed", 0.04))
	_apply_3d_slide_node_xz(container, role, clutter_idx, item_id, clamped)
	if vel.length() > stop_speed:
		_active_3d_slides[key] = {
			"container": container,
			"role": role,
			"clutter_idx": clutter_idx,
			"item_id": item_id.to_upper(),
			"pos": clamped,
			"vel": vel,
			"bounds_min_v": min_v,
			"bounds_max_v": max_v,
			"bounce_sfx_cd": 0.0
		}
		if vel.length() >= 0.6 and AudioBridge != null:
			var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
			AudioBridge.request_world_cue("paper_rustle", container.global_position if container is Node3D else _safe_global_pos(), 3.0, my_id)
	else:
		_active_3d_slides.erase(key)
		_commit_3d_slide_position(container, role, clutter_idx, item_id, clamped)


func _step_active_3d_slides(delta: float) -> void:
	if _active_3d_slides.is_empty():
		return
	var cfg: Dictionary = SHOVE_PHYSICS.get_config_dict()
	var to_commit: Array[Dictionary] = []
	for key in _active_3d_slides.keys():
		var entry: Dictionary = _active_3d_slides[key] as Dictionary
		var c: Node = entry.get("container") as Node
		if c == null or not is_instance_valid(c):
			to_commit.append({"key": key, "commit": false})
			continue
		var min_v: Vector2 = entry.get("bounds_min_v", Vector2(0.02, 0.02)) as Vector2
		var max_v: Vector2 = entry.get("bounds_max_v", Vector2(0.98, 0.98)) as Vector2
		var span: Vector2 = max_v - min_v
		var pos_v: Vector2 = entry["pos"] as Vector2
		var vel_v: Vector2 = entry["vel"] as Vector2
		var sub_pos := Vector2(
			clampf((pos_v.x - min_v.x) / span.x, 0.0, 1.0) if span.x > 0.001 else 0.5,
			clampf((pos_v.y - min_v.y) / span.y, 0.0, 1.0) if span.y > 0.001 else 0.5
		)
		var sub_vel := Vector2(
			vel_v.x / span.x if span.x > 0.001 else 0.0,
			vel_v.y / span.y if span.y > 0.001 else 0.0
		)
		var res: Dictionary = SHOVE_PHYSICS.step_slide(sub_pos, sub_vel, delta, 0.0, 1.0, cfg)
		var res_pos: Vector2 = res["pos"] as Vector2
		var res_vel: Vector2 = res["vel"] as Vector2
		var next_pos := Vector2(
			min_v.x + res_pos.x * span.x if span.x > 0.001 else (min_v.x + max_v.x) * 0.5,
			min_v.y + res_pos.y * span.y if span.y > 0.001 else (min_v.y + max_v.y) * 0.5
		)
		var next_vel := Vector2(
			res_vel.x * span.x if span.x > 0.001 else 0.0,
			res_vel.y * span.y if span.y > 0.001 else 0.0
		)
		entry["pos"] = next_pos
		entry["vel"] = next_vel
		entry["bounce_sfx_cd"] = maxf(float(entry.get("bounce_sfx_cd", 0.0)) - delta, 0.0)
		var role_str: String = str(entry["role"])
		var entry_c_idx: int = int(entry["clutter_idx"])
		_apply_3d_slide_node_xz(c, role_str, entry_c_idx, str(entry["item_id"]), next_pos)
		var impact_world: float = float(res["impact_speed"]) * maxf(span.x, span.y)
		if bool(res["bounced"]) and impact_world >= 0.35 and float(entry["bounce_sfx_cd"]) <= 0.0:
			entry["bounce_sfx_cd"] = 0.09
			if AudioBridge != null:
				var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
				AudioBridge.request_world_cue("paper_rustle", c.global_position if c is Node3D else _safe_global_pos(), 3.0, my_id)
		if bool(res["settled"]):
			to_commit.append({
				"key": key,
				"commit": true,
				"container": c,
				"role": role_str,
				"clutter_idx": entry_c_idx,
				"item_id": str(entry["item_id"]),
				"pos": next_pos
			})
	var live_drag_pos := Vector3.ZERO
	var had_live_drag: bool = false
	if _drag_3d_active:
		var active_drag_node: Node3D = _rebind_active_drag_3d_node()
		if active_drag_node != null and is_instance_valid(active_drag_node):
			live_drag_pos = active_drag_node.position
			had_live_drag = true
	for item in to_commit:
		_active_3d_slides.erase(item["key"])
		if bool(item.get("commit", false)):
			_commit_3d_slide_position(
				item["container"] as Node,
				str(item["role"]),
				int(item["clutter_idx"]),
				str(item["item_id"]),
				item["pos"] as Vector2
			)
	# Preserve live dragged node position if a slide commit ran mid-drag
	if had_live_drag and _drag_3d_active:
		var drag_node_after: Node3D = _rebind_active_drag_3d_node()
		if drag_node_after != null and is_instance_valid(drag_node_after):
			drag_node_after.position = live_drag_pos
	# Re-apply any still-active slides after server state sync/rebuild so concurrent drags stay smooth
	for key in _active_3d_slides.keys():
		var rem: Dictionary = _active_3d_slides[key] as Dictionary
		var rem_c: Node = rem.get("container") as Node
		if rem_c != null and is_instance_valid(rem_c):
			_apply_3d_slide_node_xz(rem_c, str(rem["role"]), int(rem["clutter_idx"]), str(rem["item_id"]), rem["pos"] as Vector2)


func flush_active_3d_slides(commit: bool = true) -> void:
	_flush_active_3d_slides(commit)


func _flush_active_3d_slides(commit: bool = true) -> void:
	if _active_3d_slides.is_empty():
		return
	var cfg: Dictionary = SHOVE_PHYSICS.get_config_dict()
	var keys: Array = _active_3d_slides.keys()
	for key in keys:
		var entry: Dictionary = _active_3d_slides[key] as Dictionary
		var c: Node = entry.get("container") as Node
		var min_v: Vector2 = entry.get("bounds_min_v", Vector2(0.02, 0.02)) as Vector2
		var max_v: Vector2 = entry.get("bounds_max_v", Vector2(0.98, 0.98)) as Vector2
		var span: Vector2 = max_v - min_v
		var pos_v: Vector2 = entry["pos"] as Vector2
		var vel_v: Vector2 = entry["vel"] as Vector2
		var sub_pos := Vector2(
			clampf((pos_v.x - min_v.x) / span.x, 0.0, 1.0) if span.x > 0.001 else 0.5,
			clampf((pos_v.y - min_v.y) / span.y, 0.0, 1.0) if span.y > 0.001 else 0.5
		)
		var sub_vel := Vector2(
			vel_v.x / span.x if span.x > 0.001 else 0.0,
			vel_v.y / span.y if span.y > 0.001 else 0.0
		)
		var res_sub: Vector2 = SHOVE_PHYSICS.simulate_to_rest(sub_pos, sub_vel, 0.0, 1.0, cfg)
		var rest_pos := Vector2(
			min_v.x + res_sub.x * span.x if span.x > 0.001 else (min_v.x + max_v.x) * 0.5,
			min_v.y + res_sub.y * span.y if span.y > 0.001 else (min_v.y + max_v.y) * 0.5
		)
		_active_3d_slides.erase(key)
		if c != null and is_instance_valid(c):
			var role_str: String = str(entry["role"])
			var entry_c_idx: int = int(entry["clutter_idx"])
			_apply_3d_slide_node_xz(c, role_str, entry_c_idx, str(entry["item_id"]), rest_pos)
			if commit:
				_commit_3d_slide_position(c, role_str, entry_c_idx, str(entry["item_id"]), rest_pos)


func _apply_3d_slide_node_xz(container: Node, role: String, clutter_idx: int, item_id: String, norm_pos: Vector2) -> void:
	if container == null or not is_instance_valid(container):
		return
	var lookup_key: Variant = clutter_idx if role == "clutter" else item_id
	var area_node: Node3D = container.get_content_area_node(role, lookup_key) if container.has_method("get_content_area_node") else null
	if area_node == null or not is_instance_valid(area_node):
		return
	var local_xz: Vector2 = container.norm_to_container_local_xz(norm_pos) if container.has_method("norm_to_container_local_xz") else Vector2.ZERO
	area_node.position.x = local_xz.x
	area_node.position.z = local_xz.y
	area_node.position.y = float(area_node.get_meta("base_y", area_node.position.y))


func _commit_3d_slide_position(container: Node, role: String, clutter_idx: int, item_id: String, norm_pos: Vector2) -> void:
	if container == null or not is_instance_valid(container):
		return
	var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
	if role == "clutter" and container.has_method("request_move_clutter"):
		container.request_move_clutter(my_id, clutter_idx, norm_pos)
	elif role == "loot_item" and container.has_method("request_move_stored_item"):
		container.request_move_stored_item(my_id, item_id, norm_pos)
	elif role == "planted_bomb" and container.has_method("request_move_planted_bomb"):
		container.request_move_planted_bomb(my_id, norm_pos)


func project_screen_pos_to_container_norm(screen_pos: Vector2) -> Vector2:
	if camera == null or active_container == null or not is_instance_valid(active_container):
		return Vector2(-1.0, -1.0)
	if not active_container.has_method("get_tray_node"):
		return Vector2(-1.0, -1.0)
	var tray: Node3D = active_container.get_tray_node() as Node3D
	if tray == null:
		return Vector2(-1.0, -1.0)
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var is_briefcase: bool = bool(active_container.get("is_briefcase_container"))
	var plane_y: float = tray.global_position.y + (BRIEFCASE_BUILDER.ITEM_LAYER_BASE_Y if is_briefcase else -0.030)
	var world_hit: Variant = Plane(Vector3.UP, plane_y).intersects_ray(ray_origin, ray_dir)
	if not (world_hit is Vector3):
		return Vector2(-1.0, -1.0)
	var local_pt: Vector3 = tray.to_local(world_hit as Vector3)
	if active_container.has_method("container_local_xz_to_norm"):
		return active_container.container_local_xz_to_norm(local_pt.x, local_pt.z)
	return BRIEFCASE_BUILDER.briefcase_local_xz_to_norm(local_pt.x, local_pt.z)


func project_screen_pos_to_briefcase_norm(screen_pos: Vector2) -> Vector2:
	return project_screen_pos_to_container_norm(screen_pos)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_multiplayer_authority():
		return

	var lock_stance: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	var ko_stance: int = GameConfig.Stance.KO if GameConfig != null else 4
	if stance_state == lock_stance or stance_state == ko_stance:
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_MINUS:
			_nudge_sensitivity(-0.10)
			return
		elif event.keycode == KEY_BRACKETRIGHT or event.keycode == KEY_EQUAL:
			_nudge_sensitivity(0.10)
			return

	if event.is_action_pressed("jacket_slot_1") and not event.is_echo():
		_trigger_hand_action("SELECT_SLOT", 0)
		return
	if event.is_action_pressed("jacket_slot_2") and not event.is_echo():
		_trigger_hand_action("SELECT_SLOT", 1)
		return
	if event.is_action_pressed("jacket_slot_3") and not event.is_echo():
		_trigger_hand_action("SELECT_SLOT", 2)
		return
	if event.is_action_pressed("jacket_slot_prev"):
		_trigger_hand_action("CYCLE_SLOT", -1)
		return
	if event.is_action_pressed("jacket_slot_next"):
		_trigger_hand_action("CYCLE_SLOT", 1)
		return
	if event.is_action_pressed("drop_left_hand") and not event.is_echo():
		_trigger_hand_action("DROP_LEFT")
		return
	if event.is_action_pressed("drop_right_hand") and not event.is_echo():
		_trigger_hand_action("DROP_RIGHT")
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F7:
		if GameConfig != null:
			GameConfig.debug_club_hit_gizmo = not GameConfig.debug_club_hit_gizmo
			print("[ClubHitGizmo] ", "ON" if GameConfig.debug_club_hit_gizmo else "OFF")
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F9:
		_toggle_viewmodel_tuner()
		return

	if event.is_action_pressed("toggle_club") and not event.is_echo():
		reset_anti_camp()
		_trigger_hand_action("TOGGLE_CLUB")
		return

	if event.is_action_pressed("cycle_bluff_cue") and not event.is_echo():
		ensure_overlay_uis()
		if _watch_bluff_ui != null:
			_watch_bluff_ui.cycle_cue()
		return

	if event is InputEventKey and event.keycode == KEY_B and event.pressed and not event.is_echo():
		ensure_overlay_uis()
		if _watch_bluff_ui != null:
			emit_watch_bluff(_watch_bluff_ui.get_selected_cue_id(), _safe_global_pos())
		return

	if event is InputEventKey and event.keycode == KEY_TAB and not event.is_echo():
		ensure_overlay_uis()
		if _watch_bluff_ui != null:
			_watch_bluff_ui.set_map_open(event.pressed)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if event.pressed else Input.MOUSE_MODE_CAPTURED
		return

	if event.is_action_pressed("spy_gadget_ptt") and not event.is_echo():
		ensure_overlay_uis()
		if _watch_bluff_ui != null:
			_watch_bluff_ui.set_radio_active(true)
	elif event.is_action_released("spy_gadget_ptt"):
		if _watch_bluff_ui != null:
			_watch_bluff_ui.set_radio_active(false)

	if event.is_action_pressed("primary_action") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_try_begin_primary_action()
	elif event.is_action_released("primary_action"):
		if not _lmb_trap_bucket_other_side:
			_lmb_trap_hold_active = false
		if _tripwire_ctrl != null and is_instance_valid(_tripwire_ctrl):
			_tripwire_ctrl.on_lmb_released()
		if is_charging_club:
			evaluate_club_release()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.pressed and right_hand_item_id == "BUCKET" and club_overcharge_stumble_remaining <= 0.0:
			_try_begin_bucket_rig_hold(true)
		elif not event.pressed and _lmb_trap_bucket_other_side:
			_lmb_trap_hold_active = false
			_lmb_trap_bucket_other_side = false

	var is_rmb_cancel: bool = (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	)
	var is_esc_cancel: bool = (
		event.is_action_pressed("ui_cancel")
		or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ESCAPE)
	)
	if handle_tripwire_cancel_input(is_rmb_cancel, is_esc_cancel):
		get_viewport().set_input_as_handled()
		return

	if is_esc_cancel:
		var scene: Node = get_tree().current_scene if get_tree() != null else null
		if scene != null and scene.has_method("toggle_esc_menu"):
			return
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			var scene: Node = get_tree().current_scene if get_tree() != null else null
			var esc_menu_node: Variant = scene.get("esc_menu") if scene != null else null
			var esc_open: bool = esc_menu_node is CanvasItem and (esc_menu_node as CanvasItem).visible
			var map_open: bool = _watch_bluff_ui != null and _watch_bluff_ui.is_map_open
			var tuner_open: bool = _vm_tuner_ui != null and _vm_tuner_ui.visible
			if not esc_open and not map_open and not tuner_open:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _is_aiming_dart_gun():
		var eff_sens: float = GameConfig.get_effective_mouse_sensitivity() if GameConfig != null else mouse_sensitivity
		rotate_y(-event.relative.x * eff_sens)
		head_pitch = clampf(head_pitch - event.relative.y * eff_sens, deg_to_rad(-89.0), deg_to_rad(89.0))
		_vm_sway_vel += Vector2(event.relative.x, event.relative.y) * 0.35
		if head != null:
			head.rotation.x = head_pitch
		if _ragdoll_ctrl != null and not _ragdoll_ctrl.is_ragdoll_active:
			_ragdoll_ctrl.refresh_head_pitch_pose(head_pitch)
			_sync_camera_to_ragdoll_head()
			_sync_visual_rig_sockets_to_skeleton()
			_update_first_person_viewmodel(0.0)


func _trigger_hand_action(action_type: String, slot_arg: int = 0) -> void:
	if action_type in ["SELECT_SLOT", "CYCLE_SLOT", "DROP_RIGHT", "TOGGLE_CLUB", "START_CLUB_CHARGE", "KO_SCATTER"]:
		cancel_tripwire_placement()
	if _is_peer_connected():
		server_request_hand_action.rpc_id(1, action_type, slot_arg)
	else:
		server_request_hand_action(action_type, slot_arg)


func _nudge_sensitivity(delta_mult: float) -> void:
	if GameConfig == null:
		return
	var new_mult: float = clampf(snappedf(GameConfig.mouse_sensitivity_multiplier + delta_mult, 0.05), 0.10, 4.00)
	GameConfig.set_mouse_settings(GameConfig.mouse_dpi, new_mult, true)
	mouse_sensitivity = GameConfig.get_effective_mouse_sensitivity()
	if prompt_label != null:
		prompt_label.text = "Mouse Sensitivity: %.2fx (%d DPI)" % [GameConfig.mouse_sensitivity_multiplier, GameConfig.mouse_dpi]
		prompt_label.visible = true
		_sens_toast_timer = 1.5


func request_ladder_mount(ladder: INTERACTIVE_LADDER) -> void:
	if is_multiplayer_authority() and not is_instance_valid(_active_ladder):
		_requested_ladder = ladder


func _try_auto_mount_ladder(direction: Vector3) -> bool:
	if direction.is_zero_approx():
		_last_dismounted_ladder = null
		return false
	if is_instance_valid(_last_dismounted_ladder):
		var offset := _last_dismounted_ladder.to_local(global_position)
		if Vector2(offset.x, offset.z).length() > INTERACTIVE_LADDER.LANDING_OFFSET + 0.35:
			_last_dismounted_ladder = null

	for node in get_tree().get_nodes_in_group("interactive_ladders"):
		var ladder := node as INTERACTIVE_LADDER
		if ladder == null or ladder == _last_dismounted_ladder or not ladder.can_mount_from(global_position):
			continue
		var local := ladder.to_local(global_position)
		var side := ladder.approach_side(global_position)
		if absf(local.x) > INTERACTIVE_LADDER.SHAFT_WIDTH * 0.5 + 0.20 or local.z * side > LADDER_AUTO_MOUNT_DEPTH:
			continue
		var inward := -ladder.global_transform.basis.z.normalized() * side
		if inward.dot(direction) < 0.55:
			continue
		_try_mount_ladder(ladder)
		if is_instance_valid(_active_ladder):
			return true
	return false


func _try_mount_ladder(ladder: INTERACTIVE_LADDER) -> void:
	if not ladder.can_mount_from(global_position):
		return
	var lock_stance: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	if stance_state == lock_stance or (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _can_walk_with_map()):
		return
	var lower := ladder.lower_landing_y
	var upper := ladder.upper_landing_y
	var landing := upper if absf(global_position.y - upper) < absf(global_position.y - lower) else lower
	var side := ladder.approach_side(global_position)
	var mount := ladder.climb_point(landing + LADDER_LANDING_CLEARANCE, side)
	if absf(global_position.y - landing) > 0.55 or global_position.distance_squared_to(mount) > 2.2 * 2.2:
		return
	_set_ladder_collision_exceptions(ladder, true)
	if test_move(global_transform, mount - global_position):
		_set_ladder_collision_exceptions(ladder, false)
		return
	_active_ladder = ladder
	is_climbing_ladder = true
	_climb_vertical_speed = 0.0
	_ladder_side = side
	_ladder_level_forward = 1 if landing == lower else -1
	global_position = mount
	velocity = Vector3.ZERO
	_footstep_timer = 0.0
	reset_anti_camp()


func _set_ladder_collision_exceptions(ladder: INTERACTIVE_LADDER, ignore: bool) -> void:
	for body in [ladder.climb_body, ladder.shaft_guard]:
		if not is_instance_valid(body):
			continue
		if ignore:
			add_collision_exception_with(body)
		else:
			remove_collision_exception_with(body)


func _release_ladder() -> void:
	if is_instance_valid(_active_ladder):
		_set_ladder_collision_exceptions(_active_ladder, false)
	_active_ladder = null
	is_climbing_ladder = false
	_climb_vertical_speed = 0.0


func _can_walk_with_map() -> bool:
	if _watch_bluff_ui == null or not _watch_bluff_ui.is_map_open:
		return false
	var scene := get_tree().current_scene
	var esc_menu: Variant = scene.get("esc_menu") if scene != null else null
	return not (esc_menu is CanvasItem and esc_menu.visible)


func _move_on_ladder(delta: float) -> void:
	_climb_vertical_speed = 0.0
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _can_walk_with_map():
		return
	var forward := Input.is_action_pressed("move_forward") or Input.is_physical_key_pressed(KEY_W)
	var backward := Input.is_action_pressed("move_back") or Input.is_physical_key_pressed(KEY_S)
	var toward_look := int(forward) - int(backward)
	if toward_look == 0:
		return

	# A level gaze continues toward the other landing from the point of entry.
	var look_direction := _ladder_level_forward
	if absf(head_pitch) >= LADDER_LOOK_DEAD_ZONE:
		look_direction = 1 if head_pitch > 0.0 else -1
	var direction := toward_look * look_direction
	var ladder := _active_ladder
	var landing := ladder.upper_landing_y if direction > 0 else ladder.lower_landing_y
	var end_height := landing + LADDER_LANDING_CLEARANCE
	var prev_y: float = global_position.y
	var next_height := move_toward(global_position.y, end_height, LADDER_CLIMB_SPEED * delta)
	move_and_collide(Vector3.UP * (next_height - global_position.y))
	_climb_vertical_speed = (global_position.y - prev_y) / maxf(delta, 0.001)
	if absf(_climb_vertical_speed) > 0.12:
		_footstep_timer += delta
		if _footstep_timer >= 0.34:
			_footstep_timer = 0.0
			if AudioBridge != null and GameConfig != null:
				AudioBridge.request_world_cue("footstep_walk", global_position, GameConfig.audio_radius_walk, name.to_int())
	if absf(global_position.y - end_height) <= 0.005:
		var exit := ladder.exit_point(end_height, _ladder_side)
		if not test_move(global_transform, exit - global_position):
			global_position = exit
			_last_dismounted_ladder = ladder
			_release_ladder()
			_was_on_floor = false
	if not _is_peer_connected():
		_target_position = position


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	tick_ko_and_immunity(delta)
	step_held_briefcase_live_bomb(delta)

	var ko_val: int = GameConfig.Stance.KO if GameConfig != null else 4
	var crouch_val: int = GameConfig.Stance.CROUCH if GameConfig != null else 2
	if stance_state == ko_val:
		_requested_ladder = null
		_release_ladder()
		if not is_multiplayer_authority() and _ragdoll_ctrl != null:
			_ragdoll_ctrl.step_remote_pelvis_pull(delta)
		elif is_multiplayer_authority():
			_sync_camera_to_ragdoll_head()
		_sync_visual_rig_sockets_to_skeleton()
		return

	if is_multiplayer_authority():
		if is_clock_eliminated or (MatchManager != null and MatchManager.match_state == MatchManager.MatchState.ENDED):
			_requested_ladder = null
			_release_ladder()
		if is_instance_valid(_requested_ladder):
			_try_mount_ladder(_requested_ladder)
			_requested_ladder = null
		if is_instance_valid(_active_ladder):
			_move_on_ladder(delta)
			if _ragdoll_ctrl != null:
				var climb_left: String = _get_effective_tp_left_item_id() if _tp_preview_active else _get_effective_fp_left_item_id()
				var climb_right: String = _get_effective_tp_right_item_id() if _tp_preview_active else _get_effective_fp_right_item_id()
				_ragdoll_ctrl.update_locomotion_pose(delta, 0.0, false, head_pitch, false, climb_left, climb_right, is_climbing_ladder, _climb_vertical_speed)
				_sync_camera_to_ragdoll_head()
				_sync_visual_rig_sockets_to_skeleton()
			return

	if not _is_peer_connected() or not is_multiplayer_authority():
		var prev_pos: Vector3 = position
		if position.distance_squared_to(_target_position) > 16.0:
			position = _target_position
		else:
			position = position.lerp(_target_position, 20.0 * delta)
		rotation.y = lerp_angle(rotation.y, _target_yaw, 20.0 * delta)
		if _ragdoll_ctrl != null:
			var remote_spd: float = Vector2(position.x - prev_pos.x, position.z - prev_pos.z).length() / maxf(delta, 0.001)
			var remote_vert_spd: float = (position.y - prev_pos.y) / maxf(delta, 0.001)
			_ragdoll_ctrl.update_locomotion_pose(delta, remote_spd, stance_state == crouch_val, head_pitch, is_charging_club, left_hand_item_id, right_hand_item_id, is_climbing_ladder, remote_vert_spd)
			_sync_camera_to_ragdoll_head()
			_sync_visual_rig_sockets_to_skeleton()
		elif head != null:
			head.rotation.x = lerp_angle(head.rotation.x, head_pitch, 20.0 * delta)
		return

	var movement_allowed: bool = (
		(MatchManager == null or MatchManager.match_state != MatchManager.MatchState.ENDED)
		and not is_clock_eliminated
	)
	var controls_captured := movement_allowed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var aiming_dart: bool = _is_aiming_dart_gun()
	var wants_crouch: bool = (stance_state == crouch_val) if aiming_dart else (
		controls_captured and (
			(InputMap.has_action("crouch") and Input.is_action_pressed("crouch"))
			or Input.is_key_pressed(KEY_CTRL)
		)
	)
	var wants_sprint: bool = controls_captured and not aiming_dart and (
		(InputMap.has_action("sprint") and Input.is_action_pressed("sprint"))
		or Input.is_key_pressed(KEY_SHIFT)
	)
	update_stance_from_inputs(wants_sprint, wants_crouch)

	var on_floor_now: bool = is_on_floor()
	if not on_floor_now:
		velocity.y -= gravity * delta
	elif not _was_on_floor:
		if AudioBridge != null and GameConfig != null:
			AudioBridge.request_world_cue("jump_land", global_position, GameConfig.audio_radius_jump_land, name.to_int())
	_was_on_floor = on_floor_now

	var can_jump: bool = (
		controls_captured
		and not aiming_dart
		and on_floor_now
		and stance_state != (GameConfig.Stance.CROUCH if GameConfig != null else 2)
		and stance_state != (GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3)
		and stance_state != (GameConfig.Stance.KO if GameConfig != null else 4)
		and not is_charging_club
		and club_overcharge_stumble_remaining <= 0.0
	)
	if can_jump and (Input.is_action_just_pressed("jump") or Input.is_key_pressed(KEY_SPACE)):
		velocity.y = GameConfig.jump_velocity if GameConfig != null else jump_velocity

	var input_dir: Vector2 = Vector2.ZERO
	if movement_allowed and (controls_captured or _can_walk_with_map()) and not aiming_dart:
		if InputMap.has_action("move_forward") and InputMap.has_action("move_left"):
			input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		else:
			if Input.is_key_pressed(KEY_W): input_dir.y -= 1.0
			if Input.is_key_pressed(KEY_S): input_dir.y += 1.0
			if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
			if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
			input_dir = input_dir.normalized()

	var active_speed: float = get_current_move_speed()
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if _try_auto_mount_ladder(direction if active_speed > 0.0 else Vector3.ZERO):
		_move_on_ladder(delta)
		return
	if direction != Vector3.ZERO and active_speed > 0.0:
		velocity.x = direction.x * active_speed
		velocity.z = direction.z * active_speed
		_tick_footsteps(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, maxf(active_speed, 4.5))
		velocity.z = move_toward(velocity.z, 0.0, maxf(active_speed, 4.5))
		_footstep_timer = 0.0

	move_and_slide()

	if _ragdoll_ctrl != null:
		var local_horiz_spd: float = Vector2(velocity.x, velocity.z).length()
		var pose_crouch: bool = (stance_state == crouch_val)
		var pose_charge: bool = is_charging_club
		var pose_climb: bool = is_climbing_ladder
		var pose_climb_spd: float = _climb_vertical_speed
		if _tp_preview_active:
			match _tp_sim_motion:
				"WALK":
					local_horiz_spd = GameConfig.walk_speed if GameConfig != null else 4.5
					pose_crouch = false
					pose_charge = false
					pose_climb = false
				"SPRINT":
					local_horiz_spd = GameConfig.sprint_speed if GameConfig != null else 6.8
					pose_crouch = false
					pose_charge = false
					pose_climb = false
				"CROUCH":
					local_horiz_spd = GameConfig.crouch_speed if GameConfig != null else 2.5
					pose_crouch = true
					pose_charge = false
					pose_climb = false
				"CLIMB":
					local_horiz_spd = 0.0
					pose_crouch = false
					pose_charge = false
					pose_climb = true
					pose_climb_spd = LADDER_CLIMB_SPEED
				"CLUB_CHARGE":
					local_horiz_spd = 0.0
					pose_crouch = false
					pose_charge = true
					pose_climb = false
		var pose_left: String = _get_effective_tp_left_item_id() if _tp_preview_active else _get_effective_fp_left_item_id()
		var pose_right: String = _get_effective_tp_right_item_id() if _tp_preview_active else _get_effective_fp_right_item_id()
		_ragdoll_ctrl.update_locomotion_pose(delta, local_horiz_spd, pose_crouch, head_pitch, pose_charge, pose_left, pose_right, pose_climb, pose_climb_spd)
		_sync_camera_to_ragdoll_head()
		_sync_visual_rig_sockets_to_skeleton()

	if stance_state == (GameConfig.Stance.SPRINT if GameConfig != null else 1) and door_bash_detector != null:
		for body in door_bash_detector.get_overlapping_bodies():
			_try_sprint_bash_target(body)


func _tick_footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var radius: float = get_current_footstep_radius()
	if radius <= 0.0:
		return

	var interval: float = 0.32 if stance_state == (GameConfig.Stance.SPRINT if GameConfig != null else 1) else 0.48
	_footstep_timer += delta
	if _footstep_timer >= interval:
		_footstep_timer = 0.0
		var cue: String = "footstep_sprint" if stance_state == (GameConfig.Stance.SPRINT if GameConfig != null else 1) else "footstep_walk"
		if AudioBridge != null:
			AudioBridge.request_world_cue(cue, global_position, radius, name.to_int())
