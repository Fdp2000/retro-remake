shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;

uniform vec3 cloud_mist : source_color = vec3(0.82, 0.88, 0.93);
uniform vec3 near_mist : source_color = vec3(0.76, 0.83, 0.89);

varying vec3 deck_position;

void vertex() {
	deck_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float distance_to_camera = distance(deck_position.xz, CAMERA_POSITION_WORLD.xz);
	float distance_mist = smoothstep(24.0, 215.0, distance_to_camera);
	vec3 mist = mix(near_mist, cloud_mist, distance_mist);
	// Broad, low-contrast variation keeps the deck from reading as a flat texture.
	float variation = sin(dot(deck_position.xz, vec2(0.019, 0.013)));
	variation += 0.5 * cos(dot(deck_position.xz, vec2(-0.007, 0.023)));
	ALBEDO = mist + vec3(variation * 0.009 * (1.0 - distance_mist));
	// Fade out before the mesh boundary so it blends into the sky at the horizon.
	ALPHA = 1.0 - smoothstep(195.0, 410.0, distance_to_camera);
}
