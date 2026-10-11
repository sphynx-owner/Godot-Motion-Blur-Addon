@tool
@abstract
class_name MotionBlurCompositorEffect
extends EnhancedCompositorEffect
## This class abstracts some of the default settings that are expected 
## from a motion blur compositor effect. 

const CUSTOM_VELOCITY_TEXTURE : StringName = "custom_velocity"
const COLOR_OUTPUT_TEXTURE : StringName = "color_output"

## Defines the amount of motion blur to apply given the object's velocity. At 1.0, the object's velocity will
## be blurred in full (blur fills in the motion step fully). An intensity of 0.5 can be interpreted as a 180 degrees shutter.
@export_range(0, 1.0, 0.01, "or_greater") var intensity: float = 1

@export_group("Multipliers", "multiplier_")

## Defines the intensity of blur similar to [member intensity], but only for the part of the motion caused by camera rotation.
@export_range(0, 1, 0.01) var multiplier_camera_rotation := 0.1

## Defines the intensity of blur similar to [member intensity], but only for the part of the motion caused by camera movement.
@export_range(0, 1, 0.01) var multiplier_camera_movement := 1.0

## Defines the intensity of blur similar to [member intensity], but only for the part of the motion caused by object movement.
@export_range(0, 1, 0.01) var multiplier_object_movement := 1.0

@export_group("Activation", "activation_")

## Defines a magnitude of motion beyond which motion would start getting blurred. Works in tandem with [member activation_smoothing]
## to define a seamless transition between non-blurred motion, and fully blurred motion given the motion's magnitude.
## The value is treated in terms of screen height percentage after the velocity was normalized to 60fps. Setting it to [code]50[/code]
## means that blurring starts at motion that's visually larger than half the screen's height within a 60th of a second.
## You can use these thresholds to create a less intrusive motion blur effect, where below certain movement speeds details stay crisp.
@export_range(0.0, 100.0, 0.01, "or_greater") var activation_threshold := 1.7

## Defines a range on top of [member activation_threshold] along which velocity magnitudes gradually activate motion blur.
## Used to smoothen the seam between non-activated and activated motion blur areas. See [member activation_threshold] for more info.
@export_range(0.0, 10.0, 0.01, "or_greater") var activation_smoothing := 1.25

@export_group("Additional Parameters")

## Higher sample count means better quality.
@export_range(1, 8, 1, "prefer_slider", "or_greater") var samples: int = 3

## wether this motion blur stays the same intensity below
## target_constant_framerate
@export var framerate_independent : bool = true

## Description: Removes clamping on motion blur scale to allow framerate independent motion
## blur to scale longer than realistically possible when render framerate is higher
## than target framerate.[br][br]
## [color=yellow]Warning:[/color] Turning this on would allow over-blurring of pixels, which 
## produces inaccurate results, and would likely cause nausea in players over
## long exposure durations, use with caution and out of artistic intent
@export var uncapped_independence : bool = false

## if framerate_independent is enabled, the blur would simulate 
## shutter speeds at that framerate, and up.
@export var target_constant_framerate : float = 30

@export var transparent_bg: bool = false

## WARNING: this is a testing utility, should not be enabled for regular use.
@export var disable_activation_normalization: bool = false

@export_storage var pre_blur_processor_stage: RDShaderFile = preload("res://addons/godot-motion-blur/pre_blur_processing/shader_stages/pre_blur_processor.glsl")

var _properties_to_remove: Dictionary[String, bool] = {
	"needs_motion_vectors": true,
	"needs_normal_roughness": true,
}


func _init():
	context = "MotionBlur"
	
	needs_motion_vectors = true
	needs_normal_roughness = false


func _validate_property(property: Dictionary) -> void:
	if _properties_to_remove.has(property.name):
		property.usage = PROPERTY_USAGE_NO_EDITOR
