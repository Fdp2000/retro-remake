@tool
class_name BriefcaseVisualBuilder
extends RefCounted

## Builds the unified 3D Hinged Attaché Briefcase mesh rig used by floor Briefcase pickups/containers.
## Keeps closed and open visuals in a single rig (eliminating overlapping closed-box / open-tray clipping).
## Interior is open, slot-free dark felt with freeform XY placement and strictly disjoint vertical layers.

const BRIEFCASE_SCENE: PackedScene = preload("res://Assets/Models/Kuffert/Briefcase.glb")
const BRIEFCASE_TEXTURE: Texture2D = preload("res://Assets/Models/Traps/Texture_Briefcase.png")
const MODEL_SCALE: float = 0.82
const MODEL_Y_OFFSET: float = -0.048

const CASE_WIDTH: float = 0.56
const CASE_DEPTH: float = 0.38
const BASE_HEIGHT: float = 0.085
const LID_HEIGHT: float = 0.042
const WALL_THICK: float = 0.022
const OPEN_LID_ANGLE_DEG: float = -118.0

const INTERIOR_HALF_X: float = 0.19
const INTERIOR_HALF_Z: float = 0.115
const NORM_MIN: float = 0.08
const NORM_MAX: float = 0.92

const BOMB_LAYER_Y: float = -0.045
const ITEM_LAYER_BASE_Y: float = -0.027
const ITEM_LAYER_STEP_Y: float = 0.016
const DEFAULT_BOMB_NORM_POS := Vector2(0.50, 0.45)

## Default non-overlapping spread for newly packed Objectives (player can drag anywhere afterward)
const DEFAULT_ITEM_NORM_POSITIONS: Array[Vector2] = [
	Vector2(0.32, 0.35),
	Vector2(0.68, 0.38),
	Vector2(0.36, 0.68),
	Vector2(0.66, 0.65)
]


static func clamp_norm(norm: Vector2) -> Vector2:
	return Vector2(
		clampf(norm.x, NORM_MIN, NORM_MAX),
		clampf(norm.y, NORM_MIN, NORM_MAX)
	)


static func norm_to_briefcase_local_xz(norm: Vector2) -> Vector2:
	var c: Vector2 = clamp_norm(norm)
	return Vector2(
		lerpf(-INTERIOR_HALF_X, INTERIOR_HALF_X, c.x),
		lerpf(-INTERIOR_HALF_Z, INTERIOR_HALF_Z, c.y)
	)


static func briefcase_local_xz_to_norm(local_x: float, local_z: float) -> Vector2:
	var nx: float = (local_x + INTERIOR_HALF_X) / maxf(INTERIOR_HALF_X * 2.0, 0.001)
	var nz: float = (local_z + INTERIOR_HALF_Z) / maxf(INTERIOR_HALF_Z * 2.0, 0.001)
	return clamp_norm(Vector2(nx, nz))


static func get_item_layer_y(layer_idx: int) -> float:
	return ITEM_LAYER_BASE_Y + float(maxi(layer_idx, 0)) * ITEM_LAYER_STEP_Y


static func instantiate_textured_briefcase() -> Node3D:
	var model: Node3D = BRIEFCASE_SCENE.instantiate() as Node3D
	if model == null:
		return Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = BRIEFCASE_TEXTURE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.72
	for child_mi in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child_mi as MeshInstance3D
		if mi != null:
			mi.material_override = mat
	return model


static func build_briefcase_rig(parent: Node3D) -> Dictionary:
	var rig_root := Node3D.new()
	rig_root.name = "BriefcaseVisualRig"
	parent.add_child(rig_root)

	var model: Node3D = instantiate_textured_briefcase()
	model.name = "BriefcaseModel"
	model.scale = Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	model.position = Vector3(0.0, MODEL_Y_OFFSET, 0.0)
	rig_root.add_child(model)

	var lid_pivot: Node3D = model.find_child("KnogleKuffertTop", true, false) as Node3D

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
