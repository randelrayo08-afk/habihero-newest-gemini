extends Node

signal profile_updated(user_id: String)

const USERS_PATH: String = "users"
const PROFILE_NODE: String = "profile"
const JOURNAL_NODE: String = "journal"
const PROGRESS_NODE: String = "progress"
const MOODCHECK_NODE: String = "moodcheck"
const TASK_PROOF_NODE: String = "tasks"
const STORE_PATH: String = "user://adventure_habi_store.json"
const GOOGLE_SERVICES_PATH: String = "res://google-services.json"
const FIREBASE_AUTH_SIGNUP_URL: String = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key="
const FIREBASE_AUTH_LOGIN_URL: String = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="

var _db: Node
var _auth_http: HTTPRequest
var _firebase_api_key: String = ""
var _store_cache: Dictionary = {}
var _store_loaded: bool = false
var _next_coin_callback_id: int = 1
var _pending_coin_callbacks: Dictionary = {}
var _pending_coin_reward_callbacks: Dictionary = {}
var _pending_experience_callbacks: Dictionary = {}
var _pending_streak_callbacks: Dictionary = {}
var _auth_request_active: bool = false

func _ready() -> void:
	_resolve_db()
	_load_local_store()
	_auth_http = HTTPRequest.new()
	_auth_http.name = "FirebaseEmailPasswordAuthHttp"
	add_child(_auth_http)
	_load_firebase_api_key()

func _load_firebase_api_key() -> void:
	var file: FileAccess = FileAccess.open(GOOGLE_SERVICES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var clients: Variant = parsed.get("client", [])
	if not clients is Array or clients.is_empty() or not clients[0] is Dictionary:
		return
	var api_keys: Variant = clients[0].get("api_key", [])
	if api_keys is Array and not api_keys.is_empty() and api_keys[0] is Dictionary:
		_firebase_api_key = str(api_keys[0].get("current_key", "")).strip_edges()

func _safe_invoke_callback(callback: Callable, arg1: Variant = null, arg2: Variant = null, arg3: Variant = null) -> void:
	"""Safely invoke a callback with proper null and validity checks."""
	if not _callback_target_is_alive(callback):
		return
	# Invoke callback directly - the FirebaseRTDB layer already has slot management
	if arg3 != null:
		callback.call(arg1, arg2, arg3)
	elif arg2 != null:
		callback.call(arg1, arg2)
	elif arg1 != null:
		callback.call(arg1)
	else:
		callback.call()

func _extract_uid_from_auth_token(auth_token: String) -> String:
	var token: String = auth_token.strip_edges()
	if token.begins_with("Bearer "):
		token = token.substr("Bearer ".length()).strip_edges()
	if token.is_empty() or token.count(".") < 2:
		return ""
	var parts: PackedStringArray = token.split(".")
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
				if uid != "" and uid != "guest_user":
					return uid
	return ""

func _normalize_user_identity_candidate(candidate: Variant) -> String:
	var value: String = str(candidate).strip_edges()
	if value.is_empty() or value == "guest_user":
		return ""
	if value.begins_with("Bearer "):
		value = value.substr("Bearer ".length()).strip_edges()
	if value.begins_with("local:"):
		value = value.substr("local:".length()).strip_edges()
	if value.is_empty() or value == "guest_user":
		return ""
	if value.count(".") >= 2:
		var token_uid: String = _extract_uid_from_auth_token(value)
		if token_uid != "":
			return token_uid
	return value

func get_current_user_id() -> String:
	if has_method("_resolve_current_user_id"):
		var resolved: String = str(call("_resolve_current_user_id")).strip_edges()
		if resolved != "" and resolved != "guest_user":
			return resolved

	var session: Node = null
	if get_tree() != null and get_tree().root != null:
		session = get_tree().root.get_node_or_null("UserSession")
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	if session != null:
		if session.has_method("get_current_user_id"):
			var session_uid: String = _normalize_user_identity_candidate(session.call("get_current_user_id"))
			if session_uid != "":
				return session_uid
		if session.has_method("get_current_user_email"):
			var session_email: String = str(session.call("get_current_user_email")).strip_edges()
			if session_email != "" and session_email != "guest_user":
				return session_email

	if is_inside_tree() and get_parent() != null:
		var root_node: Node = get_tree().root
		if root_node != null:
			var auth_node: Node = root_node.get_node_or_null("FirebaseAuthManager")
			if auth_node != null and auth_node != self:
				if auth_node.has_method("get_current_user_id"):
					var node_uid: String = _normalize_user_identity_candidate(auth_node.call("get_current_user_id"))
					if node_uid != "":
						return node_uid
	return "guest_user"

func get_current_user_name() -> String:
	return "Guest"

func get_current_user_email() -> String:
	return ""

func get_current_user_token() -> String:
	return ""

func get_id_token() -> String:
	return ""

func get_token() -> String:
	return ""

func get_auth_token() -> String:
	return ""

func _callback_target_is_alive(callback: Callable) -> bool:
	if callback == null:
		return false
	if not callback.is_valid():
		return false
	# Avoid direct object-slot probing on invalid or expired Callable instances.
	# Godot can raise the "slot > slot_max" error when a dead callback target is inspected.
	return true

func _resolve_db() -> void:
	if _db != null:
		return
	if get_tree() != null and get_tree().root != null:
		_db = get_tree().root.get_node_or_null("FirebaseRTDB")
	if _db == null and Engine.has_singleton("FirebaseRTDB"):
		_db = Engine.get_singleton("FirebaseRTDB")
	if _db == null:
		push_warning("FirebaseRTDB autoload is not available")

func _send_auth_request(url: String, payload: String, callback: Callable = Callable()) -> void:
	if _auth_http == null:
		if callback.is_valid():
			callback.call(false, "Firebase authentication HTTP client is unavailable.")
		return
	if _auth_request_active:
		if callback.is_valid():
			callback.call(false, "A Firebase sign-in request is already in progress. Please wait a moment.")
		return
	if _auth_http.has_method("get_http_client_status") and _auth_http.get_http_client_status() == HTTPClient.STATUS_REQUESTING:
		if _auth_http.has_method("cancel_request"):
			_auth_http.cancel_request()
	_auth_request_active = true
	_auth_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, payload)

func sign_up(email: String, password: String, display_name: String, grade: String = "", section: String = "", callback: Callable = Callable()) -> void:
	_resolve_db()
	_load_local_store()
	if _db == null or not _db.has_method("write_json") or _auth_http == null:
		if callback.is_valid():
			callback.call(false, "FirebaseRTDB is unavailable.")
		return
	if _firebase_api_key.is_empty():
		if callback.is_valid():
			callback.call(false, "Firebase Web API key is missing from google-services.json.")
		return

	var payload: Dictionary = {
		"name": display_name,
		"email": email,
		"created_at": Time.get_datetime_string_from_system(false, true),
		"grade": grade,
		"section": section,
		"coin_balance": 0  # New users start with zero coins
	}
	var auth_payload: Dictionary = {"email": email, "password": password, "returnSecureToken": true}
	_send_auth_request(FIREBASE_AUTH_SIGNUP_URL + _firebase_api_key.uri_encode(), JSON.stringify(auth_payload), callback)
	_auth_http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		_auth_request_active = false
		var auth_response: Variant = JSON.parse_string(body.get_string_from_utf8())
		var auth_ok: bool = result == OK and response_code >= 200 and response_code < 300 and auth_response is Dictionary
		if not auth_ok:
			if callback.is_valid():
				callback.call(false, _build_error_message(response_code, auth_response))
			return
		var firebase_uid: String = str(auth_response.get("localId", "")).strip_edges()
		var id_token: String = str(auth_response.get("idToken", "")).strip_edges()
		if firebase_uid.is_empty() or id_token.is_empty():
			if callback.is_valid():
				callback.call(false, "Firebase authentication returned no user identity.")
			return
		var user_root_payload: Dictionary = {PROFILE_NODE: payload, JOURNAL_NODE: {}, PROGRESS_NODE: {}}
		if _db.has_method("set_auth_token"):
			_db.set_auth_token(id_token)
		var email_key: String = _safe_key(email)
		_write_local_user(email_key, user_root_payload)
		_db.write_json(USERS_PATH + "/" + email_key, user_root_payload, func(write_result: int, write_code: int, write_body: Variant):
			var write_ok: bool = write_result == OK and write_code >= 200 and write_code < 300
			if callback.is_valid():
				if write_ok:
					callback.call(true, {"message": "Saved to Firebase", "firebase_uid": firebase_uid, "email": email, "auth_token": id_token})
				else:
					callback.call(false, _build_error_message(write_code, write_body))
		)
	, CONNECT_ONE_SHOT)

func sign_in(email: String, password: String, callback: Callable = Callable()) -> void:
	_resolve_db()
	_load_local_store()
	if _db == null or not _db.has_method("read_json") or _auth_http == null or _firebase_api_key.is_empty():
		if callback.is_valid():
			callback.call(false, "Firebase authentication is unavailable.")
		return

	var auth_payload: Dictionary = {"email": email, "password": password, "returnSecureToken": true}
	_send_auth_request(FIREBASE_AUTH_LOGIN_URL + _firebase_api_key.uri_encode(), JSON.stringify(auth_payload), callback)
	_auth_http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		_auth_request_active = false
		var response_text: String = body.get_string_from_utf8()
		var auth_response: Variant = JSON.parse_string(response_text)
		var auth_ok: bool = result == OK and response_code >= 200 and response_code < 300 and auth_response is Dictionary
		if not auth_ok:
			if callback.is_valid():
				callback.call(false, _build_error_message(response_code, auth_response))
			return
		var firebase_uid: String = str(auth_response.get("localId", "")).strip_edges()
		var id_token: String = str(auth_response.get("idToken", "")).strip_edges()
		if firebase_uid.is_empty() or id_token.is_empty():
			if callback.is_valid():
				callback.call(false, "Firebase authentication returned no user identity.")
			return
		if _db.has_method("set_auth_token"):
			_db.set_auth_token(id_token)
		var email_key: String = _safe_key(email)
		_db.read_json(USERS_PATH + "/" + email_key, func(read_result: int, read_code: int, read_body: Variant):
			var read_ok: bool = read_result == OK and read_code >= 200 and read_code < 300 and read_body is Dictionary
			if not read_ok:
				if callback.is_valid():
					callback.call(false, _build_error_message(read_code, read_body))
				return
			var profile: Dictionary = read_body.get(PROFILE_NODE, {}) if read_body is Dictionary else {}
			if not profile is Dictionary or profile.is_empty():
				if callback.is_valid():
					callback.call(false, "Firebase account exists but its profile was not found.")
				return
			var result_body: Dictionary = profile.duplicate(true)
			result_body["firebase_uid"] = firebase_uid
			result_body["auth_token"] = id_token
			if callback.is_valid():
				callback.call(true, result_body)
		)
	, CONNECT_ONE_SHOT)

func save_journal_entry(user_id: String, entry_text: String, callback: Callable = Callable()) -> void:
	_resolve_db()
	_load_local_store()
	var fallback_key: String = _storage_user_key(user_id)
	if fallback_key.strip_edges().is_empty():
		if callback.is_valid():
			callback.call(false, "Missing user id for journal save")
		return

	var write_entry_for_key: Callable = func(resolved_user_key: String) -> void:
		var safe_user_key: String = str(resolved_user_key).strip_edges()
		if safe_user_key.is_empty():
			safe_user_key = fallback_key
		var unique_stamp: String = str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_msec())
		var safe_entry_key: String = "entry_" + unique_stamp.replace(".", "_")
		var payload: Dictionary = {
			"user_id": user_id,
			"entry": entry_text,
			"created_at": Time.get_datetime_string_from_system(false, true),
			"timestamp": unique_stamp
		}
		_write_local_document(JOURNAL_NODE, safe_user_key, safe_entry_key, payload)
		if _db != null and _db.has_method("update_json"):
			var update_payload: Dictionary = {}
			update_payload[safe_entry_key] = payload
			print("FirebaseAuthManager: journal update path=", USERS_PATH + "/" + safe_user_key + "/" + JOURNAL_NODE, " key=", safe_entry_key)
			_db.update_json(USERS_PATH + "/" + safe_user_key + "/" + JOURNAL_NODE, update_payload, func(result: int, response_code: int, body: Variant):
				var ok: bool = result == OK and response_code >= 200 and response_code < 300
				if callback.is_valid():
					callback.call(ok, body if not ok else payload)
			)
		elif _db != null and _db.has_method("write_json"):
			_db.write_json(USERS_PATH + "/" + safe_user_key + "/" + JOURNAL_NODE + "/" + safe_entry_key, payload, func(result: int, response_code: int, body: Variant):
				var ok: bool = result == OK and response_code >= 200 and response_code < 300
				if callback.is_valid():
					callback.call(ok, body if not ok else payload)
			)
		else:
			if callback.is_valid():
				callback.call(true, payload)

	if _db != null and _db.has_method("read_json"):
		_db.read_json(USERS_PATH, func(result: int, response_code: int, body: Variant):
			var resolved_key: String = fallback_key
			if result == OK and response_code >= 200 and response_code < 300 and body is Dictionary:
				resolved_key = _pick_best_user_key_for_user(body, user_id, fallback_key)
			write_entry_for_key.call(resolved_key)
		)
		return
	write_entry_for_key.call(fallback_key)

func load_journal_entries(user_id: String, callback: Callable = Callable()) -> void:
	_resolve_db()
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(true, {})
		return

	print("\n📖 [load_journal_entries] user_id='", user_id, "'")
	var candidate_keys: Array = []
	var seen: Dictionary = {}
	var add_candidate: Callable = func(value: String) -> void:
		var normalized: String = str(value).strip_edges()
		if normalized.is_empty() or seen.has(normalized):
			return
		seen[normalized] = true
		candidate_keys.append(normalized)
	var raw_user_id: String = str(user_id).strip_edges()
	if raw_user_id != "":
		add_candidate.call(raw_user_id)
		add_candidate.call(raw_user_id.to_lower())
		add_candidate.call(_safe_key(raw_user_id))
	var safe_user_key: String = _storage_user_key(user_id)
	if safe_user_key != "":
		add_candidate.call(safe_user_key)
	var session: Node = get_tree().root.get_node_or_null("UserSession") if get_tree() != null and get_tree().root != null else null
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	if session != null:
		if session.has_method("get_current_user_email"):
			var email: String = str(session.call("get_current_user_email")).strip_edges()
			if email != "":
				add_candidate.call(email)
				add_candidate.call(_safe_key(email))
		if session.has_method("get_current_user_id"):
			var current_id: String = str(session.call("get_current_user_id")).strip_edges()
			if current_id != "":
				add_candidate.call(current_id)
				add_candidate.call(_safe_key(current_id))
		var email_prop: String = _node_string_property(session, "current_user_email")
		if email_prop != "":
			add_candidate.call(email_prop)
			add_candidate.call(_safe_key(email_prop))
		var current_id_prop: String = _node_string_property(session, "current_user_id")
		if current_id_prop != "":
			add_candidate.call(current_id_prop)
			add_candidate.call(_safe_key(current_id_prop))

	print("  📋 Candidate keys: ", candidate_keys)
	var merged_entries: Dictionary = {}
	var pending_paths: Array = []
	for key in candidate_keys:
		var normalized: String = str(key).strip_edges()
		if normalized.is_empty():
			continue
		var candidate_path: String = USERS_PATH + "/" + normalized + "/" + JOURNAL_NODE
		if not pending_paths.has(candidate_path):
			pending_paths.append(candidate_path)

	if pending_paths.is_empty():
		pending_paths.append(USERS_PATH)

	print("  🔍 Querying paths: ", pending_paths)
	var pending_count: Array = [pending_paths.size()]
	var final_callback: Callable = callback
	for journal_path in pending_paths:
		_db.read_json(journal_path, func(result: int, response_code: int, body: Variant):
			pending_count[0] -= 1
			var ok: bool = result == OK and response_code >= 200 and response_code < 300
			print("    ✓ Path read: ", journal_path, " ok=", ok, " response_code=", response_code)
			if ok and body is Dictionary:
				print("      Entries found: ", body.keys().size())
				if journal_path == USERS_PATH:
					for user_key in body.keys():
						var user_data: Variant = body.get(user_key)
						if user_data is Dictionary:
							var user_journal: Variant = user_data.get(JOURNAL_NODE, {})
							if user_journal is Dictionary:
								for journal_key in user_journal.keys():
									var journal_value: Variant = user_journal.get(journal_key)
									if journal_value is Dictionary:
										merged_entries[journal_key] = journal_value
				else:
					for journal_key in body.keys():
						var value: Variant = body.get(journal_key)
						if value is Dictionary:
							merged_entries[journal_key] = value
			if pending_count[0] <= 0:
				print("  ✓ All paths loaded, total entries: ", merged_entries.size())
				if final_callback.is_valid():
					final_callback.call(true, merged_entries)
		)

func save_progress(user_id: String, progress_data: Dictionary, callback: Callable = Callable()) -> void:
	_resolve_db()
	_load_local_store()
	var safe_user_key: String = _storage_user_key(user_id)
	if safe_user_key.strip_edges().is_empty():
		if callback.is_valid():
			callback.call(false, "Missing user id for progress save")
		return
	var payload: Dictionary = {
		"user_id": user_id,
		"updated_at": Time.get_datetime_string_from_system(false, true),
		"data": progress_data
	}
	_write_local_document(PROGRESS_NODE, safe_user_key, "latest", payload)
	if _db != null and _db.has_method("update_json"):
		_db.update_json(USERS_PATH + "/" + safe_user_key + "/" + PROGRESS_NODE, {"latest": payload}, func(result: int, response_code: int, body: Variant):
			var ok: bool = result == OK and response_code >= 200 and response_code < 300
			if callback.is_valid():
				callback.call(ok, body if not ok else payload)
		)
	elif _db != null and _db.has_method("write_json"):
		_db.write_json(USERS_PATH + "/" + safe_user_key + "/" + PROGRESS_NODE + "/latest", payload, func(result: int, response_code: int, body: Variant):
			var ok: bool = result == OK and response_code >= 200 and response_code < 300
			if callback.is_valid():
				callback.call(ok, body if not ok else payload)
		)
	else:
		if callback.is_valid():
			callback.call(true, payload)

func save_profile_attributes(user_id: String, attributes: Dictionary, callback: Callable = Callable()) -> void:
	"""Save question responses as profile attributes for task personalization.
	This updates the user profile with question answers like age, gender, interests, mood."""
	_resolve_db()
	_load_local_store()
	var safe_user_key: String = _resolve_profile_user_key(user_id)
	if safe_user_key.strip_edges().is_empty():
		if callback.is_valid():
			callback.call(false, "Missing user id for profile update")
		return
	
	# Only update provided attributes, keep existing profile data
	var update_payload: Dictionary = attributes.duplicate(true)
	update_payload["updated_at"] = Time.get_datetime_string_from_system(false, true)
	print("FirebaseAuthManager: updating profile for ", safe_user_key, " fields=", update_payload.keys())
	var local_users: Dictionary = _store_cache.get("users", {})
	if not local_users is Dictionary:
		local_users = {}
	var local_user: Dictionary = local_users.get(safe_user_key, {})
	if not local_user is Dictionary:
		local_user = {}
	var local_profile: Dictionary = local_user.get(PROFILE_NODE, {})
	if not local_profile is Dictionary:
		local_profile = {}
	local_profile.merge(update_payload)
	local_user[PROFILE_NODE] = local_profile
	local_users[safe_user_key] = local_user
	_store_cache["users"] = local_users
	_save_local_store()
	
	var firebase_path: String = USERS_PATH + "/" + safe_user_key + "/" + PROFILE_NODE
	if _db != null and _db.has_method("update_json"):
		_db.update_json(firebase_path, update_payload, func(result: int, response_code: int, body: Variant):
			var ok: bool = result == OK and response_code >= 200 and response_code < 300
			if ok:
				profile_updated.emit(safe_user_key)
			_safe_invoke_callback(callback, ok, body if not ok else update_payload)
		)
	elif _db != null and _db.has_method("write_json"):
		# Fallback: read current profile, merge, then write
		_db.read_json(firebase_path, func(_read_result: int, _read_code: int, read_body: Variant):
			var current_profile: Dictionary = {}
			if read_body is Dictionary:
				current_profile = read_body.duplicate(true)
			current_profile.merge(update_payload)
			_db.write_json(firebase_path, current_profile, func(result: int, response_code: int, body: Variant):
				var ok: bool = result == OK and response_code >= 200 and response_code < 300
				if ok:
					profile_updated.emit(safe_user_key)
				_safe_invoke_callback(callback, ok, body if not ok else current_profile)
			)
		)
	else:
		profile_updated.emit(safe_user_key)
		if callback.is_valid():
			callback.call(true, update_payload)

func load_profile(user_id: String, callback: Callable = Callable()) -> void:
	"""Load user profile for personalization (age, gender, interests, mood, etc)."""
	_resolve_db()
	var safe_user_key: String = _resolve_profile_user_key(user_id)
	if safe_user_key.strip_edges().is_empty():
		if callback.is_valid():
			callback.call(false, {})
		return
	
	var firebase_path: String = USERS_PATH + "/" + safe_user_key + "/" + PROFILE_NODE
	if _db != null and _db.has_method("read_json"):
		var db_ref = _db  # Capture db reference for use in lambda
		db_ref.read_json(firebase_path, func(result: int, response_code: int, body: Variant):
			var ok: bool = result == OK and response_code >= 200 and response_code < 300
			if ok and body is Dictionary and not body.is_empty():
				if callback.is_valid():
					callback.call(true, body)
				return
			var legacy_user_key: String = user_id.strip_edges().to_lower()
			if legacy_user_key != safe_user_key and not legacy_user_key.is_empty():
				var legacy_path: String = USERS_PATH + "/" + legacy_user_key + "/" + PROFILE_NODE
				if db_ref != null and db_ref.has_method("read_json"):
					db_ref.read_json(legacy_path, func(legacy_result: int, legacy_code: int, legacy_body: Variant):
						var legacy_ok: bool = legacy_result == OK and legacy_code >= 200 and legacy_code < 300 and legacy_body is Dictionary and not legacy_body.is_empty()
						if legacy_ok and db_ref != null and db_ref.has_method("update_json"):
							db_ref.update_json(firebase_path, legacy_body)
						if callback.is_valid():
							callback.call(legacy_ok, legacy_body if legacy_ok else {})
					)
					return
			if callback.is_valid():
				callback.call(false, {})
		)
	elif callback.is_valid():
		callback.call(false, {})

func load_coin_balance(user_id: String, callback: Callable = Callable()) -> void:
	var callback_id: int = _next_coin_callback_id
	_next_coin_callback_id += 1
	_pending_coin_callbacks[callback_id] = callback
	load_profile(user_id, Callable(self, "_on_coin_profile_loaded").bind(callback_id, user_id))

func _on_coin_profile_loaded(ok: bool, profile: Variant, callback_id: int, user_id: String) -> void:
	var callback: Callable = _pending_coin_callbacks.get(callback_id, Callable())
	_pending_coin_callbacks.erase(callback_id)
	var balance: int = 0
	if ok and profile is Dictionary:
		balance = max(0, int(profile.get("coin_balance", 0)))
	else:
		var local_profile: Dictionary = _load_local_user(_storage_user_key(user_id))
		balance = max(0, int(local_profile.get("coin_balance", 0)))
	if _callback_target_is_alive(callback):
		callback.call(true, balance)

func add_coins(user_id: String, amount: int, callback: Callable = Callable()) -> void:
	var reward: int = max(0, amount)
	if reward == 0:
		load_coin_balance(user_id, callback)
		return
	var callback_id: int = _next_coin_callback_id
	_next_coin_callback_id += 1
	_pending_coin_reward_callbacks[callback_id] = callback
	load_coin_balance(user_id, Callable(self, "_on_coin_balance_loaded_for_reward").bind(callback_id, user_id, reward))

func _on_coin_balance_loaded_for_reward(_ok: bool, current_balance: Variant, callback_id: int, user_id: String, reward: int) -> void:
	var new_balance: int = max(0, int(current_balance)) + reward
	save_profile_attributes(user_id, {"coin_balance": new_balance}, Callable(self, "_on_coin_reward_saved").bind(callback_id, new_balance))

func _on_coin_reward_saved(ok: bool, _body: Variant, callback_id: int, new_balance: int) -> void:
	var callback: Callable = _pending_coin_reward_callbacks.get(callback_id, Callable())
	_pending_coin_reward_callbacks.erase(callback_id)
	if ok:
		_trigger_game_sound("coin_gain")
	if _callback_target_is_alive(callback):
		callback.call(ok, new_balance)

func _trigger_game_sound(sound_name: String) -> void:
	if get_tree() == null or get_tree().root == null:
		return
	var audio_node: Node = get_tree().root.get_node_or_null("AdventureAudio")
	if audio_node == null:
		return
	match sound_name:
		"coin_gain":
			if audio_node.has_method("play_coin_gain"):
				audio_node.call("play_coin_gain")
		"exp_gain":
			if audio_node.has_method("play_exp_gain"):
				audio_node.call("play_exp_gain")
		"potion_buy":
			if audio_node.has_method("play_potion_buy"):
				audio_node.call("play_potion_buy")
		_:
			pass

func save_coin_balance(user_id: String, amount: int, callback: Callable = Callable()) -> void:
	"""Save a specific coin balance amount to the database"""
	var safe_amount: int = max(0, amount)
	save_profile_attributes(user_id, {"coin_balance": safe_amount}, callback)

func load_experience(user_id: String, callback: Callable = Callable()) -> void:
	print("FirebaseAuthManager: loading experience from users/", _storage_user_key(user_id), "/profile")
	var callback_id: int = _next_coin_callback_id
	_next_coin_callback_id += 1
	_pending_experience_callbacks[callback_id] = callback
	load_profile(user_id, Callable(self, "_on_experience_profile_loaded").bind(callback_id, user_id))

func _on_experience_profile_loaded(ok: bool, profile: Variant, callback_id: int, user_id: String) -> void:
	var callback: Callable = _pending_experience_callbacks.get(callback_id, Callable())
	_pending_experience_callbacks.erase(callback_id)
	var experience: int = 0
	if ok and profile is Dictionary:
		experience = max(0, int(profile.get("experience", 0)))
	else:
		var local_profile: Dictionary = _load_local_user(_storage_user_key(user_id))
		experience = max(0, int(local_profile.get("experience", 0)))
	print("FirebaseAuthManager: experience read ok=", ok, " value=", experience)
	if _callback_target_is_alive(callback):
		callback.call(true, experience)

func add_experience(user_id: String, amount: int, callback: Callable = Callable()) -> void:
	var reward: int = max(0, amount)
	load_experience(user_id, func(_ok: bool, current_experience: Variant):
		var new_experience: int = max(0, int(current_experience)) + reward
		_check_and_update_level(user_id, new_experience)
		save_profile_attributes(user_id, {"experience": new_experience}, func(ok: bool, _body: Variant):
			if ok:
				_trigger_game_sound("exp_gain")
			if _callback_target_is_alive(callback):
				callback.call(ok, new_experience)
		)
	)

func _check_and_update_level(user_id: String, current_experience: int) -> void:
	"""Check if experience gained warrants a level up and update profile"""
	load_level(user_id, func(_ok: bool, current_level: Variant):
		var level: int = max(1, int(current_level))
		var exp_required: int = level * 100  # exp_to_level_up = level * 100
		if current_experience >= exp_required:
			var new_level: int = level + 1
			print("FirebaseAuthManager: Level up! New level: ", new_level)
			save_profile_attributes(user_id, {"level": new_level}, Callable())
	)

func load_level(user_id: String, callback: Callable = Callable()) -> void:
	"""Load current level from profile"""
	print("FirebaseAuthManager: loading level from users/", _storage_user_key(user_id), "/profile")
	load_profile(user_id, func(ok: bool, profile: Variant):
		var level: int = 1
		if ok and profile is Dictionary:
			level = max(1, int(profile.get("level", 1)))
		else:
			var local_profile: Dictionary = _load_local_user(_storage_user_key(user_id))
			level = max(1, int(local_profile.get("level", 1)))
		print("FirebaseAuthManager: level read ok=", ok, " value=", level)
		if _callback_target_is_alive(callback):
			callback.call(true, level)
	)

func save_level(user_id: String, level: int, callback: Callable = Callable()) -> void:
	"""Save level to profile"""
	var safe_level: int = max(1, level)
	save_profile_attributes(user_id, {"level": safe_level}, callback)

func get_todays_mood(user_id: String, callback: Callable = Callable()) -> void:
	"""Retrieve today's mood from moodcheck entries"""
	load_moodcheck_entries(user_id, func(ok: bool, entries: Variant):
		var today_mood: String = ""
		if ok and entries is Dictionary:
			var current_date: String = Time.get_datetime_string_from_system(false, false).substr(0, 10)
			# Entries are stored with timestamp keys, iterate to find today's
			for key in entries.keys():
				var entry: Variant = entries.get(key)
				if entry is Dictionary:
					var saved_at: String = str(entry.get("saved_at", ""))
					if saved_at.begins_with(current_date):
						today_mood = str(entry.get("mood", ""))
						break
		if _callback_target_is_alive(callback):
			callback.call(ok, today_mood if not today_mood.is_empty() else "not_set")
	)

func get_weekly_moods(user_id: String, callback: Callable = Callable()) -> void:
	"""Retrieve moods for the last 7 days"""
	load_moodcheck_entries(user_id, func(ok: bool, entries: Variant):
		var weekly_moods: Array[String] = []
		if ok and entries is Dictionary:
			var current_date_obj: Dictionary = Time.get_datetime_dict_from_system(false)
			for day_offset in range(7):
				var target_date_obj: Dictionary = current_date_obj.duplicate()
				target_date_obj["day"] = target_date_obj.get("day", 1) - day_offset
				var target_date: String = "%04d-%02d-%02d" % [target_date_obj.get("year", 2025), target_date_obj.get("month", 1), target_date_obj.get("day", 1)]
				var found: bool = false
				for key in entries.keys():
					var entry: Variant = entries.get(key)
					if entry is Dictionary:
						var saved_at: String = str(entry.get("saved_at", ""))
						if saved_at.begins_with(target_date):
							weekly_moods.append(str(entry.get("mood", "")))
							found = true
							break
				if not found:
					weekly_moods.append("")  # Empty for days without mood entry
		if _callback_target_is_alive(callback):
			callback.call(ok, weekly_moods)
	)

func save_moodcheck_entry(user_id: String, mood_payload: Dictionary, callback: Callable = Callable()) -> void:
	_resolve_db()
	_load_local_store()
	var safe_user_key: String = _storage_user_key(user_id)
	if safe_user_key.strip_edges().is_empty():
		if callback.is_valid():
			callback.call(false, "Missing user id for moodcheck save")
		return
	var timestamp: String = str(Time.get_unix_time_from_system()).replace(".", "_")
	var safe_entry_key: String = "mood_" + timestamp
	var payload: Dictionary = mood_payload.duplicate()
	payload["saved_at"] = Time.get_datetime_string_from_system(false, true)
	_update_checkin_streak(user_id)
	_write_local_document(MOODCHECK_NODE, safe_user_key, safe_entry_key, payload)
	if _db != null and _db.has_method("update_json"):
		var update_payload: Dictionary = {}
		update_payload[safe_entry_key] = payload
		_db.update_json(USERS_PATH + "/" + safe_user_key + "/" + MOODCHECK_NODE, update_payload, func(result: int, response_code: int, body: Variant):
			if _callback_target_is_alive(callback):
				var ok: bool = result == OK and response_code >= 200 and response_code < 300
				callback.call(ok, body if not ok else payload)
		)
	elif _db != null and _db.has_method("write_json"):
		_db.write_json(USERS_PATH + "/" + safe_user_key + "/" + MOODCHECK_NODE + "/" + safe_entry_key, payload, func(result: int, response_code: int, body: Variant):
			if _callback_target_is_alive(callback):
				var ok: bool = result == OK and response_code >= 200 and response_code < 300
				callback.call(ok, body if not ok else payload)
		)
	else:
		if callback != null and callback.is_valid():
			callback.call(true, payload)

func _update_checkin_streak(user_id: String) -> void:
	load_profile(user_id, Callable(self, "_on_streak_profile_loaded").bind(user_id))

func _on_streak_profile_loaded(ok: bool, profile: Variant, user_id: String) -> void:
	var current_date: String = Time.get_datetime_string_from_system(false, false).substr(0, 10)
	var previous_date: String = ""
	var previous_streak: int = 0
	if ok and profile is Dictionary:
		previous_date = str(profile.get("last_checkin_date", ""))
		previous_streak = max(0, int(profile.get("checkin_streak", 0)))
	else:
		var local_profile: Dictionary = _load_local_user(_storage_user_key(user_id))
		previous_date = str(local_profile.get("last_checkin_date", ""))
		previous_streak = max(0, int(local_profile.get("checkin_streak", 0)))
	if previous_date == current_date:
		return
	var new_streak: int = 1
	if _date_difference_days(previous_date, current_date) == 1:
		new_streak = previous_streak + 1
	save_profile_attributes(user_id, {"checkin_streak": new_streak, "last_checkin_date": current_date})

func load_checkin_streak(user_id: String, callback: Callable = Callable()) -> void:
	var callback_id: int = _next_coin_callback_id
	_next_coin_callback_id += 1
	_pending_streak_callbacks[callback_id] = callback
	load_profile(user_id, Callable(self, "_on_streak_profile_for_display").bind(callback_id, user_id))

func _on_streak_profile_for_display(ok: bool, profile: Variant, callback_id: int, user_id: String) -> void:
	var callback: Callable = _pending_streak_callbacks.get(callback_id, Callable())
	_pending_streak_callbacks.erase(callback_id)
	var streak: int = 0
	if ok and profile is Dictionary:
		streak = max(0, int(profile.get("checkin_streak", 0)))
	else:
		var local_profile: Dictionary = _load_local_user(_storage_user_key(user_id))
		streak = max(0, int(local_profile.get("checkin_streak", 0)))
	if _callback_target_is_alive(callback):
		callback.call(true, streak)

func _date_difference_days(previous_date: String, current_date: String) -> int:
	if previous_date.is_empty() or current_date.is_empty():
		return 0
	var previous_dict: Dictionary = Time.get_datetime_dict_from_datetime_string(previous_date + " 00:00:00", false)
	var current_dict: Dictionary = Time.get_datetime_dict_from_datetime_string(current_date + " 00:00:00", false)
	if previous_dict.is_empty() or current_dict.is_empty():
		return 0
	if not previous_dict.has("year") or not current_dict.has("year"):
		return 0
	var previous_unix: int = int(Time.get_unix_time_from_datetime_dict(previous_dict))
	var current_unix: int = int(Time.get_unix_time_from_datetime_dict(current_dict))
	var delta_days: int = int(float(current_unix - previous_unix) / 86400.0)
	return max(0, delta_days)

func load_moodcheck_entries(user_id: String, callback: Callable = Callable()) -> void:
	_resolve_db()
	_load_local_store()
	var safe_user_key: String = _storage_user_key(user_id)
	if safe_user_key.is_empty():
		if callback.is_valid():
			callback.call(false, {})
		return

	var firebase_path := USERS_PATH + "/" + safe_user_key + "/" + MOODCHECK_NODE
	if _db != null and _db.has_method("read_json"):
		_db.read_json(firebase_path, func(result: int, response_code: int, body: Variant):
			if not _callback_target_is_alive(callback):
				return
			var ok: bool = result == OK and response_code >= 200 and response_code < 300 and body is Dictionary
			if ok:
				callback.call(true, body)
				return
			var fallback_users: Variant = _store_cache.get("users", {})
			var fallback_user: Variant = fallback_users.get(safe_user_key, {}) if fallback_users is Dictionary else {}
			var fallback_entries: Variant = fallback_user.get(MOODCHECK_NODE, {}) if fallback_user is Dictionary else {}
			callback.call(fallback_entries is Dictionary, fallback_entries if fallback_entries is Dictionary else {})
		)
		return

	var local_users: Variant = _store_cache.get("users", {})
	var local_user: Variant = local_users.get(safe_user_key, {}) if local_users is Dictionary else {}
	var local_entries: Variant = local_user.get(MOODCHECK_NODE, {}) if local_user is Dictionary else {}
	if callback.is_valid():
		callback.call(local_entries is Dictionary, local_entries if local_entries is Dictionary else {})

func resolve_task_reward_data(user_id: String, task_id: String, callback: Callable = Callable()) -> void:
	_resolve_db()
	var safe_user_key: String = _storage_user_key(user_id)
	if safe_user_key.strip_edges().is_empty() or task_id.strip_edges().is_empty():
		if callback.is_valid():
			callback.call(false, {})
		return
	if _db == null or not _db.has_method("read_json"):
		if callback.is_valid():
			callback.call(false, {})
		return
	var user_task_path: String = USERS_PATH + "/" + safe_user_key + "/tasks/" + task_id
	_db.read_json(user_task_path, func(result: int, response_code: int, body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if ok and body is Dictionary:
			var reward_coins: int = max(0, int(body.get("coins", body.get("reward_coins", 0))))
			var reward_exp: int = max(0, int(body.get("exp", body.get("xp", body.get("experience", 0)))))
			var reward_data: Dictionary = {
				"title": str(body.get("task_title", body.get("title", body.get("description", task_id)))).strip_edges(),
				"coins": reward_coins,
				"exp": reward_exp
			}
			if reward_data["title"].is_empty():
				reward_data["title"] = task_id
			if callback.is_valid():
				callback.call(true, reward_data)
			return
		var admin_task_path: String = "admin/tasks/" + task_id
		_db.read_json(admin_task_path, func(admin_result: int, admin_code: int, admin_body: Variant):
			var admin_ok: bool = admin_result == OK and admin_code >= 200 and admin_code < 300 and admin_body is Dictionary
			var reward_data: Dictionary = {"title": task_id, "coins": 0, "exp": 0}
			if admin_ok and admin_body is Dictionary:
				reward_data = {
					"title": str(admin_body.get("task_title", admin_body.get("title", admin_body.get("description", task_id)))).strip_edges(),
					"coins": max(0, int(admin_body.get("coins", admin_body.get("reward_coins", 0)))),
					"exp": max(0, int(admin_body.get("exp", admin_body.get("xp", admin_body.get("experience", 0)))))
				}
			if reward_data["title"].is_empty():
				reward_data["title"] = task_id
			if callback.is_valid():
				callback.call(admin_ok, reward_data)
		)
	)

func _estimate_automated_task_reward(task_title: String) -> Dictionary:
	var title: String = str(task_title).strip_edges()
	if title.is_empty():
		return {"title": title, "coins": 5, "exp": 25}
	var lower_title: String = title.to_lower()
	var minutes: int = 15
	if lower_title.find("prayer") != -1 or lower_title.find("bible") != -1 or lower_title.find("verse") != -1 or lower_title.find("devotional") != -1 or lower_title.find("reflection") != -1:
		minutes = 10
	elif lower_title.find("read") != -1 or lower_title.find("study") != -1 or lower_title.find("journal") != -1 or lower_title.find("write") != -1:
		minutes = 20
	elif lower_title.find("walk") != -1 or lower_title.find("exercise") != -1 or lower_title.find("sport") != -1:
		minutes = 30
	elif lower_title.find("serve") != -1 or lower_title.find("help") != -1 or lower_title.find("share") != -1:
		minutes = 25
	var base_points: int = max(5, int(round(float(minutes) / 2.0)))
	if lower_title.find("pray") != -1 or lower_title.find("bible") != -1 or lower_title.find("devotional") != -1:
		base_points += 2
	if lower_title.find("help") != -1 or lower_title.find("serve") != -1:
		base_points += 5
	var coins: int = max(5, base_points)
	var reward_exp: int = max(25, base_points * 5)
	return {"title": title, "coins": coins, "exp": reward_exp}

func resolve_automated_task_reward_data(task_title: String, task_id: String = "", callback: Callable = Callable()) -> void:
	var reward: Dictionary = _estimate_automated_task_reward(task_title)
	if task_id.strip_edges().is_empty():
		reward["id"] = task_id
	else:
		reward["id"] = task_id
	if callback.is_valid():
		callback.call(true, reward)

func complete_task_and_award_rewards(user_id: String, task_data: Dictionary, proof_payload: Dictionary = {}, callback: Callable = Callable()) -> void:
	var task_id: String = str(task_data.get("id", "")).strip_edges()
	var task_title: String = str(task_data.get("title", task_id)).strip_edges()
	var is_automated: bool = bool(task_data.get("is_automated", task_id.begins_with("generated_")))
	if user_id.strip_edges().is_empty() or task_id.is_empty():
		_safe_invoke_callback(callback, false, "Missing user id or task id")
		return

	var complete_persistence: Callable = func() -> void:
		if is_automated:
			_claim_automated_reward(user_id, task_id, task_title, task_data, proof_payload, callback)
			return

		mark_task_complete_for_user(user_id, task_id, func(ok: bool, body: Variant):
			if not ok:
				_safe_invoke_callback(callback, false, body)
				return
			_award_and_save_task(user_id, task_data, proof_payload, callback)
		)
	complete_persistence.call()

func _claim_automated_reward(user_id: String, task_id: String, _task_title: String, task_data: Dictionary, proof_payload: Dictionary, callback: Callable) -> void:
	_resolve_db()
	var safe_user_key: String = _storage_user_key(user_id)
	var claim_key: String = "%s_%s" % [_current_day_key(), task_id]
	var claim_path: String = USERS_PATH + "/" + safe_user_key + "/automated_reward_claims/" + claim_key
	if _db == null or not _db.has_method("read_json") or not _db.has_method("write_json"):
		_safe_invoke_callback(callback, false, "FirebaseRTDB unavailable for automated reward claim")
		return
	var backend: Node = get_tree().root.get_node_or_null("HabiBackend") if get_tree() != null and get_tree().root != null else null
	if backend == null or not backend.has_method("mark_task_complete"):
		_safe_invoke_callback(callback, false, "HabiBackend unavailable for automated task completion")
		return
	_db.read_json(claim_path, func(result: int, response_code: int, body: Variant):
		if result == OK and response_code >= 200 and response_code < 300 and body is Dictionary and not body.is_empty():
			_safe_invoke_callback(callback, false, "Automated goal reward already claimed today")
			return
		_db.write_json(claim_path, {"task_id": task_id, "claimed_at": Time.get_datetime_string_from_system(false, true)}, func(write_result: int, write_code: int, write_body: Variant):
			if write_result != OK or write_code < 200 or write_code >= 300:
				_safe_invoke_callback(callback, false, write_body)
				return
			backend.mark_task_complete(user_id, task_id, proof_payload, func(ok: bool, completion_body: Variant):
				if not ok:
					if _db.has_method("delete_json"):
						_db.delete_json(claim_path)
					_safe_invoke_callback(callback, false, completion_body)
					return
				_award_and_save_task(user_id, task_data, proof_payload, callback)
			)
		)
	)

func _award_and_save_task(user_id: String, task_data: Dictionary, proof_payload: Dictionary, callback: Callable) -> void:
	var task_id: String = str(task_data.get("id", "")).strip_edges()
	var task_title: String = str(task_data.get("title", task_id)).strip_edges()
	var is_automated: bool = bool(task_data.get("is_automated", task_id.begins_with("generated_")))
	var reward_callback: Callable = Callable(self, "_on_unified_reward_awarded").bind(user_id, task_id, task_title, is_automated, proof_payload, callback)
	if is_automated:
		var explicit_coins: int = max(0, int(task_data.get("coins", task_data.get("reward_coins", 0))))
		var explicit_experience: int = max(0, int(task_data.get("exp", task_data.get("xp", task_data.get("experience", 0)))))
		if explicit_coins > 0 or explicit_experience > 0:
			_award_reward_values(user_id, explicit_coins, explicit_experience, reward_callback)
			return
		award_automated_task_rewards(user_id, task_title, task_id, reward_callback)
	else:
		award_task_rewards(user_id, task_id, reward_callback)

func _award_reward_values(user_id: String, coins: int, experience: int, callback: Callable) -> void:
	if coins > 0:
		add_coins(user_id, coins, func(coins_ok: bool, _balance: Variant):
			if not coins_ok:
				_safe_invoke_callback(callback, false, "Failed to save coin reward")
				return
			if experience > 0:
				add_experience(user_id, experience, func(experience_ok: bool, _value: Variant):
					_safe_invoke_callback(callback, experience_ok, {"coins": coins, "exp": experience})
				)
			else:
				_safe_invoke_callback(callback, true, {"coins": coins, "exp": 0})
		)
	elif experience > 0:
		add_experience(user_id, experience, func(experience_ok: bool, _value: Variant):
			_safe_invoke_callback(callback, experience_ok, {"coins": 0, "exp": experience})
		)
	else:
		_safe_invoke_callback(callback, true, {"coins": 0, "exp": 0})

func _on_unified_reward_awarded(ok: bool, reward_data: Variant, user_id: String, task_id: String, task_title: String, is_automated: bool, proof_payload: Dictionary, callback: Callable) -> void:
	if not ok:
		_safe_invoke_callback(callback, false, reward_data)
		return
	var final_proof: Dictionary = proof_payload.duplicate(true)
	final_proof["task_id"] = task_id
	final_proof["task_title"] = task_title
	final_proof["automated"] = is_automated
	save_task_proof(user_id, task_id, final_proof, func(proof_ok: bool, proof_result: Variant):
		_safe_invoke_callback(callback, proof_ok, reward_data if proof_ok else proof_result)
	)

func _current_day_key() -> String:
	var date: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [date.year, date.month, date.day]

func award_automated_task_rewards(user_id: String, task_title: String, task_id: String = "", callback: Callable = Callable()) -> void:
	resolve_automated_task_reward_data(task_title, task_id, func(ok: bool, reward_data: Variant):
		if not ok or not reward_data is Dictionary:
			if _callback_target_is_alive(callback):
				callback.call(false, {})
			return
		var reward: Dictionary = reward_data as Dictionary
		var coins: int = max(0, int(reward.get("coins", 0)))
		var experience: int = max(0, int(reward.get("exp", 0)))
		if coins <= 0 and experience <= 0:
			if _callback_target_is_alive(callback):
				callback.call(true, reward)
			return
		if coins > 0 and has_method("add_coins"):
			call("add_coins", user_id, coins, func(_coin_ok: bool, _coin_balance: Variant):
				if experience > 0 and has_method("add_experience"):
					call("add_experience", user_id, experience, func(_exp_ok: bool, _exp_value: Variant):
						if _callback_target_is_alive(callback):
							callback.call(_coin_ok and _exp_ok, reward)
					)
				else:
					if _callback_target_is_alive(callback):
						callback.call(_coin_ok, reward)
			)
			return
		if experience > 0 and has_method("add_experience"):
			call("add_experience", user_id, experience, func(_exp_ok: bool, _exp_value: Variant):
				if _callback_target_is_alive(callback):
					callback.call(_exp_ok, reward)
			)
			return
		if _callback_target_is_alive(callback):
			callback.call(true, reward)
	)

func award_task_rewards(user_id: String, task_id: String, callback: Callable = Callable()) -> void:
	resolve_task_reward_data(user_id, task_id, func(ok: bool, reward_data: Variant):
		if not ok or not reward_data is Dictionary:
			if _callback_target_is_alive(callback):
				callback.call(false, {})
			return
		var reward: Dictionary = reward_data as Dictionary
		var coins: int = max(0, int(reward.get("coins", reward.get("reward_coins", 0))))
		var experience: int = max(0, int(reward.get("exp", reward.get("xp", reward.get("experience", 0)))))
		if coins <= 0 and experience <= 0:
			if _callback_target_is_alive(callback):
				callback.call(true, reward)
			return
		if coins > 0 and has_method("add_coins"):
			call("add_coins", user_id, coins, func(_coin_ok: bool, _coin_balance: Variant):
				if experience > 0 and has_method("add_experience"):
					call("add_experience", user_id, experience, func(_exp_ok: bool, _exp_value: Variant):
						if _callback_target_is_alive(callback):
							callback.call(_coin_ok and _exp_ok, reward)
					)
				else:
					if _callback_target_is_alive(callback):
						callback.call(_coin_ok, reward)
			)
			return
		if experience > 0 and has_method("add_experience"):
			call("add_experience", user_id, experience, func(_exp_ok: bool, _exp_value: Variant):
				if _callback_target_is_alive(callback):
					callback.call(_exp_ok, reward)
			)
			return
		if _callback_target_is_alive(callback):
			callback.call(true, reward)
	)

func mark_task_complete_for_user(user_id: String, task_id: String, callback: Callable = Callable()) -> void:
	_resolve_db()
	var safe_user_key: String = _storage_user_key(user_id)
	if safe_user_key.strip_edges().is_empty() or task_id.strip_edges().is_empty():
		if _callback_target_is_alive(callback):
			callback.call(false, "Missing user id or task id")
		return
	if _db == null or not _db.has_method("update_json"):
		if _callback_target_is_alive(callback):
			callback.call(false, "FirebaseRTDB unavailable")
		return
	var update_payload: Dictionary = {
		"completed": true,
		"completion_date": Time.get_datetime_string_from_system(false, true)
	}
	_db.update_json(USERS_PATH + "/" + safe_user_key + "/tasks/" + task_id, update_payload, func(result: int, response_code: int, body: Variant):
		var ok: bool = result == OK and response_code >= 200 and response_code < 300
		if _callback_target_is_alive(callback):
			callback.call(ok, body if not ok else update_payload)
	)

func save_task_proof(user_id: String, task_id: String, proof_payload: Dictionary, callback: Callable = Callable()) -> void:
	_resolve_db()
	_load_local_store()
	var safe_user_key: String = _storage_user_key(user_id)
	if safe_user_key.strip_edges().is_empty():
		if callback.is_valid():
			callback.call(false, "Missing user id for task proof save")
		return

	var payload: Dictionary = proof_payload.duplicate(true)
	payload["task_id"] = task_id
	payload["saved_at"] = Time.get_datetime_string_from_system(false, true)
	if not payload.has("scene"):
		payload["scene"] = "tasks"
	_save_scene_input(safe_user_key, "tasks", payload, callback)

func save_scene_input(user_id: String, scene_name: String, payload: Dictionary, callback: Callable = Callable()) -> void:
	_resolve_db()
	_load_local_store()
	var safe_user_key: String = _storage_user_key(user_id)
	var safe_scene_name: String = str(scene_name).strip_edges()
	if safe_user_key.strip_edges().is_empty() or safe_scene_name.is_empty():
		if callback.is_valid():
			callback.call(false, "Missing user id or scene name for form save")
		return
	var entry_payload: Dictionary = payload.duplicate(true)
	entry_payload["saved_at"] = Time.get_datetime_string_from_system(false, true)
	entry_payload["scene"] = scene_name
	_save_scene_input(safe_user_key, safe_scene_name, entry_payload, callback)

func _save_scene_input(user_key: String, scene_name: String, payload: Dictionary, callback: Callable = Callable()) -> void:
	var timestamp: String = str(Time.get_unix_time_from_system()).replace(".", "_")
	var safe_entry_key: String = "entry_" + timestamp
	_write_local_document(scene_name, user_key, safe_entry_key, payload)
	var firebase_path: String = USERS_PATH + "/" + user_key + "/" + scene_name
	print("FirebaseAuthManager: saving scene input to ", firebase_path, "/", safe_entry_key)
	if _db != null and _db.has_method("update_json"):
		var update_payload: Dictionary = {}
		update_payload[safe_entry_key] = payload
		_db.update_json(firebase_path, update_payload, func(result: int, response_code: int, body: Variant):
			var ok: bool = result == OK and response_code >= 200 and response_code < 300
			if callback.is_valid():
				callback.call(ok, body if not ok else payload)
		)
	elif _db != null and _db.has_method("write_json"):
		_db.write_json(firebase_path + "/" + safe_entry_key, payload, func(result: int, response_code: int, body: Variant):
			var ok: bool = result == OK and response_code >= 200 and response_code < 300
			if callback.is_valid():
				callback.call(ok, body if not ok else payload)
		)
	else:
		push_warning("FirebaseAuthManager: FirebaseRTDB unavailable; saved only to local storage at ", STORE_PATH)
		if callback.is_valid():
			callback.call(true, payload)

func _node_string_property(node: Node, property_name: String) -> String:
	if node == null:
		return ""
	var value: Variant = node.get(property_name)
	if value == null:
		return ""
	return str(value).strip_edges()

func _storage_user_key(user_id: String) -> String:
	return _resolve_profile_user_key(user_id)

func _resolve_profile_user_key(user_id: String) -> String:
	var candidate_keys: Array = []
	var seen: Dictionary = {}
	var add_candidate: Callable = func(value: Variant) -> void:
		if value == null:
			return
		var cleaned: String = str(value).strip_edges()
		if cleaned.is_empty():
			return
		var normalized: String = _safe_key(cleaned)
		if normalized.is_empty() or seen.has(normalized):
			return
		seen[normalized] = true
		candidate_keys.append(normalized)

	var raw_user_id: String = str(user_id).strip_edges()
	var session: Node = get_tree().root.get_node_or_null("UserSession") if get_tree() != null and get_tree().root != null else null
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")

	var local_users: Variant = _store_cache.get("users", {})
	if local_users is Dictionary and not local_users.is_empty():
		for user_key in local_users.keys():
			var user_entry: Variant = local_users.get(user_key)
			if not user_entry is Dictionary:
				continue
			var profile: Variant = user_entry.get(PROFILE_NODE, {})
			if not profile is Dictionary:
				continue
			var stored_email: String = str(profile.get("email", "")).strip_edges()
			var stored_uid: String = str(profile.get("uid", profile.get("firebase_uid", ""))).strip_edges()
			if stored_email.is_empty() and stored_uid.is_empty():
				continue

			var match_candidate: String = ""
			if session != null:
				if session.has_method("get_current_user_email"):
					match_candidate = str(session.call("get_current_user_email")).strip_edges()
				if match_candidate.is_empty() and session.has_method("get_current_user_id"):
					match_candidate = str(session.call("get_current_user_id")).strip_edges()
			if match_candidate.is_empty() and raw_user_id != "":
				match_candidate = raw_user_id

			if not match_candidate.is_empty():
				if _safe_key(stored_email) == _safe_key(match_candidate) or _safe_key(stored_uid) == _safe_key(match_candidate) or _safe_key(str(user_key)) == _safe_key(match_candidate):
					return str(user_key).strip_edges()

	# Prefer the signed-in email key before the raw UID, because Firebase user records are stored by email key.
	if session != null:
		if session.has_method("get_current_user_email"):
			var email: String = str(session.call("get_current_user_email")).strip_edges()
			if not email.is_empty() and email != "guest_user":
				return _safe_key(email)
		if session.has_method("get_current_user_id"):
			var current_id: String = str(session.call("get_current_user_id")).strip_edges()
			if not current_id.is_empty() and current_id != "guest_user":
				return _safe_key(current_id)

	var auth: Node = null
	if Engine.has_singleton("FirebaseAuthManager"):
		auth = Engine.get_singleton("FirebaseAuthManager")
	if auth != null:
		if auth.has_method("get_current_user_email"):
			var auth_email: String = str(auth.call("get_current_user_email")).strip_edges()
			if not auth_email.is_empty() and auth_email != "guest_user":
				return _safe_key(auth_email)
		if auth.has_method("get_current_user_id"):
			var auth_id: String = str(auth.call("get_current_user_id")).strip_edges()
			if not auth_id.is_empty() and auth_id != "guest_user":
				return _safe_key(auth_id)

	if raw_user_id != "" and raw_user_id != "guest_user":
		add_candidate.call(raw_user_id)
		add_candidate.call(raw_user_id.to_lower())
		for candidate in candidate_keys:
			if candidate != "" and candidate != "guest_user":
				return candidate
	
	return "guest_user"

func _pick_best_user_key_for_user(root_body: Dictionary, user_id: String, fallback_key: String) -> String:
	if not root_body is Dictionary or root_body.is_empty():
		return fallback_key
	var candidates: Array = []
	var seen: Dictionary = {}
	var add_candidate: Callable = func(value: String) -> void:
		var normalized: String = str(value).strip_edges()
		if normalized.is_empty() or seen.has(normalized):
			return
		seen[normalized] = true
		candidates.append(normalized)
	if user_id != "":
		add_candidate.call(user_id)
		add_candidate.call(_safe_key(user_id))
	var session: Node = get_tree().root.get_node_or_null("UserSession") if get_tree() != null and get_tree().root != null else null
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	if session != null:
		if session.has_method("get_current_user_email"):
			add_candidate.call(str(session.call("get_current_user_email")).strip_edges())
		if session.has_method("get_current_user_id"):
			add_candidate.call(str(session.call("get_current_user_id")).strip_edges())
		var session_email: String = _node_string_property(session, "current_user_email")
		if session_email != "":
			add_candidate.call(session_email)
		var session_id: String = _node_string_property(session, "current_user_id")
		if session_id != "":
			add_candidate.call(session_id)
	var best_key: String = fallback_key
	var best_score: int = -1
	for user_key in root_body.keys():
		var user_data: Variant = root_body.get(user_key)
		if not (user_data is Dictionary):
			continue
		var score: int = 0
		var user_email: String = ""
		var profile: Variant = user_data.get(PROFILE_NODE, {})
		if profile is Dictionary:
			user_email = str(profile.get("email", "")).strip_edges()
		var normalized_user_key: String = str(user_key).strip_edges()
		if normalized_user_key == fallback_key:
			score += 10
		if candidates.size() > 0:
			for candidate in candidates:
				var normalized_candidate: String = str(candidate).strip_edges()
				if normalized_candidate.is_empty():
					continue
				if normalized_user_key == _safe_key(normalized_candidate):
					score += 25
				if user_email != "" and _safe_key(user_email) == _safe_key(normalized_candidate):
					score += 30
				if normalized_user_key == normalized_candidate:
					score += 20
		if score > best_score:
			best_key = normalized_user_key
			best_score = score
	if best_key.is_empty():
		best_key = fallback_key
	return best_key

func _safe_key(value: String) -> String:
	var safe: String = value.strip_edges().to_lower()
	var original: String = value.strip_edges()
	if not original.is_empty() and not original.contains("@") and not original.contains(".") and not original.contains(" ") and original.length() >= 20:
		return original
	safe = safe.replace("@", "_")
	safe = safe.replace(".", "_")
	safe = safe.replace(" ", "_")
	return safe

func _build_error_message(response_code: int, body: Variant) -> String:
	if body is Dictionary:
		if body.has("error"):
			return str(body.get("error"))
		if body.has("message"):
			return str(body.get("message"))
	if body is String and not body.strip_edges().is_empty():
		return body
	# If the HTTP response was successful (2xx) but no meaningful body was returned,
	# report a clearer message to distinguish an empty result from a transport error.
	if response_code >= 200 and response_code < 300:
		return "No matching user data was found in Firebase."
	if response_code > 0:
		return "Request failed with HTTP %d" % response_code
	return "Request failed while contacting Firebase."

func _is_permission_denied_error(body: Variant) -> bool:
	if body is Dictionary:
		for key in ["error", "message", "details"]:
			if body.has(key):
				var value: String = str(body.get(key, "")).strip_edges().to_lower()
				if value.contains("permission denied") or value.contains("access denied"):
					return true
	if body is String:
		var text: String = body.strip_edges().to_lower()
		return text.contains("permission denied") or text.contains("access denied")
	return false

func _load_local_user(user_key: String) -> Dictionary:
	_load_local_store()
	var users: Variant = _store_cache.get("users", {})
	if users is Dictionary and users.has(user_key):
		var entry: Variant = users.get(user_key)
		if entry is Dictionary:
			if entry.has(PROFILE_NODE) and entry.get(PROFILE_NODE) is Dictionary:
				return entry.get(PROFILE_NODE)
			if entry.has("password"):
				return entry
	return {}

func _load_local_store() -> void:
	if _store_loaded:
		return
	var file: FileAccess = FileAccess.open(STORE_PATH, FileAccess.READ)
	if file == null:
		_store_cache = {}
		_store_loaded = true
		return
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		_store_cache = {}
	else:
		var parsed: Variant = JSON.parse_string(text)
		_store_cache = parsed if parsed is Dictionary else {}
	_store_loaded = true

func _save_local_store() -> void:
	var file: FileAccess = FileAccess.open(STORE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_store_cache))
	file.close()

func _write_local_user(user_key: String, payload: Dictionary) -> void:
	_load_local_store()
	var users: Dictionary = _store_cache.get("users", {})
	if not users is Dictionary:
		users = {}
	users[user_key] = payload
	_store_cache["users"] = users
	_save_local_store()

func _write_local_document(collection_name: String, user_key: String, doc_key: String, payload: Dictionary) -> void:
	_load_local_store()
	var users: Dictionary = _store_cache.get("users", {})
	if not users is Dictionary:
		users = {}
	var user_entry: Dictionary = users.get(user_key, {})
	if not user_entry is Dictionary:
		user_entry = {}
	var collection: Dictionary = user_entry.get(collection_name, {})
	if not collection is Dictionary:
		collection = {}
	collection[doc_key] = payload
	user_entry[collection_name] = collection
	users[user_key] = user_entry
	_store_cache["users"] = users
	_save_local_store()
