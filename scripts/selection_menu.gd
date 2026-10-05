extends Control

func _ready():
	$VBoxContainer/BackButton.pressed.connect(_on_back_pressed)

	$ModeMenu/SkirmishButton.pressed.connect(_on_pressed_skirmish)
	$ModeMenu/SinglePlayButton.pressed.connect(_on_pressed_single)
	$ModeMenu/MultiplayerButton.pressed.connect(_on_pressed_multiplayer)
	$ModeMenu/ModsButton.pressed.connect(_on_pressed_mods)

	TextScrambler.scramble_all($ModeMenu, 0.3, 0.12, UISound.play_hover)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/StartingMenu/starting_menu.tscn")

func _on_pressed_skirmish():
	get_tree().change_scene_to_file("res://scenes/Game/Skirmish/chapter_selection.tscn")

func _on_pressed_single():
	pass

func _on_pressed_multiplayer():
	pass

func _on_pressed_mods():
	pass
