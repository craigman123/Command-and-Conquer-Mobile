class_name VehicleBase
extends CharacterBody3D

@export_group("Common")
@export var speed := 10.0
@export var acceleration := 12.0
@export var brake_force := 25.0
@export var reach_distance := 1.0
@export var slow_down_distance := 6.0
@export var vision_range := 30.0
@export var forward_is_plus_z := true

@export_group("Dust")
@export var dust_enabled := true
@export var dust_offset := Vector3(0.0, 0.3, -2.0)  
@export var dust_max_amount := 80        
@export var dust_min_speed := 2.0
@export var default_dust_color := Color(0.85, 0.74, 0.52, 0.45)
@export var terrain_dust: Dictionary = {}
@export var dust_lifetime = 2.0

var dust: GPUParticles3D
var dust_pm: ParticleProcessMaterial
var dust_color := Color(0.8, 0.7, 0.5, 0.55)
var terrain_node: Node
var terrain_checked := false

@export_group("Avoidance")
@export var whisker_length := 6.0
@export var whisker_angle := 35.0
@export var whisker_height := 0.8
@export var avoid_strength := 1.2
@export var side_whisker_angle := 75.0   # short feelers beside the body, catch corners
@export var arrive_near_radius := 6.0    # destination this close to another unit -> stop near it
@export var detour_forward := 8.0        # when stuck: sidestep point this far ahead...
@export var detour_side := 6.0           # ...and this far to the freer side
var stuck_cooldown := 0.0
@export var make_way_distance := 5.0

@export_group("Visuals")
@export var model: Node3D
@export var tilt_speed := 8.0
@export var max_tilt_degrees := 40.0
@export var smoke_enabled := true
@export var smoke_offset := Vector3(0.0, 0.7, -2.3)
@export var smoke_max_amount := 40

@export_group("Force Through")
@export var force_stuck_time := 2.0
@export var force_stuck_radius := 1.5
@export var force_max_time := 3.0
@export var force_escape_distance := 3.0

var force_active := false
var force_dir := 1.0        
var force_timer := 0.0
var force_elapsed := 0.0
var force_anchor := Vector3.ZERO
var force_start := Vector3.ZERO
var force_flip := false

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var ring: Node3D = $SelectionRing

var nav_ready := false
var path: PackedVector3Array = PackedVector3Array()
var path_index := 0

# filled in every frame for the driving scripts to use
var has_target := false
var target_dir := Vector3.ZERO
var target_dist := 0.0
var is_last_waypoint := false

var avoid_side := 0.0      # +1 = dodging left, -1 = dodging right (kept for a moment)
var avoid_commit := 0.0    # seconds left to keep dodging that way

var current_speed := 0.0   # signed: + forward, - reverse
var reversing := false     # used by avoidance to look the right way

var stuck_timer := 0.0
var unstick_time := 0.0
var last_pos := Vector3.ZERO

var smoke: GPUParticles3D
var model_base_basis := Basis.IDENTITY
var ground_normal := Vector3.UP


func _ready():
	add_to_group("player_units")
	add_to_group("units")
	add_to_group("vehicles")
	set_selected(false)
	
	if dust_enabled:
		_setup_dust()

	if model == null:
		model = _find_model()
	if model:
		model_base_basis = model.basis

	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)

	if smoke_enabled:
		_setup_smoke()

	await get_tree().physics_frame
	await get_tree().physics_frame
	nav_ready = true


func _find_model() -> Node3D:
	for c in get_children():
		if c is Node3D and not (c is CollisionShape3D) and c != ring and c != agent and not (c is GPUParticles3D):
			return c
	return null


func set_selected(value: bool):
	if ring:
		ring.visible = value


func move_to(pos: Vector3):
	if not nav_ready:
		return
	var map := agent.get_navigation_map()
	var closest := NavigationServer3D.map_get_closest_point(map, pos)
	path = NavigationServer3D.map_get_path(map, global_position, closest, true)
	path_index = 0
	reversing = false
	_reset_force()


func _forward() -> Vector3:
	var f := global_transform.basis.z if forward_is_plus_z else -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _physics_process(delta):
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 20.0 * delta

	_update_target()
	_update_force(delta)
	_drive(delta)          # <- each vehicle type implements this
	_apply_motion()
	_update_smoke()
	_update_dust(delta)
	move_and_slide()
	_update_tilt(delta)


# override this in WheeledVehicle / TrackedVehicle / etc.
func _drive(_delta: float):
	pass


func _update_target():
	has_target = false
	while path_index < path.size():
		var d := path[path_index] - global_position
		d.y = 0.0
		target_dist = d.length()
		if target_dist < reach_distance:
			path_index += 1
			continue
		target_dir = d / target_dist
		is_last_waypoint = path_index == path.size() - 1
		has_target = true
		break


# ---------- helpers for the driving scripts ----------

func _accelerate(target_speed: float, delta: float):
	var rate := acceleration
	if target_speed == 0.0 or (signf(target_speed) != signf(current_speed) and current_speed != 0.0):
		rate = brake_force
	current_speed = move_toward(current_speed, target_speed, rate * delta)


func _apply_motion():
	var f := _forward()
	velocity.x = f.x * current_speed
	velocity.z = f.z * current_speed


# call every frame. Returns true while the vehicle should be backing out of
# a stuck spot, so the driving script can override its speed / steering.
func _update_stuck(delta: float, target_speed: float, unstick_seconds := 1.2) -> bool:
	if force_active:
		return false
	stuck_cooldown = maxf(stuck_cooldown - delta, 0.0)
	var unsticking := unstick_time > 0.0
	if unsticking:
		unstick_time -= delta
		if unstick_time <= 0.0:
			stuck_cooldown = 1.5      # starts counting after we finish backing up
			reversing = false
	elif has_target and absf(target_speed) > 1.0 and stuck_cooldown <= 0.0:
		if global_position.distance_to(last_pos) < absf(target_speed) * delta * 0.25:
			stuck_timer += delta
		else:
			stuck_timer = 0.0
		if stuck_timer > 1.0:
			stuck_timer = 0.0
			unstick_time = unstick_seconds
			_insert_detour()
	else:
		stuck_timer = 0.0
	last_pos = global_position
	return unsticking


# Called when we get stuck: drop a temporary waypoint beside whatever is
# blocking us, so after backing up we drive AROUND it instead of back into it.
func _insert_detour():
	if path_index >= path.size():
		return
	var move_dir := _forward() * (-1.0 if reversing else 1.0)
	var left := -move_dir.cross(Vector3.UP)

	# prefer the side the target is on, unless that side is blocked
	var to_target := path[path.size() - 1] - global_position
	to_target.y = 0.0
	var want := 1.0 if left.dot(to_target) > 0.0 else -1.0
	var freer := _freer_side(move_dir)
	var side := want if want == freer else freer
	if want != freer and _side_room(move_dir, want) > detour_side * 0.8:
		side = want

	# go mostly FORWARD to clear the blocker's front, then curve
	var point := global_position + move_dir * (detour_forward * 1.5) + left * side * (detour_side * 0.5)
	point = NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), point)
	path.insert(path_index, point)


# +1 if the left side has more room, -1 if the right does (two diagonal rays)
func _freer_side(move_dir: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * whisker_height
	var max_len := detour_side * 1.5
	var a := deg_to_rad(60.0)
	var dirs := [move_dir.rotated(Vector3.UP, a), move_dir.rotated(Vector3.UP, -a)]  # left, right
	var room := [max_len, max_len]
	for i in 2:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dirs[i] * max_len)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.normal.y <= 0.7:
			room[i] = origin.distance_to(hit.position)
	if is_equal_approx(room[0], room[1]):
		return avoid_side if avoid_side != 0.0 else -1.0
	return 1.0 if room[0] > room[1] else -1.0


# climbs up from whatever the ray hit to the vehicle/unit node it belongs to
func _vehicle_root(n: Node) -> Node3D:
	while n != null:
		if n.is_in_group("vehicles") or n.is_in_group("units"):
			return n as Node3D
		n = n.get_parent()
	return null


func _is_vehicle(n: Node) -> bool:
	return _vehicle_root(n) != null


# destination is taken by another unit: stop here instead of ramming it
func _stop_near():
	path = PackedVector3Array()
	path_index = 0
	reversing = false
	avoid_commit = 0.0


# returns [extra_steer_radians, speed_multiplier, path_weight]
# path_weight (0..0.8): how much to weaken the path's steering while dodging,
# so the path can't instantly pull us back into the obstacle.
func _avoid_obstacles() -> Array:
	var delta := get_physics_process_delta_time()
	var space := get_world_3d().direct_space_state
	var move_dir := _forward() * (-1.0 if reversing else 1.0)
	var origin := global_position + Vector3.UP * whisker_height
	var a := deg_to_rad(whisker_angle)
	var b := deg_to_rad(side_whisker_angle)

	# 0 = left, 1 = center, 2 = right, 3 = far left (short), 4 = far right (short)
	var dirs := [move_dir.rotated(Vector3.UP, a),
				 move_dir,
				 move_dir.rotated(Vector3.UP, -a),
				 move_dir.rotated(Vector3.UP, b),
				 move_dir.rotated(Vector3.UP, -b)]
	var lengths := [whisker_length, whisker_length, whisker_length,
					whisker_length * 0.5, whisker_length * 0.5]
	var danger := [0.0, 0.0, 0.0, 0.0, 0.0]
	var vehicle_ahead := false
	var blocker: Node3D = null
	var blocker_dist := 0.0

	for i in 5:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dirs[i] * lengths[i])
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y > 0.7:
			continue
		var d: float = 1.0 - origin.distance_to(hit.position) / lengths[i]
		var root: Node3D = null
		if hit.collider is Node:
			root = _vehicle_root(hit.collider)
		if root != null:
			d = minf(d * 1.5, 1.0)
			if i == 1:
				vehicle_ahead = true
			var hit_dist := origin.distance_to(hit.position)
			if blocker == null or hit_dist < blocker_dist:
				blocker = root
				blocker_dist = hit_dist
			if force_active:
				continue        # still remembered as blocker (make-way works), but no steering or slowing
		danger[i] = d

	# a unit is close by AND it's sitting on (or right next to) our destination:
	# we're close enough, stop here
	if blocker != null and blocker_dist < whisker_length * 0.75 and not path.is_empty():
		var dest := path[path.size() - 1]
		var gap := Vector2(dest.x - blocker.global_position.x, dest.z - blocker.global_position.z).length()
		if gap < arrive_near_radius:
			_stop_near()
	
	# an ally is in our way (not just beside us): ask it to move aside
	if blocker != null and has_target and blocker_dist < whisker_length * 0.75 and not path.is_empty():
		var to_blocker := blocker.global_position - global_position
		to_blocker.y = 0.0
		if to_blocker.length() > 0.01 and target_dir.dot(to_blocker.normalized()) > 0.3:
			if blocker.has_method("request_make_way"):
				blocker.request_make_way(self, target_dir)

	var left: float = danger[0] + danger[3]
	var right: float = danger[2] + danger[4]
	# + = steer left, so danger on the left pushes us right
	var steer: float = (right - left) * avoid_strength

	if danger[1] > 0.0:
		# blocked ahead: pick the freer side, then stick with it (no flip-flopping)
		if avoid_commit <= 0.0:
			avoid_side = 1.0 if left < right else -1.0
			if is_equal_approx(left, right):
				avoid_side = -1.0
		avoid_commit = 0.8
		steer += avoid_side * danger[1] * avoid_strength * 1.5
	elif avoid_commit > 0.0:
		# front is clear again, but keep curving briefly so the rear clears the corner
		avoid_commit -= delta
		steer += avoid_side * avoid_strength * 0.5

	var worst: float = maxf(maxf(danger[0], danger[1]), maxf(danger[2], maxf(danger[3], danger[4])))
	var path_weight := clampf(worst, 0.0, 0.8)
	if avoid_commit > 0.0:
		path_weight = maxf(path_weight, 0.5)

	# slow down, but not to a crawl: this vehicle can only turn while it's rolling
	var speed_mult: float = 1.0 - clampf(danger[1] * 0.65, 0.0, 0.65)
	if vehicle_ahead:
		speed_mult = minf(speed_mult, 0.5)
	return [steer, speed_mult, path_weight]


func _update_tilt(delta: float):
	if model == null:
		return
	var target_normal := Vector3.UP
	if is_on_floor():
		target_normal = get_floor_normal()
	ground_normal = ground_normal.slerp(target_normal, clampf(tilt_speed * delta, 0.0, 1.0)).normalized()
	var local_normal := (global_transform.basis.orthonormalized().inverse() * ground_normal).normalized()
	var angle := Vector3.UP.angle_to(local_normal)
	var max_angle := deg_to_rad(max_tilt_degrees)
	if angle > max_angle:
		var axis := Vector3.UP.cross(local_normal)
		if axis.length() > 0.001:
			local_normal = Vector3.UP.rotated(axis.normalized(), max_angle)
		else:
			local_normal = Vector3.UP
	model.basis = Basis(Quaternion(Vector3.UP, local_normal)) * model_base_basis
	if angle > max_angle:
		local_normal = Vector3.UP.slerp(local_normal, max_angle / angle)
	model.basis = Basis(Quaternion(Vector3.UP, local_normal)) * model_base_basis


func _update_smoke():
	if smoke == null:
		return
	var ratio := clampf(absf(current_speed) / speed, 0.0, 1.0)
	smoke.emitting = ratio > 0.05
	smoke.amount_ratio = maxf(ratio, 0.1)


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
	pm.direction = Vector3(0, 0.25, -1.0 if forward_is_plus_z else 1.0)   # backwards and slightly up
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

# how much free space there is on one side (+1 = left, -1 = right)
func _side_room(move_dir: Vector3, side: float) -> float:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * whisker_height
	var max_len := detour_side * 1.5
	var dir := move_dir.rotated(Vector3.UP, deg_to_rad(60.0) * side)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_len)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit.normal.y <= 0.7:
		return origin.distance_to(hit.position)
	return max_len

# another friendly vehicle is blocked by us: if we're idle, step aside
func request_make_way(requester: Node3D, their_dir: Vector3):
	if not nav_ready:
		return
	if path_index < path.size():
		return                                  # we have our own orders, stay put
	if not (requester.is_in_group("player_units") and is_in_group("player_units")):
		return                                  # only allies yield

	var dir := their_dir
	dir.y = 0.0
	dir = dir.normalized()
	var perp := dir.cross(Vector3.UP)           # sideways relative to their travel direction

	# step off to the side we're already on; if we're dead in their path, take the freer side
	var offset := global_position - requester.global_position
	offset.y = 0.0
	var side := 1.0 if perp.dot(offset) >= 0.0 else -1.0
	if absf(perp.dot(offset)) < 1.0:
		side = -_freer_side(dir)                # perp is the right-hand side, _freer_side is +1 = left

	move_to(global_position + perp * side * make_way_distance)
	
func _reset_force():
	force_active = false
	force_timer = 0.0
	force_anchor = global_position

func _update_force(delta: float):
	if not has_target:
		_reset_force()
		return

	if force_active:
		force_elapsed += delta
		if global_position.distance_to(force_start) > force_escape_distance:
			force_flip = false
			_reset_force()
		elif force_elapsed > force_max_time:
			force_flip = not force_flip      # didn't get anywhere: try the other direction next time
			_reset_force()
		return

	if global_position.distance_to(force_anchor) > force_stuck_radius:
		force_anchor = global_position
		force_timer = 0.0           # it is moving: reset
		return

	force_timer += delta
	if force_timer >= force_stuck_time:
		force_active = true
		force_elapsed = 0.0
		force_start = global_position
		var ang := _forward().signed_angle_to(target_dir, Vector3.UP)
		force_dir = -1.0 if absf(ang) > deg_to_rad(100.0) else 1.0
		if force_flip:
			force_dir = -force_dir
		unstick_time = 0.0          # cancel the old back-up routine
		stuck_timer = 0.0
		
func _setup_dust():
	dust = GPUParticles3D.new()
	dust.position = dust_offset
	dust.amount = dust_max_amount
	dust.lifetime = dust_lifetime if dust_lifetime != null and dust_lifetime > 0.0 else 2.0
	dust.local_coords = false
	dust.emitting = false
	dust.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 20, 60))
	
	dust.randomness = 1.0        # spreads particle spawn times so they don't come in clumps
	dust.explosiveness = 0.0
	dust.fixed_fps = 0           # smooth, not stepped
	dust.interpolate = true

	dust_pm = ParticleProcessMaterial.new()
	dust_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dust_pm.emission_box_extents = Vector3(0.9, 0.05, 0.3)   # wide: one puff per rear wheel
	dust_pm.direction = Vector3(0, 0.3, 0)
	dust_pm.spread = 40.0
	dust_pm.initial_velocity_min = 0.5
	dust_pm.initial_velocity_max = 1.5
	dust_pm.gravity = Vector3(0, 0.3, 0)
	dust_pm.damping_min = 0.8
	dust_pm.damping_max = 1.5
	dust_pm.scale_min = 0.7
	dust_pm.scale_max = 1.2
	dust_pm.color = dust_color
	dust_pm.angle_min = -180.0
	dust_pm.angle_max = 180.0
	dust_pm.scale_min = 1.8
	dust_pm.scale_max = 3.2
	dust_pm.initial_velocity_min = 0.3     
	dust_pm.initial_velocity_max = 1.2
	dust_pm.emission_box_extents = Vector3(1.1, 0.1, 0.6)

	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 3.5))
	var sct := CurveTexture.new()
	sct.curve = sc
	dust_pm.scale_curve = sct

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	dust_pm.color_ramp = gt
	dust.process_material = dust_pm
	
	var pg := Gradient.new()
	pg.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	pg.colors = PackedColorArray([
		Color(1, 1, 1, 0.9),
		Color(1, 1, 1, 0.55),
		Color(1, 1, 1, 0.15),
		Color(1, 1, 1, 0.0)])
	var puff := GradientTexture2D.new()
	puff.gradient = pg
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	puff.width = 64
	puff.height = 64
	
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.8),
		Color(1, 1, 1, 0.4),
		Color(1, 1, 1, 0.0)])

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
	dust.draw_pass_1 = quad
	add_child(dust)


func _update_dust(delta: float):
	if dust == null:
		return
	var target := _ground_dust_color()
	dust_color = dust_color.lerp(target, clampf(6.0 * delta, 0.0, 1.0))
	dust_pm.color = dust_color

	# dust comes from the back, or from the front while reversing
	dust.position = Vector3(dust_offset.x, dust_offset.y, dust_offset.z * (-1.0 if reversing else 1.0))

	var ratio := clampf(absf(current_speed) / speed, 0.0, 1.0)
	dust.emitting = is_on_floor() and absf(current_speed) > dust_min_speed and target.a > 0.01
	dust.amount_ratio = clampf(ratio * 1.2, 0.4, 1.0)


func _ground_dust_color() -> Color:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, global_position + Vector3.DOWN * 2.0)
	q.exclude = [get_rid()]
	q.collision_mask = 1                      # world only
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit.collider is Node and hit.collider.is_in_group("no_dust"):
		return Color(0, 0, 0, 0)
	var id := _terrain_texture_id()
	if terrain_dust.has(id):
		return terrain_dust[id]
	return default_dust_color


func _terrain_texture_id() -> int:
	if not terrain_checked:
		terrain_checked = true
		terrain_node = get_tree().root.find_child("Terrain3D", true, false)
	if terrain_node == null:
		return -1
	var data = terrain_node.get("data")
	if data == null:
		return -1
	var t = data.get_texture_id(global_position)   # Vector3: base id, overlay id, blend
	return int(t.x) if t.z < 0.5 else int(t.y)
