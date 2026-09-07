extends Control

var _auth_manager: Node
var _session: Node

func _ready() -> void:
	_auth_manager = _resolve_auth_manager()
	_session = _resolve_session()
	_configure_password_field()
	var login_button: Button = _find_button_by_text("Log In")
	_set_status("", true)
	if login_button != null:
		login_button.pressed.connect(_on_login_button_pressed)
	else:
		push_warning("Log In button not found in login scene.")

	var signup_link: LinkButton = _find_link_button_by_text("Sign Up")
	if signup_link != null:
		signup_link.pressed.connect(_on_signup_pressed)
	else:
		push_warning("Sign Up link button not found in login scene.")

	var forgot_link: LinkButton = _find_link_button_by_text("Forgot Password?")
	if forgot_link != null:
		forgot_link.pressed.connect(_on_forgot_password_pressed)
	else:
		push_warning("Forgot Password link button not found in login scene.")

func _configure_password_field() -> void:
	var password_edit: LineEdit = _find_line_edit_by_placeholder("🔒 Password")
	if password_edit == null:
		password_edit = get_node_or_null("InputContainer/VBoxContainer/LineEdit2") as LineEdit
	if password_edit != null:
		password_edit.secret = true
		_add_eye_toggle(password_edit, "Password")

func _add_eye_toggle(line_edit: LineEdit, field_name: String) -> void:
	if line_edit == null:
		return
	var toggle_name: String = "EyeToggle_%s" % field_name
	if line_edit.get_node_or_null(toggle_name) != null:
		return
	var toggle := Button.new()
	toggle.name = toggle_name
	toggle.text = "👁"
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toggle.custom_minimum_size = Vector2(24, 24)
	toggle.position = Vector2(line_edit.size.x - 34, 4)
	toggle.size = Vector2(24, 24)
	toggle.pressed.connect(func() -> void:
		line_edit.secret = not line_edit.secret
		toggle.text = "🙈" if line_edit.secret else "👁"
	)
	line_edit.add_child(toggle)
	line_edit.secret = true
	toggle.text = "🙈"

func _find_button_by_text(target_text: String) -> Button:
	for child in get_children():
		var button := child as Button
		if button != null and button.text == target_text:
			return button

		var nested_button: Button = _find_button_in_branch(child, target_text)
		if nested_button != null:
			return nested_button

	return null

func _find_button_in_branch(node: Node, target_text: String) -> Button:
	for child in node.get_children():
		var button := child as Button
		if button != null and button.text == target_text:
			return button

		var nested_button: Button = _find_button_in_branch(child, target_text)
		if nested_button != null:
			return nested_button

	return null

func _find_link_button_by_text(target_text: String) -> LinkButton:
	for child in get_children():
		var link_button := child as LinkButton
		if link_button != null and link_button.text == target_text:
			return link_button

		var nested_link: LinkButton = _find_link_button_in_branch(child, target_text)
		if nested_link != null:
			return nested_link

	return null

func _find_link_button_in_branch(node: Node, target_text: String) -> LinkButton:
	for child in node.get_children():
		var link_button := child as LinkButton
		if link_button != null and link_button.text == target_text:
			return link_button

		var nested_link: LinkButton = _find_link_button_in_branch(child, target_text)
		if nested_link != null:
			return nested_link

	return null

var _login_in_progress: bool = false

func _on_login_button_pressed() -> void:
	if _login_in_progress:
		return
	var email_edit: LineEdit = _find_line_edit_by_placeholder("✉ Email / Student ID")
	var password_edit: LineEdit = _find_line_edit_by_placeholder("🔒 Password")
	if email_edit == null:
		email_edit = get_node_or_null("InputContainer/VBoxContainer/LineEdit") as LineEdit
	if password_edit == null:
		password_edit = get_node_or_null("InputContainer/VBoxContainer/LineEdit2") as LineEdit
	var email: String = (email_edit.text if email_edit != null else "").strip_edges()
	var password: String = (password_edit.text if password_edit != null else "").strip_edges()
	var missing_fields: Array[String] = []
	if email.is_empty():
		missing_fields.append("Email / Student ID")
	if password.is_empty():
		missing_fields.append("Password")
	if not missing_fields.is_empty():
		_show_missing_fields(missing_fields)
		return

	if _auth_manager == null:
		_set_status("Firebase is unavailable right now.", false)
		push_warning("FirebaseAuthManager is not available")
		return

	_login_in_progress = true
	_set_status("Logging in...", false)
	_auth_manager.sign_in(email, password, func(ok, body):
		_login_in_progress = false
		if ok:
			var display_name: String = email
			var auth_token: String = ""
			var session_user_id: String = ""
			if body is Dictionary:
				if body.has("name"):
					display_name = str(body.get("name"))
				for key in ["uid", "user_id", "localId", "firebase_uid", "auth_uid"]:
					if body.has(key):
						var candidate: String = str(body.get(key)).strip_edges()
						if candidate != "":
							session_user_id = candidate
							break
				if body.has("auth_token"):
					auth_token = str(body.get("auth_token"))
				elif body.has("idToken"):
					auth_token = str(body.get("idToken"))
				elif body.has("token"):
					auth_token = str(body.get("token"))
				elif body.has("jwt"):
					auth_token = str(body.get("jwt"))
			if session_user_id.is_empty():
				session_user_id = email
			if auth_token.strip_edges() == "" and _session != null:
				var local_uid: String = session_user_id
				if local_uid.strip_edges().is_empty():
					if _session.has_method("get_current_user_id"):
						local_uid = str(_session.call("get_current_user_id")).strip_edges()
				if local_uid.strip_edges().is_empty() or local_uid == "guest_user":
					local_uid = email
				if local_uid != "" and local_uid != "guest_user":
					auth_token = "local:%s" % local_uid
			if _session != null:
				_session.set_user(email, display_name, session_user_id, auth_token)
				var _dbg_token: String = ""
				if _session.has_method("get_current_user_token"):
					_dbg_token = str(_session.call("get_current_user_token"))
				var token_preview: String = "(empty)"
				if _dbg_token.length() > 16:
					token_preview = _dbg_token.substr(0, 16) + "..."
				elif _dbg_token.length() > 0:
					token_preview = _dbg_token
				print("login_navigation: stored session token prefix -> %s" % token_preview)
				if _session.has_method("get_current_user_id"):
					print("login_navigation: stored session uid -> %s" % _session.call("get_current_user_id"))
				
				# Load user profile after successful login to get gender and other attributes
				_load_user_profile_after_login(session_user_id)
				
			_set_status("Login successful.", true)
			print("Login submitted to Firebase")
			_change_scene_to_file("res://home.tscn")
			var livekit_identity: String = email
			var livekit_display_name: String = display_name
			if _session != null:
				if _session.has_method("get_current_user_id"):
					livekit_identity = str(_session.call("get_current_user_id"))
				if _session.has_method("get_current_user_name"):
					livekit_display_name = str(_session.call("get_current_user_name"))
			_start_livekit_after_login(livekit_identity, livekit_display_name)
		else:
			_set_status("Login failed: %s" % str(body), false)
			push_warning("Login request failed: %s" % str(body))
	)

func _find_line_edit_by_placeholder(target_placeholder: String) -> LineEdit:
	var normalized_target: String = target_placeholder.strip_edges()
	for child in get_children():
		var line_edit := child as LineEdit
		if line_edit != null and line_edit.placeholder_text.strip_edges() == normalized_target:
			return line_edit
		var nested_line_edit: LineEdit = _find_line_edit_in_branch(child, normalized_target)
		if nested_line_edit != null:
			return nested_line_edit
	return null

func _find_line_edit_in_branch(node: Node, target_placeholder: String) -> LineEdit:
	var normalized_target: String = target_placeholder.strip_edges()
	for child in node.get_children():
		var line_edit := child as LineEdit
		if line_edit != null and line_edit.placeholder_text.strip_edges() == normalized_target:
			return line_edit
		var nested_line_edit: LineEdit = _find_line_edit_in_branch(child, normalized_target)
		if nested_line_edit != null:
			return nested_line_edit
	return null

func _on_signup_pressed() -> void:
	_change_scene_to_file("res://signup.tscn")

func _resolve_auth_manager() -> Node:
	var root: Node = get_tree().root
	if root != null:
		var manager: Node = root.get_node_or_null("FirebaseAuthManager")
		if manager != null:
			return manager
	if Engine.has_singleton("FirebaseAuthManager"):
		return Engine.get_singleton("FirebaseAuthManager")
	return null

func _find_node_by_name(root: Node, target_name: String) -> Node:
	for child in root.get_children():
		if child == null:
			continue
		if child.name == target_name:
			return child
		var nested: Node = _find_node_by_name(child, target_name)
		if nested != null:
			return nested
	return null

func _start_livekit_after_login(_identity: String, _display_name: String) -> void:
	pass

func _set_status(message: String, success: bool) -> void:
	var label: Label = get_node_or_null("AlertLabel") as Label
	if label == null:
		label = get_node_or_null("StatusLabel") as Label
	if label == null:
		label = get_node_or_null("Label/StatusLabel") as Label
	if label == null:
		return
	label.text = message
	label.modulate = Color(0.0, 0.6, 0.0, 1.0) if success else Color(0.8, 0.0, 0.0, 1.0)
	label.visible = true

func _resolve_session() -> Node:
	var root: Node = get_tree().root
	if root != null:
		var session: Node = root.get_node_or_null("UserSession")
		if session != null:
			return session
	if Engine.has_singleton("UserSession"):
		return Engine.get_singleton("UserSession")
	return null

func _change_scene_to_file(target_scene: String) -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	if not is_inside_tree():
		return
	var scene_resource: Variant = load(target_scene)
	if not (scene_resource is PackedScene):
		push_warning("Scene resource could not be loaded: %s" % target_scene)
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if tree.has_method("change_scene_to_packed"):
		tree.change_scene_to_packed(scene_resource)
	elif tree.has_method("change_scene_to_file"):
		tree.change_scene_to_file(target_scene)

func _set_alert(message: String, is_error: bool) -> void:
	var label: Label = get_node_or_null("AlertLabel") as Label
	if label == null:
		label = get_node_or_null("StatusLabel") as Label
	if label == null:
		label = get_node_or_null("Label/StatusLabel") as Label
	if label == null:
		return
	label.visible = true
	label.text = message
	label.modulate = Color(0.9, 0.15, 0.15, 1.0) if is_error else Color(0.1, 0.7, 0.2, 1.0)

func _show_missing_fields(missing_fields: Array[String]) -> void:
	if missing_fields.is_empty():
		return
	var list_text: String = ""
	for i in range(missing_fields.size()):
		if i > 0:
			list_text += "\n- "
		else:
			list_text += "- "
		list_text += missing_fields[i]
	var status_text: String = ""
	for i in range(missing_fields.size()):
		if i > 0:
			status_text += ", "
		status_text += missing_fields[i]
	_set_status("Missing: %s" % status_text, false)
	_set_alert("Missing required information:\n%s" % list_text, true)

func _on_forgot_password_pressed() -> void:
	_change_scene_to_file("res://forgotpass.tscn")

func _load_user_profile_after_login(user_id: String) -> void:
	"""Load user profile after successful login to get gender and other attributes"""
	var auth_manager = _resolve_auth_manager()
	if auth_manager == null:
		return
	
	if auth_manager.has_method("load_profile"):
		auth_manager.call("load_profile", user_id, Callable(self, "_on_profile_loaded_after_login"))
	elif auth_manager.has_method("get_profile"):
		var profile = auth_manager.call("get_profile", user_id)
		if profile is Dictionary:
			_on_profile_loaded_after_login(true, profile)

func _on_profile_loaded_after_login(success: bool, profile: Variant) -> void:
	if success and profile is Dictionary:
		print("login_navigation: User profile loaded after login")
		if _session != null and _session.has_method("set_user_profile"):
			_session.call("set_user_profile", profile)
		print("login_navigation: Profile contains gender: ", profile.get("gender", "not set"))
	else:
		print("login_navigation: Failed to load user profile after login")
