extends CanvasLayer

@export var focus_time := 1.6
@export var blur_time := 1.2

const BLUR_SHADER := preload("res://scenes/Game/GameOver/game_over.gdshader")

func _make_blur() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = BLUR_SHADER
	_blur = ColorRect.new()
	_blur.material = _mat
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_blur)
	move_child(_blur, 0)
	_mat.set_shader_parameter("strength", 1.0)

var _pending := false
var _blur: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_over")
	_make_blur()
	hide()
	$Restart.pressed.connect(_on_restart_pressed)
	$Surrender.pressed.connect(_on_surrender_pressed)



func show_game_over(focus_pos: Vector3 = Vector3.INF) -> void:
	if visible or _pending:
		return
	_pending = true

	if focus_pos != Vector3.INF:
		await _focus_camera(focus_pos)
	else:
		await get_tree().create_timer(1.5).timeout

	var ui: Array[CanvasItem] = []
	for c in get_children():
		if c != _blur and c is CanvasItem:
			c.modulate.a = 0.0
			ui.append(c)

	_mat.set_shader_parameter("strength", 0.0)
	show()

	var tw := create_tween().set_parallel(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	# smooth blur ramp
	tw.tween_property(_mat, "shader_parameter/strength", 1.0, blur_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# UI fades in over the second half of the blur
	for c in ui:
		tw.tween_property(c, "modulate:a", 1.0, blur_time * 0.5) \
			.set_delay(blur_time * 0.5)

	await tw.finished
	get_tree().paused = true


func _focus_camera(pos: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	for n in [cam, cam.get_parent()]:
		if n != null and n.get_script() != null:
			n.set_process(false)
			n.set_physics_process(false)
			n.set_process_input(false)
			n.set_process_unhandled_input(false)

	var center := get_viewport().get_visible_rect().size * 0.5
	var hit = Plane(Vector3.UP, pos.y).intersects_ray(
		cam.project_ray_origin(center), cam.project_ray_normal(center))
	if hit == null:
		return

	var target: Vector3 = cam.global_position + (pos - hit)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cam, "global_position", target, focus_time)
	await tw.finished


func _on_surrender_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
