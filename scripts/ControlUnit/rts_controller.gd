extends Node

var selected: Array = []

const LAYER_WORLD := 1      # bit 1 (layer 1)
const LAYER_VEHICLES := 2   # bit 2 (layer 2)

const DRAG_THRESHOLD := 8.0
var dragging := false
var drag_start := Vector2.ZERO
var box: Panel

func _ready():
	var layer := CanvasLayer.new()
	add_child(layer)
	box = Panel.new()
	box.visible = false
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 1.0, 0.302, 0.047)
	sb.border_color = Color(0.2, 1.0, 0.302, 0.447)
	sb.set_border_width_all(2)
	box.add_theme_stylebox_override("panel", sb)
	layer.add_child(box)

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_start = event.position
			elif dragging:
				dragging = false
				box.visible = false
				if event.position.distance_to(drag_start) < DRAG_THRESHOLD:
					_select_at(event.position)
				else:
					_select_in_rect(Rect2(drag_start, Vector2.ZERO).expand(event.position))
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_move_selected(event.position)

	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(drag_start) >= DRAG_THRESHOLD:
			var r := Rect2(drag_start, Vector2.ZERO).expand(event.position)
			box.position = r.position
			box.size = r.size
			box.visible = true
			
func _select_in_rect(rect: Rect2):
	for u in selected:
		if is_instance_valid(u):
			u.set_selected(false)
	selected.clear()

	var cam := get_viewport().get_camera_3d()
	for u in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(u) or u.dead:
			continue
		if cam.is_position_behind(u.global_position):
			continue
		if rect.has_point(cam.unproject_position(u.global_position)):
			u.set_selected(true)
			selected.append(u)

func _raycast(screen_pos: Vector2, mask: int = 0xFFFFFFFF) -> Dictionary:
	var cam = get_viewport().get_camera_3d()
	var from = cam.project_ray_origin(screen_pos)
	var to = from + cam.project_ray_normal(screen_pos) * 1000.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	return cam.get_world_3d().direct_space_state.intersect_ray(query)

func _select_at(screen_pos: Vector2):
	for u in selected:
		if is_instance_valid(u):
			u.set_selected(false)
	selected.clear()
	# world + vehicles, so a rock in front of a unit still blocks the click
	var hit = _raycast(screen_pos, LAYER_WORLD | LAYER_VEHICLES)
	if hit and hit.collider.is_in_group("player_units"):
		selected.append(hit.collider)
		hit.collider.set_selected(true)

func _move_selected(screen_pos: Vector2):
	for i in range(selected.size() - 1, -1, -1):
		if not is_instance_valid(selected[i]) or selected[i].dead:
			selected.remove_at(i)

	var hit = _raycast(screen_pos, LAYER_WORLD)
	if hit:
		var n := selected.size()
		var cols := ceili(sqrt(n))
		var rows := ceili(n / float(cols))
		var spacing := 4.0
		for i in n:
			var col := i % cols
			var row := floori(i / float(cols))
			var off := Vector3(col - (cols - 1) * 0.5, 0.0, row - (rows - 1) * 0.5) * spacing
			selected[i].move_to(hit.position + off)
