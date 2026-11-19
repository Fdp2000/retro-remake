@tool
class_name MatchEndOverlayUI
extends Control

## Match Result Summary Overlay & In-Game Rematch / Mode-Switch Controls (J5).

signal rematch_requested()
signal switch_mode_requested()
signal return_to_lobby_requested()

var last_winner_peer_id: int = 0
var last_reason: String = ""
var last_outcome_kind: String = "" # "VICTORY", "DEFEAT", or "DRAW"

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _meta_label: Label = null
var _rematch_button: Button = null
var _switch_mode_button: Button = null
var _lobby_button: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	visible = false


func _build_layout() -> void:
	if _panel != null:
		return

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.03, 0.04, 0.05, 0.72)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "MatchEndPanel"
	_panel.custom_minimum_size = Vector2(460.0, 290.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.13, 0.96)
	style.border_color = Color(0.32, 0.42, 0.36, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	style.shadow_size = 10
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "MATCH ENDED"
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.text = ""
	_subtitle_label.add_theme_font_size_override("font_size", 15)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_subtitle_label)

	_meta_label = Label.new()
	_meta_label.text = ""
	_meta_label.add_theme_font_size_override("font_size", 13)
	_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_label.modulate = Color(0.75, 0.80, 0.85)
	vbox.add_child(_meta_label)

	vbox.add_child(HSeparator.new())

	_rematch_button = Button.new()
	_rematch_button.name = "RematchButton"
	_rematch_button.text = "Rematch — New Seed"
	_rematch_button.pressed.connect(func() -> void: rematch_requested.emit())
	vbox.add_child(_rematch_button)

	_switch_mode_button = Button.new()
	_switch_mode_button.name = "SwitchModeButton"
	_switch_mode_button.text = "Switch to Dev Sandbox Gym"
	_switch_mode_button.pressed.connect(func() -> void: switch_mode_requested.emit())
	vbox.add_child(_switch_mode_button)

	_lobby_button = Button.new()
	_lobby_button.name = "ReturnToLobbyButton"
	_lobby_button.text = "Return to Lobby"
	_lobby_button.pressed.connect(func() -> void: return_to_lobby_requested.emit())
	vbox.add_child(_lobby_button)


func show_match_result(
	winner_peer_id: int,
	local_peer_id: int,
	reason: String,
	is_host: bool,
	is_sandbox: bool,
	match_seed: int
) -> void:
	_build_layout()
	last_winner_peer_id = winner_peer_id
	last_reason = reason

	if winner_peer_id == 0:
		last_outcome_kind = "DRAW"
		_title_label.text = "MUTUAL LOSS — TIME EXPIRED"
		_title_label.modulate = Color(1.0, 0.72, 0.25)
	elif winner_peer_id == local_peer_id:
		last_outcome_kind = "VICTORY"
		_title_label.text = "MISSION ACCOMPLISHED — VICTORY!"
		_title_label.modulate = Color(0.35, 0.95, 0.48)
	else:
		last_outcome_kind = "DEFEAT"
		_title_label.text = "MISSION FAILED — RIVAL ESCAPED!"
		_title_label.modulate = Color(0.95, 0.35, 0.42)

	_subtitle_label.text = reason
	_meta_label.text = "Mode: %s   |   Match Seed: #%d" % [
		"Dev Sandbox Gym" if is_sandbox else "Full Embassy Match",
		match_seed
	]

	if is_host:
		_rematch_button.text = "Rematch — New Seed"
		_rematch_button.disabled = false
		_switch_mode_button.visible = true
		_switch_mode_button.disabled = false
		_switch_mode_button.text = (
			"Switch to Full Match (Seeded Embassy)"
			if is_sandbox
			else "Switch to Dev Sandbox Gym"
		)
	else:
		_rematch_button.text = "Waiting for Host to start Rematch..."
		_rematch_button.disabled = true
		_switch_mode_button.visible = false

	visible = true


func hide_overlay() -> void:
	visible = false
