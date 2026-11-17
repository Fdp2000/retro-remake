extends MeshInstance3D

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")

@export var open_angle: float = -90.0
@export var swing_duration: float = 0.3

var is_open: bool = false
var has_rigged_bucket: bool = false
var bucket_owner_peer_id: int = 0
var _closed_rotation: float = 0.0
var _open_fraction: float = 0.0
var _push_target_y: float = 0.0
var _swing: Tween
var _busy: bool = false
var _bucket_visual: MeshInstance3D = null

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


func _ensure_bucket_visual() -> void:
	if _bucket_visual == null:
		_bucket_visual = get_node_or_null("BucketMount") as MeshInstance3D
	if _bucket_visual == null:
		_bucket_visual = PICKUP_SCRIPT.build_item_mesh("BUCKET")
		_bucket_visual.name = "BucketMount"
		_bucket_visual.position = Vector3(0.60, 1.15, 0.03)
		_bucket_visual.visible = has_rigged_bucket
		add_child(_bucket_visual)

func get_interaction_prompt() -> String:
	if is_open:
		return "[Tap E] Close  |  [Hold E] Pull Shut"
	if has_rigged_bucket:
		return "[Tap E] Open  |  [Hold E] Peek  |  [Look Up + E] Steal Bucket"
	return "[Tap E] Fast Open  |  [Hold E] Slowly Push Open"


func get_hold_interaction_duration() -> float:
	return GameConfig.door_slow_peek_hold_time if GameConfig != null else 2.80


func request_step_push(_peer_id: int, delta: float) -> void:
	if multiplayer.is_server():
		server_step_push(delta)
	else:
		server_step_push.rpc_id(1, delta)


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


func rig_water_bucket(owner_peer_id: int) -> bool:
	_ensure_bucket_visual()
	if is_open or has_rigged_bucket:
		return false
	has_rigged_bucket = true
	bucket_owner_peer_id = owner_peer_id
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("trap_arm", global_position + Vector3(0.0, 2.0, 0.0), GameConfig.audio_radius_trap_setup, owner_peer_id)
	if _is_peer_connected():
		_rpc_sync_bucket_state.rpc(true)
	else:
		_rpc_sync_bucket_state(true)
	return true


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
		_rpc_sync_bucket_state.rpc(false)
	else:
		_rpc_sync_bucket_state(false)
	return true


@rpc("authority", "call_local", "reliable")
func _rpc_sync_bucket_state(rigged: bool) -> void:
	_ensure_bucket_visual()
	has_rigged_bucket = rigged
	if _bucket_visual != null:
		_bucket_visual.visible = has_rigged_bucket
	if not is_open:
		var ajar_deg: float = GameConfig.door_bucket_ajar_angle_deg if GameConfig != null else 5.0
		rotation.y = (_closed_rotation + deg_to_rad(ajar_deg)) if has_rigged_bucket else _closed_rotation


func _trigger_rigged_bucket_drop(opener_peer_id: int, swing_dur: float) -> void:
	var owner_id: int = bucket_owner_peer_id
	has_rigged_bucket = false
	bucket_owner_peer_id = 0
	if _is_peer_connected():
		_rpc_sync_bucket_state.rpc(false)
	else:
		_rpc_sync_bucket_state(false)
	var release_deg: float = GameConfig.door_bucket_release_angle_deg if GameConfig != null else 25.0
	var open_deg: float = maxf(absf(open_angle), 1.0)
	var delay: float = clampf(swing_dur * (release_deg / open_deg), 0.0, 1.5)
	if not is_inside_tree() or delay <= 0.01:
		_resolve_bucket_drop(opener_peer_id, owner_id)
		return
	get_tree().create_timer(delay).timeout.connect(func():
		_resolve_bucket_drop(opener_peer_id, owner_id)
	)


func _resolve_bucket_drop(opener_peer_id: int, owner_id: int) -> void:
	var pos_now: Vector3 = global_position if is_inside_tree() else position
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("bucket_spill", pos_now, GameConfig.audio_radius_bucket_spill, owner_id)
	var scene: Node = get_tree().current_scene if (is_inside_tree() and get_tree() != null) else null
	var player: Node = scene.get_node_or_null("Players/" + str(opener_peer_id)) if scene != null else null
	if player == null and is_inside_tree() and get_tree() != null:
		for candidate in get_tree().get_nodes_in_group("spy_players"):
			if candidate.name.to_int() == opener_peer_id:
				player = candidate
				break
	if player is Node3D:
		var opener_pos: Vector3 = (player as Node3D).global_position
		var door_center: Vector3 = pos_now + global_basis.x * 0.60
		var flat_dist: float = Vector2(opener_pos.x - door_center.x, opener_pos.z - door_center.z).length()
		var hit_radius: float = GameConfig.bucket_hit_radius if GameConfig != null else 1.2
		if flat_dist <= hit_radius and player.has_method("apply_trap_ko"):
			player.apply_trap_ko("BUCKET", owner_id)


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
		if hit.is_empty() or not is_ancestor_of(hit["collider"]):
			return {}
	return {"player": player, "sender": sender}


func _compute_away_target_y(player: CharacterBody3D) -> float:
	# +X door leaf rotated by +90 deg (-open_angle) swings into -Z (away from +Z opener);
	# -90 deg (open_angle) swings into +Z (away from -Z opener).
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var z_dot: float = global_basis.z.dot(to_player)
	var angle_deg: float = -open_angle if z_dot >= 0.0 else open_angle
	return _closed_rotation + deg_to_rad(angle_deg)


@rpc("any_peer", "call_remote", "reliable")
func server_step_push(delta: float) -> void:
	if not multiplayer.is_server() or _busy:
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
	else:
		if _open_fraction <= 0.02:
			_push_target_y = _compute_away_target_y(player)
		_open_fraction = clampf(_open_fraction + step, 0.0, 1.0)
		if _open_fraction >= 0.98:
			_open_fraction = 1.0
			is_open = true

	var new_y: float = lerpf(_closed_rotation, _push_target_y, _open_fraction)
	if has_rigged_bucket:
		var release_deg: float = GameConfig.door_bucket_release_angle_deg if GameConfig != null else 25.0
		if _open_fraction * absf(open_angle) >= release_deg:
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
