extends Node

var selected: Array = []

const LAYER_WORLD := 1      # bit 1 (layer 1)
const LAYER_VEHICLES := 2   # bit 2 (layer 2)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select_at(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_move_selected(event.position)

func _raycast(screen_pos: Vector2, mask: int = 0xFFFFFFFF) -> Dictionary:
	var cam = get_viewport().get_camera_3d()
	var from = cam.project_ray_origin(screen_pos)
	var to = from + cam.project_ray_normal(screen_pos) * 1000.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	return cam.get_world_3d().direct_space_state.intersect_ray(query)

func _select_at(screen_pos: Vector2):
	for u in selected:
		u.set_selected(false)
	selected.clear()
	# world + vehicles, so a rock in front of a unit still blocks the click
	var hit = _raycast(screen_pos, LAYER_WORLD | LAYER_VEHICLES)
	if hit and hit.collider.is_in_group("player_units"):
		selected.append(hit.collider)
		hit.collider.set_selected(true)

func _move_selected(screen_pos: Vector2):
	# ground only, so clicking on a vehicle still gives a ground position
	var hit = _raycast(screen_pos, LAYER_WORLD)
	if hit:
		for u in selected:
			if is_instance_valid(u):
				u.move_to(hit.position)
