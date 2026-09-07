extends Node

@export var backend_url: String = "http://127.0.0.1:5000"

var room = null
var local_audio_source = null
var local_audio_track = null
var mic_input_active = false
var input_mix_rate = 48000
var identity: String = "godot-user"
var agent_name: String = "habi-friend"
var remote_audio_track = null
var remote_audio_stream = null
var remote_audio_generator = null
var remote_audio_player: AudioStreamPlayer = null
var remote_audio_playback = null
var remote_audio_poll_time: float = 0.0
var remote_audio_poll_interval: float = 0.02
var remote_audio_min_frames_available: int = 16
var remote_audio_active: bool = false
var _mic_log_frames: int = 0
var _mic_log_time: float = 0.0
var _mic_log_interval: float = 2.0

func _ready():
	set_process(true)
	var dispatch_http = HTTPRequest.new()
	add_child(dispatch_http)
	dispatch_http.connect("request_completed", Callable(self, "_on_dispatch_completed"))
	request_dispatch(dispatch_http)

func _process(_delta: float) -> void:
	if mic_input_active and local_audio_source != null:
		_capture_local_mic_input(_delta)

	if remote_audio_stream != null and remote_audio_playback != null:
		remote_audio_poll_time += _delta
		if remote_audio_poll_time >= remote_audio_poll_interval:
			remote_audio_poll_time = 0.0
			var frames_available = 0
			if remote_audio_playback.has_method("get_frames_available"):
				frames_available = int(remote_audio_playback.call("get_frames_available"))
			if frames_available >= remote_audio_min_frames_available and remote_audio_stream.has_method("poll"):
				var frames_pushed = remote_audio_stream.poll(remote_audio_playback, 256)
				if frames_pushed != null:
					print("Remote audio polled frames=", frames_pushed)

func request_dispatch(http: HTTPRequest) -> void:
	var body := {"roomName": "habi-voice-room", "identity": identity, "agentName": agent_name}
	var json = JSON.stringify(body)
	print("Requesting LiveKit agent dispatch from " + backend_url)
	var err = http.request(backend_url + "/api/livekit/dispatch", [], HTTPClient.METHOD_POST, json)
	if err != OK:
		printerr("HTTPRequest failed to start:", err)

func request_token(http: HTTPRequest) -> void:
	var body := {"roomName": "habi-voice-room", "identity": identity, "name": "Godot User"}
	var json = JSON.stringify(body)
	print("Requesting LiveKit token from " + backend_url)
	var err = http.request(backend_url + "/api/livekit/token", [], HTTPClient.METHOD_POST, json)
	if err != OK:
		printerr("HTTPRequest failed to start:", err)

func _on_dispatch_completed(_result, response_code, _headers, body_arr: PackedByteArray) -> void:
	var body_text = ""
	if body_arr.size() > 0:
		body_text = body_arr.get_string_from_utf8()

	if response_code != 200:
		printerr("Dispatch request failed (", response_code, "):", body_text)
		return

	print("LiveKit agent dispatch succeeded")	
	var token_http = HTTPRequest.new()
	add_child(token_http)
	token_http.connect("request_completed", Callable(self, "_on_request_completed"))
	request_token(token_http)

func _on_request_completed(_result, response_code, _headers, body_arr: PackedByteArray) -> void:
	var body_text = ""
	if body_arr.size() > 0:
		body_text = body_arr.get_string_from_utf8()

	if response_code != 200:
		printerr("Token request failed (", response_code, "):", body_text)
		return

	var parsed = JSON.parse_string(body_text)
	var payload = parsed
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
		if parsed["error"] != OK:
			printerr("Failed parsing token response JSON")
			return
		payload = parsed["result"]

	if typeof(payload) != TYPE_DICTIONARY or !payload.has("token") or !payload.has("url"):
		printerr("Unexpected token response format:", body_text)
		return

	var token = payload["token"]
	var url = payload["url"]
	print("Received token, connecting to LiveKit at " + url)

	if not ClassDB.class_exists("LiveKitRoom"):
		printerr("LiveKitRoom class not available. Confirm LiveKit GDExtension is installed.")
		return

	var room_obj = ClassDB.instantiate("LiveKitRoom")
	if room_obj == null:
		printerr("Unable to instantiate LiveKitRoom from the extension")
		return

	room = room_obj
	if room is Node:
		add_child(room)
	if room.has_method("set_auto_poll"):
		room.call("set_auto_poll", true)
	room.connected.connect(Callable(self, "_on_connected"))
	room.participant_connected.connect(Callable(self, "_on_participant_connected"))
	room.track_subscribed.connect(Callable(self, "_on_track_subscribed"))
	room.connect_to_room(url, token, {})

func _on_connected() -> void:
	print("LiveKit room connected")
	_attempt_publish_local_audio()

func _on_participant_connected(participant) -> void:
	print("Participant connected:", participant.get_identity())

func _on_track_subscribed(track, _publication, participant) -> void:
	var participant_identity = "unknown"
	if participant != null and participant.has_method("get_identity"):
		participant_identity = str(participant.call("get_identity"))
	print("Track subscribed from", participant_identity, "name:", track.get_name())

	if participant_identity == identity:
		print("Ignoring own local track subscription")
		return

	if track == null:
		printerr("Subscribed track is null")
		return

	if track.has_method("get_kind") and track.call("get_kind") != _livekit_track_kind_audio():
		print("Ignoring non-audio subscribed track")
		return

	_start_remote_audio(track)

func _start_remote_audio(track: Object) -> void:
	_cleanup_remote_audio()
	if not ClassDB.class_exists("LiveKitAudioStream"):
		printerr("LiveKitAudioStream class unavailable")
		return

	remote_audio_active = true
	remote_audio_stream = _livekit_audio_stream_from_track(track)
	if remote_audio_stream == null:
		printerr("LiveKitAudioStream.from_track returned null")
		remote_audio_active = false
		return

	var sample_rate = 48000
	var channels = 1
	if remote_audio_stream.has_method("get_sample_rate"):
		sample_rate = int(remote_audio_stream.call("get_sample_rate"))
	if remote_audio_stream.has_method("get_num_channels"):
		channels = int(remote_audio_stream.call("get_num_channels"))

	remote_audio_generator = AudioStreamGenerator.new()
	remote_audio_generator.mix_rate = sample_rate
	remote_audio_generator.buffer_length = 0.2

	remote_audio_player = AudioStreamPlayer.new()
	remote_audio_player.stream = remote_audio_generator
	remote_audio_player.autoplay = true
	remote_audio_player.volume_db = 0.0
	remote_audio_player.bus = "Master"
	add_child(remote_audio_player)

	var master_bus_index: int = AudioServer.get_bus_index("Master")
	if master_bus_index >= 0:
		AudioServer.set_bus_mute(master_bus_index, false)
		AudioServer.set_bus_volume_db(master_bus_index, 0.0)

	remote_audio_player.play()
	remote_audio_player.stream_paused = false
	if AudioServer.has_method("get_output_device"):
		print("LiveKit demo: effective output device=", AudioServer.get_output_device())

	remote_audio_playback = remote_audio_player.get_stream_playback()
	if remote_audio_playback == null:
		printerr("Failed to get remote audio playback")
		remote_audio_active = false
		return

	print("AI reply audio active: sample_rate=", sample_rate, "channels=", channels)

func _cleanup_remote_audio() -> void:
	if remote_audio_stream != null and remote_audio_stream.has_method("close"):
		remote_audio_stream.call("close")
	remote_audio_stream = null
	remote_audio_generator = null
	if remote_audio_player != null:
		remote_audio_player.queue_free()
		remote_audio_player = null
	remote_audio_playback = null

func _start_mic_input() -> void:
	if mic_input_active:
		return
	if AudioServer.has_method("get_input_device_list"):
		var devices = AudioServer.get_input_device_list()
		print("LiveKit demo: available input devices=", devices)
	if AudioServer.has_method("get_input_device"):
		print("LiveKit demo: current input device=", AudioServer.get_input_device())
	if not AudioServer.has_method("set_input_device_active"):
		printerr("AudioServer input activation unavailable")
		return

	_select_input_device()

	var err = AudioServer.set_input_device_active(true)
	if err != OK:
		printerr("Failed to activate microphone input, error=", err)
		if AudioServer.has_method("get_input_device_list"):
			var devices = AudioServer.get_input_device_list()
			print("LiveKit demo: input device list on activation failure=", devices)
		return

	mic_input_active = true
	if AudioServer.has_method("get_input_mix_rate"):
		input_mix_rate = int(AudioServer.get_input_mix_rate())
		print("Microphone input active, mix_rate=", input_mix_rate)

func _select_input_device() -> void:
	if not AudioServer.has_method("set_input_device") or not AudioServer.has_method("get_input_device"):
		return
	if not AudioServer.has_method("get_input_device_list"):
		return

	var current_device = str(AudioServer.get_input_device())
	var devices = AudioServer.get_input_device_list()
	if devices is Array and devices.size() > 0:
		var selected_device = str(devices[0])
		if current_device != selected_device:
			AudioServer.set_input_device(selected_device)
			print("LiveKit demo: selected input device=", selected_device)
		else:
			print("LiveKit demo: already using input device=", current_device)
		print("LiveKit demo: confirmed input device=", AudioServer.get_input_device())

func _create_local_audio_track() -> Object:
	if not ClassDB.class_exists("LiveKitAudioSource"):
		printerr("LiveKitAudioSource class unavailable")
		return null
	if not ClassDB.class_exists("LiveKitLocalAudioTrack"):
		printerr("LiveKitLocalAudioTrack class unavailable")
		return null

	var sample_rate = 48000
	if AudioServer.has_method("get_input_mix_rate"):
		sample_rate = int(AudioServer.get_input_mix_rate())

	local_audio_source = _livekit_audio_source_create(sample_rate, 2, 100)
	if local_audio_source == null:
		printerr("LiveKitAudioSource.create returned null")
		return null

	var track = _livekit_local_audio_track_create("Godot User", local_audio_source)
	if track == null:
		printerr("LiveKitLocalAudioTrack.create returned null")
		return null

	return track

func _attempt_publish_local_audio() -> void:
	if room == null:
		return
	if not room.has_method("get_local_participant"):
		printerr("LiveKit room does not expose get_local_participant")
		return

	var participant = room.call("get_local_participant")
	if participant == null:
		printerr("Local participant not available yet")
		return
	if not participant.has_method("publish_track"):
		printerr("Local participant does not support publish_track")
		return

	if local_audio_track == null:
		local_audio_track = _create_local_audio_track()
	if local_audio_track == null:
		return

	_start_mic_input()

	print("Publishing local audio track...")
	var publish_options := {"source": _livekit_track_source_microphone()}
	var result = participant.call("publish_track", local_audio_track, publish_options)
	print("Publish local audio track result:", result)

func _capture_local_mic_input(delta: float) -> void:
	if not mic_input_active or local_audio_source == null:
		return
	if not AudioServer.has_method("get_input_frames_available") or not AudioServer.has_method("get_input_frames"):
		return

	var available = int(AudioServer.get_input_frames_available())
	if available <= 0:
		return

	var to_read = min(available, 1024)
	var raw_frames: PackedVector2Array = AudioServer.get_input_frames(to_read)
	if raw_frames.size() == 0:
		return

	var frames = raw_frames.size()
	var stereo: PackedFloat32Array = PackedFloat32Array()
	stereo.resize(frames * 2)
	for i in range(frames):
		var frame: Vector2 = raw_frames[i]
		stereo[i * 2] = frame.x
		stereo[i * 2 + 1] = frame.y

	if local_audio_source.has_method("capture_frame"):
		local_audio_source.capture_frame(stereo, input_mix_rate, 2, frames)
		_mic_log_frames += frames
		_mic_log_time += delta
		if _mic_log_time >= _mic_log_interval:
			print("Captured local mic frames total=", _mic_log_frames, " in ", _mic_log_time, " seconds")
			_mic_log_frames = 0
			_mic_log_time = 0.0

func _livekit_track_kind_audio() -> Variant:
	if ClassDB.class_exists("LiveKitTrack") and ClassDB.class_has_integer_constant("LiveKitTrack", "KIND_AUDIO"):
		return ClassDB.class_get_integer_constant("LiveKitTrack", "KIND_AUDIO")
	return 0

func _livekit_track_source_microphone() -> Variant:
	if ClassDB.class_exists("LiveKitTrack") and ClassDB.class_has_integer_constant("LiveKitTrack", "SOURCE_MICROPHONE"):
		return ClassDB.class_get_integer_constant("LiveKitTrack", "SOURCE_MICROPHONE")
	return 0

func _livekit_audio_stream_from_track(track: Object) -> Object:
	if not ClassDB.class_exists("LiveKitAudioStream"):
		return null
	if not ClassDB.class_has_method("LiveKitAudioStream", "from_track"):
		return null
	return ClassDB.class_call_static("LiveKitAudioStream", "from_track", [track])

func _livekit_audio_source_create(sample_rate: int, channels: int, queue_size: int) -> Object:
	if not ClassDB.class_exists("LiveKitAudioSource"):
		return null
	if not ClassDB.class_has_method("LiveKitAudioSource", "create"):
		return null
	return ClassDB.class_call_static("LiveKitAudioSource", "create", [sample_rate, channels, queue_size])

func _livekit_local_audio_track_create(track_name: String, source: Object) -> Object:
	if not ClassDB.class_exists("LiveKitLocalAudioTrack"):
		return null
	if not ClassDB.class_has_method("LiveKitLocalAudioTrack", "create"):
		return null
	return ClassDB.class_call_static("LiveKitLocalAudioTrack", "create", [track_name, source])
