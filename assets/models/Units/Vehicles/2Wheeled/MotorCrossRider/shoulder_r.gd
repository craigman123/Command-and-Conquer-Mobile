extends Node3D

@export var shoulder: Node3D
@export var aim_rotation_degrees := Vector3(-60, 0, 0)  # tune in the Inspector
@export var aim_time := 0.2
@export var detect_range := 20.0
@export var max_yaw_degrees := 90.0
@export var forward_offset_degrees := 0.0  				# fix if the barrel points off-center

var idle_rotation: Vector3
var aim_rotation: Vector3
var aim_amount := 0.0   								# 0 = idle, 1 = fully aiming
var yaw := 0.0
var aiming := false
var target: Node3D = null
var tween: Tween


func _ready() -> void:
	idle_rotation = shoulder.rotation
	aim_rotation = Vector3(
		deg_to_rad(aim_rotation_degrees.x),
		deg_to_rad(aim_rotation_degrees.y),
		deg_to_rad(aim_rotation_degrees.z)
	)


func _process(delta: float) -> void:
	target = _find_target()
	var want_aim := target != null

	if want_aim != aiming:
		aiming = want_aim
		if tween:
			tween.kill()
		tween = create_tween()
		tween.tween_property(self, "aim_amount", 1.0 if aiming else 0.0, aim_time)

	# Turn toward the enemy, clamped so the body doesn't twist too far
	var target_yaw := 0.0
	if target:
		var local_pos := to_local(target.global_position)
		target_yaw = atan2(-local_pos.x, -local_pos.z) - deg_to_rad(forward_offset_degrees)
		var limit := deg_to_rad(max_yaw_degrees)
		target_yaw = clamp(target_yaw, -limit, limit)
	yaw = lerp_angle(yaw, target_yaw, 10.0 * delta)

	var pose := idle_rotation.lerp(aim_rotation, aim_amount)
	shoulder.basis = Basis(Vector3.UP, yaw * aim_amount) * Basis.from_euler(pose)


func _find_target() -> Node3D:
	var nearest: Node3D = null
	var best := detect_range
	for e in get_tree().get_nodes_in_group("enemy"):
		var d := global_position.distance_to(e.global_position)
		if d < best:
			best = d
			nearest = e
	return nearest
