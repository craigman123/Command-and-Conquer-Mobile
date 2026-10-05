class_name Progress

const PATH := "user://progress.cfg"

static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # fine if the file doesn't exist yet
	return cfg

static func is_episode_done(chapter_id: String, ep_index: int) -> bool:
	return _load().get_value("done", "%s_%d" % [chapter_id, ep_index], false)

static func mark_episode_done(chapter_id: String, ep_index: int) -> void:
	var cfg := _load()
	cfg.set_value("done", "%s_%d" % [chapter_id, ep_index], true)
	cfg.save(PATH)

static func is_chapter_done(chapter: Dictionary) -> bool:
	var episodes: Array = chapter.get("episodes", [])
	if episodes.is_empty():
		return false
	for i in episodes.size():
		if not is_episode_done(chapter.get("id", ""), i):
			return false
	return true
