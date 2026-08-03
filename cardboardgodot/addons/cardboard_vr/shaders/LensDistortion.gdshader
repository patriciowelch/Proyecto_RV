shader_type canvas_item;

// Corrección de distorsión de lente para Cardboard.
//
// Modelo de Brown-Conrady con los dos primeros términos radiales (k1 y k2):
//
//     r' = r * (1 + k1*r^2 + k2*r^4)
//
// La lente física del visor produce distorsión de cojín (pincushion), así que
// para contrarrestarla se pre-deforma la imagen en barril: con k1 y k2
// POSITIVOS el muestreo se estira hacia los bordes y las líneas rectas del
// mundo se ven rectas a través de la lente.
//
// Se aplica sobre la textura de cada ojo por separado, en espacio de pantalla,
// que es donde vive la distorsión óptica.

uniform float k1 : hint_range(-1.0, 1.0) = 0.0;
uniform float k2 : hint_range(-1.0, 1.0) = 0.0;

// Relación de aspecto (ancho/alto) del rectángulo de un ojo. Sin corregirla el
// radio se mide en UV no cuadradas y la distorsión sale elíptica, no radial.
uniform float aspect : hint_range(0.1, 4.0) = 1.0;

// Reescala la imagen para recuperar campo de visión: al pre-deformar en barril
// los bordes se van fuera del rectángulo y aparecerían recortados en negro.
uniform float scale : hint_range(0.1, 2.0) = 1.0;

// Centro óptico de la lente en UV. Rara vez cae justo en el medio del panel.
uniform vec2 center = vec2(0.5, 0.5);

void fragment() {
	vec2 uv = UV - center;
	uv.x *= aspect;

	float r2 = dot(uv, uv);
	float f = 1.0 + k1 * r2 + k2 * r2 * r2;

	vec2 src = uv * f * scale;
	src.x /= aspect;
	src += center;

	if (src.x < 0.0 || src.x > 1.0 || src.y < 0.0 || src.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = texture(TEXTURE, src);
	}
}
