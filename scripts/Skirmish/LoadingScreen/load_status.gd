extends Node

signal message(text: String)

func report(text: String):
	print(text)        # still shows in Output
	message.emit(text)
