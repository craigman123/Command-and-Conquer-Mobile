extends Node

const TARGET_DB := -8.0
const SILENT_DB := -60.0

var player := AudioStreamPlayer.new()
var current_path := ""
var tween: Tween

func _ready():
	add_child(player)
	player.finished.connect(player.play)
	play_music("res://assets/music/rock_background_music.mp3", 3.0)

func play_music(path: String, fade_in_time := 2.0):
	if path == current_path and player.playing:
		return # already playing, don't restart
	current_path = path
	player.stream = load(path)
	player.volume_db = SILENT_DB
	player.play()
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(player, "volume_db", TARGET_DB, fade_in_time)

func stop_music(fade_time := 1.0):
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(player, "volume_db", SILENT_DB, fade_time)
	await tween.finished
	player.stop()
	current_path = ""
