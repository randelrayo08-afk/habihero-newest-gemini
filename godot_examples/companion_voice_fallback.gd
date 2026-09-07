extends Control

@export var companion_name: String = "Habi Friend"
@export var voice_id: String = ""

var _recording_active: bool = false
var _record_player: AudioStreamPlayer
var _playback_player: AudioStreamPlayer
var _record_effect: AudioEffectRecord
var _backend: Node = null
var _input_active: bool = false

@onready var _record_button: Button = $VBoxContainer/RecordButton
@onready var _status_label: Label = $VBoxContainer/StatusLabel
@onready var _transcript_label: Label = $VBoxContainer/TranscriptLabel
@onready var _reply_label: Label = $VBoxContainer/ReplyLabel

func _ready() -> void:
	_set_status("Ready. Press Record, speak, then press Stop to send.")
	_backend = _resolve_backend()
	_setup_players()
	_record_button.button_up.connect(Callable(self, "_on_record_button_pressed"))

func _setup_players() -> void:
	_record_player = AudioStreamPlayer.new()
	_record_player.name = "RecordPlayer"
	_record_player.stream = AudioStreamMicrophone.new()
	_record_player.volume_db = -80.0
	_record_player.bus = "Master"
	_record_player.autoplay = false
	add_child(_record_player)

	_playback_player = AudioStreamPlayer.new()
	_playback_player.name = "PlaybackPlayer"
	_playback_player.bus = "Master"
	_playback_player.autoplay = false
	_playback_player.volume_db = 0.0
	add_child(_playback_player)

func _resolve_backend() -> Node:
	if Engine.has_singleton("HabiBackend"):
		return Engine.get_singleton("HabiBackend")
	var backend = get_node_or_null("/root/HabiBackend")
	return backend

func _setup_record_effect() -> void:
	if _record_effect != null:
		return
	_record_effect = AudioEffectRecord.new()
	var bus_index = AudioServer.get_bus_index("Master")
	if bus_index < 0:
		bus_index = 0
	AudioServer.add_bus_effect(bus_index, _record_effect)
	AudioServer.set_bus_mute(bus_index, false)

func _on_record_button_pressed() -> void:
	if not _recording_active:
		_start_recording()
	else:
		_stop_recording_and_send()

func _start_recording() -> void:
	_setup_record_effect()
	if _record_effect == null:
		_set_status("Recording unavailable: no record effect")
		return
	if not _input_active:
		if AudioServer.has_method("set_input_device_active"):
			AudioServer.set_input_device_active(true)
			_input_active = true
	_record_player.play()
	_record_effect.set_recording_active(true)
	_recording_active = true
	_record_button.text = "Stop Recording"
	_set_status("Recording... speak now")

func _stop_recording_and_send() -> void:
	if _record_effect == null:
		return
	_record_effect.set_recording_active(false)
	_record_player.stop()
	_recording_active = false
	_record_button.text = "Start Recording"
	_set_status("Recording stopped. Sending to backend...")

	var recording = _record_effect.get_recording()
	if recording == null:
		_set_status("No recording captured")
		return

	if recording is AudioStreamWAV:
		var wav: AudioStreamWAV = recording
		if wav.data.size() == 0:
			_set_status("Captured WAV is empty")
			return
		_send_audio_to_backend(wav.data, "audio/wav")
	else:
		_set_status("Unexpected recording format: %s" % recording.get_class())

func _send_audio_to_backend(audio_bytes: PackedByteArray, content_type: String) -> void:
	if _backend == null:
		_set_status("HabiBackend unavailable")
		return
	var audio_base64: String = Marshalls.raw_to_base64(audio_bytes)
	_backend.companion_voice(audio_base64, content_type, voice_id, companion_name, Callable(self, "_on_companion_voice_result"))
	_set_status("Waiting for backend response...")

func _on_companion_voice_result(success: bool, payload: Variant) -> void:
	if not success:
		_set_status("Backend companion voice failed")
		print("companion_voice failed:", payload)
		return

	if not (payload is Dictionary):
		_set_status("Unexpected backend response")
		print("Unexpected payload:", payload)
		return

	var transcript: String = str(payload.get("transcript", ""))
	var reply: String = str(payload.get("reply", ""))
	var audio_base64: String = str(payload.get("audioBase64", ""))
	var content_type: String = str(payload.get("audioContentType", "audio/wav"))

	_transcript_label.text = "Transcript: %s" % transcript
	_reply_label.text = "Reply: %s" % reply

	if audio_base64.strip_edges().is_empty():
		_set_status("Backend returned no audio")
		return

	var audio_bytes: PackedByteArray = Marshalls.base64_to_raw(audio_base64)
	_play_audio_bytes(audio_bytes, content_type)
	_set_status("Reply playing")

func _play_audio_bytes(bytes: PackedByteArray, content_type: String) -> void:
	var stream: AudioStream = null
	if content_type.findn("wav") != -1:
		var wav: AudioStreamWAV = AudioStreamWAV.load_from_buffer(bytes)
		if wav != null:
			stream = wav
		else:
			var fallback_wav = AudioStreamWAV.new()
			fallback_wav.data = bytes
			fallback_wav.mix_rate = 44100
			fallback_wav.format = AudioStreamWAV.FORMAT_16_BITS
			stream = fallback_wav
	else:
		var mp3 = AudioStreamMP3.new()
		mp3.data = bytes
		stream = mp3
	if stream == null:
		_set_status("Unsupported audio format: %s" % content_type)
		return
	_playback_player.stream = stream
	_playback_player.play()

func _set_status(message: String) -> void:
	_status_label.text = message
