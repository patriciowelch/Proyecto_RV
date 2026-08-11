class_name CardboardVRCamera extends Camera3D

@export var Active : bool = true
@export_category("Controls")
@export var UseGysroscope : bool = true
@export var Mouse_Sensitivity : float = 0.003
@export var GysroscopeFactor : float = 0.024
@export var RotateParent : bool = true
@export var Handle_Mouse_Capture : bool = true
@export var Input_Cancel : String  = "ui_cancel"
## Botón del mando que recentra la vista. En el IVRA07 el 9 es el gatillo que
## Godot expone como JOY_BUTTON_LEFT_SHOULDER.
@export var Input_Recenter_Joy_Button : int = JOY_BUTTON_LEFT_SHOULDER
## Botón que lanza el asistente de calibración guiada. El 10 del IVRA07 es el
## que Godot expone como JOY_BUTTON_RIGHT_SHOULDER.
@export var Input_Wizard_Joy_Button : int = JOY_BUTTON_RIGHT_SHOULDER

@export_category("Eyes")
@export_range(0.0, 2.0) var EyesSeparation : float = 0.0
## Altura de los ojos sobre el piso, en metros. El Player está apoyado en y=0,
## así que este valor es directamente la altura de la cabeza.
@export_range(0, 5.0) var EyeHeight : float =  1.75
@export_range(-360, 360) var EyeConvergencyAngle : float =  8.9

@export_category("Menú de calibración")
## Distancia del panel de calibración frente a la posición inicial. Tiene que
## ser grande comparada con EyesSeparation: los ojos están en x = ±Separación,
## así que un panel cercano cae fuera del frustum de un ojo y se ve en uno solo.
@export var MenuDistance : float = 30.0
## Escala del panel: unidades de mundo por píxel del viewport del menú.
@export var MenuPixelSize : float = 0.03

const MENU_VIEWPORT_SIZE := Vector2i(600, 640)

var viewScene = preload("res://addons/cardboard_vr/scenes/CardboardView.tscn")
var menuScene = preload("res://addons/cardboard_vr/scenes/CalibrationMenu.tscn")
var wizardScene = preload("res://addons/cardboard_vr/scenes/CalibrationWizard.tscn")
var MenuViewport : SubViewport
var MenuPanel : Sprite3D
var Wizard : Node
var left_camera_3d: Camera3D = Camera3D.new()
var right_camera_3d: Camera3D = Camera3D.new()
var LeftEyePivot : Node3D = Node3D.new()
var RightEyePivot : Node3D = Node3D.new()
var View : CardboardView
var LeftEyeSubViewPort : SubViewport = SubViewport.new()
var RightEyeSubViewPort : SubViewport = SubViewport.new()
var parent : CharacterBody3D = get_parent()

## Orientación del cuerpo al arrancar, para poder volver a ella al recentrar.
var _initial_parent_rotation : Vector3 = Vector3.ZERO
## Hacia dónde mira el cuerpo tal como quedó puesto en la escena, y su yaw.
## Los pivotes de ojo cuelgan de los SubViewport, no del jugador, así que su
## rotación es absoluta del mundo: hay que alinearlos a mano con esta dirección
## o la vista arranca (y recentra) mirando al -Z del mundo sin importar cómo
## esté girado el jugador. Se toma de la base y no del euler porque un giro de
## 180° admite más de una descomposición en ángulos.
var _frente_inicial : Vector3 = Vector3.FORWARD
var _yaw_inicial : float = 0.0

func _input(event):
	if not Active:
		return

	if event is InputEventJoypadButton and event.pressed \
			and event.button_index == Input_Recenter_Joy_Button:
		recenter()
		return

	# Tab como alternativa por teclado: permite probar el asistente sin el mando.
	var wizard_requested: bool = (event is InputEventJoypadButton and event.pressed \
			and event.button_index == Input_Wizard_Joy_Button) \
		or (event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_TAB)
	if wizard_requested:
		if Wizard:
			Wizard.start(self)
		return

	# Un SubViewport no recibe input del viewport padre por sí solo, así que hay
	# que empujárselo a mano o el menú nunca vería las teclas ni los botones.
	if MenuViewport:
		MenuViewport.push_input(event)

	if Handle_Mouse_Capture:
		if event is InputEventMouseButton:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif Input.is_action_just_pressed(Input_Cancel):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE	
			
	if not UseGysroscope and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:		
		if RotateParent:
			parent.rotate_y(-(event as InputEventMouseMotion).relative.x * Mouse_Sensitivity)
		LeftEyePivot.rotate_y(-(event as InputEventMouseMotion).relative.x * Mouse_Sensitivity)
		RightEyePivot.rotate_y(-(event as InputEventMouseMotion).relative.x * Mouse_Sensitivity)
		LeftEyePivot.rotate_object_local(Vector3.RIGHT, -(event as InputEventMouseMotion).relative.y * Mouse_Sensitivity)
		RightEyePivot.rotate_object_local(Vector3.RIGHT,-(event as InputEventMouseMotion).relative.y * Mouse_Sensitivity)
		LeftEyePivot.global_rotation.x = clamp(LeftEyePivot.global_rotation.x, deg_to_rad(-90), deg_to_rad(90))
		RightEyePivot.global_rotation.x = clamp(RightEyePivot.global_rotation.x, deg_to_rad(-90), deg_to_rad(90))	
	
						
func _ready() -> void:
	# Refuerza el modo pantalla completa de project.godot: en Android el modo
	# inmersivo se pierde con facilidad y la barra de estado vuelve a dibujarse
	# sobre el borde superior de la imagen.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	parent = get_parent()
	_initial_parent_rotation = parent.rotation
	_frente_inicial = -parent.global_transform.basis.z
	_frente_inicial.y = 0.0
	if _frente_inicial.length() < 0.001:
		_frente_inicial = Vector3.FORWARD
	_frente_inicial = _frente_inicial.normalized()
	_yaw_inicial = atan2(-_frente_inicial.x, -_frente_inicial.z)
	LeftEyePivot.add_child(left_camera_3d)
	LeftEyeSubViewPort.add_child(LeftEyePivot)
	RightEyePivot.add_child(right_camera_3d)	
	RightEyeSubViewPort.add_child(RightEyePivot)	
	View = viewScene.instantiate()
	add_child(View)
	add_child(LeftEyeSubViewPort)
	add_child(RightEyeSubViewPort)	
	_update_eye_viewport_size()
	get_window().size_changed.connect(_update_eye_viewport_size)
	View.SetViewPorts(LeftEyeSubViewPort, RightEyeSubViewPort)
	LeftEyePivot.position.y = EyeHeight
	RightEyePivot.position.y = EyeHeight
	apply_eye_transform()
	_alinear_vista()
	# Diferido: el panel se cuelga del padre del jugador, que en este momento
	# todavía está instanciando sus hijos y rechazaría un add_child.
	_create_world_menu.call_deferred()

## Monta el menú de calibración como un panel 3D fijo en el mundo, en vez de un
## overlay sobre un solo ojo: puesto sobre un ojo la distorsión y el sesgo del
## propio panel falsean la calibración que se está midiendo.
func _create_world_menu() -> void:
	MenuViewport = SubViewport.new()
	MenuViewport.size = MENU_VIEWPORT_SIZE
	MenuViewport.transparent_bg = true
	MenuViewport.disable_3d = true
	MenuViewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var menu := menuScene.instantiate()
	MenuViewport.add_child(menu)

	MenuPanel = Sprite3D.new()
	MenuPanel.add_child(MenuViewport)
	MenuPanel.texture = MenuViewport.get_texture()
	MenuPanel.pixel_size = MenuPixelSize
	MenuPanel.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	MenuPanel.shaded = false
	MenuPanel.double_sided = false
	MenuPanel.transparent = true
	# Sin test de profundidad para que no lo tape la geometría del nivel.
	MenuPanel.no_depth_test = true
	MenuPanel.visible = false

	# Se cuelga del padre del jugador para quedar fijo en el mundo y no
	# seguirlo cuando los landmarks le mueven la posición.
	var world_root := parent.get_parent()
	if world_root == null:
		world_root = get_tree().current_scene
	world_root.add_child(MenuPanel)

	# Se alinea con el frente del escenario, que es adonde deja la vista tanto el
	# arranque como recenter(). Ubicarlo ahí garantiza que el panel quede
	# siempre de frente al recentrar.
	MenuPanel.global_position = parent.global_position \
		+ Vector3(0, EyeHeight, 0) \
		+ _frente_inicial * MenuDistance
	MenuPanel.global_rotation = Vector3(0, _yaw_inicial, 0)

	menu.setup(self, View.get_lens_material(), MenuPanel)

	Wizard = wizardScene.instantiate()
	add_child(Wizard)

## Los SubViewport de cada ojo nacen en 512x512. Estirar ese cuadrado al medio
## rectángulo de pantalla deforma la imagen, y una cuadrícula de calibración
## dejaría de tener celdas cuadradas, que es justo lo que hay que juzgar.
func _update_eye_viewport_size() -> void:
	var win := get_window().size
	var eye_size := Vector2i(maxi(win.x / 2, 1), maxi(win.y, 1))
	LeftEyeSubViewPort.size = eye_size
	RightEyeSubViewPort.size = eye_size

## Los dos viewports de ojo, para que el asistente de calibración pueda
## espejar su UI dentro de ambos y no sesgar la medición con un solo ojo.
func get_eye_viewports() -> Array:
	return [LeftEyeSubViewPort, RightEyeSubViewPort]

## Recalcula la posición/rotación de cada ojo a partir de EyesSeparation y
## EyeConvergencyAngle. Idempotente: se puede llamar en caliente desde el
## menú de calibración sin ir acumulando rotaciones.
func apply_eye_transform() -> void:
	left_camera_3d.position.x = -EyesSeparation
	right_camera_3d.position.x = EyesSeparation
	left_camera_3d.rotation = Vector3.ZERO
	right_camera_3d.rotation = Vector3.ZERO
	left_camera_3d.rotate_object_local(Vector3.UP, deg_to_rad(EyeConvergencyAngle))
	right_camera_3d.rotate_object_local(Vector3.UP, -deg_to_rad(EyeConvergencyAngle))

## Dirección "al frente" del escenario: la que mira el jugador tal como quedó
## puesto en la escena. Lo usan la nube de landmarks y el asistente para
## ubicarse delante de la vista en vez de asumir el -Z del mundo.
func frente_inicial() -> Vector3:
	return _frente_inicial

func yaw_inicial() -> float:
	return _yaw_inicial

## Deja los dos ojos mirando al frente del escenario. Su rotación es absoluta
## (cuelgan de los SubViewport), así que ponerlos en cero los mandaría al -Z del
## mundo y la vista arrancaría girada respecto del cuerpo.
func _alinear_vista() -> void:
	LeftEyePivot.rotation = Vector3(0.0, _yaw_inicial, 0.0)
	RightEyePivot.rotation = Vector3(0.0, _yaw_inicial, 0.0)

## Devuelve la vista a su orientación inicial. Hace falta porque el giroscopio
## se integra por acumulación y va derivando, así que la vista termina girada
## respecto del cuerpo aunque la cabeza esté al frente.
func recenter() -> void:
	_alinear_vista()
	if RotateParent and parent:
		parent.rotation = _initial_parent_rotation

func _process(delta: float) -> void:
	if not Active:
		return
		
	LeftEyePivot.global_position = Vector3(parent.global_position.x, parent.global_position.y + EyeHeight, parent.global_position.z )
	RightEyePivot.global_position = Vector3(parent.global_position.x, parent.global_position.y + EyeHeight, parent.global_position.z )	
	
	if UseGysroscope:
		var gyroscope = Input.get_gyroscope()
		if RotateParent:
			parent.rotate_y(gyroscope.y * GysroscopeFactor)
		LeftEyePivot.rotate_y(gyroscope.y * GysroscopeFactor)
		RightEyePivot.rotate_y(gyroscope.y * GysroscopeFactor)
		LeftEyePivot.rotate_object_local(Vector3.RIGHT, gyroscope.x * GysroscopeFactor)
		RightEyePivot.rotate_object_local(Vector3.RIGHT, gyroscope.x * GysroscopeFactor)
		LeftEyePivot.rotation.x = clamp(LeftEyePivot.rotation.x, deg_to_rad(-90), deg_to_rad(90))
		RightEyePivot.rotation.x = clamp(RightEyePivot.rotation.x, deg_to_rad(-90), deg_to_rad(90))
