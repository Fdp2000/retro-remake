@tool
extends Node3D
## Per-instance materials keep changes local to this building.
const PALETTE_SHADER = preload("res://scenes/BuildingComplex2/room_palette.gdshader")
var _materials: Dictionary = {}

func _ready() -> void:
	refresh_palettes()

func refresh_palettes() -> void:
	if not is_inside_tree() or not has_node("Rooms"):
		return
	var walls := PackedColorArray()
	var floors := PackedColorArray()
	var ceilings := PackedColorArray()
	for row in range(1, 5):
		for column in range(1, 5):
			var room := get_node("Rooms/Room_%d_%d" % [row, column])
			walls.append(room.get("wall_color"))
			floors.append(room.get("floor_color"))
			ceilings.append(room.get("ceiling_color"))
	_apply_palette(get_node("Rooms"), floors, "floor")
	_apply_palette(get_node("Roofs"), ceilings, "ceiling")
	_apply_palette(get_node("Walls"), walls, "wall")

func _apply_palette(branch: Node, colors: PackedColorArray, category: String) -> void:
	for child in branch.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface in range(mesh_node.mesh.get_surface_count()):
			# Wall surface zero is plaster; preserve window frames and glass.
			if category == "wall" and surface != 0:
				continue
			var original := mesh_node.mesh.surface_get_material(surface) as ShaderMaterial
			if original == null:
				continue
			var key := "%s:%d" % [category, original.get_instance_id()]
			if not _materials.has(key):
				var tinted := original.duplicate() as ShaderMaterial
				tinted.shader = PALETTE_SHADER
				_materials[key] = tinted
			var material: ShaderMaterial = _materials[key]
			material.set_shader_parameter("room_colors", colors)
			material.set_shader_parameter("building_inverse", global_transform.affine_inverse())
			mesh_node.set_surface_override_material(surface, material)
