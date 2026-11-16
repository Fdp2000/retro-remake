@tool
extends Node3D
## Tint the existing Interiors_A textures. White restores their original appearance.
@export_group("Room Palette")
@export_color_no_alpha var wall_color: Color = Color.WHITE:
	set(value):
		wall_color = value
		_refresh()
@export_color_no_alpha var floor_color: Color = Color.WHITE:
	set(value):
		floor_color = value
		_refresh()
@export_color_no_alpha var ceiling_color: Color = Color.WHITE:
	set(value):
		ceiling_color = value
		_refresh()

func _refresh() -> void:
	if is_inside_tree():
		get_parent().get_parent().call_deferred("refresh_palettes")
