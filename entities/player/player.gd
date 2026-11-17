extends CharacterBody3D

## SpyCharacter Controller — Dual Movement, Stances & 3-Slot Inner Trenchcoat Jacket Inventory (Doc 2 v1.2).
## Client-authoritative FPS locomotion + Server-authoritative Left-Hand & 3-Slot Jacket Inventory.

enum SpyRole {
	SPY_WHITE = 1,
	SPY_BLACK = 2
}

const COLOR_SPY_WHITE: Color = Color(0.92, 0.92, 0.92)
const COLOR_SPY_BLACK: Color = Color(0.12, 0.12, 0.12)
const PICKUP_SCENE: PackedScene = preload("res://entities/props/world_item_pickup.tscn")
const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const TOP_DOWN_UI_SCRIPT = preload("res://ui/top_down_container_ui.gd")
const TAP_RELEASE_THRESHOLD: float = 0.20

# ==========================================
# Replicated Properties (MultiplayerSynchronizer — Client Locomotion/Stance Authority)
# ==========================================
@export var spy_role: int = 1:
	set(value):
		spy_role = value
		_update_mesh_color()

@export var head_pitch: float = 0.0

@export var stance_state: int = 0: # GameConfig.Stance
	set(value):
		stance_state = value
		_apply_stance_collision_and_visuals()
		_update_hud_status()

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
var _camera_tween: Tween = null
var _bonus_toast_timer: float = 0.0
var ko_remaining_seconds: float = 0.0
var wakeup_immunity_remaining: float = 0.0
var _dragging_3d_clutter_idx: int = -1
var _dragging_3d_clutter_node: Node3D = null
var _dragging_3d_plane_y: float = 0.0
var _dragging_3d_offset_xz: Vector2 = Vector2.ZERO
var _drawer_focus_just_entered: bool = false
var _drawer_e_held: bool = false
var _drawer_e_hold_elapsed: float = 0.0

# Footstep & airborne tracking
var _footstep_timer: float = 0.0
var _was_on_floor: bool = true
var _sens_toast_timer: float = 0.0
var _drop_counter: int = 0


func _enter_tree() -> void:
	add_to_group("spy_players")
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
	_setup_wearable_visual()
	_refresh_hand_and_back_sockets()
	_apply_stance_collision_and_visuals()
	_update_hud_status()

	if GameConfig != null:
		speed = GameConfig.walk_speed
		jump_velocity = GameConfig.jump_velocity
		mouse_sensitivity = GameConfig.get_effective_mouse_sensitivity()

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
		if hud != null and _container_ui == null:
			_container_ui = TOP_DOWN_UI_SCRIPT.new()
			_container_ui.name = "TopDownContainerUI"
			hud.add_child(_container_ui)
		if MatchManager != null:
			if not MatchManager.clock_updated.is_connected(_on_match_clock_updated):
				MatchManager.clock_updated.connect(_on_match_clock_updated)
			_on_match_clock_updated(name.to_int(), MatchManager.get_private_clock(name.to_int()), 0.0)
	else:
		camera.current = false
		set_process_input(false)
		set_process_unhandled_input(false)
		set_process(false)
		hud.visible = false


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
	elif wants_sprint and not is_charging_club:
		stance_state = GameConfig.Stance.SPRINT if GameConfig != null else 1
	else:
		stance_state = GameConfig.Stance.WALK if GameConfig != null else 0
	return stance_state


func get_current_move_speed() -> float:
	if GameConfig != null:
		return GameConfig.compute_final_move_speed(
			stance_state,
			left_hand_item_id == "BRIEFCASE",
			is_charging_club
		)
	return speed


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


func pickup_item(new_item_id: String, extra_briefcase_items: Array = []) -> Dictionary:
	var res: Dictionary = _inv().pickup_item(new_item_id, extra_briefcase_items)
	if bool(res["picked"]):
		_refresh_hand_and_back_sockets()
		_update_hud_status()
	return res


func select_jacket_slot(slot_index: int) -> bool:
	var ok: bool = _inv().select_jacket_slot(slot_index)
	if ok:
		_refresh_hand_and_back_sockets()
		_update_hud_status()
	return ok


func cycle_jacket_slot(step: int) -> bool:
	var ok: bool = _inv().cycle_jacket_slot(step)
	if ok:
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
		_refresh_hand_and_back_sockets()
		_update_hud_status()
	return res


func toggle_personal_club() -> Dictionary:
	var res: Dictionary = _inv().toggle_personal_club()
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	return res


func start_club_charge() -> Dictionary:
	var res: Dictionary = _inv().start_club_charge()
	if _inv().is_charging_club and stance_state == (GameConfig.Stance.SPRINT if GameConfig != null else 1):
		stance_state = GameConfig.Stance.WALK if GameConfig != null else 0
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	return res


func stop_club_charge() -> void:
	if _inv().is_charging_club:
		_inv().stop_club_charge()
		_refresh_hand_and_back_sockets()
		_update_hud_status()


func force_drop_all_hands() -> Array[Dictionary]:
	var drops: Array[Dictionary] = _inv().force_drop_all_hands()
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	return drops


func set_briefcase_bomb_state(armed: bool, owner_id: int) -> void:
	_inv().briefcase_armed_bomb = armed
	_inv().briefcase_bomb_owner_id = owner_id


func enter_container_view(container: Node) -> void:
	var already_same_container: bool = (active_container == container)
	active_container = container
	stance_state = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	_dragging_3d_clutter_idx = -1
	_dragging_3d_clutter_node = null
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
		if hud != null and _container_ui == null:
			_container_ui = TOP_DOWN_UI_SCRIPT.new()
			_container_ui.name = "TopDownContainerUI"
			hud.add_child(_container_ui)
		if _container_ui != null:
			var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
			_container_ui.open_for_container(self, container, my_id)


func exit_container_view() -> void:
	active_container = null
	_dragging_3d_clutter_idx = -1
	_dragging_3d_clutter_node = null
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


func apply_trap_ko(_reason: String, _attacker_peer_id: int = 0) -> Array[Dictionary]:
	var ko_stance: int = GameConfig.Stance.KO if GameConfig != null else 4
	if wakeup_immunity_remaining > 0.0 or stance_state == ko_stance:
		return [] as Array[Dictionary]

	if active_container != null and is_instance_valid(active_container) and active_container.has_method("close_container"):
		active_container.close_container(name.to_int(), self)
	elif stance_state == (GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3):
		exit_container_view()

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
				int(entry.get("dropped_briefcase_bomb_owner", 0))
			)

	var ko_dur: float = GameConfig.ko_ragdoll_duration if GameConfig != null else 15.0
	if _is_peer_connected():
		_rpc_apply_ko_state.rpc(ko_dur, 0.0, true)
	else:
		_rpc_apply_ko_state(ko_dur, 0.0, true)
	_sync_inventory_state_to_peers()
	return drops


func _is_authorized_state_rpc() -> bool:
	if not is_inside_tree() or not _is_peer_connected():
		return true
	var sender_id: int = multiplayer.get_remote_sender_id()
	return sender_id == 0 or sender_id == 1 or sender_id == name.to_int()


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_ko_state(ko_sec: float, imm_sec: float, enter_ko: bool) -> void:
	if not _is_authorized_state_rpc():
		return
	if enter_ko:
		ko_remaining_seconds = ko_sec
		wakeup_immunity_remaining = 0.0
		stance_state = GameConfig.Stance.KO if GameConfig != null else 4
		collision_layer = GameConfig.LAYER_RAGDOLL_KO if GameConfig != null else 8
		collision_mask = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
		if head != null:
			head.rotation.z = deg_to_rad(22.0)
	else:
		ko_remaining_seconds = 0.0
		wakeup_immunity_remaining = imm_sec
		stance_state = GameConfig.Stance.WALK if GameConfig != null else 0
		collision_layer = GameConfig.LAYER_PLAYER if GameConfig != null else 4
		collision_mask = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_PLAYER) if GameConfig != null else 5
		if head != null:
			head.rotation.z = 0.0
	_update_hud_status()


func wake_up_from_ko() -> void:
	var imm_dur: float = GameConfig.ko_wakeup_immunity_duration if GameConfig != null else 2.0
	if _is_peer_connected() and multiplayer.is_server():
		_rpc_apply_ko_state.rpc(0.0, imm_dur, false)
	else:
		_rpc_apply_ko_state(0.0, imm_dur, false)
	if is_inside_tree() and is_multiplayer_authority() and prompt_label != null:
		prompt_label.visible = false


func tick_ko_and_immunity(delta: float) -> void:
	var is_local_auth: bool = is_inside_tree() and is_multiplayer_authority()
	var ko_stance: int = GameConfig.Stance.KO if GameConfig != null else 4
	if stance_state == ko_stance:
		ko_remaining_seconds -= delta
		var clamped_ko: float = maxf(ko_remaining_seconds, 0.0)
		if is_local_auth:
			if stance_label != null:
				stance_label.text = "KNOCKED OUT! (%.1fs)" % clamped_ko
			if prompt_label != null:
				prompt_label.text = "KNOCKED OUT — Waking up in %.1fs..." % clamped_ko
				prompt_label.visible = true
		if ko_remaining_seconds <= 0.0:
			if not _is_peer_connected() or (is_inside_tree() and multiplayer.is_server()) or is_local_auth:
				wake_up_from_ko()
		return

	if wakeup_immunity_remaining > 0.0:
		wakeup_immunity_remaining = maxf(wakeup_immunity_remaining - delta, 0.0)
		if mesh_instance != null:
			mesh_instance.visible = true if wakeup_immunity_remaining <= 0.0 else (int(wakeup_immunity_remaining * 10.0) % 2 == 0)
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
		clock_label.text = "CLOCK: %02d:%02d" % [mins, secs]
		clock_label.modulate = Color(1.0, 0.35, 0.30) if clamped_sec <= 30 else Color(1.0, 1.0, 1.0)
	if delta_bonus > 0.0 and bonus_toast_label != null:
		bonus_toast_label.text = "+%ds FIRST SEARCH!" % int(round(delta_bonus))
		bonus_toast_label.visible = true
		_bonus_toast_timer = 2.2


# ==========================================
# Server-Authoritative Hand & Pickup RPCs
# ==========================================

func server_pickup_world_item(item_id: String, extra_briefcase_items: Array, pickup_pos: Vector3) -> bool:
	var res: Dictionary = pickup_item(item_id, extra_briefcase_items)
	if not bool(res["picked"]):
		return false

	if str(res["dropped_item_id"]) != "NONE":
		_server_spawn_floor_drop(
			str(res["dropped_item_id"]),
			res["dropped_briefcase_items"],
			pickup_pos,
			bool(res.get("dropped_briefcase_armed_bomb", false)),
			int(res.get("dropped_briefcase_bomb_owner", 0))
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
					int(entry.get("dropped_briefcase_bomb_owner", 0))
				)

	if str(res["dropped_item_id"]) != "NONE":
		var forward_offset: Vector3 = (-global_transform.basis.z * 0.75) if is_inside_tree() else Vector3(0.0, 0.0, -0.75)
		var drop_pos: Vector3 = _compute_safe_drop_position(forward_offset)
		_server_spawn_floor_drop(
			str(res["dropped_item_id"]),
			res["dropped_briefcase_items"],
			drop_pos,
			bool(res.get("dropped_briefcase_armed_bomb", false)),
			int(res.get("dropped_briefcase_bomb_owner", 0))
		)

	_sync_inventory_state_to_peers()


func _compute_safe_drop_position(desired_offset: Vector3) -> Vector3:
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
		var horiz_mask: int = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3
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
			inv.briefcase_objectives,
			inv.jacket_slots,
			inv.active_jacket_slot,
			inv.right_hand_mode,
			inv.is_charging_club
		)
	elif _container_ui != null and _container_ui.visible:
		_container_ui.refresh_view()


@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_inventory(l_item: String, b_objs: Array, j_slots: Array, a_slot: int, r_mode: int, charging: bool) -> void:
	if not _is_authorized_state_rpc():
		return
	_inv().apply_sync_state(l_item, b_objs, j_slots, a_slot, r_mode, charging)
	_refresh_hand_and_back_sockets()
	_update_hud_status()
	if _container_ui != null and _container_ui.visible:
		_container_ui.refresh_view()


func _server_spawn_floor_drop(dropped_id: String, b_objs: Array, world_pos: Vector3, b_armed_bomb: bool = false, b_bomb_owner: int = 0) -> void:
	_drop_counter += 1
	var drop_name: String = "Dropped_%s_%s_%d" % [name, dropped_id, _drop_counter]
	if _is_peer_connected():
		_rpc_spawn_dropped_pickup.rpc(dropped_id, b_objs, world_pos, drop_name, b_armed_bomb, b_bomb_owner)
	else:
		_rpc_spawn_dropped_pickup(dropped_id, b_objs, world_pos, drop_name, b_armed_bomb, b_bomb_owner)


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_dropped_pickup(dropped_id: String, b_objs: Array, world_pos: Vector3, drop_name: String, b_armed_bomb: bool = false, b_bomb_owner: int = 0) -> void:
	if not _is_authorized_state_rpc():
		return
	var target_root: Node = get_tree().current_scene if get_tree() != null else null
	if target_root == null:
		target_root = get_parent()
	if target_root == null:
		return

	var pickup: StaticBody3D = PICKUP_SCENE.instantiate() as StaticBody3D
	pickup.name = drop_name
	pickup.set("item_id", dropped_id)
	var typed_objs: Array[String] = []
	for item in b_objs:
		typed_objs.append(str(item))
	pickup.set("packed_objectives", typed_objs)
	pickup.set("armed_bomb", b_armed_bomb)
	pickup.set("bomb_owner_peer_id", b_bomb_owner)
	target_root.add_child(pickup)
	pickup.global_position = Vector3(world_pos.x, maxf(world_pos.y, 0.0), world_pos.z)


# ==========================================
# Visual Sockets & HUD Updates
# ==========================================

func _update_mesh_color() -> void:
	if not is_inside_tree() or not mesh_instance:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_SPY_BLACK if spy_role == SpyRole.SPY_BLACK else COLOR_SPY_WHITE
	mesh_instance.material_override = mat


func _setup_wearable_visual() -> void:
	var w_socket: Marker3D = spy_wearable_socket if spy_wearable_socket != null else get_node_or_null("VisualRig/SpyWearableSocket") as Marker3D
	if w_socket == null or w_socket.get_child_count() > 0:
		return
	var watch_mi := MeshInstance3D.new()
	watch_mi.name = "SpyWristwatchMesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.05, 0.08)
	watch_mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.85, 0.75)
	watch_mi.material_override = mat
	w_socket.add_child(watch_mi)


func _refresh_hand_and_back_sockets() -> void:
	var b_socket: Marker3D = back_club_socket if back_club_socket != null else get_node_or_null("VisualRig/BackClubSocket") as Marker3D
	var l_socket: Marker3D = left_hand_socket if left_hand_socket != null else get_node_or_null("Head/Camera3D/LeftHandSocket") as Marker3D
	var r_socket: Marker3D = right_hand_socket if right_hand_socket != null else get_node_or_null("Head/Camera3D/RightHandSocket") as Marker3D

	if b_socket != null:
		for c in b_socket.get_children():
			c.queue_free()
		if right_hand_item_id != "CLUB":
			var club_back: MeshInstance3D = PICKUP_SCRIPT.build_item_mesh("CLUB")
			club_back.name = "HolsteredClubMesh"
			b_socket.add_child(club_back)

	if l_socket != null:
		for c in l_socket.get_children():
			c.queue_free()
		if left_hand_item_id != "NONE":
			var l_mesh: MeshInstance3D = PICKUP_SCRIPT.build_item_mesh(left_hand_item_id)
			l_mesh.name = "LeftHeldMesh"
			l_socket.add_child(l_mesh)

	if r_socket != null:
		for c in r_socket.get_children():
			c.queue_free()
		if right_hand_item_id != "NONE":
			var r_mesh: MeshInstance3D = PICKUP_SCRIPT.build_item_mesh(right_hand_item_id)
			r_mesh.name = "RightHeldMesh"
			if right_hand_item_id == "CLUB" and is_charging_club:
				r_mesh.position = Vector3(-0.12, 0.34, 0.05)
				r_mesh.rotation.x = deg_to_rad(-45.0)
			r_socket.add_child(r_mesh)


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


func _is_peer_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _is_peer_connected() or not is_multiplayer_authority():
		return

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
		return
	if _interact_key_down:
		_tick_active_interact_hold(delta)
	if stance_state == lock_stance:
		prompt_label.visible = false
		_tick_drawer_open_input(delta)
		return

	_process_interaction_raycast()


func _is_e_key_pressed() -> bool:
	return (
		Input.is_action_pressed("interact_primary")
		or Input.is_action_pressed("interact")
		or Input.is_key_pressed(KEY_E)
	)


func _tick_drawer_open_input(delta: float) -> void:
	if active_container == null or not is_instance_valid(active_container):
		return
	var e_down: bool = _is_e_key_pressed()
	if _drawer_focus_just_entered:
		if not e_down:
			_drawer_focus_just_entered = false
		return
	if bool(active_container.get("is_briefcase_container")):
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
		if _drawer_e_hold_elapsed >= TAP_RELEASE_THRESHOLD and active_container.has_method("request_step_open_drawer"):
			active_container.request_step_open_drawer(my_peer_id, delta)
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

	var supports_hold: bool = (
		_interact_target.has_method("request_hold_interaction")
		and (not _interact_target.has_method("supports_hold_interaction") or bool(_interact_target.supports_hold_interaction()))
	)
	if not supports_hold:
		if not e_down:
			_reset_interact_hold()
		return

	var my_peer_id: int = multiplayer.get_unique_id() if _is_peer_connected() else 1
	if _interact_target.has_method("request_step_push"):
		if e_down:
			_interact_hold_elapsed += delta
			if _interact_hold_elapsed >= TAP_RELEASE_THRESHOLD:
				_interact_hold_triggered = true
				_interact_target.request_step_push(my_peer_id, delta)
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
			if _interact_hold_elapsed >= hold_dur:
				_interact_hold_triggered = true
				_interact_target.request_hold_interaction(my_peer_id)
	else:
		if not _interact_hold_triggered:
			_interact_target.request_interaction(my_peer_id)
		_reset_interact_hold()


func _process_interaction_raycast() -> void:
	var is_interactable: bool = false
	var target_collider: Object = null

	if raycast != null and raycast.is_colliding():
		var collider: Object = raycast.get_collider()
		while collider is Node and not collider.has_method("request_interaction"):
			collider = collider.get_parent()
		if collider and collider.has_method("request_interaction"):
			is_interactable = true
			target_collider = collider

	prompt_label.visible = is_interactable
	if is_interactable:
		prompt_label.text = target_collider.get_interaction_prompt() if target_collider.has_method("get_interaction_prompt") else "[E] Interact"

	if hold_progress_bar != null:
		hold_progress_bar.visible = false

	var e_down: bool = _is_e_key_pressed()
	var e_just_pressed: bool = (
		Input.is_action_just_pressed("interact_primary")
		or Input.is_action_just_pressed("interact")
		or (e_down and not _interact_key_down)
	)

	var my_peer_id: int = multiplayer.get_unique_id() if _is_peer_connected() else 1
	if is_interactable and target_collider != null and e_just_pressed and not _interact_key_down:
		if target_collider.has_method("request_focus_container"):
			_drawer_focus_just_entered = true
			target_collider.request_focus_container(my_peer_id)
			return
		var supports_hold: bool = (
			target_collider.has_method("request_hold_interaction")
			and (not target_collider.has_method("supports_hold_interaction") or bool(target_collider.supports_hold_interaction()))
		)
		_interact_key_down = true
		_interact_hold_elapsed = 0.0
		_interact_hold_triggered = false
		_interact_target = target_collider
		if not supports_hold:
			_interact_hold_triggered = true
			target_collider.request_interaction(my_peer_id)


func _reset_interact_hold() -> void:
	_interact_key_down = false
	_interact_hold_elapsed = 0.0
	_interact_hold_triggered = false
	_interact_target = null
	if hold_progress_bar != null:
		hold_progress_bar.visible = false


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_multiplayer_authority():
		return

	var lock_stance: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	if stance_state == lock_stance:
		var is_exit_key: bool = (
			event.is_action_pressed("move_left")
			or event.is_action_pressed("move_back")
			or event.is_action_pressed("move_right")
			or event.is_action_pressed("ui_cancel")
			or (event is InputEventKey and event.pressed and not event.is_echo() and (event.keycode in [KEY_A, KEY_S, KEY_D, KEY_ESCAPE]))
		)
		if is_exit_key:
			if _dragging_3d_clutter_idx != -1:
				_finish_container_3d_drag()
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
				elif event.button_index == MOUSE_BUTTON_LEFT and _dragging_3d_clutter_idx != -1:
					_finish_container_3d_drag()
					get_viewport().set_input_as_handled()
			elif event is InputEventMouseMotion and _dragging_3d_clutter_idx != -1:
				_update_container_3d_drag(event.position)
				get_viewport().set_input_as_handled()


func _is_point_over_interactive_ui(screen_pos: Vector2) -> bool:
	if _container_ui == null or not is_instance_valid(_container_ui):
		return false
	for btn in _container_ui.find_children("*", "Button", true, false):
		if btn is Control and (btn as Control).is_visible_in_tree():
			if (btn as Control).get_global_rect().has_point(screen_pos):
				return true
	return false


func _raycast_container_3d(screen_pos: Vector2) -> Dictionary:
	if camera == null or get_world_3d() == null:
		return {}
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return {}
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 4.0, 32)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider_node: Node = hit.get("collider") as Node
	if collider_node == null or active_container == null or not active_container.is_ancestor_of(collider_node):
		return {}
	if not bool(active_container.get("is_briefcase_container")) and active_container is Node3D:
		var local_hit: Vector3 = (active_container as Node3D).to_local(hit["position"])
		if local_hit.z < 0.34:
			return {}
	return hit


func _handle_container_3d_mouse_down(screen_pos: Vector2, button_index: int) -> bool:
	var hit: Dictionary = _raycast_container_3d(screen_pos)
	if hit.is_empty():
		return false
	var hit_area: Node3D = hit["collider"] as Node3D
	var hit_pos: Vector3 = hit["position"]
	var role: String = str(hit_area.get_meta("container_role", ""))
	var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()

	match role:
		"clutter":
			if button_index != MOUSE_BUTTON_LEFT:
				return false
			var tray: Node3D = active_container.get_tray_node() if active_container.has_method("get_tray_node") else null
			if tray == null:
				return false
			var local_hit: Vector3 = tray.to_local(hit_pos)
			_dragging_3d_clutter_idx = int(hit_area.get_meta("clutter_idx", -1))
			_dragging_3d_clutter_node = hit_area
			_dragging_3d_plane_y = hit_pos.y
			_dragging_3d_offset_xz = Vector2(hit_area.position.x - local_hit.x, hit_area.position.z - local_hit.z)
			hit_area.position.y = float(hit_area.get_meta("base_y", hit_area.position.y)) + 0.025
			return true
		"loot_item":
			if button_index == MOUSE_BUTTON_LEFT and active_container.has_method("request_loot_item"):
				active_container.request_loot_item(my_id, str(hit_area.get_meta("item_id", "")), -1)
				return true
		"lip_spring":
			if bool(active_container.get("armed_spring")) and button_index == MOUSE_BUTTON_LEFT:
				active_container.request_unlatch_spring(my_id)
				return true
			elif bool(active_container.get("spring_unlatched")):
				if button_index == MOUSE_BUTTON_RIGHT:
					active_container.request_rearm_spring(my_id)
				else:
					active_container.request_steal_spring(my_id, -1)
				return true
		"lit_bomb":
			if button_index == MOUSE_BUTTON_LEFT and active_container.has_method("request_grab_lit_bomb"):
				active_container.request_grab_lit_bomb(my_id)
				return true
	return false


func _update_container_3d_drag(screen_pos: Vector2) -> void:
	if active_container == null or not is_instance_valid(active_container) or _dragging_3d_clutter_node == null or not is_instance_valid(_dragging_3d_clutter_node):
		_dragging_3d_clutter_idx = -1
		_dragging_3d_clutter_node = null
		return
	var tray: Node3D = active_container.get_tray_node() if active_container.has_method("get_tray_node") else null
	if tray == null or camera == null:
		return
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var world_hit: Variant = Plane(Vector3.UP, _dragging_3d_plane_y).intersects_ray(ray_origin, ray_dir)
	if world_hit is Vector3:
		var local_pt: Vector3 = tray.to_local(world_hit as Vector3)
		_dragging_3d_clutter_node.position.x = clampf(local_pt.x + _dragging_3d_offset_xz.x, -0.33, 0.33)
		_dragging_3d_clutter_node.position.z = clampf(local_pt.z + _dragging_3d_offset_xz.y, -0.17, 0.17)


func _finish_container_3d_drag() -> void:
	var idx: int = _dragging_3d_clutter_idx
	var node: Node3D = _dragging_3d_clutter_node
	_dragging_3d_clutter_idx = -1
	_dragging_3d_clutter_node = null
	if node == null or not is_instance_valid(node) or active_container == null or not is_instance_valid(active_container):
		return
	node.position.y = float(node.get_meta("base_y", node.position.y))
	if active_container.has_method("tray_local_xz_to_norm") and active_container.has_method("request_move_clutter"):
		var norm_pos: Vector2 = active_container.tray_local_xz_to_norm(node.position.x, node.position.z)
		var my_id: int = multiplayer.get_unique_id() if _is_peer_connected() else name.to_int()
		active_container.request_move_clutter(my_id, idx, norm_pos)


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
	if event.is_action_pressed("toggle_club") and not event.is_echo():
		_trigger_hand_action("TOGGLE_CLUB")
		return

	if event.is_action_pressed("primary_action") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if right_hand_mode == SpyInventoryComponent.RightHandMode.CLUB and not is_charging_club:
			_trigger_hand_action("START_CLUB_CHARGE")
	elif event.is_action_released("primary_action"):
		if is_charging_club:
			_trigger_hand_action("STOP_CLUB_CHARGE")

	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ESCAPE):
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
			if not esc_open:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var eff_sens: float = GameConfig.get_effective_mouse_sensitivity() if GameConfig != null else mouse_sensitivity
		rotate_y(-event.relative.x * eff_sens)
		head.rotate_x(-event.relative.y * eff_sens)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
		head_pitch = head.rotation.x


func _trigger_hand_action(action_type: String, slot_arg: int = 0) -> void:
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


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	tick_ko_and_immunity(delta)

	var target_neck_y: float = GameConfig.standing_neck_y if GameConfig != null else 1.6
	if stance_state == (GameConfig.Stance.KO if GameConfig != null else 4):
		target_neck_y = 0.35
	elif stance_state == (GameConfig.Stance.CROUCH if GameConfig != null else 2):
		target_neck_y = GameConfig.crouched_neck_y if GameConfig != null else 0.85

	if head != null:
		var lerp_spd: float = GameConfig.stance_transition_speed if GameConfig != null else 12.0
		head.position.y = lerpf(head.position.y, target_neck_y, clampf(lerp_spd * delta, 0.0, 1.0))

	if not _is_peer_connected() or not is_multiplayer_authority():
		if position.distance_squared_to(_target_position) > 16.0:
			position = _target_position
		else:
			position = position.lerp(_target_position, 20.0 * delta)
		rotation.y = lerp_angle(rotation.y, _target_yaw, 20.0 * delta)
		head.rotation.x = lerp_angle(head.rotation.x, head_pitch, 20.0 * delta)
		return

	var wants_crouch: bool = (
		(InputMap.has_action("crouch") and Input.is_action_pressed("crouch"))
		or Input.is_key_pressed(KEY_CTRL)
	)
	var wants_sprint: bool = (
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
		on_floor_now
		and stance_state != (GameConfig.Stance.CROUCH if GameConfig != null else 2)
		and stance_state != (GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3)
		and stance_state != (GameConfig.Stance.KO if GameConfig != null else 4)
		and not is_charging_club
	)
	if can_jump and (Input.is_action_just_pressed("jump") or Input.is_key_pressed(KEY_SPACE)):
		velocity.y = GameConfig.jump_velocity if GameConfig != null else jump_velocity

	var input_dir: Vector2 = Vector2.ZERO
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
	if direction != Vector3.ZERO and active_speed > 0.0:
		velocity.x = direction.x * active_speed
		velocity.z = direction.z * active_speed
		_tick_footsteps(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, maxf(active_speed, 4.5))
		velocity.z = move_toward(velocity.z, 0.0, maxf(active_speed, 4.5))
		_footstep_timer = 0.0

	move_and_slide()

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
