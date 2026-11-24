@tool
class_name SpyRagdollController
extends Node3D

## Manages the 3D Agent Model (AgentGreen / AgentPurple), procedural locomotion posing,
## permanent first-person head-bone camera anchor, and PhysicalBoneSimulator3D ragdoll physics (Group F: F1-F5).

const AGENT_GREEN_SCENE: PackedScene = preload("res://Assets/Prefabs_Agents/AgentGreen.tscn")
const AGENT_PURPLE_SCENE: PackedScene = preload("res://Assets/Prefabs_Agents/AgentPurple.tscn")
const AGENT_BLUE_SCENE: PackedScene = preload("res://Assets/Prefabs_Agents/AgentBlue.tscn")
const AGENT_RED_SCENE: PackedScene = preload("res://Assets/Prefabs_Agents/AgentRed.tscn")

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

const FP_BODY_PUSH_BACK_Z: float = 0.24
const FP_BODY_CROUCH_EXTRA_Z: float = 0.08
const FP_BODY_SPRINT_EXTRA_Z: float = 0.0

var current_role: int = 0
var agent_instance: Node3D = null
var skeleton: Skeleton3D = null
var fp_agent_instance: Node3D = null
var fp_skeleton: Skeleton3D = null
var simulator: PhysicalBoneSimulator3D = null
var physical_bones: Dictionary = {} # bone_name -> PhysicalBone3D
var is_ragdoll_active: bool = false
var is_first_person_local: bool = false
var body_visual_layer: int = 1
var _walk_cycle_phase: float = 0.0
var _last_horiz_speed: float = 0.0
var _last_head_pitch_rad: float = 0.0
var _move_blend: float = 0.0
var _crouch_blend: float = 0.0
var _sprint_blend: float = 0.0
var _climb_blend: float = 0.0
var _climb_phase: float = 0.0
var _climb_move_blend: float = 0.0
var _is_charging_club_pose: bool = false
var _tp_left_item_id: String = "NONE"
var _tp_right_item_id: String = "NONE"
var _pelvis_sync_target: Vector3 = Vector3.ZERO
var _has_pelvis_sync_target: bool = false
var _head_eye_bone_local: Transform3D = Transform3D.IDENTITY
var _pending_impulse: Vector3 = Vector3.ZERO
var _pending_reason: String = ""
var _pending_impulse_frames: int = 0
var _bucket_head_mount: Node3D = null
var _bucket_on_head_active: bool = false
var _fp_body_mesh_inst: MeshInstance3D = null
var _fp_hide_left_arm: bool = false
var _fp_hide_right_arm: bool = false
var _fp_applied_mask_key: String = ""

static var _cached_arm_meshes: Dictionary = {}
static var _cached_role_materials: Dictionary = {}


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
		_ensure_fp_body_copy(role)
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
	if fp_agent_instance != null and is_instance_valid(fp_agent_instance):
		remove_child(fp_agent_instance)
		fp_agent_instance.queue_free()
		fp_agent_instance = null
		fp_skeleton = null
		_fp_body_mesh_inst = null
		_fp_applied_mask_key = ""

	var packed: PackedScene = AGENT_GREEN_SCENE
	match role:
		1:
			packed = AGENT_GREEN_SCENE
		2:
			packed = AGENT_PURPLE_SCENE
		3:
			packed = AGENT_BLUE_SCENE
		4:
			packed = AGENT_RED_SCENE
		_:
			packed = AGENT_GREEN_SCENE
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
	_ensure_fp_body_copy(role)
	_apply_first_person_visibility_mode()
	_sync_owner_camera_cull_mask()


func _get_packed_scene_for_role(role: int) -> PackedScene:
	match role:
		1:
			return AGENT_GREEN_SCENE
		2:
			return AGENT_PURPLE_SCENE
		3:
			return AGENT_BLUE_SCENE
		4:
			return AGENT_RED_SCENE
		_:
			return AGENT_GREEN_SCENE


func _ensure_fp_body_copy(role: int) -> void:
	if not is_first_person_local:
		if fp_agent_instance != null and is_instance_valid(fp_agent_instance):
			remove_child(fp_agent_instance)
			fp_agent_instance.queue_free()
			fp_agent_instance = null
			fp_skeleton = null
		return
	if fp_agent_instance != null and is_instance_valid(fp_agent_instance):
		return
	var packed: PackedScene = _get_packed_scene_for_role(role)
	if packed == null:
		return
	fp_agent_instance = packed.instantiate() as Node3D
	fp_agent_instance.name = "FirstPersonBody"
	fp_agent_instance.rotation.y = PI
	fp_agent_instance.position = Vector3(0.0, 0.0, FP_BODY_PUSH_BACK_Z)
	add_child(fp_agent_instance)

	fp_skeleton = fp_agent_instance.get_node_or_null("metarig/Skeleton3D") as Skeleton3D
	if fp_skeleton != null:
		var fp_layer: int = GameConfig.VISUAL_LAYER_LOCAL_FP_BODY if GameConfig != null else (1 << 14)
		for child in fp_skeleton.get_children():
			if child is MeshInstance3D:
				var m: MeshInstance3D = child as MeshInstance3D
				if m.name == "Body":
					_fp_body_mesh_inst = m
					_fp_applied_mask_key = "BODY_BOTH"
					m.visible = true
					m.layers = fp_layer
					m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					m.extra_cull_margin = 16384.0
				else:
					m.visible = false
					m.layers = fp_layer
		_ensure_fp_body_arm_variants_cached()
		_sync_fp_body_arm_visibility()
		_reset_and_fold_idle_on_skeleton(fp_skeleton, 0.0, 0.0)


func set_fp_body_visible(visible_now: bool) -> void:
	if fp_agent_instance != null and is_instance_valid(fp_agent_instance):
		fp_agent_instance.visible = visible_now and not is_ragdoll_active


func set_fp_body_arm_occupancy(hide_left: bool, hide_right: bool) -> void:
	_fp_hide_left_arm = hide_left
	_fp_hide_right_arm = hide_right
	_sync_fp_body_arm_visibility()


static func get_camera_arm_mesh(is_left: bool) -> ArrayMesh:
	_ensure_arm_meshes_cached_static()
	return _cached_arm_meshes.get("LEFT_CAMERA_ARM" if is_left else "RIGHT_CAMERA_ARM", null) as ArrayMesh


static func get_body_material_for_role(role: int) -> Material:
	if _cached_role_materials.has(role):
		return _cached_role_materials[role] as Material
	var packed: PackedScene = AGENT_GREEN_SCENE
	match role:
		1:
			packed = AGENT_GREEN_SCENE
		2:
			packed = AGENT_PURPLE_SCENE
		3:
			packed = AGENT_BLUE_SCENE
		4:
			packed = AGENT_RED_SCENE
	var mat: Material = null
	if packed != null:
		var inst: Node = packed.instantiate()
		var body_mi: MeshInstance3D = _find_body_mesh_recursive(inst)
		if body_mi != null:
			mat = body_mi.material_override
			if mat == null and body_mi.mesh != null and body_mi.mesh.get_surface_count() > 0:
				mat = body_mi.mesh.surface_get_material(0)
		inst.free()
	_cached_role_materials[role] = mat
	return mat


static func _find_skeleton_recursive(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r: Skeleton3D = _find_skeleton_recursive(c)
		if r != null:
			return r
	return null


static func _find_body_mesh_recursive(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.name == "Body":
		return n as MeshInstance3D
	for c in n.get_children():
		var r: MeshInstance3D = _find_body_mesh_recursive(c)
		if r != null:
			return r
	return null


func _ensure_fp_body_arm_variants_cached() -> void:
	_ensure_arm_meshes_cached_static()


static func _ensure_arm_meshes_cached_static() -> void:
	if _cached_arm_meshes.has("BODY_BOTH"):
		return
	if AGENT_GREEN_SCENE == null:
		return
	var inst: Node = AGENT_GREEN_SCENE.instantiate()
	var skel: Skeleton3D = _find_skeleton_recursive(inst)
	var body_mi: MeshInstance3D = _find_body_mesh_recursive(inst)
	if skel == null or body_mi == null or not (body_mi.mesh is ArrayMesh):
		inst.free()
		return
	var base_mesh: ArrayMesh = body_mi.mesh as ArrayMesh
	_cached_arm_meshes["BODY_BOTH"] = base_mesh
	if not _cached_role_materials.has(1):
		_cached_role_materials[1] = body_mi.material_override if body_mi.material_override != null else base_mesh.surface_get_material(0)

	var left_bones: Dictionary = _collect_side_arm_bone_indices(skel, true)
	var right_bones: Dictionary = _collect_side_arm_bone_indices(skel, false)

	var mdt := MeshDataTool.new()
	if mdt.create_from_surface(base_mesh, 0) != OK:
		inst.free()
		return
	var surf_mat: Material = base_mesh.surface_get_material(0)

	_cached_arm_meshes["BODY_NO_LEFT"] = _build_filtered_mesh(mdt, surf_mat, left_bones, {}, false, Transform3D.IDENTITY)
	_cached_arm_meshes["BODY_NO_RIGHT"] = _build_filtered_mesh(mdt, surf_mat, {}, right_bones, false, Transform3D.IDENTITY)
	_cached_arm_meshes["BODY_NO_ARMS"] = _build_filtered_mesh(mdt, surf_mat, left_bones, right_bones, false, Transform3D.IDENTITY)

	# Build unstretched default camera-view arm meshes anchored at each palm center
	var l_hand_idx: int = skel.find_bone("hand.L")
	var r_hand_idx: int = skel.find_bone("hand.R")
	var l_wrist: Vector3 = skel.get_bone_global_rest(l_hand_idx).origin if l_hand_idx != -1 else Vector3(0.755, 1.269, -0.044)
	var r_wrist: Vector3 = skel.get_bone_global_rest(r_hand_idx).origin if r_hand_idx != -1 else Vector3(-0.749, 1.269, -0.044)
	var l_palm: Vector3 = l_wrist + Vector3(0.20, -0.02, 0.01)
	var r_palm: Vector3 = r_wrist + Vector3(-0.20, -0.02, 0.01)

	# Rest pose: +X/-X = arm->fingers, -Y = palm, +Z = thumb.
	# Roll -95 deg around +X so thumb points +Y and palm faces +Z, then turn +/-90 deg around +Y toward camera forward (-Z),
	# plus slight inward/upward framing tilt in camera space.
	var arm_roll := Basis(Vector3.RIGHT, deg_to_rad(-95.0))
	var l_basis: Basis = Basis.from_euler(Vector3(deg_to_rad(8.0), deg_to_rad(-14.0), 0.0)) * Basis(Vector3.UP, PI * 0.5) * arm_roll
	var r_basis: Basis = Basis.from_euler(Vector3(deg_to_rad(8.0), deg_to_rad(14.0), 0.0)) * Basis(Vector3.UP, -PI * 0.5) * arm_roll
	var l_xf := Transform3D(l_basis, -(l_basis * l_palm))
	var r_xf := Transform3D(r_basis, -(r_basis * r_palm))

	_cached_arm_meshes["LEFT_CAMERA_ARM"] = _build_filtered_mesh(mdt, surf_mat, left_bones, {}, true, l_xf)
	_cached_arm_meshes["RIGHT_CAMERA_ARM"] = _build_filtered_mesh(mdt, surf_mat, right_bones, {}, true, r_xf)
	inst.free()


static func _collect_side_arm_bone_indices(skel: Skeleton3D, is_left: bool) -> Dictionary:
	var suffix: String = ".L" if is_left else ".R"
	var bones: Dictionary = {}
	for i in range(skel.get_bone_count()):
		var bn: String = skel.get_bone_name(i)
		if not bn.ends_with(suffix):
			continue
		if bn.begins_with("thigh") or bn.begins_with("shin") or bn.begins_with("foot") or bn.begins_with("toe") or bn.begins_with("pelvis") or bn.begins_with("shoulder"):
			continue
		bones[i] = true
	return bones


static func _build_filtered_mesh(
	mdt: MeshDataTool,
	surf_mat: Material,
	arm_set_a: Dictionary,
	arm_set_b: Dictionary,
	keep_matching_only: bool,
	static_bake_xform: Transform3D
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v_count: int = mdt.get_vertex_count()
	var vert_in_set := PackedByteArray()
	vert_in_set.resize(v_count)
	for vi in range(v_count):
		var bones: PackedInt32Array = mdt.get_vertex_bones(vi)
		var weights: PackedFloat32Array = mdt.get_vertex_weights(vi)
		var w_a: float = 0.0
		var w_b: float = 0.0
		for j in range(bones.size()):
			var bi: int = bones[j]
			if arm_set_a.has(bi):
				w_a += weights[j]
			if arm_set_b.has(bi):
				w_b += weights[j]
		vert_in_set[vi] = 1 if (w_a > 0.5 or w_b > 0.5) else 0

	var rot_basis: Basis = static_bake_xform.basis.orthonormalized()
	var is_static_bake: bool = keep_matching_only
	for fi in range(mdt.get_face_count()):
		var hits: int = 0
		for k in range(3):
			if vert_in_set[mdt.get_face_vertex(fi, k)] == 1:
				hits += 1
		var include_tri: bool = (hits >= 1) if keep_matching_only else (hits == 0)
		if not include_tri:
			continue
		for k in range(3):
			var vi: int = mdt.get_face_vertex(fi, k)
			var pos: Vector3 = mdt.get_vertex(vi)
			var nrm: Vector3 = mdt.get_vertex_normal(vi)
			var tan: Plane = mdt.get_vertex_tangent(vi)
			if is_static_bake:
				pos = static_bake_xform * pos
				nrm = (rot_basis * nrm).normalized()
				var tan_vec: Vector3 = (rot_basis * tan.normal).normalized()
				tan = Plane(tan_vec, tan.d)
			else:
				st.set_bones(mdt.get_vertex_bones(vi))
				st.set_weights(mdt.get_vertex_weights(vi))
			st.set_normal(nrm)
			st.set_tangent(tan)
			st.set_uv(mdt.get_vertex_uv(vi))
			st.add_vertex(pos)

	st.index()
	var out_mesh: ArrayMesh = st.commit()
	if out_mesh != null and surf_mat != null and out_mesh.get_surface_count() > 0:
		out_mesh.surface_set_material(0, surf_mat)
	return out_mesh


func _sync_fp_body_arm_visibility() -> void:
	if _fp_body_mesh_inst == null or not is_instance_valid(_fp_body_mesh_inst):
		return
	var key: String = "BODY_BOTH"
	if _fp_hide_left_arm and _fp_hide_right_arm:
		key = "BODY_NO_ARMS"
	elif _fp_hide_left_arm:
		key = "BODY_NO_LEFT"
	elif _fp_hide_right_arm:
		key = "BODY_NO_RIGHT"
	if key == _fp_applied_mask_key:
		return
	_ensure_fp_body_arm_variants_cached()
	var target_mesh: ArrayMesh = _cached_arm_meshes.get(key, null) as ArrayMesh
	if target_mesh != null:
		_fp_body_mesh_inst.mesh = target_mesh
		_fp_applied_mask_key = key


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
	_ensure_fp_body_copy(current_role)
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
	# so local FPS camera never clips its own body/head while rival CRT Trap-Cams can still render this spy.
	for child in skeleton.get_children():
		if child is MeshInstance3D and child.name != "SkeletonKeepAlive":
			var m: MeshInstance3D = child as MeshInstance3D
			var hide_for_bucket: bool = _bucket_on_head_active and (m.name == "Head" or m.name == "Eyes")
			m.visible = not hide_for_bucket
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
		_set_visual_layer_recursive(_bucket_head_mount, 1)


func _set_visual_layer_recursive(node: Node, layer_mask: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer_mask
	for child in node.get_children():
		_set_visual_layer_recursive(child, layer_mask)


func set_bucket_on_head(active: bool) -> void:
	_bucket_on_head_active = active
	if active:
		_ensure_bucket_head_mount()
	if _bucket_head_mount != null and is_instance_valid(_bucket_head_mount):
		_bucket_head_mount.visible = active
	_apply_first_person_visibility_mode()


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
	_bucket_head_mount = head_anchor.get_node_or_null("BucketHeadMount") as Node3D
	if _bucket_head_mount == null:
		const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
		_bucket_head_mount = PICKUP_SCRIPT.build_item_visual("BUCKET")
		_bucket_head_mount.name = "BucketHeadMount"
		var water_node: Node = _bucket_head_mount.find_child("Water", true, false)
		if water_node != null:
			if water_node.get_parent() != null:
				water_node.get_parent().remove_child(water_node)
			water_node.queue_free()
		var spand: MeshInstance3D = _bucket_head_mount.find_child("Spand", true, false) as MeshInstance3D
		if spand != null:
			spand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if spand.material_override is BaseMaterial3D:
				var mat: BaseMaterial3D = (spand.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				spand.material_override = mat
		_bucket_head_mount.scale = Vector3.ONE
		_bucket_head_mount.position = Vector3(0.0, 0.0, 0.0)
		_bucket_head_mount.rotation = Vector3(0.0, 0.0, PI)
		_set_visual_layer_recursive(_bucket_head_mount, 1)
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
		set_fp_body_visible(false)
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
	set_fp_body_visible(true)
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


func get_bone_world_transform(bone_name: String) -> Transform3D:
	if is_ragdoll_active:
		var pb: PhysicalBone3D = physical_bones.get(bone_name) as PhysicalBone3D
		if pb != null and pb.is_inside_tree():
			return pb.global_transform
	if skeleton != null and skeleton.is_inside_tree():
		var idx: int = skeleton.find_bone(bone_name)
		if idx != -1:
			return skeleton.global_transform * skeleton.get_bone_global_pose(idx)
	return global_transform if is_inside_tree() else transform


func compute_bone_local_offset(bone_name: String, ctrl_local_transform: Transform3D) -> Transform3D:
	if skeleton == null:
		return Transform3D.IDENTITY
	var idx: int = skeleton.find_bone(bone_name)
	if idx == -1:
		return Transform3D.IDENTITY
	var rot_pi := Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3.ZERO)
	var bone_in_ctrl: Transform3D = rot_pi * skeleton.get_bone_global_rest(idx)
	return bone_in_ctrl.affine_inverse() * ctrl_local_transform


func trigger_right_hand_action(_action_type: String) -> void:
	pass


func get_head_camera_world_transform() -> Transform3D:
	if is_ragdoll_active:
		var head_pb: PhysicalBone3D = physical_bones.get("spine.006") as PhysicalBone3D
		if head_pb != null and head_pb.is_inside_tree():
			return head_pb.global_transform * _head_eye_bone_local
	# While alive in local first-person, stabilize camera height/pitch by stance so 3rd-person lean/bob never shakes the camera
	if is_first_person_local:
		var stand_y: float = GameConfig.standing_neck_y if GameConfig != null else 1.6
		var crouch_y: float = GameConfig.crouched_neck_y if GameConfig != null else 0.85
		var eye_y: float = lerpf(stand_y, crouch_y, _crouch_blend)
		var walk_bob: float = absf(sin(_walk_cycle_phase)) * 0.014 * _move_blend * (1.0 + _sprint_blend * 0.45) * (1.0 - _crouch_blend * 0.6)
		var climb_bob_y: float = absf(sin(_climb_phase)) * 0.022 * _climb_move_blend
		var climb_bob_x: float = cos(_climb_phase) * 0.012 * _climb_move_blend
		var step_bob: float = lerpf(walk_bob, climb_bob_y, _climb_blend)
		var clamped_p: float = clampf(_last_head_pitch_rad, deg_to_rad(-89.0), deg_to_rad(89.0))
		var look_down_fwd_z: float = -sin(maxf(-clamped_p, 0.0)) * 0.10
		var eye_local := Transform3D(Basis.from_euler(Vector3(clamped_p, 0.0, 0.0)), Vector3(climb_bob_x * _climb_blend, eye_y + step_bob, look_down_fwd_z))
		return (global_transform * eye_local) if is_inside_tree() else eye_local
	if skeleton != null and skeleton.is_inside_tree():
		var head_idx: int = skeleton.find_bone("spine.006")
		if head_idx != -1:
			var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_idx)
			return head_world * _head_eye_bone_local
	return global_transform if is_inside_tree() else transform


func update_locomotion_pose(
	delta: float,
	horiz_speed: float,
	is_crouching: bool,
	head_pitch_rad: float,
	is_charging_club: bool,
	left_item_id: String = "NONE",
	right_item_id: String = "NONE",
	is_climbing: bool = false,
	climb_vertical_speed: float = 0.0
) -> void:
	if is_ragdoll_active or skeleton == null:
		return
	_fp_hide_left_arm = (left_item_id != "NONE" and left_item_id != "")
	_fp_hide_right_arm = (right_item_id != "NONE" and right_item_id != "")
	_tp_left_item_id = left_item_id
	_tp_right_item_id = right_item_id
	_sync_fp_body_arm_visibility()
	var target_crouch: float = 1.0 if (is_crouching and not is_climbing) else 0.0
	var lerp_spd: float = GameConfig.stance_transition_speed if GameConfig != null else 12.0
	_crouch_blend = lerpf(_crouch_blend, target_crouch, clampf(lerp_spd * delta, 0.0, 1.0))

	var target_climb: float = 1.0 if is_climbing else 0.0
	_climb_blend = lerpf(_climb_blend, target_climb, clampf(14.0 * delta, 0.0, 1.0))
	var climb_abs: float = absf(climb_vertical_speed)
	_climb_move_blend = lerpf(_climb_move_blend, clampf(climb_abs / 2.4, 0.0, 1.0) if is_climbing else 0.0, clampf(14.0 * delta, 0.0, 1.0))
	if is_climbing and climb_abs > 0.12:
		_climb_phase = wrapf(_climb_phase + delta * climb_vertical_speed * 3.6, 0.0, TAU)

	var walk_ref: float = GameConfig.walk_speed if GameConfig != null else 4.5
	var target_sprint: float = 1.0 if (not is_crouching and not is_climbing and horiz_speed > walk_ref + 0.65) else 0.0
	_sprint_blend = lerpf(_sprint_blend, target_sprint, clampf(10.0 * delta, 0.0, 1.0))
	_move_blend = lerpf(_move_blend, 0.0 if is_climbing else clampf(horiz_speed / maxf(walk_ref, 1.0), 0.0, 1.0), clampf(12.0 * delta, 0.0, 1.0))

	if horiz_speed > 0.25:
		var cadence: float = lerpf(2.25, 2.50, _sprint_blend)
		_walk_cycle_phase = fmod(_walk_cycle_phase + delta * horiz_speed * cadence, TAU)
	else:
		_walk_cycle_phase = move_toward(_walk_cycle_phase, 0.0, delta * 8.0)
	_last_horiz_speed = horiz_speed
	_last_head_pitch_rad = head_pitch_rad
	_is_charging_club_pose = is_charging_club

	refresh_head_pitch_pose(head_pitch_rad)


func refresh_head_pitch_pose(head_pitch_rad: float) -> void:
	if is_ragdoll_active or skeleton == null:
		return
	_last_head_pitch_rad = head_pitch_rad
	_apply_pose_to_skeleton(skeleton, head_pitch_rad, false)
	if fp_agent_instance != null and is_instance_valid(fp_agent_instance):
		fp_agent_instance.position.z = FP_BODY_PUSH_BACK_Z + _crouch_blend * FP_BODY_CROUCH_EXTRA_Z + _sprint_blend * FP_BODY_SPRINT_EXTRA_Z + _climb_blend * 0.04
		var xz_scale: float = lerpf(1.0, 0.82, _crouch_blend)
		var y_scale: float = lerpf(1.0, 0.58, _crouch_blend)
		fp_agent_instance.scale = Vector3(xz_scale, y_scale, xz_scale)
	if fp_skeleton != null:
		_apply_pose_to_skeleton(fp_skeleton, 0.0, true)


func _apply_pose_to_skeleton(skel: Skeleton3D, head_pitch_rad: float, is_fp_copy: bool) -> void:
	if skel == null:
		return
	skel.reset_bone_poses()

	var base_crouch_drop: float = 0.26 if is_fp_copy else 0.28
	var step_bounce: float = absf(cos(_walk_cycle_phase)) * 0.025 * _move_blend * (1.0 + _sprint_blend * 0.6) * (1.0 - _crouch_blend * 0.5)
	var crouch_drop: float = base_crouch_drop * _crouch_blend

	var spine_idx: int = skel.find_bone("spine")
	if spine_idx != -1 and (crouch_drop > 0.001 or step_bounce > 0.0005):
		var rest_t: Transform3D = skel.get_bone_rest(spine_idx)
		rest_t.origin.y = rest_t.origin.y - crouch_drop + (0.0 if is_fp_copy else step_bounce)
		skel.set_bone_pose_position(spine_idx, rest_t.origin)

	# Spine forward lean (3rd-person only; keep FirstPersonBody upright so it never leans into the camera)
	var stride_amp: float = lerpf(0.46, 0.78, _sprint_blend) * lerpf(1.0, 0.68, _crouch_blend) * _move_blend
	var s: float = sin(_walk_cycle_phase) * stride_amp
	var climb_s: float = sin(_climb_phase)
	var lean_rad: float = 0.0 if is_fp_copy else lerpf(0.16 * _sprint_blend + 0.24 * _crouch_blend, 0.08, _climb_blend)
	var twist_rad: float = lerpf(-s * (0.04 if is_fp_copy else 0.16), -climb_s * (0.04 if is_fp_copy else 0.14), _climb_blend)
	_rotate_bone_multi_on_skeleton(skel, "spine.001", lean_rad * 0.45, twist_rad * 0.4)
	_rotate_bone_multi_on_skeleton(skel, "spine.002", lean_rad * 0.55, twist_rad * 0.6)

	# Legs: bent crouch base + walk/sprint stride + knee bend + ankle roll, blended cleanly into ladder rung steps
	var crouch_thigh: float = (-0.88 if is_fp_copy else -1.02) * _crouch_blend
	var crouch_shin: float = (1.48 if is_fp_copy else 1.65) * _crouch_blend
	var crouch_foot: float = (-0.60 if is_fp_copy else -0.63) * _crouch_blend
	var sprint_hip_bias: float = -0.08 * _sprint_blend
	var knee_scale: float = lerpf(0.85, 1.15, _sprint_blend)

	var l_thigh: float = crouch_thigh + sprint_hip_bias + s
	var r_thigh: float = crouch_thigh + sprint_hip_bias - s
	var l_shin: float = crouch_shin + maxf(0.0, -s * knee_scale)
	var r_shin: float = crouch_shin + maxf(0.0, s * knee_scale)
	var l_foot: float = crouch_foot - s * 0.28
	var r_foot: float = crouch_foot + s * 0.28

	if _climb_blend > 0.001:
		var l_step: float = 0.5 + 0.5 * climb_s
		var r_step: float = 0.5 - 0.5 * climb_s
		var max_thigh: float = -0.78 if is_fp_copy else -1.02
		var min_thigh: float = -0.18 if is_fp_copy else -0.22
		var max_shin: float = 1.24 if is_fp_copy else 1.52
		var min_shin: float = 0.32 if is_fp_copy else 0.36
		l_thigh = lerpf(l_thigh, lerpf(min_thigh, max_thigh, l_step), _climb_blend)
		r_thigh = lerpf(r_thigh, lerpf(min_thigh, max_thigh, r_step), _climb_blend)
		l_shin = lerpf(l_shin, lerpf(min_shin, max_shin, l_step), _climb_blend)
		r_shin = lerpf(r_shin, lerpf(min_shin, max_shin, r_step), _climb_blend)
		l_foot = lerpf(l_foot, lerpf(-0.14, -0.48, l_step), _climb_blend)
		r_foot = lerpf(r_foot, lerpf(-0.14, -0.48, r_step), _climb_blend)

	_rotate_bone_on_skeleton(skel, "thigh.L", Vector3.RIGHT, l_thigh)
	_rotate_bone_on_skeleton(skel, "thigh.R", Vector3.RIGHT, r_thigh)
	_rotate_bone_on_skeleton(skel, "shin.L", Vector3.RIGHT, l_shin)
	_rotate_bone_on_skeleton(skel, "shin.R", Vector3.RIGHT, r_shin)
	_rotate_bone_on_skeleton(skel, "foot.L", Vector3.RIGHT, l_foot)
	_rotate_bone_on_skeleton(skel, "foot.R", Vector3.RIGHT, r_foot)

	# Arms: fold from T-pose and swing naturally with walk/sprint/crouch, or alternate reaching rungs when climbing.
	# Bulky side-carried items (BRIEFCASE/BUCKET) get slight outward clearance and gentler swing so they don't clip the coat.
	var l_has_item: bool = (_tp_left_item_id != "NONE" and _tp_left_item_id != "")
	var r_has_item: bool = (_tp_right_item_id != "NONE" and _tp_right_item_id != "")
	var l_bulky: bool = not is_fp_copy and (_tp_left_item_id == "BRIEFCASE" or _tp_left_item_id == "BUCKET")
	var r_bulky: bool = not is_fp_copy and (_tp_right_item_id == "BRIEFCASE" or _tp_right_item_id == "BUCKET")
	var arm_amp: float = lerpf(0.42, 0.90, _sprint_blend) * lerpf(1.0, 0.55, _crouch_blend) * (0.45 if is_fp_copy else 1.0)
	var l_arm_pitch: float = -s * arm_amp * (0.55 if l_bulky else 1.0)
	var r_arm_pitch: float = s * arm_amp * (0.55 if r_bulky else 1.0)
	var base_fore_bend: float = lerpf(-0.24, -0.42 if is_fp_copy else -0.95, _sprint_blend)
	var l_fore_bend: float = (lerpf(-0.10, -0.35, _sprint_blend) if l_bulky else base_fore_bend) - maxf(0.0, -l_arm_pitch) * 0.35
	var r_fore_bend: float = (lerpf(-0.10, -0.35, _sprint_blend) if r_bulky else base_fore_bend) - maxf(0.0, -r_arm_pitch) * 0.35

	var l_fold: float = -1.04 if l_bulky else -1.18
	var r_fold: float = 1.04 if r_bulky else 1.18

	if _climb_blend > 0.001:
		# Cross-crawl: right arm reaches high as left knee lifts, and vice versa
		var l_reach: float = 0.5 - 0.5 * climb_s
		var r_reach: float = 0.5 + 0.5 * climb_s
		if is_fp_copy:
			l_arm_pitch = lerpf(l_arm_pitch, lerpf(-0.35, -1.08, l_reach), _climb_blend)
			r_arm_pitch = lerpf(r_arm_pitch, lerpf(-0.35, -1.08, r_reach), _climb_blend)
			l_fore_bend = lerpf(l_fore_bend, lerpf(-0.92, -0.42, l_reach), _climb_blend)
			r_fore_bend = lerpf(r_fore_bend, lerpf(-0.92, -0.42, r_reach), _climb_blend)
			l_fold = lerpf(l_fold, -1.02, _climb_blend)
			r_fold = lerpf(r_fold, 1.02, _climb_blend)
		else:
			var l_climb_pitch: float = lerpf(-0.30, -0.78, l_reach) if l_has_item else lerpf(-1.05, -2.05, l_reach)
			var r_climb_pitch: float = lerpf(-0.30, -0.78, r_reach) if r_has_item else lerpf(-1.05, -2.05, r_reach)
			var l_climb_fore: float = -0.62 if l_has_item else lerpf(-1.18, -0.45, l_reach)
			var r_climb_fore: float = -0.62 if r_has_item else lerpf(-1.18, -0.45, r_reach)
			l_arm_pitch = lerpf(l_arm_pitch, l_climb_pitch, _climb_blend)
			r_arm_pitch = lerpf(r_arm_pitch, r_climb_pitch, _climb_blend)
			l_fore_bend = lerpf(l_fore_bend, l_climb_fore, _climb_blend)
			r_fore_bend = lerpf(r_fore_bend, r_climb_fore, _climb_blend)
			l_fold = lerpf(l_fold, -1.04 if l_has_item else -1.10, _climb_blend)
			r_fold = lerpf(r_fold, 1.04 if r_has_item else 1.10, _climb_blend)

	_pose_folded_arm_on_skeleton(skel, true, l_fold, l_arm_pitch, 0.04)
	_rotate_bone_on_skeleton(skel, "forearm.L", Vector3.RIGHT, l_fore_bend)

	if _is_charging_club_pose and not is_fp_copy and _climb_blend < 0.25:
		_pose_folded_arm_on_skeleton(skel, false, 1.05, -1.15, -0.10)
		_rotate_bone_on_skeleton(skel, "forearm.R", Vector3.RIGHT, -0.85)
	else:
		_pose_folded_arm_on_skeleton(skel, false, r_fold, r_arm_pitch, -0.04)
		_rotate_bone_on_skeleton(skel, "forearm.R", Vector3.RIGHT, r_fore_bend)

	# Head pitch on 3rd-person skeleton (compensating for spine forward lean)
	if not is_fp_copy:
		var comp_pitch: float = clampf(head_pitch_rad, deg_to_rad(-89.0), deg_to_rad(89.0)) + lean_rad
		_rotate_bone_on_skeleton(skel, "spine.006", Vector3.RIGHT, -comp_pitch)


func _pose_folded_arm_on_skeleton(skel: Skeleton3D, is_left: bool, fold_z: float, pitch_x: float, spread_y: float) -> void:
	var b_name: String = "upper_arm.L" if is_left else "upper_arm.R"
	var q_model: Quaternion = Quaternion(Vector3.UP, spread_y) * Quaternion(Vector3.RIGHT, pitch_x) * Quaternion(Vector3(0.0, 0.0, 1.0), fold_z)
	_apply_model_quat_on_skeleton(skel, b_name, q_model)


func _rotate_bone_multi_on_skeleton(skel: Skeleton3D, bone_name: String, pitch_x: float, yaw_y: float) -> void:
	var q_model: Quaternion = Quaternion(Vector3.UP, yaw_y) * Quaternion(Vector3.RIGHT, pitch_x)
	_apply_model_quat_on_skeleton(skel, bone_name, q_model)


func _apply_model_quat_on_skeleton(skel: Skeleton3D, bone_name: String, q_model: Quaternion) -> void:
	if skel == null:
		return
	var idx: int = skel.find_bone(bone_name)
	if idx == -1:
		return
	var g_rest: Basis = skel.get_bone_global_rest(idx).basis.orthonormalized()
	var q_local: Quaternion = g_rest.get_rotation_quaternion().inverse() * q_model * g_rest.get_rotation_quaternion()
	var rest_rot: Quaternion = skel.get_bone_rest(idx).basis.get_rotation_quaternion()
	skel.set_bone_pose_rotation(idx, rest_rot * q_local)


func _apply_idle_standing_pose(head_pitch_rad: float, crouch_ratio: float) -> void:
	_reset_and_fold_idle_on_skeleton(skeleton, head_pitch_rad, crouch_ratio)


func _reset_and_fold_idle_on_skeleton(skel: Skeleton3D, head_pitch_rad: float, crouch_ratio: float) -> void:
	if skel == null:
		return
	skel.reset_bone_poses()
	# Fold arms down from T-pose toward the spy's trenchcoat sides in model space
	_rotate_bone_on_skeleton(skel, "upper_arm.L", Vector3(0.0, 0.0, 1.0), -1.18)
	_rotate_bone_on_skeleton(skel, "upper_arm.R", Vector3(0.0, 0.0, 1.0), 1.18)
	_rotate_bone_on_skeleton(skel, "forearm.L", Vector3.RIGHT, -0.22)
	_rotate_bone_on_skeleton(skel, "forearm.R", Vector3.RIGHT, -0.22)

	if crouch_ratio > 0.001:
		var stand_y: float = GameConfig.standing_neck_y if GameConfig != null else 1.6
		var crouch_y: float = GameConfig.crouched_neck_y if GameConfig != null else 0.85
		var drop_y: float = (stand_y - crouch_y) * crouch_ratio
		var spine_idx: int = skel.find_bone("spine")
		if spine_idx != -1:
			var rest_t: Transform3D = skel.get_bone_rest(spine_idx)
			rest_t.origin.y -= drop_y
			skel.set_bone_pose_position(spine_idx, rest_t.origin)

	# Apply head pitch directly to spine.006 so the permanent head-bone camera pitches with mouse look
	_rotate_bone_on_skeleton(skel, "spine.006", Vector3.RIGHT, -clampf(head_pitch_rad, deg_to_rad(-89.0), deg_to_rad(89.0)))


func _rotate_bone_in_model_space(bone_name: String, model_axis: Vector3, angle_rad: float) -> void:
	_rotate_bone_on_skeleton(skeleton, bone_name, model_axis, angle_rad)


func _rotate_bone_on_skeleton(skel: Skeleton3D, bone_name: String, model_axis: Vector3, angle_rad: float) -> void:
	if skel == null:
		return
	var idx: int = skel.find_bone(bone_name)
	if idx == -1:
		return
	var g_rest: Basis = skel.get_bone_global_rest(idx).basis.orthonormalized()
	var local_axis: Vector3 = (g_rest.inverse() * model_axis).normalized()
	var rest_rot: Quaternion = skel.get_bone_rest(idx).basis.get_rotation_quaternion()
	skel.set_bone_pose_rotation(idx, rest_rot * Quaternion(local_axis, angle_rad))
