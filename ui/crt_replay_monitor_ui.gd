@tool
class_name CRTReplayMonitorUI
extends Control

## Zero-Bandwidth 3.0s CRT Trap-Cam Replay Monitor (AGENTS.md §4.6, Doc 6 §4).
## Attaches a local SubViewport Camera3D to each remote rival's spine.006 head anchor,
## captures staggered 12 FPS frames into per-rival circular ring buffers without streaming video over RPC,
## queues back-to-back hits, and plays back pre-impact + post-impact ragdoll footage inside a retro CRT bezel.

const DEFAULT_MAX_FRAMES: int = 126
const DEFAULT_MAX_QUEUE: int = 4
const DEFAULT_RAW_ARCHIVE_CAP: int = 32
const CAPTURE_SIZE := Vector2i(426, 240)
const DISPLAY_SIZE := Vector2(288.0, 162.0)

const CRT_SHADER_CODE: String = """shader_type canvas_item;

uniform float static_amount : hint_range(0.0, 1.0) = 0.04;
uniform float impact_flash : hint_range(0.0, 1.0) = 0.0;
uniform float time_seed = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float r2 = dot(centered, centered);
	vec2 warped_uv = UV + centered * (r2 * 0.13);

	if (warped_uv.x < 0.0 || warped_uv.x > 1.0 || warped_uv.y < 0.0 || warped_uv.y > 1.0) {
		COLOR = vec4(0.02, 0.04, 0.02, 1.0);
	} else {
		vec2 tex_res = max(vec2(textureSize(TEXTURE, 0)), vec2(160.0, 90.0));
		float shift = 0.0020 + static_amount * 0.0075;
		float r_ch = texture(TEXTURE, clamp(warped_uv + vec2(shift, 0.0), vec2(0.001), vec2(0.999))).r;
		float g_ch = texture(TEXTURE, clamp(warped_uv, vec2(0.001), vec2(0.999))).g;
		float b_ch = texture(TEXTURE, clamp(warped_uv - vec2(shift, 0.0), vec2(0.001), vec2(0.999))).b;
		vec3 col = vec3(r_ch, g_ch, b_ch) * vec3(0.92, 1.04, 0.90);

		float scan = 0.89 + 0.11 * sin(warped_uv.y * tex_res.y * 6.2831853);
		col *= scan;

		float vig = clamp(1.0 - r2 * 1.12, 0.28, 1.0);
		col *= vig;

		vec2 cell = floor(warped_uv * tex_res) + vec2(time_seed * 61.3, time_seed * 17.7);
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
var _rival_rigs: Dictionary = {} # rival_id (int) -> {rival, viewport, camera, frames, positions, visual_layer, pending_readback, frames_waited, capture_accum}
var _fallback_frames: Array[Image] = []

var _sync_accum: float = 0.0
var _last_spy_count: int = -1
var _debug_include_self: bool = false

var _audio_cue_buffer: Array[Dictionary] = []
var _voice_packet_buffer: Array[Dictionary] = []
var _latest_voip_headers: Dictionary = {} # peer_id -> PackedByteArray
var _match_archive: Array[Dictionary] = []

var _is_playing: bool = false
var _active_victim_peer_id: int = 0
var _active_reason: String = ""
var _play_elapsed: float = 0.0
var _play_accum: float = 0.0
var _play_idx: int = 0
var _impact_frame_idx: int = 0
var _post_capture_remaining: int = 0
var _playback_frames: Array[Image] = []
var _replay_queue: Array[Dictionary] = []

var _panel: PanelContainer = null
var _header_row: HBoxContainer = null
var _header_label: Label = null
var _queue_label: Label = null
var _texture_rect: TextureRect = null
var _display_tex: ImageTexture = null
var _crt_material: ShaderMaterial = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_rig_container()
	_build_layout()
	if not Engine.is_editor_hint():
		if AudioBridge != null and AudioBridge.has_signal("world_cue_emitted") and not AudioBridge.world_cue_emitted.is_connected(_on_world_cue_emitted):
			AudioBridge.world_cue_emitted.connect(_on_world_cue_emitted)
		if VoiceChatManager != null and VoiceChatManager.has_signal("voip_packet_captured") and not VoiceChatManager.voip_packet_captured.is_connected(_on_voip_packet_captured):
			VoiceChatManager.voip_packet_captured.connect(_on_voip_packet_captured)
		if _owner_player != null:
			sync_rival_rigs()


func _ensure_rig_container() -> void:
	if _rig_container == null or not is_instance_valid(_rig_container):
		_rig_container = get_node_or_null("CRTRigContainer")
	if _rig_container == null:
		_rig_container = Node.new()
		_rig_container.name = "CRTRigContainer"
		add_child(_rig_container)


func _get_capture_size() -> Vector2i:
	if GameConfig != null:
		var sz: Vector2i = GameConfig.crt_viewport_size
		if sz.x > 0 and sz.y > 0:
			return sz
	return CAPTURE_SIZE


func _get_display_size() -> Vector2:
	if GameConfig != null:
		var ds: Vector2 = GameConfig.crt_display_size
		if ds.x >= 160.0 and ds.y >= 90.0:
			return ds
	return DISPLAY_SIZE


func _get_max_queue() -> int:
	if GameConfig != null and GameConfig.crt_replay_max_queue >= 1:
		return GameConfig.crt_replay_max_queue
	return DEFAULT_MAX_QUEUE


func _build_layout() -> void:
	if _panel != null:
		return

	var disp_size: Vector2 = _get_display_size()
	var bezel_w: float = disp_size.x + 28.0
	var bezel_h: float = disp_size.y + 36.0

	_panel = PanelContainer.new()
	_panel.name = "CRTMonitorBezel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -(bezel_w + 14.0)
	_panel.offset_right = -14.0
	_panel.offset_top = 52.0
	_panel.offset_bottom = 52.0 + bezel_h
	_panel.custom_minimum_size = Vector2(bezel_w, bezel_h)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false

	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color(0.08, 0.09, 0.10, 0.96)
	outer_style.border_color = Color(0.28, 0.36, 0.30, 1.0)
	outer_style.set_border_width_all(3)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(10)
	outer_style.shadow_size = 8
	outer_style.shadow_color = Color(0.0, 0.0, 0.0, 0.60)
	_panel.add_theme_stylebox_override("panel", outer_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_header_row = HBoxContainer.new()
	_header_row.custom_minimum_size = Vector2(disp_size.x, 0.0)
	_header_row.add_theme_constant_override("separation", 6)
	_header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_header_row)

	_header_label = Label.new()
	_header_label.text = "▶ TRAP-CAM • STANDBY"
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.clip_text = true
	_header_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_label.add_theme_font_size_override("font_size", 12)
	_header_label.modulate = Color(1.0, 0.42, 0.30)
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_row.add_child(_header_label)

	_queue_label = Label.new()
	_queue_label.text = ""
	_queue_label.visible = false
	_queue_label.add_theme_font_size_override("font_size", 11)
	_queue_label.modulate = Color(1.0, 0.82, 0.35)
	_queue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_row.add_child(_queue_label)

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
	_texture_rect.custom_minimum_size = disp_size
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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


func apply_live_config() -> void:
	var disp_size: Vector2 = _get_display_size()
	var cap_size: Vector2i = _get_capture_size()
	if _panel != null:
		var bezel_w: float = disp_size.x + 28.0
		var bezel_h: float = disp_size.y + 36.0
		_panel.offset_left = -(bezel_w + 14.0)
		_panel.offset_right = -14.0
		_panel.offset_top = 52.0
		_panel.offset_bottom = 52.0 + bezel_h
		_panel.custom_minimum_size = Vector2(bezel_w, bezel_h)
		_panel.size = Vector2(bezel_w, bezel_h)
	if _header_row != null:
		_header_row.custom_minimum_size = Vector2(disp_size.x, 0.0)
	if _texture_rect != null:
		_texture_rect.custom_minimum_size = disp_size
	for rid in _rival_rigs.keys():
		var vp: SubViewport = _rival_rigs[rid].get("viewport") as SubViewport
		if vp != null and is_instance_valid(vp) and vp.size != cap_size:
			vp.size = cap_size


func setup_for_owner(owner_player: Node3D) -> void:
	_owner_player = owner_player
	if owner_player != null and owner_player.name.is_valid_int():
		_owner_peer_id = owner_player.name.to_int()
	else:
		_owner_peer_id = 0
	if is_inside_tree():
		sync_rival_rigs()


func set_debug_include_self(enabled: bool) -> void:
	if _debug_include_self == enabled:
		return
	_debug_include_self = enabled
	sync_rival_rigs()


func is_debug_include_self() -> bool:
	return _debug_include_self


func _resolve_candidate_id(candidate: Node) -> int:
	if candidate.name.is_valid_int():
		return candidate.name.to_int()
	return int(candidate.get_instance_id())


func sync_rival_rigs() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	_ensure_rig_container()

	var include_self: bool = _debug_include_self or (GameConfig != null and GameConfig.crt_archive_enabled)
	var found_rigs: Dictionary = {}
	for candidate in get_tree().get_nodes_in_group("spy_players"):
		if candidate == null or not is_instance_valid(candidate) or not (candidate is Node3D):
			continue
		var is_self: bool = (candidate == _owner_player)
		var cand_id: int = _resolve_candidate_id(candidate)
		if not is_self and _owner_peer_id != 0 and cand_id == _owner_peer_id:
			is_self = true
		if is_self and not include_self:
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
	var local_fp_layer: int = GameConfig.VISUAL_LAYER_LOCAL_SPY_BODY if GameConfig != null else (1 << 10)
	var fp_only_bit: int = GameConfig.VISUAL_LAYER_LOCAL_FP_BODY if GameConfig != null else (1 << 14)
	var cap_size: Vector2i = _get_capture_size()
	var fps: int = maxi(GameConfig.crt_replay_fps if GameConfig != null else 12, 1)
	var step_sec: float = 1.0 / float(fps)
	var total_rivals: int = maxi(rival_ids.size(), 1)

	for slot_idx in range(rival_ids.size()):
		var rival_id: int = rival_ids[slot_idx]
		var rival: Node3D = found_rigs[rival_id] as Node3D
		var is_owner_self: bool = (rival == _owner_player)
		var layer_bit: int = local_fp_layer if is_owner_self else (
			GameConfig.get_remote_spy_visual_layer(slot_idx)
			if GameConfig != null
			else (1 << (11 + posmod(slot_idx, 3)))
		)

		if not is_owner_self and rival.has_method("set_crt_body_visual_layer"):
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
			var pos_arr: Array[Vector3] = []
			var voice_arr: Array[float] = []
			var stagger_phase: float = (float(slot_idx) / float(total_rivals)) * step_sec
			_rival_rigs[rival_id] = {
				"rival": rival,
				"viewport": vp,
				"camera": cam,
				"frames": frames_arr,
				"positions": pos_arr,
				"voice_levels": voice_arr,
				"visual_layer": layer_bit,
				"pending_readback": false,
				"frames_waited": 0,
				"capture_accum": stagger_phase
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
			cam.cull_mask = all_layers & ~layer_bit & ~fp_only_bit


func update_rival_camera_transforms(only_ids: Array[int] = []) -> void:
	var owner_world: World3D = null
	if _owner_player != null and is_instance_valid(_owner_player) and _owner_player.is_inside_tree():
		owner_world = _owner_player.get_world_3d()

	var target_ids: Array = only_ids if not only_ids.is_empty() else _rival_rigs.keys()
	for rid in target_ids:
		if not _rival_rigs.has(rid):
			continue
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


func get_replay_queue_size() -> int:
	return _replay_queue.size()


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

	# Phase B: Advance active CRT replay playback
	if _is_playing:
		step_replay_playback(delta)

	# Phase C: Staggered round-robin UPDATE_ONCE at configured FPS across all tracked rivals
	# Keeps capturing all rivals even while a replay is playing so back-to-back hits have fresh pre-impact buffers.
	var fps: int = maxi(GameConfig.crt_replay_fps if GameConfig != null else 12, 1)
	var step_sec: float = 1.0 / float(fps)
	var capture_ids: Array[int] = []
	for rival_id in get_tracked_rival_ids():
		var rig: Dictionary = _rival_rigs[rival_id]
		var accum: float = float(rig.get("capture_accum", 0.0)) + delta
		if accum >= step_sec:
			accum = fmod(accum, step_sec)
			if not bool(rig.get("pending_readback", false)):
				capture_ids.append(rival_id)
		rig["capture_accum"] = accum

	if not capture_ids.is_empty():
		update_rival_camera_transforms(capture_ids)
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
	var cur_pos: Vector3 = _get_rig_world_pos(rival_peer_id)
	var cur_voice: float = _get_rig_voice_level(rival_peer_id)
	if rival_peer_id > 0 and _rival_rigs.has(rival_peer_id):
		var frames: Array[Image] = _rival_rigs[rival_peer_id]["frames"]
		var positions: Array[Vector3] = _rival_rigs[rival_peer_id]["positions"]
		var voice_levels: Array[float] = _rival_rigs[rival_peer_id]["voice_levels"]
		frames.append(img)
		positions.append(cur_pos)
		voice_levels.append(cur_voice)
		while frames.size() > max_frames:
			frames.remove_at(0)
			if not positions.is_empty():
				positions.remove_at(0)
			if not voice_levels.is_empty():
				voice_levels.remove_at(0)
	else:
		_fallback_frames.append(img)
		while _fallback_frames.size() > max_frames:
			_fallback_frames.remove_at(0)

	if _is_playing and rival_peer_id == _active_victim_peer_id and _post_capture_remaining > 0:
		_playback_frames.append(img)
		_post_capture_remaining -= 1

	for queued in _replay_queue:
		if int(queued.get("victim_peer_id", 0)) == rival_peer_id and int(queued.get("post_capture_remaining", 0)) > 0:
			var q_frames: Array[Image] = queued["playback_frames"]
			q_frames.append(img)
			queued["post_capture_remaining"] = int(queued["post_capture_remaining"]) - 1

	for archived in _match_archive:
		if int(archived.get("victim_peer_id", 0)) == rival_peer_id and int(archived.get("post_capture_remaining", 0)) > 0:
			var a_frames: Array[Image] = archived["playback_frames"]
			var a_positions: Array[Vector3] = archived["victim_positions"]
			a_frames.append(img)
			a_positions.append(cur_pos)
			archived["post_capture_remaining"] = int(archived["post_capture_remaining"]) - 1
			var prev_peak: float = float(archived.get("victim_voice_peak", 0.0))
			var new_peak: float = maxf(prev_peak, cur_voice)
			var new_sum: float = float(archived.get("victim_voice_sum", 0.0)) + cur_voice
			archived["victim_voice_peak"] = new_peak
			archived["victim_voice_sum"] = new_sum
			archived["victim_voice_score"] = new_peak + (new_sum * 0.02)


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


func _build_replay_snapshot(reason: String, victim_peer_id: int) -> Dictionary:
	var max_frames: int = maxi(GameConfig.crt_replay_frame_count if GameConfig != null else DEFAULT_MAX_FRAMES, 4)
	var fps: int = maxi(GameConfig.crt_replay_fps if GameConfig != null else 12, 1)
	var post_sec: float = clampf(GameConfig.crt_replay_post_hit_seconds if GameConfig != null else 2.75, 0.0, 3.5)
	var post_frames: int = clampi(int(round(post_sec * float(fps))), 0, maxi(max_frames - 4, 0))
	var pre_budget: int = maxi(max_frames - post_frames, 1)

	var source_frames: Array[Image] = _fallback_frames
	if _rival_rigs.has(victim_peer_id):
		source_frames = _rival_rigs[victim_peer_id]["frames"]

	var snap_frames: Array[Image] = []
	var impact_idx: int = 0
	if not source_frames.is_empty():
		var start_idx: int = maxi(source_frames.size() - pre_budget, 0)
		for i in range(start_idx, source_frames.size()):
			snap_frames.append(source_frames[i])
		impact_idx = snap_frames.size()
	else:
		var cap_size: Vector2i = _get_capture_size()
		var standby := Image.create(cap_size.x, cap_size.y, false, Image.FORMAT_RGB8)
		standby.fill(Color(0.08, 0.18, 0.11))
		snap_frames.append(standby)
		impact_idx = 0

	return {
		"reason": reason.to_upper(),
		"victim_peer_id": victim_peer_id,
		"playback_frames": snap_frames,
		"impact_frame_idx": impact_idx,
		"post_capture_remaining": post_frames
	}


func _start_replay_entry(entry: Dictionary) -> void:
	_playback_frames = entry.get("playback_frames", [] as Array[Image])
	_impact_frame_idx = int(entry.get("impact_frame_idx", 0))
	_active_victim_peer_id = int(entry.get("victim_peer_id", 0))
	_active_reason = str(entry.get("reason", "TRAP"))
	_post_capture_remaining = int(entry.get("post_capture_remaining", 0))
	_is_playing = true
	_play_elapsed = 0.0
	_play_accum = 0.0
	_play_idx = 0

	var spy_label: String = _resolve_spy_display_name(_active_victim_peer_id)
	if _header_label != null:
		_header_label.text = "▶ TRAP-CAM • %s HIT %s!" % [_active_reason, spy_label]
	_refresh_queue_badge()
	if _panel != null:
		_panel.visible = true
	if not _playback_frames.is_empty():
		_show_frame(_playback_frames[0])
	_update_crt_visuals()


func _refresh_queue_badge() -> void:
	if _queue_label == null:
		return
	if _replay_queue.is_empty():
		_queue_label.visible = false
		_queue_label.text = ""
	else:
		_queue_label.visible = true
		_queue_label.text = "+%d QUEUED" % _replay_queue.size()


func trigger_replay(reason: String, victim_peer_id: int) -> void:
	if _panel == null:
		_build_layout()
	apply_live_config()
	sync_rival_rigs()
	update_rival_camera_transforms()

	var entry: Dictionary = _build_replay_snapshot(reason, victim_peer_id)
	if _is_playing:
		var max_q: int = _get_max_queue()
		if _replay_queue.size() < max_q:
			_replay_queue.append(entry)
			_refresh_queue_badge()
		return

	_start_replay_entry(entry)


func step_replay_playback(delta: float) -> void:
	if not _is_playing:
		return
	_play_elapsed += delta
	var dur: float = GameConfig.crt_replay_duration if GameConfig != null else 4.5
	if _play_elapsed >= dur and (_post_capture_remaining <= 0 or _play_elapsed >= dur + 0.6):
		if not _replay_queue.is_empty():
			var next_entry: Dictionary = _replay_queue.pop_front()
			_start_replay_entry(next_entry)
			if AudioBridge != null:
				AudioBridge.play_local_cue("crt_static")
		else:
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
	_refresh_queue_badge()
	if _panel != null:
		_panel.visible = false
	if was_playing and emit_click_off and AudioBridge != null:
		AudioBridge.play_local_cue("crt_click_off")


func clear_queue_and_stop(emit_click_off: bool = false) -> void:
	_replay_queue.clear()
	stop_replay(emit_click_off)


func get_debug_snapshot() -> Dictionary:
	var rig_buffers: Dictionary = {}
	for rid in get_tracked_rival_ids():
		rig_buffers[rid] = (_rival_rigs[rid]["frames"] as Array).size()
	return {
		"is_playing": _is_playing,
		"active_victim_peer_id": _active_victim_peer_id,
		"active_reason": _active_reason,
		"queue_size": _replay_queue.size(),
		"archive_count": _match_archive.size(),
		"voice_buffer_count": _voice_packet_buffer.size(),
		"cue_buffer_count": _audio_cue_buffer.size(),
		"playback_idx": _play_idx,
		"playback_total": _playback_frames.size(),
		"post_capture_remaining": _post_capture_remaining,
		"play_elapsed": _play_elapsed,
		"rig_buffers": rig_buffers,
		"capture_size": _get_capture_size(),
		"display_size": _get_display_size(),
		"debug_include_self": _debug_include_self
	}


func _now_sec() -> float:
	return float(Time.get_ticks_msec()) * 0.001


func _get_rig_world_pos(peer_id: int) -> Vector3:
	if _rival_rigs.has(peer_id):
		var rival: Node3D = _rival_rigs[peer_id].get("rival") as Node3D
		if rival != null and is_instance_valid(rival) and rival.is_inside_tree():
			return rival.global_position + Vector3(0.0, 1.5, 0.0)
	return Vector3.ZERO


func _get_rig_voice_level(peer_id: int) -> float:
	if VoiceChatManager != null and peer_id > 0 and VoiceChatManager.has_method("get_peer_voice_level"):
		return clampf(float(VoiceChatManager.call("get_peer_voice_level", peer_id)), 0.0, 1.0)
	return 0.0


func _on_world_cue_emitted(cue_id: String, world_pos: Vector3, radius: float, source_peer_id: int, variant_seed: int = -1) -> void:
	var t: float = _now_sec()
	var entry: Dictionary = {
		"time_sec": t,
		"cue_id": cue_id,
		"world_pos": world_pos,
		"radius": radius,
		"source_peer_id": source_peer_id,
		"variant_seed": variant_seed
	}
	_audio_cue_buffer.append(entry)
	var keep_sec: float = (GameConfig.crt_replay_duration if GameConfig != null else 3.0) + 2.0
	while not _audio_cue_buffer.is_empty() and t - float(_audio_cue_buffer[0]["time_sec"]) > keep_sec:
		_audio_cue_buffer.remove_at(0)

	for archived in _match_archive:
		if t <= float(archived.get("post_window_end_sec", 0.0)):
			var clip_start: float = float(archived.get("clip_start_sec", t))
			var cues: Array[Dictionary] = archived["audio_cues"]
			var rel_cue: Dictionary = entry.duplicate()
			rel_cue["rel_sec"] = maxf(t - clip_start, 0.0)
			cues.append(rel_cue)


func _on_voip_packet_captured(sender_peer_id: int, packet: PackedByteArray) -> void:
	if packet.is_empty():
		return
	var t: float = _now_sec()
	var is_header: bool = packet.size() > 3 and packet[0] == 123 and packet[-1] == 125
	if is_header:
		var parsed: Variant = JSON.parse_string(packet.get_string_from_ascii())
		if parsed is Dictionary and (parsed as Dictionary).has("talkingtimestart"):
			_latest_voip_headers[sender_peer_id] = packet.duplicate()

	var pkt_entry: Dictionary = {
		"time_sec": t,
		"sender_peer_id": sender_peer_id,
		"packet": packet.duplicate(),
		"sender_pos": _get_rig_world_pos(sender_peer_id),
		"is_header": is_header
	}
	_voice_packet_buffer.append(pkt_entry)
	var keep_sec: float = (GameConfig.crt_replay_duration if GameConfig != null else 3.0) + 2.0
	while not _voice_packet_buffer.is_empty() and t - float(_voice_packet_buffer[0]["time_sec"]) > keep_sec:
		_voice_packet_buffer.remove_at(0)

	for archived in _match_archive:
		if t <= float(archived.get("post_window_end_sec", 0.0)):
			var clip_start: float = float(archived.get("clip_start_sec", t))
			var pkts: Array[Dictionary] = archived["voice_packets"]
			var rel_pkt: Dictionary = pkt_entry.duplicate()
			rel_pkt["rel_sec"] = maxf(t - clip_start, 0.0)
			pkts.append(rel_pkt)


func archive_trap_hit(reason: String, victim_peer_id: int, attacker_peer_id: int = 0) -> void:
	if GameConfig != null and not GameConfig.crt_archive_enabled:
		return
	sync_rival_rigs()
	var snap: Dictionary = _build_replay_snapshot(reason, victim_peer_id)
	var now: float = _now_sec()
	var fps: int = maxi(GameConfig.crt_replay_fps if GameConfig != null else 24, 1)
	var pre_frames_count: int = (snap["playback_frames"] as Array).size()
	var pre_sec: float = float(pre_frames_count) / float(fps)
	var post_sec: float = clampf(GameConfig.crt_replay_post_hit_seconds if GameConfig != null else 2.75, 0.0, 3.5)
	var clip_start: float = now - pre_sec

	var victim_positions: Array[Vector3] = []
	var voice_peak: float = 0.0
	var voice_sum: float = 0.0
	if _rival_rigs.has(victim_peer_id):
		var src_pos: Array[Vector3] = _rival_rigs[victim_peer_id]["positions"]
		var start_idx: int = maxi(src_pos.size() - pre_frames_count, 0)
		for i in range(start_idx, src_pos.size()):
			victim_positions.append(src_pos[i])
		var src_voice: Array[float] = _rival_rigs[victim_peer_id].get("voice_levels", [] as Array[float])
		var v_start: int = maxi(src_voice.size() - pre_frames_count, 0)
		for i in range(v_start, src_voice.size()):
			var vl: float = src_voice[i]
			voice_peak = maxf(voice_peak, vl)
			voice_sum += vl
	while victim_positions.size() < pre_frames_count:
		victim_positions.append(_get_rig_world_pos(victim_peer_id))

	var cues: Array[Dictionary] = []
	for c in _audio_cue_buffer:
		var ct: float = float(c["time_sec"])
		if ct >= clip_start and ct <= now:
			var rel_c: Dictionary = c.duplicate()
			rel_c["rel_sec"] = ct - clip_start
			cues.append(rel_c)

	var v_pkts: Array[Dictionary] = []
	for p in _voice_packet_buffer:
		var pt: float = float(p["time_sec"])
		if pt >= clip_start and pt <= now:
			var rel_p: Dictionary = p.duplicate()
			rel_p["rel_sec"] = pt - clip_start
			v_pkts.append(rel_p)

	var entry: Dictionary = {
		"reason": reason.to_upper(),
		"victim_peer_id": victim_peer_id,
		"attacker_peer_id": attacker_peer_id,
		"victim_label": _resolve_spy_display_name(victim_peer_id),
		"attacker_label": _resolve_spy_display_name(attacker_peer_id) if attacker_peer_id > 0 else "TRAP",
		"playback_frames": snap["playback_frames"],
		"victim_positions": victim_positions,
		"impact_frame_idx": snap["impact_frame_idx"],
		"post_capture_remaining": snap["post_capture_remaining"],
		"audio_cues": cues,
		"voice_packets": v_pkts,
		"voice_headers": _latest_voip_headers.duplicate(),
		"clip_start_sec": clip_start,
		"post_window_end_sec": now + post_sec,
		"victim_voice_peak": voice_peak,
		"victim_voice_sum": voice_sum,
		"victim_voice_score": voice_peak + (voice_sum * 0.02),
		"fps": fps,
		"duration": GameConfig.crt_replay_duration if GameConfig != null else 5.25
	}
	_match_archive.append(entry)
	while _match_archive.size() > DEFAULT_RAW_ARCHIVE_CAP:
		_match_archive.remove_at(0)


func get_match_archive() -> Array[Dictionary]:
	var max_clips: int = GameConfig.crt_archive_max_clips if GameConfig != null else 10
	if max_clips <= 0 or _match_archive.size() <= max_clips:
		return _match_archive.duplicate()

	var ranked: Array[Dictionary] = _match_archive.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: float = float(a.get("victim_voice_score", 0.0))
		var sb: float = float(b.get("victim_voice_score", 0.0))
		if not is_equal_approx(sa, sb):
			return sa > sb
		return float(a.get("clip_start_sec", 0.0)) < float(b.get("clip_start_sec", 0.0))
	)
	var selected: Array[Dictionary] = []
	for i in range(mini(max_clips, ranked.size())):
		selected.append(ranked[i])
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("clip_start_sec", 0.0)) < float(b.get("clip_start_sec", 0.0))
	)
	return selected


func get_match_archive_count() -> int:
	return _match_archive.size()


func clear_match_archive() -> void:
	_match_archive.clear()


func _update_crt_visuals() -> void:
	var dur: float = GameConfig.crt_replay_duration if GameConfig != null else 4.5
	var burst_sec: float = 0.18
	var static_val: float = 0.03
	if _play_elapsed < burst_sec:
		static_val = 1.0 - (_play_elapsed / burst_sec)
	elif _play_elapsed > dur - burst_sec and _replay_queue.is_empty():
		static_val = (_play_elapsed - (dur - burst_sec)) / burst_sec

	var impact_flash_val: float = 0.0
	if _impact_frame_idx > 0:
		var frames_past_impact: int = _play_idx - _impact_frame_idx
		if frames_past_impact >= -1 and frames_past_impact <= 3:
			impact_flash_val = clampf(0.85 - float(maxi(frames_past_impact, 0)) * 0.25, 0.0, 0.85)

	if _crt_material != null:
		_crt_material.set_shader_parameter("static_amount", clampf(static_val, 0.02, 1.0))
		_crt_material.set_shader_parameter("impact_flash", impact_flash_val)
		_crt_material.set_shader_parameter("time_seed", _play_elapsed)


func _resolve_spy_display_name(victim_peer_id: int) -> String:
	if _rival_rigs.has(victim_peer_id):
		var rival: Node3D = _rival_rigs[victim_peer_id].get("rival") as Node3D
		if rival != null and is_instance_valid(rival):
			var role_val: int = int(rival.get("spy_role"))
			match role_val:
				1:
					return "GREEN SPY"
				2:
					return "PURPLE SPY"
				3:
					return "BLUE SPY"
				4:
					return "RED SPY"
	return "SPY %d" % victim_peer_id


func _show_frame(img: Image) -> void:
	if _texture_rect == null or img == null:
		return
	if _display_tex == null or _display_tex.get_size() != Vector2(img.get_size()):
		_display_tex = ImageTexture.create_from_image(img)
		_texture_rect.texture = _display_tex
	else:
		_display_tex.update(img)
