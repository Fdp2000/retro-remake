shader_type spatial;

uniform bool is_wall = false;
uniform bool is_ceiling = false;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wall_blue : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D wall_green : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D wall_purple : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D wall_red : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D wall_yellow : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 room_colors[16] : source_color;
uniform int wall_variants[16];
uniform mat4 building_inverse;

varying vec3 room_surface;
varying vec3 room_normal;
varying vec2 wall_tangent;

void vertex() {
	room_surface = (building_inverse * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	room_normal = normalize(mat3(building_inverse) * MODEL_NORMAL_MATRIX * NORMAL);
	wall_tangent = (building_inverse * MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xz;
}

vec3 sample_wall(int variant, vec2 uv, vec2 dx, vec2 dy) {
	if (variant == 0) {
		return textureGrad(wall_blue, uv, dx, dy).rgb;
	}
	if (variant == 1) {
		return textureGrad(wall_green, uv, dx, dy).rgb;
	}
	if (variant == 2) {
		return textureGrad(wall_purple, uv, dx, dy).rgb;
	}
	if (variant == 3) {
		return textureGrad(wall_red, uv, dx, dy).rgb;
	}
	return textureGrad(wall_yellow, uv, dx, dy).rgb;
}

void fragment() {
	vec3 sample_position = room_surface + normalize(room_normal) * 0.25;
	ivec2 cell = ivec2(clamp(floor((sample_position.xz + vec2(18.0)) / 9.0), vec2(0.0), vec2(3.0)));
	int room = cell.y * 4 + cell.x;
	vec3 texel;
	if (is_wall) {
		// Align the texture across the full room side, including window and door tiles.
		vec2 room_uv = (room_surface.xz + vec2(18.0)) / 9.0 - vec2(cell);
		float along_wall = abs(wall_tangent.x) > abs(wall_tangent.y) ? room_uv.x : room_uv.y;
		vec2 wall_uv = vec2(along_wall, 1.0 - room_surface.y / 3.0);
		texel = sample_wall(wall_variants[room], wall_uv, dFdx(wall_uv), dFdy(wall_uv));
	} else {
		texel = texture(surface_texture, UV).rgb;
	}
	float brightness = dot(texel, vec3(0.2126, 0.7152, 0.0722));
	// Texture detail modulates the room color. Floors use a darker finish.
	float finish_strength = is_wall || is_ceiling ? 1.0 : 0.96;
	vec3 finish = room_colors[room].rgb * mix(0.58, 1.08, brightness) * finish_strength;
	ALBEDO = finish * 0.10;
	EMISSION = finish * 0.72;
	SPECULAR = 0.0;
	ROUGHNESS = 0.85;
}
