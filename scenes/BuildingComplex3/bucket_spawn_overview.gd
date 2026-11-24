@tool
class_name BucketSpawnOverview
extends Node3D

## Editor-only overview & overlap-audit tool for MatchBucketSpawnPoints.
## Renders color-coded 3D pickup footprints, vertical beacons, and floating Room/Marker labels
## in the Godot editor viewport so you can quickly inspect and tweak spawnpoints.
## Does nothing at runtime.

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
@export var confirm_delete_clipping: bool = false

@export_tool_button("Refresh & Audit Overlaps", "Search") var refresh_action: Callable = _on_refresh_pressed
@export_tool_button("Select Next Clipping", "ArrowRight") var next_clip_action: Callable = _on_select_next_clipping
@export_tool_button("Select Prev Clipping", "ArrowLeft") var prev_clip_action: Callable = _on_select_prev_clipping
@export_tool_button("Select Next Spawnpoint", "Forward") var next_any_action: Callable = _on_select_next_any
@export_tool_button("Print Room Overview", "FileList") var overview_action: Callable = _print_room_overview
@export_tool_button("Delete Clipping (Needs Confirm)", "Remove") var delete_clipping_action: Callable = _on_delete_clipping_pressed

var _overlay_root: Node3D = null
var _refresh_accum: float = 0.0
var _last_audit_results: Array[Dictionary] = []
var _clip_cursor: int = -1
var _any_cursor: int = -1

var _mat_ok: StandardMaterial3D = null
var _mat_clip: StandardMaterial3D = null
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
	if not delete_clipping_action.is_valid():
		delete_clipping_action = _on_delete_clipping_pressed


func _ensure_materials() -> void:
	if _mat_ok == null:
		_mat_ok = StandardMaterial3D.new()
		_mat_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_ok.albedo_color = Color(0.20, 0.92, 0.42, 0.55)
		_mat_ok.no_depth_test = false
	if _mat_clip == null:
		_mat_clip = StandardMaterial3D.new()
		_mat_clip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_clip.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_clip.albedo_color = Color(1.0, 0.18, 0.18, 0.78)
		_mat_clip.no_depth_test = true
	if _mat_beacon_ok == null:
		_mat_beacon_ok = StandardMaterial3D.new()
		_mat_beacon_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_beacon_ok.albedo_color = Color(0.25, 0.95, 0.50, 1.0)
	if _mat_beacon_clip == null:
		_mat_beacon_clip = StandardMaterial3D.new()
		_mat_beacon_clip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_beacon_clip.albedo_color = Color(1.0, 0.22, 0.22, 1.0)
		_mat_beacon_clip.no_depth_test = true


func _ensure_overlay_root() -> Node3D:
	if _overlay_root != null and is_instance_valid(_overlay_root):
		return _overlay_root
	var existing := get_node_or_null("_EditorOverlayRoot") as Node3D
	if existing != null:
		_overlay_root = existing
		return _overlay_root
	_overlay_root = Node3D.new()
	_overlay_root.name = "_EditorOverlayRoot"
	add_child(_overlay_root)
	# Do NOT set owner so the temporary editor gizmos are never saved into the .tscn file.
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
			var pts := room.get_node_or_null("MatchBucketSpawnPoints")
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
	var shape := CylinderShape3D.new()
	shape.radius = 0.18
	shape.height = 0.28
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# Offset upward by 0.19m so the resting surface (table/desk/floor at y=0) is not flagged.
	query.transform = Transform3D(Basis.IDENTITY, marker.global_position + Vector3(0.0, 0.19, 0.0))
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
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = 0.20
	cyl_mesh.bottom_radius = 0.20
	cyl_mesh.height = 0.32
	cyl_mesh.radial_segments = 12

	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.015
	beacon_mesh.bottom_radius = 0.015
	beacon_mesh.height = 1.6
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
		gizmo.global_position = marker.global_position

		var body := MeshInstance3D.new()
		body.mesh = cyl_mesh
		body.position = Vector3(0.0, 0.16, 0.0)
		body.material_override = _mat_clip if is_clipping else _mat_ok
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.add_child(body)

		var beacon := MeshInstance3D.new()
		beacon.mesh = beacon_mesh
		beacon.position = Vector3(0.0, 0.80, 0.0)
		beacon.material_override = _mat_beacon_clip if is_clipping else _mat_beacon_ok
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gizmo.add_child(beacon)

		if show_labels:
			var lbl := Label3D.new()
			var tag: String = "%s\n%s" % [str(entry["room_label"]), str(entry["marker_name"])]
			if is_clipping:
				tag += "\n[CLIP: %s]" % hit_desc
			lbl.text = tag
			lbl.position = Vector3(0.0, 1.75, 0.0)
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.pixel_size = 0.0055
			lbl.outline_size = 6
			lbl.modulate = Color(1.0, 0.35, 0.35) if is_clipping else Color(0.55, 1.0, 0.65)
			gizmo.add_child(lbl)


func _on_refresh_pressed() -> void:
	_rebuild_overlays()
	var clip_count: int = 0
	for r in _last_audit_results:
		if bool(r["clipping"]):
			clip_count += 1
	print("[BucketSpawnOverview] Total spawnpoints: %d | Clipping: %d" % [_last_audit_results.size(), clip_count])
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
	print("[BucketSpawnOverview] === Room Overview (%d total spawnpoints) ===" % _last_audit_results.size())
	for rk in keys:
		var items: Array = by_room[rk]
		var parts: Array[String] = []
		for it in items:
			var flag: String = " [CLIP]" if bool(it["clipping"]) else ""
			parts.append("%s%s %s" % [it["name"], flag, str(it["pos"])])
		print("  %s (%d): %s" % [rk, items.size(), " | ".join(parts)])


func _on_delete_clipping_pressed() -> void:
	if not confirm_delete_clipping:
		push_warning("[BucketSpawnOverview] Check 'confirm_delete_clipping' first before deleting clipping spawnpoints.")
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
	print("[BucketSpawnOverview] Deleted %d clipping spawnpoints. Save the scene to persist." % deleted)
	call_deferred("_rebuild_overlays")


func _select_marker_in_editor(marker: Marker3D, label_text: String) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	if Engine.has_singleton(&"EditorInterface"):
		var ei: Object = Engine.get_singleton(&"EditorInterface")
		var sel: Object = ei.call("get_selection")
		if sel != null:
			sel.call("clear")
			sel.call("add_node", marker)
	print("[BucketSpawnOverview] Selected %s (press F in 3D view to focus, W to move)" % label_text)


func _on_select_next_clipping() -> void:
	_rebuild_overlays()
	var clipping: Array[Dictionary] = []
	for r in _last_audit_results:
		if bool(r["clipping"]):
			clipping.append(r)
	if clipping.is_empty():
		print("[BucketSpawnOverview] No clipping spawnpoints found!")
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
		print("[BucketSpawnOverview] No clipping spawnpoints found!")
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
