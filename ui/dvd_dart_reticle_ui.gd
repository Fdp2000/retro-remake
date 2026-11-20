@tool
class_name DVDDartReticleUI
extends Control

## Bouncing DVD-Logo Crosshair for the 1-Shot DVD Dart Gun (Doc 4 §3.5).
## Glides across the viewport at 320 px/s, bouncing off screen edges and flashing gold on corner hits.

const RETICLE_SIZE := Vector2(78.0, 36.0)

var velocity: Vector2 = Vector2(226.27, 226.27)
var _reticle_panel: PanelContainer = null
var _reticle_label: Label = null
var _corner_flash_timer: float = 0.0
var is_reticle_active: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_visual()


func _build_visual() -> void:
	if _reticle_panel != null:
		return
	_reticle_panel = PanelContainer.new()
	_reticle_panel.name = "DVDReticleBox"
	_reticle_panel.size = RETICLE_SIZE
	_reticle_panel.position = Vector2(220.0, 160.0)
	_reticle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle_panel.modulate = Color(0.75, 0.30, 1.0, 0.92)
	add_child(_reticle_panel)

	_reticle_label = Label.new()
	_reticle_label.text = "DVD DART"
	_reticle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reticle_label.add_theme_font_size_override("font_size", 13)
	_reticle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle_panel.add_child(_reticle_label)


func set_active(active: bool) -> void:
	var was_active: bool = is_reticle_active
	is_reticle_active = active
	visible = active
	if active and _reticle_panel == null:
		_build_visual()
	if active and not was_active:
		_randomize_spawn()


func _randomize_spawn() -> void:
	if _reticle_panel == null:
		return
	var bounds: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280.0, 720.0)
	if bounds.x < 100.0 or bounds.y < 100.0:
		bounds = Vector2(1280.0, 720.0)
	var max_x: float = maxf(bounds.x - RETICLE_SIZE.x, 10.0)
	var max_y: float = maxf(bounds.y - RETICLE_SIZE.y, 10.0)
	_reticle_panel.position = Vector2(randf_range(0.0, max_x), randf_range(0.0, max_y))
	var spd: float = GameConfig.dvd_reticle_speed_px if GameConfig != null else 320.0
	var sx: float = -1.0 if randi() % 2 == 0 else 1.0
	var sy: float = -1.0 if randi() % 2 == 0 else 1.0
	velocity = Vector2(sx, sy).normalized() * spd
	_corner_flash_timer = 0.0
	_reticle_panel.modulate = Color(0.75, 0.30, 1.0, 0.92)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_reticle_active or not visible:
		return
	var bounds: Vector2 = get_viewport_rect().size
	if bounds.x < 100.0 or bounds.y < 100.0:
		bounds = Vector2(1280.0, 720.0)
	step_bounce(delta, bounds)

	if _corner_flash_timer > 0.0:
		_corner_flash_timer -= delta
		if _corner_flash_timer <= 0.0 and _reticle_panel != null:
			_reticle_panel.modulate = Color(0.75, 0.30, 1.0, 0.92)


func step_bounce(delta: float, bounds_size: Vector2) -> bool:
	if _reticle_panel == null:
		_build_visual()
	var spd: float = GameConfig.dvd_reticle_speed_px if GameConfig != null else 320.0
	var norm_dir: Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2(0.7071, 0.7071)
	velocity = norm_dir * spd

	var pos: Vector2 = _reticle_panel.position + velocity * delta
	var max_x: float = maxf(bounds_size.x - RETICLE_SIZE.x, 10.0)
	var max_y: float = maxf(bounds_size.y - RETICLE_SIZE.y, 10.0)
	var bounced_x: bool = false
	var bounced_y: bool = false

	if pos.x <= 0.0:
		pos.x = 0.0
		velocity.x = absf(velocity.x)
		bounced_x = true
	elif pos.x >= max_x:
		pos.x = max_x
		velocity.x = -absf(velocity.x)
		bounced_x = true

	if pos.y <= 0.0:
		pos.y = 0.0
		velocity.y = absf(velocity.y)
		bounced_y = true
	elif pos.y >= max_y:
		pos.y = max_y
		velocity.y = -absf(velocity.y)
		bounced_y = true

	_reticle_panel.position = pos
	if bounced_x and bounced_y:
		_corner_flash_timer = 0.45
		_reticle_panel.modulate = Color(1.0, 0.88, 0.18, 1.0)
	return bounced_x or bounced_y


func get_reticle_screen_center() -> Vector2:
	if _reticle_panel == null:
		return Vector2(640.0, 360.0)
	return _reticle_panel.position + RETICLE_SIZE * 0.5
