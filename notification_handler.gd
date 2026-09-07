extends Control
# Notification Handler - Manages notifications from Firebase
# Handles rewards, admin requests, chat reminders, goal tasks, and system notifications

var _auth_manager: Node
var _session: Node
var _current_user_id: String = ""
var _notification_panels: Dictionary = {}
var _unread_count: int = 0
var _db: Node
var _realtime_listener: Node  # Real-time listener manager

# Firebase paths
const NOTIFICATIONS_PATH: String = "users/%s/notifications"
const CONVERSATIONS_PATH: String = "conversations"
const TASKS_PATH: String = "users/%s/tasks"

func _ready() -> void:
	_auth_manager = _resolve_auth_manager()
	_session = _resolve_session()
	_db = _resolve_db()
	_realtime_listener = _resolve_realtime_listener()
	
	_current_user_id = _get_current_user_id()
	
	_setup_notification_panels()
	_setup_realtime_listeners()
	_wire_back_button()
	
	# Initial load
	call_deferred("_load_all_notifications")

func _sanitize_uid(value: String) -> String:
	var safe: String = str(value).strip_edges()
	if safe == "":
		return ""
	safe = safe.to_lower()
	for ch in ["@", ".", "#", "$", "[", "]"]:
		safe = safe.replace(ch, "_")
	safe = safe.replace(" ", "_")
	return safe

func _email_storage_key(email: String) -> String:
	var key: String = str(email).strip_edges().to_lower()
	key = key.replace("@", "_")
	key = key.replace(".", "_")
	key = key.replace(" ", "_")
	return key

func _resolve_storage_user_key() -> String:
	# Prefer email-based storage key when available, otherwise use sanitized uid
	if _session != null and _session.has_method("get_current_user_email"):
		var email = str(_session.call("get_current_user_email")).strip_edges()
		if email != "":
			return _email_storage_key(email)
	var uid = _get_current_user_id()
	return _sanitize_uid(uid)

func _resolve_auth_manager() -> Node:
	if get_tree() != null and get_tree().root != null:
		var manager: Node = get_tree().root.get_node_or_null("FirebaseAuthManager")
		if manager != null:
			return manager
	if Engine.has_singleton("FirebaseAuthManager"):
		return Engine.get_singleton("FirebaseAuthManager")
	return null

func _resolve_session() -> Node:
	if get_tree() != null and get_tree().root != null:
		var session: Node = get_tree().root.get_node_or_null("UserSession")
		if session != null:
			return session
	if Engine.has_singleton("UserSession"):
		return Engine.get_singleton("UserSession")
	return null

func _resolve_db() -> Node:
	if get_tree() != null and get_tree().root != null:
		var db: Node = get_tree().root.get_node_or_null("FirebaseRTDB")
		if db != null:
			return db
	if Engine.has_singleton("FirebaseRTDB"):
		return Engine.get_singleton("FirebaseRTDB")
	return null

func _resolve_realtime_listener() -> Node:
	"""Resolve or create the real-time listener manager"""
	if get_tree() != null and get_tree().root != null:
		var existing_listener: Node = get_tree().root.get_node_or_null("FirebaseRealtimeListener")
		if existing_listener != null:
			return existing_listener
	# Create new listener if doesn't exist
	var new_listener = load("res://firebase_realtime_listener.gd").new()
	get_tree().root.add_child.call_deferred(new_listener)
	new_listener.name = "FirebaseRealtimeListener"
	return new_listener

func _get_current_user_id() -> String:
	if _session != null and _session.has_method("get_current_user_id"):
		var uid: String = str(_session.call("get_current_user_id")).strip_edges()
		if not uid.is_empty():
			return uid
	return "guest_user"

func _setup_notification_panels() -> void:
	# Use one clean feed for the notification list instead of stacking several overlapping panels.
	_notification_panels.clear()
	var panel_root: Control = get_node_or_null("Panel") as Control
	var primary_panel: Panel = null
	if panel_root != null:
		primary_panel = panel_root.get_node_or_null("Panel8") as Panel
		if primary_panel == null:
			primary_panel = panel_root.get_node_or_null("Panel9") as Panel
		if primary_panel != null:
			primary_panel.visible = true
			primary_panel.set_meta("combined_notifications", true)
			primary_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			primary_panel.offset_left = 76
			primary_panel.offset_top = 104
			primary_panel.offset_right = -76
			primary_panel.offset_bottom = -180
			primary_panel.mouse_filter = Control.MOUSE_FILTER_PASS
			primary_panel.z_index = 0
			var close_button: Button = panel_root.get_node_or_null("Button") as Button
			if close_button != null:
				close_button.z_index = 5
			var trash_button: Button = panel_root.get_node_or_null("Button3") as Button
			if trash_button != null:
				trash_button.z_index = 5
			var settings_button: Button = panel_root.get_node_or_null("Button4") as Button
			if settings_button != null:
				settings_button.z_index = 5
			for panel_name in ["Panel9", "Panel10", "Panel11", "Panel12"]:
				var legacy_panel: Panel = panel_root.get_node_or_null(panel_name) as Panel
				if legacy_panel != null:
					legacy_panel.visible = false
					legacy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
					legacy_panel.set_meta("combined_notifications", false)
					legacy_panel.z_index = -1
			var scroll: ScrollContainer = primary_panel.get_node_or_null("NotificationScroll") as ScrollContainer
			if scroll == null:
				scroll = ScrollContainer.new()
				scroll.name = "NotificationScroll"
				scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				scroll.offset_left = 8
				scroll.offset_top = 8
				scroll.offset_right = -8
				scroll.offset_bottom = -8
				scroll.follow_focus = true
				scroll.scroll_vertical = true
				scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
				scroll.clip_contents = true
				primary_panel.add_child(scroll)
			_notification_panels["rewards"] = primary_panel
			_notification_panels["admin_requests"] = primary_panel
			_notification_panels["chat_reminders"] = primary_panel
			_notification_panels["goal_tasks"] = primary_panel
			_notification_panels["system"] = primary_panel
	else:
		# Fallback for older scene naming.
		_notification_panels["rewards"] = get_node_or_null("Panel/Panel3")
		_notification_panels["admin_requests"] = get_node_or_null("Panel/Panel4")
		_notification_panels["chat_reminders"] = get_node_or_null("Panel/Panel5")
		_notification_panels["goal_tasks"] = get_node_or_null("Panel/Panel6")
		_notification_panels["system"] = get_node_or_null("Panel/Panel7")
	
	for key in _notification_panels.keys():
		if _notification_panels[key] == null:
			print("Missing notification panel: ", key)
	
	print("Notification panels setup: ", _notification_panels.keys())

func _setup_realtime_listeners() -> void:
	"""Setup real-time listeners for all notification types"""
	if _realtime_listener == null:
		push_error("Real-time listener not available")
		return
	
	var storage_key = _resolve_storage_user_key()
	
	# Listen to tasks with real-time updates
	var tasks_path = "users/%s/tasks" % storage_key
	_realtime_listener.listen_to_path(tasks_path, Callable(self, "_on_tasks_changed"))
	
	# Listen to notifications with real-time updates
	var notifications_path = "users/%s/notifications" % storage_key
	_realtime_listener.listen_to_path(notifications_path, Callable(self, "_on_notifications_changed"))
	
	# Listen to conversations for admin messages
	_realtime_listener.listen_to_path(CONVERSATIONS_PATH, Callable(self, "_on_conversations_changed"))

func _wire_back_button() -> void:
	var back_button: Button = get_node_or_null("Panel/Button") as Button
	if back_button != null:
		back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	# Clean up real-time listeners when leaving
	if _realtime_listener != null:
		_realtime_listener.stop_all_listeners()
	get_tree().change_scene_to_file("res://home.tscn")

# ─── Real-Time Callbacks ──────────────────────────────────────
func _on_tasks_changed(_tasks_data: Dictionary) -> void:
	"""Called when tasks change in real-time"""
	_load_goal_task_notifications()
	print("Real-Time: Task panel updated")

func _on_notifications_changed(_notif_data: Dictionary) -> void:
	"""Called when notifications change in real-time"""
	_load_reward_notifications()
	_load_system_notifications()
	print("Real-Time: Notification panels updated")

func _on_conversations_changed(_conv_data: Dictionary) -> void:
	"""Called when conversations change in real-time"""
	_load_admin_request_notifications()
	_load_chat_reminder_notifications()
	print("Real-Time: Conversation panels updated")

func _load_all_notifications() -> void:
	var storage_key = _resolve_storage_user_key()
	print("Loading notifications for user: ", _current_user_id, " (storage key: ", storage_key, ")")
	_unread_count = 0
	
	# Load different notification types in parallel
	_load_reward_notifications()
	_load_admin_request_notifications()
	_load_chat_reminder_notifications()
	_load_goal_task_notifications()
	_load_system_notifications()

func _load_reward_notifications() -> void:
	var panel: Control = _notification_panels.get("rewards")
	if panel == null:
		return
	
	_clear_panel(panel)
	
	# Mock reward notifications for now - integrate with Firebase rewards system
	var rewards: Array = [
		{"title": "Level Up!", "message": "You reached Level 5", "timestamp": "2026-08-29 10:00:00", "read": false},
		{"title": "Coin Bonus", "message": "Earned 50 coins from daily check-in", "timestamp": "2026-08-29 09:00:00", "read": true}
	]
	
	_display_notifications_in_panel(panel, rewards, "rewards")

func _load_admin_request_notifications() -> void:
	var panel: Control = _notification_panels.get("admin_requests")
	if panel == null:
		return
	
	_clear_panel(panel)
	
	# Check for unread admin messages in conversations
	if _db != null and _db.has_method("read_json"):
		var conversations_path: String = "conversations"
		_db.read_json(conversations_path, func(_result: int, response_code: int, body: Variant):
			if response_code == 200 and body is Dictionary:
				var admin_requests: Array = []
				for conv_id in body.keys():
					var conv: Dictionary = body[conv_id]
					if conv is Dictionary and conv.get("unread", 0) > 0:
						var request: Dictionary = {
							"title": "New Message from Counselor",
							"message": str(conv.get("lastMessage", "You have a new message")),
							"timestamp": str(conv.get("lastMessageAt", "")),
							"read": false,
							"conversation_id": conv_id
						}
						admin_requests.append(request)
						_unread_count += 1
				
				_display_notifications_in_panel(panel, admin_requests, "admin_requests")
		)

func _load_chat_reminder_notifications() -> void:
	var panel: Control = _notification_panels.get("chat_reminders")
	if panel == null:
		return
	
	_clear_panel(panel)
	
	# Mock chat reminders - integrate with actual chat system
	var reminders: Array = [
		{"title": "Daily Check-in", "message": "Don't forget to check your mood today", "timestamp": "2026-08-29 08:00:00", "read": false}
	]
	
	_display_notifications_in_panel(panel, reminders, "chat_reminders")

func _load_goal_task_notifications() -> void:
	var panel: Control = _notification_panels.get("goal_tasks")
	if panel == null:
		return
	
	_clear_panel(panel)
	
	# Load from Firebase tasks
	var storage_key: String = _resolve_storage_user_key()
	var user_tasks_path: String = "users/%s/tasks" % storage_key
	if _db != null and _db.has_method("read_json"):
		_db.read_json(user_tasks_path, func(_result: int, response_code: int, body: Variant):
			if response_code == 200 and body is Dictionary:
				var task_notifications: Array = []
				var tasks_dict: Dictionary = body as Dictionary
				
				# Filter for incomplete tasks
				for task_id in tasks_dict.keys():
					var task: Dictionary = tasks_dict[task_id]
					if task is Dictionary:
						var completed = task.get("completed", false)
						if not completed:
							var assigned_at: String = str(task.get("assigned_at", "Today"))
							var task_notif: Dictionary = {
								"title": "Task Assigned",
								"message": "Complete your assigned task to earn rewards!",
								"timestamp": assigned_at,
								"read": task.get("read", false),
								"task_id": task_id
							}
							task_notifications.append(task_notif)
							if not task.get("read", false):
								_unread_count += 1
				
				_display_notifications_in_panel(panel, task_notifications, "goal_tasks")
			else:
				_show_empty_message(panel, "No tasks assigned yet")
		)
	else:
		_show_empty_message(panel, "Cannot load tasks")

func _load_system_notifications() -> void:
	var panel: Control = _notification_panels.get("system")
	if panel == null:
		return
	
	_clear_panel(panel)
	
	# Mock system notifications
	var system_notifications: Array = [
		{"title": "Welcome to HabiHero", "message": "Start your journey to better habits today!", "timestamp": "2026-08-29 07:00:00", "read": true}
	]
	
	_display_notifications_in_panel(panel, system_notifications, "system")

func _get_notification_list(panel: Control) -> VBoxContainer:
	if panel == null:
		return null
	var scroll: ScrollContainer = panel.get_node_or_null("NotificationScroll") as ScrollContainer
	if scroll == null:
		return null
	var list: VBoxContainer = scroll.get_node_or_null("NotificationList") as VBoxContainer
	if list == null:
		list = VBoxContainer.new()
		list.name = "NotificationList"
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.custom_minimum_size = Vector2(0, 0)
		list.offset_left = 0
		list.offset_top = 0
		list.offset_right = 0
		list.offset_bottom = 0
		list.add_theme_constant_override("separation", 12)
		scroll.add_child(list)
	return list

func _clear_panel(panel: Control) -> void:
	if panel == null:
		return
	var list: VBoxContainer = _get_notification_list(panel)
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()

func _display_notifications_in_panel(panel: Control, notifications: Array, type: String) -> void:
	if panel == null:
		return
	var list: VBoxContainer = _get_notification_list(panel)
	if list == null:
		return
	if not panel.get_meta("combined_notifications", false):
		_clear_panel(panel)
	if notifications.is_empty():
		if not panel.get_meta("combined_notifications", false):
			_show_empty_message(panel, "No " + type.replace("_", " ").capitalize() + " yet")
		return
	
	for notif in notifications:
		var notification_card: Panel = _create_notification_card(notif, type)
		list.add_child(notification_card)

func _create_notification_card(notif: Dictionary, type: String) -> Panel:
	var card: Panel = Panel.new()
	card.custom_minimum_size = Vector2(0, 80)
	
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1) if notif.get("read", true) else Color(1, 0.95, 0.9, 1)
	style.border_color = Color(0.8, 0.8, 0.8, 1)
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	card.add_theme_stylebox_override("panel", style)
	
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_top = 8
	vbox.offset_right = -12
	vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)
	
	var title_label: Label = Label.new()
	title_label.text = str(notif.get("title", "Notification"))
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1))
	vbox.add_child(title_label)
	
	var message_label: Label = Label.new()
	message_label.text = str(notif.get("message", ""))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	message_label.add_theme_font_size_override("font_size", 12)
	message_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	vbox.add_child(message_label)
	
	var time_label: Label = Label.new()
	time_label.text = str(notif.get("timestamp", ""))
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	vbox.add_child(time_label)
	
	# Add click handler for navigation
	if type == "admin_requests" and notif.has("conversation_id"):
		var card_button: Button = Button.new()
		card_button.text = ""
		card_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_button.modulate = Color(1, 1, 1, 0)  # Invisible but clickable
		card_button.pressed.connect(func():
			_navigate_to_chat(notif["conversation_id"])
		)
		card.add_child(card_button)
	
	# Add click handler for task notifications
	if type == "goal_tasks" and notif.has("task_id"):
		var card_button: Button = Button.new()
		card_button.text = ""
		card_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_button.modulate = Color(1, 1, 1, 0)  # Invisible but clickable
		card_button.pressed.connect(func():
			_navigate_to_task(notif["task_id"])
		)
		card.add_child(card_button)
	
	return card

func _show_empty_message(panel: Control, message: String) -> void:
	var label: Label = Label.new()
	label.text = message
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 20
	label.offset_top = 40
	label.offset_right = -20
	label.offset_bottom = -20
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	label.add_theme_font_size_override("font_size", 12)
	panel.add_child(label)

func _navigate_to_chat(conversation_id: String) -> void:
	print("Navigating to chat with conversation: ", conversation_id)
	get_tree().change_scene_to_file("res://guidance.tscn")

func _navigate_to_task(task_id: String) -> void:
	"""Navigate to the tasks scene with the specific task selected"""
	print("Navigating to task: ", task_id)
	if get_tree().root.has_meta("selected_task_id"):
		get_tree().root.remove_meta("selected_task_id")
	get_tree().root.set_meta("selected_task_id", task_id)
	get_tree().change_scene_to_file("res://a_itask.tscn")

func _mark_notification_read(notification_id: String, type: String) -> void:
	# Update Firebase to mark notification as read
	print("Marking notification as read: ", notification_id, " type: ", type)
	_unread_count = max(0, _unread_count - 1)
	
	# Firebase update logic would go here
	if _db != null and _db.has_method("update_json"):
		var storage_key: String = _resolve_storage_user_key()
		var notification_path: String = "users/%s/notifications" % storage_key
		var update_data: Dictionary = {
			notification_id + "/read": true
		}
		_db.update_json(notification_path, update_data, func(_result, code, _body):
			if code == 200:
				print("Notification marked as read successfully")
			else:
				print("Failed to mark notification as read: ", code)
		)

func _update_notification_badge() -> void:
	# Update notification badge count in UI
	var badge: Label = get_node_or_null("Panel/NotificationBadge")
	if badge != null:
		badge.text = str(_unread_count) if _unread_count > 0 else ""
		badge.visible = _unread_count > 0
