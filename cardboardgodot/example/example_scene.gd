extends Node3D

# Cuántas unidades de mundo cubre el ancho del cuerpo (x en [0,1] → [-SCALE/2, SCALE/2])
const SCALE = 3.0

var websocket: WebSocketPeer
var url = ""
var conectado = false

@onready var label   = $CanvasLayer/Label
@onready var player  = $Player

# Nodos P indexados por id de landmark (0, 11-16, 23-28)
const LANDMARK_IDS = [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
@onready var node_refs: Dictionary = {}


func _ready() -> void:
	label.text = "Cliente WebSocket iniciado\n"
	websocket = WebSocketPeer.new()
	for id in LANDMARK_IDS:
		node_refs[id] = $Nube.get_node("P" + str(id))
	escanear_ips_y_conectar()


# --- Conexión ----------------------------------------------------------------

func escanear_ips_y_conectar(puerto: int = 8765, inicio: int = 1, fin: int = 30) -> void:
	_async_escanear("192.168.137.", puerto, inicio, fin)

func _async_escanear(base_ip: String, puerto: int, inicio: int, fin: int) -> void:
	await get_tree().process_frame
	for i in range(inicio, fin + 1):
		var ip       = base_ip + str(i)
		var test_url = "ws://" + ip + ":" + str(puerto)
		var ws       = WebSocketPeer.new()
		if ws.connect_to_url(test_url) != OK:
			continue
		var t = 0.0
		while ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING and t < 1.0:
			ws.poll()
			await get_tree().create_timer(0.1).timeout
			t += 0.1
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			url = test_url
			label.text += "Servidor encontrado en: " + url + "\n"
			ws.close()
			conectar_servidor()
			return
		ws.close()
	label.text += "No se encontró servidor en el rango.\n"

func conectar_servidor() -> void:
	label.text += "Conectando a: " + url + "\n"
	if websocket.connect_to_url(url) != OK:
		label.text += "Error al conectar\n"


# --- Loop principal ----------------------------------------------------------

func _process(_delta: float) -> void:
	websocket.poll()
	match websocket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not conectado:
				label.text += "¡Conectado!\n"
				conectado = true
			while websocket.get_available_packet_count() > 0:
				_procesar_mensaje(websocket.get_packet().get_string_from_utf8())

		WebSocketPeer.STATE_CLOSED:
			if conectado:
				label.text += "Conexión cerrada\n"
				conectado = false


# --- Parseo de landmarks -----------------------------------------------------

func _procesar_mensaje(raw: String) -> void:
	var data = JSON.parse_string(raw)
	if data == null or not data.has("landmarks"):
		return
	label.text = ""
	for lm in data["landmarks"]:
		var id = int(lm["id"])
		if not node_refs.has(id):
			continue
		# x,y normalizados [0,1] → mundo centrado en 0; y invertido (0=arriba en imagen)
		var x_world = (float(lm["x"]) - 0.5) * SCALE
		var y_world = (0.5 - float(lm["y"])) * SCALE
		var z_world = float(lm["z"]) * SCALE
		node_refs[id].update_from_landmark(Vector3(x_world, y_world, z_world))
	# Player sigue la nariz
	if node_refs.has(0):
		player.position = node_refs[0].global_position


# --- Limpieza ----------------------------------------------------------------

func desconectar() -> void:
	if conectado:
		websocket.close()
		conectado = false

func _exit_tree() -> void:
	desconectar()
