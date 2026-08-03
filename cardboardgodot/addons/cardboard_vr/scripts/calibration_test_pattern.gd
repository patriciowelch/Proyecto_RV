class_name CalibrationTestPattern extends Control

## Patrones de prueba dibujados en espacio de pantalla, dentro del viewport de
## cada ojo. Se dibujan acá y no en el mundo 3D a propósito: la distorsión de
## lente es un efecto de pantalla, así que el patrón tiene que pasar por el
## mismo shader que se está calibrando para que juzgar "¿está recto?" tenga
## sentido.

enum Pattern { NONE, CROSS, GRID }

@export var pattern : Pattern = Pattern.NONE
@export var line_color : Color = Color(0.2, 1.0, 0.2)
@export var cell_size : float = 64.0
@export var line_width : float = 2.0


func set_pattern(p: Pattern) -> void:
	pattern = p
	queue_redraw()


func _draw() -> void:
	match pattern:
		Pattern.GRID:
			_draw_grid()
		Pattern.CROSS:
			_draw_cross()


## Cuadrícula trazada desde el centro hacia afuera: el shader distorsiona
## radialmente respecto del centro óptico, así que las líneas tienen que estar
## alineadas con ese mismo centro para que la curvatura se lea simétrica.
func _draw_grid() -> void:
	var c := size * 0.5
	var i := 0
	while c.x + i * cell_size <= size.x:
		var dx := i * cell_size
		draw_line(Vector2(c.x + dx, 0), Vector2(c.x + dx, size.y), line_color, line_width)
		draw_line(Vector2(c.x - dx, 0), Vector2(c.x - dx, size.y), line_color, line_width)
		i += 1
	i = 0
	while c.y + i * cell_size <= size.y:
		var dy := i * cell_size
		draw_line(Vector2(0, c.y + dy), Vector2(size.x, c.y + dy), line_color, line_width)
		draw_line(Vector2(0, c.y - dy), Vector2(size.x, c.y - dy), line_color, line_width)
		i += 1


## Retícula central de alto contraste, como referencia de fusión binocular.
func _draw_cross() -> void:
	var c := size * 0.5
	var arm := minf(size.x, size.y) * 0.12
	draw_line(Vector2(c.x - arm, c.y), Vector2(c.x + arm, c.y), line_color, line_width)
	draw_line(Vector2(c.x, c.y - arm), Vector2(c.x, c.y + arm), line_color, line_width)
	draw_arc(c, arm * 0.55, 0.0, TAU, 48, line_color, line_width)
