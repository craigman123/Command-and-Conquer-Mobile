extends Node3D

@export var crush_group := "units"
@export_flags_3d_physics var unit_mask := 1   # your tanks' collision layer
@export var shape_scale := 0.8                # shrink the hit area so near misses don't count
@export var bend_angle := 40.0                # degrees the bush leans away from the tank
@export var bend_time := 0.25
@export var recover := true                   # false = stays flattened
@export var recover_delay := 0.01              # seconds after the tank leaves
@export var recover_time := 3.2
@export var debug_print := true
@export var min_radius := 0.6    			  # smallest hit radius, so thin bushes can still be touched
@export var max_size := 10.0     			  # ignore meshes wider than this (ground, whole-pack meshes)

func _ready() -> void:
	var n := 0
	var skipped := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		if _make_bendable(mi):
			n += 1
		else:
			skipped += 1
	if debug_print:
		print("bendables: set up ", n, " bushes, skipped ", skipped)
		var no_bush: int = n + skipped
		LoadStatus.report("Planting %d of %d bushes..." % [n, no_bush])


func _make_bendable(bush: Node3D) -> bool:
	var meshes: Array = bush.find_children("*", "MeshInstance3D", true, false)
	if bush is MeshInstance3D:
		meshes.append(bush)
	if meshes.is_empty():
		return false

	# bounds of this bush in world space
	var box := AABB()
	var first := true
	for mi in meshes:
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	
	if box.size.x > max_size or box.size.z > max_size:
		return false

	var shape := CylinderShape3D.new()
	shape.radius = maxf(min_radius, minf(box.size.x, box.size.z) * 0.5 * shape_scale)
	shape.height = maxf(0.1, box.size.y)
	var cs := CollisionShape3D.new()
	cs.shape = shape

	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = unit_mask
	area.top_level = true            # ignore the model's own rotation and scale
	area.add_child(cs)
	bush.add_child(area)
	area.global_position = box.get_center()

	var c := box.get_center()
	var state := {
		"rest": bush.global_transform,
		"pivot": Vector3(c.x, box.position.y, c.z),   # bend around the base
		"axis": Vector3.RIGHT,
		"angle": 0.0,
		"count": 0,          # how many tanks are on it right now
		"tween": null,
	}
	area.body_entered.connect(_on_enter.bind(bush, state))
	area.body_exited.connect(_on_exit.bind(bush, state))
	return true


func _on_enter(body: Node3D, bush: Node3D, state: Dictionary) -> void:
	if not body.is_in_group(crush_group):
		return
	state.count += 1
	if state.angle < 0.01:   # lean away from where the tank came from
		var away := bush.global_position - body.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		state.axis = Vector3.UP.cross(away).normalized()
	_tween_angle(bush, state, deg_to_rad(bend_angle), bend_time, 0.0, Tween.TRANS_SINE, Tween.EASE_OUT)


func _on_exit(body: Node3D, bush: Node3D, state: Dictionary) -> void:
	if not body.is_in_group(crush_group):
		return
	state.count = maxi(0, state.count - 1)
	if state.count == 0 and recover:
		_tween_angle(bush, state, 0.0, recover_time, recover_delay, Tween.TRANS_ELASTIC, Tween.EASE_OUT)


func _tween_angle(bush: Node3D, state: Dictionary, to: float, time: float, delay: float, trans: int, ease_type: int) -> void:
	if state.tween != null and state.tween.is_valid():
		state.tween.kill()
	var tween := create_tween()
	state.tween = tween
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(func(a: float): _apply(bush, state, a), state.angle, to, time) \
		.set_trans(trans).set_ease(ease_type)


func _apply(bush: Node3D, state: Dictionary, a: float) -> void:
	state.angle = a
	var rot := Basis(state.axis, a)
	bush.global_transform = Transform3D(rot, state.pivot - rot * state.pivot) * state.rest
