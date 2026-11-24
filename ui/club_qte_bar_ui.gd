@tool
class_name ClubQTEBarUI
extends Control

## Two-Handed Club Charge QTE Bar (Doc 5 §2.B).
## Fills over 2.71s with randomized 9% Green Sweet-Spot (55%–75%) and 100% Overcharge penalty.

const BAR_SIZE := Vector2(320.0, 24.0)

var charge_ratio: float = 0.0
var charge_elapsed: float = 0.0
var green_start: float = 0.60
var green_width: float = 0.09
var is_charging: bool = false

var _bar_container: PanelContainer = null
var _track_bg: ColorRect = null
var _green_zone: ColorRect = null
var _overcharge_cap: ColorRect = null
var _cursor_rect: ColorRect = null
var _outcome_label: Label = null
var _toast_timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_visual()


func _build_visual() -> void:
	if _bar_container != null:
		return
	_bar_container = PanelContainer.new()
	_bar_container.anchor_left = 0.5
	_bar_container.anchor_right = 0.5
	_bar_container.anchor_top = 0.72
	_bar_container.anchor_bottom = 0.72
	_bar_container.offset_left = -BAR_SIZE.x * 0.5
	_bar_container.offset_right = BAR_SIZE.x * 0.5
	_bar_container.offset_top = 0.0
	_bar_container.offset_bottom = BAR_SIZE.y + 8.0
	_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_container.visible = false
	add_child(_bar_container)

	_track_bg = ColorRect.new()
	_track_bg.custom_minimum_size = BAR_SIZE
	_track_bg.color = Color(0.18, 0.20, 0.24, 0.92)
	_track_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_container.add_child(_track_bg)

	_green_zone = ColorRect.new()
	_green_zone.color = Color(0.22, 0.88, 0.34, 0.95)
	_green_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track_bg.add_child(_green_zone)

	_overcharge_cap = ColorRect.new()
	_overcharge_cap.color = Color(0.92, 0.20, 0.18, 0.95)
	_overcharge_cap.position = Vector2(BAR_SIZE.x * 0.94, 0.0)
	_overcharge_cap.size = Vector2(BAR_SIZE.x * 0.06, BAR_SIZE.y)
	_overcharge_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track_bg.add_child(_overcharge_cap)

	_cursor_rect = ColorRect.new()
	_cursor_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_cursor_rect.size = Vector2(6.0, BAR_SIZE.y + 4.0)
	_cursor_rect.position = Vector2(0.0, -2.0)
	_cursor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track_bg.add_child(_cursor_rect)

	_outcome_label = Label.new()
	_outcome_label.anchor_left = 0.5
	_outcome_label.anchor_right = 0.5
	_outcome_label.anchor_top = 0.66
	_outcome_label.anchor_bottom = 0.66
	_outcome_label.offset_left = -180.0
	_outcome_label.offset_right = 180.0
	_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_label.add_theme_font_size_override("font_size", 18)
	_outcome_label.visible = false
	_outcome_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_outcome_label)


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and _outcome_label != null:
			_outcome_label.visible = false


func begin_charge(fixed_green_start: float = -1.0) -> void:
	if _bar_container == null:
		_build_visual()
	var min_s: float = GameConfig.club_green_zone_min_start if GameConfig != null else 0.55
	var max_s: float = GameConfig.club_green_zone_max_start if GameConfig != null else 0.75
	green_width = GameConfig.club_green_zone_width if GameConfig != null else 0.09
	green_start = clampf(fixed_green_start, 0.0, 0.90) if fixed_green_start >= 0.0 else randf_range(min_s, max_s)
	charge_ratio = 0.0
	charge_elapsed = 0.0
	is_charging = true

	_green_zone.position = Vector2(green_start * BAR_SIZE.x, 0.0)
	_green_zone.size = Vector2(green_width * BAR_SIZE.x, BAR_SIZE.y)
	_cursor_rect.position.x = 0.0
	_bar_container.visible = true


func get_charge_to_green_progress() -> float:
	if not is_charging:
		return 1.0
	return clampf(charge_ratio / maxf(green_start * 0.5, 0.001), 0.0, 1.0)


func update_charge(delta: float) -> String:
	if not is_charging:
		return "IDLE"
	var fill_dur: float = GameConfig.club_charge_fill_duration if GameConfig != null else 2.71
	charge_elapsed += delta
	charge_ratio = clampf(charge_elapsed / maxf(fill_dur, 0.1), 0.0, 1.0)
	if _cursor_rect != null:
		_cursor_rect.position.x = clampf(charge_ratio * (BAR_SIZE.x - 6.0), 0.0, BAR_SIZE.x - 6.0)
	if charge_ratio >= 1.0:
		is_charging = false
		if _bar_container != null:
			_bar_container.visible = false
		return "OVERCHARGED"
	return "CHARGING"


func evaluate_release() -> String:
	is_charging = false
	if _bar_container != null:
		_bar_container.visible = false
	var tap_thresh: float = GameConfig.club_quick_tap_threshold if GameConfig != null else 0.20
	if charge_elapsed < tap_thresh:
		return "FEINT"
	if charge_ratio >= 1.0:
		return "OVERCHARGE"
	if charge_ratio >= green_start and charge_ratio <= (green_start + green_width):
		return "KO_SLAM"
	return "WHIFF"


func cancel_charge() -> void:
	is_charging = false
	charge_ratio = 0.0
	charge_elapsed = 0.0
	if _bar_container != null:
		_bar_container.visible = false


func show_outcome(text_val: String, tint: Color) -> void:
	if _outcome_label == null:
		_build_visual()
	_outcome_label.text = text_val
	_outcome_label.modulate = tint
	_outcome_label.visible = true
	_toast_timer = 1.15
