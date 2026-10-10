extends Node
class_name WheeledDriving

@export var reverse_speed := 8.0
@export var turn_radius := 6.0
@export var reverse_distance := 12.0

var v: VehicleBase
var uturn_side := 0.0
var uturn_backout := false

func setup(vehicle: VehicleBase):
	v = vehicle

func on_new_order():
	uturn_side = 0.0
	uturn_backout = false

func drive(delta: float):
	var target_speed := 0.0
	var steer_angle := 0.0

	if v.has_target:
		var angle := v._forward().signed_angle_to(v.target_dir, Vector3.UP)
		var angle_abs := absf(angle)

		if v.force_active:
			v.reversing = v.force_dir < 0.0
			if v.reversing:
				steer_angle = wrapf(angle - PI, -PI, PI)
				target_speed = -reverse_speed
			else:
				steer_angle = angle
				target_speed = v.speed
		else:
			if v.target_dist < reverse_distance:
				if angle_abs > deg_to_rad(100.0):
					v.reversing = true
				elif angle_abs < deg_to_rad(80.0):
					v.reversing = false
			else:
				v.reversing = false

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
				v.reversing = true

			if v.reversing:
				steer_angle = wrapf(angle - PI, -PI, PI)
				target_speed = -reverse_speed
			else:
				steer_angle = angle
				if uturn_side != 0.0:
					steer_angle = uturn_side * angle_abs
				target_speed = v.speed
				if absf(steer_angle) > deg_to_rad(50.0):
					target_speed = v.speed * 0.4

		if v.is_last_waypoint and v.target_dist < v.slow_down_distance:
			target_speed *= clampf(v.target_dist / v.slow_down_distance, 0.25, 1.0)

		var avoid := v._avoid_obstacles()
		steer_angle = clampf(steer_angle * (1.0 - avoid[2]) + avoid[0], -PI, PI)
		target_speed *= avoid[1]
	else:
		v.reversing = false

	if v._update_stuck(delta, target_speed):
		v.reversing = true
		var back_avoid := v._avoid_obstacles()
		target_speed = -reverse_speed * back_avoid[1]
		steer_angle = -steer_angle
		if v.unstick_time <= 0.0 and not v.has_target:
			v.reversing = false

	v._accelerate(target_speed, delta)

	var max_step := absf(v.current_speed) / turn_radius * delta
	v.rotation.y += clampf(steer_angle, -max_step, max_step)

func _side_clearance(side: float) -> float:
	var space := v.get_world_3d().direct_space_state
	var origin := v.global_position + Vector3.UP * v.whisker_height
	var f := v._forward()
	var reach := turn_radius * 2.0
	var best := reach
	for deg in [30.0, 60.0, 90.0, 120.0]:
		var dir := f.rotated(Vector3.UP, deg_to_rad(deg) * side)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach)
		q.exclude = [v.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y > 0.7:
			continue
		if hit.collider is Node and v._is_vehicle(hit.collider):
			continue
		best = minf(best, origin.distance_to(hit.position))
	return best
