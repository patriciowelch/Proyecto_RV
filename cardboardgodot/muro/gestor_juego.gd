extends "res://example/example_scene.gd"

## Gestor del juego. Extiende el sistema de landmarks (que ya construye la nube
## del cuerpo y se conecta por WebSocket) y le agrega: pantalla de bienvenida,
## confirmacion con el boton 2 o 3 del control, y el ciclo de muros con las 9
## figuras usando la captura en vivo. Los muros y el chequeo trabajan en el
## espacio local de la nube de landmarks (_cloud), asi los puntos del cuerpo se
## comparan directo contra el agujero.

const Z_SPAWN := -18.0
const Z_PLANO := 0.0

## Factor para llevar el cuerpo (en unidades CloudScale) a la escala de las
## figuras. Se ajusta en vivo mirando como encaja la silueta en los agujeros.
@export var escala_cuerpo: float = 1.7
@export var velocidad_muro: float = 3.0
@export var spawn_cada: float = 5.0

enum Estado { ESPERANDO, JUGANDO }
var _estado := Estado.ESPERANDO
var _bienvenida: Label3D
var _hud: Label3D
var _muro_activo: Muro
var _poses: Array
var _idx := 0
var _t := 0.0
var _ok := 0
var _fail := 0

func _ready() -> void:
	super._ready()               # construye la nube + conecta el WebSocket
	_ocultar_agua_glb()
	_poses = Figuras.todas()
	_crear_bienvenida()

func _ocultar_agua_glb() -> void:
	var pool := get_node_or_null("SwimmingPool")
	if pool:
		var w := pool.find_child("Water_Water_0", true, false)
		if w and w is Node3D:
			(w as Node3D).visible = false

func _crear_bienvenida() -> void:
	_bienvenida = _nuevo_label(Vector3(0, 0.6, 0), 0.007)
	_bienvenida.text = "HOLE IN THE WALL VR\n\nImita la figura de cada muro\nque se acerca.\n\nBoton 2 o 3 para empezar"

func _nuevo_label(pos: Vector3, tam: float) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = tam
	l.modulate = Color(1, 1, 0.55)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _cloud:
		_cloud.add_child(l)
		l.position = pos
	else:
		add_child(l)
	return l

# El boton 2 o 3 del control (o Enter/Espacio para probar en PC) confirma.
func _input(event: InputEvent) -> void:
	if _estado != Estado.ESPERANDO:
		return
	var confirmar := false
	if event is InputEventJoypadButton and event.pressed \
			and (event.button_index == 2 or event.button_index == 3):
		confirmar = true
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
		confirmar = true
	if confirmar:
		_iniciar()

func _iniciar() -> void:
	_estado = Estado.JUGANDO
	if _bienvenida:
		_bienvenida.queue_free()
		_bienvenida = null
	_hud = _nuevo_label(Vector3(0, 2.7, 0), 0.006)
	_spawn()

## Puntos del cuerpo en el espacio del muro. Vacio si aun no llegan datos.
func _puntos_muro() -> Array:
	if not conectado:
		return []
	var r := []
	for id in LANDMARK_IDS:
		var mi = _points.get(id)
		if mi == null:
			return []
		r.append(Vector2(mi.position.x, mi.position.y) * escala_cuerpo)
	return r

func _spawn() -> void:
	var pose = _poses[_idx]
	_idx = (_idx + 1) % _poses.size()
	var m := Muro.new()
	m.configurar(pose, velocidad_muro, Z_PLANO)
	m.position = Vector3(0, 0, Z_SPAWN)
	m.alcanzo_plano.connect(_on_alcanzo_plano)
	if _cloud:
		_cloud.add_child(m)
	else:
		add_child(m)
	_muro_activo = m

func _on_alcanzo_plano(m: Muro) -> void:
	var pts := _puntos_muro()
	var paso := false
	if not pts.is_empty():
		paso = m.evaluar(pts)["paso"]
	m.marcar(paso)
	if paso:
		_ok += 1
	else:
		_fail += 1
	get_tree().create_timer(2.0).timeout.connect(m.queue_free)

func _process(delta: float) -> void:
	super._process(delta)        # sigue actualizando el cuerpo y la cabeza
	if _estado != Estado.JUGANDO:
		return
	if is_instance_valid(_muro_activo):
		var pts := _puntos_muro()
		if not pts.is_empty():
			var verdes := _muro_activo.actualizar_feedback(pts)
			if _hud:
				_hud.text = "%s\n%d/%d articulaciones OK\nPaso: %d   Fallo: %d" % [
					_muro_activo.pose["nombre"], verdes, LANDMARK_IDS.size(), _ok, _fail]
	_t += delta
	if _t >= spawn_cada:
		_t = 0.0
		_spawn()
