class_name MainMenuOptionsUI
extends CanvasLayer

## Main Menu Options modal with Controls (DPI & Sensitivity) and Sound
## (Master, Music, Voice Chat volumes, Recording Device selector, and live Mic Test bar).

const MOUSE_SETTINGS_SCRIPT = preload("res://ui/mouse_settings_widget.gd")

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _tabs: TabContainer = null

var _master_slider: HSlider = null
var _master_val_lbl: Label = null
var _music_slider: HSlider = null
var _music_val_lbl: Label = null
var _voice_slider: HSlider = null
var _voice_val_lbl: Label = null
var _device_opt: OptionButton = null
var _mic_meter_fill: ColorRect = null
var _mic_status_lbl: Label = null
var _fullscreen_chk: CheckButton = null
var _fps_counter_chk: CheckButton = null

var _updating_ui: bool = false
var _smoothed_mic: float = 0.0


func _ready() -> void:
	layer = 50
	visible = false
	_build_ui()


func open_options() -> void:
	_build_ui()
	_refresh_devices()
	_sync_from_config()
	visible = true


func close_options() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible or _mic_meter_fill == null:
		return
	var raw_level: float = 0.0
	if VoiceChatManager != null and VoiceChatManager.has_method("get_live_mic_level"):
		raw_level = float(VoiceChatManager.call("get_live_mic_level"))
	# Boost low speech levels slightly so normal speaking is clearly visible on the bar
	var display_level: float = clampf(pow(raw_level, 0.65) * 1.35, 0.0, 1.0)
	if display_level > _smoothed_mic:
		_smoothed_mic = lerpf(_smoothed_mic, display_level, clampf(delta * 24.0, 0.0, 1.0))
	else:
		_smoothed_mic = lerpf(_smoothed_mic, display_level, clampf(delta * 8.0, 0.0, 1.0))

	_mic_meter_fill.anchor_right = _smoothed_mic
	if _smoothed_mic > 0.85:
		_mic_meter_fill.color = Color(0.95, 0.32, 0.28, 1.0)
	elif _smoothed_mic > 0.55:
		_mic_meter_fill.color = Color(0.95, 0.82, 0.30, 1.0)
	else:
		_mic_meter_fill.color = Color(0.35, 0.92, 0.52, 1.0)

	if _mic_status_lbl != null:
		if _smoothed_mic > 0.04:
			_mic_status_lbl.text = "Microphone signal detected"
			_mic_status_lbl.modulate = Color(0.55, 0.95, 0.65)
		else:
			_mic_status_lbl.text = "Speak into your mic to test input level"
			_mic_status_lbl.modulate = Color(0.75, 0.80, 0.85)


func _build_ui() -> void:
	if _panel != null:
		return

	_backdrop = ColorRect.new()
	_backdrop.name = "OptionsBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.03, 0.04, 0.05, 0.74)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_options()
	)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "OptionsWindow"
	_panel.custom_minimum_size = Vector2(520.0, 380.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12, 0.97)
	style.border_color = Color(0.32, 0.44, 0.38, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	style.shadow_size = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(root_vbox)

	var header := HBoxContainer.new()
	root_vbox.add_child(header)

	var title := Label.new()
	title.text = "OPTIONS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color(0.88, 0.94, 0.90)
	header.add_child(title)

	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.custom_minimum_size = Vector2(30, 28)
	x_btn.pressed.connect(close_options)
	header.add_child(x_btn)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_tabs)

	# Tab 1: Display
	var display_tab := MarginContainer.new()
	display_tab.name = "Display"
	display_tab.add_theme_constant_override("margin_top", 12)
	display_tab.add_theme_constant_override("margin_left", 10)
	display_tab.add_theme_constant_override("margin_right", 10)
	_tabs.add_child(display_tab)

	var display_vbox := VBoxContainer.new()
	display_vbox.add_theme_constant_override("separation", 10)
	display_tab.add_child(display_vbox)

	_fullscreen_chk = _create_styled_toggle(display_vbox, "Fullscreen", _on_fullscreen_toggled)
	_fps_counter_chk = _create_styled_toggle(display_vbox, "Show FPS Counter", _on_fps_counter_toggled)

	# Tab 2: Controls
	var controls_tab := VBoxContainer.new()
	controls_tab.name = "Controls"
	controls_tab.add_theme_constant_override("separation", 12)
	_tabs.add_child(controls_tab)

	var controls_pad := MarginContainer.new()
	controls_pad.add_theme_constant_override("margin_top", 12)
	controls_pad.add_theme_constant_override("margin_left", 10)
	controls_pad.add_theme_constant_override("margin_right", 10)
	controls_tab.add_child(controls_pad)

	var mouse_widget: VBoxContainer = MOUSE_SETTINGS_SCRIPT.new()
	mouse_widget.name = "MouseSettingsWidget"
	controls_pad.add_child(mouse_widget)

	# Tab 2: Sound
	var sound_tab := MarginContainer.new()
	sound_tab.name = "Sound"
	sound_tab.add_theme_constant_override("margin_top", 12)
	sound_tab.add_theme_constant_override("margin_left", 10)
	sound_tab.add_theme_constant_override("margin_right", 10)
	_tabs.add_child(sound_tab)

	var sound_vbox := VBoxContainer.new()
	sound_vbox.add_theme_constant_override("separation", 10)
	sound_tab.add_child(sound_vbox)

	var master_refs: Array = _add_volume_row(sound_vbox, "Master Volume:")
	_master_slider = master_refs[0] as HSlider
	_master_val_lbl = master_refs[1] as Label
	_master_slider.value_changed.connect(_on_volume_changed)

	var music_refs: Array = _add_volume_row(sound_vbox, "Music Volume:")
	_music_slider = music_refs[0] as HSlider
	_music_val_lbl = music_refs[1] as Label
	_music_slider.value_changed.connect(_on_volume_changed)

	var voice_refs: Array = _add_volume_row(sound_vbox, "Voice Chat:")
	_voice_slider = voice_refs[0] as HSlider
	_voice_val_lbl = voice_refs[1] as Label
	_voice_slider.value_changed.connect(_on_volume_changed)

	sound_vbox.add_child(HSeparator.new())

	var dev_row := HBoxContainer.new()
	dev_row.add_theme_constant_override("separation", 8)
	sound_vbox.add_child(dev_row)

	var dev_lbl := Label.new()
	dev_lbl.text = "Recording Device:"
	dev_lbl.custom_minimum_size = Vector2(130, 0)
	dev_row.add_child(dev_lbl)

	_device_opt = OptionButton.new()
	_device_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_device_opt.clip_text = true
	_device_opt.item_selected.connect(_on_device_selected)
	dev_row.add_child(_device_opt)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_devices)
	dev_row.add_child(refresh_btn)

	var meter_row := HBoxContainer.new()
	meter_row.add_theme_constant_override("separation", 8)
	sound_vbox.add_child(meter_row)

	var meter_lbl := Label.new()
	meter_lbl.text = "Mic Test:"
	meter_lbl.custom_minimum_size = Vector2(130, 0)
	meter_row.add_child(meter_lbl)

	var meter_bg := ColorRect.new()
	meter_bg.custom_minimum_size = Vector2(0, 16)
	meter_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter_bg.color = Color(0.14, 0.17, 0.19, 1.0)
	meter_row.add_child(meter_bg)

	_mic_meter_fill = ColorRect.new()
	_mic_meter_fill.anchor_left = 0.0
	_mic_meter_fill.anchor_top = 0.0
	_mic_meter_fill.anchor_bottom = 1.0
	_mic_meter_fill.anchor_right = 0.0
	_mic_meter_fill.color = Color(0.35, 0.92, 0.52, 1.0)
	meter_bg.add_child(_mic_meter_fill)

	_mic_status_lbl = Label.new()
	_mic_status_lbl.text = "Speak into your mic to test input level"
	_mic_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mic_status_lbl.add_theme_font_size_override("font_size", 11)
	_mic_status_lbl.modulate = Color(0.75, 0.80, 0.85)
	sound_vbox.add_child(_mic_status_lbl)

	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_END
	root_vbox.add_child(close_row)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(100, 32)
	close_btn.pressed.connect(close_options)
	close_row.add_child(close_btn)


func _add_volume_row(parent: VBoxContainer, label_text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(130, 0)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.02
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(46, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	return [slider, val_lbl]


func _refresh_devices() -> void:
	if _device_opt == null:
		return
	_updating_ui = true
	_device_opt.clear()
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	var current: String = GameConfig.audio_input_device if GameConfig != null else AudioServer.get_input_device()
	var select_idx: int = 0
	for i in range(devices.size()):
		var dev_name: String = devices[i]
		_device_opt.add_item(dev_name)
		if dev_name == current:
			select_idx = i
	if _device_opt.item_count > 0:
		_device_opt.select(select_idx)
	_updating_ui = false


func _sync_from_config() -> void:
	_updating_ui = true
	var m_vol: float = GameConfig.master_volume if GameConfig != null else 1.0
	var mu_vol: float = GameConfig.music_volume if GameConfig != null else 1.0
	var v_vol: float = GameConfig.voice_volume if GameConfig != null else 1.0

	_master_slider.value = m_vol
	_master_val_lbl.text = "%d%%" % roundi(m_vol * 100.0)
	_music_slider.value = mu_vol
	_music_val_lbl.text = "%d%%" % roundi(mu_vol * 100.0)
	_voice_slider.value = v_vol
	_voice_val_lbl.text = "%d%%" % roundi(v_vol * 100.0)
	if _fullscreen_chk != null:
		var is_fs: bool = GameConfig.fullscreen_enabled if GameConfig != null else (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
		_fullscreen_chk.set_pressed_no_signal(is_fs)
	if _fps_counter_chk != null:
		var show_fps: bool = GameConfig.show_fps_counter if GameConfig != null else false
		_fps_counter_chk.set_pressed_no_signal(show_fps)
	_updating_ui = false


func _create_styled_toggle(parent: VBoxContainer, label_text: String, callback: Callable) -> CheckButton:
	var row_panel := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.14, 0.19, 0.21, 1.0)
	row_style.border_color = Color(0.32, 0.48, 0.42, 0.9)
	row_style.set_border_width_all(1)
	row_style.set_corner_radius_all(6)
	row_style.set_content_margin_all(8)
	row_panel.add_theme_stylebox_override("panel", row_style)
	parent.add_child(row_panel)

	var chk := CheckButton.new()
	chk.text = label_text
	chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chk.toggled.connect(callback)
	row_panel.add_child(chk)
	return chk


func _on_fullscreen_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if GameConfig != null and GameConfig.has_method("set_fullscreen_enabled"):
		GameConfig.set_fullscreen_enabled(pressed, true)
	elif not Engine.is_editor_hint():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED)


func _on_fps_counter_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if GameConfig != null and GameConfig.has_method("set_show_fps_counter"):
		GameConfig.set_show_fps_counter(pressed, true)


func _on_volume_changed(_val: float) -> void:
	if _master_val_lbl != null:
		_master_val_lbl.text = "%d%%" % roundi(_master_slider.value * 100.0)
	if _music_val_lbl != null:
		_music_val_lbl.text = "%d%%" % roundi(_music_slider.value * 100.0)
	if _voice_val_lbl != null:
		_voice_val_lbl.text = "%d%%" % roundi(_voice_slider.value * 100.0)
	if _updating_ui or GameConfig == null:
		return
	GameConfig.set_audio_settings(_master_slider.value, _music_slider.value, _voice_slider.value, GameConfig.audio_input_device, true)


func _on_device_selected(index: int) -> void:
	if _updating_ui or _device_opt == null or index < 0 or index >= _device_opt.item_count:
		return
	var dev_name: String = _device_opt.get_item_text(index)
	if VoiceChatManager != null and VoiceChatManager.has_method("set_input_device"):
		VoiceChatManager.call("set_input_device", dev_name)
	else:
		AudioServer.set_input_device(dev_name)
	if GameConfig != null:
		GameConfig.set_audio_settings(_master_slider.value, _music_slider.value, _voice_slider.value, dev_name, true)
