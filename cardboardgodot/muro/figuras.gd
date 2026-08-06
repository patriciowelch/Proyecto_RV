class_name Figuras

## Cada figura es un ESQUELETO (huesos + cabeza) en coordenadas del plano del
## muro (x derecha, y arriba), en las mismas unidades que la nube de landmarks.
## El mismo esqueleto talla el agujero (union de huesos, restada al muro) y
## sirve para el chequeo (cada landmark del jugador debe caer sobre algun hueso).
## Las 9 poses replican el storyboard de sticks provisto.

const CUELLO := Vector2(0.0, 1.05)
const CADERA := Vector2(0.0, -0.35)

## codo/muneca = brazos ; rodilla/tobillo = piernas ; i=izquierda d=derecha
static func _pose(nombre: String, cabeza: Vector2,
		ci: Vector2, mi: Vector2, cd: Vector2, md: Vector2,
		ri: Vector2, ti: Vector2, rd: Vector2, td: Vector2) -> Dictionary:
	return {
		"nombre": nombre,
		"cabeza": cabeza,
		"huesos": [
			[CUELLO, CADERA],
			[CUELLO, cabeza],
			[CUELLO, ci], [ci, mi],
			[CUELLO, cd], [cd, md],
			[CADERA, ri], [ri, ti],
			[CADERA, rd], [rd, td],
		],
	}

static func todas() -> Array:
	return [
		_pose("Agacharse", Vector2(-0.15, 1.65),
			Vector2(0.30, 0.55), Vector2(0.75, 0.05),
			Vector2(0.40, 0.45), Vector2(0.95, -0.05),
			Vector2(-0.20, -1.10), Vector2(-0.30, -1.90),
			Vector2(0.20, -1.10), Vector2(0.30, -1.90)),
		_pose("Correr", Vector2(0.10, 1.65),
			Vector2(-0.35, 0.65), Vector2(-0.50, 0.25),
			Vector2(0.35, 1.10), Vector2(0.45, 1.50),
			Vector2(-0.35, -1.15), Vector2(-0.70, -1.60),
			Vector2(0.45, -0.85), Vector2(0.30, -1.40)),
		_pose("Brazos a la derecha", Vector2(0.0, 1.65),
			Vector2(0.40, 1.00), Vector2(0.95, 0.95),
			Vector2(0.45, 0.90), Vector2(1.05, 0.85),
			Vector2(-0.20, -1.10), Vector2(-0.22, -1.90),
			Vector2(0.20, -1.10), Vector2(0.22, -1.90)),
		_pose("Brazos arriba en V", Vector2(0.0, 1.65),
			Vector2(-0.50, 1.40), Vector2(-0.90, 1.80),
			Vector2(0.50, 1.40), Vector2(0.90, 1.80),
			Vector2(-0.30, -1.10), Vector2(-0.40, -1.90),
			Vector2(0.30, -1.10), Vector2(0.40, -1.90)),
		_pose("Estrella (cuclillas)", Vector2(0.0, 1.65),
			Vector2(-0.55, 1.05), Vector2(-1.15, 1.10),
			Vector2(0.55, 1.05), Vector2(1.15, 1.10),
			Vector2(-0.70, -0.95), Vector2(-1.15, -1.55),
			Vector2(0.70, -0.95), Vector2(1.15, -1.55)),
		_pose("Brazos abajo en V", Vector2(0.0, 1.65),
			Vector2(-0.50, 0.55), Vector2(-0.95, 0.10),
			Vector2(0.50, 0.55), Vector2(0.95, 0.10),
			Vector2(-0.20, -1.10), Vector2(-0.22, -1.90),
			Vector2(0.20, -1.10), Vector2(0.22, -1.90)),
		_pose("Un brazo arriba (inclinado)", Vector2(-0.15, 1.65),
			Vector2(-0.30, 0.60), Vector2(-0.35, 0.10),
			Vector2(0.25, 1.40), Vector2(-0.05, 1.75),
			Vector2(-0.20, -1.10), Vector2(-0.15, -1.90),
			Vector2(0.15, -1.10), Vector2(0.20, -1.90)),
		_pose("Circulo sobre la cabeza", Vector2(0.0, 1.50),
			Vector2(-0.50, 1.35), Vector2(-0.15, 1.95),
			Vector2(0.50, 1.35), Vector2(0.15, 1.95),
			Vector2(-0.35, -1.10), Vector2(-0.50, -1.90),
			Vector2(0.35, -1.10), Vector2(0.50, -1.90)),
		_pose("Un brazo recto arriba", Vector2(0.0, 1.65),
			Vector2(-0.35, 0.60), Vector2(-0.45, 0.15),
			Vector2(0.30, 1.45), Vector2(0.50, 2.00),
			Vector2(-0.20, -1.10), Vector2(-0.20, -1.90),
			Vector2(0.20, -1.10), Vector2(0.20, -1.90)),
	]
