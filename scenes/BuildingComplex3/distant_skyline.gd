@tool
extends Node3D

const CLOUD_SHADER := preload("res://scenes/BuildingComplex3/skyline_clouds.gdshader")
const FACADE_SHADER := preload("res://scenes/BuildingComplex3/skyline_facade.gdshader")
const WALL_TEXTURES: Array[Texture2D] = [
	preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Blue.png"),
	preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Green.png"),
	preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Purple.png"),
	preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Red.png"),
	preload("res://Assets/Models/Import/Interiors_A/texture/Updated_Textures/Wall/Texture_Wall_Yellow.png"),
]
const ORIGIN := Vector3(0.0, -24.0, -4.5)
const TOWER_DROP := 25.0
const BELOW_MIST_EXTENSION := 160.0
const SKYLINE_SEED := 8027
const ROOF_COLOR := Color("#657885")
const HAZE_COLOR := Color("#9cabb6")
const CLOUD_MIST := Color(0.82, 0.88, 0.93)


func _ready() -> void:
	_add_cloud_deck()
	var rng := RandomNumberGenerator.new()
	rng.seed = SKYLINE_SEED
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_add_ring(rng, box, 17, 57.0, 0.22, 0.0)
	_add_ring(rng, box, 26, 94.0, 0.51, 0.47)


func _add_cloud_deck() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(900.0, 900.0)
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	# Blend the mist before the windows’ transparent glass is drawn.
	material.render_priority = -10
	material.set_shader_parameter("cloud_mist", CLOUD_MIST)
	var deck := MeshInstance3D.new()
	deck.name = "CloudDeck"
	deck.mesh = mesh
	deck.material_override = material
	deck.position = ORIGIN
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deck)


func _add_ring(rng: RandomNumberGenerator, box: BoxMesh, tower_count: int, distance: float, haze: float, phase: float) -> void:
	var towers: Array[Array] = []
	for _texture in WALL_TEXTURES:
		towers.append([])
	var roof_details: Array[Transform3D] = []

	for index in range(tower_count):
		var angle := TAU * (float(index) + phase + rng.randf_range(-0.08, 0.08)) / tower_count
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var center := ORIGIN + Vector3.DOWN * TOWER_DROP + radial * (distance + rng.randf_range(-4.0, 4.0))
		var footprint_limit := TAU * distance / float(tower_count) * 0.82
		var width := rng.randf_range(13.0, minf(23.0, footprint_limit))
		var depth := rng.randf_range(13.0, minf(24.0, footprint_limit))
		var height := rng.randf_range(54.0, 113.0)
		if index % 11 == 2:
			height += 24.0
		var facade := rng.randi_range(0, WALL_TEXTURES.size() - 1)
		towers[facade].append(_box_at(center + Vector3.DOWN * BELOW_MIST_EXTENSION, Vector3(width, height + BELOW_MIST_EXTENSION, depth)))
		if index % 4 != 1:
			var setback_height := rng.randf_range(7.0, 17.0)
			towers[facade].append(_box_at(center + Vector3.UP * height, Vector3(width * 0.69, setback_height, depth * 0.72)))
			height += setback_height
		roof_details.append(_box_at(center + Vector3.UP * height, Vector3(width * 0.41, 2.7, depth * 0.45)))
		if index % 6 == 2:
			roof_details.append(_box_at(center + Vector3.UP * (height + 2.7), Vector3(0.55, rng.randf_range(8.0, 16.0), 0.55)))

	for i in range(WALL_TEXTURES.size()):
		var material := ShaderMaterial.new()
		material.shader = FACADE_SHADER
		material.set_shader_parameter("wall_texture", WALL_TEXTURES[i])
		material.set_shader_parameter("haze_color", HAZE_COLOR)
		material.set_shader_parameter("haze_amount", haze)
		material.set_shader_parameter("cloud_mist", CLOUD_MIST)
		material.set_shader_parameter("cloud_level", ORIGIN.y + global_position.y)
		_add_batch(box, material, towers[i])

	var roof := StandardMaterial3D.new()
	roof.albedo_color = ROOF_COLOR.lerp(HAZE_COLOR, haze)
	roof.roughness = 0.92
	roof.emission_enabled = true
	roof.emission = roof.albedo_color
	roof.emission_energy_multiplier = 0.27
	_add_batch(box, roof, roof_details)


func _box_at(base: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), base + Vector3.UP * size.y * 0.5)


func _add_batch(box: BoxMesh, material: Material, transforms: Array) -> void:
	if transforms.is_empty():
		return
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = box
	instances.instance_count = transforms.size()
	for i in range(transforms.size()):
		instances.set_instance_transform(i, transforms[i])
	var geometry := MultiMeshInstance3D.new()
	geometry.multimesh = instances
	geometry.material_override = material
	geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(geometry)
