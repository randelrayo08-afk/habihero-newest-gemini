extends Control

const MAX_CHARS: int = 250
@onready var text_edit: TextEdit = $Panel5/TextEdit
@onready var label_char: Label = $Panel5/TextEdit/labelChar
@onready var submit_button: Button = $Panel5/Button
var _previous_text: String = ""

func _ready() -> void:
	if text_edit != null:
		_previous_text = str(text_edit.text)
		if not text_edit.text_changed.is_connected(Callable(self, "_on_text_changed")):
			text_edit.text_changed.connect(Callable(self, "_on_text_changed"))
	if submit_button != null:
		if not submit_button.pressed.is_connected(Callable(self, "_on_submit_pressed")):
			submit_button.pressed.connect(Callable(self, "_on_submit_pressed"))
	_update_char_label()

func _on_text_changed() -> void:
	if text_edit == null:
		return
	var s: String = str(text_edit.text)
	
	# Block input if over 250 chars
	if s.length() > MAX_CHARS:
		text_edit.text = _previous_text
		_update_char_label()
		return
	
	# Apply word wrapping: insert newlines when line gets too long
	s = _apply_word_wrapping(s)
	
	if s != text_edit.text:
		text_edit.text = s
	
	# Update previous only when inside limit
	_previous_text = s
	_update_char_label()

func _apply_word_wrapping(text: String) -> String:
	# Wrap text to next line after ~30 chars per line
	var max_chars_per_line: int = 35
	var lines: Array = text.split("\n")
	var result: Array = []
	
	for line in lines:
		var wrapped_line: String = ""
		var words: Array = line.split(" ")
		
		for i in range(words.size()):
			var word: String = words[i]
			var test_line: String = wrapped_line
			
			if wrapped_line.length() > 0:
				test_line += " " + word
			else:
				test_line = word
			
			# If adding this word would exceed limit, wrap to next line
			if test_line.length() > max_chars_per_line and wrapped_line.length() > 0:
				result.append(wrapped_line)
				wrapped_line = word
			else:
				wrapped_line = test_line
		
		if wrapped_line.length() > 0:
			result.append(wrapped_line)
	
	return "\n".join(result)

func _update_char_label() -> void:
	if label_char == null or text_edit == null:
		return
	var count: int = text_edit.text.length()
	label_char.text = "%d/%d" % [count, MAX_CHARS]

func _on_submit_pressed() -> void:
	if text_edit == null:
		return
	var content: String = str(text_edit.text).strip_edges()
	if content == "":
		print("Please enter a reflection before submitting.")
		return
	var user_id: String = _get_current_user_id()
	var fam: Node = null
	if Engine.has_singleton("FirebaseAuthManager"):
		fam = Engine.get_singleton("FirebaseAuthManager")
	if fam != null and fam.has_method("save_scene_input"):
		var payload: Dictionary = {"reflection": content, "type": "liturgical_reflection", "scene": "liturgical"}
		fam.save_scene_input(user_id, "liturgical", payload, Callable(self, "_on_reflection_saved"))
	else:
		print("FirebaseAuthManager unavailable; saving locally")
		_on_reflection_saved(true, {"reflection": content})

func _on_reflection_saved(ok: bool, body: Variant) -> void:
	if ok:
		print("Reflection saved successfully")
		# go back to spiritual scene
		var tree: SceneTree = get_tree()
		if tree != null:
			tree.change_scene_to_file("res://spiritual.tscn")
	else:
		print("Failed to save reflection:", body)

func _get_current_user_id() -> String:
	var session = get_tree().root.get_node_or_null("UserSession")
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	if session != null and session.has_method("get_current_user_id"):
		return str(session.call("get_current_user_id"))
	# Fallback to FirebaseAuthManager
	if Engine.has_singleton("FirebaseAuthManager"):
		var auth = Engine.get_singleton("FirebaseAuthManager")
		if auth != null and auth.has_method("get_current_user"):
			var user = auth.call("get_current_user")
			if user is Dictionary and user.has("uid"):
				return str(user["uid"]).strip_edges()
	return "guest_user"
