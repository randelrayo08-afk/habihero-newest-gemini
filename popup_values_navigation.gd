extends Control
# Popup Values Navigation - Manages values reflection popup functionality

var _auth_manager: Node
var _session: Node
var _current_user_id: String = ""
var _text_edit: TextEdit
var _submit_button: Button
var _cancel_button: Button
var _character_count_label: Label
const MAX_CHARACTERS: int = 250

func _ready() -> void:
	_auth_manager = _resolve_auth_manager()
	_session = _resolve_session()
	_current_user_id = _get_current_user_id()
	
	# Find UI elements
	_text_edit = get_node_or_null("Panel5/TextEdit")
	_submit_button = get_node_or_null("Panel5/Button")
	_cancel_button = get_node_or_null("Panel5/Button2")
	_character_count_label = get_node_or_null("Panel5/TextEdit/Label")
	
	# Connect signals
	if _submit_button != null:
		_submit_button.pressed.connect(_on_submit_button_pressed)
		print("Popup Values: Submit button connected")
	else:
		print("Popup Values: Submit button not found")
	
	if _cancel_button != null:
		_cancel_button.pressed.connect(_on_cancel_button_pressed)
		print("Popup Values: Cancel button connected")
	else:
		print("Popup Values: Cancel button not found")
	
	if _text_edit != null:
		_text_edit.text_changed.connect(_on_text_changed)
		print("Popup Values: TextEdit connected")
	else:
		print("Popup Values: TextEdit not found")
	
	# Update character count
	_update_character_count()

func _resolve_auth_manager() -> Node:
	if get_tree() != null and get_tree().root != null:
		var manager: Node = get_tree().root.get_node_or_null("FirebaseAuthManager")
		if manager != null:
			return manager
	if Engine.has_singleton("FirebaseAuthManager"):
		return Engine.get_singleton("FirebaseAuthManager")
	return null

func _resolve_session() -> Node:
	if get_tree() != null and get_tree().root != null:
		var session: Node = get_tree().root.get_node_or_null("UserSession")
		if session != null:
			return session
	if Engine.has_singleton("UserSession"):
		return Engine.get_singleton("UserSession")
	return null

func _get_current_user_id() -> String:
	if _session != null and _session.has_method("get_current_user_id"):
		var uid: String = str(_session.call("get_current_user_id")).strip_edges()
		if not uid.is_empty():
			return uid
	return "guest_user"

func _on_text_changed() -> void:
	"""Handle text input changes"""
	_update_character_count()

func _update_character_count() -> void:
	"""Update the character count label"""
	if _text_edit == null or _character_count_label == null:
		return
	
	var current_length: int = _text_edit.text.length()
	_character_count_label.text = "%d/%d" % [current_length, MAX_CHARACTERS]
	
	# Change color if approaching limit
	if current_length >= MAX_CHARACTERS:
		_character_count_label.modulate = Color(1, 0, 0, 1)  # Red when at limit
	elif current_length >= MAX_CHARACTERS * 0.9:
		_character_count_label.modulate = Color(1, 0.5, 0, 1)  # Orange when near limit
	else:
		_character_count_label.modulate = Color(0.4, 0.4, 0.4, 1)  # Gray normally

func _on_submit_button_pressed() -> void:
	"""Handle reflection submission"""
	if _text_edit == null:
		print("Popup Values: TextEdit not found")
		return
	
	var reflection_text: String = _text_edit.text.strip_edges()
	
	if reflection_text.is_empty():
		_show_message("Please enter your reflection first.")
		return
	
	if reflection_text.length() > MAX_CHARACTERS:
		_show_message("Reflection is too long. Maximum %d characters." % MAX_CHARACTERS)
		return
	
	print("Popup Values: Submitting reflection for user: ", _current_user_id)
	
	# Save reflection to Firebase
	_save_reflection_to_firebase(reflection_text)

func _save_reflection_to_firebase(reflection_text: String) -> void:
	"""Save reflection to Firebase under values/liturgical"""
	if _auth_manager == null:
		_show_message("Unable to save: Firebase not available")
		return
	
	var reflection_data: Dictionary = {
		"reflection": reflection_text,
		"type": "values_reflection",
		"scene": "values",
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"character_count": reflection_text.length()
	}
	
	if _auth_manager.has_method("save_scene_input"):
		_auth_manager.save_scene_input(_current_user_id, "values", reflection_data, func(ok: bool, body: Variant):
			if ok:
				print("Popup Values: Reflection saved successfully")
				_show_message("Reflection saved successfully!")
				# Navigate back to values scene after short delay
				await get_tree().create_timer(1.5).timeout
				_navigate_back_to_values()
			else:
				print("Popup Values: Failed to save reflection: ", body)
				_show_message("Failed to save reflection. Please try again.")
		)
	else:
		# Fallback: just navigate back
		print("Popup Values: save_scene_input method not available, navigating back")
		_navigate_back_to_values()

func _on_cancel_button_pressed() -> void:
	"""Handle cancel button - navigate back without saving"""
	print("Popup Values: Cancel button pressed")
	_navigate_back_to_values()

func _navigate_back_to_values() -> void:
	"""Navigate back to the main values scene"""
	get_tree().change_scene_to_file("res://values.tscn")

func _show_message(message: String) -> void:
	"""Show a temporary message to the user"""
	print("Popup Values: ", message)
	# You could implement a toast notification here
	# For now, it just prints to console