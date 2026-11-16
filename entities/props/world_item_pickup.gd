@tool
class_name WorldItemPickup
extends StaticBody3D

## Server-authoritative floor pickup for Loose Objectives (KEY, MONEY, PASSPORT, PLANS),
## the Compact Briefcase (BRIEFCASE), and Traps/Gadgets (BUCKET, TRIPWIRE, SPRING, BOMB, LIVE_BOMB, DART_GUN).

enum ItemSlotType {
	LEFT_HAND_OBJECTIVE = 0,
	LEFT_HAND_BRIEFCASE = 1,
	RIGHT_HAND_GADGET = 2
}

const OBJECTIVE_IDS: Array[String] = ["KEY", "MONEY", "PASSPORT", "PLANS"]
const GADGET_IDS: Array[String] = ["BUCKET", "TRIPWIRE", "SPRING", "BOMB", "DART_GUN"]

const ITEM_COLORS: Dictionary = {
	"KEY": Color(0.95, 0.80, 0.15),       # Gold
	"MONEY": Color(0.20, 0.78, 0.30),     # Dollar Green
	"PASSPORT": Color(0.18, 0.38, 0.85),  # Diplomatic Blue
	"PLANS": Color(0.92, 0.92, 0.88),     # Blueprint White
	"BRIEFCASE": Color(0.38, 0.22, 0.10), # Leather Brown
	"BUCKET": Color(0.55, 0.62, 0.68),    # Galvanized Tin
	"TRIPWIRE": Color(0.85, 0.45, 0.15),  # Copper Coil
	"SPRING": Color(0.85, 0.18, 0.18),    # Boxing Glove Red
	"BOMB": Color(0.15, 0.15, 0.18),      # Cartoon Bomb Black
	"LIVE_BOMB": Color(0.95, 0.32, 0.12), # Sparking Hot-Potato Orange-Red
	"DART_GUN": Color(0.65, 0.20, 0.85)   # Retro DVD Purple
}

const ITEM_DISPLAY_NAMES: Dictionary = {
	"KEY": "Secret Key",
	"MONEY": "Bag of Money",
	"PASSPORT": "Passport",
	"PLANS": "Secret Plans",
	"BRIEFCASE": "Compact Briefcase",
	"BUCKET": "Water Bucket",
	"TRIPWIRE": "Tripwire Coil",
	"SPRING": "Spring Trap",
	"BOMB": "Time Bomb",
	"LIVE_BOMB": "Lit Time Bomb!",
	"DART_GUN": "DVD Dart Gun"
}

@export var item_id: String = "KEY":
	set(value):
		item_id = value.to_upper()
		if is_inside_tree():
			_rebuild_visuals()

@export var packed_objectives: Array[String] = []

var _mesh_instance: MeshInstance3D = null
var _collision_shape: CollisionShape3D = null
var _is_consumed: bool = false


func _ready() -> void:
	collision_layer = GameConfig.LAYER_INTERACTABLE if GameConfig != null else 2
	collision_mask = 0
	_ensure_child_nodes()
	_rebuild_visuals()


static func is_objective_item(id: String) -> bool:
	return id.to_upper() in OBJECTIVE_IDS


static func is_briefcase_item(id: String) -> bool:
	return id.to_upper() == "BRIEFCASE"


static func is_gadget_item(id: String) -> bool:
	return id.to_upper() in GADGET_IDS


static func get_display_name(id: String, briefcase_items: Array = []) -> String:
	var upper: String = id.to_upper()
	if upper == "NONE" or upper.is_empty():
		return "Empty"
	if upper == "CLUB":
		return "Two-Handed Club"
	var base_name: String = ITEM_DISPLAY_NAMES.get(upper, upper)
	if upper == "BRIEFCASE":
		return "%s [%d/4]" % [base_name, briefcase_items.size()]
	return base_name


static func build_item_mesh(id: String) -> MeshInstance3D:
	var upper: String = id.to_upper()
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ITEM_COLORS.get(upper, Color(0.8, 0.8, 0.8))

	match upper:
		"BRIEFCASE":
			var box := BoxMesh.new()
			box.size = Vector3(0.42, 0.30, 0.12)
			mi.mesh = box
		"KEY":
			var box := BoxMesh.new()
			box.size = Vector3(0.18, 0.06, 0.30)
			mi.mesh = box
		"MONEY":
			var sph := SphereMesh.new()
			sph.radius = 0.16
			sph.height = 0.28
			mi.mesh = sph
		"PASSPORT":
			var box := BoxMesh.new()
			box.size = Vector3(0.18, 0.04, 0.24)
			mi.mesh = box
		"PLANS":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.05
			cyl.bottom_radius = 0.05
			cyl.height = 0.36
			mi.mesh = cyl
			mi.rotation.z = PI * 0.5
		"BUCKET":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.16
			cyl.bottom_radius = 0.12
			cyl.height = 0.28
			mi.mesh = cyl
		"BOMB", "LIVE_BOMB":
			var sph := SphereMesh.new()
			sph.radius = 0.14
			sph.height = 0.28
			mi.mesh = sph
		"CLUB":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.06
			cyl.bottom_radius = 0.03
			cyl.height = 0.65
			mi.mesh = cyl
			mat.albedo_color = Color(0.48, 0.30, 0.14)
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.22, 0.14, 0.22)
			mi.mesh = box

	mi.material_override = mat
	return mi


func get_interaction_prompt() -> String:
	var disp: String = get_display_name(item_id, packed_objectives)
	if is_objective_item(item_id) or is_briefcase_item(item_id):
		return "[E] Pick Up %s (Left Hand)" % disp
	if item_id.to_upper() == "LIVE_BOMB":
		return "[E] Grab %s (Active Hand!)" % disp
	return "[E] Pick Up %s (Inner Jacket 1-3)" % disp


func request_interaction(caller_peer_id: int) -> void:
	if _is_consumed:
		return
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_server_request_pickup.rpc_id(1, caller_peer_id)
	else:
		_execute_server_pickup(caller_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _server_request_pickup(caller_peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != caller_peer_id:
		caller_peer_id = sender_id
	_execute_server_pickup(caller_peer_id)


func _execute_server_pickup(peer_id: int) -> void:
	if _is_consumed:
		return
	var player: Node = _find_player_node(peer_id)
	if player == null or not player.has_method("server_pickup_world_item"):
		return

	_is_consumed = true
	var picked: bool = player.server_pickup_world_item(item_id, packed_objectives.duplicate(), global_position)
	if picked:
		if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_rpc_consume_pickup.rpc()
		else:
			queue_free()
	else:
		_is_consumed = false


@rpc("authority", "call_local", "reliable")
func _rpc_consume_pickup() -> void:
	_is_consumed = true
	queue_free()


func _find_player_node(peer_id: int) -> Node:
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


func _ensure_child_nodes() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(0.45, 0.35, 0.45)
		_collision_shape.shape = box_shape
		_collision_shape.position = Vector3(0.0, 0.18, 0.0)
		add_child(_collision_shape)

	_mesh_instance = get_node_or_null("VisualMesh") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "VisualMesh"
		_mesh_instance.position = Vector3(0.0, 0.18, 0.0)
		add_child(_mesh_instance)


func _rebuild_visuals() -> void:
	_ensure_child_nodes()
	var template: MeshInstance3D = build_item_mesh(item_id)
	_mesh_instance.mesh = template.mesh
	_mesh_instance.material_override = template.material_override
	_mesh_instance.rotation = template.rotation
	template.free()
