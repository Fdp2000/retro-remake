shader_type spatial;

uniform sampler2D wall_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 haze_color : source_color = vec3(0.55, 0.66, 0.73);
uniform float haze_amount = 0.38;
uniform bool has_windows = true;
uniform vec3 cloud_mist : source_color;
uniform float cloud_level = -24.0;
uniform vec3 near_mist : source_color = vec3(0.76, 0.83, 0.89);

varying vec3 facade_position;
varying vec3 facade_normal;

void vertex() {
	facade_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	facade_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	bool along_x = abs(facade_normal.z) > abs(facade_normal.x);
	float across = along_x ? facade_position.x : facade_position.z;
	vec2 wall_uv = vec2(across / 9.0, -facade_position.y / 4.0);
	vec3 finish = texture(wall_texture, wall_uv).rgb;
	if (abs(facade_normal.y) > 0.5) {
		finish *= 0.67;
	} else if (has_windows) {
		vec2 bay = fract(vec2(across / 4.6, facade_position.y / 4.0));
		vec2 blur = max(fwidth(vec2(across / 4.6, facade_position.y / 4.0)), vec2(0.006));
		vec2 glass = smoothstep(vec2(0.24, 0.28) - blur, vec2(0.24, 0.28) + blur, bay);
		glass *= 1.0 - smoothstep(vec2(0.76, 0.78) - blur, vec2(0.76, 0.78) + blur, bay);
		finish = mix(finish, vec3(0.12, 0.22, 0.29), glass.x * glass.y * 0.88);
	}
	vec3 distant_color = mix(finish, haze_color, haze_amount);
	float fog_top = cloud_level + 28.0 + sin(across * 0.11) * 3.2;
	float cloud_cover = 1.0 - smoothstep(cloud_level + 2.0, fog_top, facade_position.y);
	ALBEDO = distant_color * 0.72 * (1.0 - cloud_cover);
	float mist_distance = distance(facade_position.xz, CAMERA_POSITION_WORLD.xz);
	float mist_depth = smoothstep(24.0, 215.0, mist_distance);
	vec3 base_mist = mix(near_mist, cloud_mist, mist_depth);
	EMISSION = mix(distant_color * 0.24, base_mist, cloud_cover);
	ROUGHNESS = 0.92;
	SPECULAR = 0.1;
}
