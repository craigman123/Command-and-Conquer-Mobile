extends CharacterBody3D

@export var speed := 10.0
@export var reverse_speed := 8.0
@export var acceleration := 12.0
@export var brake_force := 25.0
@export var turn_radius := 6.0           # smaller = tighter turns
@export var reverse_distance := 12.0     # target closer than this and behind -> reverse instead of U-turn
@export var reach_distance := 1.0
@export var slow_down_distance := 6.0    # start braking this far from the final point
@export var vision_range := 30.0
@export var whisker_length := 6.0
@export var whisker_angle := 35.0       # degrees, left/right feelers
@export var whisker_height := 0.8       # raise it so it doesn't hit the ground
@export var avoid_strength := 1.2

var stuck_timer := 0.0
var unstick_time := 0.0
var last_pos := Vector3.ZERO

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var ring: Node3D = $SelectionRing

var nav_ready := false
var path: PackedVector3Array = PackedVector3Array()
var path_index := 0
var current_speed := 0.0   # signed: + forward, - reverse
var reversing := false

@export var smoke_offset := Vector3(0.0, 0.7, -1.3)  # exhaust position (back = -Z)
@export var smoke_max_amount := 40

var smoke: GPUParticles3D

@export var tilt_speed := 8.0          # how fast the body follows the slope
@export var max_tilt_degrees := 40.0   # safety limit so it never flips weirdly

@onready var model: Node3D = $humvee
var model_base_basis: Basis
var ground_normal := Vector3.UP

func _ready():
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	model_base_basis = model.basis
	add_to_group("player_units")
	add_to_group("units")
	set_selected(false)
	_setup_smoke()
	await get_tree().physics_frame
	await get_tree().physics_frame
	nav_ready = true
	
# returns [extra_steer_radians, speed_multiplier]
func _avoid_obstacles() -> Array:
	var space := get_world_3d().direct_space_state
	var move_dir := global_transform.basis.z * (-1.0 if reversing else 1.0)
	move_dir.y = 0.0
	move_dir = move_dir.normalized()
	var origin := global_position + Vector3.UP * whisker_height
	var a := deg_to_rad(whisker_angle)

	var dirs := [move_dir.rotated(Vector3.UP, a),   # left
				 move_dir,                           # center
				 move_dir.rotated(Vector3.UP, -a)]   # right
	var danger := [0.0, 0.0, 0.0]

	for i in 3:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dirs[i] * whisker_length)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		if hit.normal.y > 0.7:     # that's just the ground / a slope, ignore
			continue
		if hit.collider is Node and (hit.collider as Node).is_in_group("units"):
			continue
		danger[i] = 1.0 - origin.distance_to(hit.position) / whisker_length

	# + = steer left, so a hit on the left pushes us right
	var steer: float = (danger[2] - danger[0]) * avoid_strength

	# head-on: pick the freer side and brake
	if danger[1] > 0.0:
		var side := 1.0 if danger[0] <= danger[2] else -1.0
		steer += side * danger[1] * avoid_strength * 1.5

	var speed_mult: float = 1.0 - clamp(danger[1] * 0.8, 0.0, 0.8)
	return [steer, speed_mult]

func set_selected(value: bool):
	ring.visible = value

func move_to(pos: Vector3):
	if not nav_ready:
		return
	var map = agent.get_navigation_map()
	var closest = NavigationServer3D.map_get_closest_point(map, pos)
	path = NavigationServer3D.map_get_path(map, global_position, closest, true)
	path_index = 0
	reversing = false


func _physics_process(delta):
	# gravity
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 20.0 * delta

	var forward := global_transform.basis.z   # your model faces +Z
	var target_speed := 0.0
	var steer_angle := 0.0

	# skip waypoints we've already reached
	var dir := Vector3.ZERO
	var dist := 0.0
	var has_target := false
	while path_index < path.size():
		dir = path[path_index] - global_position
		dir.y = 0.0
		dist = dir.length()
		if dist < reach_distance:
			path_index += 1
			continue
		dir = dir / dist
		has_target = true
		break

	if has_target:
		var angle := forward.signed_angle_to(dir, Vector3.UP)  # + = target is to the left
		var angle_abs: float = abs(angle)
		var is_last := path_index == path.size() - 1

		# decide forward vs reverse (with hysteresis so it doesn't flicker)
		if dist < reverse_distance:
			if angle_abs > deg_to_rad(100.0):
				reversing = true
			elif angle_abs < deg_to_rad(80.0):
				reversing = false
		else:
			reversing = false

		if reversing:
			steer_angle = wrapf(angle - PI, -PI, PI)
			target_speed = -reverse_speed
		else:
			steer_angle = angle
			target_speed = speed
			if abs(steer_angle) > deg_to_rad(50.0):
				target_speed = speed * 0.4

		# brake near the end of the path
		if is_last and dist < slow_down_distance:
			target_speed *= clamp(dist / slow_down_distance, 0.25, 1.0)

		# obstacle avoidance (whiskers)
		var avoid := _avoid_obstacles()
		steer_angle = clamp(steer_angle + avoid[0], -PI, PI)
		target_speed *= avoid[1]
	else:
		reversing = false

	# stuck detection: wanted to move but barely did -> back up for a bit
	if unstick_time > 0.0:
		unstick_time -= delta
		target_speed = -reverse_speed if not reversing else speed * 0.5
		steer_angle = -steer_angle
	elif has_target and abs(target_speed) > 1.0:
		var moved := global_position.distance_to(last_pos)
		if moved < abs(target_speed) * delta * 0.25:
			stuck_timer += delta
		else:
			stuck_timer = 0.0
		if stuck_timer > 1.0:
			stuck_timer = 0.0
			unstick_time = 1.2
	else:
		stuck_timer = 0.0
	last_pos = global_position

	# accelerate / brake (passes through 0 when changing direction)
	var rate := acceleration
	if target_speed == 0.0 or (sign(target_speed) != sign(current_speed) and current_speed != 0.0):
		rate = brake_force
	current_speed = move_toward(current_speed, target_speed, rate * delta)

	# steering only works while rolling: yaw rate = speed / turn radius
	var max_step: float = abs(current_speed) / turn_radius * delta
	rotation.y += clamp(steer_angle, -max_step, max_step)

	# drive along the car's own forward axis
	forward = global_transform.basis.z
	velocity.x = forward.x * current_speed
	velocity.z = forward.z * current_speed

	# smoke gets thicker the faster you go
	var speed_ratio: float = clamp(abs(current_speed) / speed, 0.0, 1.0)
	smoke.emitting = speed_ratio > 0.05
	smoke.amount_ratio = max(speed_ratio, 0.1)

	move_and_slide()
	_update_tilt(delta)
	
func _setup_smoke():
	smoke = GPUParticles3D.new()
	smoke.position = smoke_offset
	smoke.amount = smoke_max_amount
	smoke.lifetime = 1.8
	smoke.local_coords = false   # particles stay in the world, which makes the trail
	smoke.emitting = false
	smoke.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 20, 60))

	# behavior
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.25, -1)   # backwards and slightly up
	pm.spread = 15.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.9, 0)       # smoke drifts upward
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0

	# grows over its life
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(1.0, 2.2))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	pm.scale_curve = scale_tex

	# fades from dark gray to transparent
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	grad.colors = PackedColorArray([
		Color(0.25, 0.25, 0.25, 0.0),
		Color(0.35, 0.35, 0.35, 0.55),
		Color(0.6, 0.6, 0.6, 0.0),
	])
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = grad
	pm.color_ramp = color_tex
	smoke.process_material = pm

	# soft round puff texture
	var puff_grad := Gradient.new()
	puff_grad.offsets = PackedFloat32Array([0.0, 1.0])
	puff_grad.colors = PackedColorArray([Color(0.212, 0.212, 0.212, 1.0), Color(1, 1, 1, 0)])
	var puff := GradientTexture2D.new()
	puff.gradient = puff_grad
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	puff.width = 64
	puff.height = 64

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = puff
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true

	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat
	smoke.draw_pass_1 = quad

	add_child(smoke)
	
func _update_tilt(delta: float):
	# target normal: the slope under us, or flat when airborne
	var target_normal := Vector3.UP
	if is_on_floor():
		target_normal = get_floor_normal()

	# smooth it so the Humvee eases onto slopes instead of snapping
	ground_normal = ground_normal.slerp(target_normal, clamp(tilt_speed * delta, 0.0, 1.0)).normalized()

	# convert to the body's local space (body only yaws, so this isolates pitch + roll)
	var local_normal := global_transform.basis.orthonormalized().inverse() * ground_normal

	# limit the tilt
	var angle := Vector3.UP.angle_to(local_normal)
	var max_angle := deg_to_rad(max_tilt_degrees)
	if angle > max_angle:
		local_normal = Vector3.UP.slerp(local_normal, max_angle / angle)

	var tilt := Basis(Quaternion(Vector3.UP, local_normal))
	model.basis = tilt * model_base_basis
