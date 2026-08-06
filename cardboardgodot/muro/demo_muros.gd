extends Node3D

## Demo ejecutable (F6, sin servidor ni VR) de los 9 muros/poses del storyboard.
## Los muros aparecen en orden y avanzan hacia la camara. Una silueta de prueba
## (13 puntos = landmarks) se puede mover con las flechas; ESPACIO la "adopta"
## a la pose del muro entrante. En vivo, las articulaciones sobre el muro se
## pintan VERDE cuando esa parte ya entra en el agujero y ROJO si falta corregir.

const Z_PLANO := 0.0
const Z_SPAWN := -24.0
const SPAWN_CADA := 4.5
const VEL_MURO := 3.5

# Pose neutra (parado): nariz, hombros, codos, munecas, caderas, rodillas, tobillos.
const NEUTRA := [
	Vector2(0.0, 1.6),
	Vector2(-0.28, 1.05), Vector2(0.28, 1.05),
	Vector2(-0.4, 0.5), Vector2(0.4, 0.5),
	Vector2(-0.45, -0.05), Vector2(0.45, -0.05),
	Vector2(-0.2, -0.35), Vector2(0.2, -0.35),
	Vector2(-0.2, -1.1), Vector2(0.2, -1.1),
	Vector2(-0.2, -1.9), Vector2(0.2, -1.9),
]

var _poses: Array
var _idx := 0
var _base: Array = NEUTRA.duplicate()
var _offset := Vector2.ZERO
var _esferas: Array = []
var _label: Label3D
var _t := 0.0
var _ok := 0
var _fail := 0
var _pose_entrante: Dictionary
var _muro_activo: Muro

func _ready() -> void:
	_poses = Figuras.todas()
	_crear_silueta()
	_crear_label()
	_spawn()

func _crear_silueta() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in NEUTRA.size():
		var e := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.1
		s.height = 0.2
		e.mesh = s
		e.material_override = mat
		add_child(e)
		_esferas.append(e)
	_actualizar_silueta()

func _crear_label() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.01
	_label.modulate = Color(1, 1, 0.6)
	_label.position = Vector3(0, 3.3, 0)
	add_child(_label)
	_refrescar_label("-", 0)

func puntos_actuales() -> Array:
	var r := []
	for p in _base:
		r.append(p + _offset)
	return r

func _actualizar_silueta() -> void:
	var pts := puntos_actuales()
	for i in pts.size():
		_esferas[i].position = Vector3(pts[i].x, pts[i].y, Z_PLANO)

func _refrescar_label(nombre: String, verdes: int) -> void:
	_label.text = "Muro: %s   (%d/%d articulaciones OK)\nPaso: %d   Fallo: %d\nFlechas: mover   ESPACIO: adoptar pose" % [nombre, verdes, _base.size(), _ok, _fail]

## Aproxima los 13 landmarks desde el esqueleto de una pose (para "adoptarla").
func _puntos_de_pose(pose: Dictionary) -> Array:
	var h = pose["huesos"]
	var cuello: Vector2 = h[0][0]
	var cadera: Vector2 = h[0][1]
	return [
		pose["cabeza"],
		cuello + Vector2(-0.28, 0), cuello + Vector2(0.28, 0),
		h[2][1], h[4][1],          # codos
		h[3][1], h[5][1],          # munecas
		cadera + Vector2(-0.2, 0), cadera + Vector2(0.2, 0),
		h[6][1], h[8][1],          # rodillas
		h[7][1], h[9][1],          # tobillos
	]

func _spawn() -> void:
	_pose_entrante = _poses[_idx]
	_idx = (_idx + 1) % _poses.size()
	var m := Muro.new()
	m.configurar(_pose_entrante, VEL_MURO, Z_PLANO)
	m.position = Vector3(0, 0, Z_SPAWN)
	m.alcanzo_plano.connect(_on_alcanzo_plano)
	add_child(m)
	_muro_activo = m
	_refrescar_label(_pose_entrante["nombre"], 0)

func _on_alcanzo_plano(m: Muro) -> void:
	var res := m.evaluar(puntos_actuales())
	m.marcar(res["paso"])
	if res["paso"]:
		_ok += 1
	else:
		_fail += 1
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(m.queue_free)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		_base = _puntos_de_pose(_pose_entrante)
		_offset = Vector2.ZERO
		_actualizar_silueta()
	var mv := Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	if mv != Vector2.ZERO:
		_offset += mv * delta * 2.5
		_actualizar_silueta()

	# Feedback en vivo sobre el muro que se acerca.
	if is_instance_valid(_muro_activo):
		var verdes := _muro_activo.actualizar_feedback(puntos_actuales())
		_refrescar_label(_muro_activo.pose["nombre"], verdes)

	_t += delta
	if _t >= SPAWN_CADA:
		_t = 0.0
		_spawn()
