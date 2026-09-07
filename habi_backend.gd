extends Node

# Simple HTTP wrapper for habi-backend API calls
# Usage: add this file as an Autoload singleton named `HabiBackend` (Project Settings -> AutoLoad)

@export var base_url: String = "http://127.0.0.1:5000"

func get_backend_url() -> String:
	var configured: String = base_url.strip_edges().rstrip("/")
	if configured.is_empty():
		configured = "http://127.0.0.1:5000"
	var root := get_tree().root if get_tree() != null and get_tree().root != null else null
	if root != null and root.has_meta("habi_backend_url"):
		configured = str(root.get_meta("habi_backend_url")).strip_edges().rstrip("/")
	if configured.is_empty():
		configured = "http://127.0.0.1:5000"
	if OS.has_environment("HABI_BACKEND_URL"):
		configured = str(OS.get_environment("HABI_BACKEND_URL")).strip_edges().rstrip("/")
	if configured.is_empty():
		configured = "http://127.0.0.1:5000"
	return configured

func _ready():
	pass

func _resolve_user_session() -> Variant:
	if get_tree() != null and get_tree().root != null:
		var session = get_tree().root.get_node_or_null("UserSession")
		if session != null:
			return session
	if Engine.has_singleton("UserSession"):
		return Engine.get_singleton("UserSession")
	return null

func _resolve_auth_manager() -> Variant:
	if get_tree() != null and get_tree().root != null:
		var auth = get_tree().root.get_node_or_null("FirebaseAuthManager")
		if auth != null:
			return auth
	if Engine.has_singleton("FirebaseAuthManager"):
		return Engine.get_singleton("FirebaseAuthManager")
	return null

func _extract_token_from_session(session: Variant) -> String:
	if session == null:
		return ""
	if session.has_method("get_current_user_token"):
		return str(session.call("get_current_user_token")).strip_edges()
	if session.has_method("get_id_token"):
		return str(session.call("get_id_token")).strip_edges()
	if session.has_method("get_token"):
		return str(session.call("get_token")).strip_edges()
	if session.has_method("get_auth_token"):
		return str(session.call("get_auth_token")).strip_edges()
	return ""

func _extract_user_id_from_session(session: Variant) -> String:
	if session == null:
		return ""
	if session.has_method("get_current_user_token"):
		var token: String = str(session.call("get_current_user_token")).strip_edges()
		var token_uid: String = _extract_uid_from_token(token)
		if token_uid != "":
			return _sanitize_uid(token_uid)
	if session.has_method("get_current_user_id"):
		return _sanitize_uid(str(session.call("get_current_user_id")).strip_edges())
	return ""

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

func _sanitize_uid(value: String) -> String:
	var safe: String = value.strip_edges()
	if safe.is_empty():
		return ""
	safe = safe.to_lower()
	var forbidden: Array = ["@", ".", "#", "$", "[", "]"]
	for ch in forbidden:
		safe = safe.replace(ch, "_")
	safe = safe.replace(" ", "_")
	return safe

func _augment_headers_with_auth(headers: Dictionary) -> Dictionary:
	var result: Dictionary = headers.duplicate()
	if result.has("Authorization") or result.has("authorization"):
		return result

	var session = _resolve_user_session()
	var auth = _resolve_auth_manager()

	var token: String = _extract_token_from_session(session)
	if token != "":
		if token.begins_with("local:"):
			var local_uid: String = _sanitize_uid(token.substr("local:".length()))
			token = "local:" + local_uid
		if token.begins_with("Bearer "):
			result["Authorization"] = token
		else:
			result["Authorization"] = "Bearer %s" % token

	if not result.has("Authorization"):
		if auth != null:
			for method_name in ["get_id_token", "get_token", "get_auth_token"]:
				if auth.has_method(method_name):
					var ftoken: String = str(auth.call(method_name)).strip_edges()
					if ftoken != "":
						if ftoken.begins_with("Bearer "):
							result["Authorization"] = ftoken
						else:
							result["Authorization"] = "Bearer %s" % ftoken
						break

	if not result.has("Authorization"):
		var local_uid: String = _extract_user_id_from_session(session)
		if local_uid.is_empty() and auth != null:
			if auth.has_method("get_current_user_id"):
				local_uid = str(auth.call("get_current_user_id")).strip_edges()
		if local_uid != "":
			result["Authorization"] = "Bearer local:%s" % local_uid

	if result.has("Authorization"):
		var auth_debug: String = str(result["Authorization"])
		if auth_debug.begins_with("Bearer "):
			auth_debug = auth_debug.substr("Bearer ".length())
		print("habi_backend: request auth header present; identity prefix=%s" % auth_debug.substr(0, min(auth_debug.length(), 24)))
	else:
		print("habi_backend: no auth token available for request to %s" % str(base_url))

	return result

func _make_request(method: String, path: String, json_body: Variant = null, headers: Dictionary = {}, callback: Callable = Callable()):
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	var url: String = base_url.rstrip("/") + path
	var auth_headers: Dictionary = _augment_headers_with_auth(headers)
	var hdrs: Array = ["Content-Type: application/json"]
	for k in auth_headers.keys():
		hdrs.append("%s: %s" % [k, str(auth_headers[k])])
	var cb = callback if callback is Callable else Callable()
	req.connect("request_completed", Callable(self, "_on_request_completed").bind(cb, req))
	var body_text: String = ""
	if json_body != null:
		body_text = JSON.stringify(json_body)
	# Map string method to HTTPClient constant
	var method_const: int = HTTPClient.METHOD_GET
	match method.to_upper():
		"POST": method_const = HTTPClient.METHOD_POST
		"PUT": method_const = HTTPClient.METHOD_PUT
		"PATCH": method_const = HTTPClient.METHOD_PATCH
		"DELETE": method_const = HTTPClient.METHOD_DELETE
		"HEAD": method_const = HTTPClient.METHOD_HEAD
		"OPTIONS": method_const = HTTPClient.METHOD_OPTIONS
		_: method_const = HTTPClient.METHOD_GET

	# request signature: request(url, headers=Array(), method=HTTPClient.METHOD_GET, request_data="")
	var err = req.request(url, hdrs, method_const, body_text)
	if err != OK:
		if cb.is_valid():
			cb.call(false, {"error":"request_failed","code":err})
		req.queue_free()

func _on_request_completed(result: int, response_code: int, response_headers: Array, body: PackedByteArray, callback: Callable, req: HTTPRequest) -> void:
	var text: String = ""
	if body != null:
		text = body.get_string_from_utf8()
	var ok: bool = result == OK and response_code >= 200 and response_code < 300
	
	print("habi_backend: _on_request_completed - result=%d, response_code=%d, ok=%s" % [result, response_code, ok])
	print("habi_backend: response text (first 500 chars): %s" % text.substr(0, 500))
	
	if ok:
		# Try parse JSON response first
		var parsed = null
		var content_type = ""
		for h in response_headers:
			if typeof(h) == TYPE_STRING and h.findn("content-type") != -1:
				content_type = h
				print("habi_backend: found content-type header: %s" % content_type)
		
		if content_type.findn("application/json") != -1:
			print("habi_backend: JSON content-type detected, attempting parse")
			var parsed_try = JSON.parse_string(text)
			print("habi_backend: JSON parse result type: %s" % typeof(parsed_try))
			if parsed_try is Dictionary or parsed_try is Array:
				parsed = parsed_try
				print("habi_backend: Successfully parsed as %s with %d items" % ["Array" if parsed_try is Array else "Dictionary", parsed_try.size() if parsed_try is Array else parsed_try.size()])
			else:
				print("habi_backend: JSON parse failed or returned unexpected type: %s" % str(parsed_try))
		else:
			print("habi_backend: No JSON content-type found, content_type=%s" % content_type)
		
		if parsed != null:
			print("habi_backend: Calling callback with success=true, parsed data")
			if callback.is_valid():
				callback.call(true, parsed)
		else:
			print("habi_backend: Parsed was null, returning raw response")
			# return raw bytes for binary responses (audio) or text
			if callback.is_valid():
				callback.call(true, {"text":text, "bytes": body, "content_type": content_type})
	else:
		print("habi_backend: HTTP error - calling callback with success=false")
		if callback.is_valid():
			callback.call(false, {"code": response_code, "body": text})
	if req != null:
		req.queue_free()

# Public API
func get_livekit_token(room_name: String = "", identity: String = "", display_name: String = "", callback: Callable = Callable()):
	_make_request("POST", "/api/livekit/token", {"roomName": room_name, "identity": identity, "name": display_name}, {}, callback)

func dispatch_livekit(room_name: String = "", identity: String = "", agent_name: String = "habi-friend", callback: Callable = Callable()):
	_make_request("POST", "/api/livekit/dispatch", {"roomName": room_name, "identity": identity, "agentName": agent_name}, {}, callback)

func get_pipecat_session(callback: Callable = Callable()):
	_make_request("POST", "/api/pipecat/session", {}, {}, callback)

func companion_chat(message: String, companion_name: String = "Habi Friend", callback: Callable = Callable()):
	_make_request("POST", "/api/companion/chat", {"message": message, "companionName": companion_name}, {}, callback)

func companion_tts(text: String, voice_id: String = "", callback: Callable = Callable()):
	# Returns { text: <string>, bytes: <PackedByteArray> } on success
	_make_request("POST", "/api/companion/tts", {"text": text, "voiceId": voice_id}, {}, callback)

func companion_stt(audio_base64: String, content_type: String = "audio/wav", callback: Callable = Callable()):
	_make_request("POST", "/api/companion/stt", {"audioBase64": audio_base64, "contentType": content_type}, {}, callback)

func companion_voice(audio_base64: String, content_type: String = "audio/wav", voice_id: String = "", companion_name: String = "Habi Friend", callback: Callable = Callable()):
	_make_request("POST", "/api/companion/voice", {"audioBase64": audio_base64, "contentType": content_type, "voiceId": voice_id, "companionName": companion_name}, {}, callback)

func health_check(callback: Callable = Callable()):
	_make_request("GET", "/health", {}, {}, callback)

func _resolve_effective_uid(preferred_uid: String = "") -> String:
	var session = _resolve_user_session()
	var auth = _resolve_auth_manager()
	var candidates: Array = []

	if session != null:
		if session.has_method("get_current_user_token"):
			candidates.append(str(session.call("get_current_user_token")).strip_edges())
		if session.has_method("get_current_user_id"):
			candidates.append(str(session.call("get_current_user_id")).strip_edges())
		if session.has_method("get_current_user_email"):
			candidates.append(str(session.call("get_current_user_email")).strip_edges())

	if auth != null:
		if auth.has_method("get_current_user_token"):
			candidates.append(str(auth.call("get_current_user_token")).strip_edges())
		if auth.has_method("get_current_user_id"):
			candidates.append(str(auth.call("get_current_user_id")).strip_edges())
		if auth.has_method("get_current_user"):
			var user = auth.call("get_current_user")
			if user is Dictionary:
				if user.has("uid"):
					candidates.append(str(user.get("uid")).strip_edges())
				if user.has("email"):
					candidates.append(str(user.get("email")).strip_edges())

	if preferred_uid != "":
		candidates.append(preferred_uid.strip_edges())

	for candidate in candidates:
		var trimmed: String = str(candidate).strip_edges()
		if trimmed.is_empty() or trimmed == "guest_user":
			continue
		if trimmed.begins_with("Bearer "):
			trimmed = trimmed.substr("Bearer ".length()).strip_edges()
		if trimmed.begins_with("local:"):
			var local_uid: String = trimmed.substr("local:".length()).strip_edges()
			if not local_uid.is_empty() and local_uid != "guest_user":
				return local_uid
		var token_uid: String = _extract_uid_from_token(trimmed)
		if token_uid != "":
			return token_uid
		if trimmed.find("@") != -1 or trimmed.find(".") != -1:
			if trimmed == preferred_uid.strip_edges() and not trimmed.to_lower().contains("guest"):
				return trimmed
			continue
		if trimmed != "guest_user":
			return trimmed

	return preferred_uid.strip_edges() if preferred_uid.strip_edges() != "" and preferred_uid.strip_edges() != "guest_user" else ""

func get_daily_tasks(uid: String, callback: Callable = Callable()):
	# Fetch habits from the backend and map them to task objects for the home goal generator.
	var effective_uid: String = _resolve_effective_uid(uid)
	var safe_uid: String = _sanitize_uid(effective_uid)
	print("habi_backend: get_daily_tasks resolved uid=%s from preferred=%s" % [effective_uid, uid])
	var processor = Callable(self, "_on_get_daily_tasks_response").bind(callback)
	_make_request("GET", "/api/habits/%s" % safe_uid, null, {}, processor)

func refresh_task_pool(uid: String, callback: Callable = Callable()):
	# No separate task refresh endpoint currently exists; re-fetch the daily tasks.
	get_daily_tasks(uid, callback)

func mark_task_complete(uid: String, habit_id: String, proof_payload: Dictionary = {}, callback: Callable = Callable()):
	var request_body: Dictionary = {}
	if proof_payload != null and proof_payload.size() > 0:
		request_body = proof_payload.duplicate(true)
	var effective_uid: String = _resolve_effective_uid(uid)
	var safe_uid: String = _sanitize_uid(effective_uid)
	print("habi_backend: mark_task_complete resolved uid=%s from preferred=%s" % [effective_uid, uid])
	_make_request("POST", "/api/habits/%s/%s/complete" % [safe_uid, habit_id], request_body, {}, callback)

func _on_get_daily_tasks_response(success: bool, data: Variant, callback: Callable) -> void:
	if not success:
		print("habi_backend: _on_get_daily_tasks_response failed: ", str(data))
		if callback.is_valid():
			callback.call(false, data)
		return

	print("habi_backend: _on_get_daily_tasks_response received raw data type: %s" % typeof(data))
	print("habi_backend: _on_get_daily_tasks_response raw data: %s" % str(data))
	
	var task_data: Dictionary = {}
	if data is Array:
		print("habi_backend: Received Array response with %d items" % data.size())
		var tasks: Array = []
		for item in data:
			if item is Dictionary:
				var task_name = item.get("name", "")
				if task_name.is_empty():
					task_name = item.get("title", "Unnamed task")
				tasks.append({
					"id": str(item.get("id", "")),
					"title": str(task_name),
					"coins": int(item.get("coins", item.get("reward_coins", 0))),
					"exp": int(item.get("exp", item.get("xp", item.get("experience", 0)))),
					"is_automated": true
				})
				print("habi_backend: Added task: id=%s, title=%s" % [item.get("id", ""), task_name])
		task_data["tasks"] = tasks
		print("habi_backend: Processed Array into %d tasks" % tasks.size())
	elif data is Dictionary and data.has("tasks"):
		print("habi_backend: Received Dictionary with tasks key, size=%d" % data["tasks"].size())
		task_data = data
	else:
		print("habi_backend: Unrecognized response format, defaulting to empty tasks")
		task_data["tasks"] = []

	if callback.is_valid():
		callback.call(true, task_data)

func get_base_url() -> String:
	return base_url.rstrip("/")
