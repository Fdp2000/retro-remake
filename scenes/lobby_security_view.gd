extends TextureRect

const ROOM_PATH := "SecondFloor/Rooms/Room_1_1"
const SWEEP_SECONDS := 18.0
const SWEEP_ANGLE := deg_to_rad(12.0)
const CAMERA_INTERVAL := 1.0 / 30.0
const MONITOR_SHADER := preload("res://scenes/lobby_security_view.gdshader")

var _camera: Camera3D
var _viewport: SubViewport
var _rest_yaw := 0.0
var _elapsed := 0.0
var _until_update := 0.0


func _ready() -> void:
	set_process(false)
	_build_preview.call_deferred()


func _build_preview() -> void:
	var packed := load("res://scenes/test_gym.tscn") as PackedScene
	var source := packed.instantiate() as Node3D
	var building := source.get_node("BuildingComplex3") as Node3D
	var room := building.get_node(ROOM_PATH) as Node3D
	var upper := room.get_parent().get_parent() as Node3D

	# Keep the room and its window view, without starting the match or loading its layout.
	building.get_node("LadderLayout").free()
	_trim_floor(building, null)
	_trim_floor(upper, room)

	_viewport = SubViewport.new()
	_viewport.name = "SecurityViewport"
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(960, 540)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var preview_nodes := ["WorldEnvironment", "BuildingComplex3"]
	for child in source.get_children():
		if child is DirectionalLight3D:
			preview_nodes.append(String(child.name))
	for node_name in preview_nodes:
		var node := source.get_node(node_name)
		source.remove_child(node)
		node.owner = null
		_viewport.add_child(node)
	source.free()

	_camera = Camera3D.new()
	_camera.name = "CornerCamera"
	_camera.fov = 76.0
	_viewport.add_child(_camera)
	_camera.current = true
	_camera.global_position = room.to_global(Vector3(3.72, 2.63, 3.77))
	_camera.look_at(room.to_global(Vector3(-0.55, 1.24, -0.9)))
	_rest_yaw = _camera.rotation.y

	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _viewport == null or not is_instance_valid(_viewport):
		return
	var monitor := ShaderMaterial.new()
	monitor.shader = MONITOR_SHADER
	material = monitor
	texture = _viewport.get_texture()
	set_process(true)


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera) or _viewport == null or not is_instance_valid(_viewport):
		return
	_elapsed = fmod(_elapsed + delta, SWEEP_SECONDS)
	_until_update -= delta
	if _until_update > 0.0:
		return
	_until_update += CAMERA_INTERVAL
	_camera.rotation.y = _rest_yaw + sin(_elapsed * TAU / SWEEP_SECONDS) * SWEEP_ANGLE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _trim_floor(level: Node3D, visible_room: Node3D) -> void:
	for room in level.get_node("Rooms").get_children():
		if room != visible_room:
			_remove_children(room)
	if visible_room == null:
		_remove_children(level.get_node("Walls"))
		_remove_children(level.get_node("Roofs"))
		return

	var center := visible_room.position
	var limits: Vector2 = visible_room.get_meta("room_size") * 0.5 + Vector2(0.1, 0.1)
	for path in ["Walls", "Roofs"]:
		var branch := level.get_node(path) as Node3D
		for child in branch.get_children():
			var tile := child as Node3D
			if tile.name == &"RoofSeal":
				continue
			var offset := branch.transform * tile.position - center
			if absf(offset.x) > limits.x or absf(offset.z) > limits.y:
				tile.free()


func _remove_children(node: Node) -> void:
	for child in node.get_children():
		child.free()
