@tool
class_name MouseSettingsWidget
extends VBoxContainer

## Reusable Mouse DPI & Sensitivity UI control that reads/writes per-machine settings
## via GameConfig (saved to user://spy_user_settings.cfg so personal DPI never conflicts in Git).

const DPI_PRESETS: Array[int] = [400, 800, 1200, 1600, 2400, 3200]

var _dpi_option: OptionButton
var _sens_slider: HSlider
var _sens_value_label: Label
var _updating_ui: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "Mouse DPI & Sensitivity (Saved Locally)"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 13)
	header.modulate = Color(0.8, 0.85, 0.95)
	add_child(header)

	# Row 1: Hardware DPI Preset
	var dpi_row := HBoxContainer.new()
	dpi_row.add_theme_constant_override("separation", 8)
	add_child(dpi_row)

	var dpi_label := Label.new()
	dpi_label.text = "Mouse DPI:"
	dpi_label.custom_minimum_size = Vector2(95, 0)
	dpi_row.add_child(dpi_label)

	_dpi_option = OptionButton.new()
	_dpi_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(DPI_PRESETS.size()):
		var dpi_val: int = DPI_PRESETS[i]
		var label_text: String = "%d DPI (Standard)" % dpi_val if dpi_val == 800 else "%d DPI" % dpi_val
		_dpi_option.add_item(label_text, dpi_val)
	dpi_row.add_child(_dpi_option)

	# Row 2: Sensitivity Multiplier Slider
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 8)
	add_child(sens_row)

	var sens_label := Label.new()
	sens_label.text = "Sensitivity:"
	sens_label.custom_minimum_size = Vector2(95, 0)
	sens_row.add_child(sens_label)

	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.20
	_sens_slider.max_value = 2.50
	_sens_slider.step = 0.05
	_sens_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sens_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sens_row.add_child(_sens_slider)

	_sens_value_label = Label.new()
	_sens_value_label.custom_minimum_size = Vector2(48, 0)
	_sens_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sens_row.add_child(_sens_value_label)

	_dpi_option.item_selected.connect(_on_dpi_selected)
	_sens_slider.value_changed.connect(_on_sens_slider_changed)

	if not Engine.is_editor_hint() and GameConfig != null:
		GameConfig.mouse_settings_changed.connect(_on_external_mouse_settings_changed)

	refresh_from_config()


func refresh_from_config() -> void:
	if _dpi_option == null or _sens_slider == null:
		return
	_updating_ui = true

	var current_dpi: int = GameConfig.mouse_dpi if GameConfig != null else 800
	var current_mult: float = GameConfig.mouse_sensitivity_multiplier if GameConfig != null else 1.0

	var idx: int = _dpi_option.get_item_index(current_dpi)
	if idx == -1:
		_dpi_option.add_item("%d DPI" % current_dpi, current_dpi)
		idx = _dpi_option.get_item_index(current_dpi)
	_dpi_option.select(idx)

	_sens_slider.value = current_mult
	_sens_value_label.text = "%.2fx" % current_mult

	_updating_ui = false


func _on_dpi_selected(index: int) -> void:
	if _updating_ui or GameConfig == null:
		return
	var selected_dpi: int = _dpi_option.get_item_id(index)
	GameConfig.set_mouse_settings(selected_dpi, _sens_slider.value, true)


func _on_sens_slider_changed(new_value: float) -> void:
	_sens_value_label.text = "%.2fx" % new_value
	if _updating_ui or GameConfig == null:
		return
	var selected_dpi: int = _dpi_option.get_item_id(_dpi_option.selected)
	GameConfig.set_mouse_settings(selected_dpi, new_value, true)


func _on_external_mouse_settings_changed(_effective_sens: float) -> void:
	refresh_from_config()
