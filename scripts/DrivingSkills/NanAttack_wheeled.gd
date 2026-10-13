extends Node
class_name ConvoyDriving

enum Mode { GO, WAIT_ESCORT, WAIT_THREAT, FLEE }

@export var double_order_forces := true   # order again while it waits = forced go
@export var force_window := 3.0  

var _forced := true
var _next_forced := false
var _last_order_time := -100.0

# ---------- STEERING (wheeled: it can only turn while rolling) ----------
@export var turn_speed := 2.0               # radians per second at full rolling speed
@export var min_roll_factor := 0.3          # fraction of top speed needed for full turning

# ---------- CONVOY RULES ----------
@export var lead_margin := 4.0              # truck must be this much farther from the goal than the lead escort
@export var short_hop_distance := 8.0       # closer than this to the goal: no escort needed (final approach, stepping aside)
@export var wait_without_escort := true     # no escort alive: true = stand still, false = drive alone

# ---------- THREATS ----------
@export var threat_range := 35.0            # enemy this close and on our route: stop and wait
@export var flee_range := 25.0              # enemy this close: back away from it
@export var resume_delay := 1.5             # calm seconds required before moving again

@export var think_interval := 0.2           # how often the decisions are re-made
@export var debug_print := false            # prints every mode change

var v: VehicleBase
var mode := Mode.GO
var _think := 0.0
var _calm := 0.0
var _flee_dir := Vector3.ZERO
var _flee_point := Vector3.ZERO

func setup(vehicle: VehicleBase):
	v = vehicle
	_think = randf() * think_interval      # three trucks shouldn't all think on the same frame


func on_new_order():
	var now := Time.get_ticks_msec() / 1000.0
	var repeated := double_order_forces and mode != Mode.GO and (now - _last_order_time) < force_window
	_last_order_time = now
	_forced = _forced or _next_forced or repeated    # once forced, stays forced until it arrives
	_next_forced = false
	_calm = 0.0
	_think = 0.0
	_set_mode(Mode.GO, "new order" + (" (FORCED)" if _forced else ""))
	
func force_move_to(pos: Vector3):
	_next_forced = true
	v.move_to(pos)
	_next_forced = false


func drive(delta: float):
	if v == null:
		return
	
	if _forced and v.path_index >= v.path.size():
		_forced = false

	_think -= delta
	if _think <= 0.0:
		_think = think_interval
		_decide()

	var target_speed := 0.0

	if mode == Mode.FLEE:
		v.reversing = false
		v._reset_force()
		var to_point := _flee_point - v.global_position
		to_point.y = 0.0
		if to_point.length() > 2.0:
			var avoid: Array = v._avoid_obstacles()
			var ang: float = v._forward().signed_angle_to(to_point.normalized(), Vector3.UP) + float(avoid[0])
			_turn(ang, delta)
			target_speed = v.get_speed() * float(avoid[1]) * _turn_slowdown(ang)
	elif mode != Mode.GO or not v.has_target:
		# standing still on purpose: keep "force through" from kicking in
		v.reversing = false
		v._reset_force()
	else:
		target_speed = _follow_path(delta)
	if target_speed > 0.0 and not _ground_ahead():
		target_speed = 0.0
	v._accelerate(target_speed, delta)
	
func _ground_ahead() -> bool:
	var space := v.get_world_3d().direct_space_state
	var p := v.global_position + v._forward() * 4.0 + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 4.0)
	q.exclude = [v.get_rid()]
	q.collision_mask = 1      # world only, the same mask the dust code uses
	return not space.intersect_ray(q).is_empty()

func _follow_path(delta: float) -> float:
	var spd := v.get_speed()
	var target_speed := spd
	if v.is_last_waypoint and v.target_dist < v.slow_down_distance:
		target_speed *= clampf(v.target_dist / v.slow_down_distance, 0.3, 1.0)

	# backing out of a stuck spot
	if v._update_stuck(delta, target_speed):
		v.reversing = true
		return -spd * 0.5
	v.reversing = false

	var avoid: Array = v._avoid_obstacles()
	var ang := v._forward().signed_angle_to(v.target_dir, Vector3.UP)
	ang = ang * (1.0 - float(avoid[2])) + float(avoid[0])
	_turn(ang, delta)
	return target_speed * float(avoid[1]) * _turn_slowdown(ang)


func _turn(ang: float, delta: float):
	var rolling := clampf(absf(v.current_speed) / maxf(v.get_speed() * min_roll_factor, 0.1), 0.0, 1.0)
	var step := turn_speed * rolling * delta
	v.rotate_y(clampf(ang, -step, step))


func _turn_slowdown(ang: float) -> float:
	return clampf(1.0 - absf(ang) / PI * 0.7, 0.3, 1.0)


# ---------- DECISIONS (a few times per second) ----------

func _decide():
	if _forced:
		_set_mode(Mode.GO, "forced order")
		return
	var nearest: Node3D = null
	var nearest_d := threat_range
	for e in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(e) or e.get("dead") == true:
			continue
		var d := v.global_position.distance_to(e.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = e

	if nearest != null:
		_calm = resume_delay
		if nearest_d < flee_range:
			var away := v.global_position - nearest.global_position
			away.y = 0.0
			_flee_dir = away.normalized()
			var map := v.agent.get_navigation_map()
			_flee_point = NavigationServer3D.map_get_closest_point(map, v.global_position + _flee_dir * 15.0)
			_set_mode(Mode.FLEE, "enemy %.0f m away" % nearest_d)
			return
		if v.has_target:
			var to_enemy := nearest.global_position - v.global_position
			to_enemy.y = 0.0
			if to_enemy.normalized().dot(v.target_dir) > 0.2:
				_set_mode(Mode.WAIT_THREAT, "enemy on our route")
				return
	elif _calm > 0.0:
		_calm -= think_interval
		_set_mode(Mode.WAIT_THREAT, "holding after threat")
		return

	if v.has_target and not _escort_ahead():
		_set_mode(Mode.WAIT_ESCORT, "no escort ahead of us")
	else:
		_set_mode(Mode.GO, "clear")


func _escort_ahead() -> bool:
	if v.path.is_empty():
		return true
	var goal := v.path[v.path.size() - 1]
	var my_d := _flat_dist(v.global_position, goal)
	if my_d < short_hop_distance:
		return true

	var found := false
	for u in get_tree().get_nodes_in_group("player_units"):
		if u == v or not is_instance_valid(u) or u.is_in_group("mission_critical"):
			continue
		if u.get("dead") == true:
			continue
		found = true
		if _flat_dist(u.global_position, goal) < my_d - lead_margin:
			return true
	return not found and not wait_without_escort


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _set_mode(m: Mode, why: String):
	if mode != m and debug_print:
		print("[Convoy ", v.name, "] ", Mode.keys()[m], ": ", why)
	mode = m
