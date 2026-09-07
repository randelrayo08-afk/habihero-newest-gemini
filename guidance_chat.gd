extends "res://shared_nav.gd"
# ═══════════════════════════════════════════════════════════════
# Guidance chat for Adventure Habi
#
# This script implements end-to-end real-time chat using Firebase Realtime Database:
#
#   conversations/{convId}: { id, userId, userName, studentEmail, lastMessage, lastMessageAt, unread, createdAt, messages: {} }
#   messages/{msgId}:       { id, conversationId, senderId, receiverId, senderName, message, timestamp, read, type }
#
# The admin-side user id is "admin_1". Messages are stored in the shared
# project database so both the app and external admin interface stay in sync.
# ═══════════════════════════════════════════════════════════════

const DEFAULT_FIREBASE_DB_URL: String = "https://adv-habi-default-rtdb.firebaseio.com"
const ADMIN_ID: String = "admin_1"
const POLL_INTERVAL_SEC: float = 2.0

var _conversation_id: String = ""
var _conversation_path: String = ""
var _messages_path: String = ""
var _current_user_id: String = "guest_user"
var _current_user_name: String = "Student"
var _id_token: String = ""
var _db_url: String = DEFAULT_FIREBASE_DB_URL

var _known_message_ids: Dictionary = {}
var _chat_list: VBoxContainer
var _chat_scroll: ScrollContainer
var _poll_timer: Timer
var _http_poll: HTTPRequest
var _sending: bool = false
var _pending_mark_read: Array = []
var _user_email_cache: Dictionary = {}
var _history_loaded: bool = false
var _last_conversation_id: String = ""

func _ready() -> void:
	super._ready()
	if name != "Guidance":
		return
	_db_url = _resolve_database_url()
	_current_user_id = _resolve_student_id()
	_current_user_name = _resolve_student_name()
	_id_token = _resolve_id_token()
	_build_chat_ui()
	_wire_compose_bar()
	call_deferred("_load_or_create_conversation")

func _sanitize_path(value: String) -> String:
	var safe = value.to_lower()
	safe = safe.replace("@", "_at_")
	safe = safe.replace(".", "_")
	safe = safe.replace("#", "_hash_")
	safe = safe.replace("$", "_dollar_")
	safe = safe.replace("[", "_")
	safe = safe.replace("]", "_")
	safe = safe.replace("/", "_")
	return safe

func _resolve_database_url() -> String:
	var db: Node = _resolve_db()
	if db != null:
		var configured_value: Variant = db.get("database_url")
		var configured: String = str(configured_value if configured_value != null else DEFAULT_FIREBASE_DB_URL).strip_edges()
		if not configured.is_empty() and configured.begins_with("http"):
			return configured.rstrip("/")
	return DEFAULT_FIREBASE_DB_URL

func _resolve_db() -> Node:
	if get_tree() != null and get_tree().root != null:
		var db: Node = get_tree().root.get_node_or_null("FirebaseRTDB")
		if db != null:
			return db
	if Engine.has_singleton("FirebaseRTDB"):
		return Engine.get_singleton("FirebaseRTDB")
	return null

# ── Identity ──────────────────────────────────────────────────
func _resolve_student_id() -> String:
	var session: Node = _resolve_session()
	if session != null:
		if session.has_method("get_current_user_id"):
			var uid: String = str(session.call("get_current_user_id")).strip_edges()
			if not uid.is_empty():
				return uid
	return "guest_user"

func _resolve_storage_user_key() -> String:
	var session: Node = _resolve_session()
	if session != null and session.has_method("get_current_user_email"):
		var email: String = str(session.call("get_current_user_email")).strip_edges()
		if not email.is_empty():
			return _email_storage_key(email)
	return _sanitize_path(_current_user_id)

func _email_storage_key(email: String) -> String:
	var key: String = email.strip_edges().to_lower()
	key = key.replace("@", "_")
	key = key.replace(".", "_")
	key = key.replace(" ", "_")
	return key

func _resolve_student_name() -> String:
	var session: Node = _resolve_session()
	if session != null:
		if session.has_method("get_current_user_name"):
			var name_value: String = str(session.call("get_current_user_name")).strip_edges()
			if not name_value.is_empty():
				return name_value
	return "Student"

func _resolve_id_token() -> String:
	var session: Node = _resolve_session()
	if session != null:
		if session.has_method("get_current_user_token"):
			var token: String = str(session.call("get_current_user_token")).strip_edges()
			if not token.is_empty() and not token.to_lower().begins_with("local:"):
				return token

	var auth: Node = _resolve_auth_manager()
	if auth == null:
		return ""
	for m in ["get_id_token", "get_token", "get_auth_token"]:
		if auth.has_method(m):
			var candidate: String = str(auth.call(m)).strip_edges()
			if not candidate.is_empty() and not candidate.to_lower().begins_with("local:"):
				return candidate
	return ""

func _rtdb_url(path: String, query: String = "") -> String:
	var safe_path: String = path.strip_edges()
	if safe_path.begins_with("/"):
		safe_path = safe_path.substr(1)
	var base_url: String = _db_url.rstrip("/")
	var url: String = "%s/%s.json" % [base_url, safe_path]
	if safe_path.is_empty():
		url = "%s.json" % base_url

	var params: Array = []
	if not _id_token.is_empty():
		params.append("auth=" + _id_token.uri_encode())
	if not query.is_empty():
		var clean_query: String = query.strip_edges()
		if clean_query.begins_with("?"):
			clean_query = clean_query.substr(1)
		params.append(clean_query)
	if params.size() > 0:
		url += "?" + "&".join(params)
	return url

# ── UI construction (built at runtime — no scene edits needed) ──
func _clear_chat_ui() -> void:
	if _chat_list == null:
		return
	for child in _chat_list.get_children():
		child.queue_free()

func _build_chat_ui() -> void:
	var host: Control = get_node_or_null("Panel2/Panel") as Control
	if host == null:
		return
	host.clip_contents = true

	_chat_scroll = ScrollContainer.new()
	_chat_scroll.name = "ChatScroll"
	_chat_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chat_scroll.offset_left = 12
	_chat_scroll.offset_top = 12
	_chat_scroll.offset_right = -12
	_chat_scroll.offset_bottom = -12
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(_chat_scroll)

	_chat_list = VBoxContainer.new()
	_chat_list.name = "ChatList"
	_chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_list.add_theme_constant_override("separation", 8)
	_chat_scroll.add_child(_chat_list)

func _wire_compose_bar() -> void:
	var send_button: Button = get_node_or_null("Panel4/Panel/Button") as Button
	if send_button != null:
		var cb: Callable = Callable(self, "_on_send_pressed")
		if not send_button.pressed.is_connected(cb):
			send_button.pressed.connect(cb)

	var text_edit: TextEdit = get_node_or_null("Panel4/TextEdit") as TextEdit
	if text_edit != null:
		var input_cb: Callable = Callable(self, "_on_text_edit_input").bind(text_edit)
		if not text_edit.gui_input.is_connected(input_cb):
			text_edit.gui_input.connect(input_cb)

	if _poll_timer == null:
		_poll_timer = Timer.new()
		_poll_timer.name = "ChatPollTimer"
		_poll_timer.wait_time = POLL_INTERVAL_SEC
		_poll_timer.autostart = false
		_poll_timer.timeout.connect(_poll_messages)
		add_child(_poll_timer)

func _start_polling() -> void:
	if _poll_timer != null:
		_poll_timer.start()

func _stop_polling() -> void:
	if _poll_timer != null:
		_poll_timer.stop()

func _reset_conversation_tracking() -> void:
	_clear_chat_ui()
	_known_message_ids.clear()
	_history_loaded = false
	_last_conversation_id = _conversation_id
	_print_debug("conversation changed to: %s, clearing UI" % _conversation_id)

func _on_text_edit_input(event: InputEvent, _text_edit: TextEdit) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not event.shift_pressed:
			_on_send_pressed()
			get_viewport().set_input_as_handled()

# ── Conversation bootstrap ───────────────────────────────────
func _load_user_scoped_conversation(callback: Callable) -> void:
	var storage_user_key: String = _resolve_storage_user_key()
	var user_path: String = "users/" + storage_user_key + "/conversation"
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		http.queue_free()
		if code == 200:
			var conversation: Variant = JSON.parse_string(body.get_string_from_utf8())
			if conversation is Dictionary and not conversation.is_empty():
				_conversation_id = str(conversation.get("id", "user_" + _current_user_id))
				_conversation_path = "conversations/" + _conversation_id
				_messages_path = _conversation_path
				_print_debug("found user-scoped conversation with conversation_id: %s, using global path" % _conversation_id)
				callback.call(true)
				return
		_print_debug("no user-scoped conversation found at: %s" % user_path)
		callback.call(false)
	)
	_print_debug("looking up account conversation: %s" % user_path)
	http.request(_rtdb_url(user_path))

func _find_conversation_for_user(user_id: String, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		http.queue_free()
		if code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			if json is Dictionary and json.keys().size() > 0:
				var matching_ids: Array[String] = []
				var requested_user_id: String = user_id.strip_edges().to_lower()
				for conversation_key in json.keys():
					var conversation: Variant = json.get(conversation_key)
					if not conversation is Dictionary:
						continue
					var stored_user_id: String = str(conversation.get("userId", conversation.get("user_id", ""))).strip_edges().to_lower()
					if stored_user_id == requested_user_id:
						matching_ids.append(str(conversation_key))
				if not matching_ids.is_empty():
					matching_ids.sort_custom(func(left: String, right: String) -> bool:
						var left_data: Dictionary = json.get(left, {})
						var right_data: Dictionary = json.get(right, {})
						var left_messages: Variant = left_data.get("messages", {})
						var right_messages: Variant = right_data.get("messages", {})
						var left_message_count: int = left_messages.size() if left_messages is Dictionary else 0
						var right_message_count: int = right_messages.size() if right_messages is Dictionary else 0
						if left_message_count != right_message_count:
							return left_message_count > right_message_count
						var left_time: String = str(left_data.get("lastMessageAt", left_data.get("createdAt", "")))
						var right_time: String = str(right_data.get("lastMessageAt", right_data.get("createdAt", "")))
						return left_time > right_time
					)
					_print_debug("found conversation %s for user %s" % [matching_ids[0], user_id])
					callback.call(matching_ids[0])
					return
		_print_debug("no conversation found for user: %s" % user_id)
		callback.call("")
	)
	_print_debug("looking up conversation for user: %s at /conversations" % user_id)
	http.request(_rtdb_url("conversations"))

func _load_or_create_conversation() -> void:
	if _current_user_id.is_empty():
		return
	_find_conversation_for_user(_current_user_id, func(found_conversation_id: String) -> void:
		if not found_conversation_id.is_empty():
			_conversation_id = found_conversation_id
			_conversation_path = "conversations/" + _conversation_id
			_messages_path = _conversation_path
			_print_debug("reusing conversation: %s" % _conversation_id)
			_load_message_history()
			_start_polling()
			return
		_load_user_scoped_conversation(func(found: bool) -> void:
			if found:
				_print_debug("reusing account conversation: %s" % _conversation_id)
				_load_message_history()
				_start_polling()
				return
			_start_new_conversation()
		)
	)

func _start_new_conversation() -> void:
	var safe_user_id = _sanitize_path(_current_user_id)
	_conversation_id = "conv_%s_%d" % [safe_user_id, Time.get_unix_time_from_system()]
	_conversation_path = "conversations/" + _conversation_id
	_messages_path = _conversation_path
	var now_iso: String = Time.get_datetime_string_from_system(false, true)
	var student_email: String = _resolve_student_email()
	var conv := {
		"id": _conversation_id,
		"userId": _current_user_id,
		"userName": _current_user_name,
		"studentName": _current_user_name,
		"studentEmail": student_email,
		"lastMessage": "",
		"lastMessageAt": now_iso,
		"unread": 0,
		"createdAt": now_iso,
		"messages": {}
	}
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		_print_debug("create conversation response: %d -- %s" % [code, str(_b.get_string_from_utf8())])
		if code == 200:
			_print_debug("conversation created with conversation_id: %s and proper message structure" % _conversation_id)
			_load_message_history()
			_start_polling()
		else:
			print("Guidance chat: failed to create conversation (", code, ") -> body:", _b.get_string_from_utf8())
	)
	var headers := ["Content-Type: application/json"]
	var url = _rtdb_url("conversations/" + _conversation_id)
	_print_debug("creating conversation url: %s with conversation_id: %s body: %s" % [url, _conversation_id, JSON.stringify(conv)])
	http.request(url, headers, HTTPClient.METHOD_PUT, JSON.stringify(conv))

func _resolve_student_email() -> String:
	var session: Node = _resolve_session()
	if session != null:
		if session.has_method("get_current_user_email"):
			var email: String = str(session.call("get_current_user_email")).strip_edges()
			if not email.is_empty():
				return email
	return ""

func _write_message_to_top_level(message: Dictionary) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		if code != 200:
			print("Guidance chat: top-level message write failed (", code, ") body: ", _b.get_string_from_utf8())
		else:
			_print_debug("top-level message written successfully with conversation_id: %s" % message.get("conversationId", ""))
	)
	var headers := ["Content-Type: application/json"]
	var url = _rtdb_url("messages/" + message["id"])
	_print_debug("writing message to top-level /messages path with message_id: %s, conversation_id: %s" % [message["id"], message.get("conversationId", "")])
	http.request(url, headers, HTTPClient.METHOD_PUT, JSON.stringify(message))

func _on_send_pressed() -> void:
	if _sending:
		return
	if _conversation_id.is_empty():
		_load_or_create_conversation()
		return
	var text_edit: TextEdit = get_node_or_null("Panel4/TextEdit") as TextEdit
	if text_edit == null:
		return
	var text: String = text_edit.text.strip_edges()
	if text.is_empty():
		return
	_sending = true
	text_edit.text = ""

	var msg_id: String = "msg_%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	var now_iso: String = Time.get_datetime_string_from_system(false, true)
	var message := {
		"id": msg_id,
		"conversationId": _conversation_id,
		"senderId": _current_user_id,
		"receiverId": ADMIN_ID,
		"senderName": _current_user_name,
		"studentName": _current_user_name,
		"message": text,
		"timestamp": now_iso,
		"read": false,
		"type": "text",
	}
	_known_message_ids[msg_id] = true
	_render_message(message)

	var updates := {
		"lastMessage": text,
		"lastMessageAt": now_iso,
		"userId": _current_user_id,
		"userName": _current_user_name,
		"studentName": _current_user_name,
		"messages/%s" % msg_id: message
	}

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		_sending = false
		if code != 200:
			print("Guidance chat: send failed (", code, ") body: ", _b.get_string_from_utf8())
		else:
			_print_debug("message sent successfully to conversation node with conversation_id: %s" % _conversation_id)
			_write_message_to_top_level(message)
			_poll_messages()
	)
	var headers := ["Content-Type: application/json"]
	var url = _rtdb_url(_conversation_path)
	_print_debug("sending to: %s with message_id: %s for conversation: %s" % [url, msg_id, _conversation_id])
	http.request(url, headers, HTTPClient.METHOD_PATCH, JSON.stringify(updates))

# ── Polling for admin replies ────────────────────────────────
func _sort_messages_by_timestamp(messages: Dictionary) -> Array:
	var sorted: Array = []
	for msg_id in messages.keys():
		var msg: Dictionary = messages[msg_id]
		if msg is Dictionary:
			sorted.append(msg)

	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var time_a: String = str(a.get("timestamp", ""))
		var time_b: String = str(b.get("timestamp", ""))
		return time_a < time_b
	)
	return sorted

func _load_message_history() -> void:
	if _conversation_id.is_empty():
		_start_polling()
		return

	if _conversation_id != _last_conversation_id:
		_reset_conversation_tracking()

	if _history_loaded:
		_poll_messages()
		return

	_history_loaded = true
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		http.queue_free()
		if code == 200:
			var text: String = ""
			if body != null:
				text = body.get_string_from_utf8()
			_print_debug("history load result: %s" % text)
			var json = JSON.parse_string(text)
			if json is Dictionary:
				var messages_dict: Dictionary = _extract_messages_from_payload(json)
				if messages_dict.is_empty() and json.has("messages") and json["messages"] is Dictionary:
					messages_dict = json["messages"] as Dictionary
				var filtered_messages: Dictionary = {}
				for msg_id in messages_dict.keys():
					var msg: Variant = messages_dict[msg_id]
					if msg is Dictionary:
						var msg_conversation_id: String = str(msg.get("conversationId", ""))
						if msg_conversation_id == _conversation_id or msg_conversation_id.is_empty():
							filtered_messages[msg_id] = msg
				var sorted_messages: Array = _sort_messages_by_timestamp(filtered_messages)
				_print_debug("loaded %d messages for conversation %s, sorted chronologically" % [sorted_messages.size(), _conversation_id])
				for message in sorted_messages:
					var msg_id: String = str(message.get("id", ""))
					if not msg_id.is_empty():
						_known_message_ids[msg_id] = true
					_render_message(message)
			else:
				_print_debug("no message history found or invalid format")
		else:
			_print_debug("failed to load message history, code: %d" % code)
		_poll_messages()
	)
	var url = _rtdb_url(_messages_path if not _messages_path.is_empty() else "conversations/" + _conversation_id)
	_print_debug("loading message history from: %s for conversation: %s" % [url, _conversation_id])
	http.request(url)

func _extract_messages_from_payload(payload: Variant) -> Dictionary:
	var extracted: Dictionary = {}
	if not payload is Dictionary:
		return extracted

	var source: Dictionary = payload as Dictionary
	if source.has("messages") and source["messages"] is Dictionary:
		var nested_messages: Dictionary = source["messages"] as Dictionary
		for key in nested_messages.keys():
			extracted[key] = nested_messages[key]
		return extracted

	for key in source.keys():
		var value: Variant = source.get(key)
		if value is Dictionary and value.has("message"):
			extracted[key] = value
		elif key.begins_with("messages/"):
			var msg_key: String = key.substr("messages/".length())
			if not msg_key.is_empty() and value is Dictionary:
				extracted[msg_key] = value
	return extracted

func _fetch_user_email(user_id: String, callback: Callable) -> void:
	if _user_email_cache.has(user_id):
		callback.call(_user_email_cache[user_id])
		return

	if user_id == ADMIN_ID:
		var admin_display: String = "Guidance Counselor"
		_user_email_cache[user_id] = admin_display
		callback.call(admin_display)
		return

	var candidates: Array = []
	candidates.append(user_id)
	var sanitized: String = _sanitize_path(user_id)
	if sanitized != user_id:
		candidates.append(sanitized)
	if user_id.find("@") != -1:
		candidates.append(_email_storage_key(user_id))

	_fetch_user_email_candidate(user_id, candidates, 0, callback)

func _fetch_user_email_candidate(user_id: String, candidates: Array, idx: int, callback: Callable) -> void:
	if idx >= candidates.size():
		_user_email_cache[user_id] = user_id
		callback.call(user_id)
		return

	var candidate = str(candidates[idx])
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		http.queue_free()
		var display_name: String = ""
		if code == 200 and body != null:
			var text: String = body.get_string_from_utf8()
			var json = JSON.parse_string(text)
			if json is Dictionary:
				if json.has("email") and not str(json["email"]).strip_edges().is_empty():
					display_name = str(json["email"]).strip_edges()
				elif json.has("name") and not str(json["name"]).strip_edges().is_empty():
					display_name = str(json["name"]).strip_edges()
		if display_name == "":
			_fetch_user_email_candidate(user_id, candidates, idx + 1, callback)
		else:
			_user_email_cache[user_id] = display_name
			callback.call(display_name)
	)
	var profile_path: String = "users/%s/profile" % candidate
	_print_debug("fetching user profile from: %s" % profile_path)
	http.request(_rtdb_url(profile_path))

func _poll_messages() -> void:
	if _conversation_id.is_empty():
		return
	if _http_poll != null:
		return
	_http_poll = HTTPRequest.new()
	add_child(_http_poll)
	_http_poll.request_completed.connect(_on_poll_result)
	var url = _rtdb_url(_messages_path if not _messages_path.is_empty() else "conversations/" + _conversation_id)
	_print_debug("polling from: %s for conversation: %s" % [url, _conversation_id])
	_http_poll.request(url)

func _on_poll_result(_result, response_code, _headers, body) -> void:
	if _http_poll != null:
		_http_poll.queue_free()
		_http_poll = null
	if response_code != 200:
		_print_debug("poll failed code: %s body: %s" % [response_code, str(body.get_string_from_utf8()) if body != null else "<null>"])
		return
	var text: String = ""
	if body != null:
		text = body.get_string_from_utf8()
	_print_debug("poll result: %s" % text)
	var json = JSON.parse_string(text)
	if not (json is Dictionary):
		_print_debug("poll returned non-dict or null")
		return

	var messages_dict: Dictionary = _extract_messages_from_payload(json)
	if messages_dict.is_empty() and json.has("messages") and json["messages"] is Dictionary:
		messages_dict = json["messages"] as Dictionary

	var filtered_messages: Dictionary = {}
	for msg_id in messages_dict.keys():
		var msg: Variant = messages_dict[msg_id]
		if msg is Dictionary:
			var msg_conversation_id: String = str(msg.get("conversationId", ""))
			if msg_conversation_id == _conversation_id or msg_conversation_id.is_empty():
				filtered_messages[msg_id] = msg

	var sorted_messages: Array = _sort_messages_by_timestamp(filtered_messages)
	var new_messages: Array = []

	for message in sorted_messages:
		var msg_id: String = str(message.get("id", ""))
		if _known_message_ids.has(msg_id):
			continue
		if not (message is Dictionary):
			continue

		_known_message_ids[msg_id] = true
		var sender: String = str(message.get("senderId", ""))
		var receiver: String = str(message.get("receiverId", ""))
		var msg_text: String = str(message.get("message", ""))
		_print_debug("INCOMING MESSAGE [%s]: conversation=%s, sender=%s, receiver=%s, text=%s" % [msg_id, _conversation_id, sender, receiver, msg_text])
		new_messages.append(message)
		var read_flag: bool = bool(message.get("read", false))
		if sender != _current_user_id and not read_flag:
			_pending_mark_read.append(msg_id)

	for message in new_messages:
		_render_message(message)

	if _pending_mark_read.size() > 0:
		_mark_messages_read(_pending_mark_read.duplicate())
		_pending_mark_read.clear()

func _render_message(message: Dictionary) -> void:
	if _chat_list == null:
		return

	var sender_id: String = str(message.get("senderId", "")).strip_edges()
	var conversation_id: String = str(message.get("conversationId", "")).strip_edges()
	if not conversation_id.is_empty() and conversation_id != _conversation_id:
		_print_debug("Skipping message %s - belongs to conversation %s, not current %s" % [message.get("id", ""), conversation_id, _conversation_id])
		return

	var mine: bool = (sender_id == _current_user_id) or (sender_id.to_lower() == _current_user_id.to_lower())
	_print_debug("Rendering message: conversation_id=%s, sender=%s, current_user=%s, mine=%s" % [conversation_id, sender_id, _current_user_id, mine])

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN

	var bubble := _make_bubble_panel(mine)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = str(message.get("message", ""))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(220, 0)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1) if mine else Color(0.1, 0.1, 0.1, 1))
	vbox.add_child(label)

	var meta := Label.new()
	meta.text = "Loading..."
	meta.add_theme_font_size_override("font_size", 10)
	meta.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	vbox.add_child(meta)

	bubble.add_child(vbox)
	row.add_child(bubble)
	_chat_list.add_child(row)

	var ts_str: String = str(message.get("timestamp", ""))
	if ts_str.is_empty():
		ts_str = Time.get_datetime_string_from_system(false, true)
		_print_debug("Missing timestamp, using current time: %s" % ts_str)

	if mine:
		var my_display: String = _current_user_name
		var short_time := _format_message_time(ts_str)
		if short_time != "":
			meta.text = "%s • %s" % [my_display, short_time]
		else:
			meta.text = my_display
	else:
		_fetch_user_email(sender_id, func(display_name: String) -> void:
			if is_instance_valid(meta):
				var short_time := _format_message_time(ts_str)
				if short_time != "":
					meta.text = "%s • %s" % [display_name, short_time]
				else:
					meta.text = display_name
		)

	call_deferred("_scroll_to_bottom")

func _make_bubble_panel(mine: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.7607843, 0.019607844, 0.019607844, 1) if mine else Color(0.93, 0.93, 0.93, 1)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16 if mine else 4
	style.corner_radius_bottom_right = 4 if mine else 16
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _format_message_time(ts: String) -> String:
	var s: String = ts.strip_edges()
	if s == "":
		return ""
	if s.find(" ") != -1:
		var parts := s.split(" ")
		if parts.size() >= 2:
			var timepart := parts[1]
			if timepart.length() >= 5:
				return timepart.substr(0,5)
			return timepart
	if s.length() >= 5:
		return s.substr(0,5)
	return s

func _scroll_to_bottom() -> void:
	if _chat_scroll == null:
		return
	await get_tree().process_frame
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)

func _print_debug(message: String) -> void:
	print("Guidance chat: %s" % message)

func _mark_messages_read(ids: Array) -> void:
	if ids.size() == 0:
		return

	var updates := {}
	for mid in ids:
		updates["messages/%s/read" % mid] = true

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		if code != 200:
			_print_debug("mark read failed: %d" % code)
		else:
			_print_debug("marked %d messages read in conversation %s" % [ids.size(), _conversation_id])
	)
	var headers := ["Content-Type: application/json"]
	var url = _rtdb_url(_conversation_path if not _conversation_path.is_empty() else "conversations/" + _conversation_id)
	_print_debug("marking messages read at: %s for conversation: %s" % [url, _conversation_id])
	http.request(url, headers, HTTPClient.METHOD_PATCH, JSON.stringify(updates))
