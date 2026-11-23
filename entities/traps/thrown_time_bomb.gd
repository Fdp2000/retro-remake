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

const BOMB_RADIUS: float = 0.16
const BOMB_SPHERE_CENTER_OFFSET_Y: float = -0.051
const ROLL_FRICTION: float = 3.2
const ROLL_STOP_SPEED: float = 0.12
const FLOOR_BOUNCE_MIN_VY: float = 2.6

var velocity: Vector3 = Vector3.ZERO
var elapsed: float = 0.0
var _landed: bool = false
var _rolling: bool = false
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
		var visual: Node3D = PICKUP_SCRIPT.build_item_visual("LIVE_BOMB")
		visual.name = "BombVisual"
		add_child(visual)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _detonated:
		return

	fuse_remaining -= delta
	elapsed += delta

	if not _landed:
		if _rolling:
			_step_rolling_motion(delta)
		else:
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
			var next_pos: Vector3 = hit_pos + hit_normal * BOMB_RADIUS
			_set_safe_global_pos(next_pos)
			if hit_normal.y > 0.55:
				if absf(velocity.y) > FLOOR_BOUNCE_MIN_VY:
					velocity = velocity.bounce(hit_normal)
					velocity.x *= 0.72
					velocity.z *= 0.72
					velocity.y *= 0.30
				else:
					_rolling = true
					velocity.y = 0.0
			else:
				velocity = velocity.bounce(hit_normal) * 0.45
			return

	_set_safe_global_pos(cur_pos + motion)
	_rotate_visual_for_velocity(velocity, delta, 0.35)


func _step_rolling_motion(delta: float) -> void:
	var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
	horiz_vel = horiz_vel.move_toward(Vector3.ZERO, ROLL_FRICTION * delta)
	var speed: float = horiz_vel.length()
	if speed < ROLL_STOP_SPEED:
		_rolling = false
		_landed = true
		velocity = Vector3.ZERO
		if _is_peer_connected() and multiplayer.is_server():
			_rpc_sync_settled_pos.rpc(_safe_global_pos())
		return

	velocity = horiz_vel
	var cur_pos: Vector3 = _safe_global_pos()
	var motion: Vector3 = horiz_vel * delta
	var next_pos: Vector3 = cur_pos + motion

	if is_inside_tree() and get_world_3d() != null and get_world_3d().direct_space_state != null:
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var env_mask: int = GameConfig.LAYER_ENVIRONMENT if GameConfig != null else 1
		var wall_dir: Vector3 = horiz_vel / speed
		var wall_query := PhysicsRayQueryParameters3D.create(cur_pos, cur_pos + motion + wall_dir * BOMB_RADIUS, env_mask, [get_rid()])
		var wall_hit: Dictionary = space.intersect_ray(wall_query)
		if not wall_hit.is_empty():
			var w_normal: Vector3 = (wall_hit["normal"] as Vector3).normalized()
			if w_normal.y <= 0.55:
				var flat_n := Vector3(w_normal.x, 0.0, w_normal.z).normalized()
				if flat_n.length_squared() > 0.001:
					velocity = horiz_vel.bounce(flat_n) * 0.55
				next_pos = (wall_hit["position"] as Vector3) + w_normal * BOMB_RADIUS
				next_pos.y = cur_pos.y

		var floor_query := PhysicsRayQueryParameters3D.create(next_pos + Vector3(0.0, 0.25, 0.0), next_pos + Vector3(0.0, -0.45, 0.0), env_mask, [get_rid()])
		var floor_hit: Dictionary = space.intersect_ray(floor_query)
		if not floor_hit.is_empty() and (floor_hit["normal"] as Vector3).normalized().y > 0.55:
			next_pos.y = (floor_hit["position"] as Vector3).y + BOMB_RADIUS
		else:
			_rolling = false

	_set_safe_global_pos(next_pos)
	_rotate_visual_for_velocity(velocity, delta, 1.0)


func _rotate_visual_for_velocity(vel: Vector3, delta: float, spin_scale: float) -> void:
	var b_vis: Node3D = get_node_or_null("BombVisual") as Node3D
	if b_vis == null:
		return
	var horiz := Vector3(vel.x, 0.0, vel.z)
	var h_len: float = horiz.length()
	if h_len <= 0.001:
		return
	var roll_axis: Vector3 = Vector3.UP.cross(horiz / h_len)
	if roll_axis.length_squared() <= 0.0001:
		return
	var angle: float = (h_len * delta / BOMB_RADIUS) * spin_scale
	var pivot := Vector3(0.0, BOMB_SPHERE_CENTER_OFFSET_Y, 0.0)
	var old_world_pivot: Vector3 = b_vis.basis * pivot
	b_vis.rotate(roll_axis.normalized(), angle)
	b_vis.position += old_world_pivot - (b_vis.basis * pivot)


func _set_safe_global_pos(pos: Vector3) -> void:
	if is_inside_tree():
		global_position = pos
	else:
		position = pos


@rpc("authority", "call_local", "reliable")
func _rpc_sync_settled_pos(settled_pos: Vector3) -> void:
	_rolling = false
	_landed = true
	velocity = Vector3.ZERO
	_set_safe_global_pos(settled_pos)


func check_midair_catch_candidate() -> Node:
	if not is_inside_tree() or get_tree() == null or _landed or _rolling or _detonated:
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
					var p3d: Node3D = p as Node3D
					var away_horiz: Vector3 = p3d.global_position - blast_pos
					away_horiz.y = 0.0
					if away_horiz.length_squared() < 0.02:
						away_horiz = p3d.global_transform.basis.z
						away_horiz.y = 0.0
					if away_horiz.length_squared() < 0.0001:
						away_horiz = Vector3(0.0, 0.0, 1.0)
					away_horiz = away_horiz.normalized()
					var blast_kick: Vector3 = away_horiz * 12.0 + Vector3(0.0, 4.5, 0.0)
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
