class_name CRTReplayDebugUI
extends CanvasLayer

## Lightweight F10 in-game debug overlay for testing and tuning the CRT Trap-Cam Replay
## (capture resolution, bezel scale, FPS, duration, solo self-rig test, and back-to-back queueing).

const TRAP_OF_THE_GAME_UI_SCRIPT = preload("res://ui/trap_of_the_game_ui.gd")
const REASONS: Array[String] = ["SPRING", "BOMB", "BUCKET", "TRIPWIRE", "DART_GUN"]
const CAPTURE_PRESETS: Array[Vector2i] = [
	Vector2i(240, 135),
	Vector2i(320, 180),
	Vector2i(426, 240),
]
const DISPLAY_PRESETS: Array[Vector2] = [
	Vector2(288.0, 162.0),
	Vector2(384.0, 216.0),
	Vector2(480.0, 270.0),
	Vector2(576.0, 324.0),
]
const FPS_PRESETS: Array[int] = [8, 12, 15, 24]

var _owner_player: Node = null
var _crt_ui: CRTReplayMonitorUI = null
var _debug_totg_ui: TrapOfTheGameUI = null
var _panel: PanelContainer = null

var _self_rig_chk: CheckBox = null
var _target_opt: OptionButton = null
var _reason_opt: OptionButton = null
var _res_opt: OptionButton = null
var _scale_opt: OptionButton = null
var _fps_opt: OptionButton = null
var _dur_spin: SpinBox = null
var _post_spin: SpinBox = null
var _status_lbl: Label = null

var _is_syncing_ui: bool = false
var _refresh_accum: float = 0.0
var _tracked_ids_cache: Array[int] = []


func setup(player_node: Node, crt_ui: CRTReplayMonitorUI) -> void:
	_owner_player = player_node
	_crt_ui = crt_ui
	layer = 41
	visible = false
	_build_ui()


func set_crt_ui(crt_ui: CRTReplayMonitorUI) -> void:
	_crt_ui = crt_ui


func toggle_open() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if _panel == null:
		_build_ui()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Auto-enable solo self-rig when no remote rivals are present so solo testing in test_gym works out of the box
	if _crt_ui != null and _crt_ui.get_tracked_rival_ids().is_empty() and not _crt_ui.is_debug_include_self():
		_crt_ui.set_debug_include_self(true)
	_sync_controls_from_config()
	_refresh_target_options()
	_refresh_status()


func close_panel() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= 0.12:
		_refresh_accum = 0.0
		_refresh_target_options()
		_refresh_status()


func _build_ui() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "CRTReplayDebugPanel"
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 14.0
	_panel.offset_top = 56.0
	_panel.offset_right = 356.0
	_panel.offset_bottom = 520.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.11, 0.94)
	style.border_color = Color(0.28, 0.62, 0.42, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "CRT Trap-Cam Debugger [F10]"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.55, 0.95, 0.68)
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(26, 24)
	close_btn.pressed.connect(close_panel)
	header.add_child(close_btn)

	_self_rig_chk = CheckBox.new()
	_self_rig_chk.text = "Include Self Rig (Solo Test)"
	_self_rig_chk.toggled.connect(_on_self_rig_toggled)
	vbox.add_child(_self_rig_chk)

	# Target & Reason
	var tgt_row := HBoxContainer.new()
	vbox.add_child(tgt_row)
	var tgt_lbl := Label.new()
	tgt_lbl.text = "Target Rig:"
	tgt_lbl.custom_minimum_size = Vector2(92, 0)
	tgt_row.add_child(tgt_lbl)
	_target_opt = OptionButton.new()
	_target_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tgt_row.add_child(_target_opt)

	var rsn_row := HBoxContainer.new()
	vbox.add_child(rsn_row)
	var rsn_lbl := Label.new()
	rsn_lbl.text = "Trap Reason:"
	rsn_lbl.custom_minimum_size = Vector2(92, 0)
	rsn_row.add_child(rsn_lbl)
	_reason_opt = OptionButton.new()
	_reason_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in REASONS:
		_reason_opt.add_item(r)
	rsn_row.add_child(_reason_opt)

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	var trig_btn := Button.new()
	trig_btn.text = "Trigger Replay"
	trig_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trig_btn.pressed.connect(_on_trigger_pressed)
	btn_row.add_child(trig_btn)

	var b2b_btn := Button.new()
	b2b_btn.text = "Back-to-Back (x2)"
	b2b_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b2b_btn.pressed.connect(_on_back_to_back_pressed)
	btn_row.add_child(b2b_btn)

	var stop_btn := Button.new()
	stop_btn.text = "Stop & Clear Replay Queue"
	stop_btn.pressed.connect(_on_stop_pressed)
	vbox.add_child(stop_btn)

	var totg_row := HBoxContainer.new()
	totg_row.add_theme_constant_override("separation", 6)
	vbox.add_child(totg_row)

	var arch_btn := Button.new()
	arch_btn.text = "+ Archive Clip"
	arch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arch_btn.pressed.connect(_on_archive_clip_pressed)
	totg_row.add_child(arch_btn)

	var totg_btn := Button.new()
	totg_btn.text = "Play Trap of the Game"
	totg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	totg_btn.pressed.connect(_on_play_totg_pressed)
	totg_row.add_child(totg_btn)

	var clr_arch_btn := Button.new()
	clr_arch_btn.text = "Clr"
	clr_arch_btn.pressed.connect(_on_clear_archive_pressed)
	totg_row.add_child(clr_arch_btn)

	vbox.add_child(HSeparator.new())

	# Live Config Controls
	var res_row := HBoxContainer.new()
	vbox.add_child(res_row)
	var res_lbl := Label.new()
	res_lbl.text = "Capture Res:"
	res_lbl.custom_minimum_size = Vector2(92, 0)
	res_row.add_child(res_lbl)
	_res_opt = OptionButton.new()
	_res_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in CAPTURE_PRESETS:
		_res_opt.add_item("%dx%d" % [p.x, p.y])
	_res_opt.item_selected.connect(_on_config_changed)
	res_row.add_child(_res_opt)

	var scl_row := HBoxContainer.new()
	vbox.add_child(scl_row)
	var scl_lbl := Label.new()
	scl_lbl.text = "Bezel Size:"
	scl_lbl.custom_minimum_size = Vector2(92, 0)
	scl_row.add_child(scl_lbl)
	_scale_opt = OptionButton.new()
	_scale_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_opt.add_item("0.75x (288x162)")
	_scale_opt.add_item("1.00x (384x216)")
	_scale_opt.add_item("1.25x (480x270)")
	_scale_opt.add_item("1.50x (576x324)")
	_scale_opt.item_selected.connect(_on_config_changed)
	scl_row.add_child(_scale_opt)

	var fps_row := HBoxContainer.new()
	vbox.add_child(fps_row)
	var fps_lbl := Label.new()
	fps_lbl.text = "Capture FPS:"
	fps_lbl.custom_minimum_size = Vector2(92, 0)
	fps_row.add_child(fps_lbl)
	_fps_opt = OptionButton.new()
	_fps_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for f in FPS_PRESETS:
		_fps_opt.add_item("%d FPS" % f)
	_fps_opt.item_selected.connect(_on_config_changed)
	fps_row.add_child(_fps_opt)

	var dur_row := HBoxContainer.new()
	vbox.add_child(dur_row)
	var dur_lbl := Label.new()
	dur_lbl.text = "Duration (s):"
	dur_lbl.custom_minimum_size = Vector2(92, 0)
	dur_row.add_child(dur_lbl)
	_dur_spin = SpinBox.new()
	_dur_spin.min_value = 1.5
	_dur_spin.max_value = 8.0
	_dur_spin.step = 0.5
	_dur_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dur_spin.value_changed.connect(_on_spin_changed)
	dur_row.add_child(_dur_spin)

	var post_row := HBoxContainer.new()
	vbox.add_child(post_row)
	var post_lbl := Label.new()
	post_lbl.text = "Post-Hit (s):"
	post_lbl.custom_minimum_size = Vector2(92, 0)
	post_row.add_child(post_lbl)
	_post_spin = SpinBox.new()
	_post_spin.min_value = 0.0
	_post_spin.max_value = 3.5
	_post_spin.step = 0.25
	_post_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_post_spin.value_changed.connect(_on_spin_changed)
	post_row.add_child(_post_spin)

	vbox.add_child(HSeparator.new())

	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.modulate = Color(0.82, 0.90, 0.85)
	_status_lbl.text = "Status: Waiting..."
	vbox.add_child(_status_lbl)


func _sync_controls_from_config() -> void:
	_is_syncing_ui = true
	if _self_rig_chk != null and _crt_ui != null:
		_self_rig_chk.button_pressed = _crt_ui.is_debug_include_self()
	if GameConfig != null:
		var cap: Vector2i = GameConfig.crt_viewport_size
		var res_idx: int = CAPTURE_PRESETS.find(cap)
		if res_idx == -1:
			res_idx = 1
		_res_opt.selected = res_idx

		var disp: Vector2 = GameConfig.crt_display_size
		var disp_idx: int = DISPLAY_PRESETS.find(disp)
		if disp_idx == -1:
			disp_idx = 1
		_scale_opt.selected = disp_idx

		var fps_idx: int = FPS_PRESETS.find(GameConfig.crt_replay_fps)
		if fps_idx == -1:
			fps_idx = 1
		_fps_opt.selected = fps_idx

		_dur_spin.value = GameConfig.crt_replay_duration
		_post_spin.value = GameConfig.crt_replay_post_hit_seconds
	_is_syncing_ui = false


func _refresh_target_options() -> void:
	if _target_opt == null or _crt_ui == null:
		return
	var ids: Array[int] = _crt_ui.get_tracked_rival_ids()
	if ids == _tracked_ids_cache and _target_opt.item_count > 0:
		return
	_tracked_ids_cache = ids.duplicate()
	var prev_sel_id: int = _target_opt.get_selected_id()
	_target_opt.clear()
	if ids.is_empty():
		_target_opt.add_item("Standby (No Rigs)", 0)
		return
	var owner_id: int = _owner_player.name.to_int() if _owner_player != null and _owner_player.name.is_valid_int() else 0
	var select_idx: int = 0
	for i in range(ids.size()):
		var rid: int = ids[i]
		var label: String = "Self (%d)" % rid if (owner_id != 0 and rid == owner_id) else "Rival %d" % rid
		_target_opt.add_item(label, rid)
		if rid == prev_sel_id:
			select_idx = i
	_target_opt.selected = select_idx


func _get_selected_target_id() -> int:
	if _target_opt == null or _target_opt.item_count == 0:
		return 0
	return _target_opt.get_selected_id()


func _get_selected_reason() -> String:
	if _reason_opt == null or _reason_opt.selected < 0 or _reason_opt.selected >= REASONS.size():
		return "SPRING"
	return REASONS[_reason_opt.selected]


func _on_self_rig_toggled(pressed: bool) -> void:
	if _is_syncing_ui or _crt_ui == null:
		return
	_crt_ui.set_debug_include_self(pressed)
	_refresh_target_options()
	_refresh_status()


func _on_trigger_pressed() -> void:
	if _crt_ui == null:
		return
	var target_id: int = _get_selected_target_id()
	var reason: String = _get_selected_reason()
	_crt_ui.trigger_replay(reason, target_id)
	if AudioBridge != null:
		AudioBridge.play_local_cue("crt_static")
	_refresh_status()


func _on_back_to_back_pressed() -> void:
	if _crt_ui == null:
		return
	var target_id: int = _get_selected_target_id()
	var first_reason: String = _get_selected_reason()
	var second_reason: String = "BOMB" if first_reason != "BOMB" else "TRIPWIRE"
	var second_target: int = target_id
	if _tracked_ids_cache.size() > 1:
		for rid in _tracked_ids_cache:
			if rid != target_id:
				second_target = rid
				break
	_crt_ui.trigger_replay(first_reason, target_id)
	_crt_ui.trigger_replay(second_reason, second_target)
	if AudioBridge != null:
		AudioBridge.play_local_cue("crt_static")
	_refresh_status()


func _on_stop_pressed() -> void:
	if _crt_ui != null:
		_crt_ui.clear_queue_and_stop(true)
	_refresh_status()


func _on_archive_clip_pressed() -> void:
	if _crt_ui == null:
		return
	var target_id: int = _get_selected_target_id()
	var reason: String = _get_selected_reason()
	_crt_ui.archive_trap_hit(reason, target_id, target_id)
	_refresh_status()


func _on_clear_archive_pressed() -> void:
	if _crt_ui != null:
		_crt_ui.clear_match_archive()
	_refresh_status()


func _on_play_totg_pressed() -> void:
	if _crt_ui == null:
		return
	var target_id: int = _get_selected_target_id()
	if _crt_ui.get_match_archive_count() == 0:
		var reason: String = _get_selected_reason()
		_crt_ui.archive_trap_hit(reason, target_id, target_id)
		_crt_ui.archive_trap_hit("BOMB" if reason != "BOMB" else "TRIPWIRE", target_id, target_id)
	var clips: Array[Dictionary] = _crt_ui.get_match_archive()
	if clips.is_empty():
		return
	close_panel()
	if _debug_totg_ui == null:
		_debug_totg_ui = TRAP_OF_THE_GAME_UI_SCRIPT.new()
		_debug_totg_ui.name = "DebugTrapOfTheGameUI"
		add_child(_debug_totg_ui)
		_debug_totg_ui.compilation_finished.connect(func() -> void:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		)
		_debug_totg_ui.skip_to_lobby_requested.connect(func() -> void:
			print("[CRTDebug] Skip -> Lobby pressed in Trap of the Game preview")
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		)
	_debug_totg_ui.start_compilation(clips)


func _on_config_changed(_idx: int) -> void:
	_apply_controls_to_config()


func _on_spin_changed(_val: float) -> void:
	_apply_controls_to_config()


func _apply_controls_to_config() -> void:
	if _is_syncing_ui or GameConfig == null:
		return
	var res_idx: int = clampi(_res_opt.selected, 0, CAPTURE_PRESETS.size() - 1)
	var scl_idx: int = clampi(_scale_opt.selected, 0, DISPLAY_PRESETS.size() - 1)
	var fps_idx: int = clampi(_fps_opt.selected, 0, FPS_PRESETS.size() - 1)
	GameConfig.crt_viewport_size = CAPTURE_PRESETS[res_idx]
	GameConfig.crt_display_size = DISPLAY_PRESETS[scl_idx]
	GameConfig.crt_replay_fps = FPS_PRESETS[fps_idx]
	GameConfig.crt_replay_duration = float(_dur_spin.value)
	GameConfig.crt_replay_post_hit_seconds = float(_post_spin.value)
	GameConfig.crt_replay_frame_count = maxi(int(round(GameConfig.crt_replay_duration * float(GameConfig.crt_replay_fps))), 8)
	if _crt_ui != null:
		_crt_ui.apply_live_config()
	_refresh_status()


func _refresh_status() -> void:
	if _status_lbl == null or _crt_ui == null:
		return
	var snap: Dictionary = _crt_ui.get_debug_snapshot()
	var cap_sz: Vector2i = snap.get("capture_size", Vector2i.ZERO)
	var disp_sz: Vector2 = snap.get("display_size", Vector2.ZERO)
	var rig_bufs: Dictionary = snap.get("rig_buffers", {})
	var max_f: int = GameConfig.crt_replay_frame_count if GameConfig != null else 36
	var buf_parts: Array[String] = []
	for rid in rig_bufs.keys():
		buf_parts.append("Rig %s: %d/%d" % [str(rid), int(rig_bufs[rid]), max_f])
	var buf_text: String = ", ".join(buf_parts) if not buf_parts.is_empty() else "None"
	var state_text: String = "IDLE"
	if bool(snap.get("is_playing", false)):
		state_text = "PLAYING %s (Rig %d) %d/%d [post:%d]" % [
			str(snap.get("active_reason", "")),
			int(snap.get("active_victim_peer_id", 0)),
			int(snap.get("playback_idx", 0)) + 1,
			int(snap.get("playback_total", 0)),
			int(snap.get("post_capture_remaining", 0)),
		]
	var voice_pkts: int = int(snap.get("voice_buffer_count", 0))
	var cue_bufs: int = int(snap.get("cue_buffer_count", 0))
	_status_lbl.text = (
		"State: %s | Queue: %d | Archive: %d\nCap: %dx%d -> Disp: %dx%d | Cues: %d | VoicePkts: %d\nBuffers: %s" % [
			state_text,
			int(snap.get("queue_size", 0)),
			int(snap.get("archive_count", 0)),
			cap_sz.x, cap_sz.y,
			int(disp_sz.x), int(disp_sz.y),
			cue_bufs,
			voice_pkts,
			buf_text
		]
	)
