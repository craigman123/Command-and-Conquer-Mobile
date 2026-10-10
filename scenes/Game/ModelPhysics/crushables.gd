extends Node3D

@export var crush_group := "units"
@export_flags_3d_physics var unit_mask := 1
@export_flags_3d_physics var ground_mask := 1
@export var shape_scale := 0.7
@export var fall_time := 0.6
@export var fall_angle := 85.0
@export var sink_depth := 0.1
@export var remove_after := 3.0
@export var debug_print := true
@export var min_trigger_size := 1.0

func _ready() -> void:
	var n := 0
	for holder in get_children():
		if holder is Node3D:
			for cactus in _find_cacti(holder):
				if _make_crushable(cactus):
					n += 1
	if debug_print:
		print("crushables: set up ", n, " cacti")
		LoadStatus.report("Planting %d cacti's..." % n)


func _find_cacti(holder: Node3D) -> Array:
	var found: Array = []
	for node in holder.find_children("cactus_*", "Node3D", true, false):
		if String(node.name).substr(7).is_valid_int():
			found.append(node)
	if found.is_empty():
		found.append(holder)
	return found


func _world_box(cactus: Node3D) -> AABB:
	var meshes: Array = cactus.find_children("*", "MeshInstance3D", true, false)
	if cactus is MeshInstance3D:
		meshes.append(cactus)
	var box := AABB()
	var first := true
	for mi in meshes:
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _ground_y(box: AABB, body: Node3D) -> float:
	var c := box.get_center()
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(c.x, box.end.y + 5.0, c.z),
		Vector3(c.x, box.position.y - 5.0, c.z),
		ground_mask)
	q.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else box.position.y


func _make_crushable(cactus: Node3D) -> bool:
	var box := _world_box(cactus)
	if box.size == Vector3.ZERO:
		return false

	var shape := BoxShape3D.new()
	shape.size = Vector3(
		maxf(box.size.x * shape_scale, min_trigger_size),
		maxf(box.size.y, 0.1),
		maxf(box.size.z * shape_scale, min_trigger_size))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	
	for co in cactus.find_children("*", "CollisionObject3D", true, false):
		co.queue_free()

	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = unit_mask
	area.top_level = true
	area.add_child(cs)
	cactus.add_child(area)
	area.global_position = box.get_center()
	area.body_entered.connect(_on_body_entered.bind(cactus, area))
	return true


func _on_body_entered(body: Node3D, cactus: Node3D, area: Area3D) -> void:
	if not body.is_in_group(crush_group):
		return
	if cactus.has_meta("crushed"):
		return
	cactus.set_meta("crushed", true)
	area.set_deferred("monitoring", false)

	var box := _world_box(cactus)
	var c := box.get_center()
	var away := Vector3(c.x - body.global_position.x, 0.0, c.z - body.global_position.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var axis := Vector3.UP.cross(away).normalized()
	var pivot := Vector3(c.x, _ground_y(box, body), c.z)
	var start := cactus.global_transform
	var target := deg_to_rad(fall_angle)

	var tween := create_tween()
	tween.tween_method(func(a: float):
		var rot := Basis(axis, a)
		var xf := Transform3D(rot, pivot - rot * pivot) * start
		xf.origin.y -= sink_depth * (a / target)
		cactus.global_transform = xf,
		0.0, target, fall_time
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	if remove_after > 0.0:
		tween.tween_interval(remove_after)
		tween.tween_property(cactus, "global_position:y", -1.5, 0.5).as_relative()
		tween.tween_callback(cactus.queue_free)
