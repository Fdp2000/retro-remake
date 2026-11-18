@tool
class_name SpyRagdollController
extends Node3D

## Manages the 3D Agent Model (AgentGreen / AgentPurple), procedural locomotion posing,
## and 11-bone PhysicalBoneSimulator3D ragdoll physics for the 15s KO state (Group F: F1-F5).

const AGENT_GREEN_SCENE: PackedScene = preload("res://Assets/Prefabs_Agents/AgentGreen.tscn")
const AGENT_PURPLE_SCENE: PackedScene = preload("res://Assets/Prefabs_Agents/AgentPurple.tscn")

const RAGDOLL_BONE_DEFS: Array[Dictionary] = [
	{"bone": "spine", "radius": 0.16, "height": 0.36, "mass": 14.0, "joint": "NONE", "offset_y": 0.12},
	{"bone": "spine.002", "radius": 0.17, "height": 0.42, "mass": 16.0, "joint": "CONE", "offset_y": 0.16, "swing": 28.0, "twist": 22.0},
	{"bone": "spine.006", "radius": 0.15, "height": 0.34, "mass": 5.0, "joint": "CONE", "offset_y": 0.15, "swing": 35.0, "twist": 35.0},
	{"bone": "upper_arm.L", "radius": 0.07, "height": 0.26, "mass": 3.0, "joint": "CONE", "offset_y": 0.12, "swing": 65.0, "twist": 30.0},
	{"bone": "forearm.L", "radius": 0.06, "height": 0.24, "mass": 2.0, "joint": "PIN", "offset_y": 0.11},
	{"bone": "upper_arm.R", "radius": 0.07, "height": 0.26, "mass": 3.0, "joint": "CONE", "offset_y": 0.12, "swing": 65.0, "twist": 30.0},
	{"bone": "forearm.R", "radius": 0.06, "height": 0.24, "mass": 2.0, "joint": "PIN", "offset_y": 0.11},
	{"bone": "thigh.L", "radius": 0.09, "height": 0.28, "mass": 6.0, "joint": "CONE", "offset_y": 0.10, "swing": 45.0, "twist": 20.0},
	{"bone": "shin.L", "radius": 0.08, "height": 0.28, "mass": 4.0, "joint": "PIN", "offset_y": 0.11},
	{"bone": "thigh.R", "radius": 0.09, "height": 0.28, "mass": 6.0, "joint": "CONE", "offset_y": 0.10, "swing": 45.0, "twist": 20.0},
	{"bone": "shin.R", "radius": 0.08, "height": 0.28, "mass": 4.0, "joint": "PIN", "offset_y": 0.11}
]

var current_role: int = 0
var agent_instance: Node3D = null
var skeleton: Skeleton3D = null
var simulator: PhysicalBoneSimulator3D = null
var physical_bones: Dictionary = {} # bone_name -> PhysicalBone3D
var is_ragdoll_active: bool = false
var is_first_person_local: bool = false
var _walk_cycle_phase: float = 0.0
var _pelvis_sync_target: Vector3 = Vector3.ZERO
var _has_pelvis_sync_target: bool = false


func setup_for_role(role: int, local_first_person: bool = false) -> void:
	is_first_person_local = local_first_person
	if agent_instance != null and is_instance_valid(agent_instance) and current_role == role:
		_apply_first_person_head_mode()
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
		_build_physical_bone_simulator()
		_apply_idle_standing_pose(0.0, false)
	_apply_first_person_head_mode()


func _configure_meshes_cull_margin() -> void:
	if skeleton == null:
		return
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).extra_cull_margin = 16.0


func set_first_person_local(local_fp: bool) -> void:
	is_first_person_local = local_fp
	_apply_first_person_head_mode()


func _apply_first_person_head_mode() -> void:
	if skeleton == null:
		return
	for mesh_name in ["Head", "Eyes"]:
		var m: MeshInstance3D = skeleton.get_node_or_null(mesh_name) as MeshInstance3D
		if m != null:
			m.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				if is_first_person_local
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			)


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
		pb.bounce = 0.12
		pb.linear_damp = 0.45
		pb.angular_damp = 1.8

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
			pb.set("joint_constraints/swing_span", float(def.get("swing", 35.0)))
			pb.set("joint_constraints/twist_span", float(def.get("twist", 25.0)))
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
		is_ragdoll_active = true
		simulator.active = true
		simulator.physical_bones_start_simulation()

	apply_ragdoll_impulse(impulse, reason)


func apply_ragdoll_impulse(impulse: Vector3, reason: String = "") -> void:
	if not is_ragdoll_active or physical_bones.is_empty():
		return

	var pelvis_pb: PhysicalBone3D = physical_bones.get("spine") as PhysicalBone3D
	var chest_pb: PhysicalBone3D = physical_bones.get("spine.002") as PhysicalBone3D
	var head_pb: PhysicalBone3D = physical_bones.get("spine.006") as PhysicalBone3D
	var shin_l: PhysicalBone3D = physical_bones.get("shin.L") as PhysicalBone3D
	var shin_r: PhysicalBone3D = physical_bones.get("shin.R") as PhysicalBone3D

	var kind: String = reason.to_upper()
	match kind:
		"DART_GUN":
			# Dart gives a strong high-velocity kick to the upper chest & head
			if chest_pb != null:
				chest_pb.linear_velocity += impulse * 1.15
				chest_pb.angular_velocity += Vector3(impulse.z, 0.0, -impulse.x).normalized() * 9.5
			if head_pb != null:
				head_pb.linear_velocity += impulse * 1.35 + Vector3(0.0, 2.2, 0.0)
			if pelvis_pb != null:
				pelvis_pb.linear_velocity += impulse * 0.70
		"TRIPWIRE":
			# Sweep feet backward while pitching torso forward into a face-plant
			var fwd_dir := Vector3(impulse.x, 0.0, impulse.z).normalized()
			if fwd_dir.length_squared() < 0.01:
				fwd_dir = -global_transform.basis.z
			if shin_l != null:
				shin_l.linear_velocity += -fwd_dir * 7.5 + Vector3(0.0, 4.2, 0.0)
			if shin_r != null:
				shin_r.linear_velocity += -fwd_dir * 7.5 + Vector3(0.0, 4.2, 0.0)
			if chest_pb != null:
				chest_pb.linear_velocity += fwd_dir * 5.8 + Vector3(0.0, -2.5, 0.0)
			if head_pb != null:
				head_pb.linear_velocity += fwd_dir * 6.5 + Vector3(0.0, -3.0, 0.0)
		"BUCKET":
			# Heavy downward overhead splash crumple
			if head_pb != null:
				head_pb.linear_velocity += impulse + Vector3(0.0, -6.5, 0.0)
			if chest_pb != null:
				chest_pb.linear_velocity += impulse * 0.85 + Vector3(0.0, -5.0, 0.0)
			if pelvis_pb != null:
				pelvis_pb.linear_velocity += impulse * 0.5 + Vector3(0.0, -3.0, 0.0)
		"SPRING":
			# Violent chest launch backward out of the drawer
			if chest_pb != null:
				chest_pb.linear_velocity += impulse * 1.20
				chest_pb.angular_velocity += Vector3(impulse.z, 0.0, -impulse.x).normalized() * 8.0
			if pelvis_pb != null:
				pelvis_pb.linear_velocity += impulse * 0.95
			if head_pb != null:
				head_pb.linear_velocity += impulse * 1.10
		"CLUB":
			# Heavy rotational melee slam
			if chest_pb != null:
				chest_pb.linear_velocity += impulse * 1.15
				chest_pb.angular_velocity += Vector3(impulse.z, 4.5, -impulse.x).normalized() * 11.0
			if pelvis_pb != null:
				pelvis_pb.linear_velocity += impulse * 0.90
			if head_pb != null:
				head_pb.linear_velocity += impulse * 1.25
		_:
			# BOMB and general high-energy full-body launch
			for b_key in physical_bones.keys():
				var pb: PhysicalBone3D = physical_bones[b_key] as PhysicalBone3D
				if pb != null:
					pb.linear_velocity += impulse


func stop_ragdoll() -> void:
	_has_pelvis_sync_target = false
	if simulator != null and is_ragdoll_active:
		simulator.physical_bones_stop_simulation()
		simulator.active = false
	is_ragdoll_active = false
	if skeleton != null:
		skeleton.reset_bone_poses()
		_apply_idle_standing_pose(0.0, false)


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
	if skeleton != null and skeleton.is_inside_tree():
		var head_idx: int = skeleton.find_bone("spine.006")
		if head_idx != -1:
			var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_idx)
			# Rotate 180 deg around Y so Camera3D (-Z forward) looks out through the Agent's eyes (+Z bone forward)
			var eye_local := Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3(0.0, 0.16, 0.18))
			return head_world * eye_local
	return global_transform if is_inside_tree() else transform


func update_locomotion_pose(delta: float, horiz_speed: float, is_crouching: bool, head_pitch_rad: float, is_charging_club: bool) -> void:
	if is_ragdoll_active or skeleton == null:
		return
	if horiz_speed > 0.25:
		_walk_cycle_phase = fmod(_walk_cycle_phase + delta * horiz_speed * 2.4, TAU)
	else:
		_walk_cycle_phase = move_toward(_walk_cycle_phase, 0.0, delta * 8.0)

	_apply_idle_standing_pose(head_pitch_rad, is_crouching)

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


func _apply_idle_standing_pose(head_pitch_rad: float, is_crouching: bool) -> void:
	if skeleton == null:
		return
	skeleton.reset_bone_poses()
	# Fold arms down from T-pose toward the spy's trenchcoat sides in model space
	_rotate_bone_in_model_space("upper_arm.L", Vector3(0.0, 0.0, 1.0), -1.18)
	_rotate_bone_in_model_space("upper_arm.R", Vector3(0.0, 0.0, 1.0), 1.18)
	_rotate_bone_in_model_space("forearm.L", Vector3.RIGHT, -0.22)
	_rotate_bone_in_model_space("forearm.R", Vector3.RIGHT, -0.22)

	if is_crouching:
		var spine_idx: int = skeleton.find_bone("spine")
		if spine_idx != -1:
			var rest_t: Transform3D = skeleton.get_bone_rest(spine_idx)
			rest_t.origin.y -= 0.32
			skeleton.set_bone_pose_position(spine_idx, rest_t.origin)
		_rotate_bone_in_model_space("spine.001", Vector3.RIGHT, 0.30)

	# Apply head pitch in model space
	_rotate_bone_in_model_space("spine.006", Vector3.RIGHT, -clampf(head_pitch_rad, -0.8, 0.8))


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
