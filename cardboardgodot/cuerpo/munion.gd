extends Node3D

@onready var label = $CanvasLayer/Label
@onready var brazoizq = $Segmento
@onready var puntito1 = $Punto
@onready var puntito2 = $Punto2

func _ready():
	var v1 = Vector3(0,3,-5)
	var v2 = Vector3(1,1,-4)
	brazoizq.update_from_landmarks(v1,v2)
	puntito1.update_from_landmark(v1)
	puntito2.update_from_landmark(v2)

func _process(delta):
	pass
	
func update(v1:Vector3,v2:Vector3):
	brazoizq.update_from_landmarks(v1,v2)
	puntito1.update_from_landmark(v1)
	puntito2.update_from_landmark(v2)
