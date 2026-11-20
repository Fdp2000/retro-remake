@tool
class_name SpyRagdollController
extends Node3D

## Manages the 3D Agent Model (AgentGreen / AgentPurple), procedural locomotion posing,
## permanent first-person head-bone camera anchor, and PhysicalBoneSimulator3D ragdoll physics (Group F: F1-F5).

const AGENT_GREEN_SCENE: PackedScene = preload("res://Assets/Prefabs_Agents/AgentGreen.tscn")
const AGENT_PURPLE_SCENE: PackedScene = preload("res://Assets/Prefabs_Agents/AgentPurple.tscn")

# Continuous 13-bone ragdoll chain (no missing intermediate spine links, and leg capsules sized cleanly above y=0 floor)
const RAGDOLL_BONE_DEFS: Array[Dictionary] = [
	{"bone": "spine", "radius": 0.14, "height": 0.28, "mass": 12.0, "joint": "NONE", "offset_y": 0.10},
	{"bone": "spine.001", "radius": 0.13, "height": 0.26, "mass": 8.0, "joint": "CONE", "offset_y": 0.09, "swing": 22.0, "twist": 18.0},
	{"bone": "spine.002", "radius": 0.14, "height": 0.28, "mass": 10.0, "joint": "CONE", "offset_y": 0.10, "swing": 24.0, "twist": 20.0},
	{"bone": "spine.003", "radius": 0.14, "height": 0.28, "mass": 10.0, "joint": "CONE", "offset_y": 0.11, "swing": 24.0, "twist": 20.0},
	{"bone": "spine.006", "radius": 0.14, "height": 0.30, "mass": 5.0, "joint": "CONE", "offset_y": 0.14, "swing": 35.0, "twist": 30.0},
	{"bone": "upper_arm.L", "radius": 0.06, "height": 0.22, "mass": 2.5, "joint": "CONE", "offset_y": 0.11, "swing": 65.0, "twist": 30.0},
	{"bone": "forearm.L", "radius": 0.055, "height": 0.20, "mass": 1.8, "joint": "PIN", "offset_y": 0.10},
	{"bone": "upper_arm.R", "radius": 0.06, "height": 0.22, "mass": 2.5, "joint": "CONE", "offset_y": 0.11, "swing": 65.0, "twist": 30.0},
	{"bone": "forearm.R", "radius": 0.055, "height": 0.20, "mass": 1.8, "joint": "PIN", "offset_y": 0.10},
	{"bone": "thigh.L", "radius": 0.06, "height": 0.14, "mass": 5.0, "joint": "CONE", "offset_y": 0.07, "swing": 45.0, "twist": 20.0},
	{"bone": "shin.L", "radius": 0.055, "height": 0.14, "mass": 3.5, "joint": "PIN", "offset_y": 0.07},
	{"bone": "thigh.R", "radius": 0.06, "height": 0.14, "mass": 5.0, "joint": "CONE", "offset_y": 0.07, "swing": 45.0, "twist": 20.0},
	{"bone": "shin.R", "radius": 0.055, "height": 0.14, "mass": 3.5, "joint": "PIN", "offset_y": 0.07}
]

var current_role: int = 0
var agent_instance: Node3D = null
var skeleton: Skeleton3D = null
var simulator: PhysicalBoneSimulator3D = null
var physical_bones: Dictionary = {} # bone_name -> PhysicalBone3D
var is_ragdoll_active: bool = false
var is_first_person_local: bool = false
var body_visual_layer: int = 1
var _walk_cycle_phase: float = 0.0
var _crouch_blend: float = 0.0
var _pelvis_sync_target: Vector3 = Vector3.ZERO
var _has_pelvis_sync_target: bool = false
var _head_eye_bone_local: Transform3D = Transform3D.IDENTITY
var _pending_impulse: Vector3 = Vector3.ZERO
var _pending_reason: String = ""
var _pending_impulse_frames: int = 0
var _bucket_head_mount: MeshInstance3D = null
var _bucket_on_head_active: bool = false


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if is_ragdoll_active and _pending_impulse_frames > 0:
		_pending_impulse_frames -= 1
		_apply_impulse_to_bones(_pending_impulse, _pending_reason)


func setup_for_role(role: int, local_first_person: bool = false) -> void:
	is_first_person_local = local_first_person
	var local_layer: int = GameConfig.VISUAL_LAYER_LOCAL_SPY_BODY if GameConfig != null else (1 << 10)
	if is_first_person_local:
		body_visual_layer = local_layer
	elif body_visual_layer == local_layer:
		body_visual_layer = 1
	if agent_instance != null and is_instance_valid(agent_instance) and current_role == role:
		_apply_first_person_visibility_mode()
		_sync_owner_camera_cull_mask()
		return

	if is_ragdoll_active:
		stop_ragdoll()

	current_role = role
	if agent_instance != null and is_instance_valid(agent_instance):
		remove_child(agent_instance)
		agent_instance.queue_free()
		agent_instance = null
		skeleton = null
		simulator = null
		_bucket_head_mount = null
		physical_bones.clear()

	var packed: PackedScene = AGENT_PURPLE_SCENE if role == 2 else AGENT_GREEN_SCENE
	if packed == null:
		return

	agent_instance = packed.instantiate() as Node3D
	agent_instance.name = "AgentModel"
	# Agent.glb faces +Z; rotate 180 deg around Y so the spy faces Godot forward (-Z)
	agent_instance.rotation.y = PI
	add_child(agent_instance)

	skeleton = agent_instance.get_node_or_null("metarig/Skeleton3D") as Skeleton3D
	if skeleton != null:
		_configure_meshes_cull_margin()
		_calibrate_permanent_head_camera_anchor()
		_build_physical_bone_simulator()
		_apply_idle_standing_pose(0.0, 0.0)
		_ensure_bucket_head_mount()
	_apply_first_person_visibility_mode()
	_sync_owner_camera_cull_mask()


func _configure_meshes_cull_margin() -> void:
	if skeleton == null:
		return
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).extra_cull_margin = 16.0


func _calibrate_permanent_head_camera_anchor() -> void:
	if skeleton == null:
		return
	var head_idx: int = skeleton.find_bone("spine.006")
	if head_idx == -1:
		return
	var stand_y: float = GameConfig.standing_neck_y if GameConfig != null else 1.6
	var rot_pi := Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3.ZERO)
	var head_in_ctrl: Transform3D = rot_pi * skeleton.get_bone_global_rest(head_idx)
	var desired_in_ctrl := Transform3D(Basis.IDENTITY, Vector3(0.0, stand_y, 0.0))
	_head_eye_bone_local = head_in_ctrl.affine_inverse() * desired_in_ctrl


func set_body_visual_layer(layer_mask: int) -> void:
	body_visual_layer = layer_mask if layer_mask > 0 else 1
	_apply_first_person_visibility_mode()


func set_first_person_local(local_fp: bool) -> void:
	is_first_person_local = local_fp
	var local_layer: int = GameConfig.VISUAL_LAYER_LOCAL_SPY_BODY if GameConfig != null else (1 << 10)
	if is_first_person_local:
		body_visual_layer = local_layer
	elif body_visual_layer == local_layer:
		body_visual_layer = 1
	_apply_first_person_visibility_mode()
	_sync_owner_camera_cull_mask()


func _sync_owner_camera_cull_mask() -> void:
	var owner_node: Node = get_parent()
	if owner_node != null and owner_node.name == "VisualRig":
		owner_node = owner_node.get_parent()
	if owner_node != null and owner_node.has_method("apply_local_camera_cull_mask"):
		owner_node.apply_local_camera_cull_mask()


func _apply_first_person_visibility_mode() -> void:
	if skeleton == null:
		return
	# Isolate Head/Eyes/Body onto dedicated visual render layers instead of setting visible=false,
	# so local FPS camera never clips its own head while rival CRT Trap-Cams can still render this spy.
	for child in skeleton.get_children():
		if child is MeshInstance3D and child.name != "SkeletonKeepAlive":
			var m: MeshInstance3D = child as MeshInstance3D
			m.visible = true
			m.layers = body_visual_layer
			m.extra_cull_margin = 16384.0 if (is_first_person_local and m.name == "Body") else 64.0

	# Ensure a skinned keep-alive MeshInstance3D stays in the frustum when local meshes are layer-culled
	# so Godot's renderer never culls Skeleton3D / PhysicalBoneSimulator3D updates during local KO!
	var keep_alive: MeshInstance3D = skeleton.get_node_or_null("SkeletonKeepAlive") as MeshInstance3D
	var body_mesh: MeshInstance3D = skeleton.get_node_or_null("Body") as MeshInstance3D
	if keep_alive == null and body_mesh != null:
		keep_alive = MeshInstance3D.new()
		keep_alive.name = "SkeletonKeepAlive"
		keep_alive.mesh = body_mesh.mesh
		keep_alive.skin = body_mesh.skin
		keep_alive.skeleton = NodePath("..")
		keep_alive.extra_cull_margin = 16384.0
		keep_alive.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ka_mat := StandardMaterial3D.new()
		ka_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ka_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.004)
		ka_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ka_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		keep_alive.material_override = ka_mat
		skeleton.add_child(keep_alive)
	if keep_alive != null:
		keep_alive.layers = body_visual_layer
		keep_alive.visible = is_first_person_local
	if _bucket_head_mount != null and is_instance_valid(_bucket_head_mount):
		_bucket_head_mount.layers = body_visual_layer


func set_bucket_on_head(active: bool) -> void:
	_bucket_on_head_active = active
	if active:
		_ensure_bucket_head_mount()
	if _bucket_head_mount != null and is_instance_valid(_bucket_head_mount):
		_bucket_head_mount.visible = active


func _ensure_bucket_head_mount() -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	if _bucket_head_mount != null and is_instance_valid(_bucket_head_mount):
		return
	var attach: BoneAttachment3D = skeleton.get_node_or_null("HeadBucketAttachment") as BoneAttachment3D
	if attach == null:
		attach = BoneAttachment3D.new()
		attach.name = "HeadBucketAttachment"
		attach.bone_name = "spine.006"
		skeleton.add_child(attach)
	var head_anchor: Node3D = attach.get_node_or_null("HeadAnchor") as Node3D
	if head_anchor == null:
		head_anchor = Node3D.new()
		head_anchor.name = "HeadAnchor"
		head_anchor.transform = _head_eye_bone_local
		attach.add_child(head_anchor)
	_bucket_head_mount = head_anchor.get_node_or_null("BucketHeadMount") as MeshInstance3D
	if _bucket_head_mount == null:
		const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
		_bucket_head_mount = PICKUP_SCRIPT.build_item_mesh("BUCKET")
		_bucket_head_mount.name = "BucketHeadMount"
		_bucket_head_mount.scale = Vector3(1.35, 1.10, 1.35)
		_bucket_head_mount.position = Vector3(0.0, 0.08, 0.0)
		_bucket_head_mount.rotation = Vector3(0.0, 0.0, PI)
		_bucket_head_mount.layers = body_visual_layer
		_bucket_head_mount.visible = _bucket_on_head_active
		head_anchor.add_child(_bucket_head_mount)


func _build_physical_bone_simulator() -> void:
	if skeleton == null:
		return
	var existing: Node = skeleton.get_node_or_null("PhysicalBoneSimulator3D")
	if existing is PhysicalBoneSimulator3D:
		simulator = existing as PhysicalBoneSimulator3D
		return

	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "PhysicalBoneSimulator3D"
	skeleton.add_child(simulator)

	var ko_layer: int = GameConfig.LAYER_RAGDOLL_KO if GameConfig != null else 8
	var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1

	for def in RAGDOLL_BONE_DEFS:
		var b_name: String = str(def["bone"])
		var b_idx: int = skeleton.find_bone(b_name)
		if b_idx == -1:
			continue

		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + b_name.replace(".", "_")
		pb.collision_layer = ko_layer
		pb.collision_mask = env_mask
		pb.mass = float(def["mass"])
		pb.friction = 0.85
		pb.bounce = 0.10
		pb.linear_damp = 0.55
		pb.angular_damp = 2.4

		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var cap := CapsuleShape3D.new()
		cap.radius = float(def["radius"])
		cap.height = maxf(float(def["height"]), cap.radius * 2.02)
		col.shape = cap
		col.position = Vector3(0.0, float(def["offset_y"]), 0.0)
		pb.add_child(col)

		simulator.add_child(pb)
		pb.bone_name = b_name
		pb.body_offset = Transform3D.IDENTITY
		pb.joint_offset = Transform3D.IDENTITY

		var j_kind: String = str(def["joint"])
		if j_kind == "CONE":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", float(def.get("swing", 30.0)))
			pb.set("joint_constraints/twist_span", float(def.get("twist", 20.0)))
		elif j_kind == "PIN":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
		else:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE

		physical_bones[b_name] = pb


func start_ragdoll(impulse: Vector3, reason: String = "") -> void:
	if skeleton == null or simulator == null:
		return
	_has_pelvis_sync_target = false
	if not is_ragdoll_active:
		# Reset to clean upright/crouch pose right before starting simulation so bones never start twisted
		_apply_idle_standing_pose(0.0, _crouch_blend)
		is_ragdoll_active = true
		simulator.active = true
		simulator.physical_bones_start_simulation()

	apply_ragdoll_impulse(impulse, reason)


func apply_ragdoll_impulse(impulse: Vector3, reason: String = "") -> void:
	if not is_ragdoll_active or physical_bones.is_empty():
		return
	_pending_impulse = impulse
	_pending_reason = reason
	_pending_impulse_frames = 2
	_apply_impulse_to_bones(impulse, reason)


func _apply_impulse_to_bones(impulse: Vector3, reason: String) -> void:
	var pelvis_pb: PhysicalBone3D = physical_bones.get("spine") as PhysicalBone3D
	var chest_pb: PhysicalBone3D = physical_bones.get("spine.002") as PhysicalBone3D
	var upper_chest_pb: PhysicalBone3D = physical_bones.get("spine.003") as PhysicalBone3D
	var head_pb: PhysicalBone3D = physical_bones.get("spine.006") as PhysicalBone3D
	var shin_l: PhysicalBone3D = physical_bones.get("shin.L") as PhysicalBone3D
	var shin_r: PhysicalBone3D = physical_bones.get("shin.R") as PhysicalBone3D

	var kind: String = reason.to_upper()
	match kind:
		"DART_GUN":
			# Dart gives a strong high-velocity kick to the upper chest & head
			if chest_pb != null:
				chest_pb.linear_velocity = impulse * 1.15
				chest_pb.angular_velocity = Vector3(impulse.z, 0.0, -impulse.x).normalized() * 8.5
			if upper_chest_pb != null:
				upper_chest_pb.linear_velocity = impulse * 1.25
			if head_pb != null:
				head_pb.linear_velocity = impulse * 1.35 + Vector3(0.0, 2.0, 0.0)
			if pelvis_pb != null:
				pelvis_pb.linear_velocity = impulse * 0.75
		"TRIPWIRE":
			var fwd_dir := Vector3(impulse.x, 0.0, impulse.z).normalized()
			if fwd_dir.length_squared() < 0.01:
				fwd_dir = -global_transform.basis.z
			if shin_l != null:
				shin_l.linear_velocity = -fwd_dir * 7.5 + Vector3(0.0, 4.0, 0.0)
			if shin_r != null:
				shin_r.linear_velocity = -fwd_dir * 7.5 + Vector3(0.0, 4.0, 0.0)
			if chest_pb != null:
				chest_pb.linear_velocity = fwd_dir * 6.0 + Vector3(0.0, -2.5, 0.0)
			if head_pb != null:
				head_pb.linear_velocity = fwd_dir * 6.8 + Vector3(0.0, -3.0, 0.0)
		"BUCKET":
			if head_pb != null:
				head_pb.linear_velocity = impulse + Vector3(0.0, -6.0, 0.0)
			if chest_pb != null:
				chest_pb.linear_velocity = impulse * 0.85 + Vector3(0.0, -4.5, 0.0)
			if pelvis_pb != null:
				pelvis_pb.linear_velocity = impulse * 0.5 + Vector3(0.0, -2.5, 0.0)
		"SPRING":
			if chest_pb != null:
				chest_pb.linear_velocity = impulse * 1.20
				chest_pb.angular_velocity = Vector3(impulse.z, 0.0, -impulse.x).normalized() * 7.5
			if pelvis_pb != null:
				pelvis_pb.linear_velocity = impulse * 0.95
			if head_pb != null:
				head_pb.linear_velocity = impulse * 1.10
		"CLUB":
			if chest_pb != null:
				chest_pb.linear_velocity = impulse * 1.15
				chest_pb.angular_velocity = Vector3(impulse.z, 4.0, -impulse.x).normalized() * 10.0
			if pelvis_pb != null:
				pelvis_pb.linear_velocity = impulse * 0.90
			if head_pb != null:
				head_pb.linear_velocity = impulse * 1.25
		"CLUB_OVERCHARGE":
			if chest_pb != null:
				chest_pb.linear_velocity = impulse * 0.85
				chest_pb.angular_velocity = Vector3(impulse.z, 0.0, -impulse.x).normalized() * 3.0
			if pelvis_pb != null:
				pelvis_pb.linear_velocity = impulse * 0.65
			if head_pb != null:
				head_pb.linear_velocity = impulse * 0.90
		_:
			for b_key in physical_bones.keys():
				var pb: PhysicalBone3D = physical_bones[b_key] as PhysicalBone3D
				if pb != null:
					pb.linear_velocity = impulse


func stop_ragdoll() -> void:
	set_bucket_on_head(false)
	_has_pelvis_sync_target = false
	_pending_impulse_frames = 0
	if simulator != null and is_ragdoll_active:
		simulator.physical_bones_stop_simulation()
		simulator.active = false
	is_ragdoll_active = false
	if skeleton != null:
		skeleton.reset_bone_poses()
		_apply_idle_standing_pose(0.0, _crouch_blend)


func set_remote_pelvis_sync_target(world_pos: Vector3) -> void:
	_pelvis_sync_target = world_pos
	_has_pelvis_sync_target = true


func step_remote_pelvis_pull(delta: float) -> void:
	if not is_ragdoll_active or not _has_pelvis_sync_target:
		return
	var pelvis_pb: PhysicalBone3D = physical_bones.get("spine") as PhysicalBone3D
	if pelvis_pb == null or not pelvis_pb.is_inside_tree():
		return
	var cur_pos: Vector3 = pelvis_pb.global_position
	var diff: Vector3 = _pelvis_sync_target - cur_pos
	var dist: float = diff.length()
	if dist > 4.5:
		pelvis_pb.global_position = _pelvis_sync_target
		return
	if dist > 0.04:
		var pull_vel: Vector3 = diff * minf(6.5, 18.0 * delta * 60.0)
		pelvis_pb.linear_velocity = pelvis_pb.linear_velocity.lerp(pull_vel, clampf(delta * 8.0, 0.0, 1.0))


func get_pelvis_world_position() -> Vector3:
	if skeleton != null and skeleton.is_inside_tree():
		var pelvis_pb: PhysicalBone3D = physical_bones.get("spine") as PhysicalBone3D
		if is_ragdoll_active and pelvis_pb != null and pelvis_pb.is_inside_tree():
			return pelvis_pb.global_position
		var idx: int = skeleton.find_bone("spine")
		if idx != -1:
			return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin
	return global_position if is_inside_tree() else position


func get_head_camera_world_transform() -> Transform3D:
	if is_ragdoll_active:
		var head_pb: PhysicalBone3D = physical_bones.get("spine.006") as PhysicalBone3D
		if head_pb != null and head_pb.is_inside_tree():
			return head_pb.global_transform * _head_eye_bone_local
	if skeleton != null and skeleton.is_inside_tree():
		var head_idx: int = skeleton.find_bone("spine.006")
		if head_idx != -1:
			var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_idx)
			return head_world * _head_eye_bone_local
	return global_transform if is_inside_tree() else transform


func update_locomotion_pose(delta: float, horiz_speed: float, is_crouching: bool, head_pitch_rad: float, is_charging_club: bool) -> void:
	if is_ragdoll_active or skeleton == null:
		return
	var target_crouch: float = 1.0 if is_crouching else 0.0
	var lerp_spd: float = GameConfig.stance_transition_speed if GameConfig != null else 12.0
	_crouch_blend = lerpf(_crouch_blend, target_crouch, clampf(lerp_spd * delta, 0.0, 1.0))

	if horiz_speed > 0.25:
		_walk_cycle_phase = fmod(_walk_cycle_phase + delta * horiz_speed * 2.4, TAU)
	else:
		_walk_cycle_phase = move_toward(_walk_cycle_phase, 0.0, delta * 8.0)

	_apply_idle_standing_pose(head_pitch_rad, _crouch_blend)

	var swing_amp: float = clampf(horiz_speed / 6.0, 0.0, 1.0) * 0.55
	var s: float = sin(_walk_cycle_phase) * swing_amp

	_rotate_bone_in_model_space("thigh.L", Vector3.RIGHT, s)
	_rotate_bone_in_model_space("thigh.R", Vector3.RIGHT, -s)
	_rotate_bone_in_model_space("shin.L", Vector3.RIGHT, maxf(0.0, -s * 0.85))
	_rotate_bone_in_model_space("shin.R", Vector3.RIGHT, maxf(0.0, s * 0.85))

	if is_charging_club:
		_rotate_bone_in_model_space("upper_arm.R", Vector3.RIGHT, -1.10)
		_rotate_bone_in_model_space("forearm.R", Vector3.RIGHT, -0.75)
	elif absf(s) > 0.01:
		_rotate_bone_in_model_space("upper_arm.L", Vector3(0.0, 0.0, 1.0), -1.18)
		_rotate_bone_in_model_space("upper_arm.R", Vector3(0.0, 0.0, 1.0), 1.18)


func _apply_idle_standing_pose(head_pitch_rad: float, crouch_ratio: float) -> void:
	if skeleton == null:
		return
	skeleton.reset_bone_poses()
	# Fold arms down from T-pose toward the spy's trenchcoat sides in model space
	_rotate_bone_in_model_space("upper_arm.L", Vector3(0.0, 0.0, 1.0), -1.18)
	_rotate_bone_in_model_space("upper_arm.R", Vector3(0.0, 0.0, 1.0), 1.18)
	_rotate_bone_in_model_space("forearm.L", Vector3.RIGHT, -0.22)
	_rotate_bone_in_model_space("forearm.R", Vector3.RIGHT, -0.22)

	if crouch_ratio > 0.001:
		var stand_y: float = GameConfig.standing_neck_y if GameConfig != null else 1.6
		var crouch_y: float = GameConfig.crouched_neck_y if GameConfig != null else 0.85
		var drop_y: float = (stand_y - crouch_y) * crouch_ratio
		var spine_idx: int = skeleton.find_bone("spine")
		if spine_idx != -1:
			var rest_t: Transform3D = skeleton.get_bone_rest(spine_idx)
			rest_t.origin.y -= drop_y
			skeleton.set_bone_pose_position(spine_idx, rest_t.origin)

	# Apply head pitch directly to spine.006 so the permanent head-bone camera pitches with mouse look
	_rotate_bone_in_model_space("spine.006", Vector3.RIGHT, -clampf(head_pitch_rad, deg_to_rad(-89.0), deg_to_rad(89.0)))


func _rotate_bone_in_model_space(bone_name: String, model_axis: Vector3, angle_rad: float) -> void:
	if skeleton == null:
		return
	var idx: int = skeleton.find_bone(bone_name)
	if idx == -1:
		return
	var g_rest: Basis = skeleton.get_bone_global_rest(idx).basis.orthonormalized()
	var local_axis: Vector3 = (g_rest.inverse() * model_axis).normalized()
	var rest_rot: Quaternion = skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(idx, rest_rot * Quaternion(local_axis, angle_rad))
