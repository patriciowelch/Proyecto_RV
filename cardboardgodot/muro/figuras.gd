class_name Figuras

## Cada figura es un ESQUELETO (huesos + cabeza) en coordenadas del plano del
## muro (x derecha, y arriba). Las 9 poses replican el storyboard de sticks
## provisto, pero de ellas se toma solo la DIRECCION de cada segmento: los
## LARGOS salen de las proporciones de mas abajo. Asi la pose sigue siendo la
## que se dibujo y ademas le entra un cuerpo real.
##
## El mismo esqueleto talla el agujero, dibuja los nodos objetivo sobre el muro
## y sirve para el chequeo, para que las tres cosas no puedan desincronizarse.

const CUELLO := Vector2(0.0, 1.05)
const CADERA := Vector2(0.0, -0.35)
## Largo del torso en unidades de figura: es la unidad de medida de todo lo demas.
const TORSO := 1.40      # CUELLO.y - CADERA.y

## Altura del personaje, en metros.
const ALTURA := 1.8

## Proporciones del cuerpo en MULTIPLOS DEL TORSO (hombros a cadera), medidas
## sobre una persona parada frente a la camara: 120 frames, mediana, con una
## dispersion p10-p90 por debajo del 2%.
##
## Las figuras del storyboard venian dibujadas con brazos y piernas cortos: los
## tobillos caian a 1.11 torsos de la cadera cuando en un cuerpo real caen a
## 1.47, asi que para llegar al nodo objetivo habia que levantar los pies del
## piso. De ahi que los largos salgan de aca y no del dibujo.
##
## OJO con los valores horizontales (r_hombro y los brazos): MediaPipe normaliza
## x por el ancho de la imagen e y por el alto, por separado, asi que lo medido
## en horizontal viene deformado por el aspect ratio de la camara. Para el juego
## no importa mientras la calibracion se tome en el mismo espacio en que despues
## se compara al jugador, porque la deformacion se cancela; si importa si algun
## dia se quiere que el agujero tenga proporciones fisicas correctas.
##
## Son `static var` y no `const` porque la calibracion en T las reescribe con las
## medidas de quien vaya a jugar.
const POR_DEFECTO := {
	"r_hombro": 0.253,       # medio ancho de hombros
	"r_cadera": 0.142,       # medio ancho de cadera
	"l_brazo_sup": 0.364,    # hombro a codo
	"l_antebrazo": 0.380,    # codo a muneca
	"l_muslo": 0.752,        # cadera a rodilla
	"l_pierna": 0.720,       # rodilla a tobillo
	"l_nariz": 0.405,        # cuello a nariz
}

static var r_hombro: float = POR_DEFECTO["r_hombro"]
static var r_cadera: float = POR_DEFECTO["r_cadera"]
static var l_brazo_sup: float = POR_DEFECTO["l_brazo_sup"]
static var l_antebrazo: float = POR_DEFECTO["l_antebrazo"]
static var l_muslo: float = POR_DEFECTO["l_muslo"]
static var l_pierna: float = POR_DEFECTO["l_pierna"]
static var l_nariz: float = POR_DEFECTO["l_nariz"]
## Estos dos no se pueden medir con MediaPipe: no ve ni el piso ni el craneo.
static var l_pie := 0.13            # tobillo al piso
static var r_craneo := 0.29         # radio del hueco de la cabeza

## Huesos entre los 13 nodos, por INDICE en ese arreglo. Es el esqueleto
## completo. Los dos primeros son el cuello, que en los landmarks de MediaPipe
## no existe, para que la figura no quede con la cabeza suelta.
const HUESOS := [
	[0, 1], [0, 2],
	[1, 2], [1, 3], [3, 5], [2, 4], [4, 6],
	[1, 7], [2, 8], [7, 8],
	[7, 9], [9, 11], [8, 10], [10, 12],
]

## MediaPipe etiqueta izquierda/derecha segun el lado de la IMAGEN, y el
## servidor invierte el frame (cv2.flip en servidor.py) para que el preview se
## vea como un espejo. Con eso el landmark 11 ("left_shoulder") cae del lado +x
## de la nube, que en VR es la DERECHA del jugador, asi que los ids "left" tienen
## que apuntar al lado derecho de la figura. Si alguna vez se saca el flip del
## servidor, poner esto en false y queda alineado de nuevo.
const IDS_ESPEJADOS := true


# --- Escala vertical -----------------------------------------------------------

## Y de los pies y de la corona, en unidades de figura, sobre la pose de pie.
## Salen de las proporciones, asi que calibrar mueve tambien el piso y el techo
## de la figura en vez de dejarlos apuntando a la geometria vieja.
static func y_pies() -> float:
	return CADERA.y - (l_muslo + l_pierna + l_pie) * TORSO

static func y_corona() -> float:
	return CUELLO.y + (l_nariz + r_craneo) * TORSO

## Y del tobillo con la persona de pie y las piernas estiradas. Es la altura a la
## que se apoya cualquier pose, agachada o no.
static func y_tobillo_de_pie() -> float:
	return CADERA.y - (l_muslo + l_pierna) * TORSO

## Metros por unidad de figura, para que la pose de pie mida ALTURA.
static func escala() -> float:
	return ALTURA / (y_corona() - y_pies())

## Largo del torso de la figura en metros. Es la referencia rigida para escalar
## el cuerpo del jugador: siempre esta a la vista y no cambia con la postura.
static func torso() -> float:
	return TORSO * escala()

## Pasa un punto de la figura al plano del muro: metros, con y=0 en el piso.
static func a_metros(p: Vector2) -> Vector2:
	return Vector2(p.x, p.y - y_pies()) * escala()


# --- Esqueleto de una pose -----------------------------------------------------

## Cuanto se conserva de la apertura lateral de las piernas que traia el dibujo.
## Las figuras del storyboard abren mucho mas las piernas de lo que abre una
## persona parada frente a la camara, tanto en las poses de pie como en las de
## piernas separadas, asi que se comprime la componente horizontal de muslo y
## pantorrilla. En 1.0 queda la apertura original del dibujo.
static var apertura_piernas := 0.55

## Modo sentado: el jugador juega sentado frente a la camara.
##
## No hay poses aparte. Cambian dos cosas en la reconstruccion: las piernas van
## juntas y rectas (apertura 0), y la vertical se ancla en la CADERA en vez de en
## los tobillos, porque sentado los tobillos quedan bajo el escritorio y
## MediaPipe los extrapola sin ninguna base.
static var sentado := false
## Cuanto se levanta el cuerpo respecto de la cadera detectada, en torsos.
## Sentado la cadera de MediaPipe cae mas abajo de lo que corresponde al tronco;
## esto sube la figura sin tocar las poses.
static var alza_cadera := 0.15

## Indices (dentro de los 13 nodos) de rodillas y tobillos. Sentado no se
## chequean: las piernas estan dobladas bajo la mesa y en la proyeccion frontal
## no hay forma de que coincidan con ningun objetivo.
const IDX_PIERNAS := [9, 10, 11, 12]

static func apertura() -> float:
	return 0.0 if sentado else apertura_piernas

## Si esta articulacion cuenta para aprobar el muro.
static func se_chequea(i: int) -> bool:
	return not (sentado and IDX_PIERNAS.has(i))

## Avanza `largo` desde `desde` en la direccion que va de `a` a `b`.
static func _hacia(desde: Vector2, a: Vector2, b: Vector2, largo: float) -> Vector2:
	return _hacia_dir(desde, b - a, largo)

## Igual, pero con la direccion ya dada: las piernas necesitan corregirla antes.
static func _hacia_dir(desde: Vector2, d: Vector2, largo: float) -> Vector2:
	if d.length() < 0.0001:
		d = Vector2.DOWN
	return desde + d.normalized() * largo

## Direccion de un segmento de pierna, con la apertura lateral comprimida.
static func _dir_pierna(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	d.x *= apertura()
	if sentado:
		d.x = 0.0        # piernas juntas y rectas
	return d

## Los 13 nodos de la pose en unidades de figura, en el MISMO orden que
## LANDMARK_IDS: nariz, hombros, codos, munecas, caderas, rodillas, tobillos.
static func landmarks_figura(pose: Dictionary) -> Array:
	var h: Array = pose["huesos"]
	var cuello: Vector2 = h[0][0]
	var cadera: Vector2 = h[0][1]

	var hom_i := cuello + Vector2(-r_hombro * TORSO, 0.0)
	var hom_d := cuello + Vector2(r_hombro * TORSO, 0.0)
	var cad_i := cadera + Vector2(-r_cadera * TORSO, 0.0)
	var cad_d := cadera + Vector2(r_cadera * TORSO, 0.0)

	# Los brazos del storyboard nacen en el cuello y las piernas en el centro de
	# la cadera; aca arrancan en el hombro y en la cadera de cada lado, que es
	# donde estan los landmarks de MediaPipe.
	var codo_i := _hacia(hom_i, cuello, h[2][1], l_brazo_sup * TORSO)
	var codo_d := _hacia(hom_d, cuello, h[4][1], l_brazo_sup * TORSO)
	var mun_i := _hacia(codo_i, h[2][1], h[3][1], l_antebrazo * TORSO)
	var mun_d := _hacia(codo_d, h[4][1], h[5][1], l_antebrazo * TORSO)
	var rod_i := _hacia_dir(cad_i, _dir_pierna(cadera, h[6][1]), l_muslo * TORSO)
	var rod_d := _hacia_dir(cad_d, _dir_pierna(cadera, h[8][1]), l_muslo * TORSO)
	var tob_i := _hacia_dir(rod_i, _dir_pierna(h[6][1], h[7][1]), l_pierna * TORSO)
	var tob_d := _hacia_dir(rod_d, _dir_pierna(h[8][1], h[9][1]), l_pierna * TORSO)
	var nariz := _hacia(cuello, cuello, pose["cabeza"], l_nariz * TORSO)

	# Cada par es (lado izquierdo de la figura, lado derecho).
	var pares := [
		[hom_i, hom_d], [codo_i, codo_d], [mun_i, mun_d],
		[cad_i, cad_d], [rod_i, rod_d], [tob_i, tob_d],
	]
	var r := [nariz]
	for par in pares:
		r.append(par[1] if IDS_ESPEJADOS else par[0])
		r.append(par[0] if IDS_ESPEJADOS else par[1])

	# La figura se arma colgando de la cadera, que esta fija, asi que una pose
	# agachada terminaba con los pies en el aire. Se baja entera hasta apoyar los
	# tobillos: agacharse tiene que bajar la cadera, no levantar los pies. El
	# cuerpo del jugador se ancla igual (ver gestor_juego._puntos_muro).
	var dy: float = y_tobillo_de_pie() - (r[11].y + r[12].y) * 0.5
	for i in r.size():
		r[i] = (r[i] as Vector2) + Vector2(0.0, dy)
	return r

## Lo mismo, ya en metros y con y=0 en el piso: son los nodos que el muro dibuja,
## contra los que se mide cada articulacion, y con los que se talla el agujero.
static func landmarks(pose: Dictionary) -> Array:
	var r := []
	for p in landmarks_figura(pose):
		r.append(a_metros(p))
	return r


# --- Calibracion ---------------------------------------------------------------

## Reescribe las proporciones con las de una persona real. `medidas` viene en
## multiplos del torso (ver gestor_juego._medidas). No toca l_pie ni r_craneo,
## que MediaPipe no puede ver.
##
## Descarta la calibracion entera si alguna medida se aleja mas de `margen` de la
## de referencia, y en ese caso no toca nada. Entre personas estas proporciones
## varian mucho menos que eso; lo que filtra son capturas con el cuerpo cortado
## por el encuadre o los brazos a medio estirar, que devuelven largos absurdos.
## La validacion importa porque quien calibra tiene el visor puesto y no puede
## ver lo que capturo: sin esto, una mala toma deforma los muros en silencio.
static func calibrar(medidas: Dictionary, margen := 0.35) -> bool:
	for k in POR_DEFECTO:
		if not medidas.has(k):
			return false
		var ref: float = POR_DEFECTO[k]
		var v: float = medidas[k]
		if v < ref * (1.0 - margen) or v > ref * (1.0 + margen):
			return false
	# Dos invariantes anatomicos. Hacen falta porque una captura mala puede tener
	# todas las medidas dentro del margen y aun asi describir un cuerpo imposible:
	# la toma fallida de prueba dio antebrazo 0.21 contra brazo 0.50, y pantorrilla
	# 0.78 contra muslo 0.42. Los dos segmentos de un miembro son parecidos entre
	# si en cualquier persona, asi que la relacion entre ellos delata el error.
	if not _relacion_ok(medidas["l_brazo_sup"], medidas["l_antebrazo"], 0.65, 1.6):
		return false
	if not _relacion_ok(medidas["l_muslo"], medidas["l_pierna"], 0.75, 1.6):
		return false
	r_hombro = medidas["r_hombro"]
	r_cadera = medidas["r_cadera"]
	l_brazo_sup = medidas["l_brazo_sup"]
	l_antebrazo = medidas["l_antebrazo"]
	l_muslo = medidas["l_muslo"]
	l_pierna = medidas["l_pierna"]
	l_nariz = medidas["l_nariz"]
	return true

static func _relacion_ok(a: float, b: float, minimo: float, maximo: float) -> bool:
	if b <= 0.0001:
		return false
	var r := a / b
	return r >= minimo and r <= maximo

static func resumen() -> String:
	return "hombro %.2f  brazo %.2f+%.2f  cadera %.2f  pierna %.2f+%.2f" % [
		r_hombro, l_brazo_sup, l_antebrazo, r_cadera, l_muslo, l_pierna]


# --- Las 9 poses ---------------------------------------------------------------

## codo/muneca = brazos ; rodilla/tobillo = piernas ; i=izquierda d=derecha
## De estas coordenadas se usa solo la direccion de cada segmento.
static func _pose(nombre: String, cabeza: Vector2,
		ci: Vector2, mi: Vector2, cd: Vector2, md: Vector2,
		ri: Vector2, ti: Vector2, rd: Vector2, td: Vector2) -> Dictionary:
	return {
		"nombre": nombre,
		"cabeza": cabeza,
		"huesos": [
			[CUELLO, CADERA],
			[CUELLO, cabeza],
			[CUELLO, ci], [ci, mi],
			[CUELLO, cd], [cd, md],
			[CADERA, ri], [ri, ti],
			[CADERA, rd], [rd, td],
		],
	}

## Poses que llegaron del editor del espejo. Si esta vacio se usan las del
## storyboard. Se guardan como datos planos y se reconstruyen con de_datos, asi
## viajan por el WebSocket sin ninguna serializacion especial.
static var poses_editadas: Array = []

static func todas() -> Array:
	if not poses_editadas.is_empty():
		return poses_editadas
	return storyboard()

## Los 9 puntos que definen una pose, en el orden que espera _pose(): cabeza,
## codo/muneca izquierdos, codo/muneca derechos, rodilla/tobillo izquierdos,
## rodilla/tobillo derechos.
static func a_datos(p: Dictionary) -> Dictionary:
	var h: Array = p["huesos"]
	var pts := [p["cabeza"], h[2][1], h[3][1], h[4][1], h[5][1],
		h[6][1], h[7][1], h[8][1], h[9][1]]
	var planos := []
	for v in pts:
		planos.append(snappedf((v as Vector2).x, 0.001))
		planos.append(snappedf((v as Vector2).y, 0.001))
	return {"nombre": p["nombre"], "pts": planos}

static func de_datos(d: Dictionary) -> Dictionary:
	var a: Array = d["pts"]
	if a.size() < 18:
		return {}
	var v := []
	for i in 9:
		v.append(Vector2(float(a[i * 2]), float(a[i * 2 + 1])))
	return _pose(String(d.get("nombre", "sin nombre")),
		v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8])

static func lista_a_datos(poses: Array) -> Array:
	var r := []
	for p in poses:
		r.append(a_datos(p))
	return r

static func lista_de_datos(datos: Array) -> Array:
	var r := []
	for d in datos:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var p := de_datos(d)
		if not p.is_empty():
			r.append(p)
	return r

static func storyboard() -> Array:
	return [
		_pose("Agacharse", Vector2(-0.15, 1.65),
			Vector2(0.30, 0.55), Vector2(0.75, 0.05),
			Vector2(0.40, 0.45), Vector2(0.95, -0.05),
			Vector2(-0.20, -1.10), Vector2(-0.30, -1.90),
			Vector2(0.20, -1.10), Vector2(0.30, -1.90)),
		_pose("Correr", Vector2(0.10, 1.65),
			Vector2(-0.35, 0.65), Vector2(-0.50, 0.25),
			Vector2(0.35, 1.10), Vector2(0.45, 1.50),
			Vector2(-0.35, -1.15), Vector2(-0.70, -1.60),
			Vector2(0.45, -0.85), Vector2(0.30, -1.40)),
		_pose("Brazos a la derecha", Vector2(0.0, 1.65),
			Vector2(0.40, 1.00), Vector2(0.95, 0.95),
			Vector2(0.45, 0.90), Vector2(1.05, 0.85),
			Vector2(-0.20, -1.10), Vector2(-0.22, -1.90),
			Vector2(0.20, -1.10), Vector2(0.22, -1.90)),
		_pose("Brazos arriba en V", Vector2(0.0, 1.65),
			Vector2(-0.50, 1.40), Vector2(-0.90, 1.80),
			Vector2(0.50, 1.40), Vector2(0.90, 1.80),
			Vector2(-0.30, -1.10), Vector2(-0.40, -1.90),
			Vector2(0.30, -1.10), Vector2(0.40, -1.90)),
		_pose("Estrella (cuclillas)", Vector2(0.0, 1.65),
			Vector2(-0.55, 1.05), Vector2(-1.15, 1.10),
			Vector2(0.55, 1.05), Vector2(1.15, 1.10),
			Vector2(-0.70, -0.95), Vector2(-1.15, -1.55),
			Vector2(0.70, -0.95), Vector2(1.15, -1.55)),
		_pose("Brazos abajo en V", Vector2(0.0, 1.65),
			Vector2(-0.50, 0.55), Vector2(-0.95, 0.10),
			Vector2(0.50, 0.55), Vector2(0.95, 0.10),
			Vector2(-0.20, -1.10), Vector2(-0.22, -1.90),
			Vector2(0.20, -1.10), Vector2(0.22, -1.90)),
		_pose("Un brazo arriba (inclinado)", Vector2(-0.15, 1.65),
			Vector2(-0.30, 0.60), Vector2(-0.35, 0.10),
			Vector2(0.25, 1.40), Vector2(-0.05, 1.75),
			Vector2(-0.20, -1.10), Vector2(-0.15, -1.90),
			Vector2(0.15, -1.10), Vector2(0.20, -1.90)),
		_pose("Circulo sobre la cabeza", Vector2(0.0, 1.50),
			Vector2(-0.50, 1.35), Vector2(-0.15, 1.95),
			Vector2(0.50, 1.35), Vector2(0.15, 1.95),
			Vector2(-0.35, -1.10), Vector2(-0.50, -1.90),
			Vector2(0.35, -1.10), Vector2(0.50, -1.90)),
		_pose("Un brazo recto arriba", Vector2(0.0, 1.65),
			Vector2(-0.35, 0.60), Vector2(-0.45, 0.15),
			Vector2(0.30, 1.45), Vector2(0.50, 2.00),
			Vector2(-0.20, -1.10), Vector2(-0.20, -1.90),
			Vector2(0.20, -1.10), Vector2(0.20, -1.90)),
		# De frente y a segmentos de largo fijo, agacharse solo se puede
		# representar abriendo las rodillas: las piernas mantienen su largo pero
		# la cadera baja. Los brazos van al frente para equilibrar, como en una
		# sentadilla real.
		_pose("Agachado (cuclillas)", Vector2(0.0, 1.55),
			Vector2(-0.60, 0.95), Vector2(-1.15, 0.90),
			Vector2(0.60, 0.95), Vector2(1.15, 0.90),
			Vector2(-1.40, -0.70), Vector2(-1.00, -1.75),
			Vector2(1.40, -0.70), Vector2(1.00, -1.75)),
	]
