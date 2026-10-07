extends CharacterBody3D

@export var speed := 5.0
@export var turn_speed := 6.0
@export var reach_distance := 1.0  # how close (flat, ignoring height) counts as "arrived"

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var ring: Node3D = $SelectionRing

var nav_ready := false
var path: PackedVector3Array = PackedVector3Array()
var path_index := 0


func _ready():
	set_selected(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	nav_ready = true


func set_selected(value: bool):
	ring.visible = value


func move_to(pos: Vector3):
	if not nav_ready:
		return
	var map = agent.get_navigation_map()
	var closest = NavigationServer3D.map_get_closest_point(map, pos)
	path = NavigationServer3D.map_get_path(map, global_position, closest, true)
	path_index = 0
	print("path size: ", path.size())


func _physics_process(delta):
	# gravity
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 20.0 * delta

	# follow the path using only X and Z, so a navmesh that sits
	# higher or lower than the ground can't freeze the tank
	var moving := false
	while path_index < path.size():
		var target = path[path_index]
		var dir = target - global_position
		dir.y = 0.0

		if dir.length() < reach_distance:
			path_index += 1  # reached this point, go to the next one
			continue

		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), turn_speed * delta)
		moving = true
		break

	if not moving:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()
