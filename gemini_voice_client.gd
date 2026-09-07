extends Node

signal connected
signal disconnected
signal audio_received(audio: PackedByteArray)
signal text_received(text: String)
signal connection_failed(message: String)

@export var websocket_path: String = "/ws/gemini"

var _socket: WebSocketPeer
var _connecting: bool = false

func _ready() -> void:
	set_process(true)

func is_connected_to_agent() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func connect_agent() -> void:
	if is_connected_to_agent() or _connecting:
		return
	var backend: Node = get_tree().root.get_node_or_null("HabiBackend") if get_tree() != null and get_tree().root != null else null
	if backend == null and Engine.has_singleton("HabiBackend"):
		backend = Engine.get_singleton("HabiBackend")
	if backend == null or not backend.has_method("get_backend_url"):
		connection_failed.emit("HabiBackend is unavailable for Gemini voice")
		return

	var backend_url := str(backend.call("get_backend_url")).strip_edges().rstrip("/")
	if backend_url.is_empty():
		_connecting = false
		connection_failed.emit("HabiBackend URL is empty; set the backend URL before connecting Gemini voice")
		return
	var websocket_url := backend_url.replace("https://", "wss://").replace("http://", "ws://") + websocket_path
	_socket = WebSocketPeer.new()
	_connecting = true
	var error := _socket.connect_to_url(websocket_url)
	if error != OK:
		_connecting = false
		connection_failed.emit("Gemini WebSocket connection failed: %s" % error)
		return
	print("GeminiVoiceClient: connecting to ", websocket_url)

func send_pcm(audio: PackedByteArray) -> void:
	if audio.is_empty():
		return
	if not is_connected_to_agent():
		connection_failed.emit("Gemini WebSocket is not connected")
		return
	# Diagnostic log: report outgoing PCM size
	print("GeminiVoiceClient: send_pcm() bytes=", audio.size())
	_socket.send(audio)

func end_turn() -> void:
	if is_connected_to_agent():
		print("GeminiVoiceClient: end_turn() sending end_turn message")
		_socket.send_text(JSON.stringify({"type": "end_turn"}))

func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if _connecting:
			_connecting = false
			print("GeminiVoiceClient: connected")
			connected.emit()

			# Send an initial config to the Gemini voice backend so it knows which
			# provider and voice to use. Uses root meta keys `selected_gender`,
			# `voice_id_male`, and `voice_id_female` when available.
			var root := get_tree().root if get_tree() != null else null
			var preferred_voice: String = "alloy"
			if root != null:
				var gender: String = ""
				if root.has_meta("selected_gender"):
					gender = str(root.get_meta("selected_gender")).to_lower().strip_edges()
				var female_voice: String = "nova"
				var male_voice: String = "alloy"
				if root.has_meta("voice_id_female"):
					female_voice = str(root.get_meta("voice_id_female")).strip_edges()
				if root.has_meta("voice_id_male"):
					male_voice = str(root.get_meta("voice_id_male")).strip_edges()
				if female_voice.is_empty():
					female_voice = "nova"
				if male_voice.is_empty():
					male_voice = "alloy"
				if gender.find("girl") != -1 or gender.find("female") != -1:
					preferred_voice = female_voice
				elif gender.find("boy") != -1 or gender.find("male") != -1:
					preferred_voice = male_voice
				elif not female_voice.is_empty() and root.has_meta("voice_id_female"):
					preferred_voice = female_voice
				elif not male_voice.is_empty() and root.has_meta("voice_id_male"):
					preferred_voice = male_voice
			# send config message
			var cfg := {"type": "config", "provider": "gemini.google", "voiceId": preferred_voice}
			_socket.send_text(JSON.stringify(cfg))
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			if packet.is_empty() or not _socket.was_string_packet():
				continue
			var message = JSON.parse_string(packet.get_string_from_utf8())
			if not (message is Dictionary):
				continue
			var mtype := str(message.get("type", ""))
			print("GeminiVoiceClient: received message type=", mtype)
			match mtype:
				"audio":
					var encoded := str(message.get("data", ""))
					if not encoded.is_empty():
						audio_received.emit(Marshalls.base64_to_raw(encoded))
				"text":
					text_received.emit(str(message.get("text", "")))
				"input_text":
					print("Gemini input transcript: ", str(message.get("text", "")))
				"error":
					connection_failed.emit(str(message.get("message", "Gemini voice error")))
	elif state == WebSocketPeer.STATE_CLOSED:
		if _connecting:
			_connecting = false
			print("GeminiVoiceClient: connection closed before handshake completed")
			connection_failed.emit("Gemini WebSocket closed before connecting")
		disconnected.emit()
		_socket = null