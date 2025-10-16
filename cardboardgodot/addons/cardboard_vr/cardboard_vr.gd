@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_custom_type("CardboardVRCamera3D", "Camera3D", preload("res://addons/cardboard_vr/scripts/cardboard_vr_camera.gd"), preload("res://addons/cardboard_vr/icons/CardboardVRCamera3D.svg"))

func _exit_tree() -> void:
	remove_custom_type("CardboardVRCamera3D")
