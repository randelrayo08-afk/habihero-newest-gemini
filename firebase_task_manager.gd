extends Node
# Firebase Task Manager - Handles real-time task sync between admin and users
# Features:
# - Create tasks (admin)
# - Assign tasks to users
# - Fetch user tasks
# - Real-time notifications when tasks are assigned
# - Task completion tracking

const DEFAULT_FIREBASE_DB_URL: String = "https://adv-habi-default-rtdb.firebaseio.com"

var _db: Node
var _auth_manager: Node
var _db_url: String = DEFAULT_FIREBASE_DB_URL

func _ready() -> void:
	_db = _resolve_db()
	_auth_manager = _resolve_auth_manager()
	_db_url = _resolve_database_url()

func _resolve_db() -> Node:
	if get_tree() != null and get_tree().root != null:
		var db: Node = get_tree().root.get_node_or_null("FirebaseRTDB")
		if db != null:
			return db
	if Engine.has_singleton("FirebaseRTDB"):
		return Engine.get_singleton("FirebaseRTDB")
	return null

func _resolve_auth_manager() -> Node:
	if get_tree() != null and get_tree().root != null:
		var auth: Node = get_tree().root.get_node_or_null("FirebaseAuthManager")
		if auth != null:
			return auth
	if Engine.has_singleton("FirebaseAuthManager"):
		return Engine.get_singleton("FirebaseAuthManager")
	return null

func _resolve_database_url() -> String:
	if _db != null and _db.has_meta("database_url"):
		var url: String = str(_db.get("database_url")).strip_edges()
		if url != "" and url.begins_with("http"):
			return url.rstrip("/")
	return DEFAULT_FIREBASE_DB_URL

func _sanitize_path(value: String) -> String:
	var safe = value.to_lower()
	safe = safe.replace("@", "_")
	safe = safe.replace(".", "_")
	safe = safe.replace("#", "_hash_")
	safe = safe.replace("$", "_dollar_")
	safe = safe.replace("[", "_")
	safe = safe.replace("]", "_")
	safe = safe.replace("/", "_")
	return safe

func _rtdb_url(path: String) -> String:
	var clean_path = path.strip_edges().trim_prefix("/")
	return "%s/%s.json" % [_db_url, clean_path]

# ── Admin Functions ──────────────────────────────────────
func create_task(title: String, description: String, category: String, difficulty: String, due_date: String, coins_reward: int, exp_reward: int, callback: Callable = Callable()) -> void:
	"""Create a new task (admin only)"""
	var task_id: String = "task_%s_%d" % [_sanitize_path(title), Time.get_ticks_msec()]
	var task_data: Dictionary = {
		"id": task_id,
		"title": title,
		"description": description,
		"category": category,
		"difficulty": difficulty,
		"due_date": due_date,
		"coins": coins_reward,
		"exp": exp_reward,
		"created_at": Time.get_datetime_string_from_system(),
		"status": "active"
	}
	
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, _body):
		http.queue_free()
		if callback.is_valid():
			callback.call(code == 200, task_data if code == 200 else {})
	)
	
	var url = _rtdb_url("admin/tasks/%s" % task_id)
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_PUT, JSON.stringify(task_data))

func assign_task_to_user(task_id: String, user_id: String, callback: Callable = Callable()) -> void:
	"""Assign a task to a specific user"""
	var storage_key = _sanitize_path(user_id)
	var assignment: Dictionary = {
		"task_id": task_id,
		"assigned_at": Time.get_datetime_string_from_system(),
		"completed": false,
		"completion_date": ""
	}
	
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, _body):
		http.queue_free()
		
		# Send notification to user
		_send_task_notification(user_id, task_id)
		
		if callback.is_valid():
			callback.call(code == 200)
	)
	
	var url = _rtdb_url("users/%s/tasks/%s" % [storage_key, task_id])
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_PUT, JSON.stringify(assignment))

func assign_task_to_all_users(task_id: String, callback: Callable = Callable()) -> void:
	"""Broadcast a task to all users"""
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		if code == 200 and body is Dictionary:
			var users: Dictionary = JSON.parse_string(body.get_string_from_utf8()) as Dictionary
			for user_id in users.keys():
				assign_task_to_user(task_id, user_id)
		if callback.is_valid():
			callback.call(code == 200)
	)
	
	var url = _rtdb_url("users")
	http.request(url, [], HTTPClient.METHOD_GET)

func fetch_user_tasks(user_id: String, callback: Callable = Callable()) -> void:
	"""Fetch all tasks assigned to a user"""
	var storage_key = _sanitize_path(user_id)
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		var tasks: Dictionary = {}
		if code == 200 and body is not String:
			var parsed = JSON.parse_string((body as PackedByteArray).get_string_from_utf8())
			if parsed is Dictionary:
				tasks = parsed
		if callback.is_valid():
			callback.call(code == 200, tasks)
	)
	
	var url = _rtdb_url("users/%s/tasks" % storage_key)
	http.request(url, [], HTTPClient.METHOD_GET)

func mark_task_complete(user_id: String, task_id: String, callback: Callable = Callable()) -> void:
	"""Mark a task as complete for a user"""
	var storage_key = _sanitize_path(user_id)
	var update: Dictionary = {
		"completed": true,
		"completion_date": Time.get_datetime_string_from_system()
	}
	
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, _body):
		http.queue_free()
		if callback.is_valid():
			callback.call(code == 200)
	)
	
	var url = _rtdb_url("users/%s/tasks/%s" % [storage_key, task_id])
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_PATCH, JSON.stringify(update))

func _send_task_notification(user_id: String, task_id: String) -> void:
	"""Send a notification when a task is assigned"""
	var storage_key = _sanitize_path(user_id)
	var notif_data: Dictionary = {
		"id": "notif_%s_%d" % [task_id, Time.get_ticks_msec()],
		"type": "task_assigned",
		"task_id": task_id,
		"message": "A new task has been assigned to you!",
		"created_at": Time.get_datetime_string_from_system(),
		"read": false
	}
	
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b):
		http.queue_free()
	)
	
	var url = _rtdb_url("users/%s/notifications/%s" % [storage_key, notif_data["id"]])
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_PUT, JSON.stringify(notif_data))
