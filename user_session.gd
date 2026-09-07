extends Node

var current_user_id: String = "guest_user"
var current_user_name: String = "Guest"
var current_user_email: String = ""
var current_user_token: String = ""
var is_authenticated: bool = false
var last_login_time: String = ""

func set_user(email: String, display_name: String, user_id: String = "", auth_token: String = "") -> void:
	current_user_email = email.strip_edges()
	current_user_name = display_name.strip_edges()
	if current_user_name.is_empty():
		current_user_name = current_user_email

	var raw_user_id: String = _resolve_user_id(user_id, email, auth_token)
	if raw_user_id.is_empty():
		raw_user_id = current_user_email if not current_user_email.is_empty() else "guest_user"
	current_user_id = raw_user_id.strip_edges() if not auth_token.strip_edges().is_empty() else _make_key(raw_user_id)

	if auth_token.strip_edges().is_empty() and raw_user_id != "" and raw_user_id != "guest_user":
		current_user_token = "local:%s" % raw_user_id
	else:
		current_user_token = auth_token.strip_edges()
	is_authenticated = true
	last_login_time = Time.get_datetime_string_from_system(false, true)

func _resolve_user_id(requested_user_id: String, email: String, auth_token: String) -> String:
	if auth_token != "":
		var token_uid: String = _extract_uid_from_auth_token(auth_token)
		if token_uid != "" and token_uid != "guest_user":
			return token_uid
		if auth_token.begins_with("local:"):
			var local_uid: String = auth_token.substr("local:".length()).strip_edges()
			if local_uid != "" and local_uid != "guest_user":
				return local_uid

	var candidate: String = requested_user_id.strip_edges()
	if candidate != "" and candidate != "guest_user":
		return candidate

	if email != "" and email != "guest_user":
		return email
	return ""

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

	var decoded: String = ""
	decoded = Marshalls.base64_to_utf8(payload)
	var parsed: Variant = JSON.parse_string(decoded)
	if parsed is Dictionary:
		for key in ["uid", "user_id", "sub"]:
			if parsed.has(key):
				var uid: String = str(parsed.get(key)).strip_edges()
				if uid != "":
					return uid
	return ""

func clear_user() -> void:
	current_user_id = "guest_user"
	current_user_name = "Guest"
	current_user_email = ""
	current_user_token = ""
	is_authenticated = false
	last_login_time = ""

func get_current_user_id() -> String:
	return current_user_id

func get_current_user_name() -> String:
	return current_user_name

func get_current_user_email() -> String:
	return current_user_email

func get_current_user_token() -> String:
	return current_user_token

func get_id_token() -> String:
	return current_user_token

func get_token() -> String:
	return current_user_token

func get_auth_token() -> String:
	return current_user_token

func _make_key(value: String) -> String:
	var safe: String = value.strip_edges().to_lower()
	safe = safe.replace("@", "_")
	safe = safe.replace(".", "_")
	safe = safe.replace(" ", "_")
	return safe
