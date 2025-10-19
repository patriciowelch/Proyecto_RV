extends Node3D

var websocket: WebSocketPeer
var url = ""
var conectado = false
@onready var label = $CanvasLayer/Label
# Relación entre los nombres de los nodos N y los puntos P
var landmark_to_node = {
	"N11": "P11",
	"N12": "P12",
	"N13": "P13",
	"N14": "P14",
	"N15": "P15",
	"N16": "P16",
	"N0":  "P0",
	"N23": "P23",
	"N24": "P24",
	"N25": "P25",
	"N26": "P26",
	"N27": "P27",
	"N28": "P28"
}

# Acceso dinámico a los nodos P
@onready var node_refs = {}
@onready var player = $Player
# Registro de acciones activas
var acciones_activas = {}

func _ready():
	label.text = "Cliente WebSocket iniciado" + '\n'
	websocket = WebSocketPeer.new()
	# Guardar referencias a los nodos P
	for k in landmark_to_node.values():
		node_refs[k] = $Nube.get_node(k)
	# Escanear IPs y conectar
	escanear_ips_y_conectar()

# Escanea el rango 192.168.137.1-30 y conecta al primer servidor WebSocket disponible
func escanear_ips_y_conectar(puerto: int = 8765, inicio: int = 1, fin: int = 30) -> void:
	var base_ip = "192.168.137."
	async_func(base_ip, puerto, inicio, fin)

# Función asíncrona para el escaneo
func async_func(base_ip, puerto, inicio, fin) -> void:
	await get_tree().process_frame
	for i in range(inicio, fin + 1):
		var ip = base_ip + str(i)
		var test_url = "ws://" + ip + ":" + str(puerto)
		var ws = WebSocketPeer.new()
		var err = ws.connect_to_url(test_url)
		if err == OK:
			var timeout = 1.0 # segundos
			var t = 0.0
			while ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING and t < timeout:
				ws.poll()
				await get_tree().create_timer(0.1).timeout
				t += 0.1
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				url = test_url
				label.text += "\n¡Servidor encontrado en: " + url + "\n"
				ws.close()
				conectar_servidor()
				return
		ws.close()
	label.text += "\nNo se encontró servidor WebSocket en el rango.\n"

func conectar_servidor():
	label.text += "Conectando a: " + str(url) + '\n'
	var error = websocket.connect_to_url(url)
	if error != OK:
		label.text += "Error al intentar conectar: " + str(error) + '\n'
		return

func _process(delta):
	# Actualizar el estado del WebSocket
	websocket.poll()
	
	var estado = websocket.get_ready_state()
	
	match estado:
		WebSocketPeer.STATE_CONNECTING:
			# Aún conectando, no hacer nada
			pass
			
		WebSocketPeer.STATE_OPEN:
			if not conectado:
				label.text+="¡Conectado al servidor WebSocket!"+'\n'
				conectado = true
				enviar_mensaje()
			else:
				var error = websocket.send_text("estado_teclas")
				if error != OK:
					print("Error al enviar mensaje: "+str(error)+'\n')
			
			# Verificar si hay mensajes del servidor
			while websocket.get_available_packet_count() > 0:
				label.text=""
				var mensaje = websocket.get_packet().get_string_from_utf8()
				var info = mensaje.split(",")
				if info.size() == 13:
					var landmark_data = {}
					for i in info:
						var parts = i.split("_")
						var lname = parts[0]
						var vec = Vector3(int(parts[1])/100.0, 8-int(parts[2])/100.0, int(parts[3])/100.0)
						landmark_data[lname] = vec
					# Actualizar nodos según el mapeo
					for lname in landmark_to_node.keys():
						if landmark_data.has(lname):
							node_refs[landmark_to_node[lname]].update_from_landmark(landmark_data[lname])
					# Posicionar el player en la posición global de P0 si existe
					if node_refs.has("P0"):
						player.position = node_refs["P0"].global_position
				
		WebSocketPeer.STATE_CLOSING:
			label.text+="Cerrando conexión..."+'\n'
			
		WebSocketPeer.STATE_CLOSED:
			if conectado:
				label.text+="Conexión cerrada"+'\n'
				conectado = false

func enviar_mensaje():
	if not conectado:
		label.text+="No hay conexión WebSocket"+'\n'
		return
	
	var mensaje = "¡Hola desde Godot WebSocket!"
	label.text+="Enviando mensaje: "+str(mensaje)+'\n'
	
	var error = websocket.send_text(mensaje)
	if error != OK:
		label.text+="Error al enviar mensaje: "+str(error)+'\n'

func desconectar():
	if conectado:
		websocket.close()
		conectado = false

func _exit_tree():
	# Limpiar al salir
	if conectado:
		desconectar()
