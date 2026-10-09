extends VehicleBase

# Shared stuff (selection ring, whisker avoidance, vehicles-as-obstacles,
# stuck check, tilt, smoke) lives in VehicleBase.
# This file only holds what makes the Humvee drive like a Humvee.

@export_group("Humvee Driving")
@export var reverse_speed := 8.0
@export var turn_radius := 6.0           # smaller = tighter turns
@export var reverse_distance := 12.0     # target closer than this and behind -> reverse instead of U-turn


func _init():
	# the Humvee's exhaust sits closer than VehicleBase's default
	smoke_offset = Vector3(0.0, 0.7, -1.3)


func _find_model() -> Node3D:
	return $humvee


func _drive(delta: float):
	var target_speed := 0.0
	var steer_angle := 0.0

	if has_target:
		var angle := _forward().signed_angle_to(target_dir, Vector3.UP)  # + = target is to the left
		var angle_abs := absf(angle)

		# decide forward vs reverse (with hysteresis so it doesn't flicker)
		if target_dist < reverse_distance:
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
			if absf(steer_angle) > deg_to_rad(50.0):
				target_speed = speed * 0.4

		# brake near the end of the path
		if is_last_waypoint and target_dist < slow_down_distance:
			target_speed *= clampf(target_dist / slow_down_distance, 0.25, 1.0)

		# obstacle avoidance (whiskers) -> [extra_steer, speed_multiplier, path_weight]
		var avoid := _avoid_obstacles()
		steer_angle = clampf(steer_angle * (1.0 - avoid[2]) + avoid[0], -PI, PI)
		target_speed *= avoid[1]
	else:
		reversing = false

	# stuck detection: wanted to move but barely did -> back up for a bit
	if _update_stuck(delta, target_speed):
		reversing = true
		var back_avoid := _avoid_obstacles()
		target_speed = -reverse_speed * back_avoid[1]
		steer_angle = -steer_angle
		if unstick_time <= 0.0 and not has_target:
			reversing = false

	_accelerate(target_speed, delta)

	# steering only works while rolling: yaw rate = speed / turn radius
	var max_step := absf(current_speed) / turn_radius * delta
	rotation.y += clampf(steer_angle, -max_step, max_step)
