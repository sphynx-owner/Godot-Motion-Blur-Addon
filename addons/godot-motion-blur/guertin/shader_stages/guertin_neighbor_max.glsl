#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38

layout(set = 0, binding = 0) uniform isampler2D tile_max;
layout(rg8i, set = 0, binding = 1) uniform writeonly iimage2D neighbor_max;
// DEBUG_UNIFORMS

layout(push_constant, std430) uniform Params 
{	
	float nan5;
	float nan6;
	float nan7;
	float nan8;
	int nan1;
	int nan2;
	int nan3;
	int nan4;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;


void main() 
{
	ivec2 render_size = ivec2(textureSize(tile_max, 0));

	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);

	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}

	vec2 max_neighbor_velocity = vec2(0);

	float max_neighbor_velocity_length_squared = 0;

	for(int i = -1; i <= 1; i++)
	{
		for(int j = -1; j <= 1; j++)
		{
			ivec2 current_offset = ivec2(i, j);

			ivec2 current_uvi = uvi + current_offset;

			if(current_uvi.x < 0 || current_uvi.x >= render_size.x || current_uvi.y < 0 || current_uvi.y >= render_size.y)
			{
				continue;
			}

			bool is_diagonal = i != 0 && j != 0;

			vec2 current_neighbor_velocity = texelFetch(tile_max, current_uvi, 0).xy;

			bool facing_center = dot(current_neighbor_velocity, current_offset) > 0;

			if(is_diagonal && !facing_center)
			{
				continue;
			}

			float current_neighbor_velocity_length_squared = dot(current_neighbor_velocity, current_neighbor_velocity);

			if(current_neighbor_velocity_length_squared > max_neighbor_velocity_length_squared)
			{
				max_neighbor_velocity_length_squared = current_neighbor_velocity_length_squared;

				max_neighbor_velocity = current_neighbor_velocity;
			}
		}
	}

	imageStore(neighbor_max, uvi, ivec4(max_neighbor_velocity, 0, 0));
}