extends Node3D

func _ready() -> void:
	# F6 skips the normal loading flow, so quiet the menu stuff ourselves.
	for n in get_tree().root.get_children():
		if n == self or n == get_tree().current_scene:
			continue
		if n.has_method("hide_background"):
			n.hide_background()
		for v in n.find_children("*", "VideoStreamPlayer", true, false):
			v.stop()
		for a in n.find_children("*", "AudioStreamPlayer", true, false):
			a.stop()
		for a in n.find_children("*", "AudioStreamPlayer3D", true, false):
			a.stop()
	# The real map assigns these groups elsewhere; do it by hand for testing.
	await get_tree().process_frame
	var t72 := find_child("T72", true, false)
	var truck := find_child("TechnicalPickup", true, false)
	if t72:
		t72.add_to_group("player_units")
	else:
		push_warning("test_map: T72 not found")
	if truck:
		truck.add_to_group("enemy_units")
	else:
		push_warning("test_map: TechnicalPickup not found")
		
	await get_tree().create_timer(1.5).timeout
	var t := find_child("T72", true, false)
	var agent := t.find_child("NavigationAgent3D", true, false) as NavigationAgent3D
	t.move_to(t.global_position + Vector3(8, 0, -8))
	await get_tree().create_timer(0.5).timeout
	print("AGENT target=", agent.target_position, " reachable=", agent.is_target_reachable(), " finished=", agent.is_navigation_finished(), " next=", agent.get_next_path_position(), " tank=", t.global_position)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
