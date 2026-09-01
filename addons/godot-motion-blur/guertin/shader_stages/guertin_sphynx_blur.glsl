#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38
#define M_PI 3.1415926535897932384626433832795
#define EPSILON 1e-6
#define PIXEL_RADIUS 0.5
#define PIXEL_RADIUS_SQUARED 0.25
// At depth difference of 1 / SOFT_DEPTH_SENSITIVITY the velocity weights are
// at their extremes.
#define SOFT_DEPTH_SENSITIVITY 1

#define USE_JITTER

#ifdef USE_JITTER
#define TILE_JITTER jitter_tile(uvi)

#define SAMPLE_JITTER j

#else
#define TILE_JITTER 0

#define SAMPLE_JITTER 0
#endif


layout(set = 0, binding = 0) uniform sampler2D color_sampler;
layout(set = 0, binding = 1) uniform sampler2D velocity_sampler;
layout(set = 0, binding = 2) uniform isampler2D neighbor_max;
layout(rgba16f, set = 0, binding = 3) uniform writeonly image2D output_color;
// DEBUG_UNIFORMS

layout(push_constant, std430) uniform Params 
{	
	int tile_size;
	int sample_count;
	int frame;
	int transparent_bg;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Guertin's functions https://research.nvidia.com/sites/default/files/pubs/2013-11_A-Fast-and/Guertin2013MotionBlur-small.pdf
// ----------------------------------------------------------
float soft_compare(float a, float b, float sze) {
	return clamp(sze * (a - b), 0, 1);
}

float cone(float a, float b, float sze) {
	return clamp(1 - sze * abs(a - b), 0, 1);
}
// ----------------------------------------------------------

// from https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/
// and https://blog.demofox.org/2022/01/01/interleaved-gradient-noise-a-different-kind-of-low-discrepancy-sequence/ (section: Derivation Of IGN And Extensions) for animation of the noise.
// ----------------------------------------------------------
float interleaved_gradient_noise(vec2 uv) {
	uv += float(params.frame) * 5.588238;

	vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);

	return fract(magic.z * fract(dot(uv, magic.xy)));
}
// ----------------------------------------------------------

// from https://github.com/bradparks/KinoMotion__unity_motion_blur/tree/master
// ----------------------------------------------------------
vec2 safenorm(vec2 v) {
	float l = max(length(v), EPSILON);
	return v / l * int(l >= 0.5);
}

ivec2 jitter_tile(ivec2 uvi) {
	float rx, ry;
	// HACK @sphynx-owner: multiplying the input uvi seems to help reducing large emergent
	// patchiness in the blurred results along the jittered seams between tiles.
	float angle = interleaved_gradient_noise(uvi * 4) * M_PI * 2;
	rx = cos(angle);
	ry = sin(angle);
	return ivec2(vec2(rx, ry) * params.tile_size / 4);
}
// ----------------------------------------------------------

vec4 sample_x_velocity(ivec2 x, float t, vec2 vx, float vx_length, vec2 wvx, float zx, float vzx, ivec2 render_size, out float x_weight, out float x_back_weight) {
	// TODO @sphynx-owner: do we need to divide by render
	// size?
	ivec2 yx = x + ivec2(t * vx);

	if (yx.x < 0 || yx.x > render_size.x || yx.y < 0 || yx.y > render_size.y) {
		x_weight = 0;

		return vec4(0);
	}

	vec4 syx = texelFetch(velocity_sampler, yx, 0);

	vec2 vyx = syx.xy;

	float vyx_length = length(vyx);

	float tx = abs(t * vx_length);

	vec2 wvyx = vyx / vyx_length;

	float projected = abs(dot(wvyx, wvx));

	float reaches_weight = step(tx, vyx_length / 2.0 * projected);

	float zyx = syx.w;

	float vzyx = syx.z;

	float x_depth = zx + vzx * t;

	float yx_depth = zyx + vzyx * t;

	float soft_overlap_x = cone(x_depth, yx_depth, SOFT_DEPTH_SENSITIVITY);

	x_weight = soft_overlap_x * reaches_weight;

	float overlap_x = soft_compare(x_depth, yx_depth, SOFT_DEPTH_SENSITIVITY);

	x_back_weight = overlap_x;
	
	return texelFetch(color_sampler, yx, 0);
}

vec4 sample_y_velocity(ivec2 x, float t, vec2 vn, float vn_length, vec2 wvn, float zx, float vzx, ivec2 render_size, out float y_weight) {
	// The sample positon along the neighbor_max velocity.
	ivec2 yn = x + ivec2(t * vn);
	
	// If the found velocity is smaller than a pixel's radius, exit early.
	if (yn.x < 0 || yn.x > render_size.x || yn.y < 0 || yn.y > render_size.y) {
		y_weight = 0;

		return vec4(0);
	}

	// We get the velocity at the sample position.
	vec4 syn = texelFetch(velocity_sampler, yn, 0);

	// The velocity at the sample position.
	vec2 vyn = syn.xy;

	float vyn_length = length(vyn);

	// The depth at the sample position.
	float zyn = syn.w;

	// The z velocity at the sample position.
	float vzyn = syn.z;

	float x_depth = zx + vzx * t;

	// TODO @sphynx-owner: understand why we use the negative of the depth
	// velocity here and not in the sample_x_velocity function.
	float y_depth = zyn - vzyn * t;

	// We get whether the depth at the sample position plus offset derived from the z velocity is in front
	// of the depth at the current pixel. Starts at 0 when same depth, and goes to 1 the closer it is.
	float overlapn = soft_compare(y_depth, x_depth, SOFT_DEPTH_SENSITIVITY);
	
	// If the found velocity is smaller than a pixel's radius, exit early.
	if (vyn_length < PIXEL_RADIUS || overlapn <= EPSILON) {
		y_weight = 0;

		return vec4(0);
	}

	// Get the distance of the sampled position from the current pixel (would be the time multiplied by the velocity length,
	// to match how we offset x to sample the velocity in the first place).
	float tn = abs(t * vn_length);

	// Get the normalized velocity at the sampled position.
	vec2 wvyn = vyn / vyn_length;

	// We project the normalized found velocity onto the normalized neighbor_max velocity. This provides us
	// with a projection value that we can use to compare the found velocity's magnitude given it's alignment
	// with neighbor_max velocity. The less the found velocity aligns with the neighbor_max velocity, the larger
	// it would have to be to feasibly reach this pixel.
	float projected = abs(dot(wvyn, wvn));

	// y_weight is determined by:
	// 1. Can the found velocity reach over to this pixel
	// 2. Is the depth at the found pixel, including its depth velocity, overlap the current one
	// 3. An additional offset that handles when the neighbor_max velocity is larger than the found velocity
	// to counteract the resulting opacity dilution.
	y_weight = step(tn, vyn_length / 2.0 * projected) * overlapn * pow(vn_length / vyn_length, 0.5);

	return texelFetch(color_sampler, yn, 0);
}

void blend_blur(
	vec4 base_color,
	vec4 x_sample,
	float x_weight,
	float x_back_weight,
	vec4 neg_x_sample,
	float neg_x_weight,
	vec4 y_sample,
	float y_weight,
	inout vec4 color_sum,
	inout float color_weight,
	inout float alpha_weight
) {
	float current_weight_x = max(x_weight, neg_x_weight);

	// TODO @sphynx-owner: figure out a better heuristic to choosing a value. If the weight cannot be larger than
	// 1, we can simply get the difference between the negative weight and the regular weigth, clamping it between 0 and 1.
	// this needs to be thoroughly tested.
	vec4 x_color_sample = mix(neg_x_sample, x_sample, clamp(x_weight / neg_x_weight, 0, 1));

	vec4 current_color = mix(mix(mix(base_color, x_color_sample, current_weight_x), x_sample, x_back_weight), y_sample, y_weight);

	float current_color_weight = max(current_color.a, 1 - params.transparent_bg);

	color_sum += vec4(current_color.rgb * current_color_weight, current_color.a);

	color_weight += current_color_weight;

	alpha_weight += 1;
}

void main() {
	// The size of the output texture
	ivec2 render_size = ivec2(textureSize(color_sampler, 0));

	// The pixel we are running the shader for.
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);

	// If the pixel we are in is outside the target render's size, we
	// exit early
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) {
		return;
	}

	// We convert the pixel position into a texturing sampling position
	// we add 0.5 to offset the sampling to be in the "middle" of the pixel
	// and avoid artifacts caused by bilinear interpolation.
	ivec2 x = uvi;

	ivec2 neighbor_max_uvi = (uvi + TILE_JITTER) / params.tile_size;

	// We get the neighbor-max velocity for the tile we are in, with some jitter
	// between tiles to hide seams between them.
	// TODO @sphynx-owner: figure out the most optimized way to generate the different textures and sample them.
	// Technically working in screen space is the more correct way to operate because it would reduce the infulence
	// of the screen's aspect ratio, so we cannot get rid of the render size modifiers, maybe commit to them more?
	vec2 vn = texelFetch(neighbor_max, neighbor_max_uvi, 0).xy;

	// We get the true velocity at the current pixel
	vec4 sx = texelFetch(velocity_sampler, x, 0);

	vec2 vx = sx.xy;

	vec4 base_color = texelFetch(color_sampler, x, 0);

	// We must account for cases where the dominant velocity is 0 even though
	// The current velocity is not. This is only the case for the skybox, which
	// Will never overlap geometry so it can safely be ignored when calculating neighbor_max
	// NOTE @sphynx-owner: using PIXEL_RADIUS_SQUARED cause we compare against the squared length.
	if(dot(vn, vn) < PIXEL_RADIUS_SQUARED && dot(vx, vx) < PIXEL_RADIUS_SQUARED)
	{
		imageStore(output_color, uvi, base_color);
		
#ifdef DEBUG
		imageStore(debug_8_image, uvi, vec4(vn / render_size, uvi.x % params.tile_size == 0 || uvi.y %params.tile_size == 0 ? 1.0 : 0.0, 0.0));
		imageStore(debug_1_image, uvi, base_color);
		imageStore(debug_7_image, uvi, vec4(texelFetch(neighbor_max, uvi / params.tile_size, 0).xy / float(params.tile_size * 2), uvi.x % params.tile_size == 0 || uvi.y % params.tile_size == 0  ? 1.0 : 0.0, 0.0));
#endif

		return;
	}

	float vn_length = length(vn);

	// We normalize neighbor-max velocity
	vec2 wvn = vn / vn_length;

	float vx_length = length(vx);

	vec2 wvx = vx / vx_length;

	// Get the depth at current pixel
	float zx = sx.w;

	// Get the depth velocity at current pixel
	float vzx = sx.z;

	// We get some random value for the current pixel between 0 and 1. This will be used to
	// jitter the blur sampling, and achieve smoother looking blur gradient
	// with a fraction of the sample count.
	float j = interleaved_gradient_noise(uvi);

	float color_weight = EPSILON;

	float alpha_weight = EPSILON;

	// Create an initial color sum
	vec4 sum = vec4(base_color.rgb * base_color.a * color_weight, base_color.a * alpha_weight);

	for(int i = 0; i < params.sample_count; i++)
	{
		float ti = float(i + SAMPLE_JITTER) / params.sample_count;

		float neg_ti = float(i + 1 - SAMPLE_JITTER) / params.sample_count;

		// A point in time along the blur interval, used to scale velocity vectors to sample for color.
		float t = mix(0, -0.5, ti);
		
		float neg_t = mix(0, 0.5, neg_ti);

		float x_weight;

		float x_back_weight;
		
		vec4 x_sample = sample_x_velocity(x, t, vx, vx_length, wvx, zx, vzx, render_size, x_weight, x_back_weight);
		
		float neg_x_weight;

		float neg_x_back_weight;

		vec4 neg_x_sample = sample_x_velocity(x, neg_t, vx, vx_length, wvx, zx, vzx, render_size, neg_x_weight, neg_x_back_weight);

		float y_weight;

		vec4 y_sample = sample_y_velocity(x, t, vn, vn_length, wvn, zx, vzx, render_size, y_weight);
		
		float neg_y_weight;

		vec4 neg_y_sample = sample_y_velocity(x, neg_t, vn, vn_length, wvn, zx, vzx, render_size, neg_y_weight);

		blend_blur(base_color, x_sample, x_weight, x_back_weight, neg_x_sample, neg_x_weight, y_sample, y_weight, sum, color_weight, alpha_weight);

		blend_blur(base_color, neg_x_sample, neg_x_weight, neg_x_back_weight, x_sample, x_weight, neg_y_sample, neg_y_weight, sum, color_weight, alpha_weight);
	}

	sum.rgb /= color_weight;
	sum.a /= alpha_weight;

	imageStore(output_color, uvi, sum);

#ifdef DEBUG
	imageStore(debug_8_image, uvi, vec4(vn / render_size, uvi.x % params.tile_size == 0 || uvi.y %params.tile_size == 0  ? 1.0 : 0.0, 0.0));
	imageStore(debug_1_image, uvi, base_color);
	imageStore(debug_7_image, uvi, vec4(texelFetch(neighbor_max, uvi / params.tile_size, 0).xy / float(params.tile_size * 2), uvi.x % params.tile_size == 0 || uvi.y % params.tile_size == 0  ? 1.0 : 0.0, 0.0));
#endif
}