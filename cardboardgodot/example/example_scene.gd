extends Node3D

## Cliente WebSocket de los landmarks de MediaPipe.
##
## Crea la nube de puntos por código en vez de depender de nodos de escena:
## así no hay que mantener sincronizada una lista de nodos P{id} a mano.

const LANDMARK_IDS := [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]


## Filtro One Euro: suaviza según la velocidad del movimiento. Un promedio fijo
## obliga a elegir entre jitter (poco filtrado) y lag (mucho); este sube el
## filtrado cuando el punto está casi quieto, que es cuando el ruido se nota, y
## lo baja cuando se mueve rápido, que es cuando la latencia molesta.
class OneEuro:
	var _min_cutoff: float
	var _beta: float
	var _d_cutoff := 1.0
	var _x_prev := Vector3.ZERO
	var _dx_prev := Vector3.ZERO
	var _iniciado := false

	func _init(min_cutoff: float, beta: float) -> void:
		_min_cutoff = min_cutoff
		_beta = beta

	func _alpha(cutoff: float, dt: float) -> float:
		var tau := 1.0 / (TAU * cutoff)
		return 1.0 / (1.0 + tau / dt)

	func filtrar(x: Vector3, dt: float) -> Vector3:
		if dt <= 0.0:
			return _x_prev
		if not _iniciado:
			_iniciado = true
			_x_prev = x
			return x
		var dx := (x - _x_prev) / dt
		_dx_prev = _dx_prev.lerp(dx, _alpha(_d_cutoff, dt))
		var cutoff := _min_cutoff + _beta * _dx_prev.length()
		_x_prev = _x_prev.lerp(x, _alpha(cutoff, dt))
		return _x_prev

## Huesos a dibujar entre landmarks, para que la nube se lea como un cuerpo.
const BONES := [
	[11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
	[11, 23], [12, 24], [23, 24],
	[23, 25], [25, 27], [24, 26], [26, 28],
]

@export var ServerPort : int = 8765
## Subred del "Punto de acceso móvil" de Windows: el PC siempre es el .1.
@export var SubnetBase : String = "192.168.137."
@export var ScanUpTo : int = 20
## Todo en metros: el mundo es métrico y el Player está apoyado en y=0.
## En 0 la nube queda centrada EN el jugador, que es lo que corresponde con
## FollowHead: sus ojos van sobre el landmark 0, así que él *es* el esqueleto.
## Con la nube adelantada el esqueleto se le planta enfrente y le tapa el muro.
@export var CloudDistance : float = 0.0
@export var CloudHeight : float = 1.0
## Metros de mundo por unidad normalizada de MediaPipe. Solo importa si se apaga
## NormalizarNube: con la normalización activa la escala la fija el torso.
@export var CloudScale : float = 2.0
## Lleva la nube a escala real y la apoya en el piso. Sin esto los puntos quedan
## en coordenadas del ENCUADRE, y el esqueleto se dibuja del tamaño que ocupa la
## persona en la imagen y centrado en el medio del cuadro: acercarse a la cámara
## lo agranda hasta meterle medio cuerpo bajo el piso.
@export var NormalizarNube : bool = true
## Cuanto de la profundidad de MediaPipe se aplica. En 0 la nube queda plana.
## La z de MediaPipe es una estimacion ruidosa y en metros de mundo empujaba al
## jugador varios metros hacia adelante, hasta el borde del piso que rodea la
## pileta. El juego compara siluetas en 2D, asi que no se pierde nada.
@export var LandmarkDepth : float = 0.0
@export var PointRadius : float = 0.06
## Si está activo, el landmark 0 (nose, la cabeza) pasa a ser la cabeza del
## jugador: los ojos se ubican exactamente en ese punto, así que mover la
## cabeza frente a la cámara mueve el punto de vista en VR.
@export var FollowHead : bool = true
## Cuánto sobresale la cabeza por encima de la cadera con la persona de pie, en
## múltiplos del torso, y el torso del cuerpo de referencia en metros. Con estos
## dos, la altura de los ojos sale de la POSTURA y no de cómo quedó encuadrada la
## persona: parado da EyeHeight, agachado baja en proporción.
@export var CabezaSobreCaderaDePie : float = 1.405
@export var TorsoMetros : float = 0.546

@export_category("Esqueleto de debug")
## Segundo esqueleto, fijo en el mundo y más adelante que el principal. Con
## FollowHead activo el jugador termina dentro del esqueleto principal (su
## cabeza ES el landmark 0), así que hace falta una copia separada para poder
## mirar de afuera qué movimientos están llegando.
@export var ShowDebugSkeleton : bool = false
## Cuánto más adelante que el esqueleto principal, en metros.
@export var DebugDistance : float = 3.0
## Altura a la que se fija la cadera del esqueleto de debug. Se ancla ahí y no
## al centro del encuadre porque MediaPipe devuelve y fuera de [0,1] cuando el
## cuerpo se sale de cámara (sentado y cerca, los tobillos llegan a y≈2.4), y
## centrar en 0.5 dejaba medio esqueleto metros bajo el piso.
@export var DebugHipHeight : float = 1.2
## Escala del esqueleto de debug, para que entre entero en el campo de visión.
@export var DebugScale : float = 0.5

@export_category("Suavizado")
## Frecuencia de corte mínima, en Hz. Más bajo = más suave y más lento.
@export var MinCutoff : float = 1.2
## Cuánto se afloja el filtro al aumentar la velocidad. Más alto = responde
## antes a movimientos rápidos, a costa de dejar pasar algo más de ruido.
@export var SmoothBeta : float = 0.04
## La cabeza se filtra más fuerte: es el punto de vista y su tembleque es el
## que marea, mientras que un poco de latencia ahí casi no se percibe.
@export var HeadCutoffFactor : float = 0.6
@export var ReconnectSeconds : float = 3.0

@export_category("Transmisión a la PC")
## Manda a la PC, por el mismo WebSocket de los landmarks, lo que ve el jugador:
## una segunda cámara mono, sin distorsión de lente, montada sobre su cabeza.
##
## Apagado por defecto: lo reemplaza el espejo (ver rol.gd), que replica la
## escena en la PC en vez de mandar píxeles. Queda como respaldo porque anda sin
## depender de que el estado esté bien sincronizado, pero cuesta caro: cada envío
## obliga a bajar la textura de la GPU a la CPU y eso frena el render del visor.
@export var TransmitirVista : bool = false
## Resolución de la transmisión. Baja a propósito: cada envío obliga a bajar la
## textura de la GPU a la CPU, que es lo caro de todo esto.
@export var VistaAncho : int = 640
@export var VistaAlto : int = 360
## Cuántos cuadros por segundo se mandan. No hace falta más para seguir la
## partida desde la PC, y cada uno cuesta una lectura de GPU.
@export var VistaFps : float = 12.0
## 0 a 1. Más calidad son más kilobytes por cuadro sobre el WiFi.
@export var VistaCalidad : float = 0.55
## Si la imagen llega cabeza abajo, invertir esto: el sentido del eje Y al leer
## un viewport depende del backend de render.
@export var VistaVolteada : bool = false

var websocket := WebSocketPeer.new()
var url := ""
var conectado := false

var _cloud: Node3D
var _debug_cloud: Node3D
var _player: Node3D
## Frente del escenario: adonde mira el jugador tal como quedó puesto en la
## escena. Se calcula una sola vez al arrancar, porque la rotación viva del
## jugador va derivando con el giroscopio y arrastraría la nube con ella.
var _frente: Vector3 = Vector3.FORWARD
var _yaw: float = 0.0
## Donde quedo el jugador en la escena. Es su sitio en el escenario: los
## landmarks lo mueven alrededor de este punto, no a coordenadas absolutas.
var _pos_inicial: Vector3 = Vector3.ZERO
var _camera: Node
var _points: Dictionary = {}
var _bones: Dictionary = {}
var _debug_points: Dictionary = {}
var _debug_bones: Dictionary = {}
## Última posición cruda recibida por red, antes de filtrar.
var _targets: Dictionary = {}
var _filters: Dictionary = {}
var _status: Label3D
var _vista: SubViewport
var _vista_cam: Camera3D
var _t_vista := 0.0
var _reconnect_timer := 0.0
var _scanning := false
var _frames := 0


func _ready() -> void:
	print("[rol] ", "ESPEJO (PC)" if Rol.es_espejo() else "VISOR (telefono)")
	if Rol.es_espejo():
		# En el espejo la cabeza la manda el visor: si además la moviera el
		# landmark de la nariz, pelearían por la misma posición cada frame.
		FollowHead = false
		TransmitirVista = false
	_build_cloud()
	if TransmitirVista:
		_crear_vista_pc()
	_set_status("Buscando servidor en %sX:%d ..." % [SubnetBase, ServerPort])
	_buscar_y_conectar()


## Segunda cámara, mono y sin distorsión, dentro de su propio SubViewport. Como
## el SubViewport no crea un mundo propio, dibuja exactamente la misma escena que
## ve el jugador; solo cambia que es una sola imagen y sin el shader de lente.
func _crear_vista_pc() -> void:
	_vista = SubViewport.new()
	_vista.size = Vector2i(VistaAncho, VistaAlto)
	_vista.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vista.transparent_bg = false
	add_child(_vista)
	_vista_cam = Camera3D.new()
	_vista_cam.current = true          # current dentro de ESTE viewport, no del principal
	_vista.add_child(_vista_cam)


# --- Construcción de la nube --------------------------------------------------

func _build_cloud() -> void:
	_cloud = Node3D.new()
	add_child(_cloud)
	_player = get_node_or_null("Player")
	if _player:
		_camera = _player.get_node_or_null("CardboardVRCamera3D")
	var origin: Vector3 = Vector3.ZERO if _player == null else _player.global_position
	_pos_inicial = origin
	if _player:
		_frente = -_player.global_transform.basis.z
		_frente.y = 0.0
		if _frente.length() < 0.001:
			_frente = Vector3.FORWARD
		_frente = _frente.normalized()
		_yaw = atan2(-_frente.x, -_frente.z)
	# Delante del jugador según su rotación en la escena, que es adonde mira la
	# vista al arrancar y al recentrar. La nube se gira con él, así que los muros
	# (que cuelgan de acá y viajan hacia su +Z local) llegan siempre de frente.
	_cloud.global_position = origin + Vector3(0, CloudHeight, 0) + _frente * CloudDistance
	_cloud.global_rotation = Vector3(0, _yaw, 0)

	for id in LANDMARK_IDS:
		_targets[id] = Vector3.ZERO
		var corte := MinCutoff * (HeadCutoffFactor if id == 0 else 1.0)
		_filters[id] = OneEuro.new(corte, SmoothBeta)

	_armar_esqueleto(_cloud, _points, _bones,
		Color(0.2, 1.0, 0.4), Color(0.2, 0.7, 1.0), 1.0)

	if ShowDebugSkeleton:
		_debug_cloud = Node3D.new()
		add_child(_debug_cloud)
		_debug_cloud.global_position = _cloud.global_position + _frente * DebugDistance
		_debug_cloud.global_position.y = DebugHipHeight
		_debug_cloud.global_rotation = Vector3(0, _yaw, 0)
		_debug_cloud.scale = Vector3.ONE * DebugScale
		# En otro color para no confundirlo con el que controla la vista.
		_armar_esqueleto(_debug_cloud, _debug_points, _debug_bones,
			Color(1.0, 0.6, 0.1), Color(1.0, 0.35, 0.35), 1.4)

	_status = Label3D.new()
	# Sin billboard y corrido al costado: es información de diagnóstico, no tiene
	# por qué estar siempre en la cara. Queda clavado en el mundo a la derecha
	# del jugador, chico, para verlo solo cuando se gira a mirarlo.
	_status.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_status.no_depth_test = true
	_status.pixel_size = 0.005
	_status.modulate = Color(1, 1, 0.4)
	# A la derecha del jugador y PERPENDICULAR a los muros: su plano queda a 90°
	# del de la pared, así que de frente no se ve nada y hay que girar la cabeza
	# para leerlo. Es diagnóstico, no tiene que competir con el juego.
	_status.position = Vector3(2.4, 1.6, 0.0)
	_status.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	_cloud.add_child(_status)


## Arma un esqueleto (esferas + huesos) bajo `parent` y deja las referencias en
## los diccionarios que se le pasan, para poder instanciarlo más de una vez.
func _armar_esqueleto(parent: Node3D, puntos: Dictionary, huesos: Dictionary,
		color_punto: Color, color_hueso: Color, escala: float) -> void:
	var point_mat := StandardMaterial3D.new()
	point_mat.albedo_color = color_punto
	point_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = color_hueso
	bone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var radio := PointRadius * escala
	for id in LANDMARK_IDS:
		var sphere := SphereMesh.new()
		sphere.radius = radio
		sphere.height = radio * 2.0
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.material_override = point_mat
		parent.add_child(mi)
		puntos[id] = mi

	for bone in BONES:
		var cyl := CylinderMesh.new()
		cyl.top_radius = radio * 0.4
		cyl.bottom_radius = radio * 0.4
		cyl.height = 1.0
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = bone_mat
		parent.add_child(mi)
		huesos[bone] = mi


func _set_status(t: String) -> void:
	print("[landmarks] ", t)
	if _status:
		_status.text = t


# --- Conexión -----------------------------------------------------------------

func _buscar_y_conectar() -> void:
	if _scanning:
		return
	_scanning = true
	_escanear.call_deferred()


## Subredes a probar: primero aquella en la que está el propio teléfono. Fijar
## solo la del punto de acceso no alcanza, porque Android salta sola a otra red
## si esa no da internet y entonces el PC deja de ser alcanzable.
func _subredes_candidatas() -> Array:
	# La del punto de acceso va PRIMERA: es donde está el servidor en el caso
	# normal, y probarla al final costaba más de un minuto de espera.
	var bases := [SubnetBase]
	for addr in IP.get_local_addresses():
		if addr.count(".") != 3 or addr.begins_with("127."):
			continue
		# 169.254.x es link-local: Windows la asigna sola a cada adaptador sin
		# DHCP y acá aparecían cuatro. Nunca hay un servidor ahí, pero cada IP
		# inalcanzable agota el medio segundo entero del sondeo, así que probar
		# esas subredes son ~40 segundos tirados antes de llegar a la buena.
		if addr.begins_with("169.254."):
			continue
		var p := addr.split(".")
		var base := "%s.%s.%s." % [p[0], p[1], p[2]]
		if not bases.has(base):
			bases.append(base)
	return bases


func _escanear() -> void:
	var subredes := _subredes_candidatas()
	for base in subredes:
		# El .1 va primero: es el router y también el PC en el punto de acceso
		# de Windows, así que el caso normal conecta sin recorrer la subred.
		for i in range(1, ScanUpTo + 1):
			var test_url := "ws://%s%d:%d" % [base, i, ServerPort]
			var probe := WebSocketPeer.new()
			if probe.connect_to_url(test_url) != OK:
				continue
			var t := 0.0
			while probe.get_ready_state() == WebSocketPeer.STATE_CONNECTING and t < 0.5:
				probe.poll()
				await get_tree().create_timer(0.05).timeout
				t += 0.05
			var state := probe.get_ready_state()
			probe.close()
			if state == WebSocketPeer.STATE_OPEN:
				url = test_url
				_set_status("Servidor: %s\nconectando..." % url)
				websocket = WebSocketPeer.new()
				# Por acá salen los cuadros de video, que son bastante más
				# grandes que el JSON de landmarks que entra.
				websocket.outbound_buffer_size = 1 << 20
				if websocket.connect_to_url(url) != OK:
					_set_status("Error al conectar a %s" % url)
				_scanning = false
				return

	_set_status("Sin servidor en %s\nreintentando..." % ", ".join(subredes))
	_scanning = false
	_reconnect_timer = ReconnectSeconds


# --- Loop ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if _reconnect_timer > 0.0:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_buscar_y_conectar()
		return

	websocket.poll()
	match websocket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not conectado:
				conectado = true
				_set_status("Conectado a %s" % url)
			while websocket.get_available_packet_count() > 0:
				_procesar(websocket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if conectado:
				conectado = false
				_set_status("Conexión cerrada, reconectando...")
				_reconnect_timer = ReconnectSeconds

	if conectado:
		_suavizar(delta)
		if _vista:
			_transmitir_vista(delta)


## Transformada de la cabeza del jugador. Los pivotes de ojo cuelgan de los
## SubViewport del visor, no del jugador, así que hay que ir a buscarla ahí:
## tomando la del Player la transmisión no seguiría el giro de la cabeza.
func _transformada_cabeza() -> Transform3D:
	if _camera:
		var pivote = _camera.get("LeftEyePivot")
		if pivote is Node3D:
			return (pivote as Node3D).global_transform
	var t := global_transform
	if _player:
		t = _player.global_transform
		t.origin += Vector3(0, 1.75, 0)
	return t


## Manda un cuadro de la vista del jugador a la PC. El envío va estrangulado a
## VistaFps porque get_image() obliga a bajar la textura de la GPU a la CPU y eso
## frena el render: a 60 por segundo se notaba el tirón en el visor.
func _transmitir_vista(delta: float) -> void:
	_vista_cam.global_transform = _transformada_cabeza()
	_t_vista += delta
	if _t_vista < 1.0 / maxf(VistaFps, 1.0):
		return
	_t_vista = 0.0
	var tex := _vista.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	if VistaVolteada:
		img.flip_y()
	img.convert(Image.FORMAT_RGB8)      # el JPEG no admite canal alfa
	var buf := img.save_jpg_to_buffer(VistaCalidad)
	if buf.size() > 0:
		websocket.send(buf, WebSocketPeer.WRITE_MODE_BINARY)


## Corre el filtro una vez por frame y vuelca el resultado en la escena.
func _suavizar(delta: float) -> void:
	var pos := {}
	for id in _points:
		pos[id] = _filters[id].filtrar(_targets[id], delta)
	_normalizar(pos)
	for id in _points:
		_points[id].position = pos[id]

	# El esqueleto de debug acompaña al jugador: con FollowHead el jugador se
	# mueve adonde caiga la nariz, así que uno fijo en el mundo se pierde de
	# vista apenas empieza a llegar movimiento.
	if _debug_cloud and _player:
		_debug_cloud.global_position = _player.global_position \
			+ Vector3(0, DebugHipHeight, 0) + _frente * DebugDistance

	if not _debug_points.is_empty():
		# El esqueleto de debug se recentra en la cadera cada frame, así queda
		# entero a la vista sin importar cómo esté encuadrada la persona.
		var cadera_dbg := Vector3.ZERO
		if _points.has(23) and _points.has(24):
			cadera_dbg = (_points[23].position + _points[24].position) * 0.5
		for id in _debug_points:
			_debug_points[id].position = _points[id].position - cadera_dbg
	for bone in BONES:
		_update_bone(bone, _points, _bones)
		if not _debug_bones.is_empty():
			_update_bone(bone, _debug_points, _debug_bones)
	if FollowHead:
		_mover_cabeza()


## Escala la nube para que el torso mida lo que el del personaje y la apoya en el
## piso por los tobillos.
##
## Es la misma corrección que ya se les hacía a los puntos que van contra el
## muro. Hacerla acá, una sola vez, garantiza que el cuerpo que se VE sea
## exactamente el que se COMPARA: antes el esqueleto 3D quedaba en coordenadas
## del encuadre y el de la pared normalizado, así que uno se hundía en el piso
## mientras el otro se veía bien.
func _normalizar(pos: Dictionary) -> void:
	if not NormalizarNube:
		return
	var hombros: Vector3 = (pos[11] + pos[12]) * 0.5
	var cadera: Vector3 = (pos[23] + pos[24]) * 0.5
	var torso := Vector2(hombros.x - cadera.x, hombros.y - cadera.y).length()
	if torso < 0.01:
		return          # todavía no llegó nadie: dejar la nube como está
	var k := _torso_objetivo() / torso
	var tobillos: float = (pos[27].y + pos[28].y) * 0.5
	# El piso está a -CloudHeight en coordenadas locales de la nube.
	var y0 := -CloudHeight + _altura_tobillo()
	for id in pos:
		var p: Vector3 = pos[id]
		pos[id] = Vector3(p.x * k, y0 + (p.y - tobillos) * k, p.z * k)


## Largo del torso y altura del tobillo del personaje, en metros. Acá van los del
## cuerpo de referencia; el gestor del juego los sobreescribe con los de la
## calibración, para que la nube siga las medidas de quien está jugando.
func _torso_objetivo() -> float:
	return TorsoMetros

func _altura_tobillo() -> float:
	return 0.07


## Por el mismo canal llegan dos cosas distintas: los landmarks que publica el
## servidor y, cuando corre el espejo, el estado que retransmite el visor.
func _procesar(raw: String) -> void:
	var data = JSON.parse_string(raw)
	if data == null:
		return
	if data.has("landmarks"):
		_procesar_landmarks(data)
	elif data.has("est"):
		recibir_estado(data)
	elif data.has("cmd"):
		recibir_comando(data["cmd"])


## La sobreescribe el gestor del juego para aplicar el estado en el espejo.
func recibir_estado(_data: Dictionary) -> void:
	pass


## La sobreescribe el gestor del juego para ejecutar en el visor lo que se
## aprieta desde la PC.
func recibir_comando(_cmd) -> void:
	pass


## Manda un mensaje JSON por el mismo WebSocket de los landmarks.
func enviar_json(data: Dictionary) -> void:
	if conectado:
		websocket.send_text(JSON.stringify(data))


func _procesar_landmarks(data: Dictionary) -> void:
	for lm in data["landmarks"]:
		var id := int(lm["id"])
		if not _targets.has(id):
			continue
		# x,y normalizados; y se invierte porque en la imagen 0 es arriba.
		# Solo se guarda el objetivo: el filtrado corre por frame en _process,
		# porque los datos llegan a 30 Hz y la vista se dibuja más rápido, así
		# que aplicarlo acá dejaría escalones entre paquete y paquete.
		_targets[id] = Vector3(
			(float(lm["x"]) - 0.5) * CloudScale,
			(0.5 - float(lm["y"])) * CloudScale,
			float(lm["z"]) * CloudScale * LandmarkDepth)

	_frames += 1
	if _frames % 30 == 0:
		_set_status("Recibiendo (%d frames)" % _frames)


## Ubica al jugador de modo que sus ojos caigan exactamente sobre el landmark 0
## (nose). La cámara suma EyeHeight por encima de la posición del Player, así
## que hay que descontarla para que la cabeza quede en el punto y no encima.
func _mover_cabeza() -> void:
	if _player == null or not _points.has(0):
		return
	# Del landmark solo se toma el corrimiento lateral y cuánto se agachó: el
	# sitio en el escenario es el que quedó en la escena. Usar la posición
	# absoluta lo teletransportaba al plano de la nube, a CloudDistance del
	# borde, y la profundidad de MediaPipe lo terminaba de empujar fuera del mapa.
	var lateral: Vector3 = _cloud.global_transform.basis \
		* Vector3(_points[0].position.x, 0.0, 0.0)
	_player.global_position = Vector3(
		_pos_inicial.x + lateral.x,
		_pos_inicial.y + _agachado(),
		_pos_inicial.z + lateral.z)
	# El Player es un CharacterBody3D con gravedad: sin anular la velocidad,
	# move_and_slide lo sigue desplazando entre frames y la vista tiembla.
	if _player is CharacterBody3D:
		_player.velocity = Vector3.ZERO


func _p2(id: int) -> Vector2:
	var mi = _points.get(id)
	return Vector2.ZERO if mi == null else Vector2(mi.position.x, mi.position.y)


## Cuánto bajó la cabeza respecto de estar de pie, en metros (0 o negativo).
##
## No se usa la y cruda del landmark: MediaPipe la normaliza al encuadre, así que
## la altura del punto de vista terminaba dependiendo de cómo estuviera framada
## la persona y no de su postura — de ahí que la cámara quedara a la altura del
## pecho. Se mide cuánto sobresale la cabeza por encima de la cadera, en torsos,
## y se compara contra lo que sobresale estando de pie.
func _agachado() -> float:
	for id in [0, 11, 12, 23, 24]:
		if _points.get(id) == null:
			return 0.0
	var cadera := (_p2(23) + _p2(24)) * 0.5
	var hombros := (_p2(11) + _p2(12)) * 0.5
	var torso := hombros.distance_to(cadera)
	if torso < 0.01:
		return 0.0
	var sobre_cadera := (_p2(0).y - cadera.y) / torso
	return minf(0.0, (sobre_cadera - CabezaSobreCaderaDePie) * TorsoMetros)


## Estira y orienta el cilindro entre los dos landmarks del hueso.
func _update_bone(bone: Array, puntos: Dictionary, huesos: Dictionary) -> void:
	var a: MeshInstance3D = puntos.get(bone[0])
	var b: MeshInstance3D = puntos.get(bone[1])
	var mi: MeshInstance3D = huesos.get(bone)
	if a == null or b == null or mi == null:
		return
	var delta := b.position - a.position
	var len := delta.length()
	if len < 0.001:
		mi.visible = false
		return
	mi.visible = true
	mi.position = a.position + delta * 0.5
	mi.scale = Vector3(1, len, 1)
	# El cilindro nace apuntando a +Y; se lo alinea con el hueso.
	var axis := Vector3.UP.cross(delta.normalized())
	if axis.length() < 0.001:
		mi.rotation = Vector3.ZERO
	else:
		mi.rotation = Basis(axis.normalized(),
			Vector3.UP.angle_to(delta.normalized())).get_euler()


func _exit_tree() -> void:
	if conectado:
		websocket.close()
