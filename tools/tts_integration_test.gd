extends Node

# Simple integration test for companion_tts:
# - Calls HabiBackend.companion_tts with a short test phrase and optional gendered voiceId
# - Logs the callback payload, saves audio to user://test_tts.wav, and attempts playback
# - Logs playback start/finish and notifies CharacterAnimationManager if present

@export var test_text: String = "Hello! This is an integration test for TTS."
@export var prefer_gender: String = "" # "male" or "female" or empty to use backend default

var _player: AudioStreamPlayer

func _ready():
	call_deferred("_run_test")

func _run_test() -> void:
	print("[TTS Test] Starting companion_tts integration test")
	var backend = null
	if Engine.has_singleton("HabiBackend"):
		backend = Engine.get_singleton("HabiBackend")
	elif get_tree().root.has_node("HabiBackend"):
		backend = get_tree().root.get_node("HabiBackend")
	if backend == null:
		print("[TTS Test] HabiBackend not found. Make sure it's added as an AutoLoad named 'HabiBackend'.")
		return

	# Determine voice id from root meta if prefer_gender set
	var voice_id: String = ""
	var root = get_tree().root
	if prefer_gender.strip_edges() != "" and root != null:
		var gender = prefer_gender.strip_edges().to_lower()
		if gender.find("female") != -1 or gender.find("girl") != -1:
			voice_id = str(root.get_meta("voice_id_female", "")).strip_edges()
		elif gender.find("male") != -1 or gender.find("boy") != -1:
			voice_id = str(root.get_meta("voice_id_male", "")).strip_edges()

	print("[TTS Test] Using voice_id='" + voice_id + "'")

	# Notify CharacterAnimationManager (if present) that AI is about to speak
	_notify_character_animation_local("ai_started_talking")

	backend.companion_tts(test_text, voice_id, Callable(self, "_on_tts_callback"))

func _on_tts_callback(success: bool, payload: Variant) -> void:
	print("[TTS Test] companion_tts callback: success=", success)
	if not success:
		print("[TTS Test] TTS failed: ", payload)
		_notify_character_animation_local("ai_stopped_talking")
		return

	var audio_bytes: PackedByteArray = PackedByteArray()
	var content_type: String = "audio/wav"

	if payload is Dictionary:
		if payload.has("bytes") and payload["bytes"] is PackedByteArray:
			audio_bytes = payload["bytes"]
			content_type = str(payload.get("content_type", content_type))
		elif payload.has("bytes_base64"):
			audio_bytes = Marshalls.base64_to_raw(str(payload["bytes_base64"]))
			content_type = str(payload.get("content_type", content_type))
		elif payload.has("text"):
			print("[TTS Test] Received text response instead of audio: ", payload["text"])
			_notify_character_animation_local("ai_stopped_talking")
			return
	else:
		print("[TTS Test] Unexpected payload type: ", typeof(payload))
		_notify_character_animation_local("ai_stopped_talking")
		return

	print("[TTS Test] Received audio bytes length=", audio_bytes.size(), " content_type=", content_type)

	# Save to user:// for manual inspection
	var path = "user://test_tts.wav"
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(audio_bytes)
		f.close()
		print("[TTS Test] Saved audio to ", path)
	else:
		print("[TTS Test] Failed to open file for writing: ", path)

	# Play the audio via AudioStreamPlayer
	_play_audio_bytes_local(audio_bytes, content_type)

func _play_audio_bytes_local(bytes: PackedByteArray, content_type: String) -> void:
	if _player == null:
		_player = AudioStreamPlayer.new()
		add_child(_player)

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

	_player.stream = stream
	if not _player.finished.is_connected(Callable(self, "_on_playback_finished")):
		_player.finished.connect(Callable(self, "_on_playback_finished"))
	_player.play()
	print("[TTS Test] Playback started")

func _on_playback_finished() -> void:
	print("[TTS Test] Playback finished")
	_notify_character_animation_local("ai_stopped_talking")

func _notify_character_animation_local(event: String) -> void:
	# Try to find CharacterAnimationManager in the current scene and call method if available
	var cam = null
	if get_tree().root.has_node("CharacterAnimationManager"):
		cam = get_tree().root.get_node("CharacterAnimationManager")
	elif has_node("CharacterAnimationManager"):
		cam = get_node("CharacterAnimationManager")
	elif Engine.has_singleton("CharacterAnimationManager"):
		cam = Engine.get_singleton("CharacterAnimationManager")

	if cam != null and cam.has_method("on_" + event):
		print("[TTS Test] Notifying CharacterAnimationManager: ", event)
		cam.call("on_" + event)
	else:
		print("[TTS Test] CharacterAnimationManager not found or method missing: on_" + event)

func set_prefer_gender(g: String) -> void:
	prefer_gender = g
