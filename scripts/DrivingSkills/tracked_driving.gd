extends Node
class_name TrackedDriving

@export var turn_rate_degrees := 120.0
@export var pivot_angle_degrees := 45.0

var v: VehicleBase

func setup(vehicle: VehicleBase):
	v = vehicle

func drive(delta: float):
	var target_speed := 0.0
	var steer_angle := 0.0

	if v.has_target:
		var angle := v._forward().signed_angle_to(v.target_dir, Vector3.UP)
		if v.force_active:
			v.reversing = v.force_dir < 0.0
			if v.reversing:
				steer_angle = wrapf(angle - PI, -PI, PI)
				target_speed = -v.speed * 0.6
			else:
				steer_angle = angle
				target_speed = v.speed
		else:
			v.reversing = false
			steer_angle = angle
			target_speed = v.speed
			if absf(angle) > deg_to_rad(pivot_angle_degrees):
				target_speed = 0.0

		if v.is_last_waypoint and v.target_dist < v.slow_down_distance:
			target_speed *= clampf(v.target_dist / v.slow_down_distance, 0.25, 1.0)

		var avoid := v._avoid_obstacles()
		steer_angle = clampf(steer_angle * (1.0 - avoid[2]) + avoid[0], -PI, PI)
		target_speed *= avoid[1]
	else:
		v.reversing = false

	if v._update_stuck(delta, target_speed):
		v.reversing = true
		target_speed = -v.speed * 0.6
		steer_angle = -steer_angle

	v._accelerate(target_speed, delta)

	var max_step := deg_to_rad(turn_rate_degrees) * delta
	v.rotation.y += clampf(steer_angle, -max_step, max_step)
