class_name ItemIconCache
extends Node

## Renders 3D item prefabs (WorldItemPickup.build_item_visual) into cached 2D ImageTextures
## using an offscreen SubViewport with own_world_3d.

const PICKUP_SCRIPT = preload("res://entities/props/world_item_pickup.gd")
const ICON_SIZE: int = 128
const PREBAKE_IDS: Array[String] = [
	"KEY",
	"MONEY",
	"PASSPORT",
	"PLANS",
	"BRIEFCASE",
	"BUCKET",
	"TRIPWIRE",
	"SPRING",
	"BOMB",
	"LIVE_BOMB",
	"DART_GUN",
	"CLUB",
]

static var _cache: Dictionary = {} # String (UPPER) -> ImageTexture
static var _active_baker: ItemIconCache = null
static var _listeners: Array[Callable] = []

var _pending_ids: Array[String] = []
var _is_baking: bool = false


static func get_icon(item_id: String) -> Texture2D:
	var upper: String = item_id.to_upper()
	if upper.is_empty() or upper == "NONE":
		return null
	return _cache.get(upper, null) as Texture2D


static func ensure_prebaked(host: Node, on_icon_ready: Callable = Callable()) -> void:
	if on_icon_ready.is_valid() and not _listeners.has(on_icon_ready):
		_listeners.append(on_icon_ready)

	var missing: Array[String] = []
	for id in PREBAKE_IDS:
		if not _cache.has(id):
			missing.append(id)
	if missing.is_empty():
		return

	if is_instance_valid(_active_baker):
		for id in missing:
			if not _active_baker._pending_ids.has(id):
				_active_baker._pending_ids.append(id)
		return

	if host == null or not host.is_inside_tree():
		return

	var baker := ItemIconCache.new()
	baker.name = "ItemIconCacheBaker"
	baker._pending_ids = missing
	_active_baker = baker
	host.get_tree().root.add_child(baker)
	baker._start_baking()


func _start_baking() -> void:
	if _is_baking:
		return
	_is_baking = true
	call_deferred("_bake_queue_async")


func _bake_queue_async() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(ICON_SIZE, ICON_SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.96, 1.0)
	env.ambient_light_energy = 0.85

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	key_light.light_energy = 1.35
	vp.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(25.0, -140.0, 0.0)
	fill_light.light_color = Color(0.75, 0.85, 1.0)
	fill_light.light_energy = 0.55
	vp.add_child(fill_light)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(0.0, 0.0, 4.0)
	cam.near = 0.05
	cam.far = 20.0
	vp.add_child(cam)

	var stage := Node3D.new()
	vp.add_child(stage)

	while not _pending_ids.is_empty():
		var item_id: String = _pending_ids.pop_front()
		if _cache.has(item_id):
			continue

		for child in stage.get_children():
			stage.remove_child(child)
			child.queue_free()

		var pivot := Node3D.new()
		stage.add_child(pivot)

		var visual: Node3D = PICKUP_SCRIPT.build_item_visual(item_id)
		if visual == null:
			continue
		pivot.add_child(visual)

		# Orient each item for a crisp icon silhouette.
		if item_id in ["KEY", "PASSPORT", "PLANS"]:
			var raw_aabb: AABB = _compute_world_aabb(stage)
			var face_basis: Basis = _basis_facing_thin_axis(raw_aabb)
			var tilt := Vector3(deg_to_rad(12.0), deg_to_rad(-16.0), deg_to_rad(-32.0 if item_id == "KEY" else 8.0))
			pivot.transform.basis = Basis.from_euler(tilt) * face_basis
		elif item_id == "CLUB":
			pivot.rotation_degrees = Vector3(16.0, -28.0, -32.0)
		else:
			pivot.rotation_degrees = Vector3(24.0, -34.0, 0.0)

		var aabb: AABB = _compute_world_aabb(stage)
		if aabb.size.length_squared() > 0.00001:
			pivot.position -= aabb.get_center()
		var max_dim: float = maxf(aabb.size.x, aabb.size.y)
		cam.position = Vector3(0.0, 0.0, 4.0)
		cam.size = maxf(max_dim * 1.18, 0.02)

		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			break
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			break

		var img: Image = vp.get_texture().get_image()
		for _zoom_pass in range(2):
			if img == null or img.is_empty():
				break
			var used: Rect2i = img.get_used_rect()
			var max_px: int = maxi(used.size.x, used.size.y)
			if max_px <= 1 or max_px >= int(ICON_SIZE * 0.65):
				break
			var uv_offset: Vector2 = (Vector2(used.get_center()) / float(ICON_SIZE)) - Vector2(0.5, 0.5)
			cam.position.x += uv_offset.x * cam.size
			cam.position.y -= uv_offset.y * cam.size
			cam.size *= float(max_px) / (float(ICON_SIZE) * 0.62)
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			if not is_inside_tree():
				break
			await RenderingServer.frame_post_draw
			if not is_inside_tree():
				break
			img = vp.get_texture().get_image()

		# If zooming in clipped any edge (e.g., key ring/teeth outside frame), zoom back out until unclipped.
		for _out_pass in range(4):
			if img == null or img.is_empty():
				break
			var used: Rect2i = img.get_used_rect()
			var touches_edge: bool = (
				used.position.x <= 1
				or used.position.y <= 1
				or used.end.x >= ICON_SIZE - 1
				or used.end.y >= ICON_SIZE - 1
			)
			if not touches_edge:
				break
			cam.size *= 1.6
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			if not is_inside_tree():
				break
			await RenderingServer.frame_post_draw
			if not is_inside_tree():
				break
			img = vp.get_texture().get_image()

		if img != null and not img.is_empty():
			img = _center_crop_with_padding(img, 0.12)
			var tex := ImageTexture.create_from_image(img)
			_cache[item_id] = tex
			_notify_listeners(item_id)

	if is_instance_valid(vp):
		vp.queue_free()
	_is_baking = false
	if _active_baker == self:
		_active_baker = null
	queue_free()


static func _basis_facing_thin_axis(aabb: AABB) -> Basis:
	var sizes: Array[float] = [aabb.size.x, aabb.size.y, aabb.size.z]
	var axes: Array[int] = [0, 1, 2]
	axes.sort_custom(func(a: int, b: int) -> bool: return sizes[a] < sizes[b])
	var thin_idx: int = axes[0]
	var wide_idx: int = axes[1]
	var long_idx: int = axes[2]

	var basis_vecs: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var v_wide: Vector3 = basis_vecs[wide_idx]
	var v_long: Vector3 = basis_vecs[long_idx]
	var v_thin: Vector3 = basis_vecs[thin_idx]

	var from_basis := Basis(v_wide, v_long, v_thin)
	if from_basis.determinant() < 0.0:
		from_basis = Basis(-v_wide, v_long, v_thin)
	return from_basis.inverse()


static func _center_crop_with_padding(img: Image, pad_ratio: float) -> Image:
	var used: Rect2i = img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return img
	var cropped: Image = img.get_region(used)
	var max_side: int = maxi(used.size.x, used.size.y)
	var pad: int = int(ceil(float(max_side) * pad_ratio))
	var out_side: int = max_side + pad * 2
	var out := Image.create(out_side, out_side, false, img.get_format())
	out.fill(Color(0, 0, 0, 0))
	var dst := Vector2i((out_side - used.size.x) / 2, (out_side - used.size.y) / 2)
	out.blit_rect(cropped, Rect2i(Vector2i.ZERO, used.size), dst)
	return out


static func _notify_listeners(item_id: String) -> void:
	var alive: Array[Callable] = []
	for cb in _listeners:
		if cb.is_valid():
			alive.append(cb)
			cb.call(item_id)
	_listeners = alive


static func _compute_world_aabb(root: Node3D) -> AABB:
	var has_bounds := false
	var combined := AABB()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var xform: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
			for s in range(mi.mesh.get_surface_count()):
				var arrays: Array = mi.mesh.surface_get_arrays(s)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in verts:
					var wv: Vector3 = xform * v
					if not has_bounds:
						combined = AABB(wv, Vector3.ZERO)
						has_bounds = true
					else:
						combined = combined.expand(wv)
	if not has_bounds:
		return AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))
	return combined
