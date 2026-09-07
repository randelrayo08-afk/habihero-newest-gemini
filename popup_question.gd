extends Control

const MAX_CHARS = 75
var text_edit: TextEdit
var char_counter_label: Label
var submit_button: Button
var close_button: Button

func _ready() -> void:
	# Find all necessary nodes
	text_edit = find_child("TextEdit", true, false) as TextEdit
	submit_button = find_child("Button", true, false) as Button  # SUBMIT button
	close_button = find_child("Button2", true, false) as Button  # X close button
	
	# Find the character counter label inside TextEdit
	if text_edit != null:
		for child in text_edit.get_children():
			if child is Label:
				char_counter_label = child as Label
				break
	
	# Initial setup
	if char_counter_label != null:
		char_counter_label.text = "0/%d" % MAX_CHARS
	
	# Connect signals
	if text_edit != null:
		text_edit.text_changed.connect(_on_text_changed)
		# Intercept key input to prevent adding more characters when at limit
		if not text_edit.gui_input.is_connected(Callable(self, "_on_text_gui_input")):
			text_edit.gui_input.connect(Callable(self, "_on_text_gui_input"))
		# Set max length
		text_edit.custom_minimum_size = Vector2(324, 116)
	
	if submit_button != null:
		submit_button.pressed.connect(_on_submit_pressed)
		submit_button.disabled = true  # Disabled by default (no text)
	
	if close_button != null:
		close_button.pressed.connect(_on_close_pressed)
	
	print("Popup question script initialized")

func _on_text_changed() -> void:
	"""Update character counter and validate submit button"""
	if text_edit == null:
		return
	
	var current_text = text_edit.text
	var char_count = current_text.length()
	
	# Update counter label
	if char_counter_label != null:
		char_counter_label.text = "%d/%d" % [char_count, MAX_CHARS]
	
	# Limit text to max characters
	if char_count > MAX_CHARS:
		# Truncate and move cursor to the end so user doesn't keep typing beyond limit
		text_edit.text = current_text.substr(0, MAX_CHARS)
		# ensure the text property is updated immediately
		current_text = text_edit.text
		char_count = current_text.length()
		if char_counter_label != null:
			char_counter_label.text = "%d/%d" % [char_count, MAX_CHARS]
		# place cursor at the end
		var last_line := current_text.get_slice("\n", -1)
		var col := last_line.length()
		text_edit.cursor_set_line(current_text.get_slice_count("\n") - 1)
		text_edit.cursor_set_column(col)
	
	# Enable/disable submit button based on text
	# Use the possibly-updated text for submit enabling
	if submit_button != null:
		var trimmed := current_text.strip_edges()
		submit_button.disabled = trimmed.is_empty()
		# also ensure counter shows correct value
		if char_counter_label != null:
			char_counter_label.text = "%d/%d" % [char_count, MAX_CHARS]

	# If at max, prevent accepting further printable key input via gui_input handler
	# (handler will mark input handled when appropriate)

func _on_submit_pressed() -> void:
	"""Handle submit button - save answer and go back"""
	if text_edit == null or text_edit.text.strip_edges().is_empty():
		print("Cannot submit - no text entered")
		return

	var answer = text_edit.text.strip_edges()
	print("Submitted answer: ", answer)

	var root: Window = get_tree().root
	const ANSWER_STORE_KEY := "question_answers"
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})

	var origin_scene: String = ""
	var origin_choice: String = "Other"
	if root.has_meta("popup_origin_scene"):
		origin_scene = str(root.get_meta("popup_origin_scene"))
	if root.has_meta("popup_origin_choice"):
		origin_choice = str(root.get_meta("popup_origin_choice"))

	if origin_scene != "":
		answers[origin_scene] = origin_choice
		answers[origin_scene + "_other_text"] = answer
	else:
		answers["other_answer"] = answer

	root.set_meta(ANSWER_STORE_KEY, answers)
	_save_answers_to_firebase(root, answers)

	root.set_meta("popup_origin_scene", null)
	root.set_meta("popup_origin_choice", null)
	_go_back()

func _save_answers_to_firebase(root: Window, answers: Dictionary) -> void:
	if answers.is_empty():
		return

	var user_id: String = _get_current_user_id()
	if user_id.is_empty():
		user_id = "guest_user"

	var auth_manager: Variant = _resolve_firebase_manager()
	if auth_manager != null and auth_manager.has_method("save_scene_input"):
		auth_manager.call("save_scene_input", user_id, "popup_question", {
			"answers": answers.duplicate(true),
			"saved_at": Time.get_datetime_string_from_system(false, true),
		})
		return

	var db: Node = root.get_node_or_null("FirebaseRTDB")
	if db == null and Engine.has_singleton("FirebaseRTDB"):
		db = Engine.get_singleton("FirebaseRTDB")
	if db != null and db.has_method("write_json"):
		db.call("write_json", "users/%s/popup_question" % _safe_firebase_key(user_id), {
			"answers": answers.duplicate(true),
			"saved_at": Time.get_datetime_string_from_system(false, true),
		})

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

func _on_close_pressed() -> void:
	"""Handle close button - go back without saving"""
	print("Close button pressed - going back")
	_go_back()


func _on_text_gui_input(event: InputEvent) -> void:
	# Prevent additional printable characters when at MAX_CHARS
	if text_edit == null:
		return
	if not (event is InputEventKey):
		return
	var ek := event as InputEventKey
	# only intercept actual key presses (not releases) and not echoes
	if not ek.pressed or ek.echo:
		return
	# allow control keys (backspace, delete, arrows, ctrl/meta combos)
	if ek.control or ek.shift or ek.meta or ek.alt:
		return
	# unicode > 0 indicates a printable character in many cases
	if ek.unicode != 0:
		if text_edit.text.length() >= MAX_CHARS:
			get_tree().set_input_as_handled()

func _go_back() -> void:
	"""Navigate back to the previous scene"""
	# If we came from question_34, go back there
	var root: Window = get_tree().root
	var origin_scene: String = ""
	if root.has_meta("popup_origin_scene") and root.get_meta("popup_origin_scene") != null:
		origin_scene = str(root.get_meta("popup_origin_scene"))
	if origin_scene != "":
		var path := "res://%s.tscn" % origin_scene
		# attempt to change back to the originating scene file
		if ResourceLoader.exists(path):
			get_tree().change_scene_to_file(path)
			return
	# fallback
	get_tree().change_scene_to_file("res://question_34.tscn")
