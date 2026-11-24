@tool
class_name AcousticZone3D
extends Area3D

## Native Godot Area3D acoustic reverb zone (Phase 4).
## Overrides the audio bus for emitters and listeners inside the volume.

enum ReverbPreset {
	SMALL_ROOM = 0,
	LARGE_HALL = 1,
	CUSTOM = 2,
}

@export var reverb_preset: ReverbPreset = ReverbPreset.SMALL_ROOM:
	set(value):
		reverb_preset = value
		_apply_zone_settings()

@export var custom_bus_name: StringName = &"Reverb_SmallRoom":
	set(value):
		custom_bus_name = value
		_apply_zone_settings()

@export var zone_priority: int = 1:
	set(value):
		zone_priority = value
		_apply_zone_settings()

@export_range(0.0, 1.0, 0.05) var reverb_amount: float = 1.0:
	set(value):
		reverb_amount = clampf(value, 0.0, 1.0)
		_apply_zone_settings()

@export_range(0.0, 1.0, 0.05) var reverb_uniformity: float = 0.5:
	set(value):
		reverb_uniformity = clampf(value, 0.0, 1.0)
		_apply_zone_settings()


func _ready() -> void:
	_apply_zone_settings()


func get_target_bus_name() -> StringName:
	match reverb_preset:
		ReverbPreset.SMALL_ROOM:
			return &"Reverb_SmallRoom"
		ReverbPreset.LARGE_HALL:
			return &"Reverb_LargeHall"
		_:
			return custom_bus_name if custom_bus_name != &"" else &"Master"


func _apply_zone_settings() -> void:
	var target_bus: StringName = get_target_bus_name()
	audio_bus_override = true
	audio_bus_name = target_bus
	reverb_bus_enabled = true
	reverb_bus_name = target_bus
	reverb_bus_amount = reverb_amount
	reverb_bus_uniformity = reverb_uniformity
	priority = zone_priority

	collision_layer = GameConfig.LAYER_TRIGGERS
	collision_mask = GameConfig.LAYER_PLAYER
	monitoring = true
	monitorable = true
