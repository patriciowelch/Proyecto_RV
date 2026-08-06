class_name Muro extends Node3D

## Muro que avanza hacia el jugador con un agujero con forma de pose. El hueco
## se talla por resta booleana (CSG): a la caja del muro se le resta la UNION de
## los huesos de la pose (cajas orientadas) mas un cilindro para la cabeza.
## OJO rendimiento: CSG recalcula en CPU. Para el build final de Cardboard
## conviene hornear cada muro a MeshInstance3D estatica. Para prototipar va bien.

signal alcanzo_plano(muro: Muro)

var pose: Dictionary = {}
@export var ancho: float = 5.5
@export var alto: float = 6.0
@export var espesor: float = 0.4
@export var grosor: float = 0.9      # ancho del hueco por hueso (diametro)
@export var r_cabeza: float = 0.55
@export var velocidad: float = 4.0   # m/s hacia +Z (hacia el jugador)
@export var z_plano: float = 0.0     # plano de evaluacion (donde esta el cuerpo)

var _mat: StandardMaterial3D
var _detenido := false

func configurar(p: Dictionary, vel: float, z_eval: float) -> void:
	pose = p
	velocidad = vel
	z_plano = z_eval

func _ready() -> void:
	if pose.is_empty():
		pose = Figuras.todas()[0]

	var comb := CSGCombiner3D.new()
	add_child(comb)

	var caja := CSGBox3D.new()
	caja.size = Vector3(ancho, alto, espesor)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.72, 0.73, 0.78)
	caja.material = _mat
	comb.add_child(caja)

	# El hueco: union de huesos + cabeza, restada del muro.
	var hueco := CSGCombiner3D.new()
	hueco.operation = CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(hueco)
	for h in pose["huesos"]:
		hueco.add_child(_caja_hueso(h[0], h[1]))
	hueco.add_child(_cilindro_cabeza(pose["cabeza"]))

func _caja_hueso(a: Vector2, b: Vector2) -> CSGBox3D:
	var d := b - a
	var largo: float = maxf(d.length(), 0.001)
	var box := CSGBox3D.new()
	box.size = Vector3(largo + grosor, grosor, espesor * 2.0)  # +grosor: junturas redondeadas
	box.position = Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0.0)
	box.rotation = Vector3(0.0, 0.0, atan2(d.y, d.x))
	return box

func _cilindro_cabeza(c: Vector2) -> CSGCylinder3D:
	var cil := CSGCylinder3D.new()
	cil.radius = r_cabeza
	cil.height = espesor * 2.0
	cil.sides = 16
	cil.rotation = Vector3(PI / 2.0, 0.0, 0.0)  # eje del cilindro a lo largo de Z
	cil.position = Vector3(c.x, c.y, 0.0)
	return cil

func _process(delta: float) -> void:
	if _detenido:
		return
	position.z += velocidad * delta
	if position.z >= z_plano:
		_detenido = true
		alcanzo_plano.emit(self)

## Chequeo v1: cada punto (Vector2) del jugador debe caer DENTRO del hueco, es
## decir cerca de algun hueso o dentro de la cabeza. Devuelve tambien los que
## quedaron afuera (para depurar / pintar).
func evaluar(puntos: Array) -> Dictionary:
	var afuera := []
	for p in puntos:
		if not _dentro(p):
			afuera.append(p)
	return {"paso": afuera.is_empty(), "afuera": afuera}

func _dentro(p: Vector2) -> bool:
	if p.distance_to(pose["cabeza"]) <= r_cabeza:
		return true
	var r := grosor * 0.5
	for h in pose["huesos"]:
		var cp := Geometry2D.get_closest_point_to_segment(p, h[0], h[1])
		if p.distance_to(cp) <= r:
			return true
	return false

func marcar(paso: bool) -> void:
	_mat.albedo_color = Color(0.2, 0.8, 0.35) if paso else Color(0.9, 0.25, 0.25)
