extends Node

const GLYPHS := "!@#$%^&*()+=<>?/0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

func random_chars(count: int) -> String:
	var s := ""
	for i in count:
		s += GLYPHS[randi() % GLYPHS.length()]
	return s

func scramble(button: Button, duration := 0.3, delay := 0.0, on_tick := Callable()) -> void:
	# remember the real text so scrambling twice can't overwrite it
	var final_text: String = button.get_meta("final_text", button.text)
	button.set_meta("final_text", final_text)
	button.text = random_chars(final_text.length())
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var elapsed := 0.0
	var step := 0.02
	var last_revealed := 0
	while elapsed < duration:
		if not is_instance_valid(button) or not button.is_inside_tree():
			return
		var revealed := int(elapsed / duration * final_text.length())
		button.text = final_text.substr(0, revealed) + random_chars(final_text.length() - revealed)
		if revealed > last_revealed and on_tick.is_valid():
			on_tick.call()
		last_revealed = revealed
		await get_tree().create_timer(step).timeout
		elapsed += step
	if is_instance_valid(button):
		button.text = final_text

func scramble_all(container: Node, duration := 0.3, stagger := 0.15, on_tick := Callable()) -> void:
	var i := 0
	for child in container.get_children():
		if child is Button:
			scramble(child, duration, i * stagger, on_tick)
			i += 1
