extends Node

const HOVER_STREAM := preload("res://assets/sounds/hover/menu_hover.mp3")
const SELECT_STREAM := preload("res://assets/sounds/select/menu_select.mp3")

const HOVER_DB := 2.0
const SELECT_DB := 2.0

var hover_player := AudioStreamPlayer.new()
var select_player := AudioStreamPlayer.new()

func _ready():
	hover_player.stream = HOVER_STREAM
	hover_player.volume_db = HOVER_DB
	select_player.stream = SELECT_STREAM
	select_player.volume_db = SELECT_DB
	add_child(hover_player)
	add_child(select_player)

	# every Button that ever enters the game gets sounds automatically
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
	if node is Button and not node.is_in_group("no_ui_sound"):
		node.mouse_entered.connect(play_hover)
		node.pressed.connect(play_select)

func play_hover():
	hover_player.play()

func play_select():
	select_player.play()
