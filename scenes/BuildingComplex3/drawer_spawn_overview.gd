@tool
class_name DrawerSpawnOverview
extends Node3D

## Editor-only overview & overlap-audit tool for MatchDrawerSpawnPoints.
## Uses the exact bounding boxes of SearchableDrawer (2.32 x 1.14 x 0.88m) and
## SearchableDrawerSmall (0.76 x 1.06 x 0.75m) plus a +Z tray-open clearance indicator
## so you can spot clipping against walls/furniture and jump to any marker in 1 click.
## Does nothing at runtime.

const BIG_DRAWER_SIZE := Vector3(2.32, 1.14, 0.88)
const BIG_DRAWER_OFFSET := Vector3(-0.005, 0.57, 0.03)
const SMALL_DRAWER_SIZE := Vector3(0.76, 1.06, 0.75)
const SMALL_DRAWER_OFFSET := Vector3(0.0, 0.53, 0.01)
const TRAY_CLEARANCE_SIZE := Vector3(0.70, 0.30, 0.48)
const TRAY_CLEARANCE_OFFSET := Vector3(0.0, 0.78, 0.68)

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

@export var show_tray_clearance: bool = true:
	set(value):
		show_tray_clearance = value
		if Engine.is_editor_hint() and is_inside_tree():
			_rebuild_overlays()

@export_range(0.1, 5.0, 0.1) var auto_refresh_seconds: float = 0.6
@export var confirm_delete_clipping: bool = false

@export_tool_button("Refresh & Audit Overlaps", "Search") var refresh_action: Callable = _on_refresh_pressed
@export_tool_button("Select Next Clipping", "ArrowRight") var next_clip_action: Callable = _on_select_next_clipping
@export_tool_button("Select Prev Clipping", "ArrowLeft") var prev_clip_action: Callable = _on_select_prev_clipping
@export_tool_button("Select Next Spawnpoint", "Forward") var next_any_action: Callable = _on_select_next_any
@export_tool_button("Toggle Selected Small <-> Big", "Loop") var toggle_size_action: Callable = _on_toggle_selected_size
@export_tool_button("Print Room Overview", "FileList") var overview_action: Callable = _print_room_overview
@export_tool_button("Delete Clipping (Needs Confirm)", "Remove") var delete_clipping_action: Callable = _on_delete_clipping_pressed

var _overlay_root: Node3D = null
var _refresh_accum: float = 0.0
var _last_audit_results: Array[Dictionary] = []
var _clip_cursor: int = -1
var _any_cursor: int = -1
var _last_selected_marker: Marker3D = null

var _mat_ok_big: StandardMaterial3D = null
var _mat_ok_small: StandardMaterial3D = null
var _mat_clip: StandardMaterial3D = null
var _mat_tray: StandardMaterial3D = null
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
	if not toggle_size_action.is_valid():
		toggle_size_action = _on_toggle_selected_size
	if not overview_action.is_valid():
		overview_action = _print_room_overview
	if not delete_clipping_action.is_valid():
		delete_clipping_action = _on_delete_clipping_pressed


func _ensure_materials() -> void:
	if _mat_ok_big == null:
		_mat_ok_big = StandardMaterial3D.new()
		_mat_ok_big.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_ok_big.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_ok_big.albedo_color = Color(0.20, 0.85, 0.45, 0.38)
	if _mat_ok_small == null:
		_mat_ok_small = StandardMaterial3D.new()
		_mat_ok_small.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_ok_small.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_ok_small.albedo_color = Color(0.25, 0.72, 1.0, 0.40)
	if _mat_clip == null:
		_mat_clip = StandardMaterial3D.new()
		_mat_clip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_clip.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_clip.albedo_color = Color(1.0, 0.18, 0.18, 0.62)
		_mat_clip.no_depth_test = true
	if _mat_tray == null:
		_mat_tray = StandardMaterial3D.new()
		_mat_tray.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_tray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_tray.albedo_color = Color(1.0, 0.85, 0.25, 0.35)
	if _mat_beacon_ok == null:
		_mat_beacon_ok = StandardMaterial3D.new()
		_mat_beacon_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_beacon_ok.albedo_color = Color(0.25, 0.92, 0.55, 1.0)
	if _mat_beacon_clip == null:
		_mat_beacon_clip = StandardMaterial3D.new()
		_mat_beacon_clip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_beacon_clip.albedo_color = Color(1.0, 0.22, 0.22, 1.0)
		_mat_beacon_clip.no_depth_test = true


func _ensure_overlay_root() -> Node3D:
	if _overlay_root != null and is_instance_valid(_overlay_root):
		return _overlay_root
	var existing := get_node_or_null("_EditorDrawerOverlayRoot") as Node3D
	if existing != null:
		_overlay_root = existing
		return _overlay_root
	_overlay_root = Node3D.new()
	_overlay_root.name = "_EditorDrawerOverlayRoot"
	add_child(_overlay_root)
	return _overlay_root


func _is_small_only(marker: Marker3D) -> bool:
	return String(marker.name).begins_with("SmallDrawerSpawn") or str(marker.get_meta("drawer_size", "")) == "small"


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
			var pts := room.get_node_or_null("MatchDrawerSpawnPoints")
			if pts == null:
				continue
			for child in pts.get_children():
				if child is Marker3D:
					var m := child as Marker3D
					entries.append({
						"marker": m,
						"room_label": floor_prefix + String(room.name),
						"marker_name": String(m.name),
						"is_small": _is_small_only(m)
					})
	return entries


func _check_marker_overlap(marker: Marker3D, is_small: bool) -> String:
	var w3d := get_world_3d()
	if w3d == null:
		return ""
	var space := w3d.direct_space_state
	if space == null:
		return ""

	var raw_size: Vector3 = SMALL_DRAWER_SIZE if is_small else BIG_DRAWER_SIZE
	var raw_offset: Vector3 = SMALL_DRAWER_OFFSET if is_small else BIG_DRAWER_OFFSET
	# Inset slightly and lift bottom +0.05m so the floor itself is not flagged.
	var shape := BoxShape3D.new()
	shape.size = Vector3(raw_size.x - 0.04, raw_size.y - 0.06, raw_size.z - 0.04)
	var local_center := raw_offset + Vector3(0.0, 0.03, 0.0)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = marker.global_transform * Transform3D(Basis.IDENTITY, local_center)
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
	var big_box := BoxMesh.new()
	big_box.size = BIG_DRAWER_SIZE
	var small_box := BoxMesh.new()
	small_box.size = SMALL_DRAWER_SIZE
	var tray_box := BoxMesh.new()
	tray_box.size = TRAY_CLEARANCE_SIZE

	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.015
	beacon_mesh.bottom_radius = 0.015
	beacon_mesh.height = 1.4
	beacon_mesh.radial_segments = 6

	for entry in entries:
		var marker: Marker3D = entry["marker"] as Marker3D
		if marker == null or not is_instance_valid(marker) or not marker.is_inside_tree():
			continue
		var is_small: bool = bool(entry["is_small"])
		var hit_desc := _check_marker_overlap(marker, is_small)
		var is_clipping: bool = not hit_desc.is_empty()
		var rec := {
			"room": entry["room_label"],
			"name": entry["marker_name"],
			"pos": marker.position,
			"is_small": is_small,
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
		body.mesh = small_box if is_small else big_box
		body.position = SMALL_DRAWER_OFFSET if is_small else BIG_DRAWER_OFFSET
		if is_clipping:
			body.material_override = _mat_clip
		else:
			body.material_override = _mat_ok_small if is_small else _mat_ok_big
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.add_child(body)

		if show_tray_clearance:
			var tray := MeshInstance3D.new()
			tray.mesh = tray_box
			tray.position = TRAY_CLEARANCE_OFFSET
			tray.material_override = _mat_tray
			tray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gizmo.add_child(tray)

		var beacon := MeshInstance3D.new()
		beacon.mesh = beacon_mesh
		beacon.position = Vector3(0.0, 1.50, 0.0)
		beacon.material_override = _mat_beacon_clip if is_clipping else _mat_beacon_ok
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.add_child(beacon)

		if show_labels:
			var lbl := Label3D.new()
			var size_tag: String = "[SMALL]" if is_small else "[BIG/SMALL]"
			var tag: String = "%s\n%s %s" % [str(entry["room_label"]), str(entry["marker_name"]), size_tag]
			if is_clipping:
				tag += "\n[CLIP: %s]" % hit_desc
			lbl.text = tag
			lbl.position = Vector3(0.0, 2.35, 0.0)
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.pixel_size = 0.0055
			lbl.outline_size = 6
			if is_clipping:
				lbl.modulate = Color(1.0, 0.35, 0.35)
			elif is_small:
				lbl.modulate = Color(0.55, 0.85, 1.0)
			else:
				lbl.modulate = Color(0.55, 1.0, 0.65)
			gizmo.add_child(lbl)


func _on_refresh_pressed() -> void:
	_rebuild_overlays()
	var clip_count: int = 0
	for r in _last_audit_results:
		if bool(r["clipping"]):
			clip_count += 1
	print("[DrawerSpawnOverview] Total drawer spawnpoints: %d | Clipping: %d" % [_last_audit_results.size(), clip_count])
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
	print("[DrawerSpawnOverview] === Room Overview (%d total drawer spawnpoints) ===" % _last_audit_results.size())
	for rk in keys:
		var items: Array = by_room[rk]
		var parts: Array[String] = []
		for it in items:
			var flag: String = " [CLIP]" if bool(it["clipping"]) else ""
			parts.append("%s%s %s" % [it["name"], flag, str(it["pos"])])
		print("  %s (%d): %s" % [rk, items.size(), " | ".join(parts)])


func _on_delete_clipping_pressed() -> void:
	if not confirm_delete_clipping:
		push_warning("[DrawerSpawnOverview] Check 'confirm_delete_clipping' first before deleting clipping spawnpoints.")
		return
	_rebuild_overlays()
	var deleted: int = 0
	for r in _last_audit_results:
		if bool(r["clipping"]):
			var m: Marker3D = r["marker"] as Marker3D
			if m != null and is_instance_valid(m):
				m.queue_free()
				deleted += 1
	confirm_delete_clipping = false
	print("[DrawerSpawnOverview] Deleted %d clipping drawer spawnpoints. Save the scene to persist." % deleted)
	call_deferred("_rebuild_overlays")


func _select_marker_in_editor(marker: Marker3D, label_text: String) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	_last_selected_marker = marker
	if Engine.has_singleton(&"EditorInterface"):
		var ei: Object = Engine.get_singleton(&"EditorInterface")
		var sel: Object = ei.call("get_selection")
		if sel != null:
			sel.call("clear")
			sel.call("add_node", marker)
	print("[DrawerSpawnOverview] Selected %s (press F in 3D view to focus, W to move, E to rotate)" % label_text)


func _on_select_next_clipping() -> void:
	_rebuild_overlays()
	var clipping: Array[Dictionary] = []
	for r in _last_audit_results:
		if bool(r["clipping"]):
			clipping.append(r)
	if clipping.is_empty():
		print("[DrawerSpawnOverview] No clipping drawer spawnpoints found!")
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
		print("[DrawerSpawnOverview] No clipping drawer spawnpoints found!")
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


func _next_unique_marker_name(parent: Node, prefix: String) -> String:
	var idx: int = 1
	while parent.get_node_or_null("%s_%d" % [prefix, idx]) != null:
		idx += 1
	return "%s_%d" % [prefix, idx]


func toggle_marker_size(marker: Marker3D) -> bool:
	if marker == null or not is_instance_valid(marker) or marker.get_parent() == null:
		return false
	var parent: Node = marker.get_parent()
	var was_small: bool = _is_small_only(marker)
	if was_small:
		if marker.has_meta("drawer_size"):
			marker.remove_meta("drawer_size")
		if String(marker.name).begins_with("SmallDrawerSpawn"):
			var candidate: String = String(marker.name).replace("SmallDrawerSpawn", "DrawerSpawn")
			if parent.get_node_or_null(candidate) != null:
				candidate = _next_unique_marker_name(parent, "DrawerSpawn")
			marker.name = candidate
		print("[DrawerSpawnOverview] Changed %s to BIG/SMALL-capable (green)" % marker.name)
	else:
		marker.set_meta("drawer_size", "small")
		if String(marker.name).begins_with("DrawerSpawn"):
			var candidate: String = String(marker.name).replace("DrawerSpawn", "SmallDrawerSpawn")
			if parent.get_node_or_null(candidate) != null:
				candidate = _next_unique_marker_name(parent, "SmallDrawerSpawn")
			marker.name = candidate
		print("[DrawerSpawnOverview] Changed %s to SMALL-ONLY (blue)" % marker.name)
	_rebuild_overlays()
	return true


func _on_toggle_selected_size() -> void:
	var target: Marker3D = null
	if Engine.has_singleton(&"EditorInterface"):
		var ei: Object = Engine.get_singleton(&"EditorInterface")
		var sel: Object = ei.call("get_selection")
		if sel != null:
			var nodes: Array = sel.call("get_selected_nodes")
			for n in nodes:
				if n is Marker3D and (n as Node).get_parent() != null and (n as Node).get_parent().name == &"MatchDrawerSpawnPoints":
					target = n as Marker3D
					break
	if target == null and _last_selected_marker != null and is_instance_valid(_last_selected_marker):
		target = _last_selected_marker
	if target == null:
		push_warning("[DrawerSpawnOverview] Select a DrawerSpawn/SmallDrawerSpawn Marker3D (or use Select Next) first.")
		return
	toggle_marker_size(target)
