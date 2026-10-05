extends CanvasLayer

@onready var intro_video: VideoStreamPlayer = $VideoContainer/IntroVideo
@onready var loop_video: VideoStreamPlayer = $VideoContainer/LoopVideo

func _ready():
	intro_video.finished.connect(_on_intro_finished)

func _on_intro_finished():
	loop_video.show()
	loop_video.play()
	intro_video.hide()

func hide_background():
	visible = false
	intro_video.paused = true
	loop_video.paused = true

func show_background():
	visible = true
	intro_video.paused = false
	loop_video.paused = false
