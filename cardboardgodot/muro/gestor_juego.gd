extends "res://example/example_scene.gd"

## Gestor del juego. Extiende el sistema de landmarks (que ya construye la nube
## del cuerpo y se conecta por WebSocket) y le agrega: pantalla de bienvenida,
## confirmacion con el boton 2 o 3 del control, y el ciclo de muros con las 9
## figuras usando la captura en vivo. Los muros y el chequeo trabajan en el
## espacio local de la nube de landmarks (_cloud), asi los puntos del cuerpo se
## comparan directo contra el agujero.

## De donde sale el muro y donde se evalua. A 1.5 m/s el viaje son 8 segundos,
## que es el tiempo que tiene el jugador para armar la pose. Se acorto la salida
## junto con la velocidad: desde 18 m el muro se pasaba la primera mitad del
## recorrido demasiado lejos como para leer la figura.
const Z_SPAWN := -12.0
const Z_PLANO := 0.0

## Mide el torso del jugador (hombros a cadera) y lo lleva al torso de la figura.
## MediaPipe normaliza al encuadre, asi que cuanto mas lejos de la camara esta la
## persona mas chico llega todo: por eso los movimientos "se sentian chiquitos" y
## habia que retocar la ganancia cada vez que uno se corria de lugar. Con esto la
## postura deja de depender de a que distancia estes parado.
@export var normalizar_por_torso: bool = true
## Multiplicador extra sobre esa escala, para ajustar el feel en vivo.
@export var escala_cuerpo: float = 1.0
@export var velocidad_muro: float = 1.5
## Igual al tiempo de viaje (12 m / 1.5 m/s), asi los muros van de a uno y el
## siguiente sale cuando el anterior termino de evaluarse.
@export var spawn_cada: float = 8.0

## Cuanto dura la toma de medidas. Un solo frame alcanzaba para que un brazo mal
## detectado se comiera la calibracion entera, asi que se promedia por mediana
## sobre esta ventana.
@export var segundos_calibracion: float = 2.0
## Cuanto dura el flash de resultado sobre la camara.
@export var duracion_flash: float = 0.9

## Desenfoque + tinte sobre la imagen ya compuesta de los dos ojos. Va por
## encima del CardboardView, que es un CanvasLayer en la capa 1. La opacidad sale
## de `fuerza`, asi que con fuerza 0 el overlay es invisible aunque quede activo.
const SHADER_FLASH := """
shader_type canvas_item;

uniform vec4 tinte : source_color = vec4(0.0, 1.0, 0.0, 1.0);
uniform float fuerza : hint_range(0.0, 1.0) = 0.0;
uniform float radio = 8.0;
uniform sampler2D pantalla : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radio * fuerza;
	// 9 muestras: se lee como desenfoque sin costar caro en el telefono.
	vec4 c = texture(pantalla, SCREEN_UV);
	c += texture(pantalla, SCREEN_UV + vec2(-px.x, -px.y));
	c += texture(pantalla, SCREEN_UV + vec2(0.0, -px.y));
	c += texture(pantalla, SCREEN_UV + vec2(px.x, -px.y));
	c += texture(pantalla, SCREEN_UV + vec2(-px.x, 0.0));
	c += texture(pantalla, SCREEN_UV + vec2(px.x, 0.0));
	c += texture(pantalla, SCREEN_UV + vec2(-px.x, px.y));
	c += texture(pantalla, SCREEN_UV + vec2(0.0, px.y));
	c += texture(pantalla, SCREEN_UV + vec2(px.x, px.y));
	c /= 9.0;
	COLOR = vec4(mix(c.rgb, tinte.rgb, 0.5), fuerza);
}
"""

enum Estado { ESPERANDO, CALIBRANDO, JUGANDO }
var _estado := Estado.ESPERANDO
var _bienvenida: Label3D
var _hud: Label3D
var _muro_activo: Muro
var _poses: Array
var _idx := 0
var _t := 0.0
var _ok := 0
var _fail := 0
var _muestras: Dictionary = {}
var _t_calib := 0.0
var _flash: ColorRect
var _flash_mat: ShaderMaterial
var _t_flash := 0.0

func _ready() -> void:
	super._ready()               # construye la nube + conecta el WebSocket
	_ocultar_agua_glb()
	_poses = Figuras.todas()
	_crear_flash()
	_crear_bienvenida()

func _crear_flash() -> void:
	var capa := CanvasLayer.new()
	capa.layer = 10          # el CardboardView esta en la 1
	add_child(capa)
	var sh := Shader.new()
	sh.code = SHADER_FLASH
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = sh
	_flash_mat.set_shader_parameter("fuerza", 0.0)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.material = _flash_mat
	_flash.visible = false
	capa.add_child(_flash)

func _disparar_flash(paso: bool) -> void:
	if _flash_mat == null:
		return
	_flash_mat.set_shader_parameter("tinte",
		Color(0.15, 1.0, 0.35) if paso else Color(1.0, 0.15, 0.15))
	_t_flash = duracion_flash
	_flash.visible = true

func _paso_flash(delta: float) -> void:
	if _t_flash <= 0.0:
		return
	_t_flash -= delta
	_flash_mat.set_shader_parameter("fuerza",
		clampf(_t_flash / duracion_flash, 0.0, 1.0))
	if _t_flash <= 0.0:
		_flash.visible = false

func _ocultar_agua_glb() -> void:
	var pool := get_node_or_null("SwimmingPool")
	if pool:
		var w := pool.find_child("Water_Water_0", true, false)
		if w and w is Node3D:
			(w as Node3D).visible = false

func _crear_bienvenida() -> void:
	if is_instance_valid(_bienvenida):
		_bienvenida.queue_free()
	# A la altura de los ojos (la nube esta a CloudHeight) y un poco mas lejos
	# que el origen de la nube, para no quedar encima del esqueleto. El -Z local
	# de la nube es el lado contrario al jugador, asi que resta distancia.
	_bienvenida = _nuevo_label(Vector3(0, 0.75, -1.5), 0.0105)
	_bienvenida.text = "HOLE IN THE WALL VR\n\nImita la figura de cada muro\nque se acerca.\n\nBoton 2: empezar\nBoton 3: pararse en T y calibrar"

func _nuevo_label(pos: Vector3, tam: float) -> Label3D:
	var l := Label3D.new()
	# Sin billboard: las dos camaras de ojo tienen convergencia, asi que cada una
	# lo orientaria distinto y el texto no fusiona en estereo. Colgado de la nube
	# con rotacion cero ya mira al jugador, porque el +Z local de la nube apunta
	# hacia el. Mismo criterio que el panel de calibracion del addon.
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.rotation = Vector3.ZERO
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

# Boton 2 (o Enter/Espacio): arranca, y durante el juego lo frena para volver a
# la bienvenida sin cerrar la app. Boton 3 (o C): mide al jugador parado en T.
func _input(event: InputEvent) -> void:
	var boton := _boton(event)
	if boton == 0:
		return
	match _estado:
		Estado.JUGANDO:
			if boton == 2:
				_detener()
		Estado.ESPERANDO:
			if boton == 2:
				_iniciar()
			elif boton == 3:
				_empezar_calibracion()

## 2, 3 o 0 si el evento no es ninguno de los dos.
func _boton(event: InputEvent) -> int:
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == 2 or event.button_index == 3:
			return event.button_index
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			return 2
		elif event.keycode == KEY_C:
			return 3
	return 0

## Vuelve a la bienvenida: saca los muros en vuelo y el HUD, para poder
## recalibrar sin tener que cerrar y volver a abrir la app.
func _detener() -> void:
	_estado = Estado.ESPERANDO
	if _cloud:
		for n in _cloud.get_children():
			if n is Muro:
				n.queue_free()
	_muro_activo = null
	_t = 0.0
	if _hud:
		_hud.queue_free()
		_hud = null
	_crear_bienvenida()

func _pos(id: int) -> Vector2:
	var mi = _points.get(id)
	return Vector2.ZERO if mi == null else Vector2(mi.position.x, mi.position.y)

func _dist(a: int, b: int) -> float:
	return _pos(a).distance_to(_pos(b))

## Medidas del jugador tal como esta parado en este frame, o vacio si todavia no
## se lo ve entero.
##
## Se miden RELACIONES contra el torso, nunca tamanos absolutos, por dos motivos:
## deja de importar a que distancia de la camara este parado, y ademas cancela la
## deformacion de MediaPipe, que normaliza x por el ancho de la imagen e y por el
## alto (con lo cual todo lo horizontal viene estirado por el aspect ratio). Como
## el jugador se compara despues en ese mismo espacio deformado, la deformacion
## se va por los dos lados.
func _medidas() -> Dictionary:
	if not conectado:
		return {}
	for id in LANDMARK_IDS:
		if _points.get(id) == null:
			return {}
	var hombros := (_pos(11) + _pos(12)) * 0.5
	var cadera := (_pos(23) + _pos(24)) * 0.5
	var torso := hombros.distance_to(cadera)
	if torso < 0.01:
		return {}
	return {
		"r_hombro": _dist(11, 12) * 0.5 / torso,
		"r_cadera": _dist(23, 24) * 0.5 / torso,
		"l_brazo_sup": (_dist(11, 13) + _dist(12, 14)) * 0.5 / torso,
		"l_antebrazo": (_dist(13, 15) + _dist(14, 16)) * 0.5 / torso,
		"l_muslo": (_dist(23, 25) + _dist(24, 26)) * 0.5 / torso,
		"l_pierna": (_dist(25, 27) + _dist(26, 28)) * 0.5 / torso,
		"l_nariz": hombros.distance_to(_pos(0)) / torso,
	}

func _empezar_calibracion() -> void:
	_estado = Estado.CALIBRANDO
	_t_calib = 0.0
	_muestras = {}
	for k in Figuras.POR_DEFECTO:
		_muestras[k] = []

## Junta medidas mientras dura la ventana y al final se queda con la MEDIANA de
## cada una: con el promedio, un frame en que MediaPipe pierde una muneca
## arrastraba el resultado; la mediana lo ignora.
func _paso_calibracion(delta: float) -> void:
	_t_calib += delta
	var m := _medidas()
	if not m.is_empty():
		for k in m:
			(_muestras[k] as Array).append(m[k])
	var faltan: float = maxf(0.0, segundos_calibracion - _t_calib)
	if _bienvenida:
		_bienvenida.text = "CALIBRANDO\n\nParate en T, de frente,\ncon el cuerpo entero en camara.\n\n%.1f s" % faltan
	if _t_calib < segundos_calibracion:
		return

	_estado = Estado.ESPERANDO
	var n: int = (_muestras["l_muslo"] as Array).size()
	if n < 5:
		_calibracion_fallo("solo %d muestras validas" % n)
		return
	var med := {}
	for k in _muestras:
		med[k] = _mediana(_muestras[k])
	if not Figuras.calibrar(med):
		_calibracion_fallo("medidas fuera de rango: " + _texto(med))
		return
	print("[calibracion] ok sobre %d muestras -> %s" % [n, Figuras.resumen()])
	_iniciar()

func _calibracion_fallo(motivo: String) -> void:
	print("[calibracion] descartada (", motivo, ")")
	if _bienvenida:
		_bienvenida.text = "NO SE PUDO CALIBRAR\n\nTiene que verse el cuerpo entero,\nde frente y con los brazos\nbien estirados.\n\nBoton 3: reintentar\nBoton 2: jugar con las\nmedidas por defecto"

func _mediana(v: Array) -> float:
	var c := v.duplicate()
	c.sort()
	return c[c.size() / 2]

func _texto(m: Dictionary) -> String:
	var p := []
	for k in m:
		p.append("%s %.2f" % [k, m[k]])
	return ", ".join(p)

func _iniciar() -> void:
	_estado = Estado.JUGANDO
	if _bienvenida:
		_bienvenida.queue_free()
		_bienvenida = null
	_hud = _nuevo_label(Vector3(0, 2.7, 0), 0.006)
	_spawn()

## Puntos del cuerpo en el espacio del muro: metros, con y=0 en el piso. Vacio
## si aun no llegan datos.
##
## Se anclan a la cadera de la figura en vez de usar la posicion cruda: MediaPipe
## normaliza al encuadre, asi que la silueta se corria entera para arriba o para
## el costado segun como estuviera parada la persona frente a la camara. Anclando
## al centro del cuerpo, lo unico que cuenta es la POSTURA, no el encuadre.
func _puntos_muro() -> Array:
	if not conectado:
		return []
	for id in LANDMARK_IDS:
		if _points.get(id) == null:
			return []
	var cadera := (_pos(23) + _pos(24)) * 0.5
	var hombros := (_pos(11) + _pos(12)) * 0.5
	var k := escala_cuerpo
	if normalizar_por_torso:
		var torso := hombros.distance_to(cadera)
		if torso < 0.01:
			return []
		k *= Figuras.torso() / torso
	# Vertical anclada a los pies, igual que las figuras: al agacharse baja la
	# cadera y los tobillos se quedan en el piso.
	var tobillos := (_pos(27) + _pos(28)) * 0.5
	var y0 := Figuras.a_metros(Vector2(0.0, Figuras.y_tobillo_de_pie())).y
	var r := []
	for id in LANDMARK_IDS:
		var p := _pos(id)
		# La x NO se centra en el cuerpo: correrse a lo ancho de la camara tiene
		# que mover la silueta sobre el muro, porque ubicarse frente al agujero
		# es parte del juego. Antes se restaba el centro de la cadera y la
		# silueta quedaba clavada al medio por mas que uno se corriera.
		r.append(Vector2(p.x * k, y0 + (p.y - tobillos.y) * k))
	return r

func _spawn() -> void:
	var pose = _poses[_idx]
	_idx = (_idx + 1) % _poses.size()
	var m := Muro.new()
	m.configurar(pose, velocidad_muro, Z_PLANO)
	# El muro se talla desde y=0 hacia arriba, asi que hay que bajarlo hasta el
	# piso: la nube cuelga CloudHeight por encima de el.
	m.position = Vector3(0, -CloudHeight, Z_SPAWN)
	m.alcanzo_plano.connect(_on_alcanzo_plano)
	if _cloud:
		_cloud.add_child(m)
	else:
		add_child(m)
	_muro_activo = m

## El muro no se detiene ni se pinta: sigue de largo y se borra solo cuando ya
## paso la pileta. El resultado lo da el flash sobre la camara.
func _on_alcanzo_plano(m: Muro) -> void:
	var pts := _puntos_muro()
	var paso := false
	if not pts.is_empty():
		paso = m.evaluar(pts)["paso"]
	if paso:
		_ok += 1
	else:
		_fail += 1
	_disparar_flash(paso)

func _process(delta: float) -> void:
	super._process(delta)        # sigue actualizando el cuerpo y la cabeza
	_paso_flash(delta)           # corre en cualquier estado: no lo corta parar
	if _estado == Estado.CALIBRANDO:
		_paso_calibracion(delta)
		return
	if _estado != Estado.JUGANDO:
		return
	if is_instance_valid(_muro_activo):
		var pts := _puntos_muro()
		if not pts.is_empty():
			var verdes := _muro_activo.actualizar_feedback(pts)
			if _hud:
				_hud.text = "%s\n%d/%d articulaciones OK\nPaso: %d   Fallo: %d\nBoton 2: parar y recalibrar" % [
					_muro_activo.pose["nombre"], verdes, LANDMARK_IDS.size(), _ok, _fail]
	_t += delta
	if _t >= spawn_cada:
		_t = 0.0
		_spawn()
