extends Node
# Real-Time User Profile Updater
# Syncs user coins, experience, and profile data in real-time

var _db: Node
var _realtime_listener: Node
var _current_user_id: String = ""
var _session: Node
var _profile_update_callback: Callable = Callable()

func _ready() -> void:
	_db = _resolve_db()
	_realtime_listener = _resolve_realtime_listener()
	_session = _resolve_session()
	_current_user_id = _get_current_user_id()
	
	# Start listening to profile changes
	_setup_profile_listener()

func _resolve_db() -> Node:
	if get_tree() != null and get_tree().root != null:
		var db: Node = get_tree().root.get_node_or_null("FirebaseRTDB")
		if db != null:
			return db
	if Engine.has_singleton("FirebaseRTDB"):
		return Engine.get_singleton("FirebaseRTDB")
	return null

func _resolve_realtime_listener() -> Node:
	if get_tree() != null and get_tree().root != null:
		var existing_listener: Node = get_tree().root.get_node_or_null("FirebaseRealtimeListener")
		if existing_listener != null:
			return existing_listener
	# Create new listener if doesn't exist
	var new_listener = load("res://firebase_realtime_listener.gd").new()
	get_tree().root.add_child.call_deferred(new_listener)
	new_listener.name = "FirebaseRealtimeListener"
	return new_listener

func _resolve_session() -> Node:
	if get_tree() != null and get_tree().root != null:
		var session: Node = get_tree().root.get_node_or_null("UserSession")
		if session != null:
			return session
	if Engine.has_singleton("UserSession"):
		return Engine.get_singleton("UserSession")
	return null

func _get_current_user_id() -> String:
	if _session != null and _session.has_method("get_current_user_id"):
		var uid: String = str(_session.call("get_current_user_id")).strip_edges()
		if not uid.is_empty():
			return uid
	return "guest_user"

func _sanitize_key(value: String) -> String:
	var safe = str(value).strip_edges().to_lower()
	safe = safe.replace("@", "_at_")
	safe = safe.replace(".", "_")
	for ch in ["#", "$", "[", "]", "/"]:
		safe = safe.replace(ch, "_")
	return safe

func _setup_profile_listener() -> void:
	"""Setup real-time listener for user profile (coins, exp, level)"""
	if _realtime_listener == null:
		push_error("Real-time listener not available")
		return
	
	var storage_key = _sanitize_key(_current_user_id)
	var profile_path = "users/%s" % storage_key
	
	_realtime_listener.listen_to_path(profile_path, Callable(self, "_on_profile_updated"))
	
	print("Real-Time: Profile listener started for user: ", _current_user_id)

func _on_profile_updated(profile_data: Dictionary) -> void:
	"""Handle profile updates in real-time"""
	print("Real-Time: Profile updated - coins: %d, level: %d" % [profile_data.get("coins", 0), profile_data.get("level", 1)])
	
	# Trigger callback to update UI
	if _profile_update_callback.is_valid():
		_profile_update_callback.call(profile_data)

func set_profile_update_callback(callback: Callable) -> void:
	"""Register a callback to be called when profile updates"""
	_profile_update_callback = callback
