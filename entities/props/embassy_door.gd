@tool
class_name EmbassyDoor
extends Node3D

## Unified Bidirectional Embassy Door (Doc 3 §2).
## Swings 90° away from whichever side the opener approaches from (Dot Product Rule).
## Supports Tap E (Fast Open), Hold E (Silent Slow Peek), Sprint Auto-Bash, and Water Bucket rigging.

@export var door_id: String = "EmbassyDoor"
@export var open_angle_deg: float = 90.0

var is_open: bool = false
var current_target_angle_rad: float = 0.0
var has_rigged_bucket: bool = false
var bucket_owner_peer_id: int = 0

var _hinge_pivot: Node3D = null
var _door_body: StaticBody3D = null
var _bucket_visual: MeshInstance3D = null
var _swing_tween: Tween = null


func _ready() -> void:
	_ensure_nodes()
	_apply_closed_visuals()


func _ensure_nodes() -> void:
	_hinge_pivot = get_node_or_null("HingePivot") as Node3D
	if _hinge_pivot == null:
		_hinge_pivot = Node3D.new()
		_hinge_pivot.name = "HingePivot"
		_hinge_pivot.position = Vector3(-0.65, 0.0, 0.0)
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
		box.size = Vector3(1.3, 2.15, 0.1)
		col.shape = box
		col.position = Vector3(0.65, 1.075, 0.0)
		_door_body.add_child(col)

		var leaf_mesh := MeshInstance3D.new()
		leaf_mesh.name = "LeafMesh"
		var b_mesh := BoxMesh.new()
		b_mesh.size = Vector3(1.3, 2.15, 0.1)
		leaf_mesh.mesh = b_mesh
		leaf_mesh.position = Vector3(0.65, 1.075, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.38, 0.24)
		leaf_mesh.material_override = mat
		_door_body.add_child(leaf_mesh)
	else:
		_door_body.collision_layer = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3

	_bucket_visual = _hinge_pivot.get_node_or_null("BucketMount") as MeshInstance3D


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
		return "[E] Close Door"
	return "[Tap E] Fast Open  |  [Hold E] Silent Peek"


func get_hold_interaction_duration() -> float:
	return GameConfig.door_slow_peek_hold_time if GameConfig != null else 0.60


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


func rig_water_bucket(owner_peer_id: int) -> bool:
	if is_open or has_rigged_bucket:
		return false
	has_rigged_bucket = true
	bucket_owner_peer_id = owner_peer_id
	_apply_closed_visuals()
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("trap_arm", _safe_global_pos() + Vector3(0.0, 2.0, 0.0), GameConfig.audio_radius_trap_setup, owner_peer_id)
	return true


func steal_water_bucket(thief_peer_id: int) -> bool:
	if not has_rigged_bucket:
		return false
	var player: Node = _find_player_node(thief_peer_id)
	if player != null and player.has_method("server_pickup_world_item"):
		if not player.server_pickup_world_item("BUCKET", [], _safe_global_pos()):
			return false
	has_rigged_bucket = false
	bucket_owner_peer_id = 0
	_apply_closed_visuals()
	return true


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
		current_target_angle_rad = 0.0
		duration = GameConfig.door_close_duration if GameConfig != null else 0.30
		if mode == "FAST_TOGGLE" and AudioBridge != null and GameConfig != null:
			AudioBridge.request_world_cue("door_close", pos_now, GameConfig.audio_radius_door_close, peer_id)
	else:
		is_open = true
		current_target_angle_rad = compute_away_angle_rad(opener_pos)
		match mode:
			"SPRINT_BASH":
				duration = GameConfig.door_sprint_bash_duration if GameConfig != null else 0.12
				if AudioBridge != null and GameConfig != null:
					AudioBridge.request_world_cue("door_bash", pos_now, GameConfig.audio_radius_door_bash, peer_id)
			"SLOW_PEEK":
				duration = GameConfig.door_slow_peek_swing_duration if GameConfig != null else 0.60
			_:
				duration = GameConfig.door_fast_open_duration if GameConfig != null else 0.25
				if AudioBridge != null and GameConfig != null:
					AudioBridge.request_world_cue("door_open", pos_now, GameConfig.audio_radius_door_fast, peer_id)

		if has_rigged_bucket:
			_trigger_rigged_bucket_on_open(peer_id, opener_pos, duration)

	if _is_peer_connected():
		_rpc_sync_door.rpc(is_open, current_target_angle_rad, duration, has_rigged_bucket)
	else:
		_rpc_sync_door(is_open, current_target_angle_rad, duration, has_rigged_bucket)


func _trigger_rigged_bucket_on_open(opener_peer_id: int, opener_pos: Vector3, swing_duration: float) -> void:
	var release_deg: float = GameConfig.door_bucket_release_angle_deg if GameConfig != null else 25.0
	var open_deg: float = maxf(open_angle_deg, 1.0)
	var delay: float = swing_duration * clampf(release_deg / open_deg, 0.05, 0.9)
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
	var pos_now: Vector3 = _safe_global_pos()
	var flat_dist: float = Vector2(opener_pos.x - pos_now.x, opener_pos.z - pos_now.z).length()
	var hit_radius: float = GameConfig.bucket_hit_radius if GameConfig != null else 1.2
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("bucket_spill", pos_now, GameConfig.audio_radius_bucket_spill, owner_id)
	if flat_dist <= hit_radius:
		var player: Node = _find_player_node(opener_peer_id)
		if player != null and player.has_method("apply_trap_ko"):
			player.apply_trap_ko("BUCKET", owner_id)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_door(opened: bool, target_angle_rad: float, duration: float, bucket_rigged: bool) -> void:
	_ensure_nodes()
	is_open = opened
	current_target_angle_rad = target_angle_rad
	has_rigged_bucket = bucket_rigged
	if _bucket_visual != null:
		_bucket_visual.visible = has_rigged_bucket

	var final_rad: float = target_angle_rad
	if not is_open and has_rigged_bucket:
		var ajar_deg: float = GameConfig.door_bucket_ajar_angle_deg if GameConfig != null else 5.0
		final_rad = deg_to_rad(ajar_deg)

	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()

	if is_inside_tree() and duration > 0.0:
		_swing_tween = create_tween()
		_swing_tween.tween_property(_hinge_pivot, "rotation:y", final_rad, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_hinge_pivot.rotation.y = final_rad


func _apply_closed_visuals() -> void:
	if _hinge_pivot == null:
		return
	if _bucket_visual != null:
		_bucket_visual.visible = has_rigged_bucket
	if not is_open:
		var ajar_deg: float = GameConfig.door_bucket_ajar_angle_deg if GameConfig != null else 5.0
		_hinge_pivot.rotation.y = deg_to_rad(ajar_deg) if has_rigged_bucket else 0.0


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
	return null


func _is_peer_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
