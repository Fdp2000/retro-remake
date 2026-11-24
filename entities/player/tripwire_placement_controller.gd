@tool
class_name TripwirePlacementController
extends Node

## Two-Point Pole-and-Wire Tripwire Placement & Ghost Preview Controller.
## Step 1: Preview & hold LMB (0.4s) to anchor first pole on flat LAYER_ENVIRONMENT floor.
## Step 2: Preview second pole + stretched wire (0.4m..2.5m, unobstructed) & hold LMB (0.4s) to deploy.

enum Step {
	INACTIVE = 0,
	PLACING_FIRST_POLE = 1,
	PLACING_SECOND_POLE = 2
}

enum InvalidReason {
	NONE = 0,
	NO_SURFACE = 1,
	OUT_OF_REACH = 2,
	INVALID_SURFACE = 3,
	TOO_CLOSE = 4,
	TOO_FAR = 5,
	OBSTRUCTED = 6,
	TOO_CLOSE_TO_LADDER = 7
}

const PREVIEW_RAY_LENGTH: float = 8.0
const TRIPWIRE_PREFAB: PackedScene = preload("res://Assets/Prefab_Traps/tripwire.tscn")
const MAX_POLE_HEIGHT_DELTA: float = 0.65
const MIN_HORIZ_SPAN: float = 0.20
const DEFAULT_LADDER_SAFE_RADIUS: float = 1.90
const LADDER_FLOOR_HEIGHT_TOLERANCE: float = 1.20
const PEG_MODEL_HEIGHT: float = 0.1504
const PEG_RING_CENTER_RATIO: float = 0.1118 / PEG_MODEL_HEIGHT
const PEG_RING_SIDE_RADIUS_UNSCALED: float = 0.0235
const PEG_RING_TUBE_RADIUS_UNSCALED: float = 0.0056
const PEG_XZ_SCALE: float = 2.2
const PEG_SIDE_TIE_SIGN: float = 1.0

var _owner_player: Node3D = null

var current_step: int = Step.INACTIVE
var has_first_pole: bool = false
var first_pole_pos: Vector3 = Vector3.ZERO

var has_aim_hit: bool = false
var aim_pos: Vector3 = Vector3.ZERO
var aim_valid: bool = false
var invalid_reason: int = InvalidReason.NONE
var span_distance: float = 0.0

var _hold_active: bool = false
var _hold_elapsed: float = 0.0
var _require_lmb_release: bool = false

var _placed_pole_node: Node3D = null
var _ghost_pole_node: Node3D = null
var _ghost_wire_node: MeshInstance3D = null
var _mat_valid: StandardMaterial3D = null
var _mat_invalid: StandardMaterial3D = null


func setup(owner_player: Node3D) -> void:
	_owner_player = owner_player


func has_placed_first_pole() -> bool:
	return current_step == Step.PLACING_SECOND_POLE and has_first_pole


func is_holding_lmb() -> bool:
	return _hold_active


func get_hold_duration() -> float:
	return GameConfig.tripwire_pole_hold_time if GameConfig != null else 0.40


func get_hold_progress() -> float:
	return clampf(_hold_elapsed / maxf(get_hold_duration(), 0.05), 0.0, 1.0)


func begin_lmb_hold() -> bool:
	if current_step == Step.INACTIVE or _require_lmb_release or not aim_valid:
		return false
	_hold_active = true
	_hold_elapsed = 0.0
	return true


func on_lmb_released() -> void:
	_hold_active = false
	_hold_elapsed = 0.0
	_require_lmb_release = false


func cancel_lmb_hold() -> void:
	_hold_active = false
	_hold_elapsed = 0.0


func cancel_placement(require_lmb_release: bool = false) -> void:
	current_step = Step.INACTIVE
	has_first_pole = false
	first_pole_pos = Vector3.ZERO
	has_aim_hit = false
	aim_pos = Vector3.ZERO
	aim_valid = false
	invalid_reason = InvalidReason.NONE
	span_distance = 0.0
	_hold_active = false
	_hold_elapsed = 0.0
	_require_lmb_release = require_lmb_release
	_hide_visuals()


func step(
	delta: float,
	is_equipped: bool,
	lmb_pressed: bool,
	mouse_captured: bool,
	refresh_ray: bool = true
) -> void:
	if not is_equipped:
		if current_step != Step.INACTIVE or has_first_pole or _hold_active:
			cancel_placement(false)
		else:
			_hide_visuals()
		return

	if current_step == Step.INACTIVE:
		current_step = Step.PLACING_FIRST_POLE
		if lmb_pressed:
			_require_lmb_release = true

	if not mouse_captured and lmb_pressed:
		_require_lmb_release = true

	if not lmb_pressed:
		_require_lmb_release = false
		_hold_active = false
		_hold_elapsed = 0.0

	if refresh_ray:
		_query_camera_aim()

	if lmb_pressed and mouse_captured and not _require_lmb_release:
		if aim_valid:
			if not _hold_active:
				_hold_active = true
				_hold_elapsed = 0.0
			_hold_elapsed += maxf(delta, 0.0)
			if _hold_elapsed >= get_hold_duration():
				_complete_active_step()
		else:
			_hold_active = false
			_hold_elapsed = 0.0
	else:
		_hold_active = false
		_hold_elapsed = 0.0

	_update_visuals(mouse_captured)


func get_prompt_text() -> String:
	match current_step:
		Step.PLACING_FIRST_POLE:
			if not has_aim_hit:
				return ""
			if aim_valid:
				return "[Hold LMB] Place First Pole"
			if invalid_reason == InvalidReason.OUT_OF_REACH:
				return "Out of Reach"
			if invalid_reason == InvalidReason.TOO_CLOSE_TO_LADDER:
				return "Too Close to Ladder"
			return "Invalid Surface (Aim at Floor)"
		Step.PLACING_SECOND_POLE:
			if aim_valid:
				return "[Hold LMB] Connect Wire (%.2fm)  |  [RMB] Cancel" % span_distance
			match invalid_reason:
				InvalidReason.TOO_CLOSE:
					return "Too Close (%.2fm)  |  [RMB] Cancel" % span_distance
				InvalidReason.TOO_FAR:
					return "Too Far (%.2fm)  |  [RMB] Cancel" % span_distance
				InvalidReason.OBSTRUCTED:
					return "Wire Obstructed  |  [RMB] Cancel"
				InvalidReason.TOO_CLOSE_TO_LADDER:
					return "Too Close to Ladder  |  [RMB] Cancel"
				InvalidReason.OUT_OF_REACH:
					return "Out of Reach  |  [RMB] Cancel"
				InvalidReason.INVALID_SURFACE:
					return "Aim at Flat Floor  |  [RMB] Cancel"
				_:
					return "Aim at Floor  |  [RMB] Cancel"
		_:
			return ""


func evaluate_aim_from_hit(
	hit: bool,
	hit_pos: Vector3,
	hit_normal: Vector3,
	hit_col: Object,
	hit_distance: float,
	world_3d: World3D = null,
	exclude_rids: Array[RID] = []
) -> bool:
	has_aim_hit = hit
	if not hit:
		aim_pos = Vector3.ZERO
		aim_valid = false
		invalid_reason = InvalidReason.NO_SURFACE
		span_distance = 0.0
		return false

	aim_pos = hit_pos
	var surf: Dictionary = validate_floor_surface(hit_col, hit_normal, hit_distance)
	var surf_valid: bool = bool(surf["valid"])
	var surf_reason: int = int(surf["reason"])
	var context_node: Node = hit_col as Node if hit_col is Node else self
	if surf_valid and is_point_in_ladder_safezone(hit_pos, context_node):
		surf_valid = false
		surf_reason = InvalidReason.TOO_CLOSE_TO_LADDER

	if current_step != Step.PLACING_SECOND_POLE or not has_first_pole:
		span_distance = 0.0
		aim_valid = surf_valid
		invalid_reason = InvalidReason.NONE if surf_valid else surf_reason
		return aim_valid

	span_distance = first_pole_pos.distance_to(hit_pos)
	if not surf_valid:
		aim_valid = false
		invalid_reason = surf_reason
		return false

	var span_check: Dictionary = validate_second_pole(first_pole_pos, hit_pos, world_3d, exclude_rids, context_node)
	aim_valid = bool(span_check["valid"])
	invalid_reason = int(span_check["reason"])
	return aim_valid


static func validate_floor_surface(hit_col: Object, hit_normal: Vector3, hit_distance: float) -> Dictionary:
	var reach: float = GameConfig.tripwire_place_reach if GameConfig != null else 3.00
	if hit_distance > reach + 0.01:
		return {"valid": false, "reason": InvalidReason.OUT_OF_REACH}

	if hit_col == null or not (hit_col is Node):
		return {"valid": false, "reason": InvalidReason.INVALID_SURFACE}

	var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
	var col_layer_v: Variant = hit_col.get("collision_layer")
	var col_layer: int = int(col_layer_v) if col_layer_v != null else 0
	if (col_layer & env_mask) == 0:
		return {"valid": false, "reason": InvalidReason.INVALID_SURFACE}

	if _is_interactable_node(hit_col as Node):
		return {"valid": false, "reason": InvalidReason.INVALID_SURFACE}

	if hit_normal.y <= 0.70:
		return {"valid": false, "reason": InvalidReason.INVALID_SURFACE}

	return {"valid": true, "reason": InvalidReason.NONE}


static func validate_second_pole(
	p1: Vector3,
	p2: Vector3,
	world_3d: World3D = null,
	exclude_rids: Array[RID] = [],
	context_node: Node = null
) -> Dictionary:
	var span: float = p1.distance_to(p2)
	var min_span: float = GameConfig.tripwire_min_span if GameConfig != null else 0.40
	var max_span: float = GameConfig.tripwire_max_span if GameConfig != null else 2.50

	if span < min_span:
		return {"valid": false, "reason": InvalidReason.TOO_CLOSE}
	if span > max_span:
		return {"valid": false, "reason": InvalidReason.TOO_FAR}

	var horiz_span: float = Vector2(p2.x - p1.x, p2.z - p1.z).length()
	if absf(p2.y - p1.y) > MAX_POLE_HEIGHT_DELTA or horiz_span < MIN_HORIZ_SPAN:
		return {"valid": false, "reason": InvalidReason.INVALID_SURFACE}

	if is_span_in_ladder_safezone(p1, p2, context_node):
		return {"valid": false, "reason": InvalidReason.TOO_CLOSE_TO_LADDER}

	if is_wire_obstructed(p1, p2, world_3d, exclude_rids):
		return {"valid": false, "reason": InvalidReason.OBSTRUCTED}

	return {"valid": true, "reason": InvalidReason.NONE}


static func get_ladder_safe_radius() -> float:
	return GameConfig.tripwire_ladder_safe_radius if GameConfig != null else DEFAULT_LADDER_SAFE_RADIUS


static func is_point_in_ladder_safezone(pt: Vector3, context_node: Node) -> bool:
	var radius: float = get_ladder_safe_radius()
	if radius <= 0.0:
		return false
	var r_sq: float = radius * radius
	for ladder in _get_active_ladders(context_node):
		if not _is_height_on_ladder_landing(pt.y, ladder):
			continue
		var center_xz: Vector2 = _get_ladder_safe_center_xz(ladder)
		if Vector2(pt.x, pt.z).distance_squared_to(center_xz) < r_sq:
			return true
	return false


static func is_span_in_ladder_safezone(p1: Vector3, p2: Vector3, context_node: Node) -> bool:
	var radius: float = get_ladder_safe_radius()
	if radius <= 0.0:
		return false
	var r_sq: float = radius * radius
	var a_xz := Vector2(p1.x, p1.z)
	var b_xz := Vector2(p2.x, p2.z)
	var mid_y: float = (p1.y + p2.y) * 0.5
	for ladder in _get_active_ladders(context_node):
		if (
			not _is_height_on_ladder_landing(mid_y, ladder)
			and not _is_height_on_ladder_landing(p1.y, ladder)
			and not _is_height_on_ladder_landing(p2.y, ladder)
		):
			continue
		var center_xz: Vector2 = _get_ladder_safe_center_xz(ladder)
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(center_xz, a_xz, b_xz)
		if center_xz.distance_squared_to(closest) < r_sq:
			return true
	return false


static func _get_active_ladders(context_node: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if context_node == null or not is_instance_valid(context_node) or not context_node.is_inside_tree():
		return result
	var tree: SceneTree = context_node.get_tree()
	if tree == null:
		return result
	for node in tree.get_nodes_in_group("interactive_ladders"):
		if node is Node3D and (node as Node3D).is_inside_tree():
			result.append(node as Node3D)
	return result


static func _get_ladder_safe_center_xz(ladder: Node3D) -> Vector2:
	var offset_z: float = float(ladder.call("shaft_center_offset")) if ladder.has_method("shaft_center_offset") else 0.0
	var world_center: Vector3 = ladder.to_global(Vector3(0.0, 0.0, offset_z))
	return Vector2(world_center.x, world_center.z)


static func _is_height_on_ladder_landing(y_pos: float, ladder: Node3D) -> bool:
	var lower_v: Variant = ladder.get("lower_landing_y")
	var upper_v: Variant = ladder.get("upper_landing_y")
	var lower_y: float = float(lower_v) if lower_v != null else ladder.global_position.y
	var upper_y: float = float(upper_v) if upper_v != null else (lower_y + 3.22)
	return (
		absf(y_pos - lower_y) <= LADDER_FLOOR_HEIGHT_TOLERANCE
		or absf(y_pos - upper_y) <= LADDER_FLOOR_HEIGHT_TOLERANCE
	)


static func is_wire_obstructed(
	p1: Vector3,
	p2: Vector3,
	world_3d: World3D,
	exclude_rids: Array[RID] = []
) -> bool:
	if world_3d == null:
		return false
	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if space == null:
		return false

	var wire_h: float = GameConfig.tripwire_height if GameConfig != null else 0.35
	var w1: Vector3 = p1 + Vector3(0.0, wire_h, 0.0)
	var w2: Vector3 = p2 + Vector3(0.0, wire_h, 0.0)
	var delta: Vector3 = w2 - w1
	var dist: float = delta.length()
	if dist <= 0.08:
		return false

	var dir: Vector3 = delta / dist
	var inset: float = minf(0.035, dist * 0.15)
	var q_from: Vector3 = w1 + dir * inset
	var q_to: Vector3 = w2 - dir * inset
	var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1

	var query := PhysicsRayQueryParameters3D.create(q_from, q_to, env_mask, exclude_rids)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	return not space.intersect_ray(query).is_empty()


static func _is_interactable_node(node: Node) -> bool:
	var cursor: Node = node
	while cursor != null:
		if cursor.has_method("request_interaction"):
			return true
		cursor = cursor.get_parent()
	return false


func _query_camera_aim() -> void:
	if _owner_player == null or not is_instance_valid(_owner_player) or not _owner_player.is_inside_tree():
		evaluate_aim_from_hit(false, Vector3.ZERO, Vector3.UP, null, 0.0)
		return

	var cam: Camera3D = _owner_player.get("camera") as Camera3D
	if cam == null:
		cam = _owner_player.get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null or not cam.is_inside_tree():
		evaluate_aim_from_hit(false, Vector3.ZERO, Vector3.UP, null, 0.0)
		return

	var world_3d: World3D = _owner_player.get_world_3d()
	if world_3d == null:
		evaluate_aim_from_hit(false, Vector3.ZERO, Vector3.UP, null, 0.0)
		return
	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if space == null:
		evaluate_aim_from_hit(false, Vector3.ZERO, Vector3.UP, null, 0.0)
		return

	var origin: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_transform.basis.z.normalized()
	var reach: float = GameConfig.tripwire_place_reach if GameConfig != null else 3.00
	var ray_len: float = maxf(PREVIEW_RAY_LENGTH, reach + 2.0)
	var mask: int = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3
	var exclude: Array[RID] = []
	if _owner_player is CollisionObject3D:
		exclude.append((_owner_player as CollisionObject3D).get_rid())

	var query := PhysicsRayQueryParameters3D.create(origin, origin + fwd * ray_len, mask, exclude)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		evaluate_aim_from_hit(false, Vector3.ZERO, Vector3.UP, null, 0.0, world_3d, exclude)
		return

	var hit_pos: Vector3 = hit["position"] as Vector3
	var hit_normal: Vector3 = hit["normal"] as Vector3
	var hit_col: Object = hit["collider"]
	var hit_dist: float = origin.distance_to(hit_pos)
	evaluate_aim_from_hit(true, hit_pos, hit_normal, hit_col, hit_dist, world_3d, exclude)


func _complete_active_step() -> void:
	if current_step == Step.PLACING_FIRST_POLE:
		if not aim_valid:
			_hold_active = false
			_hold_elapsed = 0.0
			return
		first_pole_pos = aim_pos
		has_first_pole = true
		current_step = Step.PLACING_SECOND_POLE
		span_distance = 0.0
		aim_valid = false
		invalid_reason = InvalidReason.TOO_CLOSE
		_hold_active = false
		_hold_elapsed = 0.0
		_require_lmb_release = true
		if AudioBridge != null:
			var pole_rad: float = GameConfig.audio_radius_tripwire_arm if GameConfig != null else 4.0
			var owner_id: int = _owner_player.name.to_int() if (_owner_player != null and is_instance_valid(_owner_player)) else 0
			AudioBridge.request_world_cue("tripwire_arm", first_pole_pos + Vector3(0.0, 0.25, 0.0), pole_rad, owner_id)
		return

	if current_step == Step.PLACING_SECOND_POLE:
		if not aim_valid or not has_first_pole:
			_hold_active = false
			_hold_elapsed = 0.0
			return
		var p1: Vector3 = first_pole_pos
		var p2: Vector3 = aim_pos
		cancel_placement(true)
		if _owner_player != null and is_instance_valid(_owner_player) and _owner_player.has_method("deploy_tripwire_between"):
			_owner_player.call("deploy_tripwire_between", p1, p2)


func _ensure_visuals() -> void:
	if not is_inside_tree():
		return

	var wire_h: float = GameConfig.tripwire_height if GameConfig != null else 0.35
	var pole_h: float = wire_h + 0.05

	if _mat_valid == null:
		_mat_valid = StandardMaterial3D.new()
		_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_valid.albedo_color = Color(0.15, 0.95, 0.30, 0.55)
		_mat_valid.emission_enabled = true
		_mat_valid.emission = Color(0.10, 0.90, 0.25)
		_mat_valid.emission_energy_multiplier = 0.60

	if _mat_invalid == null:
		_mat_invalid = StandardMaterial3D.new()
		_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_invalid.albedo_color = Color(0.95, 0.18, 0.15, 0.55)
		_mat_invalid.emission_enabled = true
		_mat_invalid.emission = Color(0.95, 0.15, 0.12)
		_mat_invalid.emission_energy_multiplier = 0.60

	var world_layer: int = GameConfig.VISUAL_LAYER_WORLD if GameConfig != null else 1

	if _placed_pole_node == null:
		_placed_pole_node = _create_pole_mesh_node("PlacedFirstPole", pole_h, null, world_layer)
		add_child(_placed_pole_node)

	if _ghost_pole_node == null:
		_ghost_pole_node = _create_pole_mesh_node("GhostPole", pole_h, _mat_valid, world_layer)
		add_child(_ghost_pole_node)

	if _ghost_wire_node == null:
		_ghost_wire_node = MeshInstance3D.new()
		_ghost_wire_node.name = "GhostWire"
		_ghost_wire_node.top_level = true
		_ghost_wire_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost_wire_node.layers = world_layer
		var wire_mesh := CylinderMesh.new()
		wire_mesh.top_radius = 0.008
		wire_mesh.bottom_radius = 0.008
		wire_mesh.height = 1.0
		_ghost_wire_node.mesh = wire_mesh
		_ghost_wire_node.material_override = _mat_valid
		_ghost_wire_node.visible = false
		add_child(_ghost_wire_node)


func _create_pole_mesh_node(node_name: String, pole_h: float, mat: Material, world_layer: int) -> Node3D:
	var pole := Node3D.new()
	pole.name = node_name
	pole.top_level = true
	var model: Node3D = TRIPWIRE_PREFAB.instantiate() as Node3D
	model.name = "PoleModel"
	model.scale = Vector3(2.2, pole_h / 0.1504, 2.2)
	pole.add_child(model)
	_apply_pole_appearance(pole, mat, world_layer, mat != null)
	pole.visible = false
	return pole


func _apply_pole_appearance(pole: Node3D, mat: Material, world_layer: int, override_material: bool = true) -> void:
	for child in pole.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = world_layer
		if override_material:
			mi.material_override = mat


func _update_visuals(show_aim_ghosts: bool) -> void:
	if not is_inside_tree():
		return
	_ensure_visuals()

	var wire_h: float = GameConfig.tripwire_height if GameConfig != null else 0.35
	var pole_h: float = wire_h + 0.05
	var ring_center_y: float = pole_h * PEG_RING_CENTER_RATIO
	var ring_side_offset: float = PEG_RING_SIDE_RADIUS_UNSCALED * PEG_XZ_SCALE * PEG_SIDE_TIE_SIGN
	var pole_scale := Vector3(PEG_XZ_SCALE, pole_h / PEG_MODEL_HEIGHT, PEG_XZ_SCALE)
	var world_layer: int = GameConfig.VISUAL_LAYER_WORLD if GameConfig != null else 1
	var facing_yaw: float = 0.0
	var has_facing_yaw: bool = false
	var side_vec := Vector3.ZERO
	if has_placed_first_pole() and has_aim_hit:
		var horiz_delta := Vector2(aim_pos.x - first_pole_pos.x, aim_pos.z - first_pole_pos.z)
		if horiz_delta.length_squared() > 0.0001:
			var span_yaw: float = atan2(-horiz_delta.y, horiz_delta.x)
			facing_yaw = span_yaw + PI * 0.5
			has_facing_yaw = true
			side_vec = Vector3(-sin(span_yaw), 0.0, cos(span_yaw)) * ring_side_offset

	if _placed_pole_node != null:
		if has_placed_first_pole():
			_placed_pole_node.visible = true
			_placed_pole_node.global_position = first_pole_pos
			if has_facing_yaw:
				_placed_pole_node.rotation.y = facing_yaw
			var placed_model := _placed_pole_node.get_node_or_null("PoleModel") as Node3D
			if placed_model != null:
				placed_model.scale = pole_scale
		else:
			_placed_pole_node.visible = false

	var active_mat: StandardMaterial3D = _mat_valid if aim_valid else _mat_invalid

	if _ghost_pole_node != null:
		if show_aim_ghosts and has_aim_hit and current_step != Step.INACTIVE:
			_ghost_pole_node.visible = true
			_ghost_pole_node.global_position = aim_pos
			if has_facing_yaw:
				_ghost_pole_node.rotation.y = facing_yaw
			var ghost_model := _ghost_pole_node.get_node_or_null("PoleModel") as Node3D
			if ghost_model != null:
				ghost_model.scale = pole_scale
			_apply_pole_appearance(_ghost_pole_node, active_mat, world_layer)
		else:
			_ghost_pole_node.visible = false

	if _ghost_wire_node != null:
		if show_aim_ghosts and has_placed_first_pole() and has_aim_hit:
			var w1: Vector3 = first_pole_pos + Vector3(0.0, ring_center_y, 0.0) + side_vec
			var w2: Vector3 = aim_pos + Vector3(0.0, ring_center_y, 0.0) + side_vec
			var delta: Vector3 = w2 - w1
			var full_len: float = delta.length()
			if full_len > 0.02:
				_ghost_wire_node.visible = true
				_ghost_wire_node.material_override = active_mat
				var wire_cyl: CylinderMesh = _ghost_wire_node.mesh as CylinderMesh
				if wire_cyl != null:
					wire_cyl.height = full_len
				var dir: Vector3 = delta / full_len
				var ref_up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
				var x_axis: Vector3 = ref_up.cross(dir).normalized()
				var z_axis: Vector3 = x_axis.cross(dir).normalized()
				_ghost_wire_node.global_transform = Transform3D(Basis(x_axis, dir, z_axis), (w1 + w2) * 0.5)
			else:
				_ghost_wire_node.visible = false
		else:
			_ghost_wire_node.visible = false


func _hide_visuals() -> void:
	if _placed_pole_node != null:
		_placed_pole_node.visible = false
	if _ghost_pole_node != null:
		_ghost_pole_node.visible = false
	if _ghost_wire_node != null:
		_ghost_wire_node.visible = false
