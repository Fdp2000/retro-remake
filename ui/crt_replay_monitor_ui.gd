@tool
class_name CRTReplayMonitorUI
extends Control

## Zero-Bandwidth 3.0s CRT Trap-Cam Replay Monitor (AGENTS.md §4.6, Doc 6 §4).
## Attaches a local 240x135 SubViewport Camera3D to each remote rival's spine.006 head anchor,
## records 12 FPS frames into per-rival circular ring buffers without streaming video over RPC,
## and plays back 2.0s pre-impact + 1.0s post-impact ragdoll footage inside a retro CRT bezel.

const DEFAULT_MAX_FRAMES: int = 36
const CAPTURE_SIZE := Vector2i(240, 135)

const CRT_SHADER_CODE: String = """shader_type canvas_item;

uniform float static_amount : hint_range(0.0, 1.0) = 0.04;
uniform float impact_flash : hint_range(0.0, 1.0) = 0.0;
uniform float time_seed = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float r2 = dot(centered, centered);
	vec2 warped_uv = UV + centered * (r2 * 0.14);

	if (warped_uv.x < 0.0 || warped_uv.x > 1.0 || warped_uv.y < 0.0 || warped_uv.y > 1.0) {
		COLOR = vec4(0.02, 0.04, 0.02, 1.0);
	} else {
		float shift = 0.0022 + static_amount * 0.008;
		float r_ch = texture(TEXTURE, clamp(warped_uv + vec2(shift, 0.0), vec2(0.001), vec2(0.999))).r;
		float g_ch = texture(TEXTURE, clamp(warped_uv, vec2(0.001), vec2(0.999))).g;
		float b_ch = texture(TEXTURE, clamp(warped_uv - vec2(shift, 0.0), vec2(0.001), vec2(0.999))).b;
		vec3 col = vec3(r_ch, g_ch, b_ch) * vec3(0.92, 1.04, 0.90);

		float scan = 0.88 + 0.12 * sin(warped_uv.y * 135.0 * 6.2831853);
		col *= scan;

		float vig = clamp(1.0 - r2 * 1.15, 0.25, 1.0);
		col *= vig;

		vec2 cell = floor(warped_uv * vec2(240.0, 135.0)) + vec2(time_seed * 61.3, time_seed * 17.7);
		float snow = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		col = mix(col, vec3(snow * 0.85, snow, snow * 0.88), clamp(static_amount, 0.0, 1.0));
		col += impact_flash * vec3(0.45, 0.20, 0.12);

		COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
	}
}
"""

var _owner_player: Node3D = null
var _owner_peer_id: int = 0
var _rig_container: Node = null
var _rival_rigs: Dictionary = {} # rival_id (int) -> {rival, viewport, camera, frames, visual_layer, pending_readback, frames_waited}
var _fallback_frames: Array[Image] = []

var _capture_accum: float = 0.0
var _sync_accum: float = 0.0
var _last_spy_count: int = -1

var _is_playing: bool = false
var _active_victim_peer_id: int = 0
var _active_reason: String = ""
var _play_elapsed: float = 0.0
var _play_accum: float = 0.0
var _play_idx: int = 0
var _impact_frame_idx: int = 0
var _post_capture_remaining: int = 0
var _playback_frames: Array[Image] = []

var _panel: PanelContainer = null
var _header_label: Label = null
var _footer_label: Label = null
var _texture_rect: TextureRect = null
var _display_tex: ImageTexture = null
var _crt_material: ShaderMaterial = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_rig_container()
	_build_layout()
	if not Engine.is_editor_hint() and _owner_player != null:
		sync_rival_rigs()


func _ensure_rig_container() -> void:
	if _rig_container == null or not is_instance_valid(_rig_container):
		_rig_container = get_node_or_null("CRTRigContainer")
	if _rig_container == null:
		_rig_container = Node.new()
		_rig_container.name = "CRTRigContainer"
		add_child(_rig_container)


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "CRTMonitorBezel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -284.0
	_panel.offset_right = -14.0
	_panel.offset_top = 54.0
	_panel.offset_bottom = 250.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false

	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color(0.08, 0.09, 0.10, 0.96)
	outer_style.border_color = Color(0.28, 0.36, 0.30, 1.0)
	outer_style.set_border_width_all(3)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(10)
	outer_style.shadow_size = 6
	outer_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	_panel.add_theme_stylebox_override("panel", outer_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_header_label = Label.new()
	_header_label.text = "▶ TRAP-CAM • STANDBY"
	_header_label.add_theme_font_size_override("font_size", 12)
	_header_label.modulate = Color(1.0, 0.42, 0.30)
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_header_label)

	var screen_frame := PanelContainer.new()
	screen_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0.02, 0.03, 0.02, 1.0)
	inner_style.border_color = Color(0.16, 0.22, 0.18, 1.0)
	inner_style.set_border_width_all(2)
	inner_style.set_corner_radius_all(4)
	inner_style.set_content_margin_all(2)
	screen_frame.add_theme_stylebox_override("panel", inner_style)
	vbox.add_child(screen_frame)

	_texture_rect = TextureRect.new()
	_texture_rect.custom_minimum_size = Vector2(float(CAPTURE_SIZE.x), float(CAPTURE_SIZE.y))
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = CRT_SHADER_CODE
	_crt_material = ShaderMaterial.new()
	_crt_material.shader = shader
	_crt_material.set_shader_parameter("static_amount", 0.04)
	_crt_material.set_shader_parameter("impact_flash", 0.0)
	_crt_material.set_shader_parameter("time_seed", 0.0)
	_texture_rect.material = _crt_material
	screen_frame.add_child(_texture_rect)

	_footer_label = Label.new()
	_footer_label.text = "-02.0s  APPROACH"
	_footer_label.add_theme_font_size_override("font_size", 11)
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer_label.modulate = Color(0.62, 0.95, 0.68)
	_footer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_footer_label)


func _get_capture_size() -> Vector2i:
	if GameConfig != null:
		var sz: Vector2i = GameConfig.crt_viewport_size
		if sz.x > 0 and sz.y > 0:
			return sz
	return CAPTURE_SIZE


func setup_for_owner(owner_player: Node3D) -> void:
	_owner_player = owner_player
	if owner_player != null and owner_player.name.is_valid_int():
		_owner_peer_id = owner_player.name.to_int()
	else:
		_owner_peer_id = 0
	if is_inside_tree():
		sync_rival_rigs()


func sync_rival_rigs() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	_ensure_rig_container()

	var found_rigs: Dictionary = {}
	for candidate in get_tree().get_nodes_in_group("spy_players"):
		if candidate == null or not is_instance_valid(candidate) or not (candidate is Node3D):
			continue
		if candidate == _owner_player:
			continue
		var cand_id: int = candidate.name.to_int() if candidate.name.is_valid_int() else int(candidate.get_instance_id())
		if _owner_peer_id != 0 and cand_id == _owner_peer_id:
			continue
		found_rigs[cand_id] = candidate as Node3D

	var stale_ids: Array[int] = []
	for existing_id in _rival_rigs.keys():
		var rid: int = int(existing_id)
		var rig: Dictionary = _rival_rigs[rid]
		var vp: SubViewport = rig.get("viewport") as SubViewport
		if not found_rigs.has(rid) or vp == null or not is_instance_valid(vp):
			stale_ids.append(rid)

	for stale_id in stale_ids:
		var old_rig: Dictionary = _rival_rigs[stale_id]
		var old_vp: SubViewport = old_rig.get("viewport") as SubViewport
		if old_vp != null and is_instance_valid(old_vp):
			old_vp.queue_free()
		_rival_rigs.erase(stale_id)

	var rival_ids: Array[int] = []
	for rid in found_rigs.keys():
		rival_ids.append(int(rid))
	rival_ids.sort()

	var owner_world: World3D = null
	if _owner_player != null and is_instance_valid(_owner_player) and _owner_player.is_inside_tree():
		owner_world = _owner_player.get_world_3d()
	elif get_viewport() != null:
		owner_world = get_viewport().world_3d

	var all_layers: int = GameConfig.VISUAL_LAYER_ALL if GameConfig != null else 0xFFFFF
	var cap_size: Vector2i = _get_capture_size()

	for slot_idx in range(rival_ids.size()):
		var rival_id: int = rival_ids[slot_idx]
		var rival: Node3D = found_rigs[rival_id] as Node3D
		var layer_bit: int = (
			GameConfig.get_remote_spy_visual_layer(slot_idx)
			if GameConfig != null
			else (1 << (11 + posmod(slot_idx, 3)))
		)

		if rival.has_method("set_crt_body_visual_layer"):
			var cur_layer: int = int(rival.call("get_crt_body_visual_layer")) if rival.has_method("get_crt_body_visual_layer") else 1
			if cur_layer != layer_bit:
				rival.call("set_crt_body_visual_layer", layer_bit)

		var vp: SubViewport = null
		var cam: Camera3D = null
		if not _rival_rigs.has(rival_id):
			vp = SubViewport.new()
			vp.name = "CRTRivalViewport_%d" % rival_id
			vp.size = cap_size
			vp.own_world_3d = false
			vp.handle_input_locally = false
			vp.gui_disable_input = true
			vp.audio_listener_enable_3d = false
			vp.audio_listener_enable_2d = false
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.positional_shadow_atlas_size = 512
			vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

			cam = Camera3D.new()
			cam.name = "CRTRivalCamera"
			cam.fov = 75.0
			cam.near = 0.05
			cam.far = 80.0
			cam.current = true
			vp.add_child(cam)
			_rig_container.add_child(vp)

			var frames_arr: Array[Image] = []
			_rival_rigs[rival_id] = {
				"rival": rival,
				"viewport": vp,
				"camera": cam,
				"frames": frames_arr,
				"visual_layer": layer_bit,
				"pending_readback": false,
				"frames_waited": 0
			}
		else:
			var rig: Dictionary = _rival_rigs[rival_id]
			rig["rival"] = rival
			rig["visual_layer"] = layer_bit
			vp = rig.get("viewport") as SubViewport
			cam = rig.get("camera") as Camera3D

		if vp != null:
			if vp.size != cap_size:
				vp.size = cap_size
			if owner_world != null and vp.world_3d != owner_world:
				vp.world_3d = owner_world
		if cam != null:
			cam.cull_mask = all_layers & ~layer_bit


func update_rival_camera_transforms() -> void:
	var owner_world: World3D = null
	if _owner_player != null and is_instance_valid(_owner_player) and _owner_player.is_inside_tree():
		owner_world = _owner_player.get_world_3d()

	for rid in _rival_rigs.keys():
		var rig: Dictionary = _rival_rigs[rid]
		var rival: Node3D = rig.get("rival") as Node3D
		var vp: SubViewport = rig.get("viewport") as SubViewport
		var cam: Camera3D = rig.get("camera") as Camera3D
		if rival == null or not is_instance_valid(rival) or vp == null or not is_instance_valid(vp) or cam == null or not is_instance_valid(cam):
			continue
		if owner_world != null and vp.world_3d != owner_world:
			vp.world_3d = owner_world
		var pov_xform: Transform3D = (
			rival.call("get_crt_pov_transform")
			if rival.has_method("get_crt_pov_transform")
			else (rival.global_transform if rival.is_inside_tree() else rival.transform)
		)
		if cam.is_inside_tree():
			cam.global_transform = pov_xform
		else:
			cam.transform = pov_xform


func get_rival_rig(rival_peer_id: int) -> Dictionary:
	return _rival_rigs.get(rival_peer_id, {})


func get_tracked_rival_ids() -> Array[int]:
	var ids: Array[int] = []
	for k in _rival_rigs.keys():
		ids.append(int(k))
	ids.sort()
	return ids


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return

	_sync_accum += delta
	var spy_count: int = get_tree().get_nodes_in_group("spy_players").size() if get_tree() != null else 0
	if _sync_accum >= 0.5 or spy_count != _last_spy_count:
		_sync_accum = 0.0
		_last_spy_count = spy_count
		sync_rival_rigs()

	var is_headless: bool = DisplayServer.get_name() == "headless"

	# Phase A: Read back completed SubViewport renders queued 1+ frame earlier (zero main-viewport stall)
	if not is_headless:
		var cap_size: Vector2i = _get_capture_size()
		for rid_var in _rival_rigs.keys():
			var rival_id: int = int(rid_var)
			var rig: Dictionary = _rival_rigs[rival_id]
			if not bool(rig.get("pending_readback", false)):
				continue
			var waited: int = int(rig.get("frames_waited", 0)) + 1
			rig["frames_waited"] = waited
			if waited < 1:
				continue
			rig["pending_readback"] = false
			rig["frames_waited"] = 0
			var vp: SubViewport = rig.get("viewport") as SubViewport
			if vp == null or not is_instance_valid(vp):
				continue
			var tex: ViewportTexture = vp.get_texture()
			if tex == null:
				continue
			var img: Image = tex.get_image()
			if img == null or img.is_empty():
				continue
			if img.get_format() != Image.FORMAT_RGB8:
				img.convert(Image.FORMAT_RGB8)
			if img.get_size() != cap_size:
				img.resize(cap_size.x, cap_size.y, Image.INTERPOLATE_NEAREST)
			push_frame(img, rival_id)

	# Phase B: Advance active 3.0s CRT replay playback
	if _is_playing:
		step_replay_playback(delta)

	# Phase C: Trigger UPDATE_ONCE at 12 FPS on remote rival SubViewports
	var fps: int = GameConfig.crt_replay_fps if GameConfig != null else 12
	var step_sec: float = 1.0 / float(maxi(fps, 1))
	_capture_accum += delta
	if _capture_accum >= step_sec:
		_capture_accum = fmod(_capture_accum, step_sec)
		var capture_ids: Array[int] = []
		if not _is_playing:
			capture_ids = get_tracked_rival_ids()
		elif _post_capture_remaining > 0 and _rival_rigs.has(_active_victim_peer_id):
			capture_ids.append(_active_victim_peer_id)

		if not capture_ids.is_empty():
			update_rival_camera_transforms()
			if not is_headless:
				for rival_id in capture_ids:
					var rig: Dictionary = _rival_rigs[rival_id]
					var vp: SubViewport = rig.get("viewport") as SubViewport
					if vp != null and is_instance_valid(vp):
						rig["pending_readback"] = true
						rig["frames_waited"] = 0
						vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func push_frame(img: Image, rival_peer_id: int = 0) -> void:
	if img == null or img.is_empty():
		return
	var max_frames: int = maxi(GameConfig.crt_replay_frame_count if GameConfig != null else DEFAULT_MAX_FRAMES, 1)
	if rival_peer_id > 0 and _rival_rigs.has(rival_peer_id):
		var frames: Array[Image] = _rival_rigs[rival_peer_id]["frames"]
		frames.append(img)
		while frames.size() > max_frames:
			frames.remove_at(0)
	else:
		_fallback_frames.append(img)
		while _fallback_frames.size() > max_frames:
			_fallback_frames.remove_at(0)

	if _is_playing and rival_peer_id == _active_victim_peer_id and _post_capture_remaining > 0:
		_playback_frames.append(img)
		_post_capture_remaining -= 1


func get_buffer_size(rival_peer_id: int = 0) -> int:
	if rival_peer_id > 0 and _rival_rigs.has(rival_peer_id):
		return (_rival_rigs[rival_peer_id]["frames"] as Array).size()
	if rival_peer_id == 0 and not _rival_rigs.is_empty():
		var ids: Array[int] = get_tracked_rival_ids()
		return (_rival_rigs[ids[0]]["frames"] as Array).size()
	return _fallback_frames.size()


func get_playback_frame_count() -> int:
	return _playback_frames.size()


func get_post_capture_remaining() -> int:
	return _post_capture_remaining


func get_active_victim_peer_id() -> int:
	return _active_victim_peer_id


func is_replaying() -> bool:
	return _is_playing


func trigger_replay(reason: String, victim_peer_id: int) -> void:
	if _panel == null:
		_build_layout()
	sync_rival_rigs()
	update_rival_camera_transforms()

	var max_frames: int = maxi(GameConfig.crt_replay_frame_count if GameConfig != null else DEFAULT_MAX_FRAMES, 4)
	var fps: int = maxi(GameConfig.crt_replay_fps if GameConfig != null else 12, 1)
	var post_sec: float = clampf(GameConfig.crt_replay_post_hit_seconds if GameConfig != null else 1.0, 0.0, 2.0)
	var post_frames: int = clampi(int(round(post_sec * float(fps))), 0, maxi(max_frames - 4, 0))
	var pre_budget: int = maxi(max_frames - post_frames, 1)

	var source_frames: Array[Image] = _fallback_frames
	if _rival_rigs.has(victim_peer_id):
		source_frames = _rival_rigs[victim_peer_id]["frames"]

	_playback_frames.clear()
	if not source_frames.is_empty():
		var start_idx: int = maxi(source_frames.size() - pre_budget, 0)
		for i in range(start_idx, source_frames.size()):
			_playback_frames.append(source_frames[i])
		_impact_frame_idx = _playback_frames.size()
	else:
		var cap_size: Vector2i = _get_capture_size()
		var standby := Image.create(cap_size.x, cap_size.y, false, Image.FORMAT_RGB8)
		standby.fill(Color(0.08, 0.18, 0.11))
		_playback_frames.append(standby)
		_impact_frame_idx = 0

	_active_victim_peer_id = victim_peer_id
	_active_reason = reason.to_upper()
	_post_capture_remaining = post_frames
	_is_playing = true
	_play_elapsed = 0.0
	_play_accum = 0.0
	_play_idx = 0

	var spy_label: String = _resolve_spy_display_name(victim_peer_id)
	if _header_label != null:
		_header_label.text = "▶ TRAP-CAM • %s HIT %s!" % [_active_reason, spy_label]
	if _panel != null:
		_panel.visible = true
	if not _playback_frames.is_empty():
		_show_frame(_playback_frames[0])
	_update_crt_visuals()


func step_replay_playback(delta: float) -> void:
	if not _is_playing:
		return
	_play_elapsed += delta
	var dur: float = GameConfig.crt_replay_duration if GameConfig != null else 3.0
	if _play_elapsed >= dur:
		stop_replay(true)
		return

	var fps: int = maxi(GameConfig.crt_replay_fps if GameConfig != null else 12, 1)
	var step_sec: float = 1.0 / float(fps)
	_play_accum += delta
	while _play_accum >= step_sec:
		_play_accum -= step_sec
		if _play_idx + 1 < _playback_frames.size():
			_play_idx += 1
			_show_frame(_playback_frames[_play_idx])

	_update_crt_visuals()


func stop_replay(emit_click_off: bool = false) -> void:
	var was_playing: bool = _is_playing
	_is_playing = false
	_active_victim_peer_id = 0
	_active_reason = ""
	_post_capture_remaining = 0
	_playback_frames.clear()
	if _panel != null:
		_panel.visible = false
	if was_playing and emit_click_off and AudioBridge != null:
		AudioBridge.play_local_cue("crt_click_off")


func _update_crt_visuals() -> void:
	var dur: float = GameConfig.crt_replay_duration if GameConfig != null else 3.0
	var fps: int = maxi(GameConfig.crt_replay_fps if GameConfig != null else 12, 1)
	var burst_sec: float = 0.18
	var static_val: float = 0.03
	if _play_elapsed < burst_sec:
		static_val = 1.0 - (_play_elapsed / burst_sec)
	elif _play_elapsed > dur - burst_sec:
		static_val = (_play_elapsed - (dur - burst_sec)) / burst_sec

	var impact_flash_val: float = 0.0
	if _impact_frame_idx > 0 and (_play_idx == _impact_frame_idx or _play_idx == _impact_frame_idx - 1):
		impact_flash_val = 0.85

	if _crt_material != null:
		_crt_material.set_shader_parameter("static_amount", clampf(static_val, 0.02, 1.0))
		_crt_material.set_shader_parameter("impact_flash", impact_flash_val)
		_crt_material.set_shader_parameter("time_seed", _play_elapsed)

	if _footer_label != null:
		var rel_sec: float = float(_play_idx - _impact_frame_idx) / float(fps)
		if rel_sec < -0.04:
			_footer_label.text = "%.1fs  APPROACH" % rel_sec
			_footer_label.modulate = Color(0.62, 0.95, 0.68)
		elif absf(rel_sec) <= 0.12:
			_footer_label.text = "● 00.0s  IMPACT!"
			_footer_label.modulate = Color(1.0, 0.45, 0.28)
		else:
			_footer_label.text = "+%.1fs  KO RAGDOLL" % rel_sec
			_footer_label.modulate = Color(0.95, 0.85, 0.45)


func _resolve_spy_display_name(victim_peer_id: int) -> String:
	if _rival_rigs.has(victim_peer_id):
		var rival: Node3D = _rival_rigs[victim_peer_id].get("rival") as Node3D
		if rival != null and is_instance_valid(rival):
			var role_val: int = int(rival.get("spy_role"))
			if GameConfig != null and role_val >= 1 and role_val <= 4:
				return GameConfig.get_spy_role_name(role_val)
			if role_val == 1:
				return "SPY GREEN"
			if role_val == 2:
				return "SPY PURPLE"
			if role_val == 3:
				return "SPY BLUE"
			if role_val == 4:
				return "SPY RED"
	return "SPY %d" % victim_peer_id


func _show_frame(img: Image) -> void:
	if _texture_rect == null or img == null:
		return
	if _display_tex == null or _display_tex.get_size() != Vector2(img.get_size()):
		_display_tex = ImageTexture.create_from_image(img)
		_texture_rect.texture = _display_tex
	else:
		_display_tex.update(img)
