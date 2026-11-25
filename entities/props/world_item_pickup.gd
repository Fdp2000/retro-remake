@tool
class_name WorldItemPickup
extends StaticBody3D

## Server-authoritative floor pickup for Loose Objectives (KEY, MONEY, PASSPORT, PLANS),
## the Compact Briefcase (BRIEFCASE), and Traps/Gadgets (BUCKET, TRIPWIRE, SPRING, BOMB, LIVE_BOMB, DART_GUN)

enum ItemSlotType {
	LEFT_HAND_OBJECTIVE = 0,
	LEFT_HAND_BRIEFCASE = 1,
	RIGHT_HAND_GADGET = 2
}

const OBJECTIVE_IDS: Array[String] = ["KEY", "MONEY", "PASSPORT", "PLANS"]
const GADGET_IDS: Array[String] = ["BUCKET", "TRIPWIRE", "SPRING", "BOMB", "DART_GUN"]
const BRIEFCASE_BUILDER = preload("res://entities/props/briefcase_visual_builder.gd")

const KEY_SCENE: PackedScene = preload("res://Assets/Prefabs Samleobjekter/key.tscn")
const MONEY_SCENE: PackedScene = preload("res://Assets/Prefabs Samleobjekter/money.tscn")
const PASSPORT_SCENE: PackedScene = preload("res://Assets/Prefabs Samleobjekter/passport.tscn")
const PLANS_SCENE: PackedScene = preload("res://Assets/Prefabs Samleobjekter/plans.tscn")

const BOMB_SCENE: PackedScene = preload("res://Assets/Prefab_Traps/bomb.tscn")
const TRIPWIRE_SCENE: PackedScene = preload("res://Assets/Prefab_Traps/tripwire.tscn")
const BUCKET_SCENE: PackedScene = preload("res://Assets/Prefab_Traps/bucket.tscn")
const DART_GUN_SCENE: PackedScene = preload("res://Assets/Prefab_Traps/dart_gun.tscn")
const SPRING_SCENE: PackedScene = preload("res://Assets/Prefab_Traps/spring.tscn")
const CLUB_SCENE: PackedScene = preload("res://Assets/Prefab_Club/club.tscn")

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
			if is_briefcase_item(item_id):
				_ensure_briefcase_container()

@export var packed_objectives: Array[String] = []
@export var packed_item_positions: Dictionary = {}
@export var bomb_norm_pos: Vector2 = Vector2(0.50, 0.45)
@export var armed_spring: bool = false
@export var spring_owner_peer_id: int = 0
@export var armed_bomb: bool = false
@export var bomb_owner_peer_id: int = 0
@export var tripwire_ko_count: int = 0

var _visual_root: Node3D = null
var _collision_shape: CollisionShape3D = null
var _briefcase_container: Node = null
var _is_consumed: bool = false


func _ready() -> void:
	collision_layer = GameConfig.LAYER_INTERACTABLE if GameConfig != null else 2
	collision_mask = 0
	_ensure_child_nodes()
	_rebuild_visuals()
	if is_briefcase_item(item_id):
		_ensure_briefcase_container()


static func is_objective_item(id: String) -> bool:
	return id.to_upper() in OBJECTIVE_IDS


static func is_briefcase_item(id: String) -> bool:
	return id.to_upper() == "BRIEFCASE"


static func is_gadget_item(id: String) -> bool:
	return id.to_upper() in GADGET_IDS


static func should_emit_pickup_glint(id: String) -> bool:
	var upper: String = id.to_upper()
	if upper == "LIVE_BOMB" or upper == "NONE" or upper.is_empty():
		return false
	return is_objective_item(upper) or is_briefcase_item(upper) or is_gadget_item(upper) or upper == "CLUB"


static func get_display_name(id: String, briefcase_items: Array = []) -> String:
	var upper: String = id.to_upper()
	if upper == "NONE" or upper.is_empty():
		return "Empty"
	if upper == "CLUB":
		return "Two-Handed Club"
	var base_name: String = ITEM_DISPLAY_NAMES.get(upper, upper)
	return base_name


const DART_GUN_MUZZLE_LOCAL_POS: Vector3 = Vector3(0.0, 0.083, -0.176)


const _MODEL_VISUAL_SPECS: Dictionary = {
	"KEY": {"scene": KEY_SCENE, "scale": Vector3(1.15, 1.15, 1.15), "offset": Vector3(0.0, 0.0, -0.005), "rot": Vector3.ZERO, "floor_y": 0.025},
	"MONEY": {"scene": MONEY_SCENE, "scale": Vector3(0.90, 0.90, 0.90), "offset": Vector3(0.0, -0.105, 0.0), "rot": Vector3.ZERO, "floor_y": 0.105},
	"PASSPORT": {"scene": PASSPORT_SCENE, "scale": Vector3(1.15, 1.15, 1.15), "offset": Vector3(0.004, 0.0, 0.0), "rot": Vector3.ZERO, "floor_y": 0.025},
	"PLANS": {"scene": PLANS_SCENE, "scale": Vector3(1.10, 1.10, 1.10), "offset": Vector3.ZERO, "rot": Vector3.ZERO, "floor_y": 0.025},
	"BUCKET": {"scene": BUCKET_SCENE, "scale": Vector3(0.40, 0.40, 0.40), "offset": Vector3(0.0, -0.164, 0.0), "rot": Vector3.ZERO, "floor_y": 0.164},
	"TRIPWIRE": {"scene": TRIPWIRE_SCENE, "scale": Vector3(1.40, 1.40, 1.40), "offset": Vector3(0.0, -0.107, 0.0), "rot": Vector3.ZERO, "floor_y": 0.107},
	"SPRING": {"scene": SPRING_SCENE, "scale": Vector3(1.15, 1.15, 1.15), "offset": Vector3(-0.005, -0.015, -0.003), "rot": Vector3.ZERO, "floor_y": 0.101},
	"DART_GUN": {"scene": DART_GUN_SCENE, "scale": Vector3(0.85, 0.85, 0.85), "offset": Vector3(0.0, 0.021, 0.029), "rot": Vector3(0.0, PI * 0.5, 0.0), "floor_y": 0.106},
	"BOMB": {"scene": BOMB_SCENE, "scale": Vector3(0.85, 0.85, 0.85), "offset": Vector3(0.001, -0.146, 0.001), "rot": Vector3.ZERO, "floor_y": 0.146},
	"LIVE_BOMB": {"scene": BOMB_SCENE, "scale": Vector3(0.85, 0.85, 0.85), "offset": Vector3(0.001, -0.146, 0.001), "rot": Vector3.ZERO, "floor_y": 0.146},
	"CLUB": {"scene": CLUB_SCENE, "scale": Vector3(0.68, 0.68, 0.68), "offset": Vector3(0.0, -0.202, 0.0), "rot": Vector3.ZERO, "floor_y": 0.330}
}


static func get_item_floor_y(id: String) -> float:
	var upper: String = id.to_upper()
	if _MODEL_VISUAL_SPECS.has(upper):
		return float(_MODEL_VISUAL_SPECS[upper]["floor_y"])
	return 0.18


## Instantiates a centered visual Node3D for any trap, objective, briefcase, or melee item.
static func build_item_visual(id: String) -> Node3D:
	var upper: String = id.to_upper()
	if upper == "BRIEFCASE":
		var wrapper := Node3D.new()
		var model: Node3D = BRIEFCASE_BUILDER.instantiate_textured_briefcase()
		if model != null:
			model.scale = Vector3(0.76, 0.76, 0.76)
			model.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			model.position = Vector3(0.0, -0.04, 0.0)
			wrapper.add_child(model)
		return wrapper

	if _MODEL_VISUAL_SPECS.has(upper):
		var spec: Dictionary = _MODEL_VISUAL_SPECS[upper]
		var wrapper := Node3D.new()
		var scene: PackedScene = spec["scene"] as PackedScene
		var model: Node3D = scene.instantiate() as Node3D
		model.position = spec["offset"] as Vector3
		model.rotation = spec["rot"] as Vector3
		model.scale = spec["scale"] as Vector3
		wrapper.add_child(model)
		if upper == "LIVE_BOMB":
			_attach_live_bomb_fuse_fx(wrapper, model)
		elif upper == "DART_GUN":
			var muzzle := Marker3D.new()
			muzzle.name = "MuzzleTip"
			muzzle.position = DART_GUN_MUZZLE_LOCAL_POS
			wrapper.add_child(muzzle)
		return wrapper

	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ITEM_COLORS.get(upper, Color(0.8, 0.8, 0.8))

	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.14, 0.22)
	mi.mesh = box

	if is_briefcase_item(upper):
		mat.emission_enabled = true
		mat.emission = mat.albedo_color * 0.45
		mat.emission_energy_multiplier = 0.65
	mi.material_override = mat
	return mi


## Backwards-compatible alias for callers expecting build_item_mesh.
static func build_item_mesh(id: String) -> Node3D:
	return build_item_visual(id)


const BOMB_FUSE_TIP_LOCAL_POS: Vector3 = Vector3(0.047, 0.341, -0.001)

static var _smoke_puff_texture: GradientTexture2D = null


static func _get_smoke_puff_texture() -> GradientTexture2D:
	if _smoke_puff_texture == null:
		var grad := Gradient.new()
		grad.set_offset(0, 0.0)
		grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		grad.set_offset(1, 1.0)
		grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		grad.add_point(0.35, Color(1.0, 1.0, 1.0, 0.55))
		grad.add_point(0.72, Color(1.0, 1.0, 1.0, 0.12))
		_smoke_puff_texture = GradientTexture2D.new()
		_smoke_puff_texture.width = 64
		_smoke_puff_texture.height = 64
		_smoke_puff_texture.fill = GradientTexture2D.FILL_RADIAL
		_smoke_puff_texture.fill_from = Vector2(0.5, 0.5)
		_smoke_puff_texture.fill_to = Vector2(0.5, 0.0)
		_smoke_puff_texture.gradient = grad
	return _smoke_puff_texture


static func _attach_live_bomb_fuse_fx(_wrapper: Node3D, model: Node3D) -> void:
	var fuse_tip := Node3D.new()
	fuse_tip.name = "FuseTip"
	fuse_tip.position = BOMB_FUSE_TIP_LOCAL_POS
	model.add_child(fuse_tip)

	var ember := MeshInstance3D.new()
	ember.name = "FuseEmber"
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sph := SphereMesh.new()
	sph.radius = 0.018
	sph.height = 0.036
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.albedo_color = Color(1.0, 0.58, 0.14)
	ember.mesh = sph
	ember.material_override = ember_mat
	fuse_tip.add_child(ember)

	var sparks := CPUParticles3D.new()
	sparks.name = "FuseSparks"
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.amount = 10
	sparks.lifetime = 0.32
	sparks.local_coords = true
	sparks.emitting = true
	sparks.direction = Vector3(0.25, 1.0, 0.0).normalized()
	sparks.spread = 55.0
	sparks.gravity = Vector3(0.0, -3.5, 0.0)
	sparks.initial_velocity_min = 0.30
	sparks.initial_velocity_max = 0.70
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.018, 0.018)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.albedo_color = Color(1.0, 0.75, 0.22)
	spark_mesh.material = spark_mat
	sparks.mesh = spark_mesh
	fuse_tip.add_child(sparks)

	var smoke := CPUParticles3D.new()
	smoke.name = "FuseSmoke"
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.amount = 16
	smoke.lifetime = 0.85
	smoke.preprocess = 0.10
	smoke.local_coords = false
	smoke.emitting = true
	smoke.direction = Vector3(0.0, 1.0, 0.0)
	smoke.spread = 26.0
	smoke.gravity = Vector3(0.0, 0.55, 0.0)
	smoke.initial_velocity_min = 0.08
	smoke.initial_velocity_max = 0.18
	smoke.damping_min = 0.15
	smoke.damping_max = 0.30
	smoke.scale_amount_min = 0.75
	smoke.scale_amount_max = 1.25
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.45))
	scale_curve.add_point(Vector2(0.5, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.45))
	smoke.scale_amount_curve = scale_curve
	var smoke_grad := Gradient.new()
	smoke_grad.set_offset(0, 0.0)
	smoke_grad.set_color(0, Color(0.58, 0.54, 0.50, 0.62))
	smoke_grad.set_offset(1, 1.0)
	smoke_grad.set_color(1, Color(0.28, 0.28, 0.30, 0.0))
	smoke_grad.add_point(0.35, Color(0.40, 0.40, 0.42, 0.38))
	smoke.color_ramp = smoke_grad
	var smoke_mesh := QuadMesh.new()
	smoke_mesh.size = Vector2(0.044, 0.044)
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.disable_receive_shadows = true
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.albedo_texture = _get_smoke_puff_texture()
	smoke_mesh.material = smoke_mat
	smoke.mesh = smoke_mesh
	fuse_tip.add_child(smoke)


const ARTIFACT_PARTICLE_TEXTURE: Texture2D = preload("res://Assets/Sprites/ArtifactParticle.png")


static func create_objective_glint_particles(in_drawer: bool = false, item_id_hint: String = "", footprint_xz: Vector2 = Vector2.ZERO) -> CPUParticles3D:
	var upper: String = item_id_hint.to_upper()
	var is_high_priority: bool = upper.is_empty() or is_objective_item(upper) or is_briefcase_item(upper)
	var particles := CPUParticles3D.new()
	particles.name = "ObjectiveGlintParticles"
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.amount = 6 if in_drawer else (9 if is_high_priority else 7)
	particles.lifetime = 0.70 if in_drawer else 0.95
	particles.preprocess = 0.35
	particles.local_coords = true
	particles.emitting = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	if in_drawer:
		var ex_x: float = clampf(footprint_xz.x * 0.34, 0.028, 0.145) if footprint_xz.x > 0.001 else 0.055
		var ex_z: float = clampf(footprint_xz.y * 0.34, 0.024, 0.110) if footprint_xz.y > 0.001 else 0.055
		particles.emission_box_extents = Vector3(ex_x, 0.0002, ex_z)
		particles.direction = Vector3(1.0, 0.0, 0.0)
		particles.spread = 180.0
		particles.flatness = 1.0
		particles.gravity = Vector3.ZERO
		particles.initial_velocity_min = 0.003
		particles.initial_velocity_max = 0.010
	else:
		var box_ext := Vector3(0.22, 0.03, 0.15) if upper == "BRIEFCASE" else Vector3(0.15, 0.04, 0.15)
		particles.emission_box_extents = box_ext
		particles.direction = Vector3(0.0, 1.0, 0.0)
		particles.spread = 22.0
		particles.gravity = Vector3.ZERO
		particles.initial_velocity_min = 0.06
		particles.initial_velocity_max = 0.14
		particles.angular_velocity_min = -65.0
		particles.angular_velocity_max = 65.0

	particles.scale_amount_min = 0.65
	particles.scale_amount_max = 1.15
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.15))
	scale_curve.add_point(Vector2(0.32, 1.12))
	scale_curve.add_point(Vector2(0.74, 0.82))
	scale_curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = scale_curve

	var ramp := Gradient.new()
	ramp.set_offset(0, 0.0)
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	ramp.set_offset(1, 1.0)
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	ramp.add_point(0.22, Color(1.0, 1.0, 1.0, 0.95))
	ramp.add_point(0.76, Color(1.0, 1.0, 1.0, 0.85))
	particles.color_ramp = ramp

	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.albedo_texture = ARTIFACT_PARTICLE_TEXTURE
	spark_mat.albedo_color = Color(1.0, 0.92, 0.50, 0.95) if is_high_priority else Color(1.0, 0.96, 0.78, 0.90)

	if in_drawer:
		# Flat horizontal XZ plane so particles stay strictly inside the item's own Y layer slot
		# and are naturally depth-occluded by any clutter or items on layers above.
		spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var plane_mesh := PlaneMesh.new()
		plane_mesh.size = Vector2(0.022, 0.022)
		plane_mesh.orientation = PlaneMesh.FACE_Y
		plane_mesh.material = spark_mat
		particles.mesh = plane_mesh
	else:
		spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		var spark_mesh := QuadMesh.new()
		spark_mesh.size = Vector2(0.036, 0.036)
		spark_mesh.material = spark_mat
		particles.mesh = spark_mesh
	return particles


func get_interaction_prompt() -> String:
	return get_interaction_prompt_for_player(null)


func get_interaction_prompt_for_player(player: Node) -> String:
	var disp: String = get_display_name(item_id, packed_objectives)
	if is_briefcase_item(item_id):
		if _briefcase_container != null and is_instance_valid(_briefcase_container) and int(_briefcase_container.get("occupied_by_peer_id")) != 0:
			return "[IN USE]"
		var held_left: String = str(player.get("left_hand_item_id")).to_upper() if player != null else "NONE"
		if is_objective_item(held_left):
			return "[E] Open %s to Pack %s" % [disp, get_display_name(held_left)]
		return "[Tap E] Carry %s (Left Hand)  |  [Hold E] Open & Inspect" % disp
	if is_objective_item(item_id):
		var held_left: String = str(player.get("left_hand_item_id")).to_upper() if player != null else "NONE"
		if held_left == "BRIEFCASE":
			return "[E] Pick Up %s (Drops Briefcase)" % disp
		if is_objective_item(held_left):
			if held_left == item_id.to_upper():
				return "[Holding %s]" % disp
			return "[E] Swap %s ↔ %s" % [get_display_name(held_left), disp]
		return "[E] Pick Up %s (Left Hand)" % disp
	if item_id.to_upper() == "LIVE_BOMB":
		return "[E] Grab %s (Active Hand!)" % disp
	return "[E] Pick Up %s (Inner Jacket 1-3)" % disp


func supports_hold_interaction() -> bool:
	return is_briefcase_item(item_id)


func get_hold_interaction_duration() -> float:
	return 0.45


func request_focus_briefcase(caller_peer_id: int) -> void:
	if _is_consumed or not is_briefcase_item(item_id):
		return
	var container: Node = _ensure_briefcase_container()
	if container != null and container.has_method("request_focus_container"):
		container.request_focus_container(caller_peer_id)


func request_hold_interaction(caller_peer_id: int) -> void:
	# Holding E on a floor Briefcase enters two-stage Closed (0%) Focus Mode just like drawers
	request_focus_briefcase(caller_peer_id)


func get_briefcase_container() -> Node:
	if not is_briefcase_item(item_id):
		return null
	return _ensure_briefcase_container()


func _ensure_briefcase_container() -> Node:
	if _briefcase_container != null and is_instance_valid(_briefcase_container):
		return _briefcase_container
	_briefcase_container = get_node_or_null("BriefcaseContainer")
	if _briefcase_container == null:
		var container_script: Script = load("res://entities/props/searchable_container.gd")
		_briefcase_container = container_script.new()
		_briefcase_container.name = "BriefcaseContainer"
		_briefcase_container.set("container_id", "Compact Briefcase")
		_briefcase_container.set("is_briefcase_container", true)
		_briefcase_container.set("clutter_count", 0)
		_briefcase_container.set("linked_briefcase_pickup", self)
		var typed_items: Array[String] = []
		for obj in packed_objectives:
			typed_items.append(str(obj).to_upper())
		_briefcase_container.set("stored_items", typed_items)
		_briefcase_container.set("item_positions", packed_item_positions.duplicate())
		_briefcase_container.set("bomb_norm_pos", bomb_norm_pos)
		_briefcase_container.set("armed_spring", armed_spring)
		_briefcase_container.set("spring_owner_peer_id", spring_owner_peer_id)
		_briefcase_container.set("armed_bomb", armed_bomb)
		_briefcase_container.set("bomb_owner_peer_id", bomb_owner_peer_id)
		add_child(_briefcase_container)
	else:
		var typed_items: Array[String] = []
		for obj in packed_objectives:
			typed_items.append(str(obj).to_upper())
		_briefcase_container.set("stored_items", typed_items)
		_briefcase_container.set("item_positions", packed_item_positions.duplicate())
		_briefcase_container.set("bomb_norm_pos", bomb_norm_pos)
		_briefcase_container.set("armed_spring", armed_spring)
		_briefcase_container.set("spring_owner_peer_id", spring_owner_peer_id)
		_briefcase_container.set("armed_bomb", armed_bomb)
		_briefcase_container.set("bomb_owner_peer_id", bomb_owner_peer_id)
	return _briefcase_container


func request_interaction(caller_peer_id: int) -> void:
	if _is_consumed:
		return
	if not Engine.is_editor_hint() and multiplayer != null and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
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

	if is_briefcase_item(item_id):
		var container: Node = _ensure_briefcase_container()
		if container != null and int(container.get("occupied_by_peer_id")) != 0:
			return
		# Playtest design rule: if player holds a loose Objective in Left Hand, pressing E on the Briefcase
		# enters two-stage Briefcase Focus/Search Mode instead of picking it up or auto-packing!
		var held_left: String = str(player.get("left_hand_item_id")).to_upper()
		if is_objective_item(held_left):
			if container != null and container.has_method("focus_container"):
				container.focus_container(peer_id, player)
			return
		if container != null:
			packed_objectives.clear()
			for it in container.get("stored_items"):
				packed_objectives.append(str(it))
			var raw_pos: Variant = container.get("item_positions")
			packed_item_positions = (raw_pos as Dictionary).duplicate() if raw_pos is Dictionary else {}
			var raw_bpos: Variant = container.get("bomb_norm_pos")
			if raw_bpos is Vector2:
				bomb_norm_pos = raw_bpos as Vector2
			armed_spring = bool(container.get("armed_spring"))
			spring_owner_peer_id = int(container.get("spring_owner_peer_id"))
			armed_bomb = bool(container.get("armed_bomb"))
			bomb_owner_peer_id = int(container.get("bomb_owner_peer_id"))

	_is_consumed = true
	var picked: bool = player.server_pickup_world_item(item_id, packed_objectives.duplicate(), global_position, packed_item_positions.duplicate(), tripwire_ko_count)
	if picked:
		if is_briefcase_item(item_id):
			if player.has_method("set_briefcase_trap_state"):
				player.set_briefcase_trap_state(armed_spring, spring_owner_peer_id, armed_bomb, bomb_owner_peer_id, bomb_norm_pos)
			elif player.has_method("set_briefcase_bomb_state"):
				player.set_briefcase_bomb_state(armed_bomb, bomb_owner_peer_id)
		if not Engine.is_editor_hint() and multiplayer != null and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
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
		var p3: Node = parent.get_node_or_null(str(peer_id))
		if p3 != null and p3.has_method("pickup_item"):
			return p3
		parent = parent.get_parent()
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

	var legacy_mesh := get_node_or_null("VisualMesh") as MeshInstance3D
	if legacy_mesh != null:
		legacy_mesh.visible = false

	_visual_root = get_node_or_null("VisualRoot") as Node3D
	if _visual_root == null:
		_visual_root = Node3D.new()
		_visual_root.name = "VisualRoot"
		_visual_root.position = Vector3(0.0, 0.18, 0.0)
		add_child(_visual_root)


func _rebuild_visuals() -> void:
	_ensure_child_nodes()
	var old_glint: Node = get_node_or_null("ObjectiveGlintParticles")
	if old_glint != null:
		remove_child(old_glint)
		old_glint.queue_free()

	if _visual_root != null:
		for child in _visual_root.get_children():
			_visual_root.remove_child(child)
			child.queue_free()

	if is_briefcase_item(item_id):
		# Floor Briefcase uses BriefcaseContainer's unified hinged 3D BriefcaseVisualRig (zero double-mesh clipping!)
		if _visual_root != null:
			_visual_root.visible = false
		if _collision_shape != null:
			var b_shape := BoxShape3D.new()
			b_shape.size = Vector3(0.58, 0.16, 0.40)
			_collision_shape.shape = b_shape
			_collision_shape.position = Vector3(0.0, 0.08, 0.0)
		var b_glint := create_objective_glint_particles(false, item_id)
		b_glint.position = Vector3(0.0, 0.16, 0.0)
		add_child(b_glint)
		return

	if _visual_root != null:
		_visual_root.visible = true
		_visual_root.position = Vector3(0.0, get_item_floor_y(item_id), 0.0)
	if _collision_shape != null:
		var std_shape := BoxShape3D.new()
		std_shape.size = Vector3(0.45, 0.35, 0.45)
		_collision_shape.shape = std_shape
		_collision_shape.position = Vector3(0.0, 0.18, 0.0)

	var visual_node: Node3D = build_item_visual(item_id)
	visual_node.name = "ModelInstance"
	_visual_root.add_child(visual_node)
	if should_emit_pickup_glint(item_id):
		var glint := create_objective_glint_particles(false, item_id)
		glint.position = Vector3(0.0, maxf(get_item_floor_y(item_id) + 0.06, 0.14), 0.0)
		add_child(glint)
