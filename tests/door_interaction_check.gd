extends Node3D

var failures: int = 0

func check(condition: bool, description: String) -> void:
	if condition:
		print("DOOR CHECK PASS: ", description)
	else:
		failures += 1
		push_error("DOOR CHECK FAIL: " + description)

func _ready() -> void:
	run_checks.call_deferred()

func press_e() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().create_timer(0.1).timeout
	event = InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().create_timer(0.4).timeout

func run_checks() -> void:
	var building: Node3D = load("res://scenes/BuildingComplex/BuildingComplex.tscn").instantiate()
	add_child(building)
	var interactive_count: int = 0
	for door in building.get_node("Doors").get_children():
		if door.get_node("Door_B_Frame/Door_B_Door").has_method("request_interaction"):
			interactive_count += 1
	check(interactive_count == 22, "all 22 complex doors have interaction scripts")
	var players := Node3D.new()
	players.name = "Players"
	add_child(players)
	var player: CharacterBody3D = load("res://entities/player/player.tscn").instantiate()
	player.name = "1"
	player.position = Vector3(-9, 0, -8.5)
	players.add_child(player)
	player.set_physics_process(false)
	var camera: Camera3D = player.get_node("Head/Camera3D")
	var ray: RayCast3D = camera.get_node("RayCast3D")
	var leaf: MeshInstance3D = building.get_node("Doors/Door_4/Door_B_Frame/Door_B_Door")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.1).timeout
	check(ray.is_colliding() and leaf.is_ancestor_of(ray.get_collider()), "real player ray reaches door instead of own collider")
	check(player.get_node("HUD/PromptLabel").visible, "real player shows door interaction prompt")
	await press_e()
	check(leaf.is_open and is_equal_approx(leaf.rotation.y, -PI / 2), "E through real player opens complex door")
	var body: StaticBody3D = leaf.get_node("Door_B_Door")
	check(body.global_basis.is_equal_approx(leaf.global_basis), "collision rotates with door")
	camera.look_at(leaf.to_global(Vector3(0.35, 0.4, 0)), Vector3.UP)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await press_e()
	check(not leaf.is_open and is_zero_approx(leaf.rotation.y), "second E closes complex door")
	player.position.z = 0
	leaf.request_interaction(1)
	check(not leaf.is_open, "out of range requests rejected")
	player.position = Vector3(-9, 0, -8.5)
	camera.rotation = Vector3.ZERO
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.2)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = Vector3(-9, 1.5, -9.5)
	add_child(blocker)
	await get_tree().physics_frame
	await get_tree().physics_frame
	leaf.request_interaction(1)
	check(not leaf.is_open, "requests through walls rejected")
	print("DOOR CHECK COMPLETE: ", failures, " failures")
