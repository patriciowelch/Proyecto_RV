class_name CardboardCalibrationMenu extends Control

## Menú de calibración Cardboard: se superpone sobre el ojo izquierdo.
##
## Los 4 botones del mando llegan como botones de joystick (0..3), no como
## teclas:
##
##   botón 1 (B)     -> abrir / cerrar el menú (al cerrar, guarda)
##   botón 0 (A)     -> resetear el parámetro seleccionado
##   botones 2/3     -> ajustar el valor (- / +)
##   desplazamiento  -> arriba/abajo elige, izq/der ajusta (mantener repite)
##
## También se aceptan teclado (flechas, Enter/Space, Esc/Backspace) y el botón
## BACK de Android, para poder probar sin el mando.

const SAVE_PATH := "user://cardboard_calibration.cfg"
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.06
const STICK_DEADZONE := 0.5

## Rotación aplicada al desplazamiento, en cuartos de vuelta antihorarios.
## 3 = 270°, la orientación que coincide con la forma real de agarrar el mando.
## Es fija a propósito: no se expone en el menú para no desconfigurarla sin
## querer y quedarse sin poder navegar.
const AXIS_ROTATION_QUARTERS := 3

var camera: Node
var lens_material: ShaderMaterial
## Panel 3D que muestra este menú. Se oculta/muestra él, no este Control: si se
## ocultara el Control, el SubViewport dejaría de renderizar y el panel
## quedaría con la última imagen congelada.
var world_panel: Node3D

var param_defs := [
	{"key": "eye_separation", "label": "Separación de ojos", "min": 0.0, "max": 2.0, "step": 0.005},
	{"key": "eye_height", "label": "Altura de ojos", "min": 0.0, "max": 3.0, "step": 0.02},
	{"key": "convergence", "label": "Ángulo de convergencia", "min": -30.0, "max": 30.0, "step": 0.5},
	{"key": "use_gyro", "label": "Usar giroscopio", "bool": true},
	{"key": "gyro_sens", "label": "Sensibilidad giroscopio", "min": 0.001, "max": 0.2, "step": 0.001},
	{"key": "mouse_sens", "label": "Sensibilidad mouse", "min": 0.0005, "max": 0.02, "step": 0.0005},
	{"key": "lens_k1", "label": "Distorsión lente k1", "min": -1.0, "max": 1.0, "step": 0.005},
	{"key": "lens_k2", "label": "Distorsión lente k2", "min": -1.0, "max": 1.0, "step": 0.005},
	{"key": "lens_scale", "label": "Escala de lente", "min": 0.5, "max": 1.5, "step": 0.01},
]

var _defaults: Array = []
var _row_labels: Array[Label] = []
var _selected := 0
var _menu_open := false
var _last_input := "-"

# Estado de repetición del desplazamiento analógico.
var _dir := Vector2i.ZERO
var _timer_h := 0.0
var _timer_v := 0.0

@onready var _list: VBoxContainer = $Panel/VBox/List
@onready var _debug: Label = $Panel/VBox/Debug


func setup(cam: Node, mat: ShaderMaterial, panel: Node3D = null) -> void:
	camera = cam
	lens_material = mat
	world_panel = panel
	_build_rows()
	for i in param_defs.size():
		_defaults.append(_get_value(i))
	_load()
	_menu_open = false
	if world_panel:
		world_panel.visible = false
	_refresh()


func _build_rows() -> void:
	for child in _list.get_children():
		child.queue_free()
	_row_labels.clear()
	for def in param_defs:
		var l := Label.new()
		l.text = def["label"]
		_list.add_child(l)
		_row_labels.append(l)


## El botón BACK de Android llega como notificación, no como tecla.
## project.godot tiene quit_on_go_back=false para que no cierre la app.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle()


func _input(event: InputEvent) -> void:
	# Registro de la última entrada recibida: sirve para mapear el mando a ciegas.
	if event is InputEventKey and event.pressed:
		_last_input = "tecla %s (%d)" % [
			OS.get_keycode_string(event.keycode), event.keycode
		]
		_refresh()
	elif event is InputEventJoypadButton and event.pressed:
		_last_input = "botón joy %d" % event.button_index
		_refresh()

	if event is InputEventKey and event.pressed:
		# Las flechas se atienden por evento (no por polling) para no perder
		# pulsaciones cortas; se permite el echo del sistema como repetición.
		var arrow := Vector2.ZERO
		match event.keycode:
			KEY_LEFT: arrow = Vector2.LEFT
			KEY_RIGHT: arrow = Vector2.RIGHT
			KEY_UP: arrow = Vector2.UP
			KEY_DOWN: arrow = Vector2.DOWN
		if arrow != Vector2.ZERO:
			if _menu_open:
				_dispatch(_rotate(arrow))
				get_viewport().set_input_as_handled()
			return

		if event.echo:
			return
		match event.keycode:
			KEY_BACKSPACE, KEY_ESCAPE, KEY_BACK:
				_toggle()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if _menu_open:
					_set_value(_selected, _defaults[_selected])
					_refresh()
					get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		# El mando IVRA07 entrega sus 4 botones como joy 0..3 (A, B, X, Y),
		# no como teclas, así que se mapean por índice de joystick.
		match event.button_index:
			JOY_BUTTON_B, JOY_BUTTON_START, JOY_BUTTON_BACK:
				_toggle()
			JOY_BUTTON_A:
				if _menu_open:
					_set_value(_selected, _defaults[_selected])
					_refresh()
			JOY_BUTTON_X:
				if _menu_open:
					_step(-1)
			JOY_BUTTON_Y:
				if _menu_open:
					_step(1)


func _toggle() -> void:
	_menu_open = not _menu_open
	if world_panel:
		world_panel.visible = _menu_open
	if not _menu_open:
		_save()
	_refresh()


## Aplica una dirección ya rotada: vertical elige, horizontal ajusta.
func _dispatch(v: Vector2) -> void:
	if absf(v.y) > absf(v.x):
		_move_selection(1 if v.y > 0.0 else -1)
	elif absf(v.x) > 0.0:
		_step(1 if v.x > 0.0 else -1)


## Lee el desplazamiento crudo del stick y el d-pad, sin rotar.
## Las flechas se manejan aparte, por evento, en _input().
func _raw_direction() -> Vector2:
	var v := Vector2.ZERO
	for device in Input.get_connected_joypads():
		var stick := Vector2(
			Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
		)
		if stick.length() > STICK_DEADZONE:
			v += stick
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
			v.x -= 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
			v.x += 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
			v.y -= 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
			v.y += 1.0
	return v


## Rota el vector en cuartos de vuelta antihorarios. En coordenadas de pantalla
## (y hacia abajo) un cuarto antihorario es (x, y) -> (y, -x).
func _rotate(v: Vector2) -> Vector2:
	var out := v
	for _i in AXIS_ROTATION_QUARTERS:
		out = Vector2(out.y, -out.x)
	return out


func _process(delta: float) -> void:
	if not _menu_open:
		return

	var v := _rotate(_raw_direction())
	var h := 0
	var ver := 0
	if absf(v.x) > STICK_DEADZONE:
		h = signi(int(signf(v.x)))
	if absf(v.y) > STICK_DEADZONE:
		ver = signi(int(signf(v.y)))

	# Vertical: cambia el parámetro seleccionado.
	if ver != _dir.y:
		_dir.y = ver
		_timer_v = REPEAT_DELAY
		if ver != 0:
			_move_selection(ver)
	elif ver != 0:
		_timer_v -= delta
		if _timer_v <= 0.0:
			_timer_v = REPEAT_RATE
			_move_selection(ver)

	# Horizontal: ajusta el valor.
	if h != _dir.x:
		_dir.x = h
		_timer_h = REPEAT_DELAY
		if h != 0:
			_step(h)
	elif h != 0:
		_timer_h -= delta
		if _timer_h <= 0.0:
			_timer_h = REPEAT_RATE
			_step(h)


func _move_selection(dir: int) -> void:
	_selected = (_selected + dir + param_defs.size()) % param_defs.size()
	_refresh()


func _step(dir: int) -> void:
	var def = param_defs[_selected]
	if def.has("bool"):
		_set_value(_selected, not _get_value(_selected))
	else:
		var v = _get_value(_selected) + dir * def["step"]
		_set_value(_selected, clamp(v, def["min"], def["max"]))
	_refresh()


func _refresh() -> void:
	for i in param_defs.size():
		var def = param_defs[i]
		var v = _get_value(i)
		var value_text: String
		if def.has("bool"):
			value_text = "sí" if v else "no"
		else:
			value_text = "%.4f" % v
		var prefix = "> " if i == _selected else "   "
		_row_labels[i].text = "%s%s: %s" % [prefix, def["label"], value_text]
		_row_labels[i].modulate = Color(1, 1, 0.4) if i == _selected else Color(1, 1, 1)
	if _debug:
		_debug.text = "última entrada: %s" % _last_input


func _get_value(i: int):
	match param_defs[i]["key"]:
		"eye_separation": return camera.EyesSeparation
		"eye_height": return camera.EyeHeight
		"convergence": return camera.EyeConvergencyAngle
		"use_gyro": return camera.UseGysroscope
		"gyro_sens": return camera.GysroscopeFactor
		"mouse_sens": return camera.Mouse_Sensitivity
		"lens_k1": return lens_material.get_shader_parameter("k1")
		"lens_k2": return lens_material.get_shader_parameter("k2")
		"lens_scale": return lens_material.get_shader_parameter("scale")
	return 0


func _set_value(i: int, v) -> void:
	match param_defs[i]["key"]:
		"eye_separation":
			camera.EyesSeparation = v
			camera.apply_eye_transform()
		"eye_height":
			camera.EyeHeight = v
		"convergence":
			camera.EyeConvergencyAngle = v
			camera.apply_eye_transform()
		"use_gyro":
			camera.UseGysroscope = v
		"gyro_sens":
			camera.GysroscopeFactor = v
		"mouse_sens":
			camera.Mouse_Sensitivity = v
		"lens_k1":
			lens_material.set_shader_parameter("k1", v)
		"lens_k2":
			lens_material.set_shader_parameter("k2", v)
		"lens_scale":
			lens_material.set_shader_parameter("scale", v)


func _save() -> void:
	var cfg := ConfigFile.new()
	for i in param_defs.size():
		cfg.set_value("cardboard", param_defs[i]["key"], _get_value(i))
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for i in param_defs.size():
		var key = param_defs[i]["key"]
		if cfg.has_section_key("cardboard", key):
			_set_value(i, cfg.get_value("cardboard", key))
