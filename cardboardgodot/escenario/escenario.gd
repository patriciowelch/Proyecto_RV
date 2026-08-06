extends Node3D

## Oculta la malla de agua que viene en el .glb (material transparente/negro,
## ademas ~41k triangulos) para dejar en su lugar el plano liviano "Agua" con
## el ShaderMaterial de agua definido en la escena.

func _ready() -> void:
	var pool := get_node_or_null("SwimmingPool")
	if pool == null:
		return
	# owned=false: los hijos vienen instanciados del glb, no los posee esta escena.
	var agua_glb := pool.find_child("Water_Water_0", true, false)
	if agua_glb and agua_glb is Node3D:
		(agua_glb as Node3D).visible = false
