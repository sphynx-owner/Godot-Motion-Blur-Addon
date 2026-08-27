#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38

layout(set = 0, binding = 0) uniform isampler2D tile_max_x;
layout(rg8i, set = 0, binding = 1) uniform writeonly iimage2D tile_max;
// DEBUG_UNIFORMS

layout(push_constant, std430) uniform Params 
{	
	float nan5;
	float nan6;
	float nan7;
	float nan8;
	int tile_size;
	int nan2;
	int nan3;
	int nan4;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;


void main() 
{
	ivec2 render_size = ivec2(textureSize(tile_max_x, 0));

	ivec2 output_size = imageSize(tile_max);

	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);

	ivec2 global_uvi = uvi * ivec2(1, params.tile_size);

	if ((uvi.x >= output_size.x) || (uvi.y >= output_size.y) || (global_uvi.x >= render_size.x) || (global_uvi.y >= render_size.y)) 
	{
		return;
	}
	
	ivec4 max_velocity = ivec4(0);

	float max_velocity_length_squared = -1;

	for(int i = 0; i < params.tile_size; i++)
	{
		ivec2 current_uvi = global_uvi + ivec2(0, i);

		vec2 velocity_sample = texelFetch(tile_max_x, current_uvi, 0).xy;

		float current_velocity_length_squared = dot(velocity_sample, velocity_sample);

		if(current_velocity_length_squared > max_velocity_length_squared)
		{
			max_velocity_length_squared = current_velocity_length_squared;

			max_velocity = ivec4(velocity_sample, 0, 0);
		}
	}

	imageStore(tile_max, uvi, max_velocity);

#ifdef DEBUG
	for(int i = 0; i < 40; i++)
	{
		for(int j = 0; j < 40; j++)
		{
			imageStore(debug_6_image, uvi * 40 + ivec2(i, j), vec4(max_velocity.xy, i == 0 || j == 0 ? 1.0 : 0.0, 0.0));
			imageStore(debug_11_image, uvi * 40 + ivec2(i, j), vec4(texelFetch(tile_max_x, uvi * 40 + ivec2(i, j), 0).xy, i == 0 || j == 0 ? 1.0 : 0.0, 0.0));
		}
	}
#endif
}