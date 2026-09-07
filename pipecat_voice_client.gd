extends Node

signal connected
signal disconnected
signal audio_received(audio: PackedByteArray)
signal text_received(text: String)
signal connection_failed(message: String)

@export var websocket_url: String = "ws://127.0.0.1:8000/ws/voice"

var _socket: WebSocketPeer
var _connecting: bool = false
var _session_requested: bool = false

func is_connected_to_agent() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func connect_agent() -> void:
	if _session_requested:
		return
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		connected.emit()
		return
	var backend: Node = get_tree().root.get_node_or_null("HabiBackend")
	if backend == null or not backend.has_method("get_pipecat_session"):
		connection_failed.emit("HabiBackend is unavailable for Pipecat authentication")
		return
	_session_requested = true
	backend.get_pipecat_session(Callable(self, "_on_session_received"))

func _on_session_received(success: bool, payload: Variant) -> void:
	_session_requested = false
	if not success or not (payload is Dictionary):
		connection_failed.emit("Unable to obtain Pipecat session token")
		return
	var token: String = str(payload.get("token", "")).strip_edges()
	if token.is_empty():
		connection_failed.emit("Pipecat session response did not include a token")
		return
	_connect_with_token(token)

func _connect_with_token(token: String) -> void:
	_socket = WebSocketPeer.new()
	_connecting = true
	var separator := "&" if websocket_url.contains("?") else "?"
	var authenticated_url := websocket_url + separator + "token=" + token.uri_encode()
	var error: Error = _socket.connect_to_url(authenticated_url)
	if error != OK:
		_connecting = false
		connection_failed.emit("Pipecat WebSocket connection failed: %s" % error)
		return
	print("PipecatVoiceClient: connecting to ", websocket_url)

func send_pcm(audio: PackedByteArray) -> void:
	if audio.is_empty():
		return
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		connection_failed.emit("Pipecat WebSocket is not connected")
		return
	var chunk_size: int = 6400
	for offset in range(0, audio.size(), chunk_size):
		var end_offset: int = min(offset + chunk_size, audio.size())
		_socket.send(audio.slice(offset, end_offset))

func end_turn() -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	# Give VAD a brief silence window so it can close the speech turn quickly.
	var silence := PackedByteArray()
	silence.resize(12800)
	_socket.send(silence)

func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var state: WebSocketPeer.State = _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if _connecting:
			_connecting = false
			connected.emit()
		while _socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = _socket.get_packet()
			if not packet.is_empty():
				if _socket.was_string_packet():
					var message = JSON.parse_string(packet.get_string_from_utf8())
					if message is Dictionary and message.get("type", "") == "assistant_text":
						text_received.emit(str(message.get("text", "")))
				else:
					audio_received.emit(packet)
	elif state == WebSocketPeer.STATE_CLOSED:
		if _connecting:
			_connecting = false
			connection_failed.emit("Pipecat WebSocket closed before connecting")
		disconnected.emit()
		_socket = null
