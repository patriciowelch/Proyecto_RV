extends Node3D

## Demo ejecutable del mecanismo de muros (correr con F6, sin servidor ni VR).
## Muestra una silueta de prueba (esqueleto de puntos) y muros con agujeros que
## avanzan; al llegar al plano se pintan verde (paso) o rojo (fallo) segun el
## chequeo v1 punto-en-poligono. Flechas: mover la silueta para probar encajes.

const Z_PLANO := 0.0
const Z_SPAWN := -22.0
const SPAWN_CADA := 3.5
const VEL_MURO := 4.0

# Pose neutra parada: nariz, hombros, codos, munecas, caderas, rodillas, tobillos.
const POSE_BASE := [
	Vector2(0.0, 1.55),
	Vector2(-0.4, 1.1), Vector2(0.4, 1.1),
	Vector2(-0.5, 0.45), Vector2(0.5, 0.45),
	Vector2(-0.55, -0.15), Vector2(0.55, -0.15),
	Vector2(-0.32, -0.3), Vector2(0.32, -0.3),
	Vector2(-0.32, -1.2), Vector2(0.32, -1.2),
	Vector2(-0.32, -2.1), Vector2(0.32, -2.1),
]

var _offset := Vector2.ZERO
var _esferas: Array = []
var _label: Label3D
var _t := 0.0
var _ok := 0
var _fail := 0

func _ready() -> void:
	randomize()
	_crear_silueta()
	_crear_label()
	_spawn()

func _crear_silueta() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for p in POSE_BASE:
		var e := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.11
		s.height = 0.22
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
	_label.position = Vector3(0, 3.2, 0)
	add_child(_label)
	_refrescar_label()

func puntos_actuales() -> Array:
	var r := []
	for p in POSE_BASE:
		r.append(p + _offset)
	return r

func _actualizar_silueta() -> void:
	var pts := puntos_actuales()
	for i in pts.size():
		_esferas[i].position = Vector3(pts[i].x, pts[i].y, Z_PLANO)

func _refrescar_label() -> void:
	_label.text = "Paso: %d    Fallo: %d\nFlechas: mover la silueta" % [_ok, _fail]

func _spawn() -> void:
	var m := Muro.new()
	m.configurar(Figuras.aleatoria(), VEL_MURO, Z_PLANO)
	m.position = Vector3(0, 0, Z_SPAWN)
	m.alcanzo_plano.connect(_on_alcanzo_plano)
	add_child(m)

func _on_alcanzo_plano(m: Muro) -> void:
	var res := m.evaluar(puntos_actuales())
	m.marcar(res["paso"])
	if res["paso"]:
		_ok += 1
	else:
		_fail += 1
	_refrescar_label()
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(m.queue_free)

func _process(delta: float) -> void:
	var mv := Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	if mv != Vector2.ZERO:
		_offset += mv * delta * 2.5
		_actualizar_silueta()
	_t += delta
	if _t >= SPAWN_CADA:
		_t = 0.0
		_spawn()
