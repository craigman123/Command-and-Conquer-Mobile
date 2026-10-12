extends Node3D

@export var turn_speed := 5.0
@export var model_forward_offset := 0.0
@export var scan_range := 90.0          # how far the turret "sees", independent of the vehicle
@export var return_to_rest := true

var vehicle: VehicleBase = null
var _rest_yaw := 0.0
var _scan_timer := 0.0
var _scan_target: Node3D = null

func _ready() -> void:
	_rest_yaw = rotation.y
	var n := get_parent()
	while n != null and not (n is VehicleBase):
		n = n.get_parent()
	vehicle = n as VehicleBase
	if vehicle == null:
		push_warning("Turret: no VehicleBase parent found")

func _physics_process(delta: float) -> void:
	if vehicle == null or vehicle.dead:
		return

	var t: Node3D = vehicle.combat_target
	if not is_instance_valid(t) or t.dead:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = 0.5
			_scan_target = _find_far_enemy()
		t = _scan_target

	if is_instance_valid(t) and not t.dead:
		var dir := t.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.1:
			var parent := get_parent() as Node3D
			# turn the world direction into the parent's local space, so tilt and base rotation don't matter
			var local_dir := parent.global_transform.basis.orthonormalized().inverse() * dir
			var desired := atan2(-local_dir.x, -local_dir.z) + model_forward_offset
			var diff := angle_difference(rotation.y, desired)   # always the shortest way round
			var step := turn_speed * delta
			rotation.y += clampf(diff, -step, step)
	elif return_to_rest:
		var diff := angle_difference(rotation.y, _rest_yaw)
		var step := turn_speed * delta
		rotation.y += clampf(diff, -step, step)

func _find_far_enemy() -> Node3D:
	var best: Node3D = null
	var best_dist := scan_range
	for u in get_tree().get_nodes_in_group("units"):
		if u == vehicle or u.faction == vehicle.faction:
			continue
		var d := global_position.distance_to(u.global_position)
		if d < best_dist:
			best_dist = d
			best = u
	return best
