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

# Spin limit: how far (in degrees) you can rotate left and right
# from the direction the camera starts facing.
@export var limit_yaw := true
@export var yaw_range := 45.0

# The camera is never allowed to rise above this world height (Y).
@export var max_camera_height := 90.0
@export var debug_blocking := false

# Drag a node here whose children are Marker3D points outlining the area
# the camera may roam in. If left empty, the old square (map_limit) is used.
@export var camera_bounds: Node3D

@onready var cam: Camera3D = $Camera3D

var zoom := 60.0
var pitch := deg_to_rad(55.0)
var start_yaw := 0.0
var yaw_offset := 0.0  # how far we have spun from start_yaw (radians)
var bounds_polygon := PackedVector2Array()


func _ready():
	start_yaw = rotation.y
	zoom = clamp(start_zoom, min_zoom, max_zoom)
	pitch = clamp(pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	_update_camera()
	_build_bounds()


# Reads the Marker3D children and keeps only their X and Z (the top-down view).
func _build_bounds():
	bounds_polygon.clear()
	if camera_bounds == null:
		return
	for child in camera_bounds.get_children():
		if child is Node3D:
			bounds_polygon.append(Vector2(child.global_position.x, child.global_position.z))
	if bounds_polygon.size() < 3:
		push_warning("camera_bounds needs at least 3 Marker3D children")
		bounds_polygon.clear()
		return
	# if the camera starts outside the shape, move it to the nearest edge point
	if not _inside_bounds(global_position):
		var p := _nearest_point_on_bounds(Vector2(global_position.x, global_position.z))
		global_position.x = p.x
		global_position.z = p.y


func _process(delta):
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if dir != Vector3.ZERO:
		var move = Basis(Vector3.UP, rotation.y) * dir.normalized()
		var boost := 1.2 if Input.is_key_pressed(KEY_SHIFT) else 0.5
		var step: Vector3 = move * pan_speed * boost * (zoom / 15.0) * delta
		step.y = 0.0

		var now := _required_cam_y(Vector3.ZERO)
		# Try the full move; if blocked, slide along one axis.
		if not _is_blocked(step, now):
			global_position += step
		elif not _is_blocked(Vector3(step.x, 0, 0), now):
			global_position.x += step.x
		elif not _is_blocked(Vector3(0, 0, step.z), now):
			global_position.z += step.z
	_clamp_to_map()


func _physics_process(delta):
	var cam_pos = cam.global_position
	var ground_under_rig = _ground_y(global_position.x, global_position.z)
	var ground_under_cam = _ground_y(cam_pos.x, cam_pos.z)

	var cam_height_above_rig = cam_pos.y - global_position.y
	var needed = ground_under_cam + clearance - cam_height_above_rig
	var target_y = max(ground_under_rig, needed)
	target_y = min(target_y, max_camera_height - cam_height_above_rig)

	global_position.y = lerp(global_position.y, target_y, clamp(follow_speed * delta, 0.0, 1.0))


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		var before := _required_cam_y(Vector3.ZERO)
		var old_zoom := zoom
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clamp(zoom - zoom_step, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clamp(zoom + zoom_step, min_zoom, max_zoom)
		_update_camera()
		var after := _required_cam_y(Vector3.ZERO)
		if after > max_camera_height and after > before:
			zoom = old_zoom
			_update_camera()

	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		var before := _required_cam_y(Vector3.ZERO)
		var old_yaw := yaw_offset
		var old_pitch := pitch
		# Spin is limited to yaw_range degrees either side of the starting direction.
		# Hitting the limit only stops further spin in that direction;
		# spinning back the other way always works.
		yaw_offset = _clamp_yaw(yaw_offset - event.relative.x * rotate_speed)
		rotation.y = start_yaw + yaw_offset
		pitch = clamp(pitch + event.relative.y * rotate_speed, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		_update_camera()
		var after := _required_cam_y(Vector3.ZERO)
		if after > max_camera_height and after > before:
			yaw_offset = old_yaw
			rotation.y = start_yaw + yaw_offset
			pitch = old_pitch
			_update_camera()


# Clamps the spin offset to +/- yaw_range (does nothing if limit_yaw is off).
func _clamp_yaw(offset: float) -> float:
	if not limit_yaw:
		return offset
	var r := deg_to_rad(yaw_range)
	return clamp(offset, -r, r)


func _update_camera():
	cam.position = Vector3(0, sin(pitch), cos(pitch)) * zoom
	cam.rotation.x = -pitch


func _required_cam_y(offset: Vector3) -> float:
	var rig = global_position + offset
	var c = cam.global_position + offset
	var cam_h = cam.global_position.y - global_position.y
	return max(_ground_y(rig.x, rig.z) + cam_h, _ground_y(c.x, c.z) + clearance)


func _is_blocked(offset: Vector3, now: float) -> bool:
	# Leaving the roaming area counts as blocked (so you slide along its edge)
	if not _inside_bounds(global_position + offset):
		return true
	var then := _required_cam_y(offset)
	var blocked := then > max_camera_height and then > now + 0.01
	if blocked and debug_blocking:
		print("BLOCKED: camera would need y=", snappedf(then, 0.1), " (limit ", max_camera_height, ", now ", snappedf(now, 0.1), ")")
	return blocked


# True if the point is inside the custom shape (always true if there is none).
func _inside_bounds(p: Vector3) -> bool:
	if bounds_polygon.is_empty():
		return true
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), bounds_polygon)


func _nearest_point_on_bounds(p: Vector2) -> Vector2:
	var best := p
	var best_dist := INF
	for i in bounds_polygon.size():
		var a := bounds_polygon[i]
		var b := bounds_polygon[(i + 1) % bounds_polygon.size()]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(q)
		if d < best_dist:
			best_dist = d
			best = q
	return best


func _clamp_to_map():
	# With a custom shape, the shape does the limiting. Otherwise use the square.
	if not bounds_polygon.is_empty():
		return
	global_position.x = clamp(global_position.x, -map_limit, map_limit)
	global_position.z = clamp(global_position.z, -map_limit, map_limit)
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
