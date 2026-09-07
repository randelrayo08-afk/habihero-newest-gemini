extends Control

var _auth_manager: Node
var _session: Node
var _selected_grade: String = ""
var _selected_section: String = ""
var _selected_gender: String = ""
var _signup_in_progress: bool = false
var _grade_sections: Dictionary = {
	"Grade 6": [
		"(1) Jose Rizal",
		"(2) Andres Bonifacio",
		"(3) Gregorio Del Pilar",
		"(4) Apolinario Mabini",
		"(5) Melchora Aquino",
		"(6) Antonio Luna"
	]
}

func _ready() -> void:
	_auth_manager = _resolve_auth_manager()
	_session = _resolve_session()
	var signup_button: Button = _find_button_by_text("Sign Up")
	_set_status("", true)
	if signup_button != null:
		signup_button.pressed.connect(_on_signup_button_pressed)
		# Make signup button green when clicked and keep it green
		signup_button.pressed.connect(func():
			signup_button.modulate = Color(0.2, 0.8, 0.2, 1.0)  # Green color
		)
		# Reset to original color on hover if not already green
		signup_button.mouse_entered.connect(func():
			if signup_button.modulate != Color(0.2, 0.8, 0.2, 1.0):
				signup_button.modulate = Color(1, 1, 1, 1.0)  # Reset to white
		)
	else:
		push_warning("Sign Up button not found in signup scene.")

	var login_link: LinkButton = _find_link_button_by_text("Log In")
	if login_link != null:
		login_link.pressed.connect(_on_login_pressed)
	else:
		push_warning("Log In link button not found in signup scene.")

	# Find terms link by node name
	var terms_link = get_node_or_null("termslink")
	if terms_link == null:
		terms_link = _find_link_button_by_text("Terms")
	if terms_link == null:
		terms_link = _find_link_button_by_text("Terms and Conditions")
	if terms_link != null and terms_link is LinkButton:
		terms_link.pressed.connect(_on_terms_link_pressed)
		print("Terms link connected")
	else:
		print("Terms link not found")

	# Find privacy link by node name (may be nested)
	var privacy_link = get_node_or_null("termslink/privacylink")
	if privacy_link == null:
		privacy_link = get_node_or_null("privacylink")
	if privacy_link == null:
		privacy_link = _find_link_button_by_text("Privacy")
	if privacy_link == null:
		privacy_link = _find_link_button_by_text("Privacy Policy")
	if privacy_link != null and privacy_link is LinkButton:
		privacy_link.pressed.connect(_on_privacy_link_pressed)
		print("Privacy link connected")
	else:
		print("Privacy link not found")

	_configure_password_fields()

	# Populate Grade and Section option buttons and wire selection
	var grade_option: OptionButton = get_node_or_null("LineEdit/LineEdit5/OptionButton") as OptionButton
	var section_option: OptionButton = get_node_or_null("LineEdit/LineEdit4/OptionButton") as OptionButton
	
	if grade_option != null:
		grade_option.clear()
		grade_option.add_item("6️⃣ Grade")
		grade_option.add_item("Grade 6")
		grade_option.select(0)
		grade_option.item_selected.connect(_on_grade_selected)
		
	if section_option != null:
		section_option.clear()
		section_option.add_item("🏫 Section")
		section_option.select(0)
		section_option.item_selected.connect(_on_section_selected)

func _configure_password_fields() -> void:
	var password_edit: LineEdit = get_node_or_null("LineEdit/LineEdit2") as LineEdit
	if password_edit != null:
		password_edit.secret = true
		_add_eye_toggle(password_edit, "Password")
	var confirm_edit: LineEdit = get_node_or_null("LineEdit/LineEdit3") as LineEdit
	if confirm_edit != null:
		confirm_edit.secret = true
		_add_eye_toggle(confirm_edit, "ConfirmPassword")

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

func _add_show_password_toggle(password_edit: LineEdit, confirm_edit: LineEdit) -> void:
	if get_node_or_null("ShowPasswordToggle") != null:
		return
	var toggle := CheckBox.new()
	toggle.name = "ShowPasswordToggle"
	toggle.text = "Show Password"
	var reference: Control = password_edit if password_edit != null else confirm_edit
	if reference != null:
		toggle.position = Vector2(reference.position.x, reference.position.y + reference.size.y + 10)
		if password_edit != null:
			toggle.position.x = min(toggle.position.x, password_edit.position.x)
	else:
		toggle.position = Vector2(60, 330)
		toggle.size = Vector2(180, 28)
	toggle.pressed.connect(func():
		if password_edit != null:
			password_edit.secret = not toggle.button_pressed
		if confirm_edit != null:
			confirm_edit.secret = not toggle.button_pressed
	)
	add_child(toggle)
	toggle.size = Vector2(180, 28)

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
	# First try exact match
	for child in get_children():
		var link_button := child as LinkButton
		if link_button != null and link_button.text == target_text:
			return link_button

		var nested_link: LinkButton = _find_link_button_in_branch(child, target_text)
		if nested_link != null:
			return nested_link
	
	# Try case-insensitive match
	var target_lower = target_text.to_lower()
	for child in get_children():
		var link_button := child as LinkButton
		if link_button != null and link_button.text.to_lower() == target_lower:
			return link_button

		var nested_link: LinkButton = _find_link_button_in_branch_case_insensitive(child, target_lower)
		if nested_link != null:
			return nested_link
	
	# Try partial match
	for child in get_children():
		var link_button := child as LinkButton
		if link_button != null and target_lower in link_button.text.to_lower():
			return link_button

		var nested_link: LinkButton = _find_link_button_in_branch_partial(child, target_lower)
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

func _find_link_button_in_branch_case_insensitive(node: Node, target_lower: String) -> LinkButton:
	for child in node.get_children():
		var link_button := child as LinkButton
		if link_button != null and link_button.text.to_lower() == target_lower:
			return link_button

		var nested_link: LinkButton = _find_link_button_in_branch_case_insensitive(child, target_lower)
		if nested_link != null:
			return nested_link

	return null

func _find_link_button_in_branch_partial(node: Node, target_lower: String) -> LinkButton:
	for child in node.get_children():
		var link_button := child as LinkButton
		if link_button != null and target_lower in link_button.text.to_lower():
			return link_button

		var nested_link: LinkButton = _find_link_button_in_branch_partial(child, target_lower)
		if nested_link != null:
			return nested_link

	return null

func _on_signup_button_pressed() -> void:
	# Prevent multiple signup attempts
	if _signup_in_progress:
		print("Signup already in progress, ignoring button press")
		_set_alert("Signup is already in progress. Please wait...", false)
		return
	
	var payload: Dictionary = _collect_signup_payload()
	var email: String = str(payload.get("email", "")).strip_edges()
	var password: String = str(payload.get("password", "")).strip_edges()
	var name_value: String = str(payload.get("name", "")).strip_edges()
	var confirm_password: String = str(payload.get("confirm_password", "")).strip_edges()
	var grade: String = str(payload.get("grade", "")).strip_edges()
	var section: String = str(payload.get("section", "")).strip_edges()
	var terms_checkbox: CheckBox = get_node_or_null("CheckBox") as CheckBox
	var missing_fields: Array[String] = _validate_signup_fields(email, password, name_value, confirm_password, grade, section)

	if _auth_manager == null:
		_set_status("Firebase is unavailable right now.", false)
		push_warning("FirebaseAuthManager is not available")
		return
	if not missing_fields.is_empty():
		_show_missing_fields(missing_fields)
		return
	if password != confirm_password:
		_set_status("Passwords do not match.", false)
		_set_alert("Passwords do not match. Please re-enter the same password in both fields.", true)
		push_warning("Passwords do not match")
		return
	if terms_checkbox == null or not terms_checkbox.button_pressed:
		_set_status("Please agree to the terms and conditions before signing up.", false)
		_set_alert("You must agree to the terms and conditions before creating an account.", true)
		push_warning("User must accept terms and conditions before signing up.")
		return

	_signup_in_progress = true
	_set_status("Signing up...", false)
	var payload_copy = payload.duplicate()  # Save payload for use in callback
	
	# Disable signup button
	var signup_button: Button = _find_button_by_text("Sign Up")
	if signup_button != null:
		signup_button.disabled = true
	
	print("Starting signup request with email: ", email)
	
	_auth_manager.sign_up(email, password, name_value, grade, section, func(ok, body):
		print("Signup callback received - ok: ", ok)
		print("Response body: ", body)
		_signup_in_progress = false
		
		# Re-enable signup button
		var signup_btn: Button = _find_button_by_text("Sign Up")
		if signup_btn != null:
			signup_btn.disabled = false
		
		if ok:
			print("Signup successful, processing response...")
			var created_user_id: String = email
			var auth_token: String = ""
			
			if body is Dictionary:
				if body.has("firebase_uid"):
					created_user_id = str(body.get("firebase_uid")).strip_edges()
				if body.has("auth_token"):
					auth_token = str(body.get("auth_token")).strip_edges()
			
			if created_user_id.is_empty():
				created_user_id = email
			
			print("Created user ID: ", created_user_id)
			
			if _session != null:
				_session.set_user(email, name_value, created_user_id, auth_token)
				print("Session updated with user info")
			
			# Save profile data
			_save_profile_after_signup(created_user_id, payload_copy)
			print("Profile saved")
			
			_set_status("Account created successfully. Redirecting...", true)
			print("About to change scene to question_12.tscn")
			
			# Schedule scene change for next frame to ensure all callbacks complete
			get_tree().call_deferred("change_scene_to_file", "res://question_12.tscn")
		else:
			print("Signup failed")
			var error_text: String = str(body)
			var is_email_exists: bool = false
			
			if body is Dictionary:
				if str(body.get("message", "")) == "EMAIL_EXISTS":
					is_email_exists = true
					error_text = "Email already registered. Logging you in..."
				else:
					error_text = str(body.get("message", str(body)))
			
			_set_status(error_text, is_email_exists)
			
			if is_email_exists:
				# Try to sign in with the provided password
				print("Email exists, attempting to sign in with provided password...")
				_attempt_signin_for_existing_email(email, password, name_value, email)
			else:
				_set_alert("Signup failed: %s" % error_text, true)
				print("Signup request failed: %s" % str(body))
	)

func _on_login_pressed() -> void:
	_change_scene_to_file("res://login.tscn")

func _attempt_signin_for_existing_email(email: String, password: String, display_name: String, user_id: String) -> void:
	"""Attempt to sign in when email already exists"""
	print("Attempting sign-in for existing email: ", email)
	
	if _auth_manager == null:
		_set_status("Firebase is unavailable", false)
		_set_alert("Cannot connect to Firebase", true)
		return
	
	if not _auth_manager.has_method("sign_in"):
		print("ERROR: sign_in method not available on auth manager")
		_set_status("Firebase sign-in unavailable", false)
		_set_alert("Sign-in is not available. Please try again.", true)
		return
	
	_auth_manager.sign_in(email, password, func(ok, body):
		print("Sign-in callback - ok: ", ok, " body: ", body)
		
		if ok:
			print("Sign-in successful!")
			var created_user_id: String = user_id
			var auth_token: String = ""
			
			if body is Dictionary:
				if body.has("firebase_uid"):
					created_user_id = str(body.get("firebase_uid")).strip_edges()
				if body.has("auth_token"):
					auth_token = str(body.get("auth_token")).strip_edges()
			
			if _session != null:
				_session.set_user(email, display_name, created_user_id, auth_token)
				print("Session updated after sign-in")
			
			_set_status("Logged in successfully. Redirecting...", true)
			print("Redirecting to question_12.tscn")
			get_tree().call_deferred("change_scene_to_file", "res://question_12.tscn")
		else:
			print("Sign-in failed: ", body)
			var error_text: String = "Invalid password or account error"
			if body is Dictionary:
				error_text = str(body.get("message", error_text))
			_set_status("Sign-in failed: %s" % error_text, false)
			_set_alert("Sign-in failed. Please check your password and try again.", true)
	)


func _on_terms_link_pressed() -> void:
	"""Go to terms page from signup"""
	print("Terms link pressed - navigating to terms_signup.tscn")
	get_tree().root.set_meta("terms_from_signup", true)
	_change_scene_to_file("res://terms_signup.tscn")

func _on_privacy_link_pressed() -> void:
	"""Go to privacy page from signup"""
	print("Privacy link pressed - navigating to privacy_signup.tscn")
	get_tree().root.set_meta("privacy_from_signup", true)
	_change_scene_to_file("res://privacy_signup.tscn")

func _save_profile_after_signup(user_id: String, payload: Dictionary) -> void:
	"""Save profile data to database after successful signup"""
	var profile_data := {
		"name": payload.get("name", ""),
		"grade_level": payload.get("grade", ""),
		"section": payload.get("section", ""),
		"email": payload.get("email", ""),
		"gender": payload.get("gender", ""),
	}
	
	var auth = _resolve_auth_manager()
	if auth != null and auth.has_method("save_profile_attributes"):
		auth.save_profile_attributes(user_id, profile_data, func(ok: bool, _details: Variant):
			if ok:
				print("Profile saved after signup with gender: ", profile_data.get("gender", "not set"))
				# Also save to session for immediate access
				if _session != null and _session.has_method("set_user_profile"):
					_session.call("set_user_profile", profile_data)
			else:
				print("Warning: Profile save failed after signup")
		)

func _collect_signup_payload() -> Dictionary:
	var name_edit: LineEdit = get_node_or_null("LineEdit") as LineEdit
	var email_edit: LineEdit = get_node_or_null("LineEdit/LineEdit") as LineEdit
	var password_edit: LineEdit = get_node_or_null("LineEdit/LineEdit2") as LineEdit
	var confirm_edit: LineEdit = get_node_or_null("LineEdit/LineEdit3") as LineEdit
	var grade_display: LineEdit = get_node_or_null("LineEdit/LineEdit5") as LineEdit
	var section_display: LineEdit = get_node_or_null("LineEdit/LineEdit4") as LineEdit

	var active_grade: String = _selected_grade
	if grade_display != null and grade_display.text.strip_edges() != "":
		active_grade = grade_display.text.strip_edges()
	var active_section: String = _selected_section
	if section_display != null and section_display.text.strip_edges() != "":
		active_section = section_display.text.strip_edges()

	return {
		"name": name_edit.text if name_edit != null else "",
		"email": email_edit.text if email_edit != null else "",
		"password": password_edit.text if password_edit != null else "",
		"confirm_password": confirm_edit.text if confirm_edit != null else "",
		"grade": active_grade,
		"section": active_section,
		"gender": _selected_gender
	}

func _resolve_auth_manager() -> Node:
	var root: Node = get_tree().root
	if root != null:
		var manager: Node = root.get_node_or_null("FirebaseAuthManager")
		if manager != null:
			return manager
	if Engine.has_singleton("FirebaseAuthManager"):
		return Engine.get_singleton("FirebaseAuthManager")
	return null

func _set_status(message: String, success: bool) -> void:
	var label: Label = get_node_or_null("StatusLabel") as Label
	if label == null:
		label = get_node_or_null("Label/StatusLabel") as Label
	if label == null:
		label = get_node_or_null("Panel/StatusLabel") as Label
	if label == null:
		return
	label.text = message
	label.modulate = Color(0.0, 0.6, 0.0, 1.0) if success else Color(0.8, 0.0, 0.0, 1.0)

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
	print("_change_scene_to_file called with target: ", target_scene)
	
	if not is_instance_valid(self):
		print("ERROR: Scene instance is not valid")
		return
	
	if is_queued_for_deletion():
		print("ERROR: Scene is queued for deletion")
		return
	
	if not is_inside_tree():
		print("ERROR: Scene is not inside tree")
		return
	
	print("Attempting to load scene: ", target_scene)
	var scene_resource: Variant = load(target_scene)
	
	if scene_resource == null:
		print("ERROR: Scene resource is null: ", target_scene)
		return
	
	if not (scene_resource is PackedScene):
		print("ERROR: Loaded resource is not a PackedScene: ", target_scene, " - Type: ", scene_resource.get_class())
		return
	
	print("Scene resource loaded successfully")
	var tree: SceneTree = get_tree()
	
	if tree == null:
		print("ERROR: SceneTree is null")
		return
	
	print("Changing scene using tree...")
	if tree.has_method("change_scene_to_packed"):
		print("Using change_scene_to_packed method")
		tree.change_scene_to_packed(scene_resource)
	elif tree.has_method("change_scene_to_file"):
		print("Using change_scene_to_file method")
		tree.change_scene_to_file(target_scene)
	else:
		print("ERROR: SceneTree has no scene change method")
	
	print("Scene change initiated")



func _on_grade_selected(idx: int) -> void:
	var grade_option: OptionButton = get_node_or_null("LineEdit/LineEdit5/OptionButton") as OptionButton
	var section_option: OptionButton = get_node_or_null("LineEdit/LineEdit4/OptionButton") as OptionButton
	var grade_display: LineEdit = get_node_or_null("LineEdit/LineEdit5") as LineEdit
	var section_display: LineEdit = get_node_or_null("LineEdit/LineEdit4") as LineEdit
	
	if grade_option == null or idx == 0:
		return
	
	var grade = grade_option.get_item_text(idx)
	_selected_grade = grade
	if grade_display != null:
		grade_display.text = grade
	
	# Reset section when grade changes
	_selected_section = ""
	if section_display != null:
		section_display.text = ""
	
	# Populate sections
	_populate_sections_for_grade(grade, section_option)


func _on_section_selected(idx: int) -> void:
	var section_option: OptionButton = get_node_or_null("LineEdit/LineEdit4/OptionButton") as OptionButton
	var section_display: LineEdit = get_node_or_null("LineEdit/LineEdit4") as LineEdit
	
	if section_option == null or idx == 0:
		return
	
	var section_text = section_option.get_item_text(idx)
	_selected_section = section_text
	if section_display != null:
		section_display.text = section_text


func _populate_sections_for_grade(grade: String, section_option: OptionButton) -> void:
	if section_option == null:
		return
	section_option.clear()
	section_option.add_item("🏫 Section")
	var list = _grade_sections.get(grade, [])
	for s in list:
		section_option.add_item(s)
	section_option.select(0)


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

func _validate_signup_fields(email: String, password: String, name_value: String, confirm_password: String, grade: String, section: String) -> Array[String]:
	var missing_fields: Array[String] = []
	if name_value.is_empty():
		missing_fields.append("Name")
	if email.is_empty():
		missing_fields.append("Email")
	elif not email.contains("@gmail.com"):
		missing_fields.append("Email must be @gmail.com")
	if password.is_empty():
		missing_fields.append("Password")
	if confirm_password.is_empty():
		missing_fields.append("Confirm Password")
	if grade.is_empty() or grade == "6️⃣ Grade":
		missing_fields.append("Grade")
	if section.is_empty() or section == "🏫 Section":
		missing_fields.append("Section")
	return missing_fields
