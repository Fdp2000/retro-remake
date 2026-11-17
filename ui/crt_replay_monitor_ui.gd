@tool
class_name CRTReplayMonitorUI
extends Control

## Zero-Bandwidth 3.0s CRT Trap-Cam Replay Monitor (Doc 6 §4).
## Maintains a 12 FPS (36-frame, 240x135) local circular image ring buffer and plays it back
## on the trap owner's corner HUD when their trap or Dart Gun hits a rival spy.

const DEFAULT_MAX_FRAMES: int = 36
const CAPTURE_SIZE := Vector2i(240, 135)

var _ring_frames: Array[Image] = []
var _capture_accum: float = 0.0
var _is_playing: bool = false
var _play_elapsed: float = 0.0
var _play_idx: int = 0
var _frozen_frames: Array[Image] = []

var _panel: PanelContainer = null
var _header_label: Label = null
var _texture_rect: TextureRect = null
var _display_tex: ImageTexture = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func _build_layout() -> void:
	if _panel != null:
		return
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -270.0
	_panel.offset_right = -14.0
	_panel.offset_top = 54.0
	_panel.offset_bottom = 228.0
	_panel.modulate = Color(0.82, 1.0, 0.86, 0.96)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_header_label = Label.new()
	_header_label.text = "REC [CRT TRAP-CAM]"
	_header_label.add_theme_font_size_override("font_size", 12)
	_header_label.modulate = Color(1.0, 0.38, 0.32)
	vbox.add_child(_header_label)

	_texture_rect = TextureRect.new()
	_texture_rect.custom_minimum_size = Vector2(240.0, 135.0)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_texture_rect)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return

	var fps: int = GameConfig.crt_replay_fps if GameConfig != null else 12
	var step_sec: float = 1.0 / float(maxi(fps, 1))
	_capture_accum += delta

	if _is_playing:
		_play_elapsed += delta
		var dur: float = GameConfig.crt_replay_duration if GameConfig != null else 3.0
		if _play_elapsed >= dur:
			stop_replay()
			return
		if _capture_accum >= step_sec and not _frozen_frames.is_empty():
			_capture_accum -= step_sec
			_play_idx = (_play_idx + 1) % _frozen_frames.size()
			_show_frame(_frozen_frames[_play_idx])
		return

	if _capture_accum >= step_sec:
		_capture_accum -= step_sec
		capture_viewport_frame()


func capture_viewport_frame() -> void:
	var vp: Viewport = get_viewport()
	if vp == null or vp.get_texture() == null:
		return
	var img: Image = vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	img.resize(CAPTURE_SIZE.x, CAPTURE_SIZE.y, Image.INTERPOLATE_NEAREST)
	push_frame(img)


func push_frame(img: Image) -> void:
	var max_frames: int = GameConfig.crt_replay_frame_count if GameConfig != null else DEFAULT_MAX_FRAMES
	_ring_frames.append(img)
	while _ring_frames.size() > maxi(max_frames, 1):
		_ring_frames.remove_at(0)


func get_buffer_size() -> int:
	return _ring_frames.size()


func is_replaying() -> bool:
	return _is_playing


func trigger_replay(reason: String, victim_peer_id: int) -> void:
	if _panel == null:
		_build_layout()
	if _ring_frames.is_empty():
		var fallback := Image.create(CAPTURE_SIZE.x, CAPTURE_SIZE.y, false, Image.FORMAT_RGB8)
		fallback.fill(Color(0.12, 0.28, 0.16))
		push_frame(fallback)
	_frozen_frames = _ring_frames.duplicate()
	_is_playing = true
	_play_elapsed = 0.0
	_play_idx = 0
	if _header_label != null:
		_header_label.text = "CRT TRAP-CAM — %s HIT SPY %d!" % [reason.to_upper(), victim_peer_id]
	if _panel != null:
		_panel.visible = true
	if not _frozen_frames.is_empty():
		_show_frame(_frozen_frames[0])


func stop_replay() -> void:
	_is_playing = false
	_frozen_frames.clear()
	if _panel != null:
		_panel.visible = false


func _show_frame(img: Image) -> void:
	if _texture_rect == null or img == null:
		return
	if _display_tex == null:
		_display_tex = ImageTexture.create_from_image(img)
		_texture_rect.texture = _display_tex
	else:
		_display_tex.update(img)
