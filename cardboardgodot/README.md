# Cardboard VR Camera3D

Google cardboard VR Camera for godot 4

For mobile use: activate the gyroscope sensor on: 'Project Settings -> Input Devices -> Sensors -> Enable Gyroscope'

Usage:

* Just place on the scene orcharactebody 3D.
	
Properties:

* Active : bool = Is active
* UseGysroscope : bool = If use gyroscope as rotation input
* Mouse_Sensitivity : float = Mouse sensitivity when not using the gyroscope for rotation
* GysroscopeFactor : float = gyroscore factor speed (sensitivity)
* RotateParent : bool = if rotates parent
* Handle_Mouse_Capture : bool = if handles mouse capture (for non gyroscope use)
* Input_Cancel : String  = Input to release mouse capture 
* EyesSeparation : float = Separation of eyes cameras
* EyeHeight : float =  Base height camera
* EyeConvergenceAngle : Eyes camera convergence angle

