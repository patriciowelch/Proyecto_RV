class_name Rol

## El mismo proyecto corre en dos roles.
##
## VISOR es el telefono: lee el giroscopio, corre la logica del juego (muros,
## chequeo, calibracion) y publica su estado por WebSocket.
##
## ESPEJO es la PC: no simula nada propio, solo aplica lo que recibe, y a cambio
## puede poner la camara donde quiera. Sirve para ver y mostrar la partida sin
## tener que mirar por arriba del hombro del que tiene el visor puesto.
##
## Los landmarks NO viajan por este canal: nacen en la PC y los dos roles los
## reciben del mismo broadcast, asi que el cuerpo del jugador se dibuja igual en
## los dos sin mandar un byte de mas. Lo unico que hay que sincronizar es lo que
## no se puede deducir de los landmarks (ver gestor_juego._estado_actual).

static func es_espejo() -> bool:
	# En un preset de exportacion se agrega "espejo" como custom feature tag.
	if OS.has_feature("espejo"):
		return true
	# Y para desarrollo alcanza con correr el proyecto con --espejo, sin
	# exportar nada: los argumentos propios pueden venir por cualquiera de las
	# dos listas segun se pasen antes o despues de un "--".
	for lista in [OS.get_cmdline_args(), OS.get_cmdline_user_args()]:
		for a in lista:
			if a == "--espejo":
				return true
	return false

static func es_visor() -> bool:
	return not es_espejo()
