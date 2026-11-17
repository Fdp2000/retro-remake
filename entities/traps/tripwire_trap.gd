@tool
class_name TripwireTrap
extends StaticBody3D

## Floor & Doorway Tripwire Trap (Doc 4 §3.2).
## Triggers 15s KO on walking/sprinting spies (owner-triggerable).
## Can be jumped over (Space) or disarmed/stolen while crouching (Ctrl + Hold E).

@export var owner_peer_id: int = 0
@export var span_width: float = 1.10

var wire_height: float = 0.35
var _triggered_or_consumed: bool = false
var _trigger_area: Area3D = null


func _ready() -> void:
	set_multiplayer_authority(1)
	collision_layer = GameConfig.LAYER_INTERACTABLE if GameConfig != null else 2
	collision_mask = 0
	wire_height = GameConfig.tripwire_height if GameConfig != null else 0.35
	_ensure_nodes()


func _ensure_nodes() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(span_width + 0.16, 0.45, 0.24)
		col.shape = box
		col.position = Vector3(0.0, 0.22, 0.0)
		add_child(col)

	if get_node_or_null("Visuals") == null:
		var vis := Node3D.new()
		vis.name = "Visuals"
		add_child(vis)

		var peg_mesh := CylinderMesh.new()
		peg_mesh.top_radius = 0.025
		peg_mesh.bottom_radius = 0.032
		peg_mesh.height = wire_height + 0.05
		var peg_mat := StandardMaterial3D.new()
		peg_mat.albedo_color = Color(0.85, 0.45, 0.15)

		for side in [-1.0, 1.0]:
			var peg := MeshInstance3D.new()
			peg.mesh = peg_mesh
			peg.material_override = peg_mat
			peg.position = Vector3(side * (span_width * 0.5), (wire_height + 0.05) * 0.5, 0.0)
			vis.add_child(peg)

		var wire_mi := MeshInstance3D.new()
		wire_mi.name = "WireMesh"
		var wire_cyl := CylinderMesh.new()
		wire_cyl.top_radius = 0.008
		wire_cyl.bottom_radius = 0.008
		wire_cyl.height = span_width
		wire_mi.mesh = wire_cyl
		wire_mi.rotation.z = PI * 0.5
		wire_mi.position = Vector3(0.0, wire_height, 0.0)
		var wire_mat := StandardMaterial3D.new()
		wire_mat.albedo_color = Color(0.95, 0.32, 0.12)
		wire_mat.emission_enabled = true
		wire_mat.emission = Color(0.85, 0.25, 0.10)
		wire_mat.emission_energy_multiplier = 0.45
		wire_mi.material_override = wire_mat
		vis.add_child(wire_mi)

	_trigger_area = get_node_or_null("TriggerArea") as Area3D
	if _trigger_area == null:
		_trigger_area = Area3D.new()
		_trigger_area.name = "TriggerArea"
		_trigger_area.collision_layer = GameConfig.LAYER_TRIGGERS if GameConfig != null else 16
		_trigger_area.collision_mask = GameConfig.LAYER_PLAYER if GameConfig != null else 4
		var trig_col := CollisionShape3D.new()
		var trig_box := BoxShape3D.new()
		trig_box.size = Vector3(span_width, 0.22, 0.14)
		trig_col.shape = trig_box
		trig_col.position = Vector3(0.0, wire_height, 0.0)
		_trigger_area.add_child(trig_col)
		add_child(_trigger_area)


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
	var spy_y: float = (body as Node3D).global_position.y if (body as Node3D).is_inside_tree() else (body as Node3D).position.y
	if spy_y >= base_y + wire_height - 0.10:
		return false

	_triggered_or_consumed = true
	if AudioBridge != null:
		AudioBridge.request_world_cue("tripwire_snap", _safe_global_pos(), 10.0, owner_peer_id)
	if body.has_method("apply_trap_ko"):
		body.apply_trap_ko("TRIPWIRE", owner_peer_id)
	_consume_trap()
	return true


func get_interaction_prompt() -> String:
	return "[Crouch + Hold E] Steal Tripwire Coil"


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
	var crouch_val: int = GameConfig.Stance.CROUCH if GameConfig != null else 2
	if int(player.get("stance_state")) != crouch_val:
		return false
	if player.has_method("server_pickup_world_item"):
		if not player.server_pickup_world_item("TRIPWIRE", [], _safe_global_pos()):
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
