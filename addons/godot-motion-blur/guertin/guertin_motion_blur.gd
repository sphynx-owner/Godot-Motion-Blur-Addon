@tool
extends "res://addons/sphynx_motion_blur_toolkit/guertin/base_guertin_motion_blur.gd"
class_name GuertinMotionBlur

const TILE_MAX_X_TEXTURE_NAME : StringName = "tile_max_x"
const TILE_MAX_TEXTURE_NAME : StringName = "tile_max"
const NEIGHBOR_MAX_TEXTURE_NAME : StringName = "neighbor_max"
const TILE_VARIANCE_TEXTURE_NAME : StringName = "tile_variance"

@export_storage var blur_stage : ShaderStageResource = preload("res://addons/sphynx_motion_blur_toolkit/guertin/shader_stages/guertin_blur_stage.tres")

@export_storage var overlay_stage : ShaderStageResource = preload("res://addons/sphynx_motion_blur_toolkit/guertin/shader_stages/guertin_overlay_stage.tres")

@export_storage var tile_max_x_stage : ShaderStageResource = preload("res://addons/sphynx_motion_blur_toolkit/guertin/shader_stages/guertin_tile_max_x_stage.tres")

@export_storage var tile_max_y_stage : ShaderStageResource = preload("res://addons/sphynx_motion_blur_toolkit/guertin/shader_stages/guertin_tile_max_y_stage.tres")

@export_storage var neighbor_max_stage : ShaderStageResource = preload("res://addons/sphynx_motion_blur_toolkit/guertin/shader_stages/guertin_neighbor_max_stage.tres")

var _previous_time : float = 0

var _stencil_texture: Texture2DRD

func _render_callback_2(
	render_size : Vector2i, 
	render_scene_buffers : RenderSceneBuffersRD, 
	render_scene_data : RenderSceneDataRD
):
	var time : float = float(Time.get_ticks_msec()) / 1000.0
	
	var delta_time : float = max(time - _previous_time, 0.0000001)
	
	_previous_time = time
	
	var temp_intensity = intensity
	
	if framerate_independent:
		var capped_frame_time : float = 1 / target_constant_framerate
		
		if !uncapped_independence:
			capped_frame_time = min(capped_frame_time, delta_time)
		
		temp_intensity = intensity * capped_frame_time / delta_time
	
	ensure_texture(
		TILE_MAX_X_TEXTURE_NAME, 
		render_scene_buffers, 
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, 
		Vector2(1. / tile_size, 1.)
	)
	
	ensure_texture(
		TILE_MAX_TEXTURE_NAME, 
		render_scene_buffers, 
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, 
		Vector2(1. / tile_size, 1. / tile_size)
	)
	
	ensure_texture(
		NEIGHBOR_MAX_TEXTURE_NAME, 
		render_scene_buffers, 
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, 
		Vector2(1. / tile_size, 1. / tile_size)
	)
	
	ensure_texture(
		TILE_VARIANCE_TEXTURE_NAME, 
		render_scene_buffers, 
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, 
		Vector2(1. / tile_size, 1. / tile_size)
	)
	
	ensure_texture(CUSTOM_VELOCITY_TEXTURE_NAME, render_scene_buffers)
	
	ensure_texture(COLOR_OUTPUT_TEXTURE_NAME, render_scene_buffers)
	
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
		temp_intensity
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
			1 if clamp_velocities_to_tile else 0,
			1 if velocity_depth_test else 0,
			1 if transparent_bg else 0,
		]
	)
	
	var view_count = render_scene_buffers.get_view_count()
	
	for view in range(view_count):
		# If you want to change this you must do so inside all compute shaders
		# layouts
		var compute_dispatch_group_size := 16
		
		rd.draw_command_begin_label("Pre Blur Processing", Color(1.0, 1.0, 1.0, 1.0))
		
		var depth_image: RID = render_scene_buffers.get_depth_layer(view)
		var velocity_image: RID = render_scene_buffers.get_velocity_layer(view)
		var scene_data_buffer: RID = render_scene_data.get_uniform_buffer()
		
		var custom_velocity_image: RID = get_texture(CUSTOM_VELOCITY_TEXTURE_NAME, render_scene_buffers)
		
		var x_groups := floori((render_size.x - 1) / 16 + 1)
		var y_groups := floori((render_size.y - 1) / 16 + 1)
		
		dispatch_stage(pre_blur_processor_stage, 
		[
			get_sampler_uniform(depth_image, 0, false),
			get_sampler_uniform(velocity_image, 1, false),
			get_image_uniform(custom_velocity_image, 2),
			get_buffer_uniform(scene_data_buffer, 3),
			#get_sampler_uniform(_stencil_texture.texture_rd_rid, 4)
		],
		pre_blur_push_constants,
		Vector3i(x_groups, y_groups, 1), 
		"Process Velocity Buffer", 
		view)
		
		rd.draw_command_end_label()
		
		rd.draw_command_begin_label("Motion Blur", Color(1.0, 1.0, 1.0, 1.0))
		
		var color_image: RID= render_scene_buffers.get_color_layer(view)
		
		var color_output_image: RID = get_texture(COLOR_OUTPUT_TEXTURE_NAME, render_scene_buffers)
		
		var tile_max_x_image: RID = get_texture(TILE_MAX_X_TEXTURE_NAME, render_scene_buffers)
		
		var tile_max_image: RID = get_texture(TILE_MAX_TEXTURE_NAME, render_scene_buffers)
		
		var neighbor_max_image: RID = get_texture(NEIGHBOR_MAX_TEXTURE_NAME, render_scene_buffers)
		
		var tile_variance_image: RID = get_texture(TILE_VARIANCE_TEXTURE_NAME, render_scene_buffers)
		
		
		x_groups = floori((render_size.x / tile_size - 1) / compute_dispatch_group_size + 1)
		y_groups = floori((render_size.y - 1) / compute_dispatch_group_size + 1)
		
		dispatch_stage(
			tile_max_x_stage, 
			[
				get_sampler_uniform(custom_velocity_image, 0, false),
				get_sampler_uniform(depth_image, 1, false),
				get_image_uniform(tile_max_x_image, 2)
			],
			tile_max_x_push_constants,
			Vector3i(x_groups, y_groups, 1), 
			"TileMaxX", 
			view
		)
		
		x_groups = floori((render_size.x / tile_size - 1) / compute_dispatch_group_size + 1)
		y_groups = floori((render_size.y / tile_size - 1) / compute_dispatch_group_size + 1)
		
		dispatch_stage(
			tile_max_y_stage, 
			[
				get_sampler_uniform(tile_max_x_image, 0, false),
				get_image_uniform(tile_max_image, 1)
			],
			tile_max_y_push_constants,
			Vector3i(x_groups, y_groups, 1), 
			"TileMaxY", 
			view
		)
		
		dispatch_stage(
			neighbor_max_stage, 
			[
				get_sampler_uniform(tile_max_image, 0, false),
				get_image_uniform(neighbor_max_image, 1)
			],
			neighbor_max_push_constants,
			Vector3i(x_groups, y_groups, 1), 
			"NeighborMax", 
			view
		)
		
		x_groups = floori((render_size.x - 1) / compute_dispatch_group_size + 1)
		y_groups = floori((render_size.y - 1) / compute_dispatch_group_size + 1)
		
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
			Vector3i(x_groups, y_groups, 1), 
			"Blur Reconstruction", 
			view
		)
		
		dispatch_stage(
			overlay_stage, 
			[
				get_sampler_uniform(color_output_image, 0, false),
				get_image_uniform(color_image, 1)
			],
			[],
			Vector3i(x_groups, y_groups, 1), 
			"Overlay result", 
			view
		)
		
		rd.draw_command_end_label()
