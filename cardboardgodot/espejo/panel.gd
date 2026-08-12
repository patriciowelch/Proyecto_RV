extends CanvasLayer

## Panel de control del espejo: modo sentado/parado y editor de poses.
##
## Vive solo en la PC (ver rol.gd). Todo lo que se toca acá se aplica localmente
## para verlo al instante y se publica por el WebSocket que ya está abierto, así
## que el visor queda al día sin ningún canal nuevo.
##
## El editor trabajo en UNIDADES DE FIGURA, las mismas en las que está escrito el
## storyboard: de cada articulación se usa solo la dirección respecto de su padre,
## y los largos salen de las proporciones medidas. Por eso arrastrar un codo
## cambia el ÁNGULO del brazo y no su largo — que es justamente lo que se quiere
## editar, y por qué el editor tiene que dibujar la figura reconstruida y no los
## puntos crudos.

signal cambio_config(cfg: Dictionary)
signal cambio_poses(poses: Array)

## Nombres de los 9 puntos editables, en el orden de Figuras.a_datos.
const PUNTOS := ["cabeza", "codo izq", "muñeca izq", "codo der", "muñeca der",
	"rodilla izq", "tobillo izq", "rodilla der", "tobillo der"]

var _poses: Array = []            # poses en formato datos planos
var _sel := 0
var _arrastrando := -1

var _lista: ItemList
var _lienzo: Control
var _nombre: LineEdit
var _chk_sentado: CheckBox
var _alza: HSlider
var _alza_txt: Label
var _apertura: HSlider
var _apertura_txt: Label


func _ready() -> void:
	layer = 20
	visible = false
	_poses = Figuras.lista_a_datos(Figuras.todas())
	_construir()
	_refrescar_lista()


func alternar() -> void:
	visible = not visible
	if visible:
		_refrescar_lista()


# --- Construcción de la interfaz ----------------------------------------------

func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0.05, 0.05, 0.07, 0.93)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)

	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.add_theme_constant_override("separation", 16)
	fondo.add_child(cols)

	var izq := VBoxContainer.new()
	izq.custom_minimum_size = Vector2(260, 0)
	cols.add_child(izq)
	_construir_columna_izquierda(izq)

	_lienzo = Control.new()
	_lienzo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lienzo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lienzo.draw.connect(_dibujar_lienzo)
	_lienzo.gui_input.connect(_input_lienzo)
	cols.add_child(_lienzo)


func _construir_columna_izquierda(caja: VBoxContainer) -> void:
	caja.add_child(_titulo("MODO DEL JUGADOR"))

	_chk_sentado = CheckBox.new()
	_chk_sentado.text = "Jugador sentado"
	_chk_sentado.tooltip_text = "Piernas juntas y vertical anclada en la cadera"
	_chk_sentado.button_pressed = Figuras.sentado
	_chk_sentado.toggled.connect(func(_v): _publicar_config())
	caja.add_child(_chk_sentado)

	_alza_txt = Label.new()
	caja.add_child(_alza_txt)
	_alza = _slider(caja, -0.5, 1.0, 0.01, Figuras.alza_cadera)

	_apertura_txt = Label.new()
	caja.add_child(_apertura_txt)
	_apertura = _slider(caja, 0.0, 1.0, 0.01, Figuras.apertura_piernas)
	_actualizar_textos()

	caja.add_child(HSeparator.new())
	caja.add_child(_titulo("POSES"))

	_lista = ItemList.new()
	_lista.custom_minimum_size = Vector2(0, 240)
	_lista.item_selected.connect(_seleccionar)
	caja.add_child(_lista)

	_nombre = LineEdit.new()
	_nombre.placeholder_text = "nombre de la pose"
	_nombre.text_submitted.connect(func(t): _renombrar(t))
	caja.add_child(_nombre)

	var fila := HBoxContainer.new()
	caja.add_child(fila)
	fila.add_child(_boton("Nueva", _nueva))
	fila.add_child(_boton("Duplicar", _duplicar))
	fila.add_child(_boton("Borrar", _borrar))

	caja.add_child(HSeparator.new())
	caja.add_child(_boton("Aplicar y enviar al visor", _publicar_poses))
	caja.add_child(_boton("Volver al storyboard", _restaurar))

	var ayuda := Label.new()
	ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ayuda.text = "Arrastrá las articulaciones en el panel derecho. Se edita el ángulo de cada segmento; el largo sale de las proporciones medidas.\n\nTAB cierra el panel."
	ayuda.modulate = Color(0.7, 0.7, 0.75)
	caja.add_child(ayuda)


func _titulo(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = Color(1, 0.9, 0.4)
	return l


func _boton(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b


func _slider(caja: VBoxContainer, desde: float, hasta: float, paso: float,
		valor: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = desde
	s.max_value = hasta
	s.step = paso
	s.value = valor
	s.value_changed.connect(func(_v): _publicar_config())
	caja.add_child(s)
	return s


func _actualizar_textos() -> void:
	_alza_txt.text = "Alza de cadera: %.2f torsos" % _alza.value
	_apertura_txt.text = "Apertura de piernas: %.2f" % _apertura.value


# --- Lista de poses ------------------------------------------------------------

func _refrescar_lista() -> void:
	_lista.clear()
	for p in _poses:
		_lista.add_item(String(p.get("nombre", "sin nombre")))
	_sel = clampi(_sel, 0, maxi(0, _poses.size() - 1))
	if _poses.size() > 0:
		_lista.select(_sel)
		_nombre.text = String(_poses[_sel].get("nombre", ""))
	_lienzo.queue_redraw()


func _seleccionar(i: int) -> void:
	_sel = i
	_nombre.text = String(_poses[_sel].get("nombre", ""))
	_lienzo.queue_redraw()


func _renombrar(t: String) -> void:
	if _poses.is_empty():
		return
	_poses[_sel]["nombre"] = t
	_refrescar_lista()


func _nueva() -> void:
	# Pose de pie con los brazos abajo: un punto de partida neutro para editar.
	_poses.append(Figuras.a_datos(Figuras.storyboard()[2]))
	_poses[-1]["nombre"] = "nueva %d" % _poses.size()
	_sel = _poses.size() - 1
	_refrescar_lista()


func _duplicar() -> void:
	if _poses.is_empty():
		return
	var copia := (_poses[_sel] as Dictionary).duplicate(true)
	copia["nombre"] = String(copia.get("nombre", "")) + " (copia)"
	_poses.insert(_sel + 1, copia)
	_sel += 1
	_refrescar_lista()


func _borrar() -> void:
	if _poses.size() <= 1:
		return          # sin poses el juego no tiene con qué armar muros
	_poses.remove_at(_sel)
	_refrescar_lista()


func _restaurar() -> void:
	_poses = Figuras.lista_a_datos(Figuras.storyboard())
	_sel = 0
	_refrescar_lista()
	_publicar_poses()


# --- Lienzo de edición ---------------------------------------------------------

## Figura -> pixeles. La figura va de y_pies a y_corona; se encaja en el alto del
## lienzo con un margen y se centra en x.
func _escala_lienzo() -> float:
	var alto := Figuras.y_corona() - Figuras.y_pies()
	return (_lienzo.size.y * 0.86) / maxf(alto, 0.001)

func _a_pixel(p: Vector2) -> Vector2:
	var k := _escala_lienzo()
	var centro := _lienzo.size * 0.5
	return Vector2(centro.x + p.x * k, centro.y - (p.y - Figuras.CADERA.y) * k)

func _a_figura(px: Vector2) -> Vector2:
	var k := _escala_lienzo()
	var centro := _lienzo.size * 0.5
	return Vector2((px.x - centro.x) / k, Figuras.CADERA.y - (px.y - centro.y) / k)


func _dibujar_lienzo() -> void:
	if _poses.is_empty():
		return
	var pose := Figuras.de_datos(_poses[_sel])
	if pose.is_empty():
		return

	# Piso y eje, para saber dónde queda parada la figura.
	var y_piso := _a_pixel(Vector2(0, Figuras.y_pies())).y
	_lienzo.draw_line(Vector2(0, y_piso), Vector2(_lienzo.size.x, y_piso),
		Color(0.4, 0.4, 0.5), 2.0)
	var x_eje := _a_pixel(Vector2.ZERO).x
	_lienzo.draw_line(Vector2(x_eje, 0), Vector2(x_eje, _lienzo.size.y),
		Color(0.2, 0.2, 0.28), 1.0)

	# El esqueleto RECONSTRUIDO, que es lo que va a tallar el muro: con los
	# largos anatómicos y, si está activo, con las piernas juntas del modo
	# sentado. Dibujar los puntos crudos del storyboard mentiría.
	var nodos: Array = Figuras.landmarks_figura(pose)
	for h in Figuras.HUESOS:
		_lienzo.draw_line(_a_pixel(nodos[h[0]]), _a_pixel(nodos[h[1]]),
			Color(0.35, 0.75, 1.0), 5.0)
	for i in nodos.size():
		var col := Color(0.3, 0.9, 0.45)
		if Figuras.sentado and Figuras.IDX_PIERNAS.has(i):
			col = Color(0.45, 0.45, 0.5)      # no se chequea en sentado
		_lienzo.draw_circle(_a_pixel(nodos[i]), 7.0, col)

	# Los tiradores: los 9 puntos crudos de la pose, que son los que se arrastran.
	for i in PUNTOS.size():
		var p := _punto(i)
		var c := _a_pixel(p)
		var activo := i == _arrastrando
		_lienzo.draw_circle(c, 11.0, Color(1, 0.85, 0.2, 0.85 if activo else 0.5))
		_lienzo.draw_string(ThemeDB.fallback_font, c + Vector2(14, 4),
			PUNTOS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 1, 1, 0.75))


func _punto(i: int) -> Vector2:
	var a: Array = _poses[_sel]["pts"]
	return Vector2(float(a[i * 2]), float(a[i * 2 + 1]))


func _mover_punto(i: int, p: Vector2) -> void:
	var a: Array = _poses[_sel]["pts"]
	a[i * 2] = snappedf(p.x, 0.01)
	a[i * 2 + 1] = snappedf(p.y, 0.01)


func _input_lienzo(event: InputEvent) -> void:
	if _poses.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_arrastrando = _tirador_cerca(event.position)
		else:
			_arrastrando = -1
		_lienzo.queue_redraw()
	elif event is InputEventMouseMotion and _arrastrando >= 0:
		_mover_punto(_arrastrando, _a_figura(event.position))
		_lienzo.queue_redraw()


func _tirador_cerca(px: Vector2) -> int:
	var mejor := -1
	var mejor_d := 22.0
	for i in PUNTOS.size():
		var d := _a_pixel(_punto(i)).distance_to(px)
		if d < mejor_d:
			mejor_d = d
			mejor = i
	return mejor


# --- Publicación ---------------------------------------------------------------

func _publicar_config() -> void:
	_actualizar_textos()
	var cfg := {
		"sentado": _chk_sentado.button_pressed,
		"alza": _alza.value,
		"apertura": _apertura.value,
	}
	cambio_config.emit(cfg)
	_lienzo.queue_redraw()


func _publicar_poses() -> void:
	cambio_poses.emit(_poses.duplicate(true))
