class_name SurfaceDetector
extends Node

## Downward raycast surface detector for footstep and impact audio modulation (Phase 4).

const SURFACE_WOOD: String = "wood"
const SURFACE_TILE: String = "tile"
const SURFACE_CARPET: String = "carpet"
const SURFACE_METAL: String = "metal"
const SURFACE_DEFAULT: String = "default"

@export var ray_length: float = 1.6

var last_surface: String = SURFACE_DEFAULT


func detect_surface_below(target_node: Node3D = null) -> String:
	var node: Node3D = target_node if target_node != null else (get_parent() as Node3D)
	if node == null or not node.is_inside_tree():
		last_surface = SURFACE_DEFAULT
		return last_surface

	var world: World3D = node.get_world_3d()
	if world == null:
		last_surface = SURFACE_DEFAULT
		return last_surface

	var exclude: Array[RID] = []
	if node is CollisionObject3D:
		exclude.append((node as CollisionObject3D).get_rid())

	last_surface = detect_surface_at(world, node.global_position, ray_length, exclude)
	return last_surface


static func detect_surface_at(
	world: World3D,
	origin: Vector3,
	p_ray_length: float = 1.6,
	exclude: Array[RID] = []
) -> String:
	if world == null:
		return SURFACE_DEFAULT
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return SURFACE_DEFAULT

	var from_pos: Vector3 = origin + Vector3(0.0, 0.25, 0.0)
	var to_pos: Vector3 = origin - Vector3(0.0, p_ray_length, 0.0)
	var mask: int = GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos, mask, exclude)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return SURFACE_DEFAULT

	return identify_collider_surface(hit.get("collider", null))


static func identify_collider_surface(collider: Object) -> String:
	if collider == null:
		return SURFACE_DEFAULT

	if collider.has_meta("surface"):
		var normalized_meta: String = normalize_surface_name(str(collider.get_meta("surface", "")))
		if normalized_meta != SURFACE_DEFAULT:
			return normalized_meta

	if collider is Node:
		var parent: Node = (collider as Node).get_parent()
		if parent != null and parent.has_meta("surface"):
			var parent_meta: String = normalize_surface_name(str(parent.get_meta("surface", "")))
			if parent_meta != SURFACE_DEFAULT:
				return parent_meta

	var phys_mat_var: Variant = collider.get("physics_material_override")
	if phys_mat_var is PhysicsMaterial:
		var phys_mat: PhysicsMaterial = phys_mat_var as PhysicsMaterial
		if phys_mat.has_meta("surface"):
			var mat_meta: String = normalize_surface_name(str(phys_mat.get_meta("surface", "")))
			if mat_meta != SURFACE_DEFAULT:
				return mat_meta
		var mat_name: String = normalize_surface_name(phys_mat.resource_name)
		if mat_name != SURFACE_DEFAULT:
			return mat_name

	if collider is Node:
		var node_col: Node = collider as Node
		var name_match: String = _match_keywords(node_col.name)
		if name_match != SURFACE_DEFAULT:
			return name_match
		var parent_node: Node = node_col.get_parent()
		if parent_node != null:
			var parent_match: String = _match_keywords(parent_node.name)
			if parent_match != SURFACE_DEFAULT:
				return parent_match

	return SURFACE_DEFAULT


static func normalize_surface_name(raw: String) -> String:
	var key: String = raw.strip_edges().to_lower()
	if key.is_empty():
		return SURFACE_DEFAULT
	match key:
		"wood", "wooden", "parquet", "plank", "hardwood":
			return SURFACE_WOOD
		"tile", "ceramic", "marble", "stone", "concrete":
			return SURFACE_TILE
		"carpet", "rug", "fabric":
			return SURFACE_CARPET
		"metal", "steel", "iron", "grate", "safe", "ladder":
			return SURFACE_METAL
	return _match_keywords(key)


static func _match_keywords(text: String) -> String:
	var low: String = text.to_lower()
	if low.contains("carpet") or low.contains("rug"):
		return SURFACE_CARPET
	if low.contains("metal") or low.contains("ladder") or low.contains("safe") or low.contains("grate"):
		return SURFACE_METAL
	if low.contains("tile") or low.contains("marble") or low.contains("ceramic") or low.contains("stone"):
		return SURFACE_TILE
	if low.contains("wood") or low.contains("parquet") or low.contains("plank"):
		return SURFACE_WOOD
	return SURFACE_DEFAULT
