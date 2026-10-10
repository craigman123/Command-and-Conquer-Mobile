extends VehicleBase

# Shared stuff (selection ring, whisker avoidance, vehicles-as-obstacles,
# stuck check, tilt, smoke) lives in VehicleBase.
# This file only holds what makes the Humvee drive like a Humvee.

@export_group("Humvee Driving")
@export var reverse_speed := 8.0
@export var turn_radius := 6.0           # smaller = tighter turns
@export var reverse_distance := 12.0     # target closer than this and behind -> reverse instead of U-turn
var uturn_side := 0.0          			 # +1 = turn left, -1 = turn right, 0 = not U-turning
var uturn_backout := false     


func _init():
	dust_enabled = true
	dust_offset = Vector3(0.0, 0.3, -2.0)
	smoke_offset = Vector3(0.0, 0.7, -1.3)


func _find_model() -> Node3D:
	return $humvee

func move_to(pos: Vector3):
	uturn_side = 0.0
	uturn_backout = false
	super.move_to(pos)

func _drive(delta: float):
	var target_speed := 0.0
	var steer_angle := 0.0

	if has_target:
		var angle := _forward().signed_angle_to(target_dir, Vector3.UP)  # + = target is to the left
		var angle_abs := absf(angle)

		if force_active:
			reversing = force_dir < 0.0
			if reversing:
				steer_angle = wrapf(angle - PI, -PI, PI)
				target_speed = -reverse_speed
			else:
				steer_angle = angle
				target_speed = speed
		else:
			# forward vs reverse (hysteresis so it doesn't flicker)
			if target_dist < reverse_distance:
				if angle_abs > deg_to_rad(100.0):
					reversing = true
				elif angle_abs < deg_to_rad(80.0):
					reversing = false
			else:
				reversing = false

			# target is behind us: pick the side with room, or back out if both are tight
			if angle_abs > deg_to_rad(100.0) and uturn_side == 0.0:
				var l := _side_clearance(1.0)
				var r := _side_clearance(-1.0)
				if maxf(l, r) < turn_radius * 1.8:
					uturn_backout = true
				else:
					uturn_backout = false
					uturn_side = 1.0 if l >= r else -1.0
			elif angle_abs < deg_to_rad(80.0):
				uturn_side = 0.0
				uturn_backout = false

			if uturn_backout:
				reversing = true

			if reversing:
				steer_angle = wrapf(angle - PI, -PI, PI)
				target_speed = -reverse_speed
			else:
				steer_angle = angle
				if uturn_side != 0.0:
					steer_angle = uturn_side * angle_abs     # force the turn toward the open side
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
	
func _side_clearance(side: float) -> float:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * whisker_height
	var f := _forward()
	var reach := turn_radius * 2.0
	var best := reach
	for deg in [30.0, 60.0, 90.0, 120.0]:
		var dir := f.rotated(Vector3.UP, deg_to_rad(deg) * side)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y > 0.7:
			continue                                   # open ground / slope
		if hit.collider is Node and _is_vehicle(hit.collider):
			continue                                   # other vehicles don't block a turn
		best = minf(best, origin.distance_to(hit.position))
	return best
