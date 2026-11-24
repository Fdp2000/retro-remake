@tool
class_name PlayerSpawnOverview
extends Node3D

## Editor-only overview & overlap-audit tool for MatchPlayerSpawnPoints.
## Draws the player capsule & bounding box, forward facing indicator, vertical beacon,
## and floating Room/Marker labels in the Godot editor viewport.
## Does nothing at runtime.

const PLAYER_CAPSULE_RADIUS: float = 0.4
const PLAYER_CAPSULE_HEIGHT: float = 1.8
const PLAYER_BOUNDS_SIZE := Vector3(0.8, 1.8, 0.8)
const PLAYER_BOUNDS_OFFSET := Vector3(0.0, 0.9, 0.0)
const PLAYER_EYE_Y: float = 1.6

@export var enabled: bool = true:
	set(value):
		enabled = value
		if Engine.is_editor_hint() and is_inside_tree():
			_rebuild_overlays()

@export var show_labels: bool = true:
	set(value):
		show_labels = value
		if Engine.is_editor_hint() and is_inside_tree():
			_rebuild_overlays()

@export var show_only_clipping: bool = false:
	set(value):
		show_only_clipping = value
		if Engine.is_editor_hint() and is_inside_tree():
			_rebuild_overlays()

@export_range(0.1, 5.0, 0.1) var auto_refresh_seconds: float = 0.6

@export_tool_button("Refresh & Audit Overlaps", "Search") var refresh_action: Callable = _on_refresh_pressed
@export_tool_button("Select Next Clipping", "ArrowRight") var next_clip_action: Callable = _on_select_next_clipping
@export_tool_button("Select Prev Clipping", "ArrowLeft") var prev_clip_action: Callable = _on_select_prev_clipping
@export_tool_button("Select Next Spawnpoint", "Forward") var next_any_action: Callable = _on_select_next_any
@export_tool_button("Print Room Overview", "FileList") var overview_action: Callable = _print_room_overview

var _overlay_root: Node3D = null
var _refresh_accum: float = 0.0
var _last_audit_results: Array[Dictionary] = []
var _clip_cursor: int = -1
var _any_cursor: int = -1

var _mat_ok: StandardMaterial3D = null
var _mat_clip: StandardMaterial3D = null
var _mat_wire_ok: StandardMaterial3D = null
var _mat_wire_clip: StandardMaterial3D = null
var _mat_dir: StandardMaterial3D = null
var _mat_beacon_ok: StandardMaterial3D = null
var _mat_beacon_clip: StandardMaterial3D = null


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_tool_callables()
	_ensure_materials()
	_rebuild_overlays()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_tool_callables()
	if not enabled:
		return
	_refresh_accum += delta
	if _refresh_accum >= auto_refresh_seconds:
		_refresh_accum = 0.0
		_rebuild_overlays()


func _ensure_tool_callables() -> void:
	if not refresh_action.is_valid():
		refresh_action = _on_refresh_pressed
	if not next_clip_action.is_valid():
		next_clip_action = _on_select_next_clipping
	if not prev_clip_action.is_valid():
		prev_clip_action = _on_select_prev_clipping
	if not next_any_action.is_valid():
		next_any_action = _on_select_next_any
	if not overview_action.is_valid():
		overview_action = _print_room_overview


func _ensure_materials() -> void:
	if _mat_ok == null:
		_mat_ok = StandardMaterial3D.new()
		_mat_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_ok.albedo_color = Color(0.20, 0.88, 0.95, 0.35)
		_mat_ok.no_depth_test = false
	if _mat_clip == null:
		_mat_clip = StandardMaterial3D.new()
		_mat_clip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_clip.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_clip.albedo_color = Color(1.0, 0.18, 0.18, 0.65)
		_mat_clip.no_depth_test = true
	if _mat_wire_ok == null:
		_mat_wire_ok = StandardMaterial3D.new()
		_mat_wire_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_wire_ok.albedo_color = Color(0.30, 0.95, 1.0, 1.0)
	if _mat_wire_clip == null:
		_mat_wire_clip = StandardMaterial3D.new()
		_mat_wire_clip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_wire_clip.albedo_color = Color(1.0, 0.25, 0.25, 1.0)
		_mat_wire_clip.no_depth_test = true
	if _mat_dir == null:
		_mat_dir = StandardMaterial3D.new()
		_mat_dir.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_dir.albedo_color = Color(1.0, 0.90, 0.20, 1.0)
	if _mat_beacon_ok == null:
		_mat_beacon_ok = StandardMaterial3D.new()
		_mat_beacon_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_beacon_ok.albedo_color = Color(0.30, 0.95, 1.0, 1.0)
	if _mat_beacon_clip == null:
		_mat_beacon_clip = StandardMaterial3D.new()
		_mat_beacon_clip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_beacon_clip.albedo_color = Color(1.0, 0.22, 0.22, 1.0)
		_mat_beacon_clip.no_depth_test = true


func _ensure_overlay_root() -> Node3D:
	if _overlay_root != null and is_instance_valid(_overlay_root):
		return _overlay_root
	var existing := get_node_or_null("_EditorPlayerOverlayRoot") as Node3D
	if existing != null:
		_overlay_root = existing
		return _overlay_root
	_overlay_root = Node3D.new()
	_overlay_root.name = "_EditorPlayerOverlayRoot"
	add_child(_overlay_root)
	# Do NOT set owner so temporary editor gizmos are never saved into the .tscn file.
	return _overlay_root


func _collect_spawn_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var building := get_parent()
	if building == null:
		return entries
	if building.name == &"SecondFloor" and building.get_parent() != null and building.get_parent().name == &"BuildingComplex3":
		return entries

	var room_containers: Array[Node] = []
	var ground_rooms := building.get_node_or_null("Rooms")
	if ground_rooms != null:
		room_containers.append(ground_rooms)
	var upper_rooms := building.get_node_or_null("SecondFloor/Rooms")
	if upper_rooms != null:
		room_containers.append(upper_rooms)

	for rc in room_containers:
		var floor_prefix: String = "Upper/" if rc.get_parent().name == &"SecondFloor" else "Ground/"
		for room in rc.get_children():
			var pts := room.get_node_or_null("MatchPlayerSpawnPoints")
			if pts == null:
				continue
			for child in pts.get_children():
				if child is Marker3D:
					entries.append({
						"marker": child as Marker3D,
						"room_label": floor_prefix + String(room.name),
						"marker_name": String(child.name)
					})
	return entries


func _check_marker_overlap(marker: Marker3D) -> String:
	var w3d := get_world_3d()
	if w3d == null:
		return ""
	var space := w3d.direct_space_state
	if space == null:
		return ""
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.72
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# Lift slightly (0.93 vs 0.90) so the floor surface at y = 0 is not flagged as clipping.
	query.transform = marker.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.93, 0.0))
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hits := space.intersect_shape(query, 4)
	if hits.is_empty():
		return ""
	var hit_names: Array[String] = []
	for h in hits:
		var col: Object = h.get("collider")
		if col is Node:
			hit_names.append(String((col as Node).name))
	return ", ".join(hit_names)


func _build_wireframe_box_mesh(size: Vector3) -> ImmediateMesh:
	var half := size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, half.z),
		Vector3(-half.x, -half.y, half.z),
		Vector3(-half.x, half.y, -half.z),
		Vector3(half.x, half.y, -half.z),
		Vector3(half.x, half.y, half.z),
		Vector3(-half.x, half.y, half.z)
	]
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)
	]
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for e in edges:
		im.surface_add_vertex(corners[e.x])
		im.surface_add_vertex(corners[e.y])
	im.surface_end()
	return im


func _rebuild_overlays() -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_materials()
	var root_node := _ensure_overlay_root()
	for c in root_node.get_children():
		root_node.remove_child(c)
		c.queue_free()

	_last_audit_results.clear()
	if not enabled:
		return

	var entries := _collect_spawn_entries()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = PLAYER_CAPSULE_RADIUS
	capsule_mesh.height = PLAYER_CAPSULE_HEIGHT
	capsule_mesh.radial_segments = 16
	capsule_mesh.rings = 4

	var wire_box_mesh := _build_wireframe_box_mesh(PLAYER_BOUNDS_SIZE)

	var dir_shaft_mesh := CylinderMesh.new()
	dir_shaft_mesh.top_radius = 0.025
	dir_shaft_mesh.bottom_radius = 0.025
	dir_shaft_mesh.height = 0.65
	dir_shaft_mesh.radial_segments = 8

	var dir_tip_mesh := CylinderMesh.new()
	dir_tip_mesh.top_radius = 0.0
	dir_tip_mesh.bottom_radius = 0.08
	dir_tip_mesh.height = 0.22
	dir_tip_mesh.radial_segments = 8

	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.015
	beacon_mesh.bottom_radius = 0.015
	beacon_mesh.height = 0.9
	beacon_mesh.radial_segments = 6

	for entry in entries:
		var marker: Marker3D = entry["marker"] as Marker3D
		if marker == null or not is_instance_valid(marker) or not marker.is_inside_tree():
			continue
		var hit_desc := _check_marker_overlap(marker)
		var is_clipping: bool = not hit_desc.is_empty()
		var rec := {
			"room": entry["room_label"],
			"name": entry["marker_name"],
			"pos": marker.position,
			"clipping": is_clipping,
			"hit": hit_desc,
			"marker": marker
		}
		_last_audit_results.append(rec)

		if show_only_clipping and not is_clipping:
			continue

		var gizmo := Node3D.new()
		gizmo.name = "%s_%s" % [str(entry["room_label"]).replace("/", "_"), str(entry["marker_name"])]
		root_node.add_child(gizmo)
		gizmo.global_transform = marker.global_transform

		var body := MeshInstance3D.new()
		body.mesh = capsule_mesh
		body.position = PLAYER_BOUNDS_OFFSET
		body.material_override = _mat_clip if is_clipping else _mat_ok
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.add_child(body)

		var bounds_wire := MeshInstance3D.new()
		bounds_wire.mesh = wire_box_mesh
		bounds_wire.position = PLAYER_BOUNDS_OFFSET
		bounds_wire.material_override = _mat_wire_clip if is_clipping else _mat_wire_ok
		bounds_wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.add_child(bounds_wire)

		# Forward facing indicator at eye level pointing along local -Z
		var dir_shaft := MeshInstance3D.new()
		dir_shaft.mesh = dir_shaft_mesh
		dir_shaft.position = Vector3(0.0, PLAYER_EYE_Y, -0.325)
		dir_shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		dir_shaft.material_override = _mat_dir
		dir_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.add_child(dir_shaft)

		var dir_tip := MeshInstance3D.new()
		dir_tip.mesh = dir_tip_mesh
		dir_tip.position = Vector3(0.0, PLAYER_EYE_Y, -0.74)
		dir_tip.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		dir_tip.material_override = _mat_dir
		dir_tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.add_child(dir_tip)

		var beacon := MeshInstance3D.new()
		beacon.mesh = beacon_mesh
		beacon.position = Vector3(0.0, 2.25, 0.0)
		beacon.material_override = _mat_beacon_clip if is_clipping else _mat_beacon_ok
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.add_child(beacon)

		if show_labels:
			var lbl := Label3D.new()
			var tag: String = "%s\n%s" % [str(entry["room_label"]), str(entry["marker_name"])]
			if is_clipping:
				tag += "\n[CLIP: %s]" % hit_desc
			lbl.text = tag
			lbl.position = Vector3(0.0, 2.85, 0.0)
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.pixel_size = 0.0055
			lbl.outline_size = 6
			lbl.modulate = Color(1.0, 0.35, 0.35) if is_clipping else Color(0.55, 0.95, 1.0)
			gizmo.add_child(lbl)


func _on_refresh_pressed() -> void:
	_rebuild_overlays()
	var clip_count: int = 0
	for r in _last_audit_results:
		if bool(r["clipping"]):
			clip_count += 1
	print("[PlayerSpawnOverview] Total player spawnpoints: %d | Clipping: %d" % [_last_audit_results.size(), clip_count])
	for r in _last_audit_results:
		if bool(r["clipping"]):
			print("  CLIPPING -> %s/%s at %s (hits: %s)" % [r["room"], r["name"], str(r["pos"]), r["hit"]])


func _print_room_overview() -> void:
	_rebuild_overlays()
	var by_room: Dictionary = {}
	for r in _last_audit_results:
		var rk: String = str(r["room"])
		if not by_room.has(rk):
			by_room[rk] = []
		(by_room[rk] as Array).append(r)
	var keys := by_room.keys()
	keys.sort()
	print("[PlayerSpawnOverview] === Room Overview (%d total player spawnpoints) ===" % _last_audit_results.size())
	for rk in keys:
		var items: Array = by_room[rk]
		var parts: Array[String] = []
		for it in items:
			var flag: String = " [CLIP]" if bool(it["clipping"]) else ""
			parts.append("%s%s %s" % [it["name"], flag, str(it["pos"])])
		print("  %s (%d): %s" % [rk, items.size(), " | ".join(parts)])


func _select_marker_in_editor(marker: Marker3D, label_text: String) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	if Engine.has_singleton(&"EditorInterface"):
		var ei: Object = Engine.get_singleton(&"EditorInterface")
		var sel: Object = ei.call("get_selection")
		if sel != null:
			sel.call("clear")
			sel.call("add_node", marker)
	print("[PlayerSpawnOverview] Selected %s (press F in 3D view to focus, W to move, E to rotate)" % label_text)


func _on_select_next_clipping() -> void:
	_rebuild_overlays()
	var clipping: Array[Dictionary] = []
	for r in _last_audit_results:
		if bool(r["clipping"]):
			clipping.append(r)
	if clipping.is_empty():
		print("[PlayerSpawnOverview] No clipping player spawnpoints found!")
		return
	_clip_cursor = (_clip_cursor + 1) % clipping.size()
	var rec: Dictionary = clipping[_clip_cursor]
	_select_marker_in_editor(rec["marker"] as Marker3D, "%s/%s (%d/%d clipping)" % [rec["room"], rec["name"], _clip_cursor + 1, clipping.size()])


func _on_select_prev_clipping() -> void:
	_rebuild_overlays()
	var clipping: Array[Dictionary] = []
	for r in _last_audit_results:
		if bool(r["clipping"]):
			clipping.append(r)
	if clipping.is_empty():
		print("[PlayerSpawnOverview] No clipping player spawnpoints found!")
		return
	_clip_cursor = (_clip_cursor - 1 + clipping.size()) % clipping.size()
	var rec: Dictionary = clipping[_clip_cursor]
	_select_marker_in_editor(rec["marker"] as Marker3D, "%s/%s (%d/%d clipping)" % [rec["room"], rec["name"], _clip_cursor + 1, clipping.size()])


func _on_select_next_any() -> void:
	_rebuild_overlays()
	if _last_audit_results.is_empty():
		return
	_any_cursor = (_any_cursor + 1) % _last_audit_results.size()
	var rec: Dictionary = _last_audit_results[_any_cursor]
	_select_marker_in_editor(rec["marker"] as Marker3D, "%s/%s (%d/%d)" % [rec["room"], rec["name"], _any_cursor + 1, _last_audit_results.size()])
