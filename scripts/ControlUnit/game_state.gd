extends Node

var player_faction := "heroes"   # change to "villains" when the player plays the villain
var real_shadows := false

func set_real_shadows(on: bool):
	real_shadows = on
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = on
	for v in get_tree().get_nodes_in_group("vehicles"):
		v.set_blob_shadow(not on)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_K:
		set_real_shadows(not real_shadows)
		
func _ready():
	Engine.max_physics_steps_per_frame = 1.5
