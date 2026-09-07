extends Node
# Real-Time Firebase Listener Manager
# Maintains persistent database listeners for real-time updates
# Triggers callbacks immediately when data changes (no polling needed)

const DEFAULT_FIREBASE_DB_URL: String = "https://adv-habi-default-rtdb.firebaseio.com"

var _db: Node
var _db_url: String = DEFAULT_FIREBASE_DB_URL
var _listeners: Dictionary = {}  # {path: {callback: Callable, last_data: Dictionary, http: HTTPRequest}}
var _reconnect_attempts: Dictionary = {}  # {path: attempt_count}
var _reconnect_timer: Timer
var _is_monitoring: bool = false

func _ready() -> void:
	_db = _resolve_db()
	_db_url = _resolve_database_url()
	_setup_reconnect_timer()

func _resolve_db() -> Node:
	if get_tree() != null and get_tree().root != null:
		var db: Node = get_tree().root.get_node_or_null("FirebaseRTDB")
		if db != null:
			return db
	if Engine.has_singleton("FirebaseRTDB"):
		return Engine.get_singleton("FirebaseRTDB")
	return null

func _resolve_database_url() -> String:
	if _db != null:
		var configured: String = str(_db.get("database_url") if _db.has_meta("database_url") else DEFAULT_FIREBASE_DB_URL).strip_edges()
		if configured != "" and configured.begins_with("http"):
			return configured.rstrip("/")
	return DEFAULT_FIREBASE_DB_URL

func _setup_reconnect_timer() -> void:
	_reconnect_timer = Timer.new()
	_reconnect_timer.name = "ReconnectTimer"
	_reconnect_timer.wait_time = 5.0  # Retry failed listeners every 5 seconds
	_reconnect_timer.timeout.connect(_attempt_reconnect)
	add_child(_reconnect_timer)

func listen_to_path(path: String, callback: Callable) -> void:
	"""
	Setup a real-time listener on a Firebase path
	Callback is triggered immediately when data changes
	Signature: callback.call(data: Dictionary)
	"""
	print("Real-Time Listener: Setting up listener on path: ", path)
	
	_listeners[path] = {
		"callback": callback,
		"last_data": {},
		"http": null,
		"timestamp": Time.get_ticks_msec()
	}
	
	_reconnect_attempts[path] = 0
	_start_listening(path)

func stop_listening(path: String) -> void:
	"""Stop listening to a path"""
	if path in _listeners:
		var listener = _listeners[path]
		if listener.has("http") and listener["http"] != null:
			listener["http"].queue_free()
		_listeners.erase(path)
		_reconnect_attempts.erase(path)
		print("Real-Time Listener: Stopped listening to path: ", path)

func stop_all_listeners() -> void:
	"""Stop all active listeners"""
	for path in _listeners.keys():
		stop_listening(path)
	_is_monitoring = false

func _start_listening(path: String) -> void:
	"""Start listening to a path with immediate polling"""
	# If this node isn't inside the active scene tree yet, defer starting
	if not is_inside_tree():
		print("Real-Time Listener: Not inside tree yet, deferring start for path:", path)
		call_deferred("_start_listening", path)
		return

	var http := HTTPRequest.new()
	add_child(http)
	
	_listeners[path]["http"] = http
	
	# Set up request processing with proper callback
	http.request_completed.connect(func(_result, code, _headers, body):
		_on_data_received(path, code, body)
	)
	
	# Format URL for Firebase streaming (using .json with timeouts)
	var url = "%s/%s.json" % [_db_url, path]
	print("Real-Time Listener: Requesting - ", url)
	
	http.timeout = 60  # Keep connection open for up to 60 seconds
	http.request(url, [], HTTPClient.METHOD_GET)
	
	_is_monitoring = true

func _on_data_received(path: String, code: int, body: Variant) -> void:
	"""Process received data and trigger callback if changed"""
	var listener = _listeners.get(path)
	if listener == null:
		return
	
	# Parse response
	var new_data: Dictionary = {}
	if code == 200 and body != null:
		var body_str: String = ""
		if body is PackedByteArray:
			body_str = (body as PackedByteArray).get_string_from_utf8()
		else:
			body_str = str(body)
		
		var parsed = JSON.parse_string(body_str)
		if parsed is Dictionary:
			new_data = parsed
		elif parsed == null and body_str != "":
			# Handle null response gracefully
			new_data = {}
	
	# Compare with last data to detect changes
	var last_data = listener.get("last_data", {})
	var data_changed = _has_changed(new_data, last_data)
	
	if data_changed or listener["last_data"].is_empty():
		print("Real-Time Listener: Data changed on path: ", path)
		listener["last_data"] = new_data.duplicate(true)
		_reconnect_attempts[path] = 0  # Reset retry counter
		
		# Trigger callback immediately
		if listener["callback"].is_valid():
			listener["callback"].call(new_data)
	
	# Keep connection alive with subsequent requests
	call_deferred("_continue_listening", path)

func _continue_listening(path: String) -> void:
	"""Continue polling the path for changes"""
	if path not in _listeners:
		return
	
	var delay = 2.0  # Check every 2 seconds for changes
	await get_tree().create_timer(delay).timeout
	
	if path in _listeners:
		_start_listening(path)

func _has_changed(new_data: Dictionary, old_data: Dictionary) -> bool:
	"""Deep comparison to detect if data actually changed"""
	if new_data.size() != old_data.size():
		return true
	
	for key in new_data.keys():
		if key not in old_data:
			return true
		
		var new_val = new_data[key]
		var old_val = old_data[key]
		
		if new_val is Dictionary and old_val is Dictionary:
			if _has_changed(new_val as Dictionary, old_val as Dictionary):
				return true
		elif new_val != old_val:
			return true
	
	return false

func _attempt_reconnect() -> void:
	"""Attempt to reconnect failed listeners"""
	for path in _reconnect_attempts.keys():
		var attempts = _reconnect_attempts[path]
		if attempts > 0 and attempts < 5:  # Max 5 reconnection attempts
			print("Real-Time Listener: Reconnecting to ", path, " (attempt ", attempts, ")")
			_start_listening(path)
			_reconnect_attempts[path] += 1

func get_listener_status() -> Dictionary:
	"""Get status of all active listeners"""
	var status: Dictionary = {}
	for path in _listeners.keys():
		var listener = _listeners[path]
		status[path] = {
			"active": listener.has("http") and listener["http"] != null,
			"last_update": listener.get("timestamp", 0),
			"data_size": listener.get("last_data", {}).size()
		}
	return status
