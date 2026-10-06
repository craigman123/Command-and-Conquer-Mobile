extends CanvasLayer

# Right-click chapter_selection.tscn in the FileSystem panel -> Copy Path, and paste it here
const MENU_SCENE := "res://scenes/Game/Skirmish/chapter_selection.tscn"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS  
	hide()                          
	_show_page(%InfoPage)

	%ResumeButton.pressed.connect(_resume)
	%SettingsButton.pressed.connect(func(): _show_page(%SettingsPage))
	%BattleInfoButton.pressed.connect(func(): _show_page(%InfoPage))
	%SurrenderButton.pressed.connect(func(): _show_page(%SurrenderPage))
	
	%NeverButton.pressed.connect(_resume)
	%ConfirmSurrenderButton.pressed.connect(_surrender)

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):  
		if visible:
			_resume()
		else:
			_open()
		get_viewport().set_input_as_handled()

func _open():
	_show_page(%InfoPage)
	show()
	get_tree().paused = true

func _resume():
	hide()
	get_tree().paused = false

func _show_page(page: Control):
	for p in [%InfoPage, %SettingsPage, %SurrenderPage]:
		p.visible = (p == page)

func _surrender():
	get_tree().paused = false
	VideoBackground.show_background()
	MusicManager.play_music("res://assets/music/rock_background_music.mp3")
	get_tree().change_scene_to_file(MENU_SCENE)
