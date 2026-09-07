extends Node

signal playback_finished

# AudioManager: centralized audio playback helper for TTS and other byte streams.
# Recommend adding this file as an AutoLoad singleton named `AudioManager`.

var _player: AudioStreamPlayer = null

func _ready():
	# Create a dedicated playback player on ready
	_player = AudioStreamPlayer.new()
	_player.name = "AudioManager_Player"
	_player.bus = "Master"
	_player.autoplay = false
	# Relay finished signal
	_player.finished.connect(Callable(self, "_on_player_finished"))
	add_child(_player)
	print("AudioManager: ready, player created")

func _on_player_finished() -> void:
	print("AudioManager: playback finished")
	emit_signal("playback_finished")

func _ensure_master_unmuted():
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, false)
		AudioServer.set_bus_volume_db(master_index, 0.0)

func play_audio_bytes(bytes: PackedByteArray, content_type: String = "audio/wav") -> void:
	# Ensure master bus is enabled
	_ensure_master_unmuted()
	if _player == null:
		_ready()
	# Build an AudioStream from bytes
	var stream: AudioStream = null
	if content_type.findn("wav") != -1:
		var wav = AudioStreamWAV.load_from_buffer(bytes)
		if wav != null:
			stream = wav
		else:
			var fallback = AudioStreamWAV.new()
			fallback.data = bytes
			fallback.mix_rate = 44100
			fallback.format = AudioStreamWAV.FORMAT_16_BITS
			stream = fallback
	else:
		var mp3 = AudioStreamMP3.new()
		mp3.data = bytes
		stream = mp3

	_player.stop()
	_player.stream = stream
	_player.play()

func stop():
	if _player != null:
		_player.stop()

func set_master_volume_db(db: float) -> void:
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_volume_db(master_index, db)

func is_playing() -> bool:
	return _player != null and _player.playing
