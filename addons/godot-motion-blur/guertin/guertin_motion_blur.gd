@tool
class_name GuertinMotionBlur
extends BaseGuertingMotionBlur

const TILE_MAX_X_TEXTURE : StringName = &"tile_max_x"

const TILE_MAX_TEXTURE : StringName = &"tile_max"

const NEIGHBOR_MAX_TEXTURE : StringName = &"neighbor_max"

const TILE_VARIANCE_TEXTURE : StringName = &"tile_variance"

@export var blur_stage: RDShaderFile = preload("res://addons/godot-motion-blur/guertin/shader_stages/guertin_sphynx_blur.glsl")

@export var overlay_stage: RDShaderFile = preload("res://addons/godot-motion-blur/guertin/shader_stages/guertin_overlay.glsl")

@export var tile_max_x_stage: RDShaderFile = preload("res://addons/godot-motion-blur/guertin/shader_stages/guertin_tile_max_x.glsl")

@export var tile_max_y_stage: RDShaderFile = preload("res://addons/godot-motion-blur/guertin/shader_stages/guertin_tile_max_y.glsl")

@export var neighbor_max_stage: RDShaderFile = preload("res://addons/godot-motion-blur/guertin/shader_stages/guertin_neighbor_max.glsl")

var _previous_time : float = 0


func _enhanced_render_callback(render_size : Vector2i):
	var time : float = float(Time.get_ticks_msec()) / 1000.0
	
	var delta_time : float = max(time - _previous_time, 0.0000001)
	
	_previous_time = time
	
	var temp_intensity = intensity
	
	if framerate_independent:
		var capped_frame_time : float = 1 / target_constant_framerate
		
		if !uncapped_independence:
			capped_frame_time = min(capped_frame_time, delta_time)
		
		temp_intensity = intensity * capped_frame_time / delta_time
	
	var max_x_size: Vector2i = divide_vector2i_by_tile_size(render_size, Vector2i(tile_size, 1))
	
	var neighbor_max_size: Vector2i = divide_vector2i_by_tile_size(render_size, Vector2i(tile_size, tile_size))
	
	ensure_texture(
		TILE_MAX_X_TEXTURE,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		max_x_size
	)
	
	ensure_texture(
		TILE_MAX_TEXTURE,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		neighbor_max_size
	)
	
	ensure_texture(
		NEIGHBOR_MAX_TEXTURE,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		neighbor_max_size
	)
	
	ensure_texture(
		TILE_VARIANCE_TEXTURE,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		neighbor_max_size
	)
	
	ensure_texture(CUSTOM_VELOCITY_TEXTURE)
	
	ensure_texture(COLOR_OUTPUT_TEXTURE)
	
	var pre_blur_push_constants: PackedByteArray = get_push_constants([
		camera_rotation_multiplier,
		camera_movement_multiplier,
		object_movement_multiplier,
		camera_rotation_lower_threshold,
		camera_movement_lower_threshold,
		object_movement_lower_threshold,
		camera_rotation_upper_threshold,
		camera_movement_upper_threshold,
		object_movement_upper_threshold,
		support_fsr2,
		temp_intensity,
		tile_size
	])
	
	var tile_max_x_push_constants: PackedByteArray = get_push_constants([], [tile_size], true)
	
	var tile_max_y_push_constants: PackedByteArray = get_push_constants([], [tile_size], true)
	
	var neighbor_max_push_constants: PackedByteArray = get_push_constants([], [], true)
	
	var tile_variance_push_constants: PackedByteArray = get_push_constants([], [], true)
	
	var blur_push_constants: PackedByteArray = get_push_constants(
		[temp_intensity],
		[
			tile_size,
			samples,
			Engine.get_frames_drawn() % 8,
			1 if use_custom_curve else 0,
			1 if jitter_tiles else 0,
			1 if velocity_depth_test else 0,
			1 if transparent_bg else 0,
		]
	)
	
	rd_instance.rd.draw_command_begin_label("Pre Blur Processing", Color(1.0, 1.0, 1.0, 1.0))
	
	var depth_image: RID = get_depth_texture()
	
	var custom_velocity_image: RID = get_texture(CUSTOM_VELOCITY_TEXTURE)
	
	var render_groups_count: Vector3i = get_groups_count(Vector3i(render_size.x, render_size.y, 1), DEFAULT_GROUP_SIZE)
	
	dispatch_stage(
		pre_blur_processor_stage, 
		[
			get_sampler_uniform(depth_image, 0, false),
			get_sampler_uniform(get_velocity_texture(), 1, false),
			get_image_uniform(custom_velocity_image, 2),
			get_buffer_uniform(get_scene_uniform_data_buffer(), 3)
		],
		pre_blur_push_constants,
		render_groups_count, 
		"Process Velocity Buffer"
	)
	
	rd_instance.rd.draw_command_end_label()
	
	rd_instance.rd.draw_command_begin_label("Motion Blur", Color(1.0, 1.0, 1.0, 1.0))
	
	var color_image: RID = get_color_texture()
	
	var color_output_image: RID = get_texture(COLOR_OUTPUT_TEXTURE)
	
	var tile_max_x_image: RID = get_texture(TILE_MAX_X_TEXTURE)
	
	var tile_max_image: RID = get_texture(TILE_MAX_TEXTURE)
	
	var neighbor_max_image: RID = get_texture(NEIGHBOR_MAX_TEXTURE)
	
	var tile_variance_image: RID = get_texture(TILE_VARIANCE_TEXTURE)
	
	var max_x_groups_count: Vector3i = get_groups_count(Vector3i(max_x_size.x, max_x_size.y, 1), DEFAULT_GROUP_SIZE)
	
	dispatch_stage(
		tile_max_x_stage, 
		[
			get_sampler_uniform(custom_velocity_image, 0, false),
			get_sampler_uniform(depth_image, 1, false),
			get_image_uniform(tile_max_x_image, 2)
		],
		tile_max_x_push_constants,
		max_x_groups_count, 
		"TileMaxX"
	)
	
	var neighbor_max_groups_count: Vector3i = get_groups_count(
		Vector3i(neighbor_max_size.x, neighbor_max_size.y, 1),
		DEFAULT_GROUP_SIZE
	)
	
	dispatch_stage(
		tile_max_y_stage, 
		[
			get_sampler_uniform(tile_max_x_image, 0, false),
			get_image_uniform(tile_max_image, 1)
		],
		tile_max_y_push_constants,
		neighbor_max_groups_count, 
		"TileMaxY"
	)
	
	dispatch_stage(
		neighbor_max_stage, 
		[
			get_sampler_uniform(tile_max_image, 0, false),
			get_image_uniform(neighbor_max_image, 1)
		],
		neighbor_max_push_constants,
		neighbor_max_groups_count, 
		"NeighborMax"
	)
	
	dispatch_stage(
		blur_stage, 
		[
			get_sampler_uniform(color_image, 0, false),
			get_sampler_uniform(custom_velocity_image, 1, false),
			get_sampler_uniform(neighbor_max_image, 2, false),
			get_sampler_uniform(tile_variance_image, 3, true),
			get_image_uniform(color_output_image, 4),
			get_sampler_uniform(custom_curve_texture_rd.texture_rd_rid, 5, true)
		],
		blur_push_constants,
		render_groups_count, 
		"Blur Reconstruction"
	)
	
	dispatch_stage(
		overlay_stage, 
		[
			get_sampler_uniform(color_output_image, 0, false),
			get_image_uniform(color_image, 1)
		],
		[],
		render_groups_count, 
		"Overlay result"
	)
	
	rd_instance.rd.draw_command_end_label()
