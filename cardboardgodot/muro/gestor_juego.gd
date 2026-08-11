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

## Multiplicador sobre el tamano del cuerpo contra el agujero, alrededor de la
## cadera. La escala real ya la fija la normalizacion de la nube (NormalizarNube
## en example_scene); esto queda como perilla para ajustar el feel en vivo.
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

## --- Espejo -------------------------------------------------------------------
var _espejo := false
## Muros vivos indexados por id, para poder emparejarlos con los del visor.
var _muros: Dictionary = {}
var _proximo_id := 0
var _t_envio := 0.0
## Cuantos cuadros por segundo de estado se publican. El mensaje son ~200 bytes,
## asi que 30 cuesta 6 KB/s: nada al lado de mandar imagenes.
@export var EstadoFps : float = 30.0
var _cam_espejo: Camera3D
var _vista_ojos := false
## Ultimos contadores aplicados en el espejo. El flash se dispara cuando suben,
## en vez de mandar un evento suelto: asi un mensaje perdido no se lo come.
var _ok_visto := 0
var _fail_visto := 0
var _cabeza_espejo := Transform3D()

func _ready() -> void:
	super._ready()               # construye la nube + conecta el WebSocket
	_ocultar_agua_glb()
	_espejo = Rol.es_espejo()
	_poses = Figuras.todas()
	_crear_flash()
	if _espejo:
		_preparar_espejo()
	else:
		_crear_bienvenida()

## En el espejo no hay visor: se apaga el render estereoscopico y se pone una
## camara comun, que puede ir donde quiera porque no esta atada a la cabeza.
func _preparar_espejo() -> void:
	if _camera:
		_camera.set("Active", false)
		var vista = _camera.get("View")
		if vista:
			vista.visible = false
	_cam_espejo = Camera3D.new()
	_cam_espejo.current = true
	add_child(_cam_espejo)
	_colocar_camara_espejo()

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
	# A la altura de los ojos (la nube esta a CloudHeight) y bien adelante: el -Z
	# local de la nube es el lado contrario al jugador, asi que resta distancia.
	# El tamano en pixeles acompana a la distancia, asi el cartel se ve igual de
	# grande pero deja de estar encima de la cara.
	# Lo que se percibe es el TAMANO ANGULAR (pixel_size / distancia), no la
	# distancia: con la separacion de ojos calibrada en 5 mm casi no hay paralaje
	# estereoscopica, asi que alejar el cartel y subirle pixel_size en la misma
	# proporcion lo dejaba exactamente igual de encima. Aca 0.019/5.0 = 0.0038,
	# poco mas de la mitad del 0.0070 que tenia antes.
	_bienvenida = _nuevo_label(Vector3(0, 0.75, -5.0), 0.019)
	_bienvenida.text = "HOLE IN THE WALL VR\n\nImita la figura de cada muro\nque se acerca.\n\nBoton 2: empezar\nBoton 3: pararse en T y calibrar"

## HUD al costado IZQUIERDO y perpendicular a los muros, no de frente: adelante
## se superpone con el muro que llega y con el esqueleto objetivo. Se lee girando
## la cabeza, que es cuando uno quiere mirarlo.
func _crear_hud() -> Label3D:
	var l := _nuevo_label(Vector3(-2.4, 2.0, 0.0), 0.008)
	l.rotation = Vector3(0.0, PI * 0.5, 0.0)
	return l

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
	if _espejo:
		_input_espejo(event)
		return
	var boton := _boton(event)
	if boton != 0:
		accion(boton)

## Desde la PC se maneja todo el juego sin tocar el control: las teclas no actuan
## localmente (el espejo no simula nada), sino que se mandan al visor por el
## mismo WebSocket. V es la excepcion, porque el punto de vista es solo de acá.
func _input_espejo(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_V:
			_vista_ojos = not _vista_ojos
			print("[espejo] vista: ", "ojos del jugador" if _vista_ojos else "tercera persona")
		KEY_ENTER, KEY_SPACE:
			enviar_json({"cmd": 2})
		KEY_C:
			enviar_json({"cmd": 3})
		KEY_R:
			enviar_json({"cmd": "recentrar"})

## Las dos acciones del control, para que el boton fisico y el comando remoto
## pasen exactamente por el mismo camino.
func accion(boton: int) -> void:
	match _estado:
		Estado.JUGANDO:
			if boton == 2:
				_detener()
		Estado.ESPERANDO:
			if boton == 2:
				_iniciar()
			elif boton == 3:
				_empezar_calibracion()

## Comandos que llegan de la PC (del espejo o de la ventana de la camara).
func recibir_comando(cmd) -> void:
	if _espejo:
		return          # el espejo no ejecuta: solo emite
	if typeof(cmd) == TYPE_STRING and cmd == "recentrar":
		if _camera and _camera.has_method("recenter"):
			_camera.recenter()
		return
	accion(int(cmd))

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
	_muros.clear()
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
	_hud = _crear_hud()
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
	# La nube ya viene escalada al torso y apoyada en el piso (ver
	# example_scene._normalizar), asi que aca solo hay que cambiar de sistema de
	# coordenadas: la nube cuelga CloudHeight sobre el piso y el muro se talla
	# con el piso en y=0. La x no se toca, porque correrse a lo ancho de la
	# camara tiene que mover la silueta sobre el muro: ubicarse frente al
	# agujero es parte del juego.
	var ancla := Figuras.a_metros(Figuras.CADERA)
	var r := []
	for id in LANDMARK_IDS:
		var p := _pos(id)
		var q := Vector2(p.x, p.y + CloudHeight)
		r.append(ancla + (q - ancla) * escala_cuerpo)
	return r

func _torso_objetivo() -> float:
	return Figuras.torso()

func _altura_tobillo() -> float:
	return Figuras.a_metros(Vector2(0.0, Figuras.y_tobillo_de_pie())).y

func _spawn() -> void:
	var m := _nuevo_muro(_proximo_id, _idx, Z_SPAWN)
	_proximo_id += 1
	_idx = (_idx + 1) % _poses.size()
	m.alcanzo_plano.connect(_on_alcanzo_plano)
	_muro_activo = m

## Instancia un muro. Lo usan los dos roles: el visor cuando le toca aparecer, el
## espejo cuando ve un id que todavia no tiene.
func _nuevo_muro(id: int, idx_pose: int, z: float) -> Muro:
	var m := Muro.new()
	m.id = id
	m.idx_pose = idx_pose
	m.pasivo = _espejo
	m.configurar(_poses[idx_pose], velocidad_muro, Z_PLANO)
	# El muro se talla desde y=0 hacia arriba, asi que hay que bajarlo hasta el
	# piso: la nube cuelga CloudHeight por encima de el.
	m.position = Vector3(0, -CloudHeight, z)
	if _cloud:
		_cloud.add_child(m)
	else:
		add_child(m)
	_muros[id] = m
	return m

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
	if _espejo:
		_colocar_camara_espejo()
		_feedback_muro()
		return
	if _estado == Estado.CALIBRANDO:
		_paso_calibracion(delta)
		_publicar(delta)
		return
	if _estado == Estado.JUGANDO:
		_feedback_muro()
		_t += delta
		if _t >= spawn_cada:
			_t = 0.0
			_spawn()
	_publicar(delta)


## Dibuja el esqueleto del jugador sobre el muro que se esta jugando. En el
## espejo se elige el de mayor z, que es el mas cercano: cual es el activo no
## hace falta mandarlo porque se deduce.
func _feedback_muro() -> void:
	# El que se esta jugando es el mas cercano de los que TODAVIA no llegaron.
	# Filtrar los que ya pasaron es lo que faltaba: se quedan hasta 8 segundos
	# alejandose, seguian siendo los mas cercanos y se les dibujaba el esqueleto
	# encima con alfa 0, mientras el muro que venia quedaba sin nada.
	var m: Muro = null
	for id in _muros:
		var c = _muros[id]
		if not is_instance_valid(c) or c.position.z >= c.z_plano:
			continue
		if m == null or c.position.z > m.position.z:
			m = c
	if not is_instance_valid(m):
		return
	var pts := _puntos_muro()
	if pts.is_empty():
		return
	var verdes := m.actualizar_feedback(pts)
	if _hud:
		_hud.text = "%s\n%d/%d articulaciones OK\nPaso: %d   Fallo: %d\nBoton 2: parar y recalibrar" % [
			m.pose["nombre"], verdes, LANDMARK_IDS.size(), _ok, _fail]


# --- Publicacion del estado (solo el visor) -----------------------------------

func _publicar(delta: float) -> void:
	_t_envio += delta
	if _t_envio < 1.0 / maxf(EstadoFps, 1.0):
		return
	_t_envio = 0.0
	for id in _muros.keys():
		if not is_instance_valid(_muros[id]):
			_muros.erase(id)
	enviar_json(_estado_actual())


## Lo unico que el espejo NO puede deducir por su cuenta.
##
## Queda afuera a proposito todo lo que sale de los landmarks, que los dos roles
## reciben del mismo broadcast: el cuerpo, la posicion del jugador, los
## marcadores verde/rojo y el desvanecido de los esqueletos.
func _estado_actual() -> Dictionary:
	var muros := []
	for id in _muros:
		var m = _muros[id]
		if is_instance_valid(m):
			muros.append([id, m.idx_pose, snappedf(m.position.z, 0.001)])
	var cab := _transformada_cabeza()
	var q := cab.basis.get_rotation_quaternion()
	return {
		"est": _estado,
		# Posicion y orientacion de la cabeza: el giroscopio solo existe en el
		# telefono, no hay forma de deducirlo del otro lado.
		"cab": [
			snappedf(cab.origin.x, 0.001), snappedf(cab.origin.y, 0.001),
			snappedf(cab.origin.z, 0.001), snappedf(q.x, 0.0001),
			snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001),
		],
		# Las proporciones calibradas salen de una mediana sobre una ventana de
		# 2 s, asi que el espejo no las puede recalcular ni teniendo los mismos
		# landmarks: no recibe los mismos frames ni con el mismo timing.
		"cal": [Figuras.r_hombro, Figuras.r_cadera, Figuras.l_brazo_sup,
			Figuras.l_antebrazo, Figuras.l_muslo, Figuras.l_pierna, Figuras.l_nariz],
		# Cada muro con su id: el avance y el spawn se calculan contra el delta
		# local, asi que simularlos en paralelo se desfasaria a los pocos segundos.
		"muros": muros,
		# Contadores en vez de un evento suelto de paso/fallo: si se pierde un
		# mensaje, el siguiente igual trae el salto y el flash no se pierde.
		"ok": _ok,
		"fail": _fail,
	}


# --- Aplicacion del estado (solo el espejo) -----------------------------------

func recibir_estado(data: Dictionary) -> void:
	if not _espejo:
		return
	_aplicar_calibracion(data.get("cal"))
	_aplicar_muros(data.get("muros"))
	_aplicar_pantalla(int(data.get("est", Estado.ESPERANDO)))
	_aplicar_cabeza(data.get("cab"))
	_aplicar_contadores(int(data.get("ok", 0)), int(data.get("fail", 0)))

## Se escriben directo, sin volver a validar: el visor ya las valido contra los
## rangos anatomicos antes de aceptarlas (ver Figuras.calibrar).
func _aplicar_calibracion(a) -> void:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() != 7:
		return
	Figuras.r_hombro = float(a[0])
	Figuras.r_cadera = float(a[1])
	Figuras.l_brazo_sup = float(a[2])
	Figuras.l_antebrazo = float(a[3])
	Figuras.l_muslo = float(a[4])
	Figuras.l_pierna = float(a[5])
	Figuras.l_nariz = float(a[6])

func _aplicar_muros(lista) -> void:
	if typeof(lista) != TYPE_ARRAY:
		return
	var vivos := {}
	for e in lista:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() < 3:
			continue
		var id := int(e[0])
		vivos[id] = true
		var m = _muros.get(id)
		if not is_instance_valid(m):
			m = _nuevo_muro(id, int(e[1]), float(e[2]))
		m.position.z = float(e[2])
	# Los que el visor ya no reporta es porque se borraron al pasar la pileta.
	for id in _muros.keys():
		if not vivos.has(id):
			var m = _muros[id]
			if is_instance_valid(m):
				m.queue_free()
			_muros.erase(id)

func _aplicar_pantalla(e: int) -> void:
	if e == _estado:
		return
	_estado = e
	if _estado == Estado.JUGANDO:
		if is_instance_valid(_bienvenida):
			_bienvenida.queue_free()
			_bienvenida = null
		if not is_instance_valid(_hud):
			_hud = _crear_hud()
	else:
		if is_instance_valid(_hud):
			_hud.queue_free()
			_hud = null
		_crear_bienvenida()

func _aplicar_cabeza(a) -> void:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() != 7:
		return
	_cabeza_espejo = Transform3D(
		Basis(Quaternion(float(a[3]), float(a[4]), float(a[5]), float(a[6]))),
		Vector3(float(a[0]), float(a[1]), float(a[2])))
	# El Player no lleva camara en el espejo, pero mantenerlo en su sitio hace
	# que la vista de tercera persona sepa a quien encuadrar.
	if _player:
		_player.global_position = _cabeza_espejo.origin - Vector3(0, _altura_ojos(), 0)

func _aplicar_contadores(ok: int, fail: int) -> void:
	if ok > _ok_visto:
		_disparar_flash(true)
	elif fail > _fail_visto:
		_disparar_flash(false)
	_ok_visto = ok
	_fail_visto = fail
	_ok = ok
	_fail = fail

func _altura_ojos() -> float:
	if _camera:
		var h = _camera.get("EyeHeight")
		if typeof(h) == TYPE_FLOAT:
			return float(h)
	return 1.75

## Tercera persona por detras y al costado: se ve al jugador y al muro que se le
## viene encima, que es el plano con el que se entiende el juego desde afuera.
## Con V se pasa a los ojos del jugador.
func _colocar_camara_espejo() -> void:
	if _cam_espejo == null:
		return
	if _vista_ojos:
		_cam_espejo.global_transform = _cabeza_espejo
		return
	var ojos := _cabeza_espejo.origin
	var costado := _frente.cross(Vector3.UP).normalized()
	_cam_espejo.global_position = ojos - _frente * 3.2 + costado * 1.8 + Vector3(0, 1.0, 0)
	_cam_espejo.look_at(ojos + _frente * 2.0, Vector3.UP)
