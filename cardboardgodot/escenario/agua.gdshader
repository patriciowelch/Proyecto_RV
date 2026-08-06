shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Agua fake y barata para Cardboard movil: olas por vertice + normal analitica.
// Sin refraccion ni SCREEN_TEXTURE (caro/no disponible en el renderer compatibility).

uniform vec4 color_shallow : source_color = vec4(0.16, 0.56, 0.60, 0.55);
uniform vec4 color_deep : source_color = vec4(0.0, 0.28, 0.42, 0.82);
uniform float wave_speed = 0.6;
uniform float wave_height = 0.04;
uniform float wave_freq = 1.2;

varying float v_h;

float wsum(vec2 p, float t) {
	return sin(p.x * wave_freq + t) * 0.5 + sin(p.y * wave_freq * 0.85 + t * 1.25) * 0.5;
}

void vertex() {
	float t = TIME * wave_speed;
	float h = wsum(VERTEX.xz, t);
	VERTEX.y += h * wave_height;
	v_h = h;
	float dx = cos(VERTEX.x * wave_freq + t) * 0.5 * wave_freq * wave_height;
	float dz = cos(VERTEX.z * wave_freq * 0.85 + t * 1.25) * 0.5 * wave_freq * 0.85 * wave_height;
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	float m = clamp(v_h * 0.5 + 0.5, 0.0, 1.0);
	vec4 col = mix(color_deep, color_shallow, m);
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
