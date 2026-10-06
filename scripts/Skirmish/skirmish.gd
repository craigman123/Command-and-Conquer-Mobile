extends Control

const DATA_PATH := "res://data/skirmish.json"
const FALLBACK_IMAGE := "res://assets/sprites/SkirmishChapterImages/FallbackImages/fallback.jpg"
const MIN_LOADING_MS := 1500

var loading_path := ""
var load_start_ms := 0
var chapters := []
var selected_episode := {}

var chapter_group := ButtonGroup.new()
var episode_group := ButtonGroup.new()
var selected_chapter := -1

func _ready():
	$VBoxContainer/BackButton.pressed.connect(_on_back_pressed)
	%PlayButton.pressed.connect(_on_play_pressed)
	_load_data()
	_build_chapter_buttons()
	hide_all()
	
func _style_panels():
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.4, 0.4, 0.4, 0.5) 
	sb.set_content_margin_all(8)
	for node in [$ChaptersContainer, $EpisodesController, $PanelContainer]:
		node.add_theme_stylebox_override("panel", sb)
	
func _make_button(text: String, group: ButtonGroup = null) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(160, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if group:
		btn.toggle_mode = true
		btn.button_group = group
		var sel = StyleBoxFlat.new()
		sel.bg_color = Color(0.35, 0.45, 0.3, 1)
		sel.set_border_width_all(2)
		sel.border_color = Color(0.8, 0.85, 0.7, 1)
		btn.add_theme_stylebox_override("pressed", sel)
	return btn

func _load_data():
	var file = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("Missing " + DATA_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		chapters = parsed.get("chapters", [])
	else:
		push_warning("skirmish.json is not valid JSON")


func _clear(container: Node):
	for child in container.get_children():
		child.queue_free()

func _build_chapter_buttons():
	var box = $ChaptersContainer/Chapters
	_clear(box)
	for i in chapters.size():
		var btn = _make_button(chapters[i].get("name", "Chapter %d" % (i + 1)), chapter_group)
		btn.pressed.connect(_on_chapter_pressed.bind(i))
		if i > 0 and not Progress.is_chapter_done(chapters[i - 1]):
			btn.disabled = true
			btn.tooltip_text = "Complete %s first" % chapters[i - 1].get("name", "the previous chapter")
		box.add_child(btn)

func hide_all():
	_clear($EpisodesController/Episodes)
	selected_episode = {}
	_update_play_button()
	%SummaryText.text = ""
	$ChapterImage.hide()
	$ChapterImage/ColorRect.hide()

func _update_play_button():
	%PlayButton.show()
	if selected_episode.is_empty():
		%PlayButton.text = "Select an episode"
		%PlayButton.disabled = true
		return
	var map_path = selected_episode.get("map", "")
	var ok = map_path != "" and ResourceLoader.exists(map_path)
	%PlayButton.text = "Deploy" if ok else "Deploy (no map yet)"
	%PlayButton.disabled = not ok

func _on_chapter_pressed(index: int):
	if index == selected_chapter:
		return
	selected_chapter = index
	episode_group = ButtonGroup.new()
	hide_all()
	var chapter = chapters[index]
	var episodes = chapter.get("episodes", [])
	for i in episodes.size():
		var ep = episodes[i]
		var btn = _make_button("Episode %d: %s" % [i + 1, ep.get("name", "Untitled")], episode_group)
		btn.disabled = ep.get("locked", false)
		btn.pressed.connect(_on_episode_pressed.bind(index, i))
		$EpisodesController/Episodes.add_child(btn)
	show_chapter_image(chapter.get("image", ""))


func _on_episode_pressed(chapter_index: int, ep_index: int):
	var chapter = chapters[chapter_index]
	var ep = chapter["episodes"][ep_index]
	selected_episode = ep

	%SummaryText.text = "[b]%s[/b]\n\n%s" % [
		ep.get("name", "Untitled"),
		ep.get("summary", "No summary available yet.")
	]

	var img = ep.get("image", "")
	show_chapter_image(img if img != "" else chapter.get("image", ""))

	_update_play_button()


func _on_play_pressed():
	var map_path = selected_episode.get("map", "")
	if map_path == "" or not ResourceLoader.exists(map_path):
		return
	var session = get_node_or_null("/root/GameSession")
	if session:
		session.selected_episode = selected_episode
		session.selected_map = map_path
	VideoBackground.hide_background()
	MusicManager.stop_music(1.0)
	SceneLoader.next_scene = map_path
	get_tree().change_scene_to_file("res://scenes/Game/loading_screen.tscn")


func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/StartingMenu/selection_menu.tscn")


func show_chapter_image(path: String):
	$ChapterImage.texture = null
	$ChapterImage.show()
	$ChapterImage/LoadingVideo.show()
	$ChapterImage/LoadingVideo.play()
	load_start_ms = Time.get_ticks_msec()

	if not ResourceLoader.exists(path):
		path = FALLBACK_IMAGE

	loading_path = path
	ResourceLoader.load_threaded_request(path)


func _process(_delta):
	if loading_path == "":
		return

	var status = ResourceLoader.load_threaded_get_status(loading_path)
	var elapsed = Time.get_ticks_msec() - load_start_ms

	if status == ResourceLoader.THREAD_LOAD_LOADED and elapsed >= MIN_LOADING_MS:
		_finish_loading(ResourceLoader.load_threaded_get(loading_path))
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		if loading_path != FALLBACK_IMAGE:
			loading_path = FALLBACK_IMAGE
			ResourceLoader.load_threaded_request(FALLBACK_IMAGE)
		else:
			_finish_loading(null)


func _finish_loading(tex: Texture2D):
	$ChapterImage.texture = tex
	$ChapterImage/LoadingVideo.stop()
	$ChapterImage/LoadingVideo.hide()
	loading_path = ""
