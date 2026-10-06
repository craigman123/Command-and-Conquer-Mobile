extends Node3D

@export var pan_speed := 20.0
@export var rotate_speed := 0.005
@export var zoom_step := 2.0
@export var min_zoom := 6.0
@export var max_zoom := 35.0
@export var min_pitch := 25.0    # degrees, flattest view
@export var max_pitch := 80.0    # degrees, steepest (top-down) view
@export var map_limit := 45.0

@onready var cam: Camera3D = $Camera3D

var zoom := 15.0
var pitch := deg_to_rad(50.0)

func _ready():
	zoom = clamp(cam.position.length(), min_zoom, max_zoom)
	_update_camera()

func _process(delta):
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if dir != Vector3.ZERO:
		# move relative to where the camera is facing
		var move = Basis(Vector3.UP, rotation.y) * dir.normalized()
		global_position += move * pan_speed * (zoom / 15.0) * delta
		global_position.x = clamp(global_position.x, -map_limit, map_limit)
		global_position.z = clamp(global_position.z, -map_limit, map_limit)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clamp(zoom - zoom_step, min_zoom, max_zoom)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clamp(zoom + zoom_step, min_zoom, max_zoom)
			_update_camera()

	# hold the middle mouse button and drag to rotate
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		rotation.y -= event.relative.x * rotate_speed
		pitch = clamp(pitch + event.relative.y * rotate_speed, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		_update_camera()

func _update_camera():
	cam.position = Vector3(0, sin(pitch), cos(pitch)) * zoom
	cam.rotation.x = -pitch
