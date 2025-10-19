extends Node3D

@onready var col_shape: CapsuleShape3D = $CollisionShape3D.shape
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func update_from_landmarks(p1: Vector3, p2: Vector3):
	var distance = p1.distance_to(p2)
	align_y_between(p1, p2)
	# 1) Ajustar colisión
	col_shape.height = distance
	col_shape.radius = 0.05

	# 2) Escalar tu objeto importado
	var base_length = 2.7   # altura original del modelo en su eje local Y
	mesh_instance.scale = Vector3(1, distance / base_length, 1)
	
func align_y_between(p1: Vector3, p2: Vector3):
	var dir = (p2 - p1).normalized()   # nuevo eje Y
	var up = dir

	# Buscar un vector auxiliar que no sea paralelo a dir
	var aux = Vector3.FORWARD
	if abs(up.dot(aux)) > 0.99:
		aux = Vector3.RIGHT

	# Construir los otros ejes con producto vectorial
	var right = up.cross(aux).normalized()
	var forward = right.cross(up).normalized()

	# Ahora usamos transform (local al padre, no global)
	var xform = Transform3D(Basis(right, up, forward), p1)
	transform = xform
