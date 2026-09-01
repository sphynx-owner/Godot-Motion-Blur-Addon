@tool
@abstract
class_name BaseGuertingMotionBlur
extends MotionBlurCompositorEffect

@export_group("Guerting Parameters")
@export_range(16, 64, 1) var tile_size : int = 40


func _property_can_revert(property: StringName) -> bool:
	return property == "samples"


func _property_get_revert(property: StringName) -> Variant:
	return 4
