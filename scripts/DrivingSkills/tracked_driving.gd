extends Node
class_name TrackedDriving

@export var turn_rate_degrees := 120.0
@export var pivot_angle_degrees := 45.0

# ---------- NEW ----------
@export var short_reverse_distance := 6.0   # destination this close behind us: back up to it if the way back is clear
@export var side_margin := 2.5              # a unit closer than this beside us blocks reversing (hull swings when it pivots)
@export var sense_interval := 0.15          # seconds between raycast sweeps; results are reused in between

var v: VehicleBase
var _reversing_now := false
var _clock := 0.0
var _last_sense := -100.0
var _rear := 99.0
var _beside_l := 99.0
var _beside_r := 99.0
var _query := PhysicsRayQueryParameters3D.new()


func setup(vehicle: VehicleBase):
	v = vehicle
	_query.exclude = [v.get_rid()]
	_clock = randf() * sense_interval


func on_new_order():
	_reversing_now = false


func drive(delta: float):
	var target_speed := 0.0
	var steer_angle := 0.0
	_clock += delta

	if v.has_target:
		var angle := v._forward().signed_angle_to(v.target_dir, Vector3.UP)
		var angle_abs := absf(angle)
		if v.force_active:
			_reversing_now = false
			v.reversing = v.force_dir < 0.0
			if v.reversing:
				steer_angle = wrapf(angle - PI, -PI, PI)
				target_speed = -v.speed * 0.6
			else:
				steer_angle = angle
				target_speed = v.speed
		else:
			# Reverse only when it is short AND nothing is behind or beside us.
			# Once reversing, keep going until we're clearly facing it again (no flip-flopping).
			if _reversing_now:
				if angle_abs < deg_to_rad(100.0) or not _rear_is_clear(v.target_dist):
					_reversing_now = false
			elif angle_abs > deg_to_rad(120.0) and v.target_dist < short_reverse_distance \
					and _rear_is_clear(v.target_dist):
				_reversing_now = true

			if _reversing_now:
				v.reversing = true
				steer_angle = wrapf(angle - PI, -PI, PI)
				target_speed = -v.speed * 0.6
			else:
				# turning left/right/U-turn: tracks pivot on the spot, the shortest way round
				v.reversing = false
				steer_angle = angle
				target_speed = v.speed
				if angle_abs > deg_to_rad(pivot_angle_degrees):
					target_speed = 0.0

		if v.is_last_waypoint and v.target_dist < v.slow_down_distance:
			target_speed *= clampf(v.target_dist / v.slow_down_distance, 0.25, 1.0)

		var avoid = v._avoid_obstacles()
		steer_angle = clampf(steer_angle * (1.0 - avoid[2]) + avoid[0], -PI, PI)
		target_speed *= avoid[1]
	else:
		_reversing_now = false
		v.reversing = false

	if v._update_stuck(delta, target_speed):
		v.reversing = true
		target_speed = -v.speed * 0.6
		steer_angle = -steer_angle

	v._accelerate(target_speed, delta)

	var max_step := deg_to_rad(turn_rate_degrees) * delta
	v.rotation.y += clampf(steer_angle, -max_step, max_step)


func _rear_is_clear(dist: float) -> bool:
	if _clock - _last_sense >= sense_interval:
		_sense()
	return _rear > dist + 1.0 and _beside_l >= side_margin and _beside_r >= side_margin


func _sense():
	_last_sense = _clock
	var space := v.get_world_3d().direct_space_state
	var origin := v.global_position + Vector3.UP * v.whisker_height
	var f := v._forward()
	_rear = _fan(space, origin, -f, [-35.0, 0.0, 35.0], short_reverse_distance + 2.0)
	_beside_l = _fan(space, origin, f, [70.0, 90.0, 110.0], side_margin + 2.0)
	_beside_r = _fan(space, origin, f, [-70.0, -90.0, -110.0], side_margin + 2.0)


func _fan(space: PhysicsDirectSpaceState3D, origin: Vector3, base: Vector3, degs: Array, reach: float) -> float:
	var best := reach
	for deg in degs:
		var dir := base.rotated(Vector3.UP, deg_to_rad(deg))
		_query.from = origin
		_query.to = origin + dir * reach
		var hit := space.intersect_ray(_query)
		if hit.is_empty() or hit.normal.y > 0.7:
			continue
		best = minf(best, origin.distance_to(hit.position))
	return best
