extends Node
# Voice Companion Handler - REST API Version (No LiveKit required)
# Uses /api/companion/voice, /api/companion/chat, /api/companion/tts, /api/companion/stt endpoints

signal voice_started()
signal voice_stopped()
signal transcription_received(text: String)
signal reply_received(text: String, audio_data: PackedByteArray)
signal error_occurred(error_message: String)
signal processing_started()
signal processing_finished()

var _backend: Node = null
var _auth_manager: Node = null
var _is_recording: bool = false
var _is_processing: bool = false
var _companion_name: String = "Habi Friend"
var _voice_id: String = "alloy"  # Default ElevenLabs voice ID

# Audio recording
var _audio_capture: AudioStreamMicrophone = null
var _audio_player: AudioStreamPlayer = null
var _recording_buffer: PackedVector2Array = PackedVector2Array()
var _sample_rate: int = 16000

# HTTP requests
var _voice_request: HTTPRequest = null
var _stt_request: HTTPRequest = null
var _tts_request: HTTPRequest = null
var _chat_request: HTTPRequest = null

func _ready() -> void:
	_backend = _resolve_backend()
	_auth_manager = _resolve_auth_manager()
	
	# Setup HTTP request nodes
	_voice_request = HTTPRequest.new()
	add_child(_voice_request)
	_voice_request.request_completed.connect(_on_voice_request_completed)
	
	_stt_request = HTTPRequest.new()
	add_child(_stt_request)
	_stt_request.request_completed.connect(_on_stt_request_completed)
	
	_tts_request = HTTPRequest.new()
	add_child(_tts_request)
	_tts_request.request_completed.connect(_on_tts_request_completed)
	
	_chat_request = HTTPRequest.new()
	add_child(_chat_request)
	_chat_request.request_completed.connect(_on_chat_request_completed)
	
	# Setup audio player
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "VoiceCompanionPlayer"
	add_child(_audio_player)
	
	# Setup microphone capture
	_audio_capture = AudioStreamMicrophone.new()
	_audio_capture.sample_rate = _sample_rate
	
	print("VoiceCompanionRest: initialized with REST API endpoints")

	# Determine initial voice id from project/root meta (gender-aware)
	var root = null
	if get_tree() != null:
		root = get_tree().root
	if root != null:
		var selected_gender: String = ""
		if root.has_meta("selected_gender"):
			selected_gender = str(root.get_meta("selected_gender")).to_lower().strip_edges()
		var female_voice: String = ""
		var male_voice: String = ""
		if root.has_meta("voice_id_female"):
			female_voice = str(root.get_meta("voice_id_female")).strip_edges()
		if root.has_meta("voice_id_male"):
			male_voice = str(root.get_meta("voice_id_male")).strip_edges()

		if selected_gender.find("girl") != -1 or selected_gender.find("female") != -1:
			if female_voice != "":
				_voice_id = female_voice
		elif selected_gender.find("boy") != -1 or selected_gender.find("male") != -1:
			if male_voice != "":
				_voice_id = male_voice

func _resolve_backend() -> Node:
	"""Get the HabiBackend singleton"""
	if get_tree() != null and get_tree().root != null:
		var backend = get_tree().root.get_node_or_null("HabiBackend")
		if backend != null:
			return backend
	return null

func _resolve_auth_manager() -> Node:
	"""Get the FirebaseAuthManager singleton"""
	if get_tree() != null and get_tree().root != null:
		var auth = get_tree().root.get_node_or_null("FirebaseAuthManager")
		if auth != null:
			return auth
	return null

func get_backend_url() -> String:
	"""Get the backend URL"""
	if _backend != null and _backend.has_method("get_backend_url"):
		return str(_backend.call("get_backend_url"))
	return "http://localhost:3000"

func get_auth_headers() -> Dictionary:
	"""Get authorization headers"""
	var headers = {}
	if _backend != null and _backend.has_method("get_auth_headers"):
		headers = _backend.call("get_auth_headers")
	return headers

# ─────────────────────────────────────────────────
# MAIN VOICE FLOW
# ─────────────────────────────────────────────────

func start_voice_recording() -> void:
	"""Start recording from microphone"""
	if _is_recording:
		return
	
	_is_recording = true
	_recording_buffer.clear()
	voice_started.emit()
	print("VoiceCompanionRest: started recording")

func stop_voice_recording() -> void:
	"""Stop recording and process audio"""
	if not _is_recording:
		return
	
	_is_recording = false
	voice_stopped.emit()
	print("VoiceCompanionRest: stopped recording, processing audio")
	
	# Convert recording buffer to WAV and send
	_process_recorded_audio()

func _process_recorded_audio() -> void:
	"""Convert recorded audio to WAV and send to voice endpoint"""
	if _recording_buffer.is_empty():
		error_occurred.emit("No audio recorded")
		return
	
	_is_processing = true
	processing_started.emit()
	
	# Convert PackedVector2Array to WAV bytes
	var wav_bytes = _convert_audio_to_wav(_recording_buffer)
	var audio_base64 = _encode_base64(wav_bytes)
	
	# Send to backend
	_send_voice_request(audio_base64)

func _send_voice_request(audio_base64: String) -> void:
	"""Send voice audio to /api/companion/voice endpoint"""
	var url = get_backend_url() + "/api/companion/voice"
	var headers = get_auth_headers()
	headers["Content-Type"] = "application/json"
	
	var body = {
		"audioBase64": audio_base64,
		"contentType": "audio/wav",
		"voiceId": _voice_id,
		"companionName": _companion_name
	}
	
	var json_body = JSON.stringify(body)
	print("VoiceCompanionRest: sending voice request to ", url)
	
	_voice_request.request(url, headers, HTTPClient.METHOD_POST, json_body)

func _on_voice_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle voice endpoint response"""
	_is_processing = false
	processing_finished.emit()
	
	if response_code != 200:
		var error_msg = "Voice request failed with code %d" % response_code
		print("VoiceCompanionRest: ", error_msg)
		error_occurred.emit(error_msg)
		return
	
	var response_text = body.get_string_from_utf8()
	var json = JSON.parse_string(response_text)
	
	if json == null:
		error_occurred.emit("Failed to parse voice response")
		return
	
	var transcript = json.get("transcript", "")
	var reply_text = json.get("reply", "")
	var audio_base64 = json.get("audioBase64", "")
	
	print("VoiceCompanionRest: transcript='%s', reply='%s'" % [transcript, reply_text])
	
	transcription_received.emit(transcript)
	var audio_bytes = _decode_base64(audio_base64) if not audio_base64.is_empty() else PackedByteArray()
	reply_received.emit(reply_text, audio_bytes)
	
	# Play the audio response
	if not audio_base64.is_empty():
		_play_audio_from_base64(audio_base64)

# ─────────────────────────────────────────────────
# TEXT CHAT (Optional, for fallback)
# ─────────────────────────────────────────────────

func send_text_message(message: String) -> void:
	"""Send a text message to the companion"""
	if message.is_empty():
		return
	
	_is_processing = true
	processing_started.emit()
	
	var url = get_backend_url() + "/api/companion/chat"
	var headers = get_auth_headers()
	headers["Content-Type"] = "application/json"
	
	var body = {
		"message": message,
		"companionName": _companion_name
	}
	
	var json_body = JSON.stringify(body)
	print("VoiceCompanionRest: sending chat message")
	
	_chat_request.request(url, headers, HTTPClient.METHOD_POST, json_body)

func _on_chat_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle chat endpoint response"""
	_is_processing = false
	processing_finished.emit()
	
	if response_code != 200:
		error_occurred.emit("Chat request failed with code %d" % response_code)
		return
	
	var response_text = body.get_string_from_utf8()
	var json = JSON.parse_string(response_text)
	
	if json == null:
		error_occurred.emit("Failed to parse chat response")
		return
	
	var reply = json.get("reply", "")
	reply_received.emit(reply, PackedByteArray())

# ─────────────────────────────────────────────────
# TEXT-TO-SPEECH (Standalone TTS)
# ─────────────────────────────────────────────────

func synthesize_text(text: String) -> void:
	"""Send text to TTS endpoint and play audio"""
	if text.is_empty():
		return
	
	_is_processing = true
	processing_started.emit()
	
	var url = get_backend_url() + "/api/companion/tts"
	var headers = get_auth_headers()
	headers["Content-Type"] = "application/json"
	
	var body = {
		"text": text,
		"voiceId": _voice_id
	}
	
	var json_body = JSON.stringify(body)
	print("VoiceCompanionRest: sending TTS request")
	
	_tts_request.request(url, headers, HTTPClient.METHOD_POST, json_body)

func _on_tts_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle TTS response - body is raw audio"""
	_is_processing = false
	processing_finished.emit()
	
	if response_code != 200:
		error_occurred.emit("TTS request failed with code %d" % response_code)
		return
	
	print("VoiceCompanionRest: received TTS audio (%d bytes)" % body.size())
	_play_audio_from_bytes(body)

# ─────────────────────────────────────────────────
# SPEECH-TO-TEXT (Standalone STT)
# ─────────────────────────────────────────────────

func transcribe_audio(audio_base64: String) -> void:
	"""Send audio to STT endpoint"""
	if audio_base64.is_empty():
		return
	
	_is_processing = true
	processing_started.emit()
	
	var url = get_backend_url() + "/api/companion/stt"
	var headers = get_auth_headers()
	headers["Content-Type"] = "application/json"
	
	var body = {
		"audioBase64": audio_base64,
		"contentType": "audio/wav"
	}
	
	var json_body = JSON.stringify(body)
	print("VoiceCompanionRest: sending STT request")
	
	_stt_request.request(url, headers, HTTPClient.METHOD_POST, json_body)

func _on_stt_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle STT response"""
	_is_processing = false
	processing_finished.emit()
	
	if response_code != 200:
		error_occurred.emit("STT request failed with code %d" % response_code)
		return
	
	var response_text = body.get_string_from_utf8()
	var json = JSON.parse_string(response_text)
	
	if json == null:
		error_occurred.emit("Failed to parse STT response")
		return
	
	var transcript = json.get("transcript", "")
	print("VoiceCompanionRest: STT result='%s'" % transcript)
	transcription_received.emit(transcript)

# ─────────────────────────────────────────────────
# BASE64 ENCODING/DECODING
# ─────────────────────────────────────────────────

func _encode_base64(data: PackedByteArray) -> String:
	"""Encode bytes to base64 string using simple algorithm"""
	var base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	var result = ""
	var i = 0
	while i < data.size():
		var b1 = int(data[i]) if i < data.size() else 0
		var b2 = int(data[i + 1]) if i + 1 < data.size() else 0
		var b3 = int(data[i + 2]) if i + 2 < data.size() else 0
		
		var n = (b1 << 16) | (b2 << 8) | b3
		result += base64_chars[(n >> 18) & 0x3F]
		result += base64_chars[(n >> 12) & 0x3F]
		result += base64_chars[(n >> 6) & 0x3F] if i + 1 < data.size() else "="
		result += base64_chars[n & 0x3F] if i + 2 < data.size() else "="
		i += 3
	return result

func _decode_base64(encoded: String) -> PackedByteArray:
	"""Decode base64 string to bytes"""
	var base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	var result = PackedByteArray()
	var i = 0
	while i < encoded.length():
		var c1 = base64_chars.find(encoded[i]) if i < encoded.length() else 0
		var c2 = base64_chars.find(encoded[i + 1]) if i + 1 < encoded.length() else 0
		var c3 = base64_chars.find(encoded[i + 2]) if i + 2 < encoded.length() else 0
		var c4 = base64_chars.find(encoded[i + 3]) if i + 3 < encoded.length() else 0
		
		if c1 == -1: c1 = 0
		if c2 == -1: c2 = 0
		if c3 == -1: c3 = 0
		if c4 == -1: c4 = 0
		
		var n = (c1 << 18) | (c2 << 12) | (c3 << 6) | c4
		result.append((n >> 16) & 0xFF)
		if i + 2 < encoded.length() and encoded[i + 2] != '=':
			result.append((n >> 8) & 0xFF)
		if i + 3 < encoded.length() and encoded[i + 3] != '=':
			result.append(n & 0xFF)
		i += 4
	return result

# ─────────────────────────────────────────────────
# AUDIO UTILITIES
# ─────────────────────────────────────────────────

func _convert_audio_to_wav(audio_data: PackedVector2Array) -> PackedByteArray:
	"""Convert stereo audio samples to WAV format"""
	var wav = PackedByteArray()
	
	# WAV header (RIFF format, mono, 16-bit PCM)
	var num_channels = 1
	var sample_rate = _sample_rate
	var bits_per_sample = 16
	var num_samples = audio_data.size()
	
	var byte_rate = int((sample_rate * num_channels * bits_per_sample) / 8.0)
	var block_align = int((num_channels * bits_per_sample) / 8.0)
	var subchunk2_size = num_samples * block_align
	var chunk_size = 36 + subchunk2_size
	
	# RIFF header
	wav.append_array("RIFF".to_ascii_buffer())
	wav.append(chunk_size & 0xFF)
	wav.append((chunk_size >> 8) & 0xFF)
	wav.append((chunk_size >> 16) & 0xFF)
	wav.append((chunk_size >> 24) & 0xFF)
	wav.append_array("WAVE".to_ascii_buffer())
	
	# fmt sub-chunk
	wav.append_array("fmt ".to_ascii_buffer())
	wav.append(16)  # Subchunk1Size (16 for PCM)
	wav.append(0)
	wav.append(0)
	wav.append(0)
	wav.append(1)  # Audio format (1 = PCM)
	wav.append(0)
	wav.append(num_channels & 0xFF)  # Number of channels
	wav.append((num_channels >> 8) & 0xFF)
	wav.append(sample_rate & 0xFF)  # Sample rate
	wav.append((sample_rate >> 8) & 0xFF)
	wav.append((sample_rate >> 16) & 0xFF)
	wav.append((sample_rate >> 24) & 0xFF)
	wav.append(byte_rate & 0xFF)  # Byte rate
	wav.append((byte_rate >> 8) & 0xFF)
	wav.append((byte_rate >> 16) & 0xFF)
	wav.append((byte_rate >> 24) & 0xFF)
	wav.append(block_align & 0xFF)  # Block align
	wav.append((block_align >> 8) & 0xFF)
	wav.append(bits_per_sample & 0xFF)  # Bits per sample
	wav.append((bits_per_sample >> 8) & 0xFF)
	
	# data sub-chunk
	wav.append_array("data".to_ascii_buffer())
	wav.append(subchunk2_size & 0xFF)
	wav.append((subchunk2_size >> 8) & 0xFF)
	wav.append((subchunk2_size >> 16) & 0xFF)
	wav.append((subchunk2_size >> 24) & 0xFF)
	
	# Audio samples (mono, 16-bit PCM, little-endian)
	for sample in audio_data:
		var left = int(sample.x * 32767)
		left = clampi(left, -32768, 32767)
		wav.append(left & 0xFF)
		wav.append((left >> 8) & 0xFF)
	
	return wav

func _play_audio_from_base64(audio_base64: String) -> void:
	"""Decode base64 audio and play it"""
	var audio_bytes = _decode_base64(audio_base64)
	_play_audio_from_bytes(audio_bytes)

func _play_audio_from_bytes(audio_bytes: PackedByteArray) -> void:
	"""Play audio from raw bytes"""
	if audio_bytes.is_empty():
		print("VoiceCompanionRest: no audio data to play")
		return
	
	# Create AudioStreamWAV from bytes
	var audio_stream = AudioStreamWAV.new()
	audio_stream.data = audio_bytes
	
	_audio_player.stream = audio_stream
	_audio_player.play()
	print("VoiceCompanionRest: playing audio response")

func set_companion_name(companion_name: String) -> void:
	"""Set the companion's name"""
	_companion_name = companion_name

func set_voice_id(voice_id: String) -> void:
	"""Set the TTS voice ID"""
	_voice_id = voice_id

func voice_is_processing() -> bool:
	"""Check if processing a request"""
	return _is_processing

func voice_is_recording() -> bool:
	"""Check if currently recording"""
	return _is_recording
