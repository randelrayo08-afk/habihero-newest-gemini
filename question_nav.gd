extends Control

const ANSWER_STORE_KEY := "question_answers"
var selected_buttons: Dictionary = {}  # Track selected buttons: {button_text: Button}

func _ready() -> void:
	# Ensure buttons are clickable and have proper focus settings
	_enable_button_interaction()
	
	# Connect all buttons
	_connect_navigation_button()
	_connect_answer_buttons()

	# Scene-specific setup
	if name.to_lower().find("question_12") != -1 or name.to_lower().find("question12") != -1:
		_setup_question_12()
	
	# Initialize selected buttons tracking for this scene
	selected_buttons.clear()
	
	# Restore previously selected button/buttons for this scene
	_restore_selected_buttons()
	
	print("Scene initialized: ", name)
	print("Total buttons found and connected")

func _enable_button_interaction() -> void:
	"""Ensure all buttons in the scene are interactive"""
	var button_count = 0
	for child in _get_all_descendants(self):
		var control: Control = child as Control
		if control != null:
			# Allow mouse events to pass through panels but stop at buttons
			if control is Button:
				control.mouse_filter = Control.MOUSE_FILTER_STOP
				control.focus_mode = Control.FOCUS_ALL
				control.disabled = false
				button_count += 1
				print("Enabled button: ", control.name, " with text: '", _get_button_text(control), "'")
			elif control is Panel or control is PanelContainer or control is Container:
				# Containers should pass mouse events through
				control.mouse_filter = Control.MOUSE_FILTER_PASS
			else:
				# Other controls pass through
				control.mouse_filter = Control.MOUSE_FILTER_PASS
	print("Total buttons enabled: ", button_count)

func _connect_navigation_button() -> void:
	var target_button: Button = _find_button_by_text(_resolve_button_text())
	if target_button != null:
		if not target_button.pressed.is_connected(_on_target_button_pressed):
			target_button.pressed.connect(_on_target_button_pressed)
	else:
		push_warning("Button with text '%s' not found in %s." % [_resolve_button_text(), name])

func _connect_answer_buttons() -> void:
	var connected_count = 0
	for child in _get_all_descendants(self):
		var button: Button = child as Button
		if button == null:
			continue
		if _is_navigation_button(button):
			continue
		
		# Get button text - could be in button.text or in a child label
		var txt := button.text.strip_edges()
		if txt.is_empty():
			# Try to get text from first child label
			for sub_child in button.get_children():
				if sub_child is Label:
					txt = sub_child.text.strip_edges()
					break
		
		if txt == "+" or txt == "-":
			continue
		var lower := txt.to_lower()
		if lower == "boy" or lower == "girl":
			# These are handled specially for question_12
			continue
		if txt == "Save" or txt == "Cancel" or txt == "OK" or txt == "Back" or txt == "Sent!":
			continue
		
		# Skip completely empty buttons
		if txt.is_empty():
			continue
		
		# Connect the button click signal
		if not button.pressed.is_connected(_on_answer_button_pressed):
			button.pressed.connect(_on_answer_button_pressed.bind(button))
			connected_count += 1
			print("Connected answer button: ", button.name, " with text: '", txt, "'")
		
		# Connect hover effects
		if not button.mouse_entered.is_connected(_on_button_mouse_entered):
			button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
		if not button.mouse_exited.is_connected(_on_button_mouse_exited):
			button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
	
	print("Total answer buttons connected: ", connected_count)

func _find_button_by_text(search_text: String) -> Button:
	"""Find a button by its text (checks button.text and child Labels)"""
	var target_text := search_text.strip_edges().to_lower()
	for child in _get_all_descendants(self):
		var button: Button = child as Button
		if button == null:
			continue
		var btn_text := _get_button_text(button).strip_edges().to_lower()
		if btn_text == target_text:
			return button
	return null

func _restore_selected_buttons() -> void:
	"""Restore previously selected button states for this scene"""
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	
	for child in _get_all_descendants(self):
		var button: Button = child as Button
		if button == null:
			continue
		if _is_navigation_button(button):
			continue
		
		var btn_text := _get_button_text(button).strip_edges()
		
		# Special handling for question_12 gender buttons
		if (name.to_lower().contains("question_12") or name.to_lower().contains("question12")):
			if btn_text.to_lower() in ["boy", "girl"]:
				var saved_gender = str(answers.get(name + "_gender", "")).strip_edges().to_lower()
				if saved_gender == btn_text.to_lower():
					button.modulate = Color(0.65, 1.0, 0.7, 1.0)
					button.self_modulate = Color.WHITE
					button.button_pressed = true
				else:
					button.modulate = Color(1, 1, 1, 1)
					button.self_modulate = Color.WHITE
					button.button_pressed = false
				continue
		
		var group_key := _get_scene_answer_key_for_button(button)
		if name.to_lower().contains("question_34") or name.to_lower().contains("question34"):
			var saved_answers: PackedStringArray = str(answers.get(group_key, "")).split(",", false)
			if btn_text in saved_answers:
				button.modulate = Color(0.65, 1.0, 0.7, 1.0)
				button.self_modulate = Color.WHITE
				continue
		
		# Check if this button was previously selected
		if answers.has(group_key) and str(answers[group_key]) == btn_text:
			button.modulate = Color(0.65, 1.0, 0.7, 1.0)
			button.self_modulate = Color.WHITE
		else:
			button.modulate = Color(1, 1, 1, 1)
			button.self_modulate = Color.WHITE

func _get_all_descendants(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_descendants(child))
	return result

func _get_button_text(button: Button) -> String:
	"""Helper to get button text from button or child label"""
	var txt = button.text.strip_edges()
	if txt.is_empty():
		for child in button.get_children():
			if child is Label:
				txt = child.text.strip_edges()
				break
	return txt

func _is_navigation_button(button: Button) -> bool:
	var label: String = _get_button_text(button).strip_edges().to_lower()
	return label == "continue" or label == "finish" or label == "cont" or label == "done"

func _on_answer_button_pressed(button: Button) -> void:
	# Get button text - could be in button.text or in a child label
	var answer: String = button.text.strip_edges()
	if answer.is_empty():
		# Try to get text from first child label
		for child in button.get_children():
			if child is Label:
				answer = child.text.strip_edges()
				break
	
	if answer.is_empty():
		print("WARNING: Button has no text: ", button.name)
		return
	
	print("Button clicked: ", answer, " in scene: ", name)

	# Handle "Other" button - redirect to popup_question.tscn
	if answer.to_lower() == "other":
		# store origin info so popup can return/save to this scene
		var root: Window = get_tree().root
		root.set_meta("popup_origin_scene", name)
		root.set_meta("popup_origin_choice", answer)
		_change_scene_to_file("res://popup_question.tscn")
		return

	if name.to_lower().contains("question_34") or name.to_lower().contains("question34"):
		_toggle_multi_select(button, answer)
		return

	# For all questions, use single select - only one button per question
	_record_answer_single_select(button, answer)

func _toggle_multi_select(button: Button, answer: String) -> void:
	"""Allow multiple selections (for question_34)"""
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	var group_key := _get_scene_answer_key_for_button(button)
	var selected_answers: PackedStringArray = str(answers.get(group_key, "")).split(",", false)
	var is_selected: bool = answer in selected_answers
	
	if is_selected:
		selected_answers.erase(answer)
		button.modulate = Color(1, 1, 1, 1)
		button.self_modulate = Color.WHITE
		print("Deselected: ", answer)
	else:
		selected_answers.append(answer)
		button.modulate = Color(0.65, 1.0, 0.7, 1.0)
		button.self_modulate = Color.WHITE
		print("Selected: ", answer, " - Color changed to green")
	
	if selected_answers.is_empty():
		answers.erase(group_key)
	else:
		answers[group_key] = ",".join(selected_answers)
	root.set_meta(ANSWER_STORE_KEY, answers)
	_save_current_answers_to_firebase()

func _record_answer_single_select(button: Button, answer: String) -> void:
	"""Single select - only one button per question"""
	var group_key: String = _get_scene_answer_key_for_button(button)
	for child in _get_all_descendants(self):
		var other_button: Button = child as Button
		if other_button == null or other_button == button:
			continue
		if _is_navigation_button(other_button):
			continue
		if _get_scene_answer_key_for_button(other_button) != group_key:
			continue
		
		var txt := _get_button_text(other_button)
		if txt == "+" or txt == "-":
			continue
		var lower := txt.to_lower()
		if lower == "boy" or lower == "girl":
			continue
		if txt == "Save" or txt == "Cancel" or txt == "OK" or txt == "Back" or txt == "Sent!":
			continue
		other_button.modulate = Color(1, 1, 1, 1)
		other_button.self_modulate = Color.WHITE
	
	button.modulate = Color(0.65, 1.0, 0.7, 1.0)
	button.self_modulate = Color.WHITE
	_store_single_select_answer(button, answer)
	print("Selected: ", answer, " in group: ", group_key)

func _store_single_select_answer(button: Button, answer: String) -> void:
	"""Store a single selected answer for one button group"""
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	answers[_get_scene_answer_key_for_button(button)] = answer
	root.set_meta(ANSWER_STORE_KEY, answers)
	_save_current_answers_to_firebase()

func _store_multi_select_answers() -> void:
	"""Store multiple selected answers"""
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	
	if selected_buttons.is_empty():
		answers.erase(name)
	else:
		var answer_list: PackedStringArray = PackedStringArray()
		for answer_key in selected_buttons.keys():
			answer_list.append(answer_key)
		answers[name] = ",".join(answer_list)
	
	root.set_meta(ANSWER_STORE_KEY, answers)
	_save_current_answers_to_firebase()

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
		# IMPORTANT: Save to /progress/{scene_name} not to timestamped entries
		# Questions should have one latest response, not historical entries
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
				for interest in val.split(",", false):
					interest = interest.strip_edges()
					if not interest.is_empty() and interest not in interests:
						interests.append(interest)
			elif key.contains("adventure_today"):
				var val = str(answers[key]).strip_edges()
				for interest in val.split(",", false):
					interest = interest.strip_edges()
					if not interest.is_empty() and interest not in interests:
						interests.append(interest)
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
	print("Continue button pressed. Scene: ", name)
	print("Current answers: ", answers)
	
	# Special handling for question_12 - needs age and gender
	if name.to_lower().contains("question_12") or name.to_lower().contains("question12"):
		var has_age := false
		var has_gender := false
		
		# Check if age was set (stored in answers[name + "_age"])
		if answers.has(name + "_age"):
			var age_val = str(answers[name + "_age"]).strip_edges()
			if age_val.is_valid_int() and int(age_val) > 0:
				has_age = true
			print("Age check: value=", age_val, " is_valid_int=", age_val.is_valid_int(), " > 0=", int(age_val) > 0)
		
		# Check if gender was selected (stored in answers[name + "_gender"])
		if answers.has(name + "_gender"):
			var gender_val = str(answers[name + "_gender"]).strip_edges()
			if gender_val.to_lower() in ["boy", "girl"]:
				has_gender = true
			print("Gender check: value=", gender_val, " is_valid=", gender_val.to_lower() in ["boy", "girl"])
		
		print("Question 12 validation: has_age=", has_age, " has_gender=", has_gender)
		
		if has_age and has_gender:
			_save_current_answers_to_firebase()
			_change_scene_to_file(_resolve_next_scene())
		else:
			_show_require_answer_alert()
		return
	
	if name.to_lower().contains("question_34") or name.to_lower().contains("question34"):
		var answered_count := 0
		for group_name in ["like_to_do", "adventure_today"]:
			var key := "%s_%s" % [name, group_name]
			if answers.has(key) and not str(answers[key]).strip_edges().is_empty():
				answered_count += 1
		if answered_count >= 2:
			_save_current_answers_to_firebase()
			_change_scene_to_file(_resolve_next_scene())
		else:
			_show_require_answer_alert()
		return
	
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
		return "res://moodcheck.tscn"
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
	print("Showing require answer alert for scene: ", name)
	if name.to_lower().contains("question_12") or name.to_lower().contains("question12"):
		var root: Window = get_tree().root
		var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
		var missing: Array[String] = []
		
		# Check age
		var age_val = str(answers.get(name + "_age", "0")).strip_edges()
		print("Age value: ", age_val, " answers dict: ", answers)
		if not age_val.is_valid_int() or int(age_val) <= 0:
			missing.append("Age (must be greater than 0)")
		
		# Check gender
		if not answers.has(name + "_gender"):
			missing.append("Gender (Boy or Girl)")
		
		var msg := "⚠️ PLEASE COMPLETE:\n\n"
		for m in missing:
			msg += "➤ " + m + "\n"
		msg += "\nThen click CONTINUE"
		
		print("Alert message: ", msg)
		_show_in_scene_alert(msg)
		return
	
	if name.to_lower().contains("question_34") or name.to_lower().contains("question34"):
		_show_in_scene_alert("Please choose one option for each question before finishing.")
		return
	# For all other questions, show generic alert
	_show_in_scene_alert("Please answer the question before continuing.")

func _show_in_scene_alert(message: String) -> void:
	print("Showing alert: ", message)
	var label_name := "__require_answer_label__"
	var req_label: Label = get_node_or_null(label_name) as Label
	if req_label == null:
		req_label = Label.new()
		req_label.name = label_name
		req_label.custom_minimum_size = Vector2(500, 120)
		var vw := 0.0
		if get_viewport() != null:
			vw = get_viewport().get_visible_rect().size.x
		req_label.position = Vector2(max(10, (vw - 500) / 2), 100)
		req_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		req_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		req_label.add_theme_constant_override("outline_size", 3)
		req_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		req_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD
		req_label.z_index = 1000
		add_child(req_label)
		print("Created alert label at position: ", req_label.position)
	
	req_label.text = message
	req_label.visible = true
	print("Alert label now visible with text: ", message)
	# hide after 4 seconds
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 4.0
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
		# Look for the age label - it should be between +/- buttons
		if age_label == null and child is Label:
			var txt = child.text.strip_edges()
			if txt.is_valid_int():  # Check if it's a number
				age_label = child
				print("Found age label with value: ", txt)
		
		if child is Button:
			var btn_text = _get_button_text(child as Button)
			print("Found button: ", btn_text)
			if btn_text == "+":
				plus_btn = child as Button
			elif btn_text == "-":
				minus_btn = child as Button
			elif btn_text.to_lower() == "boy":
				boy_btn = child as Button
			elif btn_text.to_lower() == "girl":
				girl_btn = child as Button

	print("Setup Question 12: age_label=", age_label != null, " plus=", plus_btn != null, " minus=", minus_btn != null, " boy=", boy_btn != null, " girl=", girl_btn != null)

	# Connect plus/minus handlers if age label and buttons found
	if age_label != null:
		if plus_btn != null and not plus_btn.pressed.is_connected(_on_plus_button_pressed):
			plus_btn.pressed.connect(_on_plus_button_pressed.bind(age_label))
			print("Connected plus button")
		if minus_btn != null and not minus_btn.pressed.is_connected(_on_minus_button_pressed):
			minus_btn.pressed.connect(_on_minus_button_pressed.bind(age_label))
			print("Connected minus button")

	# Connect gender buttons
	if boy_btn != null:
		if not boy_btn.pressed.is_connected(_on_gender_button_pressed):
			boy_btn.pressed.connect(_on_gender_button_pressed.bind(boy_btn, girl_btn))
			print("Connected boy button")
	
	if girl_btn != null:
		if not girl_btn.pressed.is_connected(_on_gender_button_pressed):
			girl_btn.pressed.connect(_on_gender_button_pressed.bind(girl_btn, boy_btn))
			print("Connected girl button")

func _on_plus_button_pressed(age_label: Label) -> void:
	var current_age: int = int(age_label.text)
	current_age += 1
	age_label.text = str(current_age)
	print("Age increased to: ", current_age)
	_save_question_12_age(current_age)

func _on_minus_button_pressed(age_label: Label) -> void:
	var current_age: int = int(age_label.text)
	if current_age > 0:
		current_age -= 1
	age_label.text = str(current_age)
	print("Age decreased to: ", current_age)
	_save_question_12_age(current_age)

func _save_question_12_age(age: int) -> void:
	"""Save age selection for question_12"""
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	answers[name + "_age"] = str(age)
	root.set_meta(ANSWER_STORE_KEY, answers)
	print("Age saved to key: ", name + "_age", " with value: ", str(age))
	print("Current answers after age save: ", answers)
	_save_current_answers_to_firebase()

func _on_gender_button_pressed(button: Button, other_button: Button) -> void:
	# Get the gender text
	var gender: String = _get_button_text(button).strip_edges().to_lower()
	print("Gender button pressed: ", gender)
	
	# Turn this button green and deselect the other
	button.modulate = Color(0.65, 1.0, 0.7, 1.0)
	button.self_modulate = Color.WHITE
	button.button_pressed = true
	
	if other_button != null:
		other_button.modulate = Color(1, 1, 1, 1)
		other_button.self_modulate = Color.WHITE
		other_button.button_pressed = false
	
	# Save the gender selection
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	answers[name + "_gender"] = gender
	root.set_meta(ANSWER_STORE_KEY, answers)
	print("Gender saved to key: ", name + "_gender", " with value: ", gender)
	print("Current answers: ", answers)
	
	# Also save to user profile for persistence
	_save_gender_to_profile(gender)
	
	_save_current_answers_to_firebase()

func _save_gender_to_profile(gender: String) -> void:
	"""Save gender to user profile for persistence across login/logout"""
	var user_id: String = _get_current_user_id()
	if user_id.is_empty() or user_id == "guest_user":
		print("question_nav: Cannot save gender - no valid user ID")
		return
	
	var firebase_manager: Variant = _resolve_firebase_manager()
	if firebase_manager != null and firebase_manager.has_method("save_profile_attributes"):
		var profile_update = {"gender": gender}
		firebase_manager.call("save_profile_attributes", user_id, profile_update)
		print("question_nav: Saved gender to profile: ", gender, " for user: ", user_id)
	else:
		print("question_nav: Cannot save gender - Firebase manager not available or missing method")

func _on_button_mouse_entered(button: Button) -> void:
	"""Add hover effect when mouse enters button"""
	# Store original color if not already selected
	if not button.has_meta("original_color"):
		button.set_meta("original_color", button.modulate)
	
	# Light up on hover
	var _current_color = button.modulate
	button.modulate = Color(1.2, 1.2, 1.2, 1.0).clamp()

func _on_button_mouse_exited(button: Button) -> void:
	"""Restore color when mouse leaves button"""
	# Check if button is selected (green) or not
	var answer: String = _get_button_text(button)
	var is_selected = false
	
	# For single-select, check the correct group metadata
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	var group_key := _get_scene_answer_key_for_button(button)
	if answers.has(group_key):
		is_selected = answer in str(answers[group_key]).split(",", false)
	
	if is_selected:
		button.modulate = Color(0.65, 1.0, 0.7, 1.0)
	else:
		button.modulate = Color(1, 1, 1, 1)

func _get_scene_answer_key_for_button(button: Button) -> String:
	if name.to_lower().contains("question_34") or name.to_lower().contains("question34"):
		# Use the scene hierarchy instead of screen coordinates; Android scaling can
		# move controls across a viewport threshold while their question group stays fixed.
		var ancestor: Node = button.get_parent()
		while ancestor != null and ancestor != self:
			if ancestor.name == "Panel3":
				return "%s_%s" % [name, "adventure_today"]
			ancestor = ancestor.get_parent()
		return "%s_%s" % [name, "like_to_do"]
	return name
