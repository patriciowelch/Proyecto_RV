class_name Figuras

## Figuras (agujeros) como poligono 2D en el plano XY del muro, en las mismas
## unidades que la nube de landmarks. Cada figura deberia corresponder a una
## pose humana alcanzable. El mismo poligono se usa para tallar el muro (CSG)
## y para el chequeo punto-en-poligono.

# Parado, brazos al cuerpo (rectangulo alto que incluye la cabeza).
const PARADO := PackedVector2Array([
	Vector2(-0.7, 1.8), Vector2(0.7, 1.8),
	Vector2(0.7, -2.3), Vector2(-0.7, -2.3),
])

# Brazos en cruz (forma de T).
const BRAZOS_EN_T := PackedVector2Array([
	Vector2(0.0, 1.9), Vector2(0.55, 1.5), Vector2(0.55, 1.15),
	Vector2(2.1, 1.15), Vector2(2.1, 0.65), Vector2(0.55, 0.65),
	Vector2(0.55, -2.3), Vector2(-0.55, -2.3), Vector2(-0.55, 0.65),
	Vector2(-2.1, 0.65), Vector2(-2.1, 1.15), Vector2(-0.55, 1.15),
	Vector2(-0.55, 1.5),
])

# Salto de estrella: brazos arriba en diagonal, piernas abiertas (forma de X).
const ESTRELLA := PackedVector2Array([
	Vector2(0.0, 2.0), Vector2(0.5, 1.4),
	Vector2(2.0, 1.7), Vector2(0.85, 0.5),
	Vector2(1.5, -2.3), Vector2(0.2, -0.7),
	Vector2(-0.2, -0.7), Vector2(-1.5, -2.3),
	Vector2(-0.85, 0.5), Vector2(-2.0, 1.7),
	Vector2(-0.5, 1.4),
])

static func todas() -> Array:
	return [PARADO, BRAZOS_EN_T, ESTRELLA]

static func aleatoria() -> PackedVector2Array:
	var t := todas()
	return t[randi() % t.size()]
