extends Node3D

# Right-click your pause scene (canvas_layer.tscn) in the FileSystem panel -> Copy Path, and paste it here
const PAUSE_MENU := preload("res://scenes/Game/PausePanel/canvas_layer.tscn")

func _ready() -> void:
	add_child(PAUSE_MENU.instantiate())
