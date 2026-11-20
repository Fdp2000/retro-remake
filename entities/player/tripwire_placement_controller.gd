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
	OBSTRUCTED = 6
}

const PREVIEW_RAY_LENGTH: float = 8.0
const MAX_POLE_HEIGHT_DELTA: float = 0.65
const MIN_HORIZ_SPAN: float = 0.20

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

var _placed_pole_node: MeshInstance3D = null
var _ghost_pole_node: MeshInstance3D = null
var _ghost_wire_node: MeshInstance3D = null
var _mat_valid: StandardMaterial3D = null
var _mat_invalid: StandardMaterial3D = null
var _mat_placed_pole: StandardMaterial3D = null


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

	var span_check: Dictionary = validate_second_pole(first_pole_pos, hit_pos, world_3d, exclude_rids)
	aim_valid = bool(span_check["valid"])
	invalid_reason = int(span_check["reason"])
	return aim_valid


static func validate_floor_surface(hit_col: Object, hit_normal: Vector3, hit_distance: float) -> Dictionary:
	var reach: float = GameConfig.interact_reach if GameConfig != null else 2.2
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
	exclude_rids: Array[RID] = []
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

	if is_wire_obstructed(p1, p2, world_3d, exclude_rids):
		return {"valid": false, "reason": InvalidReason.OBSTRUCTED}

	return {"valid": true, "reason": InvalidReason.NONE}


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
	var reach: float = GameConfig.interact_reach if GameConfig != null else 2.2
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

	if _mat_placed_pole == null:
		_mat_placed_pole = StandardMaterial3D.new()
		_mat_placed_pole.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_placed_pole.albedo_color = Color(0.92, 0.50, 0.16, 0.92)
		_mat_placed_pole.emission_enabled = true
		_mat_placed_pole.emission = Color(0.85, 0.42, 0.12)
		_mat_placed_pole.emission_energy_multiplier = 0.45

	var world_layer: int = GameConfig.VISUAL_LAYER_WORLD if GameConfig != null else 1

	if _placed_pole_node == null:
		_placed_pole_node = _create_pole_mesh_node("PlacedFirstPole", pole_h, _mat_placed_pole, world_layer)
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


func _create_pole_mesh_node(node_name: String, pole_h: float, mat: Material, world_layer: int) -> MeshInstance3D:
	var pole := MeshInstance3D.new()
	pole.name = node_name
	pole.top_level = true
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.layers = world_layer
	var peg_mesh := CylinderMesh.new()
	peg_mesh.top_radius = 0.025
	peg_mesh.bottom_radius = 0.032
	peg_mesh.height = pole_h
	pole.mesh = peg_mesh
	pole.material_override = mat
	pole.visible = false
	return pole


func _update_visuals(show_aim_ghosts: bool) -> void:
	if not is_inside_tree():
		return
	_ensure_visuals()

	var wire_h: float = GameConfig.tripwire_height if GameConfig != null else 0.35
	var pole_h: float = wire_h + 0.05

	if _placed_pole_node != null:
		if has_placed_first_pole():
			_placed_pole_node.visible = true
			_placed_pole_node.global_position = first_pole_pos + Vector3(0.0, pole_h * 0.5, 0.0)
			var placed_cyl: CylinderMesh = _placed_pole_node.mesh as CylinderMesh
			if placed_cyl != null:
				placed_cyl.height = pole_h
		else:
			_placed_pole_node.visible = false

	var active_mat: StandardMaterial3D = _mat_valid if aim_valid else _mat_invalid

	if _ghost_pole_node != null:
		if show_aim_ghosts and has_aim_hit and current_step != Step.INACTIVE:
			_ghost_pole_node.visible = true
			_ghost_pole_node.global_position = aim_pos + Vector3(0.0, pole_h * 0.5, 0.0)
			_ghost_pole_node.material_override = active_mat
			var ghost_cyl: CylinderMesh = _ghost_pole_node.mesh as CylinderMesh
			if ghost_cyl != null:
				ghost_cyl.height = pole_h
		else:
			_ghost_pole_node.visible = false

	if _ghost_wire_node != null:
		if show_aim_ghosts and has_placed_first_pole() and has_aim_hit:
			var w1: Vector3 = first_pole_pos + Vector3(0.0, wire_h, 0.0)
			var w2: Vector3 = aim_pos + Vector3(0.0, wire_h, 0.0)
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
