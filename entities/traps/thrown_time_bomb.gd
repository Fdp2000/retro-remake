@tool
class_name ThrownTimeBomb
extends StaticBody3D

## Ballistic Hot-Potato Lit Time Bomb (Doc 4 §3.4).
## Hurls across rooms (~9.0m), triggers direct mid-air catch into rival active hand,
## supports floor Tap-E re-grab, and detonates a 5.0m wall/closed-door-occluded KO blast.

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")

@export var owner_peer_id: int = 0
@export var thrower_peer_id: int = 0
@export var fuse_remaining: float = 3.0

var velocity: Vector3 = Vector3.ZERO
var elapsed: float = 0.0
var _landed: bool = false
var _detonated: bool = false
var _gravity: float = 9.8


func _ready() -> void:
	set_multiplayer_authority(1)
	collision_layer = GameConfig.LAYER_INTERACTABLE if GameConfig != null else 2
	collision_mask = 0
	_ensure_nodes()


func _ensure_nodes() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var sph := SphereShape3D.new()
		sph.radius = 0.20
		col.shape = sph
		add_child(col)

	if get_node_or_null("BombVisual") == null:
		var mi := PICKUP_SCRIPT.build_item_mesh("LIVE_BOMB")
		mi.name = "BombVisual"
		add_child(mi)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _detonated:
		return

	fuse_remaining -= delta
	elapsed += delta

	if not _landed:
		velocity.y -= _gravity * delta
		if not _is_peer_connected() or multiplayer.is_server():
			var catcher: Node = check_midair_catch_candidate()
			if catcher != null:
				catch_by_spy(catcher)
				return
		_step_ballistic_motion(delta)

	if fuse_remaining <= 0.0:
		if not _is_peer_connected() or multiplayer.is_server():
			detonate()


func _step_ballistic_motion(delta: float) -> void:
	var motion: Vector3 = velocity * delta
	if motion.length_squared() <= 0.000001:
		return
	var cur_pos: Vector3 = _safe_global_pos()
	if is_inside_tree() and get_world_3d() != null and get_world_3d().direct_space_state != null:
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
		var query := PhysicsRayQueryParameters3D.create(cur_pos, cur_pos + motion, env_mask, [get_rid()])
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			var hit_pos: Vector3 = hit["position"]
			var hit_normal: Vector3 = (hit["normal"] as Vector3).normalized()
			var next_pos: Vector3 = hit_pos + hit_normal * 0.16
			if is_inside_tree():
				global_position = next_pos
			else:
				position = next_pos
			if hit_normal.y > 0.55 or velocity.length() < 1.5:
				_landed = true
				velocity = Vector3.ZERO
			else:
				velocity = velocity.bounce(hit_normal) * 0.45
			return

	if is_inside_tree():
		global_position = cur_pos + motion
	else:
		position = cur_pos + motion


func check_midair_catch_candidate() -> Node:
	if not is_inside_tree() or get_tree() == null or _landed or _detonated:
		return null
	var ignore_dur: float = GameConfig.time_bomb_self_catch_ignore_time if GameConfig != null else 0.25
	var cur_pos: Vector3 = _safe_global_pos()
	var ko_val: int = GameConfig.Stance.KO if GameConfig != null else 4

	for spy in get_tree().get_nodes_in_group("spy_players"):
		if not (spy is Node3D):
			continue
		if elapsed < ignore_dur and spy.name.to_int() == thrower_peer_id:
			continue
		if int(spy.get("stance_state")) == ko_val:
			continue
		var spy_torso: Vector3 = (spy as Node3D).global_position + Vector3(0.0, 0.95, 0.0)
		if spy_torso.distance_to(cur_pos) <= 0.75:
			return spy
	return null


func catch_by_spy(spy: Node) -> bool:
	if _detonated or spy == null:
		return false
	_detonated = true
	if spy.has_method("catch_live_bomb"):
		spy.catch_live_bomb(maxf(fuse_remaining, 0.15), owner_peer_id)
	_consume_bomb()
	return true


func detonate() -> void:
	if _detonated:
		return
	_detonated = true
	fuse_remaining = 0.0
	var pos_now: Vector3 = _safe_global_pos()
	detonate_blast_at(get_tree() if is_inside_tree() else null, get_world_3d() if is_inside_tree() else null, pos_now, owner_peer_id, get_rid() if is_inside_tree() else RID())
	_consume_bomb()


static func detonate_blast_at(tree: SceneTree, world_3d: World3D, blast_pos: Vector3, bomb_owner_id: int, exclude_rid: RID = RID()) -> void:
	if AudioBridge != null and GameConfig != null:
		AudioBridge.request_world_cue("bomb_explode", blast_pos, GameConfig.audio_radius_bomb_explosion, bomb_owner_id)

	if tree == null:
		return
	var blast_radius: float = GameConfig.time_bomb_blast_radius if GameConfig != null else 5.0
	for p in tree.get_nodes_in_group("spy_players"):
		if p is Node3D and (p as Node3D).global_position.distance_to(blast_pos) <= blast_radius:
			if not _is_point_blast_occluded(world_3d, blast_pos, (p as Node3D).global_position, exclude_rid):
				if p.has_method("apply_trap_ko"):
					var away_dir: Vector3 = ((p as Node3D).global_position + Vector3(0.0, 0.9, 0.0) - blast_pos).normalized()
					var blast_kick: Vector3 = away_dir * 16.5 + Vector3(0.0, 7.5, 0.0)
					p.apply_trap_ko("BOMB", bomb_owner_id, blast_kick)


static func _is_point_blast_occluded(world_3d: World3D, blast_pos: Vector3, target_pos: Vector3, exclude_rid: RID = RID()) -> bool:
	if world_3d == null or world_3d.direct_space_state == null:
		return false
	var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
	var exclude: Array[RID] = []
	if exclude_rid.is_valid():
		exclude.append(exclude_rid)
	var query := PhysicsRayQueryParameters3D.create(
		blast_pos + Vector3(0.0, 0.35, 0.0),
		target_pos + Vector3(0.0, 0.85, 0.0),
		env_mask,
		exclude
	)
	var hit: Dictionary = world_3d.direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _is_blast_occluded(target_pos: Vector3) -> bool:
	return _is_point_blast_occluded(get_world_3d() if is_inside_tree() else null, _safe_global_pos(), target_pos, get_rid() if is_inside_tree() else RID())


func get_interaction_prompt() -> String:
	return "[E] Grab Lit Time Bomb (%.1fs)!" % maxf(fuse_remaining, 0.0)


func request_interaction(caller_peer_id: int) -> void:
	if _detonated:
		return
	if _is_peer_connected():
		_server_grab_bomb.rpc_id(1, caller_peer_id)
	else:
		_execute_grab_bomb(caller_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _server_grab_bomb(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != caller_peer_id:
		caller_peer_id = sender
	_execute_grab_bomb(caller_peer_id)


func _execute_grab_bomb(caller_peer_id: int) -> void:
	if _detonated:
		return
	var spy: Node = _find_player_node(caller_peer_id)
	if spy != null:
		catch_by_spy(spy)


func _find_player_node(peer_id: int) -> Node:
	if not is_inside_tree() or get_tree() == null:
		return null
	var scene: Node = get_tree().current_scene
	if scene != null:
		var p: Node = scene.get_node_or_null("Players/" + str(peer_id))
		if p != null:
			return p
	for candidate in get_tree().get_nodes_in_group("spy_players"):
		if candidate.name == str(peer_id):
			return candidate
	return null


func _consume_bomb() -> void:
	if _is_peer_connected():
		_rpc_consume.rpc()
	elif is_inside_tree():
		queue_free()


@rpc("authority", "call_local", "reliable")
func _rpc_consume() -> void:
	_detonated = true
	if is_inside_tree():
		queue_free()


func _safe_global_pos() -> Vector3:
	return global_position if is_inside_tree() else position


func _is_peer_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
