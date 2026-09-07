extends Node

# Keep mic capture on the default OS input device.
# Forcing a device switch on Windows can trigger a second input popup and freeze the app.

signal livekit_connected(room_name: String)
signal livekit_error(message: String)
signal livekit_state_changed(state: String)

var _backend: Node = null
var _room: Object = null
var _room_url: String = ""
var _room_name: String = ""
var _identity: String = ""
var _display_name: String = ""
var _connecting: bool = false
var _native_supported: bool = false
var _using_fallback: bool = false
var _dispatch_required: bool = false
var _dispatch_endpoint: String = ""
var _dispatch_agent_name: String = "habi-friend"
var _dispatch_requested: bool = false
var _dispatch_succeeded: bool = false
var _local_participant: Object = null
var _waiting_for_local_participant: bool = false
var _participant_poll_time: float = 0.0
var _participant_wait_iterations: int = 0
var _local_audio_track: Object = null
var _local_audio_source: Object = null
var _local_audio_track_published: bool = false
var _mic_input_active: bool = false
var _input_mix_rate: int = 48000
var _publish_retry_time: float = 0.0
var _publish_retry_interval: float = 1.0
var _publish_pending: bool = false
var _remote_audio_track: Object = null
var _remote_audio_stream: Object = null
var _remote_audio_generator: Object = null
var _remote_audio_player: AudioStreamPlayer = null
var _remote_audio_playback: Object = null
var _remote_audio_poll_time: float = 0.0
var _remote_audio_poll_interval: float = 0.05
var _remote_audio_min_frames_available: int = 16
var _remote_audio_silence_time: float = 0.0
var _remote_audio_resume_after_silence: float = 0.5
var _remote_audio_quiet_time: float = 0.0
var _remote_audio_quiet_timeout: float = 0.2
var _remote_audio_stuck_timeout: float = 1.0
var _mic_was_active_during_remote: bool = false
var _force_mic_start: bool = false

@export var mic_enabled: bool = false
var _connected_once: bool = false
var _local_stereo_buffer: PackedFloat32Array = PackedFloat32Array()
var _local_capture_counter: int = 0
var _preferred_input_device_name: String = ""

func _class_call_static(class_name: String, method_name: String, args: Array = []) -> Variant:
	if not ClassDB.class_exists(class_name):
		return null
	if not ClassDB.class_has_method(class_name, method_name):
		return null
	return ClassDB.class_call_static(class_name, method_name, args)

func _safe_call(target: Object, method_name: String, args: Array = []) -> Variant:
	if target == null:
		return null
	if not target.has_method(method_name):
		return null
	if args.is_empty():
		return target.call(method_name)
	return target.callv(method_name, args)

func _livekit_room_state_connected() -> Variant:
	if ClassDB.class_exists("LiveKitRoom") and ClassDB.class_has_integer_constant("LiveKitRoom", "STATE_CONNECTED"):
		return ClassDB.class_get_integer_constant("LiveKitRoom", "STATE_CONNECTED")
	return "connected"

func _livekit_room_state_reconnecting() -> Variant:
	if ClassDB.class_exists("LiveKitRoom") and ClassDB.class_has_integer_constant("LiveKitRoom", "STATE_RECONNECTING"):
		return ClassDB.class_get_integer_constant("LiveKitRoom", "STATE_RECONNECTING")
	return "reconnecting"

func _livekit_room_state_disconnected() -> Variant:
	if ClassDB.class_exists("LiveKitRoom") and ClassDB.class_has_integer_constant("LiveKitRoom", "STATE_DISCONNECTED"):
		return ClassDB.class_get_integer_constant("LiveKitRoom", "STATE_DISCONNECTED")
	return "disconnected"

func _livekit_track_kind_audio() -> Variant:
	if ClassDB.class_exists("LiveKitTrack") and ClassDB.class_has_integer_constant("LiveKitTrack", "KIND_AUDIO"):
		return ClassDB.class_get_integer_constant("LiveKitTrack", "KIND_AUDIO")
	return "audio"

func _livekit_track_source_microphone() -> Variant:
	if ClassDB.class_exists("LiveKitTrack") and ClassDB.class_has_integer_constant("LiveKitTrack", "SOURCE_MICROPHONE"):
		return ClassDB.class_get_integer_constant("LiveKitTrack", "SOURCE_MICROPHONE")
	return "microphone"

func _room_state_is_connected(state_value: Variant) -> bool:
	if state_value == null:
		return false
	var state_name := str(state_value).to_lower()
	return state_name == "connected" or state_name == "state_connected"

func _ready() -> void:
	_backend = _resolve_backend()
	if _backend == null:
		print("LiveKitVoiceManager: HabiBackend singleton unavailable")
	else:
		print("LiveKitVoiceManager: ready")
	if mic_enabled:
		print("LiveKitVoiceManager: mic_enabled is true at ready, starting microphone")
		set_mic_enabled(true)
	set_process(true)

func _process(delta: float) -> void:
	_capture_local_mic_input()

	if _room != null and _local_participant != null and _publish_pending:
		_publish_retry_time += delta
		if _publish_retry_time >= _publish_retry_interval:
			_publish_retry_time = 0.0
			print("LiveKitVoiceManager: retrying local audio track publish after a failed attempt")
			_attempt_publish_local_audio_track()

	if _remote_audio_stream != null and _remote_audio_playback != null:
		_remote_audio_poll_time += delta
		if _remote_audio_poll_time >= _remote_audio_poll_interval:
			_remote_audio_poll_time = 0.0
			_check_remote_audio_playback()

	if _room == null:
		return

	_participant_poll_time += delta
	if _participant_poll_time >= 0.2:
		_participant_poll_time = 0.0
		if _room.has_method("poll_events"):
			var auto_poll = _room.has_method("get_auto_poll") and _room.call("get_auto_poll")
			if not auto_poll:
				print("LiveKitVoiceManager: calling poll_events")
				var poll_result = _room.call("poll_events")
				print("LiveKitVoiceManager: poll_events returned", poll_result)

		if _waiting_for_local_participant:
			_participant_wait_iterations += 1
			if _participant_wait_iterations % 2 == 0:
				print("LiveKitVoiceManager: still waiting for local participant, iteration=", _participant_wait_iterations)
			_check_local_participant()

func connect_voice_agent(room_name: String = "habi-voice-room", identity: String = "", display_name: String = "Habi User") -> void:
	print("LiveKitVoiceManager: connect_voice_agent called", {
		"room_name": room_name,
		"identity": identity,
		"display_name": display_name,
		"native_supported": _is_livekit_extension_available(),
	})
	if _connecting:
		print("LiveKitVoiceManager: connection already in progress")
		return

	if _room != null and get_connection_state() == "connected":
		print("LiveKitVoiceManager: already connected to LiveKit room", _room_name)
		if _local_audio_track == null:
			_attempt_publish_local_audio_track()
		if _dispatch_required and not _dispatch_requested and not _dispatch_succeeded:
			print("LiveKitVoiceManager: already connected but dispatch required, requesting agent dispatch")
			_dispatch_livekit_agent()
		_connecting = false
		return

	_connecting = true
	_using_fallback = false
	_dispatch_requested = false
	_dispatch_succeeded = false
	_room_name = room_name
	_identity = identity if not identity.is_empty() else _default_identity()
	_display_name = display_name if not display_name.is_empty() else _default_display_name()
	_native_supported = _is_livekit_extension_available()
	_backend = _resolve_backend()
	if _backend == null:
		_emit_error("HabiBackend singleton unavailable")
		_connecting = false
		return

	emit_signal("livekit_state_changed", "requesting_token")
	print("LiveKitVoiceManager: requesting token", {
		"room_name": _room_name,
		"identity": _identity,
		"display_name": _display_name,
	})
	_backend.get_livekit_token(_room_name, _identity, _display_name, Callable(self, "_on_token_completed"))
	print("LiveKitVoiceManager: token request sent to backend")

func disconnect_voice_agent() -> void:
	_stop_mic_input()
	_cleanup_remote_audio()
	if _room != null:
		if _room.has_method("disconnect_from_room"):
			_room.call("disconnect_from_room")
		elif _room.has_method("disconnect"):
			_room.call("disconnect")
	_room = null
	_local_audio_track = null
	_local_audio_source = null
	_using_fallback = false
	_connected_once = false
	emit_signal("livekit_state_changed", "disconnected")

func get_connection_state() -> String:
	if _using_fallback:
		return "connected"
	if _room == null:
		return "idle"
	if _room.has_method("get_connection_state"):
		var state_value = _room.call("get_connection_state")
		if state_value == _livekit_room_state_connected():
			return "connected"
		elif state_value == _livekit_room_state_reconnecting():
			return "reconnecting"
		elif state_value == _livekit_room_state_disconnected():
			return "disconnected"
		return str(state_value)
	return "connected"

func _on_dispatch_completed(success: bool, payload: Variant) -> void:
	print("LiveKitVoiceManager: dispatch completed, success=", success, " payload=", payload)
	_dispatch_requested = false

	if success:
		_dispatch_succeeded = true
		print("LiveKitVoiceManager: LiveKit agent dispatch succeeded")
		return

	print("LiveKitVoiceManager: LiveKit agent dispatch failed; retrying token request: %s" % str(payload))

	_backend = _resolve_backend()
	if _backend == null:
		_emit_error("HabiBackend singleton unavailable")
		_connecting = false
		return

	emit_signal("livekit_state_changed", "requesting_token")
	_backend.get_livekit_token(_room_name, _identity, _display_name, Callable(self, "_on_token_completed"))

func _on_token_completed(success: bool, payload: Variant) -> void:
	print("LiveKitVoiceManager: token completed, success=", success, " payload=", payload)
	if not success:
		_emit_error("LiveKit token request failed: %s" % str(payload))
		_connecting = false
		return

	var token: String = ""
	var url: String = ""
	var room_name: String = _room_name
	if payload is Dictionary:
		token = str(payload.get("token", ""))
		url = str(payload.get("url", ""))
		room_name = str(payload.get("roomName", _room_name))
		_dispatch_required = bool(payload.get("dispatchRequired", false))
		_dispatch_endpoint = str(payload.get("dispatchEndpoint", ""))
		_dispatch_agent_name = str(payload.get("agentName", _dispatch_agent_name))
	else:
		_emit_error("Unexpected LiveKit token payload: %s" % str(payload))
		_connecting = false
		return

	print("LiveKitVoiceManager: token payload parsed", {
		"token_present": not token.is_empty(),
		"url": url,
		"room_name": room_name,
		"dispatch_required": _dispatch_required,
		"dispatch_endpoint": _dispatch_endpoint,
		"dispatch_agent_name": _dispatch_agent_name,
	})

	if token.is_empty():
		_emit_error("LiveKit token was empty")
		_connecting = false
		return

	_room_url = url
	_room_name = room_name
	if _native_supported:
		_connect_to_room(token)
	else:
		_use_backend_fallback(token)

func _connect_to_room(token: String) -> void:
	emit_signal("livekit_state_changed", "connecting")
	print("LiveKitVoiceManager: connecting to room", {
		"url": _room_url,
		"room_name": _room_name,
		"identity": _identity,
		"display_name": _display_name,
		"native_supported": _is_livekit_extension_available(),
	})
	if not _is_livekit_extension_available():
		_emit_error("LiveKit GDExtension is not available. Confirm the extension is installed and the path is valid.")
		_connecting = false
		return

	if _room != null:
		disconnect_voice_agent()

	var room_obj: Object = ClassDB.instantiate("LiveKitRoom")
	if room_obj == null:
		_emit_error("Unable to instantiate LiveKitRoom from the installed extension")
		_connecting = false
		return

	_room = room_obj
	var connect_method: String = _find_method(_room, ["connect_to_room", "join_room", "connectAsync", "connect"])
	if connect_method.is_empty():
		_emit_error("The loaded LiveKit extension does not expose a room connection method")
		_connecting = false
		return

	var options: Dictionary = {}
	var result: Variant
	if _room.has_method("set_auto_poll"):
		print("LiveKitVoiceManager: ensuring auto_poll is enabled")
		_room.call("set_auto_poll", true)

	if _room.has_signal("connected"):
		_room.connect("connected", Callable(self, "_on_room_connected"))
		print("LiveKitVoiceManager: connected signal connected")
	else:
		print("LiveKitVoiceManager: connected signal not available on LiveKitRoom")
	if _room.has_signal("connection_failed"):
		_room.connect("connection_failed", Callable(self, "_on_room_connection_failed"))
		print("LiveKitVoiceManager: connection_failed signal connected")
	else:
		print("LiveKitVoiceManager: connection_failed signal not available on LiveKitRoom")
	if _room.has_signal("track_subscribed"):
		_room.connect("track_subscribed", Callable(self, "_on_track_subscribed"))
		print("LiveKitVoiceManager: track_subscribed signal connected")
	else:
		print("LiveKitVoiceManager: track_subscribed signal not available on LiveKitRoom")

	if _room.has_signal("track_unsubscribed"):
		_room.connect("track_unsubscribed", Callable(self, "_on_track_unsubscribed"))
		print("LiveKitVoiceManager: track_unsubscribed signal connected")
	else:
		print("LiveKitVoiceManager: track_unsubscribed signal not available on LiveKitRoom")

	if _room.has_signal("participant_connected"):
		_room.connect("participant_connected", Callable(self, "_on_participant_connected"))
		print("LiveKitVoiceManager: participant_connected signal connected")
	else:
		print("LiveKitVoiceManager: participant_connected signal not available on LiveKitRoom")

	if _room.has_signal("participant_disconnected"):
		_room.connect("participant_disconnected", Callable(self, "_on_participant_disconnected"))
		print("LiveKitVoiceManager: participant_disconnected signal connected")
	else:
		print("LiveKitVoiceManager: participant_disconnected signal not available on LiveKitRoom")

	print("LiveKitVoiceManager: connect method", connect_method, "options=", options)
	if connect_method == "connect":
		result = _room.call(connect_method, _room_url, token, options)
	else:
		result = _room.callv(connect_method, [_room_url, token, options])

	if _room.has_method("get_auto_poll"):
		print("LiveKitVoiceManager: _room auto_poll after connect?", _room.call("get_auto_poll"))

	print("LiveKitVoiceManager: connect result=", result)
	if result is bool and result:
		print("LiveKitVoiceManager: connect_to_room started async connect for", _room_name)
		_waiting_for_local_participant = true
		_participant_poll_time = 0.0
		_participant_wait_iterations = 0
		return

	_emit_error("LiveKit connection returned an unexpected result")
	_connecting = false

func _use_backend_fallback(_token: String) -> void:
	print("LiveKitVoiceManager: native extension unavailable; using backend fallback")
	_using_fallback = true
	emit_signal("livekit_connected", _room_name)
	emit_signal("livekit_state_changed", "connected")
	_connecting = false

	if _dispatch_required:
		print("LiveKitVoiceManager: dispatch is required for fallback path, requesting agent dispatch")
		_dispatch_livekit_agent()

func _on_room_connected() -> void:
	print("LiveKitVoiceManager: room signaled connected")
	emit_signal("livekit_connected", _room_name)
	emit_signal("livekit_state_changed", "connected")
	_connected_once = true
	_waiting_for_local_participant = true
	_participant_poll_time = 0.0
	_participant_wait_iterations = 0
	_dump_room_debug_info()
	_check_local_participant()
	_connecting = false

	if _dispatch_required and not _dispatch_succeeded:
		print("LiveKitVoiceManager: dispatch is required, requesting agent dispatch")
		_dispatch_livekit_agent()

	if _room.has_signal("track_subscribed") and not _room.is_connected("track_subscribed", Callable(self, "_on_track_subscribed")):
		_room.connect("track_subscribed", Callable(self, "_on_track_subscribed"))
		print("LiveKitVoiceManager: connected track_subscribed signal")
	if _room.has_signal("track_unsubscribed") and not _room.is_connected("track_unsubscribed", Callable(self, "_on_track_unsubscribed")):
		_room.connect("track_unsubscribed", Callable(self, "_on_track_unsubscribed"))
		print("LiveKitVoiceManager: connected track_unsubscribed signal")

func _on_room_connection_failed(error: String) -> void:
	_emit_error("LiveKit room connection failed: %s" % error)
	_connecting = false

func _on_participant_disconnected(participant: Object) -> void:
	print("LiveKitVoiceManager: participant_disconnected", participant)

func _dump_room_debug_info() -> void:
	print("LiveKitVoiceManager: dumping room debug info")
	if _room == null:
		print("LiveKitVoiceManager: room is null in debug dump")
		return

	var signals = []
	if _room.has_method("get_signal_list"):
		for sig in _room.call("get_signal_list"):
			signals.append(str(sig.name))
	else:
		print("LiveKitVoiceManager: room.get_signal_list unavailable")

	var methods = []
	if _room.has_method("get_method_list"):
		for m in _room.call("get_method_list"):
			methods.append(str(m.name))
	else:
		print("LiveKitVoiceManager: room.get_method_list unavailable")

	var participants = []
	if _room.has_method("get_participants"):
		for p in _room.call("get_participants"):
			participants.append(str(p))
	elif _room.has_method("get_remote_participants"):
		for p in _room.call("get_remote_participants"):
			participants.append(str(p))
	else:
		print("LiveKitVoiceManager: room participant list methods unavailable")

	var connection_state = "unknown"
	if _room.has_method("get_connection_state"):
		connection_state = _room.call("get_connection_state")

	print("LiveKitVoiceManager: room debug info", {
		"signals": signals,
		"methods": methods,
		"participants": participants,
		"connection_state": connection_state
	})

func _create_local_audio_track() -> Object:
	if not ClassDB.class_exists("LiveKitAudioSource"):
		print("LiveKitVoiceManager: LiveKitAudioSource class unavailable")
		return null

	if not ClassDB.class_exists("LiveKitLocalAudioTrack"):
		print("LiveKitVoiceManager: LiveKitLocalAudioTrack class unavailable")
		return null

	var sample_rate := 48000
	if AudioServer.has_method("get_input_mix_rate"):
		sample_rate = int(AudioServer.get_input_mix_rate())
		print("LiveKitVoiceManager: input mix rate detected=", sample_rate)
	else:
		print("LiveKitVoiceManager: AudioServer.get_input_mix_rate unavailable, using default", sample_rate)

	_input_mix_rate = sample_rate
	var source = _class_call_static("LiveKitAudioSource", "create", [sample_rate, 2, 100])
	if source == null:
		print("LiveKitVoiceManager: LiveKitAudioSource.create returned null")
		return null

	_local_audio_source = source
	var track = _class_call_static("LiveKitLocalAudioTrack", "create", [_display_name, source])
	if track == null:
		print("LiveKitVoiceManager: LiveKitLocalAudioTrack.create returned null")
		return null

	return track

func _attempt_publish_local_audio_track() -> void:
	if _local_participant == null:
		print("LiveKitVoiceManager: cannot publish because local participant is null")
		_publish_pending = true
		return

	if not _local_participant.has_method("publish_track"):
		print("LiveKitVoiceManager: local participant does not support publish_track")
		_publish_pending = true
		return

	if _local_audio_track == null:
		_local_audio_track = _create_local_audio_track()

	if _local_audio_track == null:
		print("LiveKitVoiceManager: could not create local audio track")
		_publish_pending = true
		return

	if _local_audio_track_published:
		print("LiveKitVoiceManager: audio track already published; resuming mic input")
		_start_mic_input()
		return

	_start_mic_input()

	print("LiveKitVoiceManager: publishing local audio track")
	var publish_options := {
		"source": _livekit_track_source_microphone()
	}
	var publish_result = _local_participant.call("publish_track", _local_audio_track, publish_options)
	print("LiveKitVoiceManager: publish result=", publish_result)

	if publish_result == null or (publish_result is bool and publish_result == false):
		print("LiveKitVoiceManager: publish_track returned null or failed")
		_publish_pending = true
		_publish_retry_time = 0.0
		return
	if publish_result is int and publish_result != OK:
		print("LiveKitVoiceManager: publish_track returned error code", publish_result)
		_publish_pending = true
		_publish_retry_time = 0.0
		return

	print("LiveKitVoiceManager: local audio track published successfully")
	_publish_pending = false
	_publish_retry_time = 0.0
	mic_enabled = true
	_local_audio_track_published = true

	if _local_participant != null:
		var pubs = null
		if _local_participant.has_method("get_track_publications"):
			pubs = _local_participant.call("get_track_publications")
		elif _local_participant.has_method("get_published_tracks"):
			pubs = _local_participant.call("get_published_tracks")
		elif _local_participant.has_method("get"):
			pubs = _local_participant.get("trackPublications")
		print("LiveKitVoiceManager: local participant publications=", pubs)
		if _local_audio_track != null and _local_audio_track.has_method("get_sid"):
			print("LiveKitVoiceManager: local audio track sid=", _local_audio_track.call("get_sid"))

func _check_local_participant() -> void:
	if _room == null:
		return

	if _room.has_method("get_connection_state"):
		var state_value = _room.call("get_connection_state")
		print("LiveKitVoiceManager: current room state=", state_value, "type=", typeof(state_value))

	var participant = _get_room_local_participant()
	if participant == null:
		return

	_local_participant = participant
	_waiting_for_local_participant = false
	print("LiveKitVoiceManager: local participant now available:", _local_participant)
	if _local_participant.has_method("publish_track"):
		print("LiveKitVoiceManager: local participant can publish audio tracks")
		if mic_enabled:
			print("LiveKitVoiceManager: mic_enabled is true, attempting local audio publish")
			_attempt_publish_local_audio_track()
		elif _local_audio_track == null:
			print("LiveKitVoiceManager: mic disabled, not publishing local audio track")
	else:
		print("LiveKitVoiceManager: local participant does not support publish_track")

	if _room.has_method("get_connection_state") and _room_state_is_connected(_room.call("get_connection_state")):
		_connecting = false

func _get_room_local_participant() -> Object:
	if _room == null:
		return null

	if _room.has_method("get_local_participant"):
		var participant = _room.call("get_local_participant")
		print("LiveKitVoiceManager: room get_local_participant =>", participant)
		if participant != null:
			return participant

	var candidate_methods = ["local_participant", "localParticipant"]
	for method_name in candidate_methods:
		if _room.has_method(method_name):
			var participant = _room.call(method_name)
			print("LiveKitVoiceManager: room call", method_name, "=>", participant)
			if participant != null:
				return participant

	var candidate_props = ["local_participant", "localParticipant"]
	for prop_name in candidate_props:
		if _room.has_method("get"):
			var participant = _room.get(prop_name)
			print("LiveKitVoiceManager: room get", prop_name, "=>", participant)
			if participant != null:
				return participant

	return null

func _on_track_subscribed(track: Object, _publication: Object, participant: Object) -> void:
	print("LiveKitVoiceManager: track_subscribed event for track=", track, " participant=", participant)
	if track == null:
		print("LiveKitVoiceManager: subscribed track is null")
		return

	if track.has_method("get_kind") and track.call("get_kind") != _livekit_track_kind_audio():
		print("LiveKitVoiceManager: ignoring non-audio subscribed track")
		return

	var participant_identity = "unknown"
	var participant_methods: Array = []
	if participant != null:
		if participant.has_method("get_identity"):
			participant_identity = str(participant.call("get_identity"))
		if participant.has_method("get_method_list"):
			var participant_method_list = participant.get_method_list()
			for m in participant_method_list:
				participant_methods.append(m.name)
	print("LiveKitVoiceManager: track subscription participant info", {
		"identity": participant_identity,
		"methods": participant_methods
	})
	if participant_identity == _identity:
		print("LiveKitVoiceManager: ignoring own local track subscription for identity=", participant_identity)
		return

	print("LiveKitVoiceManager: remote participant identity=", participant_identity)
	_remote_audio_track = track
	var track_kind = "unknown"
	var track_source = "unknown"
	if track.has_method("get_kind"):
		track_kind = str(track.call("get_kind"))
	if track.has_method("get_source"):
		track_source = str(track.call("get_source"))
	print("LiveKitVoiceManager: subscribed remote track kind=", track_kind, "source=", track_source)

	if _mic_input_active:
		_mic_was_active_during_remote = true
		print("LiveKitVoiceManager: remote track subscribed while mic active; will stop microphone when remote audio begins")

	_cleanup_remote_audio()

	var track_methods: Array = []
	if track != null and track.has_method("get_method_list"):
		var method_list = track.get_method_list()
		for m in method_list:
			track_methods.append(m.name)

	var track_type: String = "unknown"
	if track != null and track.has_method("get_kind"):
		track_type = str(track.call("get_kind"))

	print("LiveKitVoiceManager: attempting to create LiveKitAudioStream from subscribed track", {
		"track": track,
		"track_has_methods": track_methods,
		"track_type": track_type,
		"livekit_audio_stream_available": ClassDB.class_exists("LiveKitAudioStream")
	})

	_remote_audio_stream = _class_call_static("LiveKitAudioStream", "from_track", [track])
	if _remote_audio_stream == null:
		print("LiveKitVoiceManager: LiveKitAudioStream.from_track failed", {
			"track_has_method_get_kind": track != null and track.has_method("get_kind"),
			"track_has_method_get_source": track != null and track.has_method("get_source"),
			"track_type": track_type
		})
		return

	var sample_rate := 48000
	var channels := 1
	if _remote_audio_stream.has_method("get_sample_rate"):
		sample_rate = int(_remote_audio_stream.call("get_sample_rate"))
	if _remote_audio_stream.has_method("get_num_channels"):
		channels = int(_remote_audio_stream.call("get_num_channels"))

	print("LiveKitVoiceManager: remote audio stream created", {
		"sample_rate": sample_rate,
		"channels": channels,
		"stream_methods": _remote_audio_stream.get_method_list().map(func(m): return m.name)
	})

	_remote_audio_generator = AudioStreamGenerator.new()
	_remote_audio_generator.mix_rate = sample_rate
	_remote_audio_generator.buffer_length = 0.2

	_remote_audio_player = AudioStreamPlayer.new()
	_remote_audio_player.stream = _remote_audio_generator
	_remote_audio_player.autoplay = true
	_remote_audio_player.volume_db = 6.0

	var master_bus_index = AudioServer.get_bus_index("Master")
	var bus_name = "Master"
	if master_bus_index < 0:
		print("LiveKitVoiceManager: Master bus not found, falling back to bus index 0")
		master_bus_index = 0
		if AudioServer.has_method("get_bus_name"):
			bus_name = AudioServer.get_bus_name(master_bus_index)
	else:
		if AudioServer.has_method("get_bus_name"):
			bus_name = AudioServer.get_bus_name(master_bus_index)
	print("LiveKitVoiceManager: audio bus selected=", bus_name, "index=", master_bus_index)
	AudioServer.set_bus_mute(master_bus_index, false)
	AudioServer.set_bus_volume_db(master_bus_index, 6.0)
	var output_device = ""
	var output_devices = []
	if AudioServer.has_method("get_output_device_list"):
		output_devices = AudioServer.get_output_device_list()
		print("LiveKitVoiceManager: available output devices=", output_devices)
	if AudioServer.has_method("get_output_device"):
		output_device = AudioServer.get_output_device()
		print("LiveKitVoiceManager: current output device=", output_device)
	print("LiveKitVoiceManager: using OS default output device routing")
	_remote_audio_player.bus = bus_name

	add_child(_remote_audio_player)
	if _remote_audio_player.has_signal("finished"):
		_remote_audio_player.connect("finished", Callable(self, "_on_remote_audio_finished"))
		print("LiveKitVoiceManager: connected finished signal for remote audio player")
	_remote_audio_player.play()
	if _remote_audio_player.has_method("is_playing"):
		print("LiveKitVoiceManager: remote audio player is_playing=", _remote_audio_player.is_playing())
	else:
		print("LiveKitVoiceManager: remote audio player created and play() called")

	_remote_audio_playback = _remote_audio_player.get_stream_playback()
	print("LiveKitVoiceManager: remote audio playback retrieved", {
		"playback": _remote_audio_playback,
		"has_get_frames_available": _remote_audio_playback != null and _remote_audio_playback.has_method("get_frames_available"),
		"has_is_playing": _remote_audio_playback != null and _remote_audio_playback.has_method("is_playing")
	})
	if _remote_audio_playback == null:
		print("LiveKitVoiceManager: failed to get AudioStreamGeneratorPlayback from player")
		_cleanup_remote_audio()
		return

	_remote_audio_silence_time = 0.0
	_remote_audio_quiet_time = 0.0

	print("LiveKitVoiceManager: remote audio playback started, sample_rate=", sample_rate, "channels=", channels)
	print("LiveKitVoiceManager: remote audio track stored and audio playback initialized")

func _is_livekit_extension_available() -> bool:
	if ClassDB.class_exists("LiveKitRoom"):
		return true
	return false

func _is_remote_audio_active() -> bool:
	if _remote_audio_player == null or _remote_audio_playback == null:
		return false
	if _remote_audio_playback.has_method("get_frames_available"):
		var frames_available = int(_remote_audio_playback.call("get_frames_available"))
		return frames_available > 0
	if _remote_audio_player.has_method("is_playing"):
		return bool(_remote_audio_player.call("is_playing"))
	return false

func _start_mic_input(force: bool = false) -> void:
	if _mic_input_active:
		return
	if _is_remote_audio_active() and not force and not _force_mic_start:
		print("LiveKitVoiceManager: deferring mic input while remote AI audio is playing; remote silence_time=", _remote_audio_silence_time, "quiet_time=", _remote_audio_quiet_time)
		return
	if AudioServer.has_method("get_input_device_list"):
		var devices = AudioServer.get_input_device_list()
		print("LiveKitVoiceManager: available input devices=", devices)
	if AudioServer.has_method("get_input_device"):
		print("LiveKitVoiceManager: current input device=", AudioServer.get_input_device())

	_select_input_device()

	_mic_input_active = true
	if AudioServer.has_method("get_input_mix_rate"):
		_input_mix_rate = int(AudioServer.get_input_mix_rate())
	print("LiveKitVoiceManager: microphone input enabled using default system device, mix_rate=", _input_mix_rate)

func _select_input_device() -> void:
	if AudioServer.has_method("get_input_device"):
		print("LiveKitVoiceManager: using default system input device=", AudioServer.get_input_device())
	return

func _stop_mic_input() -> void:
	if not _mic_input_active:
		return
	_mic_input_active = false
	print("LiveKitVoiceManager: microphone input stopped")

func _resume_mic_input() -> void:
	if _mic_input_active:
		return
	if _remote_audio_stream != null and _remote_audio_playback != null and _is_remote_audio_active():
		print("LiveKitVoiceManager: remote audio still active, not resuming microphone yet")
		return
	_mic_input_active = true
	print("LiveKitVoiceManager: microphone input resumed on default system device")
	_mic_was_active_during_remote = false
	_remote_audio_silence_time = 0.0
	_remote_audio_quiet_time = 0.0

func _unpublish_local_audio_track() -> void:
	if _local_participant == null or _local_audio_track == null:
		return
	if not _local_participant.has_method("unpublish_track"):
		print("LiveKitVoiceManager: local participant does not support unpublish_track")
		return
	if not _local_audio_track.has_method("get_sid"):
		print("LiveKitVoiceManager: local audio track does not expose sid")
		return

	var track_sid = str(_local_audio_track.call("get_sid"))
	if track_sid == "":
		print("LiveKitVoiceManager: could not determine local audio track sid")
		return

	print("LiveKitVoiceManager: unpublishing local audio track sid=", track_sid)
	_local_participant.call("unpublish_track", track_sid)
	_local_audio_track = null
	_local_audio_source = null
	_local_audio_track_published = false
	_publish_pending = false
	mic_enabled = false
	print("LiveKitVoiceManager: local audio track unpublished")

func set_mic_enabled(enabled: bool) -> void:
	if enabled:
		mic_enabled = true
		if _mic_input_active:
			print("LiveKitVoiceManager: mic already active")
			return
		if _room == null or _local_participant == null:
			print("LiveKitVoiceManager: cannot enable mic until connected to LiveKit room; will retry when connected")
			return
		_attempt_publish_local_audio_track()
	else:
		mic_enabled = false
		_publish_pending = false
		if _mic_input_active:
			_stop_mic_input()
			print("LiveKitVoiceManager: mic disabled")
		elif _local_audio_track != null:
			print("LiveKitVoiceManager: mic disabled with no active input; cleaning up existing audio track")
		else:
			print("LiveKitVoiceManager: mic already disabled")

		if _local_audio_track != null:
			if _local_participant != null:
				_unpublish_local_audio_track()
			else:
				print("LiveKitVoiceManager: local audio track exists but local participant is unavailable; clearing track")
				_local_audio_track = null
				_local_audio_source = null
				_local_audio_track_published = false
			return
		if _local_audio_track == null and _local_audio_track_published:
			print("LiveKitVoiceManager: clearing published audio state")
			_local_audio_track_published = false

func toggle_mic() -> void:
	set_mic_enabled(not mic_enabled)

func start_push_to_talk() -> void:
	print("LiveKitVoiceManager: start_push_to_talk")
	_force_mic_start = true
	set_mic_enabled(true)

func stop_push_to_talk() -> void:
	print("LiveKitVoiceManager: stop_push_to_talk")
	_force_mic_start = false
	mic_enabled = false
	_publish_pending = false
	if _mic_input_active:
		_stop_mic_input()
	print("LiveKitVoiceManager: push-to-talk stopped; local audio track state preserved")

func is_livekit_connected() -> bool:
	return get_connection_state() == "connected"

func _capture_local_mic_input() -> void:
	if _is_remote_audio_active() and not _force_mic_start:
		if _mic_input_active:
			_stop_mic_input()
		return
	if not _mic_input_active or _local_audio_source == null:
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
	_local_stereo_buffer.resize(frames * 2)
	for i in range(frames):
		var frame: Vector2 = raw_frames[i]
		_local_stereo_buffer[i * 2] = frame.x
		_local_stereo_buffer[i * 2 + 1] = frame.y

	var peak: float = 0.0
	var sum_sqr: float = 0.0
	for s in _local_stereo_buffer:
		var a = abs(float(s))
		if a > peak:
			peak = a
		sum_sqr += a * a
	var rms: float = 0.0
	if _local_stereo_buffer.size() > 0:
		rms = sqrt(sum_sqr / float(_local_stereo_buffer.size()))
	if peak > 0.0001:
		print("LiveKitVoiceManager: mic capture peak=", peak, "rms=", rms, "frames=", frames)

	if _local_audio_source.has_method("capture_frame"):
		_local_audio_source.capture_frame(_local_stereo_buffer, _input_mix_rate, 2, frames)
		_local_capture_counter += 1
		if _local_capture_counter % 20 == 0:
			print("LiveKitVoiceManager: captured local mic frames=", frames, "available=", available, "queue_ms=", _local_audio_source.call("get_queued_duration") if _local_audio_source.has_method("get_queued_duration") else "n/a")

func _find_method(target: Object, candidates: Array) -> String:
	if target == null:
		return ""
	for candidate in candidates:
		if target.has_method(str(candidate)):
			return str(candidate)
	return ""

func save_mic_capture_wav(filename: String = "mic_capture.wav") -> void:
	if _local_stereo_buffer.size() == 0:
		print("LiveKitVoiceManager: no captured samples to save")
		return

	var frames = int(_local_stereo_buffer.size() / 2.0)
	var sample_rate = int(_input_mix_rate)
	var out_path = "user://" + filename
	var file = FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		print("LiveKitVoiceManager: failed to open file for writing:", out_path)
		return

	var channels = 1
	var bits_per_sample = 16
	var bytes_per_sample = bits_per_sample / 8.0
	var subchunk2_size = frames * channels * int(bytes_per_sample)
	var chunk_size = 36 + subchunk2_size

	file.store_string("RIFF")
	file.store_32(chunk_size)
	file.store_string("WAVE")
	file.store_string("fmt ")
	file.store_32(16)
	file.store_16(1)
	file.store_16(channels)
	file.store_32(sample_rate)
	file.store_32(sample_rate * channels * int(bytes_per_sample))
	file.store_16(int(channels * bytes_per_sample))
	file.store_16(bits_per_sample)
	file.store_string("data")
	file.store_32(subchunk2_size)

	for i in range(frames):
		var left = int(clamp(int(_local_stereo_buffer[i * 2] * 32767.0), -32768, 32767))
		var right = int(clamp(int(_local_stereo_buffer[i * 2 + 1] * 32767.0), -32768, 32767))
		var mono = int((left + right) / 2.0)
		file.store_16(mono)

	file.close()
	print("LiveKitVoiceManager: saved mic capture to", out_path)

func _check_remote_audio_playback() -> void:
	if _remote_audio_playback == null or _remote_audio_stream == null:
		return

	var frames_available = 0
	if _remote_audio_playback.has_method("get_frames_available"):
		frames_available = int(_remote_audio_playback.call("get_frames_available"))

	var playback_is_playing = false
	if _remote_audio_playback.has_method("is_playing"):
		playback_is_playing = bool(_remote_audio_playback.call("is_playing"))

	print("LiveKitVoiceManager: remote audio status", {
		"frames_available": frames_available,
		"playback_is_playing": playback_is_playing,
		"remote_audio_silence_time": _remote_audio_silence_time,
		"remote_audio_quiet_time": _remote_audio_quiet_time,
	})

	if _mic_input_active and _mic_was_active_during_remote and _is_remote_audio_active():
		print("LiveKitVoiceManager: remote audio began while mic was active; stopping microphone to avoid feedback")
		_stop_mic_input()

	if frames_available >= _remote_audio_min_frames_available and _remote_audio_stream.has_method("poll"):
		var frames_pushed = _remote_audio_stream.poll(_remote_audio_playback, 256)
		if frames_pushed != null:
			print("LiveKitVoiceManager: polled remote audio stream, frames pushed=", frames_pushed)
			if frames_pushed == 0:
				print("LiveKitVoiceManager: remote audio poll returned 0 frames")

	if frames_available == 0:
		_remote_audio_quiet_time += _remote_audio_poll_interval
	else:
		_remote_audio_quiet_time = 0.0

	if _remote_audio_quiet_time >= _remote_audio_quiet_timeout and not playback_is_playing:
		print("LiveKitVoiceManager: remote audio playback ended/quiet, cleaning up", {
			"playback_is_playing": playback_is_playing,
			"frames_available": frames_available,
			"quiet_time": _remote_audio_quiet_time,
		})
		_cleanup_remote_audio()
		if mic_enabled and not _mic_input_active:
			print("LiveKitVoiceManager: resuming microphone after remote audio ended")
			_resume_mic_input()

	if frames_available == 0:
		_remote_audio_silence_time += _remote_audio_poll_interval
	else:
		_remote_audio_silence_time = 0.0

	if _remote_audio_silence_time >= _remote_audio_resume_after_silence and mic_enabled and not _mic_input_active:
		print("LiveKitVoiceManager: remote audio silence detected, resuming mic input")
		_resume_mic_input()

	if frames_available == 0 and playback_is_playing and _remote_audio_silence_time >= _remote_audio_stuck_timeout:
		print("LiveKitVoiceManager: remote audio appears silent but playback still active; forcing cleanup and mic resume", {
			"playback_is_playing": playback_is_playing,
			"frames_available": frames_available,
			"silence_time": _remote_audio_silence_time,
		})
		_cleanup_remote_audio()
		if mic_enabled and not _mic_input_active:
			print("LiveKitVoiceManager: forced mic resume after silent remote audio")
			_resume_mic_input()

func _dispatch_livekit_agent() -> void:
	if _dispatch_requested:
		print("LiveKitVoiceManager: dispatch already requested, skipping duplicate call")
		return

	if _dispatch_succeeded:
		print("LiveKitVoiceManager: dispatch already succeeded, skipping duplicate call")
		return

	if _backend == null:
		_backend = _resolve_backend()
	if _backend == null:
		print("LiveKitVoiceManager: cannot dispatch LiveKit agent because HabiBackend is unavailable")
		return

	print("LiveKitVoiceManager: dispatch state", {
		"dispatch_required": _dispatch_required,
		"dispatch_endpoint": _dispatch_endpoint,
		"dispatch_agent_name": _dispatch_agent_name,
		"room_name": _room_name,
		"identity": _identity,
	})
	if _dispatch_endpoint == "" or not _dispatch_required:
		print("LiveKitVoiceManager: dispatch not required or no endpoint configured")
		return

	_dispatch_requested = true
	print("LiveKitVoiceManager: dispatching LiveKit agent", {
		"room_name": _room_name,
		"agent": _dispatch_agent_name,
		"identity": _identity,
	})
	_backend.dispatch_livekit(_room_name, _identity, _dispatch_agent_name, Callable(self, "_on_dispatch_completed"))

func _cleanup_remote_audio() -> void:
	if _remote_audio_stream != null:
		if _remote_audio_stream.has_method("close"):
			_remote_audio_stream.call("close")
		_remote_audio_stream = null
	_remote_audio_generator = null
	if _remote_audio_player != null:
		_remote_audio_player.stop()
		_remote_audio_player.queue_free()
		_remote_audio_player = null
	_remote_audio_playback = null
	_remote_audio_track = null
	_remote_audio_silence_time = 0.0
	_remote_audio_quiet_time = 0.0

func _on_remote_audio_finished() -> void:
	print("LiveKitVoiceManager: remote audio finished signal received")
	_cleanup_remote_audio()
	if mic_enabled and not _mic_input_active:
		print("LiveKitVoiceManager: resuming mic after remote audio finished")
		_resume_mic_input()

func _on_track_unsubscribed(track: Object, _publication: Object, participant: Object) -> void:
	print("LiveKitVoiceManager: track_unsubscribed event for track=", track, "participant=", participant)
	if track == null:
		return
	if _remote_audio_track == null:
		return
	if track != _remote_audio_track:
		return
	print("LiveKitVoiceManager: remote audio track unsubscribed, cleaning up and resuming microphone")
	_cleanup_remote_audio()
	if mic_enabled and not _mic_input_active:
		_resume_mic_input()

func _resolve_backend() -> Node:
	var root = null
	if get_tree() != null:
		root = get_tree().root
	if root != null:
		var backend: Node = root.get_node_or_null("HabiBackend")
		if backend != null:
			return backend
	if Engine.has_singleton("HabiBackend"):
		return Engine.get_singleton("HabiBackend")
	return null

func _default_identity() -> String:
	if Engine.has_singleton("UserSession"):
		var session = Engine.get_singleton("UserSession")
		if session != null:
			if session.has_method("get_current_user_id"):
				var user_id = str(session.call("get_current_user_id")).strip_edges()
				if not user_id.is_empty():
					return user_id
			if session.has_method("get_current_user_email"):
				var user_email = str(session.call("get_current_user_email")).strip_edges()
				if not user_email.is_empty():
					return user_email
			if session.has_method("get_current_user_id"):
				var user_id_prop = str(session.call("get_current_user_id")).strip_edges()
				if not user_id_prop.is_empty():
					return user_id_prop
	return "godot-user"

func _default_display_name() -> String:
	if Engine.has_singleton("UserSession"):
		var session = Engine.get_singleton("UserSession")
		if session != null:
			if session.has_method("get_current_user_name"):
				var user_name = str(session.call("get_current_user_name")).strip_edges()
				if not user_name.is_empty():
					return user_name
	return "Habi User"

func _emit_error(message: String) -> void:
	print("LiveKitVoiceManager error: ", message)
	emit_signal("livekit_error", message)
	emit_signal("livekit_state_changed", "error")
