@tool
class_name BriefcaseVisualBuilder
extends RefCounted

## Builds the unified 3D Hinged Attaché Briefcase mesh rig used by floor Briefcase pickups/containers.
## Keeps closed and open visuals in a single rig (eliminating overlapping closed-box / open-tray clipping).

const CASE_WIDTH: float = 0.56
const CASE_DEPTH: float = 0.38
const BASE_HEIGHT: float = 0.085
const LID_HEIGHT: float = 0.042
const WALL_THICK: float = 0.022
const OPEN_LID_ANGLE_DEG: float = -118.0

## 4 neat interior compartment centers (in TrayPivot local XZ) for KEY, MONEY, PASSPORT, PLANS
const BRIEFCASE_SLOT_OFFSETS: Array[Vector2] = [
	Vector2(-0.135, -0.070),
	Vector2(0.135, -0.070),
	Vector2(-0.135, 0.068),
	Vector2(0.135, 0.068)
]


static func build_briefcase_rig(parent: Node3D) -> Dictionary:
	var rig_root := Node3D.new()
	rig_root.name = "BriefcaseVisualRig"
	parent.add_child(rig_root)

	var leather_mat := StandardMaterial3D.new()
	leather_mat.albedo_color = Color(0.36, 0.20, 0.10)
	leather_mat.roughness = 0.72

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.24, 0.13, 0.07)
	trim_mat.roughness = 0.68

	var felt_mat := StandardMaterial3D.new()
	felt_mat.albedo_color = Color(0.16, 0.22, 0.19)
	felt_mat.roughness = 0.92

	var divider_mat := StandardMaterial3D.new()
	divider_mat.albedo_color = Color(0.28, 0.16, 0.09)
	divider_mat.roughness = 0.80

	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color(0.88, 0.74, 0.28)
	brass_mat.metallic = 0.72
	brass_mat.roughness = 0.28

	# Base bottom floor (y = -0.075 to -0.059 in TrayPivot space -> rests flush on world y = 0 when TrayPivot.y = 0.075)
	var floor_mi := _make_box(Vector3(CASE_WIDTH, 0.016, CASE_DEPTH), leather_mat)
	floor_mi.name = "BaseFloor"
	floor_mi.position = Vector3(0.0, -0.067, 0.0)
	rig_root.add_child(floor_mi)

	# Soft dark-felt interior liner
	var liner_mi := _make_box(Vector3(CASE_WIDTH - WALL_THICK * 2.0, 0.004, CASE_DEPTH - WALL_THICK * 2.0), felt_mat)
	liner_mi.name = "FeltLiner"
	liner_mi.position = Vector3(0.0, -0.057, 0.0)
	rig_root.add_child(liner_mi)

	# Subtle cross dividers marking the 4 objective compartments inside the base
	var div_x := _make_box(Vector3(CASE_WIDTH - WALL_THICK * 2.4, 0.012, 0.010), divider_mat)
	div_x.position = Vector3(0.0, -0.050, 0.0)
	rig_root.add_child(div_x)
	var div_z := _make_box(Vector3(0.010, 0.012, CASE_DEPTH - WALL_THICK * 2.4), divider_mat)
	div_z.position = Vector3(0.0, -0.050, 0.0)
	rig_root.add_child(div_z)

	# Base walls (left, right, back, front)
	var half_w: float = CASE_WIDTH * 0.5
	var half_d: float = CASE_DEPTH * 0.5
	var wall_center_y: float = -0.075 + BASE_HEIGHT * 0.5

	for side_sign in [-1.0, 1.0]:
		var side_w := _make_box(Vector3(WALL_THICK, BASE_HEIGHT, CASE_DEPTH), leather_mat)
		side_w.position = Vector3(side_sign * (half_w - WALL_THICK * 0.5), wall_center_y, 0.0)
		rig_root.add_child(side_w)

	var back_w := _make_box(Vector3(CASE_WIDTH, BASE_HEIGHT, WALL_THICK), leather_mat)
	back_w.position = Vector3(0.0, wall_center_y, -(half_d - WALL_THICK * 0.5))
	rig_root.add_child(back_w)

	var front_w := _make_box(Vector3(CASE_WIDTH, BASE_HEIGHT, WALL_THICK), leather_mat)
	front_w.position = Vector3(0.0, wall_center_y, half_d - WALL_THICK * 0.5)
	rig_root.add_child(front_w)

	# Carrying handle on front face (+Z)
	var handle_bar := _make_box(Vector3(0.16, 0.022, 0.022), trim_mat)
	handle_bar.position = Vector3(0.0, wall_center_y + 0.004, half_d + 0.036)
	rig_root.add_child(handle_bar)
	for post_sign in [-1.0, 1.0]:
		var post := _make_box(Vector3(0.020, 0.022, 0.034), brass_mat)
		post.position = Vector3(post_sign * 0.072, wall_center_y + 0.004, half_d + 0.017)
		rig_root.add_child(post)

	# Two brass latch clasps on front face (+Z)
	for clasp_sign in [-1.0, 1.0]:
		var clasp := _make_box(Vector3(0.044, 0.030, 0.016), brass_mat)
		clasp.position = Vector3(clasp_sign * 0.165, wall_center_y + 0.030, half_d + 0.008)
		rig_root.add_child(clasp)

	# Hinged Top Lid pivoting at back edge (-Z)
	var lid_pivot := Node3D.new()
	lid_pivot.name = "BriefcaseLidPivot"
	lid_pivot.position = Vector3(0.0, -0.075 + BASE_HEIGHT, -half_d)
	rig_root.add_child(lid_pivot)

	# Lid top panel (centered at z = +half_d relative to back hinge)
	var lid_top := _make_box(Vector3(CASE_WIDTH + 0.006, 0.014, CASE_DEPTH + 0.006), leather_mat)
	lid_top.position = Vector3(0.0, LID_HEIGHT - 0.007, half_d)
	lid_pivot.add_child(lid_top)

	# Lid inner felt lining
	var lid_liner := _make_box(Vector3(CASE_WIDTH - WALL_THICK * 2.0, 0.004, CASE_DEPTH - WALL_THICK * 2.0), felt_mat)
	lid_liner.position = Vector3(0.0, LID_HEIGHT - 0.016, half_d)
	lid_pivot.add_child(lid_liner)

	# Lid skirt walls
	var skirt_h: float = LID_HEIGHT - 0.012
	var skirt_y: float = skirt_h * 0.5
	for side_sign in [-1.0, 1.0]:
		var l_side := _make_box(Vector3(WALL_THICK, skirt_h, CASE_DEPTH), leather_mat)
		l_side.position = Vector3(side_sign * (half_w - WALL_THICK * 0.5), skirt_y, half_d)
		lid_pivot.add_child(l_side)

	var l_back := _make_box(Vector3(CASE_WIDTH, skirt_h, WALL_THICK), leather_mat)
	l_back.position = Vector3(0.0, skirt_y, WALL_THICK * 0.5)
	lid_pivot.add_child(l_back)

	var l_front := _make_box(Vector3(CASE_WIDTH, skirt_h, WALL_THICK), leather_mat)
	l_front.position = Vector3(0.0, skirt_y, CASE_DEPTH - WALL_THICK * 0.5)
	lid_pivot.add_child(l_front)

	# Brass corner bumpers on top lid
	for sx in [-1.0, 1.0]:
		for sz in [0.0, 1.0]:
			var corner := _make_box(Vector3(0.048, 0.018, 0.048), brass_mat)
			corner.position = Vector3(sx * (half_w - 0.016), LID_HEIGHT - 0.006, 0.016 + sz * (CASE_DEPTH - 0.032))
			lid_pivot.add_child(corner)

	# Soft interior OmniLight3D (only turned on while opened)
	var light := OmniLight3D.new()
	light.name = "BriefcaseInteriorLight"
	light.position = Vector3(0.0, 0.50, 0.0)
	light.omni_range = 1.4
	light.light_energy = 0.85
	light.visible = false
	parent.add_child(light)

	return {
		"root": rig_root,
		"lid_pivot": lid_pivot,
		"interior_light": light
	}


static func set_lid_open_ratio(lid_pivot: Node3D, ratio: float, interior_light: OmniLight3D = null) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if lid_pivot != null and is_instance_valid(lid_pivot):
		lid_pivot.rotation.x = deg_to_rad(OPEN_LID_ANGLE_DEG * clamped)
	if interior_light != null and is_instance_valid(interior_light):
		interior_light.visible = clamped > 0.04


static func _make_box(sz: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.material_override = mat
	return mi
