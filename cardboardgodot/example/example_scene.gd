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
@export var CloudDistance : float = 3.0
@export var CloudHeight : float = 1.0
## Metros de mundo por unidad normalizada de MediaPipe.
@export var CloudScale : float = 2.0
@export var PointRadius : float = 0.06
## Si está activo, el landmark 0 (nose, la cabeza) pasa a ser la cabeza del
## jugador: los ojos se ubican exactamente en ese punto, así que mover la
## cabeza frente a la cámara mueve el punto de vista en VR.
@export var FollowHead : bool = true

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

var websocket := WebSocketPeer.new()
var url := ""
var conectado := false

var _cloud: Node3D
var _player: Node3D
var _camera: Node
var _points: Dictionary = {}
## Última posición cruda recibida por red, antes de filtrar.
var _targets: Dictionary = {}
var _filters: Dictionary = {}
var _bones: Dictionary = {}
var _status: Label3D
var _reconnect_timer := 0.0
var _scanning := false
var _frames := 0


func _ready() -> void:
	_build_cloud()
	_set_status("Buscando servidor en %sX:%d ..." % [SubnetBase, ServerPort])
	_buscar_y_conectar()


# --- Construcción de la nube --------------------------------------------------

func _build_cloud() -> void:
	_cloud = Node3D.new()
	add_child(_cloud)
	_player = get_node_or_null("Player")
	if _player:
		_camera = _player.get_node_or_null("CardboardVRCamera3D")
	var origin: Vector3 = Vector3.ZERO if _player == null else _player.global_position
	# Alineado con el -Z del mundo, que es adonde mira la vista al recentrar.
	_cloud.global_position = origin + Vector3(0, CloudHeight, -CloudDistance)

	var point_mat := StandardMaterial3D.new()
	point_mat.albedo_color = Color(0.2, 1.0, 0.4)
	point_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.2, 0.7, 1.0)
	bone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for id in LANDMARK_IDS:
		var sphere := SphereMesh.new()
		sphere.radius = PointRadius
		sphere.height = PointRadius * 2.0
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.material_override = point_mat
		_cloud.add_child(mi)
		_points[id] = mi
		_targets[id] = Vector3.ZERO
		var corte := MinCutoff * (HeadCutoffFactor if id == 0 else 1.0)
		_filters[id] = OneEuro.new(corte, SmoothBeta)

	for bone in BONES:
		var cyl := CylinderMesh.new()
		cyl.top_radius = PointRadius * 0.4
		cyl.bottom_radius = PointRadius * 0.4
		cyl.height = 1.0
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = bone_mat
		_cloud.add_child(mi)
		_bones[bone] = mi

	_status = Label3D.new()
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.no_depth_test = true
	_status.pixel_size = 0.004
	_status.modulate = Color(1, 1, 0.4)
	_status.position = Vector3(0, 2.2, 0)
	_cloud.add_child(_status)


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
	var bases := []
	for addr in IP.get_local_addresses():
		if addr.count(".") != 3 or addr.begins_with("127."):
			continue
		var p := addr.split(".")
		var base := "%s.%s.%s." % [p[0], p[1], p[2]]
		if not bases.has(base):
			bases.append(base)
	if not bases.has(SubnetBase):
		bases.append(SubnetBase)
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


## Corre el filtro una vez por frame y vuelca el resultado en la escena.
func _suavizar(delta: float) -> void:
	for id in _points:
		_points[id].position = _filters[id].filtrar(_targets[id], delta)
	for bone in BONES:
		_update_bone(bone)
	if FollowHead:
		_mover_cabeza()


func _procesar(raw: String) -> void:
	var data = JSON.parse_string(raw)
	if data == null or not data.has("landmarks"):
		return

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
			float(lm["z"]) * CloudScale)

	_frames += 1
	if _frames % 30 == 0:
		_set_status("Recibiendo (%d frames)" % _frames)


## Ubica al jugador de modo que sus ojos caigan exactamente sobre el landmark 0
## (nose). La cámara suma EyeHeight por encima de la posición del Player, así
## que hay que descontarla para que la cabeza quede en el punto y no encima.
func _mover_cabeza() -> void:
	if _player == null or not _points.has(0):
		return
	var cabeza: Vector3 = _cloud.to_global(_points[0].position)
	var altura_ojos: float = 1.75
	if _camera:
		altura_ojos = _camera.EyeHeight
	_player.global_position = cabeza - Vector3(0, altura_ojos, 0)
	# El Player es un CharacterBody3D con gravedad: sin anular la velocidad,
	# move_and_slide lo sigue desplazando entre frames y la vista tiembla.
	if _player is CharacterBody3D:
		_player.velocity = Vector3.ZERO


## Estira y orienta el cilindro entre los dos landmarks del hueso.
func _update_bone(bone: Array) -> void:
	var a: MeshInstance3D = _points.get(bone[0])
	var b: MeshInstance3D = _points.get(bone[1])
	var mi: MeshInstance3D = _bones.get(bone)
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
