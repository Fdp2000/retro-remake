class_name ClubHitGizmo
extends Node3D

## Toggleable 3D debug gizmo visualizing the club slam range, forward cone, and hit/blocked rays.

const FLASH_DURATION: float = 1.25

var _flash_mesh_inst: MeshInstance3D = null
var _flash_mesh: ImmediateMesh = null
var _flash_mat: StandardMaterial3D = null
var _flash_remaining: float = 0.0


func _ready() -> void:
	top_level = true
	_flash_mesh = ImmediateMesh.new()
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.vertex_color_use_as_albedo = true
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash_mat.no_depth_test = true

	_flash_mesh_inst = MeshInstance3D.new()
	_flash_mesh_inst.mesh = _flash_mesh
	_flash_mesh_inst.material_override = _flash_mat
	_flash_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash_mesh_inst)


func _process(delta: float) -> void:
	if _flash_remaining > 0.0:
		_flash_remaining = maxf(_flash_remaining - delta, 0.0)
		var alpha: float = clampf(_flash_remaining / FLASH_DURATION, 0.0, 1.0)
		if _flash_mat != null:
			_flash_mat.albedo_color = Color(1.0, 1.0, 1.0, alpha)
		if _flash_remaining <= 0.0 and _flash_mesh != null:
			_flash_mesh.clear_surfaces()


func show_slam_impact(
	cam_origin: Vector3,
	fwd_flat: Vector3,
	melee_range: float,
	min_dot: float,
	rays: Array[Dictionary]
) -> void:
	if _flash_mesh == null:
		return
	_flash_mesh.clear_surfaces()
	_flash_remaining = FLASH_DURATION
	if _flash_mat != null:
		_flash_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)

	var dir_fwd: Vector3 = fwd_flat.normalized() if fwd_flat.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
	var half_angle: float = acos(clampf(min_dot, -1.0, 1.0))
	var segments: int = 20

	# 1. Draw translucent cone fan at cam_origin height
	_flash_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var cone_col := Color(0.25, 0.85, 1.0, 0.28)
	for i in range(segments):
		var a0: float = lerpf(-half_angle, half_angle, float(i) / float(segments))
		var a1: float = lerpf(-half_angle, half_angle, float(i + 1) / float(segments))
		var p0: Vector3 = cam_origin + dir_fwd.rotated(Vector3.UP, a0) * melee_range
		var p1: Vector3 = cam_origin + dir_fwd.rotated(Vector3.UP, a1) * melee_range
		_flash_mesh.surface_set_color(cone_col)
		_flash_mesh.surface_add_vertex(cam_origin)
		_flash_mesh.surface_set_color(cone_col)
		_flash_mesh.surface_add_vertex(p0)
		_flash_mesh.surface_set_color(cone_col)
		_flash_mesh.surface_add_vertex(p1)
	_flash_mesh.surface_end()

	# 2. Draw cone outline + hit/miss rays
	_flash_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var edge_col := Color(0.25, 0.95, 1.0, 0.95)
	var left_edge: Vector3 = cam_origin + dir_fwd.rotated(Vector3.UP, -half_angle) * melee_range
	var right_edge: Vector3 = cam_origin + dir_fwd.rotated(Vector3.UP, half_angle) * melee_range
	_flash_mesh.surface_set_color(edge_col)
	_flash_mesh.surface_add_vertex(cam_origin)
	_flash_mesh.surface_set_color(edge_col)
	_flash_mesh.surface_add_vertex(left_edge)
	_flash_mesh.surface_set_color(edge_col)
	_flash_mesh.surface_add_vertex(cam_origin)
	_flash_mesh.surface_set_color(edge_col)
	_flash_mesh.surface_add_vertex(right_edge)

	for i in range(segments):
		var a0: float = lerpf(-half_angle, half_angle, float(i) / float(segments))
		var a1: float = lerpf(-half_angle, half_angle, float(i + 1) / float(segments))
		_flash_mesh.surface_set_color(edge_col)
		_flash_mesh.surface_add_vertex(cam_origin + dir_fwd.rotated(Vector3.UP, a0) * melee_range)
		_flash_mesh.surface_set_color(edge_col)
		_flash_mesh.surface_add_vertex(cam_origin + dir_fwd.rotated(Vector3.UP, a1) * melee_range)

	for r in rays:
		var hit: bool = bool(r.get("hit", false))
		var target_pt: Vector3 = r.get("to", cam_origin)
		var line_col: Color = Color(0.20, 1.0, 0.35, 1.0) if hit else Color(1.0, 0.25, 0.20, 1.0)
		_flash_mesh.surface_set_color(line_col)
		_flash_mesh.surface_add_vertex(cam_origin)
		_flash_mesh.surface_set_color(line_col)
		_flash_mesh.surface_add_vertex(target_pt)
	_flash_mesh.surface_end()
