class_name CardboardView extends CanvasLayer

@onready var left_eye_control: Control = $HorizontalDivider/LeftEyeControl
@onready var right_eye_control: Control = $HorizontalDivider/RightEyeControl
@onready var background: ColorRect = $Background
@onready var left_eye: TextureRect = $HorizontalDivider/LeftEyeControl/LeftEye
@onready var right_eye: TextureRect = $HorizontalDivider/RightEyeControl/RightEye

var left_eye_position: Vector2
var right_eye_position: Vector2
var currentSize = 0.0
var currentCenterOffset = 0.0

func SetViewPorts(leftEye : SubViewport, rightEye : SubViewport):

	left_eye.texture = leftEye.get_texture()
	right_eye.texture = rightEye.get_texture()
	_update_lens_aspect()
	left_eye.resized.connect(_update_lens_aspect)

## El shader mide el radio en UV del rectángulo del ojo, que no es cuadrado.
## Sin pasarle el aspecto la distorsión sale elíptica en vez de radial.
func _update_lens_aspect() -> void:
	var mat := get_lens_material()
	if mat == null:
		return
	var s := left_eye.size
	if s.y > 0.0:
		mat.set_shader_parameter("aspect", s.x / s.y)

func get_lens_material() -> ShaderMaterial:
	return left_eye.material
