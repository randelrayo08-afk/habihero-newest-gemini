extends Node

# Admin helper for:
# - Journal entry viewing (who submitted what)
# - Mood tracking data
# - User level and experience progression
# - Chat/Conversation viewing and management

var _db: Node
var _auth_manager: Node

func _ready() -> void:
	_resolve_db()
	_resolve_auth_manager()

func _resolve_db() -> void:
	if _db != null:
		return
	if get_tree() != null and get_tree().root != null:
		_db = get_tree().root.get_node_or_null("FirebaseRTDB")
	if _db == null and Engine.has_singleton("FirebaseRTDB"):
		_db = Engine.get_singleton("FirebaseRTDB")

func _resolve_auth_manager() -> void:
	if _auth_manager != null:
		return
	if get_tree() != null and get_tree().root != null:
		_auth_manager = get_tree().root.get_node_or_null("FirebaseAuthManager")
	if _auth_manager == null and Engine.has_singleton("FirebaseAuthManager"):
		_auth_manager = Engine.get_singleton("FirebaseAuthManager")

func get_all_journal_entries(callback: Callable = Callable()) -> void:
	"""Retrieve all journal entries from all users (admin only)"""
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(false, {})
		return
	
	_db.read_json("users", func(result: int, response_code: int, body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if not ok or body == null or not body is Dictionary:
			if callback.is_valid():
				callback.call(false, {})
			return
		
		var all_entries: Dictionary = {}
		var users: Dictionary = body as Dictionary
		
		for user_key in users.keys():
			var user_data: Variant = users.get(user_key)
			if user_data is Dictionary and user_data.has("journal"):
				var journals: Variant = user_data.get("journal")
				if journals is Dictionary:
					all_entries[user_key] = journals
		
		if callback.is_valid():
			callback.call(true, all_entries)
	)

func get_user_journals(user_identifier: String, callback: Callable = Callable()) -> void:
	"""Retrieve all journals for a specific user"""
	if _auth_manager == null:
		if callback.is_valid():
			callback.call(false, {})
		return
	
	_auth_manager.load_journal_entries(user_identifier, callback)

func get_all_mood_entries(callback: Callable = Callable()) -> void:
	"""Retrieve all mood entries from all users for mood tracking analysis"""
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(false, {})
		return
	
	_db.read_json("users", func(result: int, response_code: int, body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if not ok or body == null or not body is Dictionary:
			if callback.is_valid():
				callback.call(false, {})
			return
		
		var all_moods: Dictionary = {}
		var users: Dictionary = body as Dictionary
		
		for user_key in users.keys():
			var user_data: Variant = users.get(user_key)
			if user_data is Dictionary and user_data.has("moodcheck"):
				var moods: Variant = user_data.get("moodcheck")
				if moods is Dictionary:
					all_moods[user_key] = moods
		
		if callback.is_valid():
			callback.call(true, all_moods)
	)

func get_user_level_and_exp(user_identifier: String, callback: Callable = Callable()) -> void:
	"""Get a user's current level and experience"""
	if _auth_manager == null:
		if callback.is_valid():
			callback.call(false, {"level": 1, "experience": 0})
		return
	
	_auth_manager.load_profile(user_identifier, func(ok: bool, profile: Variant):
		if ok and profile is Dictionary:
			var stats: Dictionary = {
				"level": max(1, int(profile.get("level", 1))),
				"experience": max(0, int(profile.get("experience", 0))),
				"checkin_streak": max(0, int(profile.get("checkin_streak", 0))),
				"last_checkin_date": str(profile.get("last_checkin_date", ""))
			}
			if callback.is_valid():
				callback.call(true, stats)
		else:
			if callback.is_valid():
				callback.call(false, {})
	)

func export_journal_report(output_path: String = "user://journal_report.txt") -> void:
	"""Export all journals to a text file for admin review"""
	get_all_journal_entries(func(ok: bool, all_entries: Variant):
		if not ok or all_entries == null or not all_entries is Dictionary:
			push_error("AdminHelper: Failed to retrieve journal entries")
			return
		
		var report_text: String = "=== JOURNAL SUBMISSIONS REPORT ===\n"
		report_text += "Generated: " + Time.get_datetime_string_from_system(false, true) + "\n"
		report_text += "==================================================\n\n"
		
		var entries_dict: Dictionary = all_entries as Dictionary
		for user_key in entries_dict.keys():
			var user_journals: Variant = entries_dict.get(user_key)
			if user_journals is Dictionary:
				report_text += "\n--- USER: " + user_key + " ---\n"
				
				var journal_keys: Array = (user_journals as Dictionary).keys()
				# Sort by timestamp descending (newest first)
				journal_keys.sort_custom(func(a, b): return str(a) > str(b))
				
				for key in journal_keys:
					var entry: Variant = (user_journals as Dictionary).get(key)
					if entry is Dictionary:
						var created_at: String = str(entry.get("created_at", "Unknown"))
						var text: String = str(entry.get("entry", "(empty)"))
						report_text += "\n[" + created_at + "]\n" + text + "\n"
				
				report_text += "\n--------------------------------------------------\n"
		
		var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if file != null:
			file.store_string(report_text)
			print("AdminHelper: Journal report exported to ", output_path)
			print("Total users with entries: ", entries_dict.size())
		else:
			push_error("AdminHelper: Failed to write journal report to ", output_path)
	)

# ═══════════════════════════════════════════════════════════════
# CHAT/CONVERSATION ADMIN FUNCTIONS
# ═══════════════════════════════════════════════════════════════

func _normalize_message_bucket(messages_value: Variant) -> Dictionary:
	"""Return a safe dictionary of message objects for admin-side reads."""
	var normalized: Dictionary = {}
	if messages_value is Dictionary:
		var source: Dictionary = messages_value as Dictionary
		for key in source.keys():
			var value: Variant = source.get(key)
			if value is Dictionary:
				var msg: Dictionary = value as Dictionary
				var msg_id: String = str(msg.get("id", key))
				normalized[msg_id] = msg
	return normalized

func _collect_legacy_message_entries(payload: Dictionary) -> Dictionary:
	"""Convert legacy message keys like messages/msg_123 into a normal message bucket."""
	var normalized: Dictionary = {}
	for key in payload.keys():
		if key == "messages":
			continue
		var value: Variant = payload.get(key)
		if value is Dictionary:
			var msg: Dictionary = value as Dictionary
			if msg.has("message") or msg.has("senderId") or msg.has("conversationId"):
				var msg_id: String = str(msg.get("id", key))
				normalized[msg_id] = msg
			elif key.begins_with("messages/"):
				var msg_key: String = key.substr("messages/".length())
				if not msg_key.is_empty() and value is Dictionary:
					var message_map: Dictionary = value as Dictionary
					var legacy_id: String = str(message_map.get("id", msg_key))
					normalized[legacy_id] = message_map
	return normalized

func get_all_conversations(callback: Callable = Callable()) -> void:
	"""Retrieve all student conversations for admin review"""
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(false, {})
		return
	
	_db.read_json("conversations", func(result: int, response_code: int, body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if not ok or body == null or not body is Dictionary:
			if callback.is_valid():
				callback.call(false, {})
			return
		
		var conversations: Dictionary = body as Dictionary
		for conv_id in conversations.keys():
			var conv: Variant = conversations.get(conv_id)
			if conv is Dictionary:
				var conv_map: Dictionary = conv as Dictionary
				var bucket: Dictionary = _normalize_message_bucket(conv_map.get("messages", {}))
				var legacy_bucket: Dictionary = _collect_legacy_message_entries(conv_map)
				for msg_id in legacy_bucket.keys():
					bucket[msg_id] = legacy_bucket.get(msg_id)
				conv_map["messages"] = bucket
				if not conv_map.has("userName") and conv_map.has("userId"):
					conv_map["userName"] = _conversation_display_name(conv_map)
		
		# Also get messages from top-level path to populate conversations
		_db.read_json("messages", func(msg_result: int, msg_response_code: int, msg_body: Variant):
			# Merge messages into their respective conversations
			if msg_result == OK and msg_response_code >= 200 and msg_response_code < 300 and msg_body is Dictionary:
				var all_messages: Dictionary = msg_body as Dictionary
				for msg_id in all_messages.keys():
					var msg: Variant = all_messages.get(msg_id)
					if msg is Dictionary:
						var msg_map: Dictionary = msg as Dictionary
						var conv_id: String = str(msg_map.get("conversationId", ""))
						if not conv_id.is_empty() and conversations.has(conv_id):
							var conv: Variant = conversations.get(conv_id)
							if conv is Dictionary:
								var conv_map: Dictionary = conv as Dictionary
								var bucket: Dictionary = _normalize_message_bucket(conv_map.get("messages", {}))
								var message_id: String = str(msg_map.get("id", msg_id))
								bucket[message_id] = msg_map
								conv_map["messages"] = bucket
								if not conv_map.has("userName") and conv_map.has("userId"):
									conv_map["userName"] = _conversation_display_name(conv_map)
			
			if callback.is_valid():
				callback.call(true, conversations)
		)
	)

func get_conversation_details(conversation_id: String, callback: Callable = Callable()) -> void:
	"""Get full details of a specific conversation with all messages"""
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(false, {})
		return
	
	_db.read_json("conversations/%s" % conversation_id, func(result: int, response_code: int, body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if not ok or body == null or not body is Dictionary:
			if callback.is_valid():
				callback.call(false, {})
			return
		
		# If conversation has nested messages, ensure they're properly structured
		var conversation_data: Dictionary = body as Dictionary
		_normalize_conversation_for_admin(conversation_data)
		_db.read_json("messages", func(msg_result: int, msg_response_code: int, msg_body: Variant):
			if msg_result == OK and msg_response_code >= 200 and msg_response_code < 300 and msg_body is Dictionary:
				var all_messages: Dictionary = msg_body as Dictionary
				var conv_messages: Dictionary = _normalize_message_bucket(conversation_data.get("messages", {}))
				for msg_id in all_messages.keys():
					var msg: Variant = all_messages.get(msg_id)
					if msg is Dictionary and str((msg as Dictionary).get("conversationId", "")) == conversation_id:
						var msg_map: Dictionary = msg as Dictionary
						conv_messages[str(msg_map.get("id", msg_id))] = msg_map
				conversation_data["messages"] = conv_messages
				var display: String = _conversation_display_name(conversation_data)
				if display != "":
					conversation_data["userName"] = display
					conversation_data["displayName"] = display
					conversation_data["studentName"] = display
			if callback.is_valid():
				callback.call(true, conversation_data)
		)
	)

func send_admin_reply(conversation_id: String, student_id: String, reply_text: String, callback: Callable = Callable()) -> void:
	"""Admin sends a reply message to a student"""
	if _db == null or not _db.has_method("write_json"):
		if callback.is_valid():
			callback.call(false, "Database not available")
		return
	
	var msg_id: String = "msg_%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	var now_iso: String = Time.get_datetime_string_from_system(false, true)
	
	var reply_message: Dictionary = {
		"id": msg_id,
		"conversationId": conversation_id,
		"senderId": "admin_1",
		"receiverId": student_id,
		"message": reply_text,
		"timestamp": now_iso,
		"read": false,
		"type": "text"
	}
	
	# Keep messages nested under the `messages` object so admin and student clients can read it reliably.
	var conv_updates: Dictionary = {
		"lastMessage": reply_text,
		"lastMessageAt": now_iso,
		"messages": {
			msg_id: reply_message
		}
	}
	
	_db.update_json("conversations/%s" % conversation_id, conv_updates, func(result: int, response_code: int, _body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if not ok:
			if callback.is_valid():
				callback.call(false, "Failed to update conversation with message")
			return
		
		# Also write to /messages/{msgId} for admin dashboard retrieval
		_db.write_json("messages/%s" % msg_id, reply_message, func(result2: int, response_code2: int, _body2: Variant):
			var ok2: bool = result2 == OK and response_code2 >= 200 and response_code2 < 300
			if callback.is_valid():
				callback.call(ok2, reply_message)
		)
	)

# ═══════════════════════════════════════════════════════════════
# TASK MANAGEMENT ADMIN FUNCTIONS
# ═══════════════════════════════════════════════════════════════

func create_task(title: String, description: String = "", category: String = "Academic", difficulty: String = "Easy", estimated_time: String = "15 mins", coins_reward: int = 10, exp_reward: int = 25, callback: Callable = Callable()) -> void:
	"""Create a new task in the admin section"""
	if _db == null or not _db.has_method("write_json"):
		if callback.is_valid():
			callback.call(false, "Database not available")
		return
	
	var task_id: String = "task_%s_%d" % [_sanitize_path(title), Time.get_ticks_msec()]
	var task_data: Dictionary = {
		"id": task_id,
		"title": title,
		"description": description,
		"category": category,
		"difficulty": difficulty,
		"estimated_time": estimated_time,
		"coins": coins_reward,
		"exp": exp_reward,
		"created_at": Time.get_datetime_string_from_system(false, true),
		"status": "active",
		"assigned_to": []  # Array of user IDs
	}
	
	_db.write_json("admin/tasks/%s" % task_id, task_data, func(result: int, response_code: int, _body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if callback.is_valid():
			callback.call(ok, task_data if ok else {})
	)

func assign_task_to_user(task_id: String, user_id: String, callback: Callable = Callable()) -> void:
	"""Assign an existing task to a specific user"""
	if _db == null or not _db.has_method("read_json") or not _db.has_method("write_json"):
		if callback.is_valid():
			callback.call(false)
		return
	
	_db.read_json("admin/tasks/%s" % task_id, func(result: int, response_code: int, admin_task: Variant):
		var task_rewards: Dictionary = {"coins": 0, "exp": 0}
		if result == OK and response_code >= 200 and response_code < 300 and admin_task is Dictionary:
			task_rewards = {
				"coins": max(0, int(admin_task.get("coins", 0))),
				"exp": max(0, int(admin_task.get("exp", 0)))
			}
		var storage_key = _sanitize_path(user_id)
		var assignment: Dictionary = {
			"task_id": task_id,
			"assigned_at": Time.get_datetime_string_from_system(false, true),
			"completed": false,
			"completion_date": "",
			"coins": task_rewards["coins"],
			"exp": task_rewards["exp"],
			"task_title": admin_task.get("title", "") if admin_task is Dictionary else ""
		}
		_db.write_json("users/%s/tasks/%s" % [storage_key, task_id], assignment, func(write_result: int, write_code: int, _body: Variant):
			var ok: bool = write_result == OK and write_code >= 200 and write_code < 300
			if ok:
				_send_task_assigned_notification(user_id, task_id)
			if callback.is_valid():
				callback.call(ok)
		)
	)

func assign_task_to_all_users(task_id: String, callback: Callable = Callable()) -> void:
	"""Broadcast a task to all users"""
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(false)
		return
	
	# First, get all users
	_db.read_json("users", func(_result: int, response_code: int, body: Variant):
		if response_code != 200 or body == null or not body is Dictionary:
			if callback.is_valid():
				callback.call(false)
			return
		
		var users_dict: Dictionary = body as Dictionary
		var assignment_results: Array = []
		var total_users: int = users_dict.keys().size()
		
		for user_key in users_dict.keys():
			assign_task_to_user(task_id, user_key, func(ok: bool):
				assignment_results.append(ok)
				if assignment_results.size() == total_users:
					# All assignments attempted
					var successful: int = assignment_results.filter(func(b): return b == true).size()
					if callback.is_valid():
						callback.call(true, {"assigned": successful, "total": total_users})
			)
	)

func get_all_tasks(callback: Callable = Callable()) -> void:
	"""Retrieve all admin-created tasks"""
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(false, {})
		return
	
	_db.read_json("admin/tasks", func(result: int, response_code: int, body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		var tasks: Dictionary = {}
		if ok and body is Dictionary:
			tasks = body as Dictionary
		
		if callback.is_valid():
			callback.call(ok, tasks)
	)

func get_user_tasks(user_id: String, callback: Callable = Callable()) -> void:
	"""Retrieve all tasks assigned to a specific user"""
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(false, {})
		return
	
	var storage_key = _sanitize_path(user_id)
	_db.read_json("users/%s/tasks" % storage_key, func(result: int, response_code: int, body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		var tasks: Dictionary = {}
		if ok and body is Dictionary:
			tasks = body as Dictionary
		
		if callback.is_valid():
			callback.call(ok, tasks)
	)

func get_task_completions(task_id: String, callback: Callable = Callable()) -> void:
	"""Get all user completions for a specific task"""
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(false, {})
		return
	
	# Read all users and check if they completed this task
	_db.read_json("users", func(_result: int, response_code: int, body: Variant):
		if response_code != 200 or body == null or not body is Dictionary:
			if callback.is_valid():
				callback.call(false, {})
			return
		
		var completions: Dictionary = {}
		var users_dict: Dictionary = body as Dictionary
		
		for user_id in users_dict.keys():
			var user_data: Variant = users_dict.get(user_id)
			if user_data is Dictionary and user_data.has("tasks"):
				var tasks: Variant = user_data.get("tasks")
				if tasks is Dictionary and tasks.has(task_id):
					var task: Variant = tasks.get(task_id)
					if task is Dictionary and task.get("completed", false):
						completions[user_id] = task
		
		if callback.is_valid():
			callback.call(true, completions)
	)

func mark_task_complete(user_id: String, task_id: String, proof: Dictionary = {}, callback: Callable = Callable()) -> void:
	"""Mark a task as complete for a user"""
	if _db == null or not _db.has_method("update_json"):
		if callback.is_valid():
			callback.call(false)
		return
	
	var storage_key = _sanitize_path(user_id)
	var update: Dictionary = {
		"completed": true,
		"completion_date": Time.get_datetime_string_from_system(false, true)
	}
	
	# Add proof if provided
	if proof.size() > 0:
		update["proof"] = proof
	
	_db.update_json("users/%s/tasks/%s" % [storage_key, task_id], update, func(result: int, response_code: int, _body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if callback.is_valid():
			callback.call(ok)
	)

func delete_task(task_id: String, callback: Callable = Callable()) -> void:
	"""Delete a task from the admin section"""
	if _db == null or not _db.has_method("delete_path"):
		if callback.is_valid():
			callback.call(false)
		return
	
	_db.delete_path("admin/tasks/%s" % task_id, func(result: int, response_code: int, _body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if callback.is_valid():
			callback.call(ok)
	)

func _send_task_assigned_notification(user_id: String, task_id: String) -> void:
	"""Send a notification when a task is assigned to a user"""
	if _db == null or not _db.has_method("write_json"):
		return
	
	var storage_key = _sanitize_path(user_id)
	var notif_data: Dictionary = {
		"id": "notif_%s_%d" % [task_id, Time.get_ticks_msec()],
		"type": "task_assigned",
		"task_id": task_id,
		"title": "New Task Assigned",
		"message": "A new task has been assigned to you!",
		"created_at": Time.get_datetime_string_from_system(false, true),
		"read": false
	}
	
	_db.write_json("users/%s/notifications/%s" % [storage_key, notif_data["id"]], notif_data, func(_r, _c, _b):
		print("Task assigned notification sent to user: %s" % user_id)
	)

func _sanitize_path(value: String) -> String:
	"""Sanitize path for Firebase"""
	var safe = str(value).strip_edges().to_lower()
	safe = safe.replace("@", "_")
	safe = safe.replace(".", "_")
	safe = safe.replace("#", "_hash_")
	safe = safe.replace("$", "_dollar_")
	safe = safe.replace("[", "_")
	safe = safe.replace("]", "_")
	safe = safe.replace("/", "_")
	return safe

func export_conversations_report(output_path: String = "user://conversations_report.txt") -> void:
	"""Export all conversations and messages to a text file"""
	get_all_conversations(func(ok: bool, all_convs: Variant):
		if not ok or all_convs == null or not all_convs is Dictionary:
			push_error("AdminHelper: Failed to retrieve conversations")
			return
		
		var report_text: String = "=== CONVERSATIONS & MESSAGES REPORT ===\n"
		report_text += "Generated: " + Time.get_datetime_string_from_system(false, true) + "\n"
		report_text += "==================================================\n\n"
		
		var convs_dict: Dictionary = all_convs as Dictionary
		var conv_count: int = 0
		var msg_count: int = 0
		
		# Sort conversations by lastMessageAt (newest first)
		var conv_ids: Array = convs_dict.keys()
		conv_ids.sort_custom(func(a, b): 
			var a_time: String = str(convs_dict[a].get("lastMessageAt", ""))
			var b_time: String = str(convs_dict[b].get("lastMessageAt", ""))
			return a_time > b_time
		)
		
		for conv_id in conv_ids:
			var conv: Variant = convs_dict.get(conv_id)
			if not conv is Dictionary:
				continue
			
			conv_count += 1
			var student_id: String = str(conv.get("userId", "Unknown"))
			var created_at: String = str(conv.get("createdAt", "Unknown"))
			var last_msg_at: String = str(conv.get("lastMessageAt", "Unknown"))
			
			report_text += "\n========================\n"
			report_text += "CONVERSATION: %s\n" % conv_id
			report_text += "Student ID: %s\n" % student_id
			report_text += "Created: %s\n" % created_at
			report_text += "Last Message: %s\n" % last_msg_at
			report_text += "========================\n"
			
			if conv.has("messages") and conv["messages"] is Dictionary:
				var messages: Dictionary = conv["messages"] as Dictionary
				var msg_ids: Array = messages.keys()
				
				# Sort messages by timestamp
				msg_ids.sort_custom(func(a, b):
					var a_time: String = str(messages[a].get("timestamp", ""))
					var b_time: String = str(messages[b].get("timestamp", ""))
					return a_time < b_time
				)
				
				for msg_id in msg_ids:
					var msg: Variant = messages.get(msg_id)
					if msg is Dictionary:
						msg_count += 1
						var sender: String = str(msg.get("senderId", "Unknown"))
						var timestamp: String = str(msg.get("timestamp", "Unknown"))
						var text: String = str(msg.get("message", "(empty)"))
						var is_read: String = "✓" if msg.get("read", false) else "✗"
						
						report_text += "[%s] <%s> %s\n" % [timestamp, sender, text]
						if sender == "admin_1":
							report_text += "    (Admin Reply) [Read: %s]\n" % is_read
		
		report_text += "\n==================================================\n"
		report_text += "SUMMARY\n"
		report_text += "Total Conversations: %d\n" % conv_count
		report_text += "Total Messages: %d\n" % msg_count
		report_text += "Report Generated: " + Time.get_datetime_string_from_system(false, true) + "\n"
		
		var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if file != null:
			file.store_string(report_text)
			print("AdminHelper: Conversations report exported to ", output_path)
			print("  Conversations: ", conv_count, " | Messages: ", msg_count)
		else:
			push_error("AdminHelper: Failed to write conversations report to ", output_path)
	)
func _candidate_display_name(conversation: Dictionary) -> String:
	if conversation == null or not conversation is Dictionary:
		return ""
	var names: Array = [
		conversation.get("displayName", ""),
		conversation.get("studentName", ""),
		conversation.get("userName", ""),
		conversation.get("name", ""),
		conversation.get("student_email", ""),
		conversation.get("userEmail", "")
	]
	for entry in names:
		var value: String = str(entry).strip_edges()
		if value != "" and value != "guest_user":
			return value
	return ""

func _conversation_display_name(conversation: Dictionary) -> String:
	var candidate: String = _candidate_display_name(conversation)
	if candidate != "":
		return candidate
	var user_id: String = str(conversation.get("userId", "")).strip_edges()
	if user_id != "" and user_id != "guest_user":
		return user_id
	return "Student"

func _normalize_conversation_for_admin(conv_map: Dictionary) -> void:
	var bucket: Dictionary = _normalize_message_bucket(conv_map.get("messages", {}))
	var legacy_bucket: Dictionary = _collect_legacy_message_entries(conv_map)
	for msg_id in legacy_bucket.keys():
		bucket[msg_id] = legacy_bucket.get(msg_id)
	conv_map["messages"] = bucket
	var display: String = _conversation_display_name(conv_map)
	if display != "":
		conv_map["userName"] = display
		conv_map["displayName"] = display
		conv_map["studentName"] = display

