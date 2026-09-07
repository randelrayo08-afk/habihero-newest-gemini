extends Control

const ANSWER_STORE_KEY := "question_answers"

func _ready() -> void:
	_connect_navigation_button()
	_connect_answer_buttons()

	# Scene-specific setup
	if name.to_lower().find("question_12") != -1 or name.to_lower().find("question12") != -1:
		_setup_question_12()
	
	# Restore previously selected button for this scene
	_restore_selected_button()

func _connect_navigation_button() -> void:
	var target_button: Button = _find_button_by_text(_resolve_button_text())
	if target_button != null:
		if not target_button.pressed.is_connected(_on_target_button_pressed):
			target_button.pressed.connect(_on_target_button_pressed)
	else:
		push_warning("Button with text '%s' not found in %s." % [_resolve_button_text(), name])

func _connect_answer_buttons() -> void:
	for child in _get_all_descendants(self):
		var button: Button = child as Button
		if button == null:
			continue
		if _is_navigation_button(button):
			continue
		# Skip UI control buttons that are not answer choices
		var txt := _get_button_text(button).strip_edges()
		if txt == "+" or txt == "-":
			continue
		var lower := txt.to_lower()
		if lower == "boy" or lower == "girl":
			# These are handled specially for question_12
			continue
		if txt == "Save" or txt == "Cancel" or txt == "OK" or txt == "Back" or txt == "Sent!":
			continue
		if not button.pressed.is_connected(_on_answer_button_pressed):
			button.pressed.connect(_on_answer_button_pressed.bind(button))

func _find_button_by_text(search_text: String) -> Button:
	"""Find a button by its text (checks button.text and child Labels)"""
	for child in _get_all_descendants(self):
		var button: Button = child as Button
		if button == null:
			continue
		var btn_text := _get_button_text(button).strip_edges()
		if btn_text == search_text:
			return button
	return null

func _restore_selected_button() -> void:
	"""Restore previously selected button state for this scene"""
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	if not answers.has(name):
		return
	
	var saved_answer: String = str(answers[name]).strip_edges()
	if saved_answer.is_empty():
		return
	
	# Find and highlight the button that matches the saved answer
	for child in _get_all_descendants(self):
		var button: Button = child as Button
		if button == null:
			continue
		if _is_navigation_button(button):
			continue
		var btn_text := _get_button_text(button).strip_edges()
		if btn_text == saved_answer:
			button.modulate = Color(0.65, 1.0, 0.7, 1.0)
			button.disabled = false
		else:
			button.modulate = Color(1, 1, 1, 1)
			button.disabled = false

func _get_all_descendants(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_descendants(child))
	return result


func _get_button_text(button: Button) -> String:
	# Return the visible text for a Button. Many scenes put the label in a child Label node.
	if button == null:
		return ""
	if button.text != null and button.text.strip_edges() != "":
		return str(button.text)
	# Look for a Label child
	for child in button.get_children():
		if child is Label:
			return str(child.text)
	# As a fallback, search descendants
	for desc in _get_all_descendants(button):
		if desc is Label:
			return str(desc.text)
	return ""

func _is_navigation_button(button: Button) -> bool:
	var label: String = _get_button_text(button).strip_edges().to_lower()
	return label == "continue" or label == "finish"

func _on_answer_button_pressed(button: Button) -> void:
	var answer: String = _get_button_text(button).strip_edges()
	if answer.is_empty():
		return

	if answer.to_lower() == "other":
		# Record origin so the popup can return and save the "Other" text to this question
		var root: Window = get_tree().root
		root.set_meta("popup_origin_scene", name)
		root.set_meta("popup_origin_choice", answer)
		# Redirect to popup_question.tscn
		_change_scene_to_file("res://popup_question.tscn")
		return
	
	# Single-select: record answer and highlight only this button
	_record_answer(answer, button)

func _record_answer(answer: String, button: Button) -> void:
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	answers[name] = answer
	root.set_meta(ANSWER_STORE_KEY, answers)
	_save_current_answers_to_firebase()

	# Deselect all other buttons and revert their color
	for child in _get_all_descendants(self):
		var each_button: Button = child as Button
		if each_button != null and each_button != button:
			var txt := _get_button_text(each_button).strip_edges().to_lower()
			if txt != "+" and txt != "-" and txt != "save" and txt != "cancel" and txt != "ok" and txt != "back" and txt != "sent!" and txt != "continue" and txt != "finish":
				each_button.modulate = Color(1, 1, 1, 1)
				each_button.disabled = false
				each_button.focus_mode = Control.FOCUS_ALL

	# Select only this button (green highlight)
	button.modulate = Color(0.65, 1.0, 0.7, 1.0)
	button.disabled = false

func _save_current_answers_to_firebase() -> void:
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	if answers.is_empty():
		return

	var user_id: String = _get_current_user_id()
	if user_id.is_empty():
		user_id = "guest_user"

	var firebase_manager: Variant = _resolve_firebase_manager()
	if firebase_manager != null and firebase_manager.has_method("save_scene_input"):
		var payload: Dictionary = {
			"question": name,
			"answers": answers.duplicate(true),
			"saved_at": Time.get_datetime_string_from_system(false, true),
		}
		# Save to progress/{scene_name} not to timestamped entries
		_save_question_response_to_firebase(firebase_manager, user_id, payload)
		return

	var db: Node = root.get_node_or_null("FirebaseRTDB")
	if db == null and Engine.has_singleton("FirebaseRTDB"):
		db = Engine.get_singleton("FirebaseRTDB")
	if db != null and db.has_method("write_json"):
		var payload: Dictionary = {
			"question": name,
			"answers": answers.duplicate(true),
			"saved_at": Time.get_datetime_string_from_system(false, true),
		}
		db.call("write_json", "users/%s/%s" % [_safe_firebase_key(user_id), name], payload)

func _save_question_response_to_firebase(firebase_manager: Variant, user_id: String, payload: Dictionary) -> void:
	"""Save question responses to user profile for task personalization.
	Maps question answers to profile attributes:
	- question_12: age, gender
	- question_34: interests, mood
	- others: stored in profile.responses
	"""
	if firebase_manager == null:
		return
	
	var profile_update: Dictionary = {}
	var answers: Dictionary = payload.get("answers", {})
	
	# Map question_12 responses to profile
	if name.to_lower().contains("question_12") or name.to_lower().contains("question12"):
		# Extract age from answers
		if answers.has(name + "_age"):
			var age_val = str(answers[name + "_age"]).strip_edges()
			if age_val.is_valid_int():
				profile_update["age"] = int(age_val)
		
		# Extract gender from answers
		if answers.has(name + "_gender"):
			var gender_val = str(answers[name + "_gender"]).strip_edges().to_lower()
			if gender_val in ["boy", "girl"]:
				profile_update["gender"] = gender_val
		
		print("question_nav: Saving question_12 to profile: age=%s, gender=%s" % [
			profile_update.get("age", "unset"),
			profile_update.get("gender", "unset")
		])
	
	# Map question_34 responses to profile
	elif name.to_lower().contains("question_34") or name.to_lower().contains("question34"):
		var interests: Array[String] = []
		var _mood: String = ""
		
		# Collect selected interests and mood
		for key in answers.keys():
			if key.contains("like_to_do"):
				var val = str(answers[key]).strip_edges()
				if not val.is_empty() and val not in interests:
					interests.append(val)
			elif key.contains("adventure_today"):
				var val = str(answers[key]).strip_edges()
				if not val.is_empty() and val not in interests:
					interests.append(val)
			elif key.contains("mood"):
				var mood_value = str(answers[key]).strip_edges()
				if not mood_value.is_empty():
					_mood = mood_value
		
		if interests.size() > 0:
			profile_update["interests"] = interests
		if not _mood.is_empty():
			profile_update["mood"] = _mood.to_lower()
		
		print("question_nav: Saving question_34 to profile: interests=%s, mood=%s" % [
			profile_update.get("interests", []),
			profile_update.get("mood", "unset")
		])
	
	# Generic fallback: store all answers in profile.responses
	if profile_update.is_empty():
		profile_update["responses"] = answers
	
	# Save to profile
	if firebase_manager.has_method("save_profile_attributes"):
		firebase_manager.call("save_profile_attributes", user_id, profile_update)
	elif firebase_manager.has_method("save_scene_input"):
		firebase_manager.call("save_scene_input", user_id, name, payload)

func _get_current_user_id() -> String:
	var root: Window = get_tree().root
	var session: Node = root.get_node_or_null("UserSession")
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	if session != null:
		if session.has_method("get_current_user_id"):
			var uid: String = str(session.call("get_current_user_id")).strip_edges()
			if not uid.is_empty():
				return uid
	var auth: Node = root.get_node_or_null("FirebaseAuthManager")
	if auth == null and Engine.has_singleton("FirebaseAuthManager"):
		auth = Engine.get_singleton("FirebaseAuthManager")
	if auth != null and auth.has_method("get_current_user"):
		var user = auth.call("get_current_user")
		if user != null and user is Dictionary and user.has("uid"):
			var auth_uid: String = str(user["uid"]).strip_edges()
			if not auth_uid.is_empty():
				return auth_uid
	return ""

func _resolve_firebase_manager() -> Variant:
	var root: Window = get_tree().root
	var manager: Node = root.get_node_or_null("FirebaseAuthManager")
	if manager == null and Engine.has_singleton("FirebaseAuthManager"):
		manager = Engine.get_singleton("FirebaseAuthManager")
	return manager

func _safe_firebase_key(value: String) -> String:
	var safe: String = value.strip_edges().to_lower()
	safe = safe.replace("@", "_")
	safe = safe.replace(".", "_")
	safe = safe.replace(" ", "_")
	return safe

func _on_target_button_pressed() -> void:
	# Prevent navigation unless this scene has a recorded answer
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	
	if answers.has(name) and not str(answers[name]).strip_edges().is_empty():
		_save_current_answers_to_firebase()
		_change_scene_to_file(_resolve_next_scene())
	else:
		_show_require_answer_alert()

func _resolve_button_text() -> String:
	if name.to_lower().contains("question_34") or name.to_lower().contains("question34"):
		return "Finish"
	return "Continue"

func _resolve_next_scene() -> String:
	if name.to_lower().contains("question_34") or name.to_lower().contains("question34"):
		return "res://home.tscn"
	return "res://question_34.tscn"

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


func _show_require_answer_alert() -> void:
	# If this is question_34, show in-scene alert for single-select
	if name.to_lower().find("question_34") != -1 or name.to_lower().find("question34") != -1:
		_show_in_scene_alert("Please select an option before finishing.")
		return
	
	# If this is question_12, show an in-scene label listing which sub-answers are missing
	if name.to_lower().find("question_12") != -1 or name.to_lower().find("question12") != -1:
		var missing: Array[String] = []
		# check age presence
		var age_found: bool = false
		for child in _get_all_descendants(self):
			if child is Label and child.text.strip_edges().is_valid_int():
				age_found = true
				break
		if not age_found:
			missing.append("Age")
		# check gender presence by detecting selected state
		var gender_found: bool = false
		for child in _get_all_descendants(self):
			if child is Button and _get_button_text(child).strip_edges().to_lower() in ["boy","girl"]:
				if child.button_pressed:
					gender_found = true
					break
		if not gender_found:
			missing.append("Gender")

		var label_name := "__require_answer_label__"
		var req_label: Label = get_node_or_null(label_name) as Label
		if req_label == null:
			req_label = Label.new()
			req_label.name = label_name
			req_label.custom_minimum_size = Vector2(400, 60)
			var vw := 0.0
			if get_viewport() != null:
				vw = get_viewport().get_visible_rect().size.x
			req_label.position = Vector2(max(10, (vw - 400) / 2), 30)
			req_label.add_theme_color_override("font_color", Color(0.76, 0.02, 0.02, 1))
			req_label.autowrap_mode = 3 as TextServer.AutowrapMode
			add_child(req_label)

		if missing.size() == 0:
			req_label.visible = false
			return
		# build message
		var msg := "Missing required information:\n"
		for m in missing:
			msg += " - %s\n" % m
		req_label.text = msg
		req_label.visible = true
		# hide after 3 seconds
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = 3.0
		t.connect("timeout", Callable(req_label, "hide"))
		add_child(t)
		t.start()
		return

	# Fallback: generic centered popup for other scenes
	if find_child("__require_answer_popup__", false, false) != null:
		return
	var popup := PopupPanel.new()
	popup.name = "__require_answer_popup__"
	popup.popup_window = true
	add_child(popup)
	var panel := PanelContainer.new()
	popup.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var label := Label.new()
	label.text = "Please answer the question before continuing."
	label.autowrap_mode = 3 as TextServer.AutowrapMode
	label.custom_minimum_size = Vector2(280, 0)
	vbox.add_child(label)
	var ok := Button.new()
	ok.text = "OK"
	ok.pressed.connect(popup.hide)
	vbox.add_child(ok)
	popup.popup_centered(Vector2i(320, 120))

func _show_in_scene_alert(message: String) -> void:
	var label_name := "__require_answer_label__"
	var req_label: Label = get_node_or_null(label_name) as Label
	if req_label == null:
		req_label = Label.new()
		req_label.name = label_name
		req_label.custom_minimum_size = Vector2(400, 60)
		var vw := 0.0
		if get_viewport() != null:
			vw = get_viewport().get_visible_rect().size.x
		req_label.position = Vector2(max(10, (vw - 400) / 2), 30)
		req_label.add_theme_color_override("font_color", Color(0.76, 0.02, 0.02, 1))
		req_label.autowrap_mode = 3 as TextServer.AutowrapMode
		add_child(req_label)
	
	req_label.text = message
	req_label.visible = true
	# hide after 3 seconds
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 3.0
	t.connect("timeout", Callable(req_label, "hide"))
	add_child(t)
	t.start()

func _setup_question_12() -> void:
	# Find age label (initially "0"), plus and minus buttons, and gender buttons
	var age_label: Label = null
	var plus_btn: Button = null
	var minus_btn: Button = null
	var boy_btn: Button = null
	var girl_btn: Button = null

	for child in _get_all_descendants(self):
		if age_label == null and child is Label and child.text.strip_edges() == "0":
			age_label = child
		if child is Button and _get_button_text(child).strip_edges() == "+":
			plus_btn = child
		if child is Button and _get_button_text(child).strip_edges() == "-":
			minus_btn = child
		if child is Button and _get_button_text(child).strip_edges().to_lower() == "boy":
			boy_btn = child
		if child is Button and _get_button_text(child).strip_edges().to_lower() == "girl":
			girl_btn = child

	# Create a small popup LineEdit for manual age entry
	var age_popup := PopupPanel.new()
	age_popup.name = "__age_popup__"
	var pc := PanelContainer.new()
	age_popup.add_child(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	var lbl := Label.new()
	lbl.text = "Enter age (0 or greater):"
	vb.add_child(lbl)
	var le := LineEdit.new()
	le.placeholder_text = "0"
	le.custom_minimum_size = Vector2(200, 0)
	le.text_submitted.connect(func(t):
		_commit_age_entry(t, age_label, age_popup)
	)
	vb.add_child(le)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var saveb := Button.new()
	saveb.text = "Save"
	saveb.pressed.connect(func(): _commit_age_entry(le.text, age_label, age_popup))
	hb.add_child(saveb)
	var cancelb := Button.new()
	cancelb.text = "Cancel"
	cancelb.pressed.connect(age_popup.hide)
	hb.add_child(cancelb)
	add_child(age_popup)

	# Connect plus/minus
	if plus_btn != null:
		plus_btn.pressed.connect(func(): _change_age_by(1, age_label))
	if minus_btn != null:
		minus_btn.pressed.connect(func(): _change_age_by(-1, age_label))

	# Allow clicking the label to open the popup
	if age_label != null:
		age_label.mouse_filter = Control.MOUSE_FILTER_PASS
		age_label.connect("gui_input", Callable(self, "_on_age_label_input").bind(age_label, age_popup, le))

	# Connect gender buttons
	if boy_btn != null:
		boy_btn.pressed.connect(func(): _select_gender("Boy", boy_btn, girl_btn))
	if girl_btn != null:
		girl_btn.pressed.connect(func(): _select_gender("Girl", girl_btn, boy_btn))


func _change_age_by(delta: int, age_label: Label) -> void:
	if age_label == null:
		return
	var cur: int = 0
	var t := age_label.text.strip_edges()
	if t.is_valid_int():
		cur = int(t)
	cur = max(0, cur + delta)
	age_label.text = str(cur)
	_update_question12_record(age_label)


func _on_age_label_input(event: InputEvent, age_label: Label, age_popup: PopupPanel, le: LineEdit) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		# open popup with current value
		le.text = age_label.text.strip_edges()
		age_popup.popup_centered(Vector2i(320, 120))
		le.grab_focus()


func _commit_age_entry(text: String, age_label: Label, popup: PopupPanel) -> void:
	var s := text.strip_edges()
	if s.is_empty():
		return
	# allow only non-negative integers
	if not s.is_valid_int():
		# ignore invalid input
		return
	var n := int(s)
	if n < 0:
		return
	age_label.text = str(n)
	popup.hide()
	_update_question12_record(age_label)


func _select_gender(gender: String, selected: Button, other: Button) -> void:
	# visually highlight selected and un-highlight the other
	if selected != null:
		selected.modulate = Color(0.65, 1.0, 0.7, 1.0)
		selected.button_pressed = true
	if other != null:
		other.modulate = Color(1, 1, 1, 1)
		other.button_pressed = false
	var age_label: Label = null
	for child in _get_all_descendants(self):
		if child is Label and child.text.strip_edges().is_valid_int():
			age_label = child
			break
	_update_question12_record(age_label, gender)


func _update_question12_record(age_label: Label, gender_override: String = "") -> void:
	var age := ""
	if age_label != null:
		age = age_label.text.strip_edges()
	var gender := gender_override
	if gender == "":
		for child in _get_all_descendants(self):
			if child is Button and _get_button_text(child).strip_edges().to_lower() in ["boy","girl"]:
				if child.button_pressed:
					gender = _get_button_text(child).strip_edges()
	if age != "" and gender != "":
		var root: Window = get_tree().root
		var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
		answers[name] = "%s|%s" % [age, gender]
		root.set_meta(ANSWER_STORE_KEY, answers)
