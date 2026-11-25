class_name KoRadialUI
extends Control

## Centered radial countdown indicator shown over the player's crosshair while KOed.
## Styled after DVDDartReticleUI's radial cooldown indicator, in monochrome white.

const CIRCLE_RADIUS: float = 9.0
const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.50)
const TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.18)
const FILL_COLOR := Color(1.0, 1.0, 1.0, 0.28)
const ARC_COLOR := Color(1.0, 1.0, 1.0, 0.96)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)

var _ratio: float = 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_ko_progress(remaining: float, duration: float) -> void:
	var next_ratio: float = 0.0
	if remaining > 0.0 and duration > 0.001:
		next_ratio = clampf(remaining / duration, 0.0, 1.0)
	var should_show: bool = next_ratio > 0.001
	if visible != should_show:
		visible = should_show
		if should_show:
			queue_redraw()
	if not is_equal_approx(_ratio, next_ratio):
		_ratio = next_ratio
		if should_show:
			queue_redraw()


func _draw() -> void:
	if _ratio <= 0.001:
		return
	var center: Vector2 = size * 0.5

	draw_circle(center, CIRCLE_RADIUS + 2.0, BACKDROP_COLOR, true, -1.0, true)
	draw_arc(center, CIRCLE_RADIUS, 0.0, TAU, 36, TRACK_COLOR, 2.5, true)

	var start_angle: float = -PI * 0.5
	var sweep_angle: float = TAU * _ratio
	var steps: int = maxi(int(ceil(_ratio * 28.0)), 2)
	var fan := PackedVector2Array()
	fan.append(center)
	for i in range(steps + 1):
		var a: float = start_angle + sweep_angle * (float(i) / float(steps))
		fan.append(center + Vector2(cos(a), sin(a)) * (CIRCLE_RADIUS - 1.5))
	draw_colored_polygon(fan, FILL_COLOR)

	draw_arc(center, CIRCLE_RADIUS, start_angle, start_angle + sweep_angle, maxi(steps + 8, 12), OUTLINE_COLOR, 4.2, true)
	draw_arc(center, CIRCLE_RADIUS, start_angle, start_angle + sweep_angle, maxi(steps + 8, 12), ARC_COLOR, 2.4, true)
