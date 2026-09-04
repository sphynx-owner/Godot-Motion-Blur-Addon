@tool
@abstract
class_name MotionBlurCompositorEffect
extends EnhancedCompositorEffect
## This class abstracts some of the default settings that are expected 
## from a motion blur compositor effect. 

const CUSTOM_VELOCITY_TEXTURE : StringName = "custom_velocity"
const COLOR_OUTPUT_TEXTURE : StringName = "color_output"

@export_group("Motion Blur Parameters")

## Higher sample count means better quality.
@export_range(1, 64) var samples: int = 2

## Controls the intensity of the blur.
@export_range(0, 1.0, 0.001, "or_greater") var intensity: float = 1

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
## sutter speeds at that framerate, and up.
@export var target_constant_framerate : float = 30

@export var transparent_bg: bool = false

@export_storage var pre_blur_processor_stage: RDShaderFile = preload("res://addons/godot-motion-blur/pre_blur_processing/shader_stages/pre_blur_processor.glsl")

@export_group("multipliers", "multiplier_")

@export_range(0, 1, 0.001) var multiplier_camera_rotation := 1.0

@export_range(0, 1, 0.001) var multiplier_camera_movement := 1.0

@export_range(0, 1, 0.001) var multiplier_object_movement := 1.0

@export_group("velocity thresholds", "velocity_threshold_")

@export_range(0.0, 100.0, 0.001) var velocity_threshold_lower := 0.0:
	set(value):
		velocity_threshold_lower = value
		
		if !_velocity_thresholds_setter_gate:
			_velocity_thresholds_setter_gate = true
			velocity_threshold_upper = max(velocity_threshold_upper, velocity_threshold_lower)
			_velocity_thresholds_setter_gate = false

@export_range(0.0, 100.0, 0.001) var velocity_threshold_upper := 0.0:
	set(value):
		velocity_threshold_upper = value
		
		if !_velocity_thresholds_setter_gate:
			_velocity_thresholds_setter_gate = true
			velocity_threshold_lower = min(velocity_threshold_lower, velocity_threshold_upper)
			_velocity_thresholds_setter_gate = false

var _velocity_thresholds_setter_gate: bool = false

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
