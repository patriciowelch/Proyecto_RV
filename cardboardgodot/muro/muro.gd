class_name Muro extends Node3D

## Muro que avanza hacia el jugador con un agujero tallado por resta booleana
## (CSG): una caja menos el poligono de la figura extruido a lo ancho del muro.
## OJO rendimiento: CSG se recalcula en CPU. Para el build final de Cardboard
## conviene hornear cada muro a MeshInstance3D estatico. Para prototipar va bien.

signal alcanzo_plano(muro: Muro)

@export var figura: PackedVector2Array = Figuras.PARADO
@export var ancho: float = 5.0
@export var alto: float = 6.0
@export var espesor: float = 0.4
@export var velocidad: float = 3.0   # m/s hacia +Z (hacia el jugador)
@export var z_plano: float = 0.0     # plano de evaluacion (donde esta el cuerpo)

var _mat: StandardMaterial3D
var _detenido := false

func configurar(fig: PackedVector2Array, vel: float, z_eval: float) -> void:
	figura = fig
	velocidad = vel
	z_plano = z_eval

func _ready() -> void:
	var comb := CSGCombiner3D.new()
	add_child(comb)

	var caja := CSGBox3D.new()
	caja.size = Vector3(ancho, alto, espesor)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.72, 0.73, 0.78)
	caja.material = _mat
	comb.add_child(caja)

	# La figura se extruye mas que el espesor y se corre en -Z para atravesar
	# el muro entero, asi el agujero queda pasante.
	var hueco := CSGPolygon3D.new()
	hueco.polygon = figura
	hueco.mode = CSGPolygon3D.MODE_DEPTH
	hueco.depth = espesor * 2.0
	hueco.operation = CSGShape3D.OPERATION_SUBTRACTION
	hueco.position = Vector3(0.0, 0.0, -espesor)
	comb.add_child(hueco)

func _process(delta: float) -> void:
	if _detenido:
		return
	position.z += velocidad * delta
	if position.z >= z_plano:
		_detenido = true
		alcanzo_plano.emit(self)

## Chequeo v1: cada punto (Vector2 en el plano del muro) debe caer dentro del
## agujero. Devuelve tambien la lista de puntos que quedaron afuera.
func evaluar(puntos: Array) -> Dictionary:
	var afuera := []
	for p in puntos:
		if not Geometry2D.is_point_in_polygon(p, figura):
			afuera.append(p)
	return {"paso": afuera.is_empty(), "afuera": afuera}

func marcar(paso: bool) -> void:
	_mat.albedo_color = Color(0.2, 0.8, 0.35) if paso else Color(0.9, 0.25, 0.25)
