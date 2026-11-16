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
			assert_true(String(piece.get_meta("source_asset")).begins_with("res://Assets/Models/Import/Household Items/Low Poly Furniture/"), "Furniture must come from household collection")
			for mesh_node in piece.find_children("*", "MeshInstance3D", true, false):
				assert_true(mesh_node.material_override == null, "Preserve imported materials")
			var bounds: AABB = spawner._bounds(piece, Transform3D.IDENTITY)
			assert_true(absf(bounds.position.y) < 0.001, "Furniture must rest on floor")
			assert_true(bounds.size.x <= 2.001 and bounds.size.z <= 1.401, "Furniture must fit reserved space")
			assert_true(not piece.find_children("*", "StaticBody3D", true, false).is_empty(), "Furniture needs collision")
	assert_true(types.size() == 112, "All 112 household assets should be represented")
	spawner.populate()
	assert_true(spawner.spawned_count == 128, "Repeated populate must not duplicate furniture")
	building.free()
