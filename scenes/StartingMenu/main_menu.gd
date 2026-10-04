extends Control

@onready var hover_sound: AudioStreamPlayer = $HoverSound
@onready var select_sound: AudioStreamPlayer = $SelectionSound

func _ready():
	$VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)
	$VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$VBoxContainer/CreditsButton.pressed.connect(_on_credits_pressed)
	$VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

	$VBoxContainer/PlayButton.mouse_entered.connect(play_hover_sound)
	$VBoxContainer/SettingsButton.mouse_entered.connect(play_hover_sound)
	$VBoxContainer/CreditsButton.mouse_entered.connect(play_hover_sound)
	$VBoxContainer/QuitButton.mouse_entered.connect(play_hover_sound)

func play_hover_sound():
	hover_sound.play()

func play_select_sound():
	select_sound.play()

func _on_play_pressed():
	play_select_sound()
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/StartingMenu/selection_menu.tscn")

func _on_settings_pressed():
	play_select_sound()

func _on_credits_pressed():
	play_select_sound()

func _on_quit_pressed():
	play_select_sound()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
