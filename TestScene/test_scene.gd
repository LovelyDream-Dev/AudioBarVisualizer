extends Node2D

@export var song:AudioStreamPlayer

var songPosition:float = 0.0
var hasPlayed:bool

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		if song.playing:
			pause()
		else:
			play()

func play():
	song.play(songPosition)

func pause():
	songPosition = song.get_playback_position()
	song.stop()
