extends Area3D

@onready var sphere = $CollisionShape3D

func update_from_landmark(lm: Vector3):
	# Escalamos las coords normalizadas de Mediapipe
	position = lm
