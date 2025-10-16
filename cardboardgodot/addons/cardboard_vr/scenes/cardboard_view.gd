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
