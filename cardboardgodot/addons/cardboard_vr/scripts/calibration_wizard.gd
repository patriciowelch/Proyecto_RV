class_name CardboardCalibrationWizard extends Node

## Asistente de calibración guiada en dos fases.
##
##   Fase 1 (IPD)   -> separa/acerca las cámaras hasta que la figura se funde
##                     en una sola imagen nítida.
##   Fase 2 (lente) -> ajusta k1/k2 del shader hasta que la cuadrícula se ve
##                     recta, sobre todo en los bordes.
##
## Nota de diseño: la UI NO va en un CanvasLayer sobre la pantalla. En un visor
## estéreo un CanvasLayer cubre los dos ojos con una sola imagen plana, así que
## no se puede fusionar y encima falsea justo lo que se está midiendo. Acá se
## renderiza una vez en un SubViewport y se espeja dentro del viewport de cada
## ojo, de modo que pasa por el mismo shader de lente que se está calibrando.

signal calibration_finished(ipd: float, k1: float, k2: float)
signal phase_changed(phase: int)

enum Phase { IPD, LENS, DONE }

const IPD_STEP := 0.02
const CONV_STEP := 0.1
const K_STEP := 0.005
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.06
const STICK_DEADZONE := 0.5
## Igual que en el menú: el mando se agarra rotado 270° antihorario.
const AXIS_ROTATION_QUARTERS := 3

## Distancia del objetivo de fusión. Tiene que ser grande comparada con la
## separación de ojos o el objetivo cae fuera del frustum de un ojo.
@export var TargetDistance : float = 30.0
@export var TargetSize : float = 10.0

var camera: Node
var lens_material: ShaderMaterial

var _phase: int = Phase.IPD
## Sin esto el asistente atendería el mando antes de haber arrancado y le
## robaría la entrada al menú de calibración.
var _active := false
## Cuál de los dos parámetros de la fase actual ajustan izquierda/derecha.
## Fase 1: separación / convergencia. Fase 2: k1 / k2.
var _selected_param := 0
var _target: MeshInstance3D
var _mirrors: Array[TextureRect] = []

var _dir := Vector2i.ZERO
var _timer_h := 0.0

@onready var _ui_viewport: SubViewport = $UIViewport
@onready var _pattern: CalibrationTestPattern = $UIViewport/WizardUI/TestPattern
@onready var _phase_label: Label = $UIViewport/WizardUI/Panel/VBox/PhaseLabel
@onready var _instruction: Label = $UIViewport/WizardUI/Panel/VBox/Instruction
@onready var _value_label: Label = $UIViewport/WizardUI/Panel/VBox/Value
@onready var _minus_button: Button = $UIViewport/WizardUI/Panel/VBox/Buttons/Minus
@onready var _plus_button: Button = $UIViewport/WizardUI/Panel/VBox/Buttons/Plus
@onready var _next_button: Button = $UIViewport/WizardUI/Panel/VBox/Buttons/Next


func _ready() -> void:
	_minus_button.pressed.connect(func(): _adjust(-1))
	_plus_button.pressed.connect(func(): _adjust(1))
	_next_button.pressed.connect(_next)
	set_process(false)
	visible_in_eyes(false)


## Arranca el asistente. `cam` debe ser el CardboardVRCamera.
func start(cam: Node) -> void:
	camera = cam
	lens_material = cam.View.get_lens_material()
	_build_mirrors()
	_build_target()
	_active = true
	_phase = Phase.IPD
	_enter_phase(_phase)
	set_process(true)
	visible_in_eyes(true)


func visible_in_eyes(v: bool) -> void:
	for m in _mirrors:
		m.visible = v
	if _target:
		_target.visible = v and _phase == Phase.IPD


## Espeja el viewport de la UI dentro de cada ojo. Un mismo nodo no puede estar
## dos veces en el árbol, así que se renderiza una vez y se muestra dos.
func _build_mirrors() -> void:
	if not _mirrors.is_empty():
		return
	for vp in camera.get_eye_viewports():
		var mirror := TextureRect.new()
		mirror.texture = _ui_viewport.get_texture()
		mirror.set_anchors_preset(Control.PRESET_FULL_RECT)
		mirror.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mirror.stretch_mode = TextureRect.STRETCH_SCALE
		mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vp.add_child(mirror)
		_mirrors.append(mirror)


## Objetivo 3D de alto contraste para juzgar la fusión binocular en la fase 1.
func _build_target() -> void:
	if _target:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(TargetSize, TargetSize)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_cross_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Sin test de profundidad: la geometría del nivel (columnas, paredes) tapaba
	# el objetivo y dejaba media cruz a la vista, que es justo lo que hay que
	# poder comparar entre los dos ojos. Conserva su posición 3D real, así que
	# la paralaje que se está calibrando sigue siendo la correcta.
	mat.no_depth_test = true
	mat.render_priority = 1

	_target = MeshInstance3D.new()
	_target.mesh = quad
	_target.material_override = mat

	var world_root: Node = camera.parent.get_parent()
	if world_root == null:
		world_root = get_tree().current_scene
	world_root.add_child(_target)
	# Alineado con el -Z del mundo, que es adonde mira la vista al recentrar.
	_target.global_position = camera.parent.global_position \
		+ Vector3(0, camera.EyeHeight, 0) \
		+ Vector3(0, 0, -TargetDistance)
	_target.global_rotation = Vector3.ZERO


func _make_cross_texture(px: int = 256) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var half := px / 2
	var thickness := int(px * 0.06)
	for y in px:
		for x in px:
			if absi(x - half) < thickness or absi(y - half) < thickness:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _enter_phase(phase: int) -> void:
	_phase = phase
	_selected_param = 0
	match phase:
		Phase.IPD:
			_phase_label.text = "Fase 1 de 2 — Distancia interpupilar"
			_instruction.text = "Ajustá hasta ver una sola figura nítida, sin doble. Arriba/abajo cambia entre separación y convergencia."
			# Sin retícula: encima del objetivo resultaba incómoda a la vista.
			_pattern.set_pattern(CalibrationTestPattern.Pattern.NONE)
			_next_button.text = "Siguiente"
			if _target:
				_target.visible = true
		Phase.LENS:
			_phase_label.text = "Fase 2 de 2 — Distorsión de lente"
			_instruction.text = "Ajustá el valor hasta que las líneas de la cuadrícula se vean rectas, especialmente en los bordes."
			_pattern.set_pattern(CalibrationTestPattern.Pattern.GRID)
			_next_button.text = "Finalizar"
			if _target:
				_target.visible = false
		Phase.DONE:
			_pattern.set_pattern(CalibrationTestPattern.Pattern.NONE)
			if _target:
				_target.visible = false
			_active = false
			visible_in_eyes(false)
			set_process(false)
	phase_changed.emit(phase)
	_refresh()


func _refresh() -> void:
	match _phase:
		Phase.IPD:
			var sel_sep := "> " if _selected_param == 0 else "   "
			var sel_conv := "> " if _selected_param == 1 else "   "
			_value_label.text = "%sSeparación: %.3f\n%sConvergencia: %.2f°" % [
				sel_sep, camera.EyesSeparation, sel_conv, camera.EyeConvergencyAngle]
		Phase.LENS:
			var k1: float = lens_material.get_shader_parameter("k1")
			var k2: float = lens_material.get_shader_parameter("k2")
			var sel_k1 := "> " if _selected_param == 0 else "   "
			var sel_k2 := "> " if _selected_param == 1 else "   "
			_value_label.text = "%sk1: %.3f\n%sk2: %.3f" % [sel_k1, k1, sel_k2, k2]


func _adjust(dir: int) -> void:
	match _phase:
		Phase.IPD:
			if _selected_param == 0:
				camera.EyesSeparation = clampf(
					camera.EyesSeparation + dir * IPD_STEP, 0.0, 5.0)
			else:
				# La convergencia rota cada ojo hacia adentro. Con separación 0
				# sigue habiendo doble imagen si este ángulo no es el correcto,
				# así que tiene que ser ajustable acá o la fase no cierra.
				camera.EyeConvergencyAngle = clampf(
					camera.EyeConvergencyAngle + dir * CONV_STEP, -30.0, 30.0)
			camera.apply_eye_transform()
		Phase.LENS:
			var key := "k1" if _selected_param == 0 else "k2"
			var v: float = lens_material.get_shader_parameter(key)
			lens_material.set_shader_parameter(key, clampf(v + dir * K_STEP, -1.0, 1.0))
	_refresh()


func _next() -> void:
	match _phase:
		Phase.IPD:
			_enter_phase(Phase.LENS)
		Phase.LENS:
			_enter_phase(Phase.DONE)
			calibration_finished.emit(
				camera.EyesSeparation,
				lens_material.get_shader_parameter("k1"),
				lens_material.get_shader_parameter("k2"))


func _back() -> void:
	if _phase == Phase.LENS:
		_enter_phase(Phase.IPD)


func _input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventKey and event.pressed:
		var arrow := Vector2.ZERO
		match event.keycode:
			KEY_LEFT: arrow = Vector2.LEFT
			KEY_RIGHT: arrow = Vector2.RIGHT
			KEY_UP: arrow = Vector2.UP
			KEY_DOWN: arrow = Vector2.DOWN
		if arrow != Vector2.ZERO:
			_dispatch(_rotate(arrow))
			get_viewport().set_input_as_handled()
			return
		if event.echo:
			return
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_next()
			KEY_BACKSPACE, KEY_ESCAPE:
				_back()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A:
				_next()
			JOY_BUTTON_B:
				_back()
			JOY_BUTTON_X:
				_adjust(-1)
			JOY_BUTTON_Y:
				_adjust(1)


## Izquierda/derecha ajusta el parámetro elegido; arriba/abajo alterna entre los
## dos parámetros de la fase actual.
func _dispatch(v: Vector2) -> void:
	if absf(v.y) > absf(v.x):
		_selected_param = 1 - _selected_param
		_refresh()
	elif absf(v.x) > 0.0:
		_adjust(1 if v.x > 0.0 else -1)


func _rotate(v: Vector2) -> Vector2:
	var out := v
	for _i in AXIS_ROTATION_QUARTERS:
		out = Vector2(out.y, -out.x)
	return out


func _raw_direction() -> Vector2:
	var v := Vector2.ZERO
	for device in Input.get_connected_joypads():
		var stick := Vector2(
			Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
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


func _process(delta: float) -> void:
	var v := _rotate(_raw_direction())
	var h := 0
	var ver := 0
	if absf(v.x) > STICK_DEADZONE:
		h = signi(int(signf(v.x)))
	if absf(v.y) > STICK_DEADZONE:
		ver = signi(int(signf(v.y)))

	# Vertical alterna el parámetro. Solo por flanco: repetir un conmutador de
	# dos estados lo haría parpadear mientras se mantiene la dirección.
	if ver != _dir.y:
		_dir.y = ver
		if ver != 0:
			_selected_param = 1 - _selected_param
			_refresh()

	if h != _dir.x:
		_dir.x = h
		_timer_h = REPEAT_DELAY
		if h != 0:
			_adjust(h)
	elif h != 0:
		_timer_h -= delta
		if _timer_h <= 0.0:
			_timer_h = REPEAT_RATE
			_adjust(h)
