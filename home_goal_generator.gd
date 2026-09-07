extends Control

# Firebase-based task pool (fetched from backend)
# Each task has: { "id": "task_001", "title": "Read a devotional..." }
var _current_daily_tasks: Array[String] = []
var _current_task_ids: Array[String] = []
var _task_pool: Array = []
var _active_tasks: Array = []
var _task_state: Dictionary = {}
var _user_id: String = ""
var _user_profile: Dictionary = {}  # Profile with age, gender, interests, mood
var _realtime_listener: Node
var _is_loading: bool = false
var _fetch_retry_count: int = 0
var _fetch_max_retries: int = 10

const MAX_ACTIVE_TASKS: int = 5
const DAILY_GOAL_COUNT: int = 5
const GOAL_TEXT_TRUNCATE_CHARS: int = 28
const TASK_REFRESH_INTERVAL_HOURS: int = 24
const REFILL_HOURS: int = 24
const TASK_STATE_PATH_PREFIX: String = "user://daily_task_state_"

func _ready() -> void:
	# Get current user ID from UserSession singleton
	_user_id = _get_current_user_id()
	_task_state = _load_task_state()
	_realtime_listener = _resolve_realtime_listener()
	_apply_completed_task_from_meta()
	
	_is_loading = true
	print("home_goal_generator: Fetching daily tasks for user %s" % _user_id)
	_setup_assigned_tasks_listener()
	
	# Load user profile first, then fetch tasks
	call_deferred("_load_user_profile_and_fetch_tasks")

func _load_user_profile_and_fetch_tasks() -> void:
	"""Load the user profile which contains age, gender, interests for task personalization."""
	_user_id = _get_current_user_id()
	var auth_manager: Variant = _resolve_firebase_manager()
	
	if auth_manager != null and auth_manager.has_method("load_profile"):
		auth_manager.call("load_profile", _user_id, Callable(self, "_on_profile_loaded"))
		return
	
	# If profile loading not available, proceed directly to fetch tasks
	_fetch_daily_tasks()

func _on_profile_loaded(success: bool, profile: Variant) -> void:
	"""Callback when user profile is loaded. Extract personalization attributes."""
	if success and profile is Dictionary:
		_user_profile = profile.duplicate()
		print("home_goal_generator: Loaded user profile: age=%s, gender=%s, interests=%s" % [
			_user_profile.get("age", "unset"),
			_user_profile.get("gender", "unset"),
			_user_profile.get("interests", [])
		])
	else:
		print("home_goal_generator: Could not load profile or no profile data yet")
		_user_profile = {}
	
	_fetch_daily_tasks()

func _fetch_daily_tasks() -> void:
	_user_id = _get_current_user_id()
	var backend = _resolve_backend()
	if backend == null:
		_fetch_retry_count += 1
		if _fetch_retry_count >= _fetch_max_retries:
			print("home_goal_generator: HabiBackend not available after %d retries, using fallback tasks" % _fetch_max_retries)
			_is_loading = false
			_use_fallback_tasks()
			_load_user_assigned_tasks_from_firebase()
			_render_daily_goals()
			return
		
		print("home_goal_generator: HabiBackend singleton not found, retrying... (attempt %d/%d)" % [_fetch_retry_count, _fetch_max_retries])
		# Retry after one more frame
		call_deferred("_fetch_daily_tasks")
		return
	
	if _user_id.strip_edges().is_empty() or _user_id == "guest_user":
		print("home_goal_generator: no authenticated user yet; skipping backend habit fetch and using fallback tasks")
		_is_loading = false
		_use_fallback_tasks()
		_load_user_assigned_tasks_from_firebase()
		_refresh_active_tasks()
		_render_daily_goals()
		return
	
	print("home_goal_generator: HabiBackend found, fetching tasks for user %s" % _user_id)
	print("home_goal_generator: habit fetch target uid=%s" % _user_id)
	var session = get_tree().root.get_node_or_null("UserSession")
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	var session_uid: String = ""
	if session != null:
		if session.has_method("get_current_user_id"):
			session_uid = str(session.call("get_current_user_id")).strip_edges()
	var token: String = ""
	if backend != null:
		token = backend._extract_token_from_session(session)
	var decoded_uid: String = ""
	if token != "":
		decoded_uid = backend._extract_uid_from_token(token)
	print("home_goal_generator: session uid=%s | token uid=%s | request uid=%s" % [session_uid, decoded_uid, _user_id])
	backend.get_daily_tasks(_user_id, Callable(self, "_on_daily_tasks_received"))

func _use_fallback_tasks() -> void:
	# Use hardcoded fallback tasks when backend is not available
	# Tasks are personalized based on user profile (age, gender, interests)
	var age: int = _user_profile.get("age", 10)
	var _gender: String = _user_profile.get("gender", "")
	var interests: Array = _user_profile.get("interests", [])
	
	var fallback_tasks: Array[String] = [
		"Read a short devotional and reflect for 5 minutes.",
		"Write down one thing you're grateful for today.",
		"Share an encouraging message with someone.",
		"Spend 10 minutes in prayer or quiet reflection.",
		"Read a Bible verse and think about how it applies to your day."
	]
	
	# Add age-appropriate tasks
	if age >= 8 and age <= 15:
		fallback_tasks.append("Draw or create something that represents your feelings today.")
		fallback_tasks.append("Spend 5 minutes doing your favorite hobby.")
	
	if age >= 12:
		fallback_tasks.append("Write a short journal entry about your day.")
		fallback_tasks.append("Help someone with a task or problem.")
	
	# Add interest-based tasks
	if "games" in interests or "playing" in interests:
		fallback_tasks.append("Play a game or sport you enjoy for 15 minutes.")
	
	if "reading" in interests or "books" in interests:
		fallback_tasks.append("Read a story or article that interests you.")
	
	if "drawing" in interests or "art" in interests or "creative" in interests:
		fallback_tasks.append("Create something artistic or expressive.")
	
	if "music" in interests or "singing" in interests:
		fallback_tasks.append("Listen to or play music that makes you happy.")
	
	_task_pool.clear()
	for i in range(fallback_tasks.size()):
		_task_pool.append({
			"id": "fallback_%d" % i,
			"title": fallback_tasks[i],
			"is_automated": true
		})
	_task_state["last_refresh_time"] = _get_current_unix_time()
	_save_task_state()
	print("home_goal_generator: Using %d fallback tasks (personalized for profile: age=%s, interests=%s)" % [
		_task_pool.size(),
		age,
		interests
	])

func _append_unique_task(task_data: Dictionary) -> void:
	if not task_data is Dictionary:
		return
	var task_id: String = str(task_data.get("id", "")).strip_edges()
	if task_id.is_empty():
		return
	for existing in _task_pool:
		if existing is Dictionary and str(existing.get("id", "")).strip_edges() == task_id:
			return
	_task_pool.append(task_data)

func _on_daily_tasks_received(success: bool, data: Variant) -> void:
	_is_loading = false
	print("home_goal_generator: _on_daily_tasks_received called with success=%s" % success)
	print("home_goal_generator: data type=%s, data=%s" % [typeof(data), str(data)])
	
	if not success:
		push_error("home_goal_generator: Failed to fetch daily tasks: %s" % str(data))
		_use_fallback_tasks()
		_load_user_assigned_tasks_from_firebase()
		_refresh_active_tasks()
		_render_daily_goals()
		return

	print("home_goal_generator: Received task data: %s" % str(data))

	# Parse the response: { "tasks": [{"id": "...", "title": "..."}, ...], "timestamp": ... }
	if not data is Dictionary or not data.has("tasks"):
		push_error("home_goal_generator: Invalid response format - not a Dictionary or missing 'tasks' key")
		print("home_goal_generator: data is Dictionary? %s, has tasks? %s" % [data is Dictionary, data.has("tasks") if data is Dictionary else false])
		_use_fallback_tasks()
		_load_user_assigned_tasks_from_firebase()
		_refresh_active_tasks()
		_render_daily_goals()
		return

	var task_list: Array = data["tasks"]
	print("home_goal_generator: task_list type=%s, size=%d" % [typeof(task_list), task_list.size()])
	_task_pool.clear()
	for task in task_list:
		print("home_goal_generator: processing task: %s" % str(task))
		if task is Dictionary and task.has("title") and task.has("id"):
			_append_unique_task({
				"id": str(task["id"]),
				"title": str(task["title"]),
				"coins": max(0, int(task.get("coins", task.get("reward_coins", 0)))),
				"exp": max(0, int(task.get("exp", task.get("xp", task.get("experience", 0))))),
				"is_automated": true
			})
		else:
			print("home_goal_generator: skipping task - not a Dictionary or missing id/title: %s" % str(task))

	if task_list.is_empty() or _task_pool.size() == 0:
		print("home_goal_generator: backend returned no tasks for this user; using fallback tasks")
		_use_fallback_tasks()
		_load_user_assigned_tasks_from_firebase()
		_refresh_active_tasks()
		_render_daily_goals()
		return

	print("home_goal_generator: Loaded %d tasks into pool" % _task_pool.size())
	print("home_goal_generator: User profile for task selection: age=%s, gender=%s, interests=%s" % [
		_user_profile.get("age", "unset"),
		_user_profile.get("gender", "unset"),
		_user_profile.get("interests", [])
	])
	print("home_goal_generator: task_pool contents: %s" % str(_task_pool))
	_load_user_assigned_tasks_from_firebase()
	_refresh_active_tasks()
	_render_daily_goals()

func _resolve_firebase_db() -> Node:
	if get_tree() != null and get_tree().root != null:
		var db: Node = get_tree().root.get_node_or_null("FirebaseRTDB")
		if db != null:
			return db
	if Engine.has_singleton("FirebaseRTDB"):
		return Engine.get_singleton("FirebaseRTDB")
	return null

func _sanitize_firebase_key(value: String) -> String:
	var safe = str(value).strip_edges().to_lower()
	safe = safe.replace("@", "_")
	safe = safe.replace(".", "_")
	safe = safe.replace("#", "_hash_")
	safe = safe.replace("$", "_dollar_")
	safe = safe.replace("[", "_")
	safe = safe.replace("]", "_")
	safe = safe.replace("/", "_")
	safe = safe.replace(" ", "_")
	return safe

func _collect_user_storage_keys() -> Array:
	var keys: Array = []
	var seen: Dictionary = {}
	var raw_values: Array = []
	var user_id: String = _get_current_user_id()
	if user_id.strip_edges() != "" and user_id != "guest_user":
		raw_values.append(user_id)
	var session = get_tree().root.get_node_or_null("UserSession") if get_tree() != null and get_tree().root != null else null
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	if session != null:
		if session.has_method("get_current_user_email"):
			var email: String = str(session.call("get_current_user_email")).strip_edges()
			if email != "":
				raw_values.append(email)
	for value in raw_values:
		var normalized: String = _sanitize_firebase_key(value)
		if normalized != "":
			keys.append(normalized)
		var legacy_variant: String = str(value).strip_edges().to_lower().replace("@", "_at_")
		legacy_variant = legacy_variant.replace(".", "_")
		if legacy_variant != "" and legacy_variant != normalized:
			keys.append(legacy_variant)
	for key in keys:
		if key != "" and not seen.has(key):
			seen[key] = true
	return seen.keys()

func _resolve_realtime_listener() -> Node:
	if get_tree() != null and get_tree().root != null:
		var existing_listener: Node = get_tree().root.get_node_or_null("FirebaseRealtimeListener")
		if existing_listener != null:
			return existing_listener
	if Engine.has_singleton("FirebaseRealtimeListener"):
		return Engine.get_singleton("FirebaseRealtimeListener")
	var new_listener = load("res://firebase_realtime_listener.gd").new()
	if get_tree() != null and get_tree().root != null:
		get_tree().root.add_child.call_deferred(new_listener)
	new_listener.name = "FirebaseRealtimeListener"
	return new_listener

func _setup_assigned_tasks_listener() -> void:
	if _realtime_listener == null:
		return
	if _user_id.strip_edges().is_empty() or _user_id == "guest_user":
		return
	var storage_key: String = _sanitize_firebase_key(_user_id)
	var tasks_path: String = "users/%s/tasks" % storage_key
	_realtime_listener.listen_to_path(tasks_path, Callable(self, "_on_assigned_tasks_realtime_changed"))
	print("home_goal_generator: assigned task listener started for path=", tasks_path)

func _on_assigned_tasks_realtime_changed(tasks_data: Dictionary) -> void:
	if tasks_data is Dictionary:
		var goal_generator: Node = self
		if not goal_generator.has_method("_on_user_assigned_tasks_loaded"):
			goal_generator = _get_goal_generator_controller()
		if goal_generator != null and goal_generator.has_method("_on_user_assigned_tasks_loaded"):
			goal_generator.call("_on_user_assigned_tasks_loaded", true, tasks_data)
		_return_rendered_tasks()

func _load_user_assigned_tasks_from_firebase() -> void:
	var db: Node = _resolve_firebase_db()
	if db == null or not db.has_method("read_json"):
		return
	var keys: Array = _collect_user_storage_keys()
	if keys.is_empty():
		return
	var goal_generator: Node = _get_goal_generator_controller()
	var pending_reads: Array = [keys.size()]
	for storage_key in keys:
		db.read_json("users/%s/tasks" % storage_key, func(_result: int, response_code: int, body: Variant) -> void:
			pending_reads[0] -= 1
			if response_code == 200 and body is Dictionary:
				if goal_generator != null and goal_generator.has_method("_on_user_assigned_tasks_loaded"):
					goal_generator.call("_on_user_assigned_tasks_loaded", true, body)
			if pending_reads[0] <= 0:
				_return_rendered_tasks()
		)

func _get_goal_generator_controller() -> Node:
	var current_scene: Node = get_tree().current_scene if get_tree() != null else null
	if current_scene == null:
		return null
	var goal_generator: Node = current_scene.get_node_or_null("Panel3/GoalGenerator")
	if goal_generator != null:
		return goal_generator
	return self

func _store_assignment_reward(task_id: String, reward_data: Dictionary) -> void:
	if task_id.strip_edges().is_empty() or not reward_data is Dictionary:
		return
	var rewards: Dictionary = _task_state.get("assigned_task_rewards", {})
	if rewards == null:
		rewards = {}
	var normalized: Dictionary = {
		"coins": max(0, int(reward_data.get("coins", 0))),
		"exp": max(0, int(reward_data.get("exp", 0)))
	}
	rewards[task_id] = normalized
	_task_state["assigned_task_rewards"] = rewards

func _on_user_assigned_tasks_loaded(success: bool, data: Variant) -> void:
	if not success or not data is Dictionary:
		return
	var user_tasks: Dictionary = data as Dictionary
	if user_tasks.is_empty():
		return
	var db: Node = _resolve_firebase_db()
	if db == null:
		return
	var seen_ids: Dictionary = {}
	for task in _task_pool:
		if task is Dictionary:
			var task_id: String = str(task.get("id", "")).strip_edges()
			if task_id != "":
				seen_ids[task_id] = true
	for task_key in user_tasks.keys():
		var task_entry: Variant = user_tasks.get(task_key)
		if not task_entry is Dictionary:
			continue
		var task_id: String = str(task_entry.get("task_id", task_key)).strip_edges()
		if task_id.is_empty() or seen_ids.has(task_id):
			continue
		var assigned_value: Variant = task_entry.get("completed", false)
		if assigned_value is bool and bool(assigned_value):
			var completed_assignments: Array = _task_state.get("completed_assigned_task_ids", [])
			if completed_assignments == null:
				completed_assignments = []
			if task_id not in completed_assignments:
				completed_assignments.append(task_id)
			_task_state["completed_assigned_task_ids"] = completed_assignments
			var completed_lookup: Variant = _task_state.get("assigned_task_lookup", {})
			if completed_lookup is Dictionary:
				completed_lookup.erase(task_id)
				_task_state["assigned_task_lookup"] = completed_lookup
			_save_task_state()
			continue
		var task_coins: int = max(0, int(task_entry.get("coins", 0)))
		var task_exp: int = max(0, int(task_entry.get("exp", 0)))
		var task_coins_raw: Variant = task_entry.get("coins", task_entry.get("reward_coins", 0))
		var task_exp_raw: Variant = task_entry.get("exp", task_entry.get("xp", task_entry.get("experience", 0)))
		task_coins = max(0, int(task_coins_raw))
		task_exp = max(0, int(task_exp_raw))
		if task_coins > 0 or task_exp > 0:
			_store_assignment_reward(task_id, {"coins": task_coins, "exp": task_exp})
		var task_description: String = str(task_entry.get("task_title", task_entry.get("title", task_entry.get("description", "")))).strip_edges()
		if task_description.is_empty():
			task_description = str(task_entry.get("text", "")).strip_edges()
		_task_state["assigned_task_lookup"] = _task_state.get("assigned_task_lookup", {})
		var assigned_lookup: Dictionary = _task_state["assigned_task_lookup"] as Dictionary
		if not task_description.is_empty():
			assigned_lookup[task_id] = task_description
			_task_state["assigned_task_lookup"] = assigned_lookup
			if task_coins > 0 or task_exp > 0:
				_store_assignment_reward(task_id, {"coins": task_coins, "exp": task_exp})
			if not _task_pool.any(func(task): return str(task.get("id", "")) == task_id):
				_task_pool.append({"id": task_id, "title": task_description, "coins": task_coins, "exp": task_exp, "is_automated": false})
			else:
				for task in _task_pool:
					if task is Dictionary and str(task.get("id", "")) == task_id:
						task["coins"] = task_coins
						task["exp"] = task_exp
			_continue_after_assigned_sync()
			continue
		db.read_json("admin/tasks/%s" % task_id, func(_result: int, response_code: int, body: Variant) -> void:
			_on_admin_task_detail_loaded(response_code == 200, body, task_id)
		)

func _continue_after_assigned_sync() -> void:
	_return_rendered_tasks()

func _on_admin_task_detail_loaded(success: bool, data: Variant, task_id: String) -> void:
	if success and data is Dictionary:
		var reward_coins: int = max(0, int(data.get("coins", 0)))
		var reward_exp: int = max(0, int(data.get("exp", 0)))
		_store_assignment_reward(task_id, {"coins": reward_coins, "exp": reward_exp})
	var task_title: String = "Admin Assigned Task"
	if success and data is Dictionary:
		task_title = str(data.get("task_title", data.get("title", data.get("description", "Admin Assigned Task")))).strip_edges()
		if task_title.is_empty():
			task_title = str(data.get("title", data.get("description", "Admin Assigned Task"))).strip_edges()
		if task_title.is_empty():
			task_title = str(data.get("description", "Admin Assigned Task")).strip_edges()
		if task_title.is_empty():
			task_title = "Admin Assigned Task"
	else:
		var assignment_lookup: Variant = _task_state.get("assigned_task_lookup", {})
		if assignment_lookup is Dictionary and assignment_lookup.has(task_id):
			task_title = str(assignment_lookup.get(task_id, "")).strip_edges()
		if task_title.is_empty():
			task_title = "Admin Assigned Task"
	if not _task_pool.any(func(task): return str(task.get("id", "")) == task_id):
		_task_pool.append({"id": task_id, "title": task_title, "coins": max(0, int(data.get("coins", 0))) if success and data is Dictionary else 0, "exp": max(0, int(data.get("exp", 0))) if success and data is Dictionary else 0, "is_automated": false})
	else:
		for task in _task_pool:
			if task is Dictionary and str(task.get("id", "")) == task_id:
				task["title"] = task_title
				task["coins"] = max(0, int(data.get("coins", task.get("coins", 0)))) if success and data is Dictionary else task.get("coins", 0)
				task["exp"] = max(0, int(data.get("exp", task.get("exp", 0)))) if success and data is Dictionary else task.get("exp", 0)
	_return_rendered_tasks()

func _return_rendered_tasks() -> void:
	_refresh_active_tasks()
	_render_daily_goals()

func _collect_task_rows(root: Node) -> Array:
	var rows: Array = []
	if root is Button and root.name.find("TaskRow") != -1:
		rows.append(root)
	for child in root.get_children():
		rows += _collect_task_rows(child)
	return rows

func _debug_find_taskrow_nodes() -> void:
	var matches: Array = []
	var stack: Array = []
	if get_tree() == null or get_tree().root == null:
		print("home_goal_generator: _debug_find_taskrow_nodes -> no scene tree available")
		return
	stack.append(get_tree().root)
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n.name.find("TaskRow") != -1:
			matches.append({"path": n.get_path(), "type": str(n.get_class()), "name": n.name})
		for c in n.get_children():
			stack.append(c)

	if matches.size() == 0:
		print("home_goal_generator: _debug_find_taskrow_nodes -> no matches found in root")
	else:
		print("home_goal_generator: _debug_find_taskrow_nodes found %d matches:" % matches.size())
		for m in matches:
			print(" - %s (%s) at %s" % [m.name, m.type, str(m.path)])

func _render_daily_goals() -> void:
	if not is_inside_tree() or get_tree() == null or get_tree().root == null:
		print("home_goal_generator: skipping render because the scene tree is unavailable")
		return
	var tree_root: Node = get_tree().root

	# Prepare a font resource (try Luckiest Guy, fallback to Poppins)
	var goal_dynamic_font = null
	var _goal_font_size: int = 18
	var font_candidates: Array = [
		"res://Luckiest_Guy/LuckiestGuy-Regular.ttf",
		"res://Poppins/Poppins-Regular.ttf",
		"res://Poppins/Poppins-Bold.ttf",
	]
	for fp in font_candidates:
		if ResourceLoader.exists(fp):
			var font_file = load(fp)
			if font_file != null:
				goal_dynamic_font = font_file
				break

	var rows: Array = _collect_task_rows(self)
	# Debug: print current scene and attempt to locate TaskRow nodes in the tree
	if get_tree() != null:
		var cs = get_tree().get_current_scene()
		if cs != null:
			print("home_goal_generator: current_scene = %s (path=%s)" % [str(cs.name), str(cs.get_path())])
		else:
			print("home_goal_generator: current_scene = null")
	_debug_find_taskrow_nodes()
	if rows.size() == 0:
		# Try to find GoalGenerator#GOAL node (which contains the TaskRow buttons)
		var goal_container: Node = tree_root.get_node_or_null("GoalGenerator#GOAL")
		if goal_container != null:
			print("home_goal_generator: Found GoalGenerator#GOAL node, searching for TaskRows inside")
			rows = _collect_task_rows(goal_container)
	
	if rows.size() == 0:
		# If rows aren't direct descendants, search the current scene and other fallbacks silently.
		var scene_root: Node = null
		if has_method("get_tree") and get_tree() != null:
			scene_root = get_tree().get_current_scene()
		if scene_root != null:
			print("home_goal_generator: searching current_scene: %s" % str(scene_root.name))
			rows = _collect_task_rows(scene_root)
		else:
			rows = []
		# last resort: try group-based lookup (works if TaskRow nodes are grouped in the scene)
		if rows.size() == 0 and Engine.has_singleton("SceneTree"):
			var group_nodes: Array = []
			if get_tree() != null:
				group_nodes = get_tree().get_nodes_in_group("GoalTaskRow")
				if group_nodes.size() > 0:
					rows = group_nodes
				else:
					# fallback to searching the entire root
					var child_names: Array = []
					if get_tree() != null and get_tree().root != null:
						for c in get_tree().root.get_children():
							child_names.append(c.name)
					print("home_goal_generator: current_scene children: %s" % str(child_names))
					rows = _collect_task_rows(get_tree().root)
					if rows.size() == 0:
						push_warning("No goal rows found in full scene tree")
						return

	rows.sort_custom(Callable(self, "_compare_buttons_by_top"))

	var completed_task_id: String = ""
	var completed_task_title: String = ""
	if get_tree().root.has_meta("selected_task_data"):
		var selected_task_data: Dictionary = get_tree().root.get_meta("selected_task_data") as Dictionary
		if selected_task_data != null and selected_task_data.has("submitted") and selected_task_data["submitted"] == true:
			if selected_task_data.has("id"):
				completed_task_id = str(selected_task_data["id"])
			if selected_task_data.has("title"):
				completed_task_title = str(selected_task_data["title"])

	if completed_task_id != "" or completed_task_title != "":
		var filtered_tasks: Array = []
		var filtered_ids: Array = []
		for j in range(_current_daily_tasks.size()):
			var task_title: String = _current_daily_tasks[j]
			var task_id: String = _current_task_ids[j] if j < _current_task_ids.size() else ""
			if task_id != "" and task_id == completed_task_id:
				continue
			if task_id == "" and completed_task_title != "" and task_title == completed_task_title:
				continue
			filtered_tasks.append(task_title)
			filtered_ids.append(task_id)
		_current_daily_tasks = filtered_tasks
		_current_task_ids = filtered_ids

	print("home_goal_generator: found %d rows" % rows.size())
	print("home_goal_generator: goals = %s" % str(_current_daily_tasks))
	
	for i in range(rows.size()):
		var btn: Button = rows[i]
		if i >= _current_daily_tasks.size():
			# Clear empty rows instead of leaving stale UI
			btn.text = ""
			btn.disabled = true
			btn.modulate.a = 0.5  # Fade out empty rows
			continue
			
		var truncated_text: String = _truncate_goal_text(_current_daily_tasks[i])
		btn.text = ""
		btn.disabled = false
		btn.modulate.a = 1.0  # Ensure populated rows are visible
		
		# Put the visible goal text in a left-aligned child label inside the button
		var margin: MarginContainer = btn.get_node_or_null("GoalMargin") as MarginContainer
		if margin == null:
			margin = MarginContainer.new()
			margin.name = "GoalMargin"
			margin.anchor_left = 0
			margin.anchor_top = 0
			margin.anchor_right = 1
			margin.anchor_bottom = 1
			margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			margin.size_flags_vertical = Control.SIZE_FILL
			btn.add_child(margin)

		var hbox: HBoxContainer = margin.get_node_or_null("GoalHBox") as HBoxContainer
		if hbox == null:
			hbox = HBoxContainer.new()
			hbox.name = "GoalHBox"
			hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.size_flags_vertical = Control.SIZE_FILL
			margin.add_child(hbox)

		var lbl: Label = hbox.get_node_or_null("GoalText") as Label
		if lbl == null:
			lbl = Label.new()
			lbl.name = "GoalText"
			lbl.clip_text = false
			# Note: Label in this Godot version doesn't support `autowrap` assignment at runtime
			lbl.align = 0
			lbl.valign = 1
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.size_flags_vertical = Control.SIZE_FILL
			lbl.custom_minimum_size = Vector2(0, 36)
			lbl.add_theme_color_override("font_color", Color(0,0,0,1))
			if goal_dynamic_font != null:
				lbl.add_theme_font_override("font", goal_dynamic_font)
			hbox.add_child(lbl)

		# Ensure spacer exists (create if missing)
		var mid_spacer: Control = hbox.get_node_or_null("GoalMidSpacer") as Control
		if mid_spacer == null:
			mid_spacer = Control.new()
			mid_spacer.name = "GoalMidSpacer"
			mid_spacer.custom_minimum_size = Vector2(8, 0)
			mid_spacer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			mid_spacer.size_flags_vertical = Control.SIZE_FILL
			hbox.add_child(mid_spacer)

		# Always update the label text (handle re-renders)
		lbl.text = truncated_text

		# Add a flexible spacer to push the status indicator to the far right
		var right_spacer: Control = hbox.get_node_or_null("GoalRightSpacer") as Control
		if right_spacer == null:
			right_spacer = Control.new()
			right_spacer.name = "GoalRightSpacer"
			right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			right_spacer.size_flags_vertical = Control.SIZE_FILL
			hbox.add_child(right_spacer)

		var status_label: Label = hbox.get_node_or_null("GoalStatus") as Label
		if status_label == null:
			status_label = Label.new()
			status_label.name = "GoalStatus"
			status_label.align = 2
			status_label.valign = 1
			status_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			status_label.size_flags_vertical = Control.SIZE_FILL
			status_label.custom_minimum_size = Vector2(36, 0)
			status_label.add_theme_color_override("font_color", Color(0,0,0,1))
			hbox.add_child(status_label)
		status_label.text = "☐"
		print("home_goal_generator: set button text for row %d -> %s" % [i, _current_daily_tasks[i]])

		if not btn.pressed.is_connected(Callable(self, "_on_goal_pressed").bind(i, _current_daily_tasks[i])):
			btn.pressed.connect(Callable(self, "_on_goal_pressed").bind(i, _current_daily_tasks[i]))

func _resolve_backend() -> Node:
	var backend: Node = get_tree().root.get_node_or_null("HabiBackend")
	if backend != null:
		return backend
	if Engine.has_singleton("HabiBackend"):
		return Engine.get_singleton("HabiBackend")
	return null

func _resolve_firebase_manager() -> Variant:
	var auth_manager: Variant = get_tree().root.get_node_or_null("FirebaseAuthManager")
	if auth_manager != null:
		return auth_manager
	if Engine.has_singleton("FirebaseAuthManager"):
		return Engine.get_singleton("FirebaseAuthManager")
	return null

func _extract_uid_from_token(token: String) -> String:
	var value: String = token.strip_edges()
	if value.begins_with("Bearer "):
		value = value.substr("Bearer ".length()).strip_edges()
	if value.is_empty() or value.count(".") < 2:
		return ""
	var parts: PackedStringArray = value.split(".")
	if parts.size() < 2:
		return ""
	var payload: String = parts[1]
	payload = payload.replace("-", "+").replace("_", "/")
	while payload.length() % 4 != 0:
		payload += "="
	var decoded: String = Marshalls.base64_to_utf8(payload)
	var parsed: Variant = JSON.parse_string(decoded)
	if parsed is Dictionary:
		for key in ["uid", "user_id", "sub"]:
			if parsed.has(key):
				var uid: String = str(parsed.get(key)).strip_edges()
				if uid != "":
					return uid
	return ""

func _get_current_user_id() -> String:
	# Resolve the signed-in identity before any backend call. Support both JWT tokens and local session IDs.
	var candidates: Array = []
	var session = get_tree().root.get_node_or_null("UserSession") if get_tree() != null and get_tree().root != null else null
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	if session != null:
		if session.has_method("get_current_user_token"):
			candidates.append(str(session.call("get_current_user_token")).strip_edges())
		if session.has_method("get_current_user_id"):
			candidates.append(str(session.call("get_current_user_id")).strip_edges())
		if session.has_method("get_current_user_email"):
			candidates.append(str(session.call("get_current_user_email")).strip_edges())

	if Engine.has_singleton("FirebaseAuthManager"):
		var auth = Engine.get_singleton("FirebaseAuthManager")
		if auth != null:
			if auth.has_method("get_current_user_token"):
				candidates.append(str(auth.call("get_current_user_token")).strip_edges())
			if auth.has_method("get_current_user_id"):
				candidates.append(str(auth.call("get_current_user_id")).strip_edges())
			if auth.has_method("get_current_user_email"):
				candidates.append(str(auth.call("get_current_user_email")).strip_edges())
			if auth.has_method("get_current_user"):
				var user = auth.call("get_current_user")
				if user != null and user is Dictionary:
					if user.has("uid"):
						candidates.append(str(user["uid"]).strip_edges())
					if user.has("email"):
						candidates.append(str(user["email"]).strip_edges())

	for candidate in candidates:
		var candidate_value: String = str(candidate).strip_edges()
		if candidate_value.is_empty() or candidate_value == "guest_user":
			continue
		if candidate_value.begins_with("Bearer "):
			candidate_value = candidate_value.substr("Bearer ".length()).strip_edges()
		if candidate_value.begins_with("local:"):
			var local_uid: String = candidate_value.substr("local:".length()).strip_edges()
			if not local_uid.is_empty() and local_uid != "guest_user":
				return local_uid
		var token_uid: String = _extract_uid_from_token(candidate_value)
		if not token_uid.is_empty() and token_uid != "guest_user":
			return token_uid
		if candidate_value.find("@") != -1 or candidate_value.find(".") != -1:
			if candidate_value != "guest_user":
				return candidate_value
			continue
		if candidate_value != "guest_user":
			return candidate_value

	print("home_goal_generator: no authenticated user id available yet; using guest mode")
	return "guest_user"

func _on_goal_pressed(_index: int, goal: String) -> void:
	if get_tree() == null:
		return
	
	var task_id: String = ""
	if _index < _current_task_ids.size():
		task_id = _current_task_ids[_index]

	# Store the selected task and richer metadata for the detail screen. Always prefer the real
	# Firebase reward payload for the assigned task before the scene changes, because the fallback
	# generator can otherwise overwrite the task-by-task reward values.
	var selected_task_data: Dictionary = _build_selected_task_data(goal, task_id)
	var auth_manager: Variant = _resolve_firebase_manager()
	var user_id: String = _get_current_user_id()
	if task_id.strip_edges() != "" and user_id.strip_edges() != "" and user_id != "guest_user" and auth_manager != null and auth_manager.has_method("resolve_task_reward_data"):
		auth_manager.call("resolve_task_reward_data", user_id, task_id, func(ok: bool, reward_data: Variant):
			if ok and reward_data is Dictionary:
				var real_reward: Dictionary = reward_data as Dictionary
				selected_task_data["title"] = str(real_reward.get("title", selected_task_data.get("title", goal))).strip_edges()
				selected_task_data["coins"] = max(0, int(real_reward.get("coins", real_reward.get("reward_coins", selected_task_data.get("coins", 0)))))
				selected_task_data["exp"] = max(0, int(real_reward.get("exp", real_reward.get("xp", real_reward.get("experience", selected_task_data.get("exp", 0))))))
				selected_task_data["id"] = task_id
			get_tree().root.set_meta("selected_task", goal)
			get_tree().root.set_meta("selected_task_data", selected_task_data)
			if get_tree() != null:
				get_tree().change_scene_to_file("res://a_itask.tscn")
		)
		return
	get_tree().root.set_meta("selected_task", goal)
	get_tree().root.set_meta("selected_task_data", selected_task_data)
	get_tree().change_scene_to_file("res://a_itask.tscn")

func _build_selected_task_data(goal: String, task_id: String = "") -> Dictionary:
	var data: Dictionary = {
		"title": goal,
		"estimated_time": "15 mins.",
		"difficulty": "Easy",
		"category": "Academic",
		"coins": 5,
		"exp": 25,
		"id": task_id,
		"is_automated": true
	}

	var reward_state: Variant = _task_state.get("assigned_task_rewards", {})
	var assignment_lookup: Variant = _task_state.get("assigned_task_lookup", {})
	var matched_task_id: String = task_id.strip_edges()
	var preferred_task: Dictionary = {}

	for task in _task_pool:
		if not task is Dictionary:
			continue
		var pool_id: String = str(task.get("id", "")).strip_edges()
		var pool_title: String = str(task.get("title", "")).strip_edges()
		if matched_task_id != "" and pool_id == matched_task_id:
			preferred_task = task
			break
		if pool_title == goal.strip_edges() and pool_id != "":
			if reward_state is Dictionary and reward_state.has(pool_id):
				preferred_task = task
				break
			if preferred_task.is_empty():
				preferred_task = task

	if preferred_task.size() > 0:
		data["title"] = str(preferred_task.get("title", goal))
		data["id"] = str(preferred_task.get("id", task_id)).strip_edges()
		data["is_automated"] = bool(preferred_task.get("is_automated", true))
		data["coins"] = max(0, int(preferred_task.get("coins", data["coins"])))
		data["exp"] = max(0, int(preferred_task.get("exp", data["exp"])))
		matched_task_id = data["id"]

	if matched_task_id == "" and goal.strip_edges() != "" and assignment_lookup is Dictionary:
		for assigned_id in assignment_lookup.keys():
			var assigned_title: String = str(assignment_lookup.get(assigned_id, "")).strip_edges()
			if assigned_title == goal.strip_edges():
				matched_task_id = str(assigned_id).strip_edges()
				data["id"] = matched_task_id
				data["is_automated"] = false
				break

	if matched_task_id != "":
		if reward_state is Dictionary and reward_state.has(matched_task_id):
			var stored_reward: Dictionary = reward_state.get(matched_task_id, {}) as Dictionary
			if stored_reward != null:
				data["coins"] = max(0, int(stored_reward.get("coins", data["coins"])))
				data["exp"] = max(0, int(stored_reward.get("exp", data["exp"])))
				data["title"] = str(assignment_lookup.get(matched_task_id, data["title"])) if assignment_lookup is Dictionary else data["title"]
				if data["title"].strip_edges().is_empty():
					data["title"] = goal

	if data["id"].strip_edges() == "" and goal.strip_edges() != "":
		for task in _task_pool:
			if task is Dictionary and str(task.get("title", "")).strip_edges() == goal.strip_edges():
				var pool_id: String = str(task.get("id", "")).strip_edges()
				if reward_state is Dictionary and reward_state.has(pool_id):
					data["id"] = pool_id
					var stored_reward: Dictionary = reward_state.get(pool_id, {}) as Dictionary
					data["coins"] = max(0, int(stored_reward.get("coins", data["coins"])))
					data["exp"] = max(0, int(stored_reward.get("exp", data["exp"])))
					break

	var lower_goal: String = goal.to_lower()
	# First, try to parse any explicit time mention like "10 mins" or "1 hour"
	var minutes: int = 0
	var re_hours := RegEx.new()
	if re_hours.compile("(\\d{1,3})\\s*(hours|hour|hrs|hr)") == OK:
		var m = re_hours.search(lower_goal)
		if m != null:
			minutes = int(m.get_string(1)) * 60
	if minutes == 0:
		var re_mins := RegEx.new()
		if re_mins.compile("(\\d{1,3})\\s*(minutes|minute|mins|min)") == OK:
			var m2 = re_mins.search(lower_goal)
			if m2 != null:
				minutes = int(m2.get_string(1))

	# If no explicit time, use heuristics based on keywords
	if minutes == 0:
		if lower_goal.find("pray") != -1 or lower_goal.find("bible") != -1 or lower_goal.find("verse") != -1 or lower_goal.find("church") != -1 or lower_goal.find("worship") != -1 or lower_goal.find("reflection") != -1:
			minutes = 10
			data["difficulty"] = "Easy"
			data["category"] = "Religion"
		elif lower_goal.find("read") != -1 or lower_goal.find("study") != -1 or lower_goal.find("learn") != -1:
			minutes = 20
			data["difficulty"] = "Easy"
			data["category"] = "Academic"
		elif lower_goal.find("write") != -1 or lower_goal.find("journal") != -1 or lower_goal.find("reflect") != -1:
			minutes = 15
			data["difficulty"] = "Easy"
			data["category"] = "Academic"
		elif lower_goal.find("serve") != -1 or lower_goal.find("help") != -1 or lower_goal.find("share") != -1:
			minutes = 25
			data["difficulty"] = "Medium"
			data["category"] = "Service"
		elif lower_goal.find("exercise") != -1 or lower_goal.find("walk") != -1 or lower_goal.find("run") != -1:
			minutes = 30
			data["difficulty"] = "Medium"
			data["category"] = "Health"
		else:
			# fallback default
			minutes = 15

	# Format estimated time string
	if minutes >= 60 and minutes % 60 == 0:
		var hours: int = int(float(minutes) / 60.0)
		data["estimated_time"] = "%d hour%s." % [hours, "" if hours == 1 else "s"]
	elif minutes >= 60:
		data["estimated_time"] = "%d mins." % minutes
	else:
		data["estimated_time"] = "%d mins." % minutes

	var has_real_reward_override: bool = false
	if matched_task_id != "" and reward_state is Dictionary and reward_state.has(matched_task_id):
		has_real_reward_override = true
	elif preferred_task is Dictionary:
		var preferred_coins: int = max(0, int(preferred_task.get("coins", 0)))
		var preferred_exp: int = max(0, int(preferred_task.get("exp", 0)))
		if preferred_coins > 0 or preferred_exp > 0:
			has_real_reward_override = true

	if not has_real_reward_override:
		# Compute reward split into coins and exp (coins ~= minutes/2 rounded)
		var base_points: int = max(1, int(round(float(minutes) / 2.0)))
		if data.has("difficulty"):
			match data["difficulty"]:
				"Easy": base_points = max(base_points, 5)
				"Medium": base_points = max(base_points, 10)
				"Hard": base_points = max(base_points, 20)

		# category adjustments
		if data["category"].to_lower().find("service") != -1:
			base_points += 5
		if lower_goal.find("pray") != -1 or lower_goal.find("bible") != -1:
			base_points += 2

		data["coins"] = base_points
		data["exp"] = base_points * 5
	else:
		data["coins"] = max(0, int(data.get("coins", 0)))
		data["exp"] = max(0, int(data.get("exp", 0)))

	return data

func _on_task_marked_complete(success: bool, data: Variant) -> void:
	if success:
		print("home_goal_generator: Task marked as complete")
	else:
		print("home_goal_generator: Failed to mark task as complete: %s" % str(data))

func _apply_completed_task_from_meta() -> void:
	if not get_tree().root.has_meta("selected_task_data"):
		return

	var selected_task_data: Dictionary = get_tree().root.get_meta("selected_task_data") as Dictionary
	if selected_task_data == null or not selected_task_data.has("submitted") or selected_task_data["submitted"] != true:
		return

	var task_id: String = str(selected_task_data.get("id", "")).strip_edges()
	if task_id != "":
		var completed_ids: Array = _task_state.get("completed_task_ids", [])
		if completed_ids == null:
			completed_ids = []
		if task_id not in completed_ids:
			completed_ids.append(task_id)
			_task_state["completed_task_ids"] = completed_ids
			var completed_titles: Dictionary = _task_state.get("completed_task_titles", {})
			if completed_titles == null:
				completed_titles = {}
			completed_titles[task_id] = str(selected_task_data.get("title", task_id))
			_task_state["completed_task_titles"] = completed_titles
			var reward_coins: int = max(0, int(selected_task_data.get("coins", 0)))
			var reward_exp: int = max(0, int(selected_task_data.get("exp", 0)))
			var completed_assigned_ids: Array = _task_state.get("completed_assigned_task_ids", [])
			if completed_assigned_ids == null:
				completed_assigned_ids = []
			if not task_id.begins_with("generated_") and task_id not in completed_assigned_ids:
				completed_assigned_ids.append(task_id)
				_task_state["completed_assigned_task_ids"] = completed_assigned_ids
			var active_ids: Array = _task_state.get("active_task_ids", [])
			if active_ids is Array and task_id in active_ids:
				active_ids.erase(task_id)
				_task_state["active_task_ids"] = active_ids
			var assigned_lookup: Variant = _task_state.get("assigned_task_lookup", {})
			if assigned_lookup is Dictionary and assigned_lookup.has(task_id):
				assigned_lookup.erase(task_id)
				_task_state["assigned_task_lookup"] = assigned_lookup
			for task_index in range(_task_pool.size() - 1, -1, -1):
				if task_index < _task_pool.size() and str(_task_pool[task_index].get("id", "")) == task_id and not task_id.begins_with("generated_"):
					_task_pool.remove_at(task_index)
					break
			_save_task_state()
			print("home_goal_generator: recorded completed task id", task_id, "coins earned=", reward_coins, "EXP earned=", reward_exp)

	get_tree().root.remove_meta("selected_task_data")

func _current_day_key() -> String:
	var date_dict: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [date_dict.get("year", 2000), date_dict.get("month", 1), date_dict.get("day", 1)]

func _get_current_unix_time() -> int:
	return int(Time.get_unix_time_from_system())

func _load_task_state() -> Dictionary:
	var state: Dictionary = {}
	var state_path: String = _task_state_path()
	if not FileAccess.file_exists(state_path):
		return state

	var file = FileAccess.open(state_path, FileAccess.READ)
	if file == null:
		return state

	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		state = parsed
	return state

func _save_task_state() -> void:
	var file = FileAccess.open(_task_state_path(), FileAccess.WRITE)
	if file == null:
		push_warning("home_goal_generator: failed to open task state file for writing")
		return
	file.store_string(JSON.stringify(_task_state))
	file.close()

func _task_state_path() -> String:
	var safe_user_id: String = _user_id.strip_edges().to_lower()
	if safe_user_id.is_empty():
		safe_user_id = "guest_user"
	for character in ["@", ".", "#", "$", "[", "]", " "]:
		safe_user_id = safe_user_id.replace(character, "_")
	return TASK_STATE_PATH_PREFIX + safe_user_id + ".json"

func _refresh_active_tasks() -> void:
	var now: int = _get_current_unix_time()
	var last_refresh: int = int(_task_state.get("last_refresh_time", 0))
	var last_refresh_date: String = str(_task_state.get("last_refresh_date", "")).strip_edges()
	var current_day_key: String = _current_day_key()
	var completed_ids: Array = _task_state.get("completed_task_ids", [])
	if completed_ids == null:
		completed_ids = []
	var completed_assigned_ids: Array = _task_state.get("completed_assigned_task_ids", [])
	if completed_assigned_ids == null:
		completed_assigned_ids = []

	var persisted_titles: Dictionary = _task_state.get("active_task_titles", {})
	var assigned_titles: Variant = _task_state.get("assigned_task_lookup", {})
	if persisted_titles is Dictionary:
		for persisted_id in persisted_titles.keys():
			var persisted_title: String = str(persisted_titles.get(persisted_id, "")).strip_edges()
			if not persisted_title.is_empty() and str(persisted_id) not in completed_ids and str(persisted_id) not in completed_assigned_ids:
				_append_task_to_pool(str(persisted_id), persisted_title)
	if assigned_titles is Dictionary:
		for assigned_id in assigned_titles.keys():
			var assigned_title: String = str(assigned_titles.get(assigned_id, "")).strip_edges()
			if not assigned_title.is_empty() and str(assigned_id) not in completed_ids and str(assigned_id) not in completed_assigned_ids:
				_append_task_to_pool(str(assigned_id), assigned_title)

	var reached_daily_rollover: bool = last_refresh_date.is_empty() or last_refresh_date != current_day_key
	var reached_time_window: bool = last_refresh == 0 or (now - last_refresh) >= REFILL_HOURS * 3600
	if reached_daily_rollover or reached_time_window:
		print("home_goal_generator: daily refresh or time window reached, resetting completed tasks")
		completed_ids.clear()
		_task_state["completed_task_ids"] = completed_ids
		_task_state["completed_task_titles"] = {}
		_task_state["last_refresh_time"] = now
		_task_state["last_refresh_date"] = current_day_key

	var active_ids: Array = _task_state.get("active_task_ids", [])
	if active_ids == null:
		active_ids = []

	# Remove completed tasks from active list.
	for completed_id in completed_ids.duplicate():
		if completed_id in active_ids:
			active_ids.erase(completed_id)
	for completed_assignment_id in completed_assigned_ids:
		if completed_assignment_id in active_ids:
			active_ids.erase(completed_assignment_id)

	# Ensure active IDs are valid and unique
	var valid_active_ids: Array = []
	for id in active_ids:
		if id == "":
			continue
		if id in valid_active_ids:
			continue
		for task in _task_pool:
			if task["id"] == id:
				valid_active_ids.append(id)
				break
	active_ids = valid_active_ids

	# Fill the active task slots from the available pool.
	for task in _task_pool:
		if active_ids.size() >= MAX_ACTIVE_TASKS:
			break
		if task["id"] in active_ids:
			continue
		if task["id"] in completed_ids:
			continue
		if task["id"] in completed_assigned_ids:
			continue
		active_ids.append(task["id"])

	_task_state["active_task_ids"] = active_ids
	var active_titles: Dictionary = {}
	for task in _task_pool:
		if task["id"] in active_ids and task["id"] not in completed_ids:
			active_titles[str(task["id"])] = str(task["title"])
	_task_state["active_task_titles"] = active_titles
	_task_state["last_refresh_time"] = now
	_save_task_state()

	print("home_goal_generator: refresh_active_tasks -> active_ids=%s completed_ids=%s" % [str(active_ids), str(completed_ids)])

	_active_tasks.clear()
	for task in _task_pool:
		if task["id"] in active_ids:
			_active_tasks.append(task)

	print("home_goal_generator: active_tasks (full)=%s" % str(_active_tasks))

	_current_daily_tasks.clear()
	_current_task_ids.clear()
	for task in _active_tasks:
		_current_daily_tasks.append(str(task["title"]))
		_current_task_ids.append(str(task["id"]))

	print("home_goal_generator: current_daily_tasks=%s" % str(_current_daily_tasks))
	print("home_goal_generator: current_task_ids=%s" % str(_current_task_ids))
	print("home_goal_generator: active_ids=%s" % str(active_ids))

func _append_task_to_pool(task_id: String, task_title: String) -> void:
	if task_id.is_empty() or task_title.is_empty():
		return
	for task in _task_pool:
		if task is Dictionary and str(task.get("id", "")) == task_id:
			return
	_task_pool.append({
		"id": task_id,
		"title": task_title,
		"is_automated": false
	})

func force_refresh_tasks() -> void:
	# Manually trigger a refresh of the task pool before 24 hours
	print("home_goal_generator: Force refreshing task pool")
	_is_loading = true
	if Engine.has_singleton("HabiBackend"):
		var backend = Engine.get_singleton("HabiBackend")
		backend.refresh_task_pool(_user_id, Callable(self, "_on_daily_tasks_received"))
	else:
		_is_loading = false
		push_error("home_goal_generator: HabiBackend singleton not found")

func _goal_store_path() -> String:
	# Kept for backwards compatibility, but no longer used with Firebase backend
	return "user://daily_goal.json"

func _load_goal_data() -> Dictionary:
	# Kept for backwards compatibility, but no longer used with Firebase backend
	# Tasks are now fetched from Firebase via the backend API
	return {}

func _truncate_goal_text(goal: String, max_chars: int = GOAL_TEXT_TRUNCATE_CHARS) -> String:
	if goal.length() <= max_chars:
		return goal
	var truncated = goal.substr(0, max_chars)
	truncated = truncated.strip_edges(false, true)
	return truncated + "..."

func _compare_buttons_by_top(a: Button, b: Button) -> int:
	return int(a.position.y - b.position.y)

func _save_goal_data(_goals: Array, _timestamp: int) -> void:
	# Kept for backwards compatibility, but no longer used with Firebase backend
	# All persistence is now handled by the backend API
	pass
