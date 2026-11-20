@tool
class_name AirportExitDoor
extends StaticBody3D

## Single Shared Airport Exit Door (Master GDD §3).
## Interacting ([E]) with this door while holding the Briefcase containing all 4 Objectives
## triggers instant Escape Victory via MatchManager; otherwise it KOs the player with a ragdoll knockback.


func _ready() -> void:
	collision_layer = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3
	collision_mask = 0


func get_interaction_prompt() -> String:
	return "[E] Escape via Airport Exit (Needs 4/4 Briefcase)"


func request_interaction(caller_peer_id: int) -> void:
	if _is_peer_connected():
		_server_attempt_exit.rpc_id(1, caller_peer_id)
	else:
		var p: Node = _find_player_node(caller_peer_id)
		if p != null:
			try_trigger_exit_victory(p)


@rpc("any_peer", "call_local", "reliable")
func _server_attempt_exit(caller_peer_id: int) -> void:
	if _is_peer_connected() and not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		caller_peer_id = sender
	var p: Node = _find_player_node(caller_peer_id)
	if p != null:
		try_trigger_exit_victory(p)


func try_trigger_exit_victory(player: Node) -> bool:
	if player == null:
		return false
	if str(player.get("left_hand_item_id")).to_upper() != "BRIEFCASE":
		_ko_rejected_exit_attempt(player)
		return false

	var objs: Array = player.get("briefcase_objectives") as Array
	var req_count: int = GameConfig.required_objectives_count if GameConfig != null else 4
	if objs == null or objs.size() < req_count:
		_ko_rejected_exit_attempt(player)
		return false

	var peer_id: int = player.name.to_int()
	if peer_id == 0:
		peer_id = 1

	if MatchManager != null:
		if MatchManager.match_state != MatchManager.MatchState.IN_PROGRESS:
			MatchManager.start_new_match([1, 2])
		return MatchManager.report_airport_exit_reached(peer_id, objs.size())
	return true


func _ko_rejected_exit_attempt(player: Node) -> void:
	if player == null or not player.has_method("apply_trap_ko"):
		return
	var kick_impulse: Vector3 = Vector3.ZERO
	if is_inside_tree() and player is Node3D:
		var away: Vector3 = (player as Node3D).global_position - global_position
		away.y = 0.0
		if away.length_squared() > 0.01:
			kick_impulse = away.normalized() * 12.0 + Vector3(0.0, 5.0, 0.0)
	player.apply_trap_ko("AIRPORT_EXIT", 0, kick_impulse)


func _find_player_node(peer_id: int) -> Node:
	if is_inside_tree() and get_tree() != null:
		var scene: Node = get_tree().current_scene
		if scene != null:
			var p: Node = scene.get_node_or_null("Players/" + str(peer_id))
			if p != null:
				return p
		for candidate in get_tree().get_nodes_in_group("spy_players"):
			if candidate.name == str(peer_id):
				return candidate
	var parent: Node = get_parent()
	while parent != null:
		var p2: Node = parent.get_node_or_null("Players/" + str(peer_id))
		if p2 != null:
			return p2
		parent = parent.get_parent()
	return null


func _is_peer_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
