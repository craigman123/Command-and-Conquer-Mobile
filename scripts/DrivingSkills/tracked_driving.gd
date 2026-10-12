extends Node
class_name TrackedDriving

@export var turn_rate_degrees := 120.0
@export var pivot_angle_degrees := 45.0

# ---------- REVERSING ----------
@export var short_reverse_distance := 30.0  # destination BEHIND us closer than this: reverse to it (if the way back is clear)
@export var rear_check_distance := 10.0     # we need this much clear ground behind us to start reversing (checked again as we go)
@export var side_margin := 2.5              # a unit closer than this beside us blocks reversing (hull swings when it pivots)
@export var reverse_commit_time := 1.0     # first seconds of a reverse: only a destination clearly IN FRONT cancels it (stops click-spam flip-flopping)
@export var reverse_lockout := 4.0          # got stuck while reversing? don't try reversing again for this long
@export var sense_interval := 0.15          # seconds between raycast sweeps; results are reused in between
@export var debug_print := false            # prints WHY the tank reverses / stops reversing / gets stuck (turn on to investigate)

# ---------- RETREAT ("back down") ----------
@export var retreat_distance := 25.0        # how far to back away from the enemy (metres)
@export var retreat_reverse_max := 20.0     # reverse at most this far; the rest is driven forward
@export var retreat_safe_distance := 60.0   # stop early once this far from the enemy
@export var retreat_timeout := 15.0         # give up the retreat after this many seconds (e.g. if it is stuck)

var v: VehicleBase
var _reversing_now := false
var _reverse_lock := 0.0
var _reverse_time := 0.0
var _unstick_forward := false
var _was_force := false
var _clock := 0.0
var _last_sense := -100.0
var _rear := 99.0
var _beside_l := 99.0
var _beside_r := 99.0
var _query := PhysicsRayQueryParameters3D.new()

var _retreating := false
var _retreat_reversing := true
var _retreat_start := Vector3.ZERO
var _retreat_dist := 25.0
var _retreat_time := 0.0
var _threat_node: Node3D = null
var _threat_pos := Vector3.ZERO


func setup(vehicle: VehicleBase):
	v = vehicle
	_query.exclude = [v.get_rid()]
	_clock = randf() * sense_interval


func on_new_order():
	_retreating = false
	# NOTE: we do NOT reset _reversing_now. If the player clicks again and again while the
	# tank is backing up, it must keep backing up (towards the newest click), not start over.


# Call this when the player tells the unit to back down.
# threat = the enemy (a Node3D, followed while it lives) or a Vector3 position.
# The tank keeps its FRONT toward the threat and reverses away; if something is behind it,
# or the retreat is long, it pivots round and drives forward. Any new order cancels it.
func start_retreat(threat, distance: float = -1.0) -> void:
	if v == null:
		return
	v._stop_near()                          # drop the old move order (clears the path)
	_reversing_now = false
	_threat_node = null
	if threat is Node3D:
		_threat_node = threat
		_threat_pos = threat.global_position
	elif threat is Vector3:
		_threat_pos = threat
	else:
		return
	_retreat_dist = distance if distance > 0.0 else retreat_distance
	_retreat_start = v.global_position
	_retreat_time = 0.0
	_sense()
	_retreat_reversing = _rear >= 3.0
	_retreating = true


func stop_retreat() -> void:
	_retreating = false
	_threat_node = null


func is_retreating() -> bool:
	return _retreating


func drive(delta: float):
	var target_speed := 0.0
	var steer_angle := 0.0
	_clock += delta
	_reverse_lock = maxf(_reverse_lock - delta, 0.0)

	if _retreating:
		_drive_retreat(delta)
		return

	if v.force_active != _was_force:
		_was_force = v.force_active
		_dbg("force-through %s (dir %s)" % ["ON" if _was_force else "off", "reverse" if v.force_dir < 0.0 else "forward"])

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
			# Reverse when the destination is behind us and the ground behind is clear.
			# Once reversing, keep going (no flip-flopping) until the destination is no longer behind
			# us or something gets in the way.
			if _reversing_now:
				_reverse_time += delta
				var exit_deg := 60.0 if _reverse_time < reverse_commit_time else 100.0
				if angle_abs < deg_to_rad(exit_deg):
					_set_reversing(false, "destination in front of us")
				elif v.target_dist > short_reverse_distance * 1.5:
					_set_reversing(false, "destination too far to reverse all the way")
				elif not _rear_is_clear(v.target_dist):
					_set_reversing(false, "something behind us")
			elif _reverse_lock <= 0.0 and angle_abs > deg_to_rad(120.0) \
					and v.target_dist < short_reverse_distance and _rear_is_clear(v.target_dist):
				_set_reversing(true, "destination %.1f m behind" % v.target_dist)

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

	# Stuck recovery. VehicleBase always wants to BACK UP out of a jam, but if we were already
	# reversing, backing up again just pushes us further into whatever is behind us.
	# So: stuck while reversing -> drive FORWARD out of it, and don't reverse again for a while.
	var unsticking: bool = v._update_stuck(delta, target_speed)
	if unsticking:
		if _reversing_now:
			_set_reversing(false, "stuck while reversing, going forward instead")
			_reverse_lock = reverse_lockout
			_unstick_forward = true
		var back := not _unstick_forward
		v.reversing = back
		target_speed = -v.speed * 0.6 if back else v.speed * 0.6
		if back:
			steer_angle = -steer_angle
	else:
		_unstick_forward = false

	v._accelerate(target_speed, delta)

	var max_step := deg_to_rad(turn_rate_degrees) * delta
	v.rotation.y += clampf(steer_angle, -max_step, max_step)


func _set_reversing(on: bool, why: String) -> void:
	if on and not _reversing_now:
		_reverse_time = 0.0
	if _reversing_now != on:
		_dbg("%s: %s" % ["REVERSE start" if on else "reverse stop", why])
	_reversing_now = on


func _dbg(msg: String) -> void:
	if debug_print:
		print("[Tracked ", v.name, "] ", msg)


func _drive_retreat(delta: float) -> void:
	if _threat_node != null and is_instance_valid(_threat_node):
		_threat_pos = _threat_node.global_position
	var pos := v.global_position
	var away := pos - _threat_pos
	away.y = 0.0
	if away.length() < 0.5:
		away = -v._forward()
	away = away.normalized()

	_retreat_time += delta
	var travelled := Vector2(pos.x - _retreat_start.x, pos.z - _retreat_start.z).length()
	var from_threat := Vector2(pos.x - _threat_pos.x, pos.z - _threat_pos.z).length()
	if travelled >= _retreat_dist or from_threat >= retreat_safe_distance or _retreat_time >= retreat_timeout:
		stop_retreat()
		v.reversing = false
		v._accelerate(0.0, delta)
		return

	if _clock - _last_sense >= sense_interval * 0.5:
		_sense()
	if _retreat_reversing and (_rear < 1.5 or travelled >= retreat_reverse_max):
		_retreat_reversing = false

	var angle := v._forward().signed_angle_to(away, Vector3.UP)
	var steer_angle := 0.0
	var target_speed := 0.0

	if _retreat_reversing:
		# back away with the front still on the enemy
		v.reversing = true
		steer_angle = wrapf(angle - PI, -PI, PI)
		var room := clampf((_rear - 1.5) / 4.0, 0.25, 1.0)
		target_speed = -v.speed * 0.6 * room
	else:
		# pivot round, then drive away forward
		v.reversing = false
		steer_angle = angle
		target_speed = v.speed
		if absf(angle) > deg_to_rad(pivot_angle_degrees):
			target_speed = 0.0
		var avoid = v._avoid_obstacles()
		steer_angle = clampf(steer_angle * (1.0 - avoid[2]) + avoid[0], -PI, PI)
		target_speed *= avoid[1]

	v._accelerate(target_speed, delta)
	var max_step := deg_to_rad(turn_rate_degrees) * delta
	v.rotation.y += clampf(steer_angle, -max_step, max_step)


# Is the ground behind us clear? We only need rear_check_distance of it to START reversing;
# this is checked again every sweep while we reverse.
func _rear_is_clear(dist: float) -> bool:
	if _clock - _last_sense >= sense_interval:
		_sense()
	var need := minf(dist, rear_check_distance) + 1.0
	return _rear > need and _beside_l >= side_margin and _beside_r >= side_margin


func _sense():
	_last_sense = _clock
	var space := v.get_world_3d().direct_space_state
	var origin := v.global_position + Vector3.UP * v.whisker_height
	var f := v._forward()
	_rear = _fan(space, origin, -f, [-35.0, 0.0, 35.0], rear_check_distance + 2.0)
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
