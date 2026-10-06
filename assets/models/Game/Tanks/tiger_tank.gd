extends CharacterBody3D

@export var speed := 6.0
@export var turn_speed := 6.0

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var ring: Node3D = $SelectionRing

var nav_ready := false

func _ready():
	set_selected(false)
	agent.path_height_offset = 0.5   
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	nav_ready = true

func set_selected(value: bool):
	ring.visible = value

func move_to(pos: Vector3):
	if not nav_ready:
		return
	var map = agent.get_navigation_map()
	agent.target_position = NavigationServer3D.map_get_closest_point(map, pos)
	
func _physics_process(delta):
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 20.0 * delta

	if agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var next = agent.get_next_path_position()
		var dir = next - global_position
		dir.y = 0.0
		if dir.length() > 0.1:
			dir = dir.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), turn_speed * delta)

	move_and_slide()
