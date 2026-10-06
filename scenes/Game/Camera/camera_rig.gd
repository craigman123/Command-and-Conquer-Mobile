extends Node3D

@export var pan_speed := 35.0
@export var rotate_speed := 0.005
@export var zoom_step := 4.0
@export var min_zoom := 20.0
@export var max_zoom := 70.0
@export var min_pitch := 40.0   
@export var max_pitch := 80.0
@export var map_limit := 215.0
@export var clearance := 4.0     
@export var follow_speed := 8.0
@export var start_zoom := 40.0 

@onready var cam: Camera3D = $Camera3D

var zoom := 60.0
var pitch := deg_to_rad(55.0)

func _ready():
	zoom = clamp(start_zoom, min_zoom, max_zoom)
	pitch = clamp(pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	_update_camera()

func _process(delta):
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if dir != Vector3.ZERO:
		var move = Basis(Vector3.UP, rotation.y) * dir.normalized()
		var boost := 2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		global_position += move * pan_speed * boost * (zoom / 15.0) * delta
	_clamp_to_map()

func _physics_process(delta):
	# measure the ground under the pivot and under the camera
	var cam_pos = cam.global_position
	var ground_under_rig = _ground_y(global_position.x, global_position.z)
	var ground_under_cam = _ground_y(cam_pos.x, cam_pos.z)

	var cam_height_above_rig = cam_pos.y - global_position.y
	var needed = ground_under_cam + clearance - cam_height_above_rig
	var target_y = max(ground_under_rig, needed)

	global_position.y = lerp(global_position.y, target_y, clamp(follow_speed * delta, 0.0, 1.0))

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clamp(zoom - zoom_step, min_zoom, max_zoom)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clamp(zoom + zoom_step, min_zoom, max_zoom)
			_update_camera()

	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		rotation.y -= event.relative.x * rotate_speed
		pitch = clamp(pitch + event.relative.y * rotate_speed, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		_update_camera()

func _update_camera():
	cam.position = Vector3(0, sin(pitch), cos(pitch)) * zoom
	cam.rotation.x = -pitch

func _clamp_to_map():
	# keep the pivot inside the map
	global_position.x = clamp(global_position.x, -map_limit, map_limit)
	global_position.z = clamp(global_position.z, -map_limit, map_limit)
	# keep the camera itself inside too, pushing the pivot back in if it sticks out
	var c = cam.global_position
	global_position.x -= c.x - clamp(c.x, -map_limit, map_limit)
	global_position.z -= c.z - clamp(c.z, -map_limit, map_limit)

func _ground_y(x: float, z: float) -> float:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -100, z))
	var ignore: Array[RID] = []
	for u in get_tree().get_nodes_in_group("units"):
		ignore.append(u.get_rid())
	query.exclude = ignore
	var hit = space.intersect_ray(query)
	return hit.position.y if hit else 0.0
