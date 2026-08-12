class_name Muro extends Node3D

## Muro que avanza hacia el jugador con un agujero con forma de pose. El hueco
## se talla por resta booleana (CSG): a la caja del muro se le resta la UNION de
## los huesos de la pose (cajas orientadas), un cilindro en cada juntura para
## redondear las esquinas internas, y otro mas grande para la cabeza.
##
## Sobre la cara que mira al jugador se dibujan DOS esqueletos 2D superpuestos:
## el objetivo (translucido, donde tienen que quedar las articulaciones) y el del
## jugador (opaco, su proyeccion en vivo). Poder compararlos es lo que hace
## jugable la pose; el agujero solo, sin referencia, no dice donde pararse.
##
## OJO rendimiento: CSG recalcula en CPU. Para el build final de Cardboard
## conviene hornear cada muro a MeshInstance3D estatica. Para prototipar va bien.

signal alcanzo_plano(muro: Muro)

## TODO en metros, con el origen del muro AL RAS DEL PISO: la caja crece hacia
## arriba desde y=0 y el agujero se talla con los pies en y=0. Asi el muro se
## apoya en el borde de la pileta con solo ponerlo a la altura del piso.
var pose: Dictionary = {}
@export var ancho: float = 8.0       # cubre el ancho de la pileta (8.11)
@export var alto: float = 3.0
@export var espesor: float = 0.4
@export var grosor: float = 0.20     # ancho del hueco por hueso (diametro)
## Radio del hueco de la cabeza. Se deriva de las proporciones para que siga a la
## calibracion; en 0 o menos se recalcula, con un valor > 0 se fuerza a mano.
@export var r_cabeza: float = 0.0
## Cuanto mas grande que el craneo se abre el hueco de la cabeza. Toca SOLO el
## agujero de la pared: el nodo objetivo dibujado sale de r_nodo y no cambia. No
## se agranda r_craneo en Figuras porque de ahi sale tambien la corona de la
## figura, y mover eso reescalaria el personaje entero.
@export var holgura_cabeza: float = 1.6
@export var velocidad: float = 4.0   # m/s hacia +Z (hacia el jugador)
@export var z_plano: float = 0.0     # plano de evaluacion (donde esta el cuerpo)
## Cuanto sigue viajando el muro despues de atravesar al jugador antes de
## borrarse. Con 12 m ya paso la pileta entera y queda fuera de la vista.
@export var distancia_salida: float = 12.0
## Radio de acierto por articulacion, en metros. Cada nodo del jugador tiene que
## caer a menos de esto de su nodo objetivo.
##
## Medido sobre las 9 poses con las piernas ya cerradas: en 0.20 ningun palito
## (brazos y piernas al eje) pasa ningun muro, que era el agujero que habia que
## tapar, y cada pose aprueba la suya. Quedan 2 pares de poses que se aprueban
## entre si; baja a 0 con 0.16, pero eso empieza a pelearse con el ruido de
## MediaPipe. Se prefiere el 0.20 porque cruzarse de pose exige adoptar OTRA
## pose valida entera, cosa que nadie hace por accidente, mientras que el palito
## era quedarse quieto.
@export var tolerancia: float = 0.20
## Alfa del esqueleto objetivo dibujado sobre el muro.
@export var alfa_objetivos: float = 0.35
## Grosor de los huesos dibujados y radio de los nodos, en metros.
@export var ancho_linea: float = 0.045
@export var r_nodo: float = 0.07
## A que distancia del jugador empiezan a desvanecerse los dos esqueletos
## dibujados. Sirven para armar la pose mientras el muro viene de lejos, pero al
## llegar solo ensucian: la imagen de atravesar el agujero queda limpia.
@export var distancia_desvanecer: float = 3.5

## Los 13 nodos objetivo de la pose, en metros y en el orden de LANDMARK_IDS.
## De aca sale TODO: el agujero, el esqueleto objetivo dibujado y el chequeo.
var _objetivos: Array = []

## Identificador que asigna el visor, para poder emparejar este muro con su copia
## en el espejo.
var id: int = 0
## Indice de la pose dentro de Figuras.todas(), para que el espejo pueda armar
## el mismo muro sin que le manden la figura entera.
var idx_pose: int = 0
## En el espejo el muro no avanza solo: su z la manda el visor. Sin esto los dos
## correrian a distinto framerate y se separarian a los pocos segundos, porque
## tanto el avance como el spawn se calculan contra el delta local.
var pasivo := false

var _mat: StandardMaterial3D
var _evaluado := false
## Opacidad actual de los esqueletos dibujados: 1 lejos, 0 encima del jugador.
var _alfa := 1.0
var _mat_objetivo: StandardMaterial3D
var _mat_barras: StandardMaterial3D
# Esqueleto 2D del jugador sobre el muro: un nodo por articulacion (verde/rojo)
# y una barra por hueso.
var _marcadores: Array = []
var _mats_marc: Array = []
var _barras: Array = []

func configurar(p: Dictionary, vel: float, z_eval: float) -> void:
	pose = p
	velocidad = vel
	z_plano = z_eval

func _ready() -> void:
	if pose.is_empty():
		pose = Figuras.todas()[0]
	_objetivos = Figuras.landmarks(pose)
	if r_cabeza <= 0.0:
		r_cabeza = Figuras.r_craneo * Figuras.torso() * holgura_cabeza

	var comb := CSGCombiner3D.new()
	add_child(comb)

	var caja := CSGBox3D.new()
	caja.size = Vector3(ancho, alto, espesor)
	# La caja nace centrada en su origen; se la sube media altura para que el
	# borde de abajo quede en y=0, es decir al ras del piso.
	caja.position = Vector3(0.0, alto * 0.5, 0.0)
	_mat = _material_muro()
	caja.material = _mat
	comb.add_child(caja)

	# El hueco: union de huesos + cabeza, restada del muro.
	var hueco := CSGCombiner3D.new()
	hueco.operation = CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(hueco)
	for h in Figuras.HUESOS:
		hueco.add_child(_caja_hueso(_objetivos[h[0]], _objetivos[h[1]]))
	# Un cilindro en cada articulacion. Sin esto la union de cajas deja las
	# esquinas internas en angulo vivo y el agujero se lee amorfo; con esto cada
	# juntura queda redondeada y la silueta se lee como un esqueleto.
	for p in _objetivos:
		hueco.add_child(_cilindro(p, grosor * 0.5))
	hueco.add_child(_cilindro(_objetivos[0], r_cabeza))
	# Los huesos son tiras, asi que las zonas CERRADAS por huesos (el torso, entre
	# hombros y caderas, y el triangulo del cuello) no se restaban y quedaban como
	# islas de pared flotando en el medio del agujero, sin nada que las sostenga.
	# Hay que restarlas rellenas.
	hueco.add_child(_poligono([_objetivos[1], _objetivos[2], _objetivos[8], _objetivos[7]]))
	hueco.add_child(_poligono([_objetivos[0], _objetivos[1], _objetivos[2]]))

	_dibujar_objetivos()

## Rojo oscuro con manchado procedural. El ruido se genera en runtime (no hace
## falta ningun asset) y va por color_ramp directo al albedo, asi la pared se lee
## como material y no como un plano de color liso.
func _material_muro() -> StandardMaterial3D:
	var ruido := FastNoiseLite.new()
	ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ruido.frequency = 0.015
	ruido.fractal_octaves = 4

	var rampa := Gradient.new()
	rampa.set_color(0, Color(0.16, 0.025, 0.03))
	rampa.set_color(1, Color(0.40, 0.08, 0.07))

	var tex := NoiseTexture2D.new()
	tex.noise = ruido
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	tex.color_ramp = rampa

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(3.0, 1.5, 1.0)
	mat.roughness = 0.95
	mat.metallic = 0.0
	return mat

## Esqueleto 2D OBJETIVO, sobre la cara que mira al jugador: muestra en que
## posicion tiene que quedar cada articulacion para pasar. Va translucido y
## apenas mas atras que el del jugador, que se dibuja encima.
func _dibujar_objetivos() -> void:
	var z := espesor * 0.5 + 0.02
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.85, 1.0, alfa_objetivos)
	_mat_objetivo = mat
	for h in Figuras.HUESOS:
		_colocar_hueso(_nueva_barra(mat), _objetivos[h[0]], _objetivos[h[1]], z)
	# Los nodos van mas gordos que los del jugador, asi cuando la articulacion
	# llega a destino su marcador queda visiblemente dentro del objetivo.
	for p in _objetivos:
		var n := _nuevo_nodo(mat, r_nodo * 1.5)
		n.position = Vector3(p.x, p.y, z)

func _nueva_barra(mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE       # el largo real se aplica por escala
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	return mi

func _nuevo_nodo(mat: StandardMaterial3D, radio: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radio
	s.height = radio * 2.0
	mi.mesh = s
	mi.material_override = mat
	add_child(mi)
	return mi

## Estira y orienta una barra entre dos puntos del plano del muro.
func _colocar_hueso(mi: MeshInstance3D, a: Vector2, b: Vector2, z: float) -> void:
	var d := b - a
	var largo := d.length()
	if largo < 0.001:
		mi.visible = false
		return
	mi.visible = true
	mi.position = Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, z)
	mi.rotation = Vector3(0.0, 0.0, atan2(d.y, d.x))
	mi.scale = Vector3(largo, ancho_linea, ancho_linea)

func _caja_hueso(a: Vector2, b: Vector2) -> CSGBox3D:
	var d := b - a
	var largo: float = maxf(d.length(), 0.001)
	var box := CSGBox3D.new()
	box.size = Vector3(largo, grosor, espesor * 2.0)
	box.position = Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0.0)
	box.rotation = Vector3(0.0, 0.0, atan2(d.y, d.x))
	return box

## Area con signo: positiva si los vertices giran en sentido antihorario.
func _area_con_signo(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

## Region cerrada del cuerpo, extruida a lo largo del espesor del muro.
##
## Normaliza el sentido de giro: CSGPolygon3D lo necesita consistente, y segun de
## que nodos salga la region los vertices pueden llegar en cualquiera de los dos
## (el espejado de ids invierte el orden izquierda/derecha). El triangulo del
## cuello venia horario mientras el torso venia antihorario, y por eso no se
## restaba y quedaba un triangulito de pared en el pecho.
func _poligono(vertices: Array) -> CSGPolygon3D:
	var poli := CSGPolygon3D.new()
	var pts := PackedVector2Array()
	for v in vertices:
		pts.append(v)
	if _area_con_signo(pts) < 0.0:
		pts.reverse()
	poli.polygon = pts
	poli.mode = CSGPolygon3D.MODE_DEPTH
	poli.depth = espesor * 2.0
	poli.position = Vector3(0.0, 0.0, -espesor)
	return poli

func _cilindro(c: Vector2, radio: float) -> CSGCylinder3D:
	var cil := CSGCylinder3D.new()
	cil.radius = radio
	cil.height = espesor * 2.0
	cil.sides = 16
	cil.rotation = Vector3(PI / 2.0, 0.0, 0.0)  # eje del cilindro a lo largo de Z
	cil.position = Vector3(c.x, c.y, 0.0)
	return cil

## El muro NO frena en el plano de evaluacion: avisa que llego y sigue de largo,
## atravesando al jugador y perdiendose por detras. Frenarlo y pintarlo de
## verde/rojo cortaba el movimiento justo en el momento de mas tension; el
## resultado ahora lo da el flash de la camara.
func _process(delta: float) -> void:
	if not pasivo:
		position.z += velocidad * delta
	# El desvanecido sale de la z, asi que en el espejo sigue igual sin mandar
	# nada: se deduce de la posicion que ya viene sincronizada.
	_alfa = clampf((z_plano - position.z) / maxf(distancia_desvanecer, 0.001), 0.0, 1.0)
	if _mat_objetivo:
		_mat_objetivo.albedo_color.a = alfa_objetivos * _alfa
	if _mat_barras:
		_mat_barras.albedo_color.a = _alfa
	if pasivo:
		return
	if not _evaluado and position.z >= z_plano:
		_evaluado = true
		alcanzo_plano.emit(self)
	if position.z >= z_plano + distancia_salida:
		queue_free()

## Chequeo v2: cada articulacion del jugador tiene que estar cerca de SU nodo
## objetivo, no simplemente dentro del agujero. El agujero queda como guia
## visual. Los puntos llegan en el orden de LANDMARK_IDS, igual que _objetivos.
func evaluar(puntos: Array) -> Dictionary:
	var afuera := []
	for i in puntos.size():
		# Sentado las rodillas y los tobillos no cuentan (ver Figuras.se_chequea).
		if Figuras.se_chequea(i) and not _cerca(i, puntos[i]):
			afuera.append(puntos[i])
	return {"paso": afuera.is_empty(), "afuera": afuera}

func _cerca(i: int, p: Vector2) -> bool:
	if i >= _objetivos.size():
		return false
	return p.distance_to(_objetivos[i]) <= tolerancia

## Esqueleto 2D del JUGADOR en vivo, dibujado encima del objetivo: es la
## proyeccion de su cuerpo sobre el muro. Cada articulacion se pinta VERDE si ya
## llego a su nodo objetivo y ROJA si todavia hay que corregirla. Devuelve
## cuantas quedaron verdes. Se llama cada frame mientras el muro se acerca.
func actualizar_feedback(puntos: Array) -> int:
	if _marcadores.size() != puntos.size():
		_reset_marcadores(puntos.size())
	var verdes := 0
	var z := espesor * 0.5 + 0.06   # apenas por delante del esqueleto objetivo
	for i in puntos.size():
		var p: Vector2 = puntos[i]
		var ok := _cerca(i, p)
		_marcadores[i].position = Vector3(p.x, p.y, z)
		var c := Color(0.2, 0.85, 0.35) if ok else Color(0.9, 0.25, 0.25)
		c.a = _alfa
		_mats_marc[i].albedo_color = c
		if ok:
			verdes += 1
	for j in _barras.size():
		var h: Array = Figuras.HUESOS[j]
		if h[0] < puntos.size() and h[1] < puntos.size():
			_colocar_hueso(_barras[j], puntos[h[0]], puntos[h[1]], z)
		else:
			_barras[j].visible = false
	return verdes

func _reset_marcadores(n: int) -> void:
	for m in _marcadores:
		m.queue_free()
	for b in _barras:
		b.queue_free()
	_marcadores.clear()
	_mats_marc.clear()
	_barras.clear()

	var mat_hueso := StandardMaterial3D.new()
	mat_hueso.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_hueso.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_hueso.albedo_color = Color(1.0, 0.85, 0.25, _alfa)
	_mat_barras = mat_hueso
	for h in Figuras.HUESOS:
		_barras.append(_nueva_barra(mat_hueso))

	for i in range(n):
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.albedo_color = Color(0.9, 0.25, 0.25, _alfa)
		_marcadores.append(_nuevo_nodo(mm, r_nodo))
		_mats_marc.append(mm)
