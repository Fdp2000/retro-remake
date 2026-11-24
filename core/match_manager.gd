@tool
extends Node

## Server-authoritative Match & Private Clock Economy Manager (Master GDD §3, Doc 3 §3.A, Doc 7).
## Tracks match_seed, private countdown timers (03:00 start, +10s per first drawer search),
## OG 1984 Clock Elimination (surviving rival must still complete 4-item Briefcase escape),
## and Airport Exit Victory.

signal match_started(seed_value: int)
signal clock_updated(peer_id: int, remaining_seconds: float, delta_bonus: float)
signal spy_eliminated_by_clock(peer_id: int)
signal match_ended(winner_peer_id: int, reason: String)

enum MatchState {
	INACTIVE = 0,
	IN_PROGRESS = 1,
	ENDED = 2
}

var match_state: int = MatchState.INACTIVE
var match_seed: int = 0
var active_spawner_config: Dictionary = {}
var peer_clocks: Dictionary = {}        # peer_id (int) -> remaining_seconds (float)
var eliminated_peers: Dictionary = {}   # peer_id (int) -> bool
var peer_roles: Dictionary = {}         # peer_id (int) -> role (int 1..4)
var winner_peer_id: int = 0
var end_reason: String = ""

var _sync_accumulator: float = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	tick_match_clocks(delta)


func tick_match_clocks(delta: float) -> void:
	if match_state != MatchState.IN_PROGRESS:
		return
	if GameConfig != null and GameConfig.debug_disable_match_timer:
		return

	# Only server / host (or offline authority) ticks the authoritative match clocks
	if _is_network_connected() and not multiplayer.is_server():
		return

	var active_peers_remaining: int = 0
	for peer_id in peer_clocks.keys():
		if eliminated_peers.get(peer_id, false):
			continue

		var current_time: float = float(peer_clocks[peer_id]) - delta
		if current_time <= 0.0:
			peer_clocks[peer_id] = 0.0
			eliminated_peers[peer_id] = true
			_broadcast_clock_elimination(peer_id)
		else:
			peer_clocks[peer_id] = current_time
			active_peers_remaining += 1

	# OG 1984 Mutual Loss (Draw): If all spies run out of time before anyone escapes
	if active_peers_remaining == 0 and not peer_clocks.is_empty():
		_finish_match(0, "Mutual Loss (Draw) — All spies ran out of time!")
		return

	_sync_accumulator += delta
	if _sync_accumulator >= 0.25:
		_sync_accumulator = 0.0
		_sync_clocks_to_owners()


## Host initializes a deterministic match seed and resets private clocks for all participating peers.
func start_new_match(participating_peers: Array = [1, 2], custom_seed: int = 0) -> void:
	if _is_network_connected() and not multiplayer.is_server():
		return

	if custom_seed != 0:
		match_seed = custom_seed
	else:
		var seeder := RandomNumberGenerator.new()
		seeder.randomize()
		match_seed = int(seeder.randi() & 0x7FFFFFFF)
		if match_seed == 0:
			match_seed = 7321

	peer_clocks.clear()
	eliminated_peers.clear()
	winner_peer_id = 0
	end_reason = ""
	_sync_accumulator = 0.0

	if GameConfig != null and GameConfig.spawner_auto_preset_by_player_count and GameConfig.has_method("apply_player_count_preset"):
		GameConfig.apply_player_count_preset(clampi(participating_peers.size(), 2, 4))

	for peer_id in participating_peers:
		peer_clocks[peer_id] = GameConfig.starting_clock_seconds
		eliminated_peers[peer_id] = false

	match_state = MatchState.IN_PROGRESS
	active_spawner_config = GameConfig.get_spawner_config_dict() if (GameConfig != null and GameConfig.has_method("get_spawner_config_dict")) else {}

	if _is_network_connected():
		_rpc_on_match_started.rpc(match_seed, active_spawner_config)
		_sync_clocks_to_owners()
	else:
		match_started.emit(match_seed)
		for peer_id in peer_clocks.keys():
			clock_updated.emit(peer_id, peer_clocks[peer_id], 0.0)


## Awards +10s (GameConfig.drawer_first_search_bonus_seconds) to a spy's private clock on first container search.
func award_first_search_bonus(peer_id: int) -> void:
	if match_state != MatchState.IN_PROGRESS:
		return
	if _is_network_connected() and not multiplayer.is_server():
		return
	if eliminated_peers.get(peer_id, false) or not peer_clocks.has(peer_id):
		return

	var bonus: float = GameConfig.drawer_first_search_bonus_seconds
	peer_clocks[peer_id] = float(peer_clocks[peer_id]) + bonus

	if _is_network_connected() and (peer_id == 1 or peer_id in multiplayer.get_peers()):
		_rpc_update_private_clock.rpc_id(peer_id, peer_id, peer_clocks[peer_id], bonus)
	else:
		clock_updated.emit(peer_id, peer_clocks[peer_id], bonus)
		AudioBridge.play_local_cue("clock_bonus_ding")


## Validates Airport Exit victory: touching the Airport Exit Door while holding the Briefcase with all 4 Objectives.
func report_airport_exit_reached(peer_id: int, packed_objectives_count: int) -> bool:
	if match_state != MatchState.IN_PROGRESS:
		return false
	if _is_network_connected() and not multiplayer.is_server():
		return false
	if eliminated_peers.get(peer_id, false):
		return false
	if packed_objectives_count < GameConfig.required_objectives_count:
		return false

	var role: int = get_peer_role(peer_id)
	var spy_label: String = GameConfig.get_spy_role_name(role) if (GameConfig != null and role > 0) else ("Spy %d" % peer_id)
	_finish_match(peer_id, "Escape Victory — %s escaped with all %d Objectives!" % [spy_label, packed_objectives_count])
	return true


func sync_peer_roles(roles: Dictionary) -> void:
	if _is_network_connected() and not multiplayer.is_server():
		return
	var clean_roles: Dictionary = {}
	for k in roles.keys():
		clean_roles[int(k)] = int(roles[k])
	if _is_network_connected():
		_rpc_sync_peer_roles.rpc(clean_roles)
	else:
		peer_roles = clean_roles


func get_peer_role(peer_id: int) -> int:
	return int(peer_roles.get(peer_id, 0))


func eliminate_disconnected_peer(peer_id: int) -> void:
	if match_state != MatchState.IN_PROGRESS:
		return
	if _is_network_connected() and not multiplayer.is_server():
		return
	if not peer_clocks.has(peer_id) or eliminated_peers.get(peer_id, false):
		return
	peer_clocks[peer_id] = 0.0
	eliminated_peers[peer_id] = true
	_broadcast_clock_elimination(peer_id)


func get_private_clock(peer_id: int) -> float:
	return float(peer_clocks.get(peer_id, GameConfig.starting_clock_seconds))


func set_debug_timer_disabled(disabled_now: bool) -> void:
	if _is_network_connected():
		_rpc_set_debug_timer_disabled.rpc(disabled_now)
	else:
		_rpc_set_debug_timer_disabled(disabled_now)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_debug_timer_disabled(disabled_now: bool) -> void:
	if GameConfig != null:
		GameConfig.debug_disable_match_timer = disabled_now
	for peer_id in peer_clocks.keys():
		clock_updated.emit(peer_id, peer_clocks[peer_id], 0.0)


func is_peer_eliminated(peer_id: int) -> bool:
	return bool(eliminated_peers.get(peer_id, false))


func _sync_clocks_to_owners() -> void:
	for peer_id in peer_clocks.keys():
		if _is_network_connected():
			var connected_peers: PackedInt32Array = multiplayer.get_peers()
			if peer_id == 1 or peer_id in connected_peers:
				_rpc_update_private_clock.rpc_id(peer_id, peer_id, peer_clocks[peer_id], 0.0)
		else:
			clock_updated.emit(peer_id, peer_clocks[peer_id], 0.0)


func _broadcast_clock_elimination(peer_id: int) -> void:
	if _is_network_connected():
		_rpc_on_spy_eliminated.rpc(peer_id)
	else:
		spy_eliminated_by_clock.emit(peer_id)


func _finish_match(winner_id: int, reason: String) -> void:
	match_state = MatchState.ENDED
	winner_peer_id = winner_id
	end_reason = reason
	if _is_network_connected():
		_rpc_on_match_ended.rpc(winner_id, reason)
	else:
		match_ended.emit(winner_id, reason)


func _is_network_connected() -> bool:
	if Engine.is_editor_hint() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


@rpc("authority", "call_local", "reliable")
func _rpc_sync_peer_roles(roles: Dictionary) -> void:
	var clean_roles: Dictionary = {}
	for k in roles.keys():
		clean_roles[int(k)] = int(roles[k])
	peer_roles = clean_roles


@rpc("authority", "call_local", "reliable")
func _rpc_on_match_started(seed_value: int, synced_spawner_config: Dictionary = {}) -> void:
	match_seed = seed_value
	active_spawner_config = synced_spawner_config.duplicate()
	if not synced_spawner_config.is_empty() and GameConfig != null and GameConfig.has_method("apply_spawner_config_dict"):
		GameConfig.apply_spawner_config_dict(synced_spawner_config)
	match_state = MatchState.IN_PROGRESS
	eliminated_peers.clear()
	winner_peer_id = 0
	end_reason = ""
	match_started.emit(seed_value)


@rpc("authority", "call_local", "unreliable")
func _rpc_update_private_clock(peer_id: int, remaining_seconds: float, delta_bonus: float) -> void:
	peer_clocks[peer_id] = remaining_seconds
	if delta_bonus > 0.0:
		AudioBridge.play_local_cue("clock_bonus_ding")
	clock_updated.emit(peer_id, remaining_seconds, delta_bonus)


@rpc("authority", "call_local", "reliable")
func _rpc_on_spy_eliminated(peer_id: int) -> void:
	peer_clocks[peer_id] = 0.0
	eliminated_peers[peer_id] = true
	spy_eliminated_by_clock.emit(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_on_match_ended(winner_id: int, reason: String) -> void:
	match_state = MatchState.ENDED
	winner_peer_id = winner_id
	end_reason = reason
	match_ended.emit(winner_id, reason)
