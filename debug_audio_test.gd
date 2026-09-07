extends Node

func _ready() -> void:
	print("debug audio start")
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 48000
	stream.buffer_length = 0.1
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.autoplay = true
	player.bus = "Master"
	add_child(player)
	player.play()
	print("playing started")
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()
