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
@export_range(0, 4) var wall_texture_offset := 0

static var _wall_swatches: Dictionary[int, Color] = {}

var _wall_material: ShaderMaterial
var _plain_materials: Dictionary[String, StandardMaterial3D] = {}


func _apply_palette(branch: Node, _colors: PackedColorArray, category: String) -> void:
	var is_wall := category == "wall"
	var material: Material = _wall_texture_material() if is_wall else _plain_material(category)

	for child in branch.find_children("*", "MeshInstance3D", true, false):
		var tile := child as MeshInstance3D
		if tile.mesh == null or (not is_wall and tile.scene_file_path != FLOOR_TILE):
			continue
		# Window frames and glass keep their own materials.
		var surface_count := 1 if is_wall else tile.mesh.get_surface_count()
		for surface in range(surface_count):
			tile.set_surface_override_material(surface, material)


func _plain_material(category: String) -> StandardMaterial3D:
	if not _plain_materials.has(category):
		var material := StandardMaterial3D.new()
		material.albedo_texture = FLOOR_TEXTURE if category == "floor" else CEILING_TEXTURE
		material.roughness = 1.0
		material.metallic_specular = 0.0
		_plain_materials[category] = material
	return _plain_materials[category]


func _wall_texture_material() -> ShaderMaterial:
	if _wall_material == null:
		_wall_material = ShaderMaterial.new()
		_wall_material.shader = UPDATED_PALETTE_SHADER
		for parameter in WALL_TEXTURES:
			_wall_material.set_shader_parameter(parameter, WALL_TEXTURES[parameter])

	_wall_material.set_shader_parameter("building_inverse", global_transform.affine_inverse())
	var variants := PackedInt32Array()
	for row in range(4):
		for column in range(4):
			variants.append(_wall_variant(Vector2i(column, row)))
	_wall_material.set_shader_parameter("wall_variants", variants)
	return _wall_material


func get_room_wall_swatch(room: Node3D) -> Color:
	# Use the same world-to-cell mapping as the wall shader, even on smaller layouts.
	var center := to_local(room.global_position)
	var coords := (Vector2(center.x, center.z) + Vector2(18.0, 18.0)) / 9.0
	var cell := Vector2i(coords.floor().clamp(Vector2.ZERO, Vector2(3.0, 3.0)))
	var variant := _wall_variant(cell)
	if not _wall_swatches.has(variant):
		var texture: Texture2D = WALL_TEXTURES.values()[variant]
		var image := texture.get_image()
		if image.is_compressed() and image.decompress() != OK:
			return Color("#546c65")
		var swatch := Color(0, 0, 0, 0)
		# Sample the painted area of the texture, away from the trim.
		for row in range(4):
			for column in range(5):
				var uv := Vector2(0.25 + column * 0.125, 0.28 + row * 0.07)
				var pixel := Vector2i(uv * Vector2(image.get_size() - Vector2i.ONE))
				swatch += image.get_pixelv(pixel)
		_wall_swatches[variant] = swatch / 20.0
	return _wall_swatches[variant]


func _wall_variant(cell: Vector2i) -> int:
	return (cell.y * 2 + cell.x + wall_texture_offset) % WALL_TEXTURES.size()
