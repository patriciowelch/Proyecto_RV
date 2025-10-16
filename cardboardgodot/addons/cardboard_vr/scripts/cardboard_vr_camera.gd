class_name CardboardVRCamera extends Camera3D

@export var Active : bool = true
@export_category("Controls")
@export var UseGysroscope : bool = true
@export var Mouse_Sensitivity : float = 0.003
@export var GysroscopeFactor : float = 0.2
@export var RotateParent : bool = true
@export var Handle_Mouse_Capture : bool = true
@export var Input_Cancel : String  = "cancel"

@export_category("Eyes")
@export_range(0.1, 2.0) var EyesSeparation : float = 2
@export_range(0, 5.0) var EyeHeight : float =  0.8
@export_range(-360, 360) var EyeConvergencyAngle : float =  3

var viewScene = preload("res://addons/cardboard_vr/scenes/CardboardView.tscn")
var left_camera_3d: Camera3D = Camera3D.new()
var right_camera_3d: Camera3D = Camera3D.new()
var LeftEyePivot : Node3D = Node3D.new()
var RightEyePivot : Node3D = Node3D.new()
var View : CardboardView
var LeftEyeSubViewPort : SubViewport = SubViewport.new()
var RightEyeSubViewPort : SubViewport = SubViewport.new()
var parent : CharacterBody3D = get_parent()

func _input(event):	
	if not Active:
		return
		
	if Handle_Mouse_Capture:
		if event is InputEventMouseButton:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif Input.is_action_just_pressed(Input_Cancel):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE	
			
	if not UseGysroscope and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:		
		if RotateParent:
			parent.rotate_y(-(event as InputEventMouseMotion).relative.x * Mouse_Sensitivity)
		LeftEyePivot.rotate_y(-(event as InputEventMouseMotion).relative.x * Mouse_Sensitivity)
		RightEyePivot.rotate_y(-(event as InputEventMouseMotion).relative.x * Mouse_Sensitivity)
		LeftEyePivot.rotate_object_local(Vector3.RIGHT, -(event as InputEventMouseMotion).relative.y * Mouse_Sensitivity)
		RightEyePivot.rotate_object_local(Vector3.RIGHT,-(event as InputEventMouseMotion).relative.y * Mouse_Sensitivity)
		LeftEyePivot.global_rotation.x = clamp(LeftEyePivot.global_rotation.x, deg_to_rad(-90), deg_to_rad(90))
		RightEyePivot.global_rotation.x = clamp(RightEyePivot.global_rotation.x, deg_to_rad(-90), deg_to_rad(90))	
	
						
func _ready() -> void:		
	parent = get_parent()
	LeftEyePivot.add_child(left_camera_3d)
	LeftEyeSubViewPort.add_child(LeftEyePivot)
	RightEyePivot.add_child(right_camera_3d)	
	RightEyeSubViewPort.add_child(RightEyePivot)	
	View = viewScene.instantiate()
	add_child(View)
	add_child(LeftEyeSubViewPort)
	add_child(RightEyeSubViewPort)	
	View.SetViewPorts(LeftEyeSubViewPort, RightEyeSubViewPort)	
	left_camera_3d.position.x = -(EyesSeparation)
	right_camera_3d.position.x = EyesSeparation		
	LeftEyePivot.position.y = EyeHeight
	RightEyePivot.position.y = EyeHeight
	left_camera_3d.rotate_object_local(Vector3.UP, deg_to_rad(EyeConvergencyAngle))
	right_camera_3d.rotate_object_local(Vector3.UP, -deg_to_rad(EyeConvergencyAngle))
	
func _process(delta: float) -> void:	
	if not Active:
		return
		
	LeftEyePivot.global_position = Vector3(parent.global_position.x, parent.global_position.y + EyeHeight, parent.global_position.z )
	RightEyePivot.global_position = Vector3(parent.global_position.x, parent.global_position.y + EyeHeight, parent.global_position.z )	
	
	if UseGysroscope:
		var gyroscope = Input.get_gyroscope() * GysroscopeFactor
		if RotateParent:			
			parent.rotate_y(gyroscope.y * GysroscopeFactor)		
		LeftEyePivot.rotate_y(gyroscope.y * GysroscopeFactor)
		RightEyePivot.rotate_y(gyroscope.y * GysroscopeFactor)		
		LeftEyePivot.rotate_object_local(Vector3.RIGHT, gyroscope.x * GysroscopeFactor)
		RightEyePivot.rotate_object_local(Vector3.RIGHT, gyroscope.x * GysroscopeFactor)
		LeftEyePivot.rotation.x = clamp(LeftEyePivot.rotation.x, deg_to_rad(-90), deg_to_rad(90))
		RightEyePivot.rotation.x = clamp(RightEyePivot.rotation.x, deg_to_rad(-90), deg_to_rad(90))	
