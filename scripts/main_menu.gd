extends Control

func _ready():
	$VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)
	$VBoxContainer/GeneralsButton.pressed.connect(_on_generals_pressed)
	$VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$VBoxContainer/ModsButton.pressed.connect(_on_mods_pressed)
	$VBoxContainer/CreditsButton.pressed.connect(_on_credits_pressed)
	$VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

	TextScrambler.scramble_all($VBoxContainer, 0.3, 0.15, UISound.play_hover)

func _on_play_pressed():
	get_tree().change_scene_to_file("res://scenes/StartingMenu/selection_menu.tscn")

func _on_generals_pressed(): pass
func _on_settings_pressed(): pass
func _on_mods_pressed(): pass
func _on_credits_pressed(): pass

func _on_quit_pressed():
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
