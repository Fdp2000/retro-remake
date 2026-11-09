extends CharacterBody3D

@export var head_pitch: float = 0.0

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.003

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var hud: CanvasLayer = $HUD
@onready var prompt_label: Label = $HUD/PromptLabel

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var _target_position: Vector3 = Vector3.ZERO
var _initial_pos_set: bool = false
var _interact_key_down: bool = false

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
	_target_position = position

func _ready() -> void:
	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		set_process_unhandled_input(true)
		set_process(true)
		hud.visible = true
	else:
		camera.current = false
		set_process_unhandled_input(false)
		set_process(false)
		hud.visible = false

func _set(property: StringName, value: Variant) -> bool:
	if not is_inside_tree():
		return false
	if property == &"position" and not is_multiplayer_authority():
		_target_position = value
		if not _initial_pos_set:
			_initial_pos_set = true
			return false
		return true
	return false

func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var is_interactable: bool = false
	var target_collider: Object = null

	if raycast.is_colliding():
		var collider: Object = raycast.get_collider()
		if collider and collider.has_method("request_interaction"):
			is_interactable = true
			target_collider = collider

	prompt_label.visible = is_interactable

	var interact_pressed: bool = (
		Input.is_action_just_pressed("interact")
		or Input.is_action_just_pressed("ui_accept")
		or Input.is_key_pressed(KEY_E)
	)

	if is_interactable and target_collider and interact_pressed and not _interact_key_down:
		_interact_key_down = true
		target_collider.request_interaction(multiplayer.get_unique_id())

	if not (Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_E)):
		_interact_key_down = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Toggle mouse capture with ui_cancel (Escape)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# Click into window to recapture mouse
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Mouse horizontal motion rotates the CharacterBody3D around the Y-axis
		rotate_y(-event.relative.x * mouse_sensitivity)

		# Mouse vertical motion rotates the Head around the X-axis (clamped between -89° and +89°)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

		# Update the synced head_pitch variable
		head_pitch = head.rotation.x

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Remote puppets interpolate position and update Head pitch visually
		if position.distance_squared_to(_target_position) > 16.0:
			position = _target_position
		else:
			position = position.lerp(_target_position, 20.0 * delta)

		head.rotation.x = lerp_angle(head.rotation.x, head_pitch, 20.0 * delta)
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if is_on_floor() and (Input.is_action_just_pressed("jump") or Input.is_key_pressed(KEY_SPACE)):
		velocity.y = jump_velocity

	# Standard first-person WASD vector movement relative to body transform
	var input_dir: Vector2 = Vector2.ZERO
	if InputMap.has_action("move_forward") and InputMap.has_action("move_left"):
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	else:
		if Input.is_key_pressed(KEY_W): input_dir.y -= 1.0
		if Input.is_key_pressed(KEY_S): input_dir.y += 1.0
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
		if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
		input_dir = input_dir.normalized()

	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
