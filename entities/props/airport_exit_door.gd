@tool
class_name AirportExitDoor
extends StaticBody3D

## Single Shared Airport Exit Door (Master GDD §3).
## Touching or interacting with this door while holding the Briefcase containing all 4 Objectives
## triggers instant Escape Victory via MatchManager.

var _exit_area: Area3D = null


func _ready() -> void:
	collision_layer = (GameConfig.LAYER_ENVIRONMENT | GameConfig.LAYER_INTERACTABLE) if GameConfig != null else 3
	collision_mask = 0
	_ensure_nodes()


func _ensure_nodes() -> void:
	_exit_area = get_node_or_null("ExitTouchArea") as Area3D
	if _exit_area == null:
		_exit_area = Area3D.new()
		_exit_area.name = "ExitTouchArea"
		_exit_area.collision_layer = GameConfig.LAYER_TRIGGERS if GameConfig != null else 16
		_exit_area.collision_mask = GameConfig.LAYER_PLAYER if GameConfig != null else 4
		add_child(_exit_area)

		var area_col := CollisionShape3D.new()
		area_col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 2.3, 1.2)
		area_col.shape = box
		area_col.position = Vector3(0.0, 1.15, 0.0)
		_exit_area.add_child(area_col)
	else:
		_exit_area.collision_layer = GameConfig.LAYER_TRIGGERS if GameConfig != null else 16
		_exit_area.collision_mask = GameConfig.LAYER_PLAYER if GameConfig != null else 4

	if not _exit_area.body_entered.is_connected(_on_exit_area_body_entered):
		_exit_area.body_entered.connect(_on_exit_area_body_entered)


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


func _on_exit_area_body_entered(body: Node) -> void:
	if Engine.is_editor_hint():
		return
	if _is_peer_connected() and not multiplayer.is_server():
		return
	if body != null and body.is_in_group("spy_players"):
		try_trigger_exit_victory(body)


func try_trigger_exit_victory(player: Node) -> bool:
	if player == null:
		return false
	if str(player.get("left_hand_item_id")).to_upper() != "BRIEFCASE":
		return false

	var objs: Array = player.get("briefcase_objectives") as Array
	var req_count: int = GameConfig.required_objectives_count if GameConfig != null else 4
	if objs == null or objs.size() < req_count:
		return false

	var peer_id: int = player.name.to_int()
	if peer_id == 0:
		peer_id = 1

	if MatchManager != null:
		if MatchManager.match_state != MatchManager.MatchState.IN_PROGRESS:
			MatchManager.start_new_match([1, 2])
		return MatchManager.report_airport_exit_reached(peer_id, objs.size())
	return true


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
