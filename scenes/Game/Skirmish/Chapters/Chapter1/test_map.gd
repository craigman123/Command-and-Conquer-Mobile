extends Node3D

const PAUSE_MENU := preload("res://scenes/Game/PausePanel/canvas_layer.tscn")

func _ready() -> void:
	var target: String = SceneLoader.next_scene
	if target == "":
		push_warning("No scene to load")
		get_tree().change_scene_to_file.call_deferred("res://scenes/StartingMenu/404.tscn")
		return

	Engine.max_fps = 30
	add_child(PAUSE_MENU.instantiate())
