@tool
extends "res://addons/sphynx_motion_blur_toolkit/base_classes/mb_compositor_effect.gd"

@export_group("Guerting Parameters")
@export var tile_size : int = 40

@export var jitter_tiles: bool = true

@export var clamp_velocities_to_tile: bool = false


func _property_can_revert(property: StringName) -> bool:
	return property == "samples"


func _property_get_revert(property: StringName) -> Variant:
	return 4
