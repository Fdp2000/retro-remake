shader_type canvas_item;

void fragment() {
	vec4 image = texture(TEXTURE, UV);
	float tone = dot(image.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 surveillance = mix(image.rgb, tone * vec3(0.92, 0.98, 1.05), 0.28);
	float vignette = smoothstep(0.32, 0.74, length(UV - vec2(0.5)));
	float line = 0.985 + 0.015 * cos(UV.y * 540.0 * 3.14159);
	COLOR = vec4(surveillance * (1.0 - vignette * 0.21) * line, image.a);
}
