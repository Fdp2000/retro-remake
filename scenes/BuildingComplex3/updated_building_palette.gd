@tool
extends "res://scenes/BuildingComplex2/building_palette.gd"

const UPDATED_PALETTE_SHADER := preload("res://scenes/BuildingComplex3/updated_room_palette.gdshader")
const FLOOR_TEXTURE := preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Texture_Floor.png")
const CEILING_TEXTURE := preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Texture_Ceiling.png")
const FLOOR_TILE := "res://Assets/Models/Import/Interiors_A/Scenes/Floor/floor_3x_3.tscn"
const WALL_TEXTURES := {
	"wall_blue": preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Blue.png"),
	"wall_green": preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Green.png"),
	"wall_purple": preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Purple.png"),
	"wall_red": preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Red.png"),
	"wall_yellow": preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Yellow.png"),
}
# Hue of the painted area in each texture, in the same order as the shader samplers.
const WALL_HUES := [0.495, 0.284, 0.670, 0.023, 0.173]

var _updated_materials: Dictionary[String, ShaderMaterial] = {}


func _surface_tint(room: Node, _category: String) -> Color:
	return room.get("wall_color")


func _apply_palette(branch: Node, colors: PackedColorArray, category: String) -> void:
	var is_wall := category == "wall"
	if not _updated_materials.has(category):
		var material := ShaderMaterial.new()
		material.shader = UPDATED_PALETTE_SHADER
		material.set_shader_parameter("is_wall", is_wall)
		material.set_shader_parameter("is_ceiling", category == "ceiling")
		if is_wall:
			for parameter in WALL_TEXTURES:
				material.set_shader_parameter(parameter, WALL_TEXTURES[parameter])
		else:
			var texture := FLOOR_TEXTURE if category == "floor" else CEILING_TEXTURE
			material.set_shader_parameter("surface_texture", texture)
		_updated_materials[category] = material

	var material := _updated_materials[category]
	material.set_shader_parameter("room_colors", colors)
	material.set_shader_parameter("building_inverse", global_transform.affine_inverse())
	if is_wall:
		var variants := PackedInt32Array()
		for color in colors:
			variants.append(_wall_variant(color.h))
		material.set_shader_parameter("wall_variants", variants)

	for child in branch.find_children("*", "MeshInstance3D", true, false):
		var tile := child as MeshInstance3D
		if tile.mesh == null or (not is_wall and tile.scene_file_path != FLOOR_TILE):
			continue
		# Window frames and glass keep their own materials.
		var surface_count := 1 if is_wall else tile.mesh.get_surface_count()
		for surface in range(surface_count):
			tile.set_surface_override_material(surface, material)


func _wall_variant(hue: float) -> int:
	var nearest := 0
	var nearest_distance := INF
	for index in range(WALL_HUES.size()):
		var difference := absf(hue - WALL_HUES[index])
		var distance := minf(difference, 1.0 - difference)
		if distance < nearest_distance:
			nearest = index
			nearest_distance = distance
	return nearest
