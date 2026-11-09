extends StaticBody3D

@export var prop_id: int = 0
@export var is_active: bool = false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var material: StandardMaterial3D

const COLOR_INACTIVE: Color = Color(0.85, 0.2, 0.2)  # Red
const COLOR_ACTIVE: Color = Color(0.2, 0.85, 0.3)    # Green

func _ready() -> void:
	# Ensure unique material instance so each prop updates visually independently
	material = StandardMaterial3D.new()
	mesh_instance.material_override = material
	_update_color()

	# If host, sync current state to any newly connecting peers
	NetworkManager.player_connected.connect(_on_player_connected)

func _on_player_connected(peer_id: int) -> void:
	if multiplayer.is_server() and peer_id != 1:
		sync_state.rpc_id(peer_id, is_active)

func request_interaction(caller_peer_id: int) -> void:
	# Route request to host (Peer 1)
	server_interact.rpc_id(1, prop_id, caller_peer_id)

@rpc("any_peer", "call_local", "reliable")
func server_interact(p_prop_id: int, caller_peer_id: int) -> void:
	# Authoritative server validation: only host / Peer 1 handles interaction logic
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	# Prevent ID spoofing if caller_peer_id doesn't match the network sender
	if sender_id != 0 and caller_peer_id != sender_id:
		push_warning("InteractableBox [prop_id=%d]: Correcting spoofed caller ID %d to sender %d" % [prop_id, caller_peer_id, sender_id])
		caller_peer_id = sender_id

	is_active = not is_active
	print("InteractableBox [prop_id=%d]: Host toggled is_active to %s (requested by peer %d)" % [prop_id, str(is_active), caller_peer_id])
	sync_state.rpc(is_active)

@rpc("authority", "call_local", "reliable")
func sync_state(new_state: bool) -> void:
	# Verify sender is host (peer 1) or local invocation (peer 0)
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != 1:
		push_error("InteractableBox [prop_id=%d]: Unauthorized sync_state received from peer %d" % [prop_id, sender_id])
		return

	is_active = new_state
	_update_color()
	print("InteractableBox [prop_id=%d]: Synced state to %s (local peer: %d, color: %s)" % [
		prop_id,
		str(is_active),
		multiplayer.get_unique_id(),
		"GREEN" if is_active else "RED"
	])

func _update_color() -> void:
	if material:
		material.albedo_color = COLOR_ACTIVE if is_active else COLOR_INACTIVE
