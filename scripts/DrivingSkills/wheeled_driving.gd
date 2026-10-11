extends Node
class_name WheeledDriving

@export var reverse_speed := 8.0
@export var turn_radius := 6.0
@export var short_reverse_distance := 8.0   # destination this close behind us: back up to it, but only if the way back is clear
@export var min_turn_speed := 3.0           # can still steer while almost stopped (otherwise it can't turn from a standstill)
@export var corner_speed_factor := 0.55     # speed multiplier at a 90 degree corner (1.0 = never slow for corners)
@export var arrive_decel := 0.6             # share of brake_force used to plan the stop (lower = starts braking earlier)
@export var bumper_room := 3.5              # measured from the vehicle centre: less than this ahead/behind counts as blocked
@export var three_point_angle := 60.0       # degrees to turn before switching forward <-> reverse in a tight spot

# ---------- NEW ----------
@export var side_margin := 2.5              # a unit closer than this (from our centre) BESIDE us blocks the swing of the nose/tail
@export var sense_interval := 0.12          # seconds between raycast sweeps. Results are reused in between (main lag saver)
@export var uturn_timeout := 6.0            # a U-turn that takes longer than this is abandoned for a three-point turn
@export var three_point_timeout := 10.0     # a three-point turn that takes longer than this is abandoned
@export var max_shuffles := 8               # max forward/back switches in one three-point turn
@export var maneuver_cooldown := 1.5        # after a failed manoeuvre, wait this long before planning another
@export var orbit_limit_degrees := 400.0    # turned this much without getting closer = circling the destination
@export var orbit_progress := 1.5           # metres closer that count as "making progress"
@export var orbit_give_up_dist := 8.0       # circling this close to the destination twice: call it arrived

enum Mode { NORMAL, REVERSE, UTURN, THREE_POINT }

var v: VehicleBase
var mode := Mode.NORMAL
var turn_side := 0.0        # +1 = turn left, -1 = turn right (same convention as _side_clearance)
var tp_forward := true
var tp_turned := 0.0
var tp_hold := 0.0
var last_yaw := 0.0

var _man_time := 0.0        # how long the current manoeuvre has been running
var _shuffles := 0
var _cooldown := 0.0
var _best_dist := INF       # orbit detection
var _orbit_yaw := 0.0
var _orbit_strikes := 0
var _crawl_time := 0.0      # while > 0 the vehicle crawls so its turning circle shrinks

# cached sensor readings (see _sense)
var _clock := 0.0
var _last_sense := -100.0
var _front := 99.0
var _rear := 99.0
var _left := 99.0
var _right := 99.0
var _beside_l := 99.0
var _beside_r := 99.0
var _query := PhysicsRayQueryParameters3D.new()   # one query object, reused for every ray


func setup(vehicle: VehicleBase):
	v = vehicle
	last_yaw = v.rotation.y
	_query.exclude = [v.get_rid()]
	_clock = randf() * sense_interval   # spread units out so they don't all raycast on the same frame


func on_new_order():
	_end_maneuver()
	_cooldown = 0.0
	_reset_orbit()


func _end_maneuver():
	mode = Mode.NORMAL
	turn_side = 0.0
	tp_forward = true
	tp_turned = 0.0
	tp_hold = 0.0
	_man_time = 0.0
	_shuffles = 0


func _enter(m: Mode):
	mode = m
	_man_time = 0.0
	_shuffles = 0
	tp_forward = true
	tp_turned = 0.0
	tp_hold = 0.0


func _reset_orbit():
	_best_dist = INF
	_orbit_yaw = 0.0
	_orbit_strikes = 0
	_crawl_time = 0.0


func drive(delta: float):
	var target_speed := 0.0
	var steer_angle := 0.0
	var avoid_steer := 0.0
	var avoid_speed := 1.0
	var avoid_weight := 0.0
	var avoided := false

	_clock += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_crawl_time = maxf(_crawl_time - delta, 0.0)
	if mode != Mode.NORMAL:
		_man_time += delta

	if v.has_target:
		var angle := v._forward().signed_angle_to(v.target_dir, Vector3.UP)
		var angle_abs := absf(angle)

		if v.force_active:
			_end_maneuver()
			v.reversing = v.force_dir < 0.0
			if v.reversing:
				steer_angle = wrapf(angle - PI, -PI, PI)
				target_speed = -reverse_speed
			else:
				steer_angle = angle
				target_speed = v.speed
		else:
			_plan_maneuver(angle)

			match mode:
				Mode.NORMAL:
					v.reversing = false
					steer_angle = angle
					target_speed = v.speed * _turn_speed_factor(angle_abs) * _corner_factor()
					target_speed = minf(target_speed, _close_turn_cap(angle_abs))

				Mode.REVERSE:
					# destination is just behind us and the way back is clear
					v.reversing = true
					steer_angle = wrapf(angle - PI, -PI, PI)
					target_speed = -reverse_speed

				Mode.UTURN:
					# enough room beside us: one smooth forward half-circle
					v.reversing = false
					steer_angle = turn_side * PI
					target_speed = v.speed * 0.6

				Mode.THREE_POINT:
					# tight spot: shuffle forward / back, always turning the same way
					_ensure_sensed(sense_interval * 0.5)
					tp_hold = maxf(tp_hold - delta, 0.0)
					if tp_hold <= 0.0:
						var turned_enough := tp_turned > deg_to_rad(three_point_angle)
						if tp_forward and (turned_enough or _front < bumper_room):
							tp_forward = false
							tp_turned = 0.0
							tp_hold = 0.5
							_shuffles += 1
						elif not tp_forward and (turned_enough or _rear < bumper_room):
							tp_forward = true
							tp_turned = 0.0
							tp_hold = 0.5
							_shuffles += 1
					v.reversing = not tp_forward
					steer_angle = turn_side * PI
					target_speed = v.speed * 0.4 if tp_forward else -reverse_speed * 0.5

		# plan the stop: brake as late as the brakes allow, but never crawl
		if v.is_last_waypoint:
			var cap := maxf(sqrt(2.0 * v.brake_force * arrive_decel * v.target_dist), 2.0)
			target_speed = clampf(target_speed, -cap, cap)

		if mode != Mode.THREE_POINT:
			var avoid = v._avoid_obstacles()
			avoid_steer = avoid[0]
			avoid_speed = avoid[1]
			avoid_weight = avoid[2]
			avoided = true
			steer_angle = clampf(steer_angle * (1.0 - avoid_weight) + avoid_steer, -PI, PI)
			target_speed *= avoid_speed
	else:
		v.reversing = false
		if mode != Mode.NORMAL:
			_end_maneuver()
		_reset_orbit()

	if mode != Mode.THREE_POINT and v._update_stuck(delta, target_speed):
		v.reversing = true
		if not avoided:
			var back_avoid = v._avoid_obstacles()
			avoid_speed = back_avoid[1]
		target_speed = -reverse_speed * avoid_speed
		steer_angle = -steer_angle
		if v.unstick_time <= 0.0 and not v.has_target:
			v.reversing = false

	v._accelerate(target_speed, delta)

	var turn_speed := absf(v.current_speed)
	if v.has_target:
		turn_speed = maxf(turn_speed, min_turn_speed)
	var max_step := turn_speed / turn_radius * delta
	v.rotation.y += clampf(steer_angle, -max_step, max_step)

	var yaw_change := absf(wrapf(v.rotation.y - last_yaw, -PI, PI))
	if mode == Mode.THREE_POINT:
		tp_turned += yaw_change
	last_yaw = v.rotation.y

	_check_orbit(yaw_change)


# Decides HOW to face a destination that is behind us. Runs once per manoeuvre
# (plus cheap cached checks while it is running), so it doesn't spam raycasts.
func _plan_maneuver(angle: float):
	var angle_abs := absf(angle)
	match mode:
		Mode.NORMAL:
			if angle_abs <= deg_to_rad(100.0) or _cooldown > 0.0:
				return
			_ensure_sensed(sense_interval)
			turn_side = _pick_side(angle)

			if v.target_dist < short_reverse_distance and _reverse_is_safe(v.target_dist):
				_enter(Mode.REVERSE)            # short and the way back is clear: just back up to it
			elif maxf(_left, _right) >= turn_radius * 1.8 and _front >= turn_radius * 0.8:
				_enter(Mode.UTURN)              # room beside AND ahead: drive round
			else:
				_enter(Mode.THREE_POINT)        # boxed in: shuffle round

		Mode.REVERSE:
			_ensure_sensed(sense_interval)
			if angle_abs < deg_to_rad(80.0):
				_end_maneuver()
			elif _rear < 1.5 or _beside_l < side_margin * 0.6 or _beside_r < side_margin * 0.6:
				# something appeared behind / right beside us: don't back into it, turn instead
				turn_side = _pick_side(angle)
				_enter(Mode.THREE_POINT)

		Mode.UTURN:
			_ensure_sensed(sense_interval)
			if angle_abs < deg_to_rad(70.0):
				_end_maneuver()
			elif _man_time > uturn_timeout or _front < 1.5:
				# the half-circle isn't working (blocked, or a unit moved into the arc)
				turn_side = _pick_side(angle)
				_enter(Mode.THREE_POINT)

		Mode.THREE_POINT:
			if angle_abs < deg_to_rad(70.0):
				_end_maneuver()
			elif _man_time > three_point_timeout or _shuffles > max_shuffles:
				# give up for a moment so the stuck-recovery and avoidance get a turn
				_end_maneuver()
				_cooldown = maneuver_cooldown


# Which way to turn: normally the shorter way round (towards the side the destination
# is on), but only if that side has room. Otherwise the roomier side.
func _pick_side(angle: float) -> float:
	var want := 1.0 if angle >= 0.0 else -1.0
	var want_room := _left if want > 0.0 else _right
	var other_room := _right if want > 0.0 else _left
	if want_room >= turn_radius * 1.8 or want_room >= other_room * 0.7:
		return want
	return -want


# Backing up is only worth it when nothing is behind us AND nothing is standing
# beside us where the nose or tail would swing into it.
func _reverse_is_safe(dist: float) -> bool:
	return _rear > dist + 1.0 and _rear >= bumper_room \
		and _beside_l >= side_margin and _beside_r >= side_margin


# smooth slow-down for big steering angles (instead of a sudden 40% step)
func _turn_speed_factor(angle_abs: float) -> float:
	return lerpf(1.0, 0.5, clampf(angle_abs / deg_to_rad(100.0), 0.0, 1.0))


# The turning circle shrinks as speed drops (yaw rate = speed / turn_radius, with a floor of
# min_turn_speed). When the destination is INSIDE the normal turning circle, full speed makes the
# vehicle orbit it forever, so slow down enough for the circle to fit.
func _close_turn_cap(angle_abs: float) -> float:
	if _crawl_time > 0.0:
		return 1.0
	if v.target_dist >= turn_radius * 2.0 or angle_abs < deg_to_rad(30.0):
		return INF
	return maxf(min_turn_speed * (v.target_dist * 0.5 / turn_radius), 1.0)


# Backstop: if we keep turning but never get closer, we're circling. First crawl (tighter
# circle); if that fails too and we're already close, accept it as arrived.
func _check_orbit(yaw_change: float):
	if not v.has_target or v.force_active:
		_reset_orbit()
		return
	if v.target_dist < _best_dist - orbit_progress:
		_best_dist = v.target_dist
		_orbit_yaw = 0.0
		return
	_orbit_yaw += yaw_change
	if _orbit_yaw < deg_to_rad(orbit_limit_degrees):
		return
	_orbit_yaw = 0.0
	_orbit_strikes += 1
	if _orbit_strikes == 1:
		_crawl_time = 4.0
	elif v.target_dist < orbit_give_up_dist:
		v.has_target = false     # close enough. NOTE: check this matches how VehicleBase marks arrival
		_end_maneuver()
		_reset_orbit()
	else:
		_crawl_time = 4.0
		_cooldown = 0.0
		turn_side = 1.0 if v._forward().signed_angle_to(v.target_dir, Vector3.UP) >= 0.0 else -1.0
		_enter(Mode.THREE_POINT)


# looks one waypoint ahead: slow down for a sharp corner coming up, stay fast on a straight
func _corner_factor() -> float:
	if v.is_last_waypoint or v.path_index + 1 >= v.path.size() or v.target_dist > 8.0:
		return 1.0
	var a: Vector3 = v.path[v.path_index]
	var b: Vector3 = v.path[v.path_index + 1]
	var seg1 := a - v.global_position
	var seg2 := b - a
	seg1.y = 0.0
	seg2.y = 0.0
	if seg1.length() < 0.1 or seg2.length() < 0.1:
		return 1.0
	var k := clampf(seg1.angle_to(seg2) / deg_to_rad(90.0), 0.0, 1.0)
	return lerpf(1.0, corner_speed_factor, k)


# ---------- SENSING (cached) ----------
# All distances are measured from the vehicle centre. Units block like walls.

func _room(dir_sign: float, reach: float) -> float:
	_ensure_sensed(sense_interval)
	return minf(_front if dir_sign > 0.0 else _rear, reach)


func _side_clearance(side: float) -> float:
	_ensure_sensed(sense_interval)
	return _left if side > 0.0 else _right


func _ensure_sensed(max_age: float):
	if _clock - _last_sense >= max_age:
		_sense()


func _sense():
	_last_sense = _clock
	var space := v.get_world_3d().direct_space_state
	var origin := v.global_position + Vector3.UP * v.whisker_height
	var f := v._forward()
	var reach := maxf(turn_radius * 2.0, short_reverse_distance + 2.0)
	var beside_reach := side_margin + 2.0

	_front = _fan(space, origin, f, [-35.0, 0.0, 35.0], reach)
	_rear = _fan(space, origin, -f, [-35.0, 0.0, 35.0], reach)
	_left = _fan(space, origin, f, [30.0, 60.0, 90.0, 120.0], turn_radius * 2.0)
	_right = _fan(space, origin, f, [-30.0, -60.0, -90.0, -120.0], turn_radius * 2.0)
	_beside_l = _fan(space, origin, f, [70.0, 90.0, 110.0], beside_reach)
	_beside_r = _fan(space, origin, f, [-70.0, -90.0, -110.0], beside_reach)


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
