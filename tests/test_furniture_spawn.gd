@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

func test_furniture_at_all_room_markers() -> void:
	var packed := ResourceLoader.load("res://scenes/BuildingComplex2/BuildingComplex2.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var building := packed.instantiate()
	var spawner := building.get_node("FurnitureSpawner")
	spawner.populate()
	assert_true(spawner.spawned_count == 128, "Expected furniture at all 128 markers")
	var types: Dictionary = {}
	for room in building.get_node("Rooms").get_children():
		for marker in room.get_node("FurnitureSpawnPoints").get_children():
			assert_true(marker.get_child_count() == 1, "Each marker needs one furniture piece")
			var piece := marker.get_child(0) as Node3D
			types[piece.get_meta("source_piece")] = true
			for mesh_node in piece.find_children("*", "MeshInstance3D", true, false):
				var material := mesh_node.material_override as StandardMaterial3D
				assert_true(material != null, "Furniture mesh must have wood material")
				if material != null:
					assert_true(material.albedo_texture != null and material.normal_texture != null and material.roughness_texture != null, "Wood color, normal and roughness maps must be assigned")
			var bounds: AABB = spawner._bounds(piece, Transform3D.IDENTITY)
			assert_true(absf(bounds.position.y) < 0.001, "Furniture must rest on floor")
			assert_true(bounds.size.x <= 2.001 and bounds.size.z <= 1.401, "Furniture must fit reserved space")
			assert_true(not piece.find_children("*", "StaticBody3D", true, false).is_empty(), "Furniture needs collision")
	assert_true(types.size() == 53, "All 53 source furniture designs should be represented")
	spawner.populate()
	assert_true(spawner.spawned_count == 128, "Repeated populate must not duplicate furniture")
	building.free()
