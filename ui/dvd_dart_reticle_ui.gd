@tool
class_name DVDDartReticleUI
extends Control

## Bouncing DVD-Logo Crosshair for the 1-Shot DVD Dart Gun (Doc 4 §3.5).
## Glides across the viewport at 384 px/s, bouncing off screen edges and flashing gold on corner hits.

const RETICLE_SIZE := Vector2(48.0, 48.0)
const COOLDOWN_SIZE := Vector2(44.0, 44.0)
const DEFAULT_RETICLE_COLOR := Color(0.84, 0.40, 1.0, 0.96)
const CORNER_FLASH_COLOR := Color(1.0, 0.88, 0.18, 1.0)
const COOLDOWN_ARC_COLOR := Color(0.88, 0.46, 1.0, 0.96)
const COOLDOWN_FILL_COLOR := Color(0.84, 0.40, 1.0, 0.24)
const COOLDOWN_TRACK_COLOR := Color(0.22, 0.14, 0.30, 0.58)
const OUTLINE_COLOR := Color(0.05, 0.03, 0.08, 0.88)

class CrosshairGraphic extends Control:
	var reticle_color: Color = DEFAULT_RETICLE_COLOR

	func set_reticle_color(c: Color) -> void:
		if reticle_color.is_equal_approx(c):
			return
		reticle_color = c
		queue_redraw()

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var inner_gap: float = 5.5
		var outer_len: float = 15.0
		var ring_radius: float = 11.0
		var dot_color := Color(1.0, 0.97, 1.0, 0.98)

		# Dark outline pass so the crosshair stays readable over bright and dark surfaces
		draw_arc(center, ring_radius, 0.0, TAU, 32, OUTLINE_COLOR, 3.6, true)
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(center + dir * inner_gap, center + dir * outer_len, OUTLINE_COLOR, 4.0, true)
		draw_circle(center, 3.2, OUTLINE_COLOR, true, -1.0, true)

		# Colored crosshair ring, cardinal ticks, and crisp center dot
		draw_arc(center, ring_radius, 0.0, TAU, 32, reticle_color, 1.8, true)
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(center + dir * inner_gap, center + dir * outer_len, reticle_color, 2.0, true)
		draw_circle(center, 1.9, dot_color, true, -1.0, true)


class CooldownCircleGraphic extends Control:
	var ratio: float = 0.0

	func set_ratio(new_ratio: float) -> void:
		var clamped: float = clampf(new_ratio, 0.0, 1.0)
		if is_equal_approx(ratio, clamped):
			return
		ratio = clamped
		queue_redraw()

	func _draw() -> void:
		if ratio <= 0.001:
			return
		var center: Vector2 = size * 0.5
		var radius: float = 14.0

		draw_circle(center, radius + 3.0, Color(0.05, 0.03, 0.08, 0.70), true, -1.0, true)
		draw_arc(center, radius, 0.0, TAU, 40, COOLDOWN_TRACK_COLOR, 4.0, true)

		var start_angle: float = -PI * 0.5
		var sweep_angle: float = TAU * ratio
		var steps: int = maxi(int(ceil(ratio * 32.0)), 2)
		var fan := PackedVector2Array()
		fan.append(center)
		for i in range(steps + 1):
			var a: float = start_angle + sweep_angle * (float(i) / float(steps))
			fan.append(center + Vector2(cos(a), sin(a)) * (radius - 2.0))
		draw_colored_polygon(fan, COOLDOWN_FILL_COLOR)

		draw_arc(center, radius, start_angle, start_angle + sweep_angle, maxi(steps + 8, 12), OUTLINE_COLOR, 6.0, true)
		draw_arc(center, radius, start_angle, start_angle + sweep_angle, maxi(steps + 8, 12), COOLDOWN_ARC_COLOR, 3.6, true)


var velocity: Vector2 = Vector2(226.27, 226.27)
var _reticle_graphic: CrosshairGraphic = null
var _cooldown_graphic: CooldownCircleGraphic = null
var _corner_flash_timer: float = 0.0
var is_reticle_active: bool = false
var _cooldown_ratio: float = 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_visual()


func _build_visual() -> void:
	if _reticle_graphic == null:
		_reticle_graphic = CrosshairGraphic.new()
		_reticle_graphic.name = "DVDReticleCrosshair"
		_reticle_graphic.size = RETICLE_SIZE
		_reticle_graphic.custom_minimum_size = RETICLE_SIZE
		_reticle_graphic.position = Vector2(220.0, 160.0)
		_reticle_graphic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_reticle_graphic.set_reticle_color(DEFAULT_RETICLE_COLOR)
		_reticle_graphic.visible = is_reticle_active
		add_child(_reticle_graphic)
	if _cooldown_graphic == null:
		_cooldown_graphic = CooldownCircleGraphic.new()
		_cooldown_graphic.name = "DartAimCooldownCircle"
		_cooldown_graphic.size = COOLDOWN_SIZE
		_cooldown_graphic.custom_minimum_size = COOLDOWN_SIZE
		_cooldown_graphic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cooldown_graphic.visible = false
		add_child(_cooldown_graphic)


func _refresh_visibility() -> void:
	var cd_active: bool = _cooldown_ratio > 0.001
	if _reticle_graphic != null:
		_reticle_graphic.visible = is_reticle_active
	if _cooldown_graphic != null:
		_cooldown_graphic.visible = cd_active
	visible = is_reticle_active or cd_active


func set_active(active: bool) -> void:
	var was_active: bool = is_reticle_active
	is_reticle_active = active
	if active and _reticle_graphic == null:
		_build_visual()
	if active and not was_active:
		_randomize_spawn()
	_refresh_visibility()


func set_aim_cooldown(remaining: float, duration: float, screen_center_pos: Vector2) -> void:
	if _cooldown_graphic == null:
		_build_visual()
	var safe_dur: float = maxf(duration, 0.001)
	_cooldown_ratio = clampf(remaining / safe_dur, 0.0, 1.0) if remaining > 0.0 else 0.0
	if _cooldown_graphic != null:
		_cooldown_graphic.set_ratio(_cooldown_ratio)
		if _cooldown_ratio > 0.001:
			var bounds: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280.0, 720.0)
			if bounds.x < 100.0 or bounds.y < 100.0:
				bounds = Vector2(1280.0, 720.0)
			var top_left: Vector2 = screen_center_pos - COOLDOWN_SIZE * 0.5
			top_left.x = clampf(top_left.x, 12.0, maxf(bounds.x - COOLDOWN_SIZE.x - 12.0, 12.0))
			top_left.y = clampf(top_left.y, 12.0, maxf(bounds.y - COOLDOWN_SIZE.y - 12.0, 12.0))
			_cooldown_graphic.position = top_left
	_refresh_visibility()


func _randomize_spawn() -> void:
	if _reticle_graphic == null:
		return
	var bounds: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280.0, 720.0)
	if bounds.x < 100.0 or bounds.y < 100.0:
		bounds = Vector2(1280.0, 720.0)
	var max_x: float = maxf(bounds.x - RETICLE_SIZE.x, 10.0)
	var max_y: float = maxf(bounds.y - RETICLE_SIZE.y, 10.0)
	_reticle_graphic.position = Vector2(randf_range(0.0, max_x), randf_range(0.0, max_y))
	var spd: float = GameConfig.dvd_reticle_speed_px if GameConfig != null else 384.0
	var sx: float = -1.0 if randi() % 2 == 0 else 1.0
	var sy: float = -1.0 if randi() % 2 == 0 else 1.0
	velocity = Vector2(sx, sy).normalized() * spd
	_corner_flash_timer = 0.0
	_reticle_graphic.set_reticle_color(DEFAULT_RETICLE_COLOR)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_reticle_active or not visible:
		return
	var bounds: Vector2 = get_viewport_rect().size
	if bounds.x < 100.0 or bounds.y < 100.0:
		bounds = Vector2(1280.0, 720.0)
	step_bounce(delta, bounds)

	if _corner_flash_timer > 0.0:
		_corner_flash_timer -= delta
		if _corner_flash_timer <= 0.0 and _reticle_graphic != null:
			_reticle_graphic.set_reticle_color(DEFAULT_RETICLE_COLOR)


func step_bounce(delta: float, bounds_size: Vector2) -> bool:
	if _reticle_graphic == null:
		_build_visual()
	var spd: float = GameConfig.dvd_reticle_speed_px if GameConfig != null else 384.0
	var norm_dir: Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2(0.7071, 0.7071)
	velocity = norm_dir * spd

	var pos: Vector2 = _reticle_graphic.position + velocity * delta
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

	_reticle_graphic.position = pos
	if bounced_x and bounced_y:
		_corner_flash_timer = 0.45
		_reticle_graphic.set_reticle_color(CORNER_FLASH_COLOR)
	return bounced_x or bounced_y


func get_reticle_screen_center() -> Vector2:
	if _reticle_graphic == null:
		return Vector2(640.0, 360.0)
	return _reticle_graphic.position + RETICLE_SIZE * 0.5
