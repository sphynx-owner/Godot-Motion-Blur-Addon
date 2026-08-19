@tool
extends "res://addons/sphynx_enhanced_compositor_toolkit/base_classes/enhanced_compositor_effect.gd"
#class_name MotionBlurCompositor
## This class abstracts some of the default settings that are expected 
## from a motion blur compositor effect. 

const CUSTOM_VELOCITY_TEXTURE_NAME : StringName = "custom_velocity"
const COLOR_OUTPUT_TEXTURE_NAME : StringName = "color_output"

@export_group("Motion Blur Parameters")

# diminishing returns over 8
@export_range(4, 64) var samples: int = 8

# you really don't want this over 0.5, but you can if you want to try
@export_range(0, 1.0, 0.001, "or_greater") var intensity: float = 1

@export_range(0, 1) var center_fade: float = 0.0

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

@export var velocity_depth_test := true

## Modifies the otherwise regular average color over time
## to be weighted average over time based on a distribution curve.
## flat line is equivalent to the default, and you can choose 
## to modify the amount of color during the motion blur frame from
## start to finish.
@export var custom_curve: Curve

@export var use_custom_curve: bool

@export var transparent_bg: bool = false

@export var support_fsr2 := true

@export_storage var pre_blur_processor_stage : ShaderStageResource = preload("res://addons/sphynx_motion_blur_toolkit/pre_blur_processing/shader_stages/pre_blur_processing_stage.tres")

@export_group("Movement Separation")

@export_subgroup("Camera Rotation")

@export var camera_rotation_multiplier := 1.0
@export var camera_rotation_lower_threshold := 0.0
@export var camera_rotation_upper_threshold := 0.0

@export_subgroup("Camera Movement")

@export var camera_movement_multiplier := 1.0
@export var camera_movement_lower_threshold := 0.0
@export var camera_movement_upper_threshold := 0.0

@export_subgroup("Object Movement")

@export var object_movement_multiplier := 1.0
@export var object_movement_lower_threshold := 0.0
@export var object_movement_upper_threshold := 0.0

var custom_curve_texture_rd: Texture2DRD

var _properties_to_remove: Dictionary[String, bool] = {
	"needs_motion_vectors": true,
	"needs_normal_roughness": true,
}


func _init():
	context = "MotionBlur"
	
	needs_motion_vectors = true
	needs_normal_roughness = false
	
	_custom_curve_updated()
	
	super()


func _validate_property(property: Dictionary) -> void:
	if _properties_to_remove.has(property.name):
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _custom_curve_updated() -> void:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	
	var curve_texture := CurveTexture.new()
	
	curve_texture.curve = custom_curve if custom_curve != null else Curve.new()
	
	var curve_image : Image = RenderingServer.texture_2d_get(curve_texture)
	curve_image.clear_mipmaps()
	curve_image.decompress()
	curve_image.convert(Image.FORMAT_RGBAF)
	
	var curve_texture_format : RDTextureFormat = RDTextureFormat.new()
	curve_texture_format.width = curve_image.get_width()
	curve_texture_format.height = curve_image.get_height()
	curve_texture_format.depth = 1
	
	curve_texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	
	curve_texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	
	curve_texture_format.usage_bits = \
	RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	
	var paint_texture_view : RDTextureView = RDTextureView.new()
	
	custom_curve_texture_rd = Texture2DRD.new()
	
	custom_curve_texture_rd.texture_rd_rid = rd.texture_create(
		curve_texture_format, 
		paint_texture_view, 
		[curve_image.get_data()]
	)
