@tool
class_name EmbassyDoor
extends Node3D

## Unified Bidirectional Embassy Door (Doc 3 §2).
## Swings 90° away from whichever side the opener approaches from (Dot Product Rule).
## Supports Tap E (Fast Open), Hold E (Silent Slow Peek), Sprint Auto-Bash, and Water Bucket rigging.

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")

static var _splash_mesh: CylinderMesh = null
static var _splash_mat: StandardMaterial3D = null

@export var door_id: String = "EmbassyDoor"
@export var open_angle_deg: float = 90.0

var is_open: bool = false
var open_fraction: float = 0.0
var push_side_sign: float = -1.0
var current_target_angle_rad: float = 0.0
var has_rigged_bucket: bool = false
var bucket_owner_peer_id: int = 0
var bucket_side_sign: float = 1.0

var _hinge_pivot: Node3D = null
var _door_body: StaticBody3D = null
var _handle_pivot: Node3D = null
var _bucket_visual: Node3D = null
var _swing_tween: Tween = null
var _handle_tween: Tween = null
var _handle_release_timer: float = 0.0
var _step_start_rad: float = 0.0


func _ready() -> void:
	set_multiplayer_authority(1)
	_ensure_nodes()
	_apply_closed_visuals()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _handle_release_timer > 0.0:
		_handle_release_timer -= delta
		if _handle_release_timer <= 0.0:
			_release_handle_to_rest()


func _ensure_nodes() -> void:
	_hinge_pivot = get_node_or_null("HingePivot") as Node3D
	if _hinge_pivot == null:
		_hinge_pivot = Node3D.new()
		_hinge_pivot.name = "HingePivot"
		_hinge_pivot.position = Vector3(-0.59, 0.0, 0.0)
		add_child(_hinge_pivot)

	_door_body = _hinge_pivot.get_node_or_null("DoorLeaf") as StaticBody3D
	if _door_body == null:
		_door_body = StaticBody3D.new()
		_door_body.name = "DoorLeaf"
		_door_body.collision_layer = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3
		_door_body.collision_mask = 0
		_hinge_pivot.add_child(_door_body)

		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(1.18, 2.08, 0.068)
		col.shape = box
		col.position = Vector3(0.59, 1.04, 0.0)
		_door_body.add_child(col)

		var leaf_mesh := MeshInstance3D.new()
		leaf_mesh.name = "LeafMesh"
		var b_mesh := BoxMesh.new()
		b_mesh.size = Vector3(1.18, 2.08, 0.068)
		leaf_mesh.mesh = b_mesh
		leaf_mesh.position = Vector3(0.59, 1.04, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.38, 0.24)
		leaf_mesh.material_override = mat
		_door_body.add_child(leaf_mesh)
	else:
		_door_body.collision_layer = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3

	_handle_pivot = _door_body.get_node_or_null("HandlePivot") as Node3D

	_bucket_visual = get_node_or_null("BucketMount") as Node3D
	if _bucket_visual == null:
		_bucket_visual = PICKUP_SCRIPT.build_item_visual("BUCKET")
		_bucket_visual.name = "BucketMount"
		_bucket_visual.visible = has_rigged_bucket
		add_child(_bucket_visual)
		var hitbox := StaticBody3D.new()
		hitbox.name = "BucketHitbox"
		hitbox.collision_layer = GameConfig.LAYER_INTERACTABLE if GameConfig != null else 2
		hitbox.collision_mask = 0
		hitbox.set_meta("bucket_door", self)
		var hcol := CollisionShape3D.new()
		hcol.name = "CollisionShape3D"
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.22
		cyl.height = 0.36
		hcol.shape = cyl
		hcol.position = Vector3(0.0, -0.02, 0.0)
		hcol.disabled = not has_rigged_bucket
		hitbox.add_child(hcol)
		_bucket_visual.add_child(hitbox)
	_update_bucket_mount_transform()


func _get_bucket_ajar_rad() -> float:
	var ajar_deg: float = GameConfig.door_bucket_ajar_angle_deg if GameConfig != null else 10.0
	return deg_to_rad(ajar_deg) * (-bucket_side_sign)


func _update_bucket_mount_transform() -> void:
	if _bucket_visual == null or not is_instance_valid(_bucket_visual):
		return
	var ajar_rad: float = _get_bucket_ajar_rad()
	var hinge_pos: Vector3 = _hinge_pivot.position if _hinge_pivot != null else Vector3(-0.59, 0.0, 0.0)
	_bucket_visual.position = hinge_pos + Basis(Vector3.UP, ajar_rad) * Vector3(1.00, 2.244, bucket_side_sign * 0.055)
	_bucket_visual.rotation = Vector3(0.0, ajar_rad, 0.0)


func _safe_global_transform() -> Transform3D:
	return global_transform if is_inside_tree() else transform


func _safe_global_pos() -> Vector3:
	return global_position if is_inside_tree() else position


func compute_away_angle_rad(opener_world_pos: Vector3) -> float:
	var xform: Transform3D = _safe_global_transform()
	var forward: Vector3 = -xform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var to_opener: Vector3 = opener_world_pos - xform.origin
	to_opener.y = 0.0
	var dot_val: float = forward.dot(to_opener)
	# +X door leaf rotated by -90° around +Y swings toward +Z; +90° swings toward -Z.
	var side: float = -1.0 if dot_val >= 0.0 else 1.0
	return side * deg_to_rad(open_angle_deg)


func get_interaction_prompt() -> String:
	if is_open:
		return "[Tap E] Close  |  [Hold E] Pull Shut"
	if has_rigged_bucket:
		return "[Tap E] Open  |  [Hold E] Peek  |  [Look Up + E] Steal Bucket"
	return "[Tap E] Fast Open  |  [Hold E] Slowly Push Open"


func get_hold_interaction_duration() -> float:
	return GameConfig.door_slow_peek_hold_time if GameConfig != null else 2.80


func request_step_push(caller_peer_id: int, delta: float, want_open: int = -1) -> void:
	var opener_pos: Vector3 = _resolve_opener_position(caller_peer_id)
	if _is_peer_connected():
		_server_step_push.rpc_id(1, caller_peer_id, delta, opener_pos, want_open)
	else:
		_execute_step_push(caller_peer_id, delta, opener_pos, want_open)


func request_begin_peek(_caller_peer_id: int) -> void:
	pass


func request_interaction(caller_peer_id: int) -> void:
	var opener_pos: Vector3 = _resolve_opener_position(caller_peer_id)
	if _is_peer_connected():
		_server_door_action.rpc_id(1, caller_peer_id, "FAST_TOGGLE", opener_pos)
	else:
		_execute_door_action(caller_peer_id, "FAST_TOGGLE", opener_pos)


func request_hold_interaction(caller_peer_id: int) -> void:
	var opener_pos: Vector3 = _resolve_opener_position(caller_peer_id)
	if _is_peer_connected():
		_server_door_action.rpc_id(1, caller_peer_id, "SLOW_PEEK", opener_pos)
	else:
		_execute_door_action(caller_peer_id, "SLOW_PEEK", opener_pos)


func request_sprint_bash(caller_peer_id: int, basher_pos: Vector3) -> void:
	if is_open:
		return
	if _is_peer_connected():
		_server_door_action.rpc_id(1, caller_peer_id, "SPRINT_BASH", basher_pos)
	else:
		_execute_door_action(caller_peer_id, "SPRINT_BASH", basher_pos)


func _compute_bucket_side_sign(armer_world_pos: Vector3) -> float:
	var xform: Transform3D = _safe_global_transform()
	var z_axis: Vector3 = xform.basis.z
	z_axis.y = 0.0
	if z_axis.length_squared() < 0.0001:
		z_axis = Vector3.BACK
	else:
		z_axis = z_axis.normalized()
	var to_armer: Vector3 = armer_world_pos - xform.origin
	to_armer.y = 0.0
	return 1.0 if z_axis.dot(to_armer) >= 0.0 else -1.0


func rig_water_bucket(owner_peer_id: int, other_side: bool = false) -> bool:
	_ensure_nodes()
	if is_open or has_rigged_bucket:
		return false
	has_rigged_bucket = true
	bucket_owner_peer_id = owner_peer_id
	var base_sign: float = _compute_bucket_side_sign(_resolve_opener_position(owner_peer_id))
	bucket_side_sign = -base_sign if other_side else base_sign
	_apply_closed_visuals()
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("trap_arm", _safe_global_pos() + Vector3(0.0, 2.0, 0.0), GameConfig.audio_radius_trap_setup, owner_peer_id)
	if _is_peer_connected():
		_rpc_sync_door.rpc(is_open, current_target_angle_rad, 0.0, has_rigged_bucket, bucket_side_sign)
	return true


func set_prearmed_water_bucket(armed: bool, side_sign: float = 1.0) -> void:
	_ensure_nodes()
	is_open = false
	open_fraction = 0.0
	current_target_angle_rad = 0.0
	has_rigged_bucket = armed
	bucket_owner_peer_id = 0
	bucket_side_sign = 1.0 if side_sign >= 0.0 else -1.0
	_apply_closed_visuals()


func get_bucket_world_position() -> Vector3:
	if _bucket_visual != null and is_instance_valid(_bucket_visual):
		return _bucket_visual.global_position if _bucket_visual.is_inside_tree() else _bucket_visual.position
	return _safe_global_pos() + Vector3(0.0, 2.24, 0.0)


func request_steal_bucket(caller_peer_id: int) -> void:
	if not has_rigged_bucket:
		return
	if _is_peer_connected():
		_server_steal_bucket.rpc_id(1, caller_peer_id)
	else:
		steal_water_bucket(caller_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _server_steal_bucket(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != caller_peer_id:
		caller_peer_id = sender_id
	steal_water_bucket(caller_peer_id)


func steal_water_bucket(thief_peer_id: int, player_override: Node = null) -> bool:
	if not has_rigged_bucket:
		return false
	var player: Node = player_override if player_override != null else _find_player_node(thief_peer_id)
	if player != null and player.has_method("server_pickup_world_item"):
		if not player.server_pickup_world_item("BUCKET", [], _safe_global_pos()):
			return false
	has_rigged_bucket = false
	bucket_owner_peer_id = 0
	var keep_ajar_rad: float = _get_bucket_ajar_rad() if not is_open else current_target_angle_rad
	current_target_angle_rad = keep_ajar_rad
	if _bucket_visual != null:
		_bucket_visual.visible = false
		var hcol: CollisionShape3D = _bucket_visual.get_node_or_null("BucketHitbox/CollisionShape3D") as CollisionShape3D
		if hcol != null:
			hcol.disabled = true
	if _is_peer_connected():
		_rpc_sync_door.rpc(is_open, current_target_angle_rad, 0.0, has_rigged_bucket, bucket_side_sign)
	else:
		_rpc_sync_door(is_open, current_target_angle_rad, 0.0, has_rigged_bucket, bucket_side_sign)
	return true


@rpc("any_peer", "call_local", "reliable")
func _server_step_push(caller_peer_id: int, delta: float, opener_pos: Vector3, want_open: int = -1) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != caller_peer_id:
		caller_peer_id = sender_id
	var player: Node = _find_player_node(caller_peer_id)
	if player != null and player is Node3D:
		opener_pos = (player as Node3D).global_position
		if opener_pos.distance_to(_safe_global_pos()) > 3.5:
			return
	_execute_step_push(caller_peer_id, delta, opener_pos, want_open)


func _execute_step_push(peer_id: int, delta: float, opener_pos: Vector3, want_open: int = -1) -> void:
	if (want_open == 1 and is_open) or (want_open == 0 and not is_open):
		return
	var slow_dur: float = GameConfig.door_slow_peek_swing_duration if GameConfig != null else 2.80
	var step: float = clampf(delta, 0.0, 0.15) / maxf(slow_dur, 0.5)
	if is_open:
		open_fraction = clampf(open_fraction - step, 0.0, 1.0)
		if open_fraction <= 0.02:
			open_fraction = 0.0
			is_open = false
			_step_start_rad = 0.0
		current_target_angle_rad = push_side_sign * deg_to_rad(open_angle_deg) * open_fraction
	else:
		if open_fraction <= 0.001:
			var away_rad: float = compute_away_angle_rad(opener_pos)
			push_side_sign = 1.0 if away_rad >= 0.0 else -1.0
			var current_rel_rad: float = _hinge_pivot.rotation.y if _hinge_pivot != null else current_target_angle_rad
			if absf(current_rel_rad) > 0.01:
				if (away_rad * current_rel_rad) > 0.0:
					_step_start_rad = 0.0
					open_fraction = clampf(absf(current_rel_rad) / maxf(deg_to_rad(open_angle_deg), 1.0), 0.0, 0.95)
				else:
					_step_start_rad = current_rel_rad
					open_fraction = 0.0
			else:
				_step_start_rad = 0.0
		open_fraction = clampf(open_fraction + step, 0.0, 1.0)
		if open_fraction >= 0.98:
			open_fraction = 1.0
			is_open = true
			_step_start_rad = 0.0
		var full_target_rad: float = push_side_sign * deg_to_rad(open_angle_deg)
		current_target_angle_rad = lerpf(_step_start_rad, full_target_rad, open_fraction)

	if has_rigged_bucket:
		var opener_side: float = _compute_bucket_side_sign(opener_pos)
		var ajar_rad: float = _get_bucket_ajar_rad()
		var same_delta_deg: float = GameConfig.door_bucket_same_side_release_delta_deg if GameConfig != null else 4.0
		var opp_release_deg: float = GameConfig.door_bucket_release_angle_deg if GameConfig != null else 28.0
		var should_drop: bool = (
			absf(current_target_angle_rad - ajar_rad) >= deg_to_rad(same_delta_deg)
			if (opener_side == bucket_side_sign)
			else absf(current_target_angle_rad) >= deg_to_rad(opp_release_deg)
		)
		if should_drop:
			has_rigged_bucket = false
			var owner_id: int = bucket_owner_peer_id
			bucket_owner_peer_id = 0
			_resolve_bucket_drop(peer_id, opener_pos, owner_id)

	if _is_peer_connected():
		_rpc_sync_door.rpc(is_open, current_target_angle_rad, 0.0, has_rigged_bucket, bucket_side_sign, true)
	else:
		_rpc_sync_door(is_open, current_target_angle_rad, 0.0, has_rigged_bucket, bucket_side_sign, true)


@rpc("any_peer", "call_local", "reliable")
func _server_door_action(caller_peer_id: int, mode: String, opener_pos: Vector3) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != caller_peer_id:
		caller_peer_id = sender_id
	var player: Node = _find_player_node(caller_peer_id)
	if player != null and player is Node3D:
		opener_pos = (player as Node3D).global_position
		if opener_pos.distance_to(_safe_global_pos()) > 3.5:
			return
	_execute_door_action(caller_peer_id, mode, opener_pos)


func _execute_door_action(peer_id: int, mode: String, opener_pos: Vector3) -> void:
	var duration: float = 0.25
	var pos_now: Vector3 = _safe_global_pos()
	if is_open:
		if mode != "FAST_TOGGLE" and mode != "SLOW_PEEK":
			return
		is_open = false
		open_fraction = 0.0
		current_target_angle_rad = 0.0
		duration = GameConfig.door_close_duration if GameConfig != null else 0.30
		if mode == "FAST_TOGGLE" and AudioBridge != null and GameConfig != null:
			AudioBridge.request_world_cue("door_close", pos_now, GameConfig.audio_radius_door_close, peer_id)
	else:
		is_open = true
		open_fraction = 1.0
		current_target_angle_rad = compute_away_angle_rad(opener_pos)
		push_side_sign = 1.0 if current_target_angle_rad >= 0.0 else -1.0
		match mode:
			"SPRINT_BASH":
				duration = GameConfig.door_sprint_bash_duration if GameConfig != null else 0.12
				if AudioBridge != null and GameConfig != null:
					AudioBridge.request_world_cue("door_bash", pos_now, GameConfig.audio_radius_door_bash, peer_id)
			"SLOW_PEEK":
				duration = GameConfig.door_slow_peek_swing_duration if GameConfig != null else 2.80
			_:
				duration = GameConfig.door_fast_open_duration if GameConfig != null else 0.25
				if AudioBridge != null and GameConfig != null:
					AudioBridge.request_world_cue("door_open", pos_now, GameConfig.audio_radius_door_fast, peer_id)

		if has_rigged_bucket:
			_trigger_rigged_bucket_on_open(peer_id, opener_pos, duration)

	var use_handle: bool = (mode != "SPRINT_BASH")
	if _is_peer_connected():
		_rpc_sync_door.rpc(is_open, current_target_angle_rad, duration, has_rigged_bucket, bucket_side_sign, use_handle)
	else:
		_rpc_sync_door(is_open, current_target_angle_rad, duration, has_rigged_bucket, bucket_side_sign, use_handle)


func _trigger_rigged_bucket_on_open(opener_peer_id: int, opener_pos: Vector3, swing_duration: float) -> void:
	var opener_side: float = _compute_bucket_side_sign(opener_pos)
	var start_rad: float = _hinge_pivot.rotation.y if _hinge_pivot != null else _get_bucket_ajar_rad()
	var total_span: float = maxf(absf(current_target_angle_rad - start_rad), 0.05)
	var delay: float = 0.0
	if opener_side == bucket_side_sign:
		var same_delta_rad: float = deg_to_rad(GameConfig.door_bucket_same_side_release_delta_deg if GameConfig != null else 4.0)
		delay = swing_duration * clampf(same_delta_rad / total_span, 0.02, 0.9)
	else:
		var opp_release_rad: float = deg_to_rad(GameConfig.door_bucket_release_angle_deg if GameConfig != null else 28.0)
		var remaining_rad: float = maxf(opp_release_rad - absf(start_rad), 0.0)
		delay = swing_duration * clampf(remaining_rad / total_span, 0.02, 0.9)
	var owner_id: int = bucket_owner_peer_id
	has_rigged_bucket = false
	bucket_owner_peer_id = 0

	if not is_inside_tree():
		_resolve_bucket_drop(opener_peer_id, opener_pos, owner_id)
		return

	get_tree().create_timer(delay).timeout.connect(func():
		var live_opener_pos: Vector3 = opener_pos
		var opener_node: Node = _find_player_node(opener_peer_id)
		if opener_node is Node3D:
			live_opener_pos = (opener_node as Node3D).global_position
		_resolve_bucket_drop(opener_peer_id, live_opener_pos, owner_id)
	)


func _resolve_bucket_drop(opener_peer_id: int, opener_pos: Vector3, owner_id: int) -> void:
	var drop_local_pos: Vector3 = _bucket_visual.position if _bucket_visual != null else Vector3(0.0, 2.29, bucket_side_sign * 0.30)
	if is_inside_tree():
		if _is_peer_connected():
			_rpc_play_bucket_drop_fx.rpc(drop_local_pos)
		else:
			_rpc_play_bucket_drop_fx(drop_local_pos)
	var drop_world_pos: Vector3 = _safe_global_transform() * drop_local_pos
	var impact_delay: float = GameConfig.bucket_fall_impact_delay if GameConfig != null else 0.10
	if not is_inside_tree() or Engine.is_editor_hint() or impact_delay <= 0.005:
		_apply_bucket_impact(opener_peer_id, opener_pos, owner_id, drop_world_pos)
		return
	get_tree().create_timer(impact_delay).timeout.connect(func():
		var live_opener_pos: Vector3 = opener_pos
		var opener_node: Node = _find_player_node(opener_peer_id)
		if opener_node is Node3D:
			live_opener_pos = (opener_node as Node3D).global_position
		_apply_bucket_impact(opener_peer_id, live_opener_pos, owner_id, drop_world_pos)
	)


func _apply_bucket_impact(opener_peer_id: int, opener_pos: Vector3, owner_id: int, drop_world_pos: Vector3) -> void:
	var flat_dist: float = Vector2(opener_pos.x - drop_world_pos.x, opener_pos.z - drop_world_pos.z).length()
	var hit_radius: float = GameConfig.bucket_hit_radius if GameConfig != null else 1.2
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("bucket_spill", drop_world_pos, GameConfig.audio_radius_bucket_spill, owner_id)
	if flat_dist <= hit_radius:
		var player: Node = _find_player_node(opener_peer_id)
		if player != null and player.has_method("apply_trap_ko"):
			player.apply_trap_ko("BUCKET", owner_id)


static func _get_splash_mesh() -> CylinderMesh:
	if _splash_mesh == null:
		_splash_mesh = CylinderMesh.new()
		_splash_mesh.top_radius = 0.25
		_splash_mesh.bottom_radius = 0.25
		_splash_mesh.height = 0.02
	return _splash_mesh


static func _get_splash_mat() -> StandardMaterial3D:
	if _splash_mat == null:
		_splash_mat = StandardMaterial3D.new()
		_splash_mat.albedo_color = Color(0.32, 0.78, 0.98)
		_splash_mat.roughness = 0.2
	return _splash_mat


@rpc("authority", "call_local", "reliable")
func _rpc_play_bucket_drop_fx(drop_local_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var fx_root := Node3D.new()
	fx_root.name = "BucketDropFX"
	add_child(fx_root)
	var falling: Node3D = PICKUP_SCRIPT.build_item_visual("BUCKET")
	falling.position = drop_local_pos
	fx_root.add_child(falling)
	var tw := fx_root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(falling, "position:y", 0.14, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(falling, "rotation:x", PI * 0.85 * bucket_side_sign, 0.18)
	tw.chain().tween_callback(func():
		if not is_instance_valid(fx_root):
			return
		var splash := MeshInstance3D.new()
		splash.mesh = _get_splash_mesh()
		splash.material_override = _get_splash_mat()
		splash.position = Vector3(drop_local_pos.x, 0.02, drop_local_pos.z)
		fx_root.add_child(splash)
		var hit_r: float = GameConfig.bucket_hit_radius if GameConfig != null else 1.2
		var stw := fx_root.create_tween()
		stw.tween_property(splash, "scale", Vector3(hit_r * 3.5, 1.0, hit_r * 3.5), 0.22).set_ease(Tween.EASE_OUT)
		stw.tween_property(splash, "scale", Vector3(0.01, 1.0, 0.01), 0.33).set_ease(Tween.EASE_IN)
		stw.parallel().tween_property(falling, "position:y", -0.20, 0.33)
		stw.tween_callback(fx_root.queue_free)
	)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_door(opened: bool, target_angle_rad: float, duration: float, bucket_rigged: bool, bucket_side: float = 1.0, animate_handle: bool = false) -> void:
	_ensure_nodes()
	is_open = opened
	if duration > 0.0:
		open_fraction = clampf(absf(target_angle_rad) / maxf(deg_to_rad(open_angle_deg), 0.01), 0.0, 1.0)
	if absf(target_angle_rad) > 0.01:
		push_side_sign = 1.0 if target_angle_rad >= 0.0 else -1.0
	if _door_body != null:
		_door_body.collision_layer = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3
	current_target_angle_rad = target_angle_rad
	has_rigged_bucket = bucket_rigged
	bucket_side_sign = 1.0 if bucket_side >= 0.0 else -1.0
	if _bucket_visual != null:
		_update_bucket_mount_transform()
		_bucket_visual.visible = has_rigged_bucket
		var hcol: CollisionShape3D = _bucket_visual.get_node_or_null("BucketHitbox/CollisionShape3D") as CollisionShape3D
		if hcol != null:
			hcol.disabled = not has_rigged_bucket

	if animate_handle:
		if duration > 0.0:
			_pulse_handle_press()
		else:
			_hold_handle_pressed()

	var final_rad: float = target_angle_rad
	if not is_open and absf(target_angle_rad) <= 0.001 and has_rigged_bucket:
		final_rad = _get_bucket_ajar_rad()

	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()

	if duration <= 0.0:
		_hinge_pivot.rotation.y = final_rad
		return

	var total_span: float = maxf(deg_to_rad(open_angle_deg), 0.1)
	var remaining_span: float = absf(final_rad - _hinge_pivot.rotation.y)
	var scaled_dur: float = duration * clampf(remaining_span / total_span, 0.12, 1.0)

	if is_inside_tree() and scaled_dur > 0.01 and not is_equal_approx(_hinge_pivot.rotation.y, final_rad):
		_swing_tween = create_tween()
		_swing_tween.tween_property(_hinge_pivot, "rotation:y", final_rad, scaled_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_hinge_pivot.rotation.y = final_rad


func _pulse_handle_press() -> void:
	if _handle_pivot == null or not is_instance_valid(_handle_pivot):
		return
	_handle_release_timer = 0.0
	if _handle_tween != null and _handle_tween.is_valid():
		_handle_tween.kill()
	var press_rad: float = deg_to_rad(32.0)
	if not is_inside_tree():
		_handle_pivot.rotation.z = 0.0
		return
	_handle_tween = create_tween()
	_handle_tween.tween_property(_handle_pivot, "rotation:z", press_rad, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_handle_tween.tween_property(_handle_pivot, "rotation:z", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hold_handle_pressed() -> void:
	if _handle_pivot == null or not is_instance_valid(_handle_pivot):
		return
	_handle_release_timer = 0.14
	var press_rad: float = deg_to_rad(32.0)
	if _handle_tween != null and _handle_tween.is_valid():
		_handle_tween.kill()
	if not is_inside_tree():
		_handle_pivot.rotation.z = press_rad
		return
	if absf(_handle_pivot.rotation.z - press_rad) > 0.02:
		_handle_tween = create_tween()
		_handle_tween.tween_property(_handle_pivot, "rotation:z", press_rad, 0.05).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_handle_pivot.rotation.z = press_rad


func _release_handle_to_rest() -> void:
	if _handle_pivot == null or not is_instance_valid(_handle_pivot):
		return
	if _handle_tween != null and _handle_tween.is_valid():
		_handle_tween.kill()
	if not is_inside_tree():
		_handle_pivot.rotation.z = 0.0
		return
	_handle_tween = create_tween()
	_handle_tween.tween_property(_handle_pivot, "rotation:z", 0.0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply_closed_visuals() -> void:
	if _hinge_pivot == null:
		return
	if _bucket_visual != null:
		_update_bucket_mount_transform()
		_bucket_visual.visible = has_rigged_bucket
		var hcol: CollisionShape3D = _bucket_visual.get_node_or_null("BucketHitbox/CollisionShape3D") as CollisionShape3D
		if hcol != null:
			hcol.disabled = not has_rigged_bucket
	if not is_open:
		_hinge_pivot.rotation.y = _get_bucket_ajar_rad() if has_rigged_bucket else 0.0


func _resolve_opener_position(peer_id: int) -> Vector3:
	var p: Node = _find_player_node(peer_id)
	if p is Node3D:
		return (p as Node3D).global_position if (p as Node3D).is_inside_tree() else (p as Node3D).position
	var xform: Transform3D = _safe_global_transform()
	return xform.origin + (-xform.basis.z)


func _find_player_node(peer_id: int) -> Node:
	if not is_inside_tree() or get_tree() == null:
		return null
	var scene: Node = get_tree().current_scene
	if scene != null:
		var p: Node = scene.get_node_or_null("Players/" + str(peer_id))
		if p != null:
			return p
	var parent: Node = get_parent()
	if parent != null:
		var p2: Node = parent.get_node_or_null("Players/" + str(peer_id))
		if p2 != null:
			return p2
	for candidate in get_tree().get_nodes_in_group("spy_players"):
		if candidate.name.to_int() == peer_id:
			return candidate
	return null


func _is_peer_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
