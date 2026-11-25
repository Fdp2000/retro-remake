@tool
class_name TripwireTrap
extends StaticBody3D

## Floor & Doorway Tripwire Trap (Doc 4 §3.2).
## Triggers 15s KO on walking/sprinting spies (owner-triggerable).
## Can be jumped over (Space), crouched under (Ctrl), or disarmed/stolen (Hold E).

@export var owner_peer_id: int = 0
@export var span_width: float = 1.10
@export var start_point: Vector3 = Vector3.ZERO
@export var end_point: Vector3 = Vector3.ZERO
@export var use_endpoints: bool = false
@export var trigger_count: int = 0

const MAX_TRIGGERS: int = 3

const TRIPWIRE_PREFAB: PackedScene = preload("res://Assets/Prefab_Traps/tripwire.tscn")
const PEG_MODEL_HEIGHT: float = 0.1504
const PEG_RING_CENTER_RATIO: float = 0.1118 / PEG_MODEL_HEIGHT
const PEG_RING_SIDE_RADIUS_UNSCALED: float = 0.0235
const PEG_RING_TUBE_RADIUS_UNSCALED: float = 0.0056
const PEG_XZ_SCALE: float = 2.2
const PEG_SIDE_TIE_SIGN: float = 1.0

var wire_height: float = 0.35
var _triggered_or_consumed: bool = false
var _trigger_area: Area3D = null


func _ready() -> void:
	set_multiplayer_authority(1)
	collision_layer = GameConfig.LAYER_INTERACTABLE if GameConfig != null else 2
	collision_mask = 0
	wire_height = GameConfig.tripwire_height if GameConfig != null else 0.35
	if use_endpoints:
		_apply_endpoint_transform()
	_ensure_nodes()


func configure_endpoints(p1: Vector3, p2: Vector3) -> void:
	start_point = p1
	end_point = p2
	use_endpoints = true
	span_width = maxf(p1.distance_to(p2), 0.05)
	wire_height = GameConfig.tripwire_height if GameConfig != null else 0.35
	if is_node_ready():
		_apply_endpoint_transform()
		_rebuild_geometry()


func _apply_endpoint_transform() -> void:
	var delta: Vector3 = end_point - start_point
	var horiz := Vector3(delta.x, 0.0, delta.z)
	var horiz_len: float = horiz.length()
	var mid: Vector3 = (start_point + end_point) * 0.5
	if is_inside_tree():
		global_position = mid
	else:
		position = mid
	if horiz_len > 0.0001:
		rotation.y = atan2(-horiz.z, horiz.x)


func _compute_span_metrics() -> Dictionary:
	var full_span: float = maxf(span_width, 0.05)
	var horiz_len: float = full_span
	var dy: float = 0.0
	var local_p1 := Vector3(-full_span * 0.5, 0.0, 0.0)
	var local_p2 := Vector3(full_span * 0.5, 0.0, 0.0)

	if use_endpoints:
		var delta: Vector3 = end_point - start_point
		var horiz := Vector3(delta.x, 0.0, delta.z)
		horiz_len = horiz.length()
		dy = delta.y
		full_span = maxf(delta.length(), 0.05)
		var mid: Vector3 = (start_point + end_point) * 0.5
		local_p1 = Vector3(-horiz_len * 0.5, start_point.y - mid.y, 0.0)
		local_p2 = Vector3(horiz_len * 0.5, end_point.y - mid.y, 0.0)

	var tilt: float = atan2(dy, maxf(horiz_len, 0.0001)) if use_endpoints else 0.0
	return {
		"full_span": full_span,
		"local_p1": local_p1,
		"local_p2": local_p2,
		"tilt": tilt
	}


func _ensure_nodes() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		add_child(col)

	if get_node_or_null("Visuals") == null:
		var vis := Node3D.new()
		vis.name = "Visuals"
		add_child(vis)

	_trigger_area = get_node_or_null("TriggerArea") as Area3D
	if _trigger_area == null:
		_trigger_area = Area3D.new()
		_trigger_area.name = "TriggerArea"
		_trigger_area.collision_layer = GameConfig.LAYER_TRIGGERS if GameConfig != null else 16
		_trigger_area.collision_mask = GameConfig.LAYER_PLAYER if GameConfig != null else 4
		var trig_col := CollisionShape3D.new()
		trig_col.name = "TriggerShape"
		_trigger_area.add_child(trig_col)
		add_child(_trigger_area)

	_rebuild_geometry()


func _rebuild_geometry() -> void:
	var metrics: Dictionary = _compute_span_metrics()
	var full_span: float = float(metrics["full_span"])
	var local_p1: Vector3 = metrics["local_p1"] as Vector3
	var local_p2: Vector3 = metrics["local_p2"] as Vector3
	var tilt: float = float(metrics["tilt"])

	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		var box := BoxShape3D.new()
		box.size = Vector3(full_span + 0.16, 0.45, 0.24)
		col.shape = box
		col.position = Vector3(0.0, 0.22, 0.0)
		col.rotation = Vector3(0.0, 0.0, tilt)

	var vis: Node3D = get_node_or_null("Visuals") as Node3D
	if vis != null:
		for child in vis.get_children():
			vis.remove_child(child)
			child.queue_free()

		var peg_h: float = wire_height + 0.05
		var peg_scale := Vector3(PEG_XZ_SCALE, peg_h / PEG_MODEL_HEIGHT, PEG_XZ_SCALE)
		var ring_center_y: float = peg_h * PEG_RING_CENTER_RATIO
		var ring_side_offset_z: float = PEG_RING_SIDE_RADIUS_UNSCALED * PEG_XZ_SCALE * PEG_SIDE_TIE_SIGN
		var ring_tube_r: float = PEG_RING_TUBE_RADIUS_UNSCALED * PEG_XZ_SCALE

		for i in range(2):
			var peg: Node3D = TRIPWIRE_PREFAB.instantiate() as Node3D
			peg.name = "Peg_%d" % i
			var base_pt: Vector3 = local_p1 if i == 0 else local_p2
			peg.position = base_pt
			peg.scale = peg_scale
			peg.rotation.y = PI * 0.5
			vis.add_child(peg)

		var wire_mat := StandardMaterial3D.new()
		wire_mat.albedo_color = Color(0.95, 0.32, 0.12)
		wire_mat.emission_enabled = true
		wire_mat.emission = Color(0.85, 0.25, 0.10)
		wire_mat.emission_energy_multiplier = 0.45

		var p1_tie: Vector3 = local_p1 + Vector3(0.0, ring_center_y, ring_side_offset_z)
		var p2_tie: Vector3 = local_p2 + Vector3(0.0, ring_center_y, ring_side_offset_z)
		var span_vec: Vector3 = p2_tie - p1_tie
		var span_len: float = maxf(span_vec.length(), 0.01)

		var wire_mi := MeshInstance3D.new()
		wire_mi.name = "WireMesh"
		var wire_cyl := CylinderMesh.new()
		wire_cyl.top_radius = 0.008
		wire_cyl.bottom_radius = 0.008
		wire_cyl.height = span_len
		wire_mi.mesh = wire_cyl
		wire_mi.rotation = Vector3(0.0, 0.0, -PI * 0.5 + tilt)
		wire_mi.position = Vector3(0.0, ring_center_y, ring_side_offset_z)
		wire_mi.material_override = wire_mat
		vis.add_child(wire_mi)

		var knot_mesh := TorusMesh.new()
		knot_mesh.inner_radius = maxf(ring_tube_r - 0.001, 0.003)
		knot_mesh.outer_radius = knot_mesh.inner_radius + 0.014
		knot_mesh.rings = 16
		knot_mesh.ring_segments = 12

		for i in range(2):
			var base_tie: Vector3 = p1_tie if i == 0 else p2_tie
			var knot_mi := MeshInstance3D.new()
			knot_mi.name = "WireTie_%d" % i
			knot_mi.mesh = knot_mesh
			knot_mi.position = base_tie
			knot_mi.rotation = Vector3(0.0, 0.0, 0.0)
			knot_mi.material_override = wire_mat
			vis.add_child(knot_mi)

	var area: Area3D = _trigger_area if _trigger_area != null else get_node_or_null("TriggerArea") as Area3D
	if area != null:
		var trig_col: CollisionShape3D = null
		for child in area.get_children():
			if child is CollisionShape3D:
				trig_col = child as CollisionShape3D
				break
		if trig_col != null:
			var trig_box := BoxShape3D.new()
			trig_box.size = Vector3(full_span, 0.22, 0.14)
			trig_col.shape = trig_box
			trig_col.position = Vector3(0.0, wire_height, 0.0)
			trig_col.rotation = Vector3(0.0, 0.0, tilt)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _triggered_or_consumed or _trigger_area == null:
		return
	if _is_peer_connected() and not multiplayer.is_server():
		return

	for body in _trigger_area.get_overlapping_bodies():
		if try_trip_spy(body):
			break


func try_trip_spy(body: Node) -> bool:
	if _triggered_or_consumed or body == null or not body.is_in_group("spy_players"):
		return false
	if not (body is Node3D):
		return false
	var stance: int = int(body.get("stance_state"))
	var crouch_val: int = GameConfig.Stance.CROUCH if GameConfig != null else 2
	var ko_val: int = GameConfig.Stance.KO if GameConfig != null else 4
	if stance == crouch_val or stance == ko_val:
		return false
	if float(body.get("wakeup_immunity_remaining")) > 0.0:
		return false

	# Jumping over the 0.35m wire raises feet cleanly above trigger band
	var base_y: float = global_position.y if is_inside_tree() else position.y
	var spy_pos: Vector3 = (body as Node3D).global_position if (body as Node3D).is_inside_tree() else (body as Node3D).position
	if use_endpoints:
		var seg_xz := Vector2(end_point.x - start_point.x, end_point.z - start_point.z)
		var len_sq: float = seg_xz.length_squared()
		var t: float = 0.5
		if len_sq > 0.0001:
			var rel_xz := Vector2(spy_pos.x - start_point.x, spy_pos.z - start_point.z)
			t = clampf(rel_xz.dot(seg_xz) / len_sq, 0.0, 1.0)
		base_y = lerpf(start_point.y, end_point.y, t)
	if spy_pos.y >= base_y + wire_height - 0.10:
		return false

	if AudioBridge != null:
		var snap_rad: float = GameConfig.audio_radius_tripwire_snap if GameConfig != null else 38.0
		AudioBridge.request_world_cue("tripwire_snap", _safe_global_pos() + Vector3(0.0, 0.35, 0.0), snap_rad, owner_peer_id)
	if body.has_method("apply_trap_ko"):
		body.apply_trap_ko("TRIPWIRE", owner_peer_id)
	trigger_count += 1
	if trigger_count >= MAX_TRIGGERS:
		_triggered_or_consumed = true
		_consume_trap()
	return true


func get_interaction_prompt() -> String:
	return "[Hold E] Steal Tripwire Coil"


func supports_hold_interaction() -> bool:
	return true


func get_hold_interaction_duration() -> float:
	return GameConfig.trap_steal_hold_time if GameConfig != null else 1.00


func request_interaction(_caller_peer_id: int) -> void:
	pass


func request_hold_interaction(caller_peer_id: int) -> void:
	if _triggered_or_consumed:
		return
	if _is_peer_connected():
		_server_steal_tripwire.rpc_id(1, caller_peer_id)
	else:
		try_steal_tripwire(caller_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _server_steal_tripwire(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != caller_peer_id:
		caller_peer_id = sender
	try_steal_tripwire(caller_peer_id)


func try_steal_tripwire(caller_peer_id: int, player_override: Node = null) -> bool:
	if _triggered_or_consumed:
		return false
	var player: Node = player_override if player_override != null else _find_player_node(caller_peer_id)
	if player == null:
		return false
	var ko_val: int = GameConfig.Stance.KO if GameConfig != null else 4
	var lock_val: int = GameConfig.Stance.DRAWER_LOCK if GameConfig != null else 3
	var stance: int = int(player.get("stance_state"))
	if stance == ko_val or stance == lock_val or bool(player.get("is_clock_eliminated")):
		return false
	if player.has_method("server_pickup_world_item"):
		if not player.server_pickup_world_item("TRIPWIRE", [], _safe_global_pos(), {}, trigger_count):
			return false
	_triggered_or_consumed = true
	_consume_trap()
	return true


func _consume_trap() -> void:
	if _is_peer_connected():
		_rpc_consume.rpc()
	elif is_inside_tree():
		queue_free()


@rpc("authority", "call_local", "reliable")
func _rpc_consume() -> void:
	_triggered_or_consumed = true
	if is_inside_tree():
		queue_free()


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


func _safe_global_pos() -> Vector3:
	return global_position if is_inside_tree() else position


func _is_peer_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
