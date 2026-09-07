extends Control

var _auth_manager: Node = null
var _session: Node = null
var _current_user_id: String = ""
var _confirmation_dialog: Panel = null

func _ready() -> void:
	_resolve_dependencies()
	_connect_buttons()
	_load_profile_into_fields()

func _resolve_dependencies() -> void:
	if get_tree() != null and get_tree().root != null:
		_auth_manager = get_tree().root.get_node_or_null("FirebaseAuthManager")
		_session = get_tree().root.get_node_or_null("UserSession")
	if _auth_manager == null and Engine.has_singleton("FirebaseAuthManager"):
		_auth_manager = Engine.get_singleton("FirebaseAuthManager")
	if _session == null and Engine.has_singleton("UserSession"):
		_session = Engine.get_singleton("UserSession")

func _connect_buttons() -> void:
	var save_button: Button = get_node_or_null("Panel2/Button2") as Button
	if save_button != null:
		if not save_button.pressed.is_connected(_on_save_pressed):
			save_button.pressed.connect(_on_save_pressed)

	var back_button: Button = get_node_or_null("Panel2/back_edit") as Button
	if back_button != null:
		if not back_button.pressed.is_connected(_on_back_pressed):
			back_button.pressed.connect(_on_back_pressed)

	var legacy_back_button: Button = get_node_or_null("Button") as Button
	if legacy_back_button != null:
		if not legacy_back_button.pressed.is_connected(_on_back_pressed):
			legacy_back_button.pressed.connect(_on_back_pressed)

	_create_confirmation_dialog()

func _create_confirmation_dialog() -> void:
	if _confirmation_dialog != null and is_instance_valid(_confirmation_dialog):
		return

	var overlay: ColorRect = ColorRect.new()
	overlay.name = "ProfileConfirmOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)

	var dialog_panel: Panel = Panel.new()
	dialog_panel.name = "ProfileConfirmDialog"
	dialog_panel.size = Vector2(340, 180)
	dialog_panel.position = Vector2(90, 250)
	dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog_panel.visible = false
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.56, 0.34, 0.14, 1.0)
	panel_style.border_width_left = 5
	panel_style.border_width_top = 5
	panel_style.border_width_right = 5
	panel_style.border_width_bottom = 5
	panel_style.border_color = Color(0.86, 0.74, 0.24, 1.0)
	panel_style.corner_radius_top_left = 28
	panel_style.corner_radius_top_right = 28
	panel_style.corner_radius_bottom_right = 28
	panel_style.corner_radius_bottom_left = 28
	panel_style.shadow_color = Color(0, 0, 0, 0.7)
	panel_style.shadow_size = 6
	dialog_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(dialog_panel)

	var dialog_margin: MarginContainer = MarginContainer.new()
	dialog_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_margin.offset_left = 20
	dialog_margin.offset_top = 20
	dialog_margin.offset_right = -20
	dialog_margin.offset_bottom = -20
	dialog_panel.add_child(dialog_margin)

	var dialog_vbox: VBoxContainer = VBoxContainer.new()
	dialog_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dialog_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog_vbox.add_theme_constant_override("separation", 18)
	dialog_margin.add_child(dialog_vbox)

	var title_label: Label = Label.new()
	title_label.text = "Are you sure you want to change your profile?"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size = Vector2(300, 70)
	title_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title_label.add_theme_font_size_override("font_size", 18)
	dialog_vbox.add_child(title_label)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_theme_constant_override("separation", 20)
	dialog_vbox.add_child(button_row)

	var cancel_button: Button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(110, 44)
	var cancel_style: StyleBoxFlat = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.78, 0.78, 0.78, 1.0)
	cancel_style.border_width_left = 2
	cancel_style.border_width_top = 2
	cancel_style.border_width_right = 2
	cancel_style.border_width_bottom = 2
	cancel_style.border_color = Color(0.2, 0.2, 0.2, 1.0)
	cancel_style.corner_radius_top_left = 18
	cancel_style.corner_radius_top_right = 18
	cancel_style.corner_radius_bottom_right = 18
	cancel_style.corner_radius_bottom_left = 18
	cancel_button.add_theme_stylebox_override("normal", cancel_style)
	cancel_button.add_theme_stylebox_override("hover", cancel_style)
	cancel_button.add_theme_stylebox_override("pressed", cancel_style)
	cancel_button.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1.0))
	cancel_button.add_theme_font_size_override("font_size", 16)
	cancel_button.pressed.connect(_hide_confirmation_popup)
	button_row.add_child(cancel_button)

	var confirm_button: Button = Button.new()
	confirm_button.text = "Yes"
	confirm_button.custom_minimum_size = Vector2(110, 44)
	var confirm_style: StyleBoxFlat = StyleBoxFlat.new()
	confirm_style.bg_color = Color(0.18, 0.55, 0.18, 1.0)
	confirm_style.border_width_left = 2
	confirm_style.border_width_top = 2
	confirm_style.border_width_right = 2
	confirm_style.border_width_bottom = 2
	confirm_style.border_color = Color(0.18, 0.33, 0.12, 1.0)
	confirm_style.corner_radius_top_left = 18
	confirm_style.corner_radius_top_right = 18
	confirm_style.corner_radius_bottom_right = 18
	confirm_style.corner_radius_bottom_left = 18
	confirm_button.add_theme_stylebox_override("normal", confirm_style)
	confirm_button.add_theme_stylebox_override("hover", confirm_style)
	confirm_button.add_theme_stylebox_override("pressed", confirm_style)
	confirm_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	confirm_button.add_theme_font_size_override("font_size", 16)
	confirm_button.pressed.connect(_confirm_save_profile)
	button_row.add_child(confirm_button)

	_confirmation_dialog = dialog_panel
	_hide_confirmation_popup()

func _show_confirmation_popup() -> void:
	var overlay: ColorRect = get_node_or_null("ProfileConfirmOverlay") as ColorRect
	var panel: Panel = get_node_or_null("ProfileConfirmDialog") as Panel
	if overlay == null or panel == null:
		return
	overlay.visible = true
	panel.visible = true
	panel.position = Vector2(90, 250)

func _hide_confirmation_popup() -> void:
	var overlay: ColorRect = get_node_or_null("ProfileConfirmOverlay") as ColorRect
	var panel: Panel = get_node_or_null("ProfileConfirmDialog") as Panel
	if overlay != null:
		overlay.visible = false
	if panel != null:
		panel.visible = false

func _on_save_pressed() -> void:
	_show_confirmation_popup()

func _confirm_save_profile() -> void:
	_hide_confirmation_popup()
	var user_id = _resolve_current_user_id()
	if user_id.is_empty():
		push_warning("EditProfile: cannot save because no user id is available.")
		return

	var payload = _collect_profile_payload()
	if payload.get("name", "").strip_edges().is_empty():
		push_warning("EditProfile: name cannot be empty.")
		return
	if payload.get("email", "").strip_edges().is_empty():
		push_warning("EditProfile: email cannot be empty.")
		return

	if _auth_manager != null and _auth_manager.has_method("save_profile_attributes"):
		_auth_manager.call("save_profile_attributes", user_id, payload, func(ok: bool, _body: Variant):
			if ok:
				if _session != null and _session.has_method("set_user"):
					_session.call("set_user", payload.get("email", ""), payload.get("name", ""), user_id, _session.get_current_user_token())
					if _session != null and _session.has_method("set_user_profile"):
						_session.call("set_user_profile", payload)
				print("EditProfile: profile updated in Firebase.")
				_show_save_feedback("Profile updated successfully.")
			else:
				print("EditProfile: save failed -> ", _body)
				_show_save_feedback("Profile save failed. Please try again.")
		)
		return

	var db = get_tree().root.get_node_or_null("FirebaseRTDB")
	if db != null and db.has_method("write_json"):
		db.write_json("users/%s/profile" % _safe_key(user_id), payload, func(result: int, response_code: int, _body: Variant):
			var ok = result == OK and response_code >= 200 and response_code < 300
			if ok:
				_show_save_feedback("Profile updated successfully.")
			else:
				_show_save_feedback("Profile save failed. Please try again.")
		)

func _show_save_feedback(message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Profile Update"
	dialog.dialog_text = message
	dialog.min_size = Vector2(320, 120)
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_PRIMARY_SCREEN
	add_child(dialog)
	dialog.popup_centered()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://settings.tscn")

func _resolve_current_user_id() -> String:
	if _session != null and _session.has_method("get_current_user_id"):
		var session_id: String = str(_session.call("get_current_user_id")).strip_edges()
		if session_id != "" and session_id != "guest_user":
			return session_id
	if _auth_manager != null and _auth_manager.has_method("get_current_user_id"):
		var auth_id: String = str(_auth_manager.call("get_current_user_id")).strip_edges()
		if auth_id != "" and auth_id != "guest_user":
			return auth_id
	if _session != null and _session.has_method("get_current_user_email"):
		var email: String = str(_session.call("get_current_user_email")).strip_edges()
		if email != "":
			return email
	return ""

func _safe_key(value: String) -> String:
	var key = value.strip_edges().to_lower()
	key = key.replace("@", "_")
	key = key.replace(".", "_")
	key = key.replace(" ", "_")
	return key

func _load_profile_into_fields() -> void:
	var user_id = _resolve_current_user_id()
	_current_user_id = user_id

	var name_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/NameInputRow/LineEdit") as LineEdit
	var email_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/BirthdayInputRow/BirthdayEdit") as LineEdit

	if _session != null and _session.has_method("get_current_user_name"):
		var session_name: String = str(_session.call("get_current_user_name")).strip_edges()
		if session_name != "" and session_name != "Guest" and name_edit != null:
			name_edit.text = session_name
	if _session != null and _session.has_method("get_current_user_email"):
		var session_email: String = str(_session.call("get_current_user_email")).strip_edges()
		if session_email != "" and email_edit != null:
			email_edit.text = session_email

	if user_id.is_empty():
		print("EditProfile: No user id available for profile load.")
		return

	if _auth_manager != null and _auth_manager.has_method("load_profile"):
		_auth_manager.call("load_profile", user_id, func(ok: bool, profile: Variant):
			if ok and profile is Dictionary:
				_apply_profile_data(profile)
			else:
				print("EditProfile: profile load failed or no profile yet.")
		)
		return

	var db = get_tree().root.get_node_or_null("FirebaseRTDB")
	if db != null and db.has_method("read_json"):
		var safe_key = _safe_key(user_id)
		db.read_json("users/%s/profile" % safe_key, func(result: int, response_code: int, body: Variant):
			if result == OK and response_code >= 200 and response_code < 300 and body is Dictionary:
				_apply_profile_data(body)
		)

func _apply_profile_data(profile: Dictionary) -> void:
	var name_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/NameInputRow/LineEdit") as LineEdit
	var email_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/BirthdayInputRow/BirthdayEdit") as LineEdit

	if name_edit != null and profile.has("name"):
		name_edit.text = str(profile.get("name", "")).strip_edges()
	if email_edit != null and profile.has("email"):
		email_edit.text = str(profile.get("email", "")).strip_edges()

func _collect_profile_payload() -> Dictionary:
	var name_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/NameInputRow/LineEdit") as LineEdit
	var email_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/BirthdayInputRow/BirthdayEdit") as LineEdit

	var payload: Dictionary = {}
	if name_edit != null:
		payload["name"] = name_edit.text.strip_edges()
	if email_edit != null:
		payload["email"] = email_edit.text.strip_edges()
	return payload
