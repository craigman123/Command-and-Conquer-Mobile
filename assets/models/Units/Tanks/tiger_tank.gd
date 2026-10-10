extends VehicleBase

# Shared stuff (selection ring, whiskers, stuck check, make-way, tilt, smoke)
# lives in VehicleBase. This file only holds how a tank drives.

@export_group("Tank Driving")
@export var turn_rate_degrees := 120.0   # tracks can pivot in place
@export var pivot_angle_degrees := 45.0  # target more off-axis than this -> stop and turn first


func _init():
	forward_is_plus_z = false                  # the tank model faces -Z
	speed = 5.0
	smoke_offset = Vector3(0.0, 0.7, 2.3)      # exhaust at the rear (+Z for this model)
	dust_offset = Vector3(0.0, 0.3, 2.5)


func _drive(delta: float):
	var target_speed := 0.0
	var steer_angle := 0.0

	if has_target:
		var angle := _forward().signed_angle_to(target_dir, Vector3.UP)  # + = target is to the left
		if force_active:
			reversing = force_dir < 0.0
			if reversing:
				steer_angle = wrapf(angle - PI, -PI, PI)
				target_speed = -speed * 0.6
			else:
				steer_angle = angle
				target_speed = speed            # no stopping to pivot while forcing
		else:
			reversing = false
			steer_angle = angle
			target_speed = speed
			if absf(angle) > deg_to_rad(pivot_angle_degrees):
				target_speed = 0.0                # turn on the spot first

		# brake near the end of the path
		if is_last_waypoint and target_dist < slow_down_distance:
			target_speed *= clampf(target_dist / slow_down_distance, 0.25, 1.0)

		# whiskers -> [extra_steer, speed_multiplier, path_weight]
		var avoid := _avoid_obstacles()
		steer_angle = clampf(steer_angle * (1.0 - avoid[2]) + avoid[0], -PI, PI)
		target_speed *= avoid[1]
	else:
		reversing = false

	# stuck detection: back up for a moment
	if _update_stuck(delta, target_speed):
		reversing = true
		target_speed = -speed * 0.6
		steer_angle = -steer_angle

	_accelerate(target_speed, delta)

	# tracks turn independently of speed
	var max_step := deg_to_rad(turn_rate_degrees) * delta
	rotation.y += clampf(steer_angle, -max_step, max_step)
