extends MeshInstance3D

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")

static var _splash_mesh: CylinderMesh = null
static var _splash_mat: StandardMaterial3D = null

@export var open_angle: float = -90.0
@export var swing_duration: float = 0.3

var is_open: bool = false
var has_rigged_bucket: bool = false
var bucket_owner_peer_id: int = 0
var bucket_side_sign: float = 1.0
var _closed_rotation: float = 0.0
var _open_fraction: float = 0.0
var _push_target_y: float = 0.0
var _swing: Tween
var _busy: bool = false
var _bucket_visual: Node3D = null
var _step_start_y: float = 0.0

func _ready() -> void:
	set_multiplayer_authority(1)
	is_open = absf(rotation.y) > 0.5
	_closed_rotation = 0.0 if is_open else rotation.y
	_open_fraction = 1.0 if is_open else 0.0
	_push_target_y = rotation.y if is_open else (_closed_rotation + deg_to_rad(open_angle))
	for body in find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 3
		for col in body.get_children():
			if col is CollisionShape3D and (col as CollisionShape3D).shape is ConcavePolygonShape3D:
				var solid_box := BoxShape3D.new()
				solid_box.size = Vector3(1.20, 2.08, 0.062)
				(col as CollisionShape3D).shape = solid_box
				(col as CollisionShape3D).position = Vector3(0.605, 0.0, 0.031)
	_ensure_bucket_visual()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state.call_deferred()


func _exit_tree() -> void:
	if _bucket_visual != null and is_instance_valid(_bucket_visual) and _bucket_visual.get_parent() != self:
		_bucket_visual.queue_free()
		_bucket_visual = null


func _ensure_bucket_visual() -> void:
	var target_parent: Node = get_parent() if get_parent() != null else self
	var mount_name: String = "BucketMount_%d" % get_instance_id()
	if _bucket_visual == null or not is_instance_valid(_bucket_visual):
		_bucket_visual = target_parent.get_node_or_null(mount_name) as Node3D
	if _bucket_visual == null:
		_bucket_visual = PICKUP_SCRIPT.build_item_visual("BUCKET")
		_bucket_visual.name = mount_name
		_bucket_visual.visible = has_rigged_bucket
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
		if target_parent == self or target_parent.is_node_ready():
			target_parent.add_child(_bucket_visual)
		else:
			target_parent.add_child.call_deferred(_bucket_visual)
	elif _bucket_visual.get_parent() != null and _bucket_visual.get_parent() != target_parent:
		_bucket_visual.get_parent().remove_child(_bucket_visual)
		if target_parent == self or target_parent.is_node_ready():
			target_parent.add_child(_bucket_visual)
		else:
			target_parent.add_child.call_deferred(_bucket_visual)
	_update_bucket_visual_transform()


func _get_bucket_ajar_rad() -> float:
	var ajar_deg: float = GameConfig.door_bucket_ajar_angle_deg if GameConfig != null else 10.0
	return deg_to_rad(ajar_deg) * (-bucket_side_sign)


func _update_bucket_visual_transform() -> void:
	if _bucket_visual == null or not is_instance_valid(_bucket_visual):
		return
	var ajar_rad: float = _get_bucket_ajar_rad()
	var z_local: float = 0.031 + (0.13 if bucket_side_sign > 0.0 else 0.0)
	var local_pos := Vector3(1.05, 1.183, z_local)
	if _bucket_visual.get_parent() == self:
		_bucket_visual.position = local_pos
		_bucket_visual.rotation = Vector3.ZERO
	else:
		var ajar_basis := Basis(Vector3.UP, _closed_rotation + ajar_rad)
		_bucket_visual.position = position + ajar_basis * local_pos
		_bucket_visual.rotation = Vector3(0.0, _closed_rotation + ajar_rad, 0.0)

func get_interaction_prompt() -> String:
	if is_open:
		return "[Tap E] Close  |  [Hold E] Pull Shut"
	if has_rigged_bucket:
		return "[Tap E] Open  |  [Hold E] Peek  |  [Look Up + E] Steal Bucket"
	return "[Tap E] Fast Open  |  [Hold E] Slowly Push Open"


func get_hold_interaction_duration() -> float:
	return GameConfig.door_slow_peek_hold_time if GameConfig != null else 2.80


func request_step_push(_peer_id: int, delta: float, want_open: int = -1) -> void:
	if multiplayer.is_server():
		server_step_push(delta, want_open)
	else:
		server_step_push.rpc_id(1, delta, want_open)


func request_begin_peek(_peer_id: int) -> void:
	pass


func request_interaction(_peer_id: int) -> void:
	if multiplayer.is_server():
		server_interact(false, false)
	else:
		server_interact.rpc_id(1, false, false)


func request_hold_interaction(_peer_id: int) -> void:
	if multiplayer.is_server():
		server_interact(true, false)
	else:
		server_interact.rpc_id(1, true, false)


func request_sprint_bash(_peer_id: int, _basher_pos: Vector3) -> void:
	if is_open:
		return
	if multiplayer.is_server():
		server_interact(false, true)
	else:
		server_interact.rpc_id(1, false, true)


func _find_player_node(peer_id: int) -> Node:
	if not is_inside_tree() or get_tree() == null:
		return null
	var scene: Node = get_tree().current_scene
	if scene != null:
		var p: Node = scene.get_node_or_null("Players/" + str(peer_id))
		if p != null:
			return p
	for candidate in get_tree().get_nodes_in_group("spy_players"):
		if candidate.name.to_int() == peer_id:
			return candidate
	return null


func _compute_bucket_side_sign(owner_peer_id: int) -> float:
	var player: Node = _find_player_node(owner_peer_id)
	if not (player is Node3D):
		return 1.0
	var door_basis: Basis = (get_parent() as Node3D).global_basis * Basis(Vector3.UP, _closed_rotation) if get_parent() is Node3D else global_basis
	var z_axis: Vector3 = door_basis.z
	z_axis.y = 0.0
	if z_axis.length_squared() < 0.0001:
		z_axis = Vector3.BACK
	else:
		z_axis = z_axis.normalized()
	var origin: Vector3 = global_position if is_inside_tree() else position
	var to_armer: Vector3 = (player as Node3D).global_position - origin
	to_armer.y = 0.0
	return 1.0 if z_axis.dot(to_armer) >= 0.0 else -1.0


func rig_water_bucket(owner_peer_id: int, other_side: bool = false) -> bool:
	_ensure_bucket_visual()
	if is_open or has_rigged_bucket:
		return false
	has_rigged_bucket = true
	bucket_owner_peer_id = owner_peer_id
	var base_sign: float = _compute_bucket_side_sign(owner_peer_id)
	bucket_side_sign = -base_sign if other_side else base_sign
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("bucket_arm", global_position + Vector3(0.0, 2.0, 0.0), GameConfig.audio_radius_bucket_arm, owner_peer_id)
	if _is_peer_connected():
		_rpc_sync_bucket_state.rpc(true, bucket_side_sign)
	else:
		_rpc_sync_bucket_state(true, bucket_side_sign)
	return true


func set_prearmed_water_bucket(armed: bool, side_sign: float = 1.0) -> void:
	_ensure_bucket_visual()
	is_open = false
	_open_fraction = 0.0
	rotation.y = _closed_rotation
	has_rigged_bucket = armed
	bucket_owner_peer_id = 0
	bucket_side_sign = 1.0 if side_sign >= 0.0 else -1.0
	if _bucket_visual != null:
		_bucket_visual.visible = has_rigged_bucket
		var hcol: CollisionShape3D = _bucket_visual.get_node_or_null("BucketHitbox/CollisionShape3D") as CollisionShape3D
		if hcol != null:
			hcol.disabled = not has_rigged_bucket
	_update_bucket_visual_transform()
	if has_rigged_bucket:
		rotation.y = _closed_rotation + _get_bucket_ajar_rad()


func get_bucket_world_position() -> Vector3:
	if _bucket_visual != null and is_instance_valid(_bucket_visual):
		return _bucket_visual.global_position if _bucket_visual.is_inside_tree() else _bucket_visual.position
	return (global_position if is_inside_tree() else position) + Vector3(0.0, 1.15, 0.0)


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
	if sender_id != 0:
		caller_peer_id = sender_id
	steal_water_bucket(caller_peer_id)


func steal_water_bucket(thief_peer_id: int, player_override: Node = null) -> bool:
	if not has_rigged_bucket:
		return false
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	var player: Node = player_override if player_override != null else (scene.get_node_or_null("Players/" + str(thief_peer_id)) if scene != null else null)
	if player != null and player.has_method("server_pickup_world_item"):
		if not player.server_pickup_world_item("BUCKET", [], global_position):
			return false
	has_rigged_bucket = false
	bucket_owner_peer_id = 0
	if _is_peer_connected():
		_rpc_sync_bucket_state.rpc(false, bucket_side_sign, false)
	else:
		_rpc_sync_bucket_state(false, bucket_side_sign, false)
	return true


@rpc("authority", "call_local", "reliable")
func _rpc_sync_bucket_state(rigged: bool, bucket_side: float = 1.0, snap_closed: bool = true) -> void:
	bucket_side_sign = 1.0 if bucket_side >= 0.0 else -1.0
	_ensure_bucket_visual()
	has_rigged_bucket = rigged
	if _bucket_visual != null:
		_bucket_visual.visible = has_rigged_bucket
		var hcol: CollisionShape3D = _bucket_visual.get_node_or_null("BucketHitbox/CollisionShape3D") as CollisionShape3D
		if hcol != null:
			hcol.disabled = not has_rigged_bucket
	if not is_open and snap_closed:
		rotation.y = (_closed_rotation + _get_bucket_ajar_rad()) if has_rigged_bucket else _closed_rotation


func _trigger_rigged_bucket_drop(opener_peer_id: int, swing_dur: float) -> void:
	var owner_id: int = bucket_owner_peer_id
	var opener_side: float = _compute_bucket_side_sign(opener_peer_id)
	var start_rel_rad: float = wrapf(rotation.y - _closed_rotation, -PI, PI)
	var open_rad: float = maxf(deg_to_rad(absf(open_angle)), 0.1)
	var delay: float = 0.0
	if swing_dur > 0.0:
		if opener_side == bucket_side_sign:
			var same_delta_rad: float = deg_to_rad(GameConfig.door_bucket_same_side_release_delta_deg if GameConfig != null else 4.0)
			delay = clampf(swing_dur * (same_delta_rad / open_rad), 0.0, 1.5)
		else:
			var opp_release_rad: float = deg_to_rad(GameConfig.door_bucket_release_angle_deg if GameConfig != null else 28.0)
			var remaining_rad: float = maxf(opp_release_rad - absf(start_rel_rad), 0.0)
			delay = clampf(swing_dur * (remaining_rad / open_rad), 0.0, 1.5)
	var drop_world_pos: Vector3 = _bucket_visual.global_position if (_bucket_visual != null and _bucket_visual.is_inside_tree()) else ((global_position if is_inside_tree() else position) + Vector3(0.60, 1.18, 0.0))
	has_rigged_bucket = false
	bucket_owner_peer_id = 0
	if _is_peer_connected():
		_rpc_sync_bucket_state.rpc(false, bucket_side_sign, false)
	else:
		_rpc_sync_bucket_state(false, bucket_side_sign, false)
	if not is_inside_tree() or delay <= 0.01:
		_resolve_bucket_drop(opener_peer_id, owner_id, drop_world_pos)
		return
	get_tree().create_timer(delay).timeout.connect(func():
		_resolve_bucket_drop(opener_peer_id, owner_id, drop_world_pos)
	)


func _resolve_bucket_drop(opener_peer_id: int, owner_id: int, drop_world_pos: Vector3 = Vector3.INF) -> void:
	if is_inside_tree() and drop_world_pos != Vector3.INF:
		if _is_peer_connected():
			_rpc_play_bucket_drop_fx.rpc(drop_world_pos, bucket_side_sign)
		else:
			_rpc_play_bucket_drop_fx(drop_world_pos, bucket_side_sign)
	var impact_delay: float = GameConfig.bucket_fall_impact_delay if GameConfig != null else 0.10
	if not is_inside_tree() or Engine.is_editor_hint() or impact_delay <= 0.005:
		_apply_bucket_impact(opener_peer_id, owner_id, drop_world_pos)
		return
	get_tree().create_timer(impact_delay).timeout.connect(func():
		_apply_bucket_impact(opener_peer_id, owner_id, drop_world_pos)
	)


func _apply_bucket_impact(opener_peer_id: int, owner_id: int, drop_world_pos: Vector3) -> void:
	var pos_now: Vector3 = global_position if is_inside_tree() else position
	var closed_x: Vector3 = ((get_parent() as Node3D).global_basis * Basis(Vector3.UP, _closed_rotation)).x if get_parent() is Node3D else global_basis.x
	var check_pos: Vector3 = drop_world_pos if drop_world_pos != Vector3.INF else (_bucket_visual.global_position if (_bucket_visual != null and _bucket_visual.is_inside_tree()) else (pos_now + closed_x * 0.60))
	var scene: Node = get_tree().current_scene if (is_inside_tree() and get_tree() != null) else null
	var player: Node = scene.get_node_or_null("Players/" + str(opener_peer_id)) if scene != null else null
	if player == null and is_inside_tree() and get_tree() != null:
		for candidate in get_tree().get_nodes_in_group("spy_players"):
			if candidate.name.to_int() == opener_peer_id:
				player = candidate
				break
	var ko_hit: bool = false
	if player is Node3D:
		var opener_pos: Vector3 = (player as Node3D).global_position
		var flat_dist: float = Vector2(opener_pos.x - check_pos.x, opener_pos.z - check_pos.z).length()
		var hit_radius: float = GameConfig.bucket_hit_radius if GameConfig != null else 1.2
		if flat_dist <= hit_radius and player.has_method("apply_trap_ko"):
			ko_hit = true
			if is_inside_tree():
				if _is_peer_connected():
					_rpc_clear_bucket_drop_fx.rpc()
				else:
					_rpc_clear_bucket_drop_fx()
			if AudioBridge != null and GameConfig != null:
				var ko_rad: float = GameConfig.audio_radius_spring_trigger
				AudioBridge.request_world_cue("bucket_spill", Vector3(check_pos.x, 1.35, check_pos.z), ko_rad, owner_id)
			player.apply_trap_ko("BUCKET", owner_id)
	if not ko_hit and AudioBridge != null and GameConfig != null:
		var impact_delay: float = GameConfig.bucket_fall_impact_delay if GameConfig != null else 0.10
		var ground_wait: float = maxf(0.18 - impact_delay, 0.0)
		var ground_pos := Vector3(check_pos.x, 0.25, check_pos.z)
		if ground_wait <= 0.005 or not is_inside_tree() or Engine.is_editor_hint():
			AudioBridge.request_world_cue("bucket_spill", ground_pos, GameConfig.audio_radius_bucket_spill, owner_id)
		else:
			get_tree().create_timer(ground_wait).timeout.connect(func():
				if AudioBridge != null and GameConfig != null:
					AudioBridge.request_world_cue("bucket_spill", ground_pos, GameConfig.audio_radius_bucket_spill, owner_id)
			)


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
func _rpc_play_bucket_drop_fx(drop_world_pos: Vector3, side_sign: float) -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var fx_root := Node3D.new()
	fx_root.name = "BucketDropFX_%d" % get_instance_id()
	get_parent().add_child(fx_root)
	fx_root.global_position = Vector3(drop_world_pos.x, (get_parent() as Node3D).global_position.y if get_parent() is Node3D else 0.0, drop_world_pos.z)
	var start_y: float = maxf(drop_world_pos.y - fx_root.global_position.y, 0.5)
	var falling: Node3D = PICKUP_SCRIPT.build_item_visual("BUCKET")
	falling.name = "FallingBucket"
	falling.position = Vector3(0.0, start_y, 0.0)
	fx_root.add_child(falling)
	var tw := fx_root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(falling, "position:y", 0.14, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(falling, "rotation:x", PI * 0.85 * side_sign, 0.18)
	tw.chain().tween_callback(func():
		if not is_instance_valid(fx_root):
			return
		var splash := MeshInstance3D.new()
		splash.mesh = _get_splash_mesh()
		splash.material_override = _get_splash_mat()
		splash.position = Vector3(0.0, 0.02, 0.0)
		fx_root.add_child(splash)
		var hit_r: float = GameConfig.bucket_hit_radius if GameConfig != null else 1.2
		var stw := fx_root.create_tween()
		stw.tween_property(splash, "scale", Vector3(hit_r * 3.5, 1.0, hit_r * 3.5), 0.22).set_ease(Tween.EASE_OUT)
		stw.tween_property(splash, "scale", Vector3(0.01, 1.0, 0.01), 0.33).set_ease(Tween.EASE_IN)
		if is_instance_valid(falling):
			stw.parallel().tween_property(falling, "position:y", -0.20, 0.33)
		stw.tween_callback(fx_root.queue_free)
	)


@rpc("authority", "call_local", "reliable")
func _rpc_clear_bucket_drop_fx() -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var fx_root: Node = get_parent().get_node_or_null("BucketDropFX_%d" % get_instance_id())
	if fx_root != null and is_instance_valid(fx_root):
		var falling: Node = fx_root.get_node_or_null("FallingBucket")
		if falling != null and is_instance_valid(falling):
			falling.queue_free()


func _is_peer_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _request_state() -> void:
	server_get_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func server_get_state() -> void:
	if multiplayer.is_server():
		sync_state.rpc_id(multiplayer.get_remote_sender_id(), is_open, rotation.y, swing_duration)


func _find_verified_opener(is_sprint_bash: bool) -> Dictionary:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var scene: Node = get_tree().current_scene
	if scene == null:
		return {}
	var player: CharacterBody3D = scene.get_node_or_null("Players/" + str(sender)) as CharacterBody3D
	if player == null:
		return {}
	var view: Camera3D = player.get_node_or_null("Head/Camera3D") as Camera3D
	if view == null:
		return {}
	if not is_sprint_bash:
		var query := PhysicsRayQueryParameters3D.create(
			view.global_position, view.global_position - view.global_basis.z * 2.5, 3, [player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var hit_col: Object = hit["collider"]
		var is_bucket_hit: bool = hit_col is Node and (hit_col as Node).has_meta("bucket_door") and (hit_col as Node).get_meta("bucket_door") == self
		if not is_ancestor_of(hit_col) and not is_bucket_hit:
			return {}
	return {"player": player, "sender": sender}


func _compute_away_target_y(player: CharacterBody3D) -> float:
	# +X door leaf rotated by +90 deg (-open_angle) swings into -Z (away from +Z opener);
	# -90 deg (open_angle) swings into +Z (away from -Z opener).
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var closed_basis: Basis = (get_parent() as Node3D).global_basis * Basis(Vector3.UP, _closed_rotation) if get_parent() is Node3D else global_basis
	var z_dot: float = closed_basis.z.dot(to_player)
	var angle_deg: float = -open_angle if z_dot >= 0.0 else open_angle
	return _closed_rotation + deg_to_rad(angle_deg)


@rpc("any_peer", "call_remote", "reliable")
func server_step_push(delta: float, want_open: int = -1) -> void:
	if not multiplayer.is_server() or _busy:
		return
	if (want_open == 1 and is_open) or (want_open == 0 and not is_open):
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var player: CharacterBody3D = scene.get_node_or_null("Players/" + str(sender)) as CharacterBody3D
	if player == null or player.global_position.distance_to(global_position) > 3.5:
		return

	var slow_dur: float = GameConfig.door_slow_peek_swing_duration if GameConfig != null else 2.80
	var step: float = clampf(delta, 0.0, 0.15) / maxf(slow_dur, 0.5)
	if is_open:
		_open_fraction = clampf(_open_fraction - step, 0.0, 1.0)
		if _open_fraction <= 0.02:
			_open_fraction = 0.0
			is_open = false
			_step_start_y = _closed_rotation
	else:
		if _open_fraction <= 0.001:
			_push_target_y = _compute_away_target_y(player)
			var current_rel_rad: float = wrapf(rotation.y - _closed_rotation, -PI, PI)
			if absf(current_rel_rad) > 0.01:
				if ((_push_target_y - _closed_rotation) * current_rel_rad) > 0.0:
					_step_start_y = _closed_rotation
					_open_fraction = clampf(absf(current_rel_rad) / maxf(deg_to_rad(absf(open_angle)), 0.1), 0.0, 0.95)
				else:
					_step_start_y = rotation.y
					_open_fraction = 0.0
			else:
				_step_start_y = _closed_rotation
		_open_fraction = clampf(_open_fraction + step, 0.0, 1.0)
		if _open_fraction >= 0.98:
			_open_fraction = 1.0
			is_open = true
			_step_start_y = _closed_rotation

	var new_y: float = lerpf(_step_start_y if not is_open else _closed_rotation, _push_target_y, _open_fraction)
	if has_rigged_bucket:
		var opener_side: float = _compute_bucket_side_sign(sender)
		var ajar_rad: float = _get_bucket_ajar_rad()
		var same_delta_deg: float = GameConfig.door_bucket_same_side_release_delta_deg if GameConfig != null else 4.0
		var opp_release_deg: float = GameConfig.door_bucket_release_angle_deg if GameConfig != null else 28.0
		var should_drop: bool = (
			absf(new_y - (_closed_rotation + ajar_rad)) >= deg_to_rad(same_delta_deg)
			if (opener_side == bucket_side_sign)
			else absf(wrapf(new_y - _closed_rotation, -PI, PI)) >= deg_to_rad(opp_release_deg)
		)
		if should_drop:
			_trigger_rigged_bucket_drop(sender, 0.0)
	if multiplayer.has_multiplayer_peer():
		sync_step_angle.rpc(new_y, is_open, _open_fraction, _push_target_y)
	else:
		sync_step_angle(new_y, is_open, _open_fraction, _push_target_y)


@rpc("authority", "call_local", "unreliable_ordered")
func sync_step_angle(new_y: float, opened_state: bool, frac: float, push_target_y: float) -> void:
	if _swing != null and _swing.is_valid():
		_swing.kill()
	_busy = false
	is_open = opened_state
	_open_fraction = clampf(frac, 0.0, 1.0)
	_push_target_y = push_target_y
	rotation.y = new_y
	for body in find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 3


@rpc("any_peer", "call_remote", "reliable")
func server_interact(is_slow_peek: bool = false, is_sprint_bash: bool = false) -> void:
	if not multiplayer.is_server() or _busy:
		return
	var opener_info: Dictionary = _find_verified_opener(is_sprint_bash)
	if opener_info.is_empty():
		return
	var player: CharacterBody3D = opener_info["player"] as CharacterBody3D
	var sender: int = int(opener_info["sender"])

	var next_open: bool = not is_open
	if is_sprint_bash and is_open:
		return

	var dur: float = swing_duration
	var target_y: float = _closed_rotation
	if next_open:
		target_y = _push_target_y if _open_fraction > 0.05 else _compute_away_target_y(player)
		if is_sprint_bash:
			dur = GameConfig.door_sprint_bash_duration if GameConfig != null else 0.12
			if AudioBridge != null and GameConfig != null:
				AudioBridge.request_world_cue("door_bash", global_position, GameConfig.audio_radius_door_bash, sender)
		elif is_slow_peek:
			dur = GameConfig.door_slow_peek_swing_duration if GameConfig != null else 2.80
		else:
			dur = GameConfig.door_fast_open_duration if GameConfig != null else 0.25
			if AudioBridge != null and GameConfig != null:
				AudioBridge.request_world_cue("door_open", global_position, GameConfig.audio_radius_door_fast, sender)
		if has_rigged_bucket:
			_trigger_rigged_bucket_drop(sender, dur)
	else:
		dur = GameConfig.door_close_duration if GameConfig != null else 0.30
		if not is_slow_peek and AudioBridge != null and GameConfig != null:
			AudioBridge.request_world_cue("door_close", global_position, GameConfig.audio_radius_door_close, sender)

	if multiplayer.has_multiplayer_peer():
		sync_state.rpc(next_open, target_y, dur)
	else:
		sync_state(next_open, target_y, dur)


@rpc("authority", "call_local", "reliable")
func sync_state(opened: bool, target_y: float = 9999.0, dur: float = -1.0) -> void:
	is_open = opened
	_open_fraction = 1.0 if is_open else 0.0
	for body in find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 3
	if _swing != null and _swing.is_valid():
		_swing.kill()
	var final_y: float = target_y
	if final_y > 9000.0:
		final_y = _closed_rotation + (deg_to_rad(open_angle) if is_open else 0.0)
	if is_open:
		_push_target_y = final_y
	var final_dur: float = dur if dur > 0.0 else swing_duration
	var total_span: float = maxf(deg_to_rad(absf(open_angle)), 0.1)
	var scaled_dur: float = final_dur * clampf(absf(final_y - rotation.y) / total_span, 0.12, 1.0)
	if scaled_dur <= 0.01 or is_equal_approx(rotation.y, final_y):
		rotation.y = final_y
		_busy = false
		return
	_busy = true
	_swing = create_tween()
	_swing.tween_property(self, "rotation:y", final_y, scaled_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swing.finished.connect(func() -> void: _busy = false)
