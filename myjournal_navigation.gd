extends Control

var _auth_manager: Node
var _session: Node
var _is_saving: bool = false

func _ready() -> void:
	print("=== MyJournal Scene Initializing ===")
	_auth_manager = _resolve_auth_manager()
	_session = _resolve_session()
	
	print("Auth Manager: ", _auth_manager)
	print("Session: ", _session)
	
	_ensure_entry_editor()
	_load_saved_entries()

	# Connect close button
	var close_button: Button = _find_button_by_text("CLOSE")
	if close_button != null:
		if not close_button.pressed.is_connected(Callable(self, "_go_back")):
			close_button.pressed.connect(_go_back)
		print("✓ Close button connected successfully")
	else:
		push_warning("Close button not found in My Journal scene.")

	# Connect save button - try multiple ways
	var save_button: Button = _find_button_by_text("SAVE")
	if save_button != null:
		if not save_button.pressed.is_connected(Callable(self, "_save_entry")):
			save_button.pressed.connect(_save_entry)
		print("✓ Save button connected by text match: ", save_button.name)
	else:
		# Try to find button by node path
		save_button = get_node_or_null("Panel2/Button") as Button
		if save_button != null:
			if not save_button.pressed.is_connected(Callable(self, "_save_entry")):
				save_button.pressed.connect(_save_entry)
			print("✓ Save button found by node path: Panel2/Button")
		else:
			push_error("✗ Save button not found - save functionality unavailable")
			push_error("Searched for text='SAVE' and node path='Panel2/Button'")


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

func _go_back() -> void:
	var previous_scene: String = _previous_scene_from_history()
	if previous_scene.is_empty():
		previous_scene = "res://journal.tscn"
	_change_scene_to_file(previous_scene)

func _previous_scene_from_history() -> String:
	var history: Node = _resolve_history()
	if history != null and history.has_method("get_previous_scene"):
		return history.get_previous_scene()
	return ""

func _resolve_history() -> Node:
	if get_tree() != null and get_tree().root != null:
		var history: Node = get_tree().root.get_node_or_null("NavigationHistory")
		if history != null:
			return history
	if Engine.has_singleton("NavigationHistory"):
		return Engine.get_singleton("NavigationHistory")
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

func _save_entry() -> void:
	if _is_saving:
		print("Already saving, please wait...")
		return
	
	print("\n=== SAVE ENTRY INITIATED ===")
	
	if _auth_manager == null:
		push_warning("FirebaseAuthManager is not available")
		_show_save_error("Journal system not ready. Please refresh the page.")
		return
	
	var text_entry: String = _find_entry_text()
	if text_entry.strip_edges().is_empty():
		_show_save_error("Please write something in your journal")
		return
	
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = _session.get_current_user_id()
		print("User ID from session: ", user_id)
	else:
		print("No session, using guest_user")
	
	print("Entry text length: ", text_entry.length())
	print("Max length: 300")
	
	# Show saving state
	var editor: TextEdit = _get_entry_text_edit()
	if editor != null:
		editor.editable = false
	
	_is_saving = true
	_show_save_error("Saving...")
	
	print("Calling _auth_manager.save_journal_entry()")
	_auth_manager.save_journal_entry(user_id, text_entry, func(ok, body):
		_is_saving = false
		
		# Re-enable editor
		if editor != null:
			editor.editable = true
		
		print("Save callback executed:")
		print("  Success: ", ok)
		print("  Response: ", body)
		
		if ok:
			print("✓ Journal entry saved successfully!")
			_show_save_error("✓ Entry saved!")
			# Clear the input field after successful save
			if editor != null:
				editor.text = ""
				_update_char_count(editor)
			# Reload journals to show the just-saved entry
			await get_tree().process_frame
			_load_saved_entries()
		else:
			print("✗ Journal save failed")
			var error_msg: String = "Failed to save entry"
			if body is Dictionary and body.has("error"):
				error_msg = str(body.get("error"))
			elif body is String:
				error_msg = body
			elif body != null:
				error_msg = str(body)
			print("Error message: ", error_msg)
			_show_save_error("✗ Error: " + error_msg)
	)

func _find_entry_text() -> String:
	var text_box: TextEdit = get_node_or_null("EntryTextEdit") as TextEdit
	if text_box == null:
		text_box = get_node_or_null("Panel3/EntryTextEdit") as TextEdit
	if text_box == null:
		text_box = get_node_or_null("Panel2/EntryTextEdit") as TextEdit
	if text_box == null:
		text_box = get_node_or_null("Panel2/TextEdit") as TextEdit
	if text_box != null:
		return text_box.text
	return ""

func _load_saved_entries() -> void:
	if _auth_manager == null or not _auth_manager.has_method("load_journal_entries"):
		_show_journal_entries({})
		return
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = _session.get_current_user_id()
	_auth_manager.load_journal_entries(user_id, func(ok, body):
		if ok and body is Dictionary:
			_show_journal_entries(body)
		else:
			_show_journal_entries({})
	)

func _ensure_entry_editor() -> void:
	var existing: TextEdit = _get_entry_text_edit()
	if existing != null:
		_setup_entry_editor(existing)
		return
	var container: Control = get_node_or_null("Panel3") as Control
	if container == null:
		container = get_node_or_null("Panel2") as Control
	if container == null:
		container = self
	var editor: TextEdit = TextEdit.new()
	editor.name = "EntryTextEdit"
	editor.placeholder_text = "Write how you’re feeling today..."
	editor.custom_minimum_size = Vector2(320, 180)
	container.add_child(editor)
	_setup_entry_editor(editor)

func _get_entry_text_edit() -> TextEdit:
	var text_box: TextEdit = get_node_or_null("EntryTextEdit") as TextEdit
	if text_box == null:
		text_box = get_node_or_null("Panel3/EntryTextEdit") as TextEdit
	if text_box == null:
		text_box = get_node_or_null("Panel2/EntryTextEdit") as TextEdit
	if text_box == null:
		text_box = get_node_or_null("Panel2/TextEdit") as TextEdit
	return text_box

func _setup_entry_editor(editor: TextEdit) -> void:
	editor.placeholder_text = "Write how you’re feeling today..."
	editor.text = editor.text.strip_edges()
	editor.editable = true
	editor.custom_minimum_size = Vector2(320, 180)
	_style_entry_editor(editor)
	var callback: Callable = Callable(self, "_on_entry_text_changed")
	if not editor.is_connected("text_changed", callback):
		editor.text_changed.connect(callback)
	_update_char_count(editor)

func _on_entry_text_changed() -> void:
	var editor: TextEdit = _get_entry_text_edit()
	if editor == null:
		return
	if editor.text.length() > 300:
		editor.text = editor.text.substr(0, 300)
		editor.caret_column = 300
	_update_char_count(editor)

func _update_char_count(editor: TextEdit) -> void:
	var label: Label = get_node_or_null("Label2") as Label
	if label == null:
		label = get_node_or_null("Panel3/Label2") as Label
	if label == null:
		label = get_node_or_null("Panel2/Label2") as Label
	if label == null:
		return
	label.text = "%d/300" % editor.text.length()

func _style_entry_editor(editor: TextEdit) -> void:
	editor.add_theme_color_override("font_color", Color(0.16, 0.10, 0.03, 1.0))
	editor.add_theme_color_override("font_readonly_color", Color(0.16, 0.10, 0.03, 1.0))
	editor.add_theme_color_override("selection_color", Color(0.68, 0.82, 0.96, 0.35))
	editor.add_theme_color_override("caret_color", Color(0.16, 0.10, 0.03, 1.0))
	editor.add_theme_color_override("background_color", Color(0.0, 0.0, 0.0, 0.0))
	editor.add_theme_color_override("placeholder_color", Color(0.55, 0.42, 0.24, 1.0))
	var empty_box: StyleBoxEmpty = StyleBoxEmpty.new()
	editor.add_theme_stylebox_override("normal", empty_box)
	editor.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _show_journal_entries(entries_body: Dictionary) -> void:
	var label: Label = get_node_or_null("Panel3/EntriesLabel") as Label
	if label == null:
		label = get_node_or_null("EntriesLabel") as Label
	if label == null:
		return
	var lines: PackedStringArray = []
	if entries_body.is_empty():
		lines.append("No journal entries yet.")
	else:
		var entry_keys: Array = entries_body.keys()
		entry_keys.sort_custom(func(a, b): return str(a) > str(b))  # Sort descending (newest first)
		var max_entries: int = 10  # Show only last 10 entries
		for i in range(min(entry_keys.size(), max_entries)):
			var key = entry_keys[i]
			var item: Variant = entries_body.get(key)
			if item is Dictionary:
				var entry_text: String = str(item.get("entry", "")).strip_edges()
				var created_at: String = str(item.get("created_at", "")).strip_edges()
				if entry_text.is_empty():
					continue
				if not created_at.is_empty():
					lines.append("[" + created_at + "]\n" + entry_text)
				else:
					lines.append(entry_text)
		if lines.is_empty():
			lines.append("No journal entries yet.")
	label.text = "\n---\n".join(lines)

func _show_save_error(message: String) -> void:
	"""Display error message to user"""
	var error_label: Label = get_node_or_null("ErrorLabel") as Label
	if error_label == null:
		error_label = get_node_or_null("Panel3/ErrorLabel") as Label
	if error_label == null:
		error_label = get_node_or_null("Panel2/ErrorLabel") as Label
	if error_label != null:
		error_label.text = message
		# Auto-clear error after 3 seconds
		_schedule_clear_error.call_deferred(error_label)

func _schedule_clear_error(error_label: Label) -> void:
	"""Deferred function to clear error after timeout"""
	await get_tree().create_timer(3.0).timeout
	if error_label != null and is_instance_valid(error_label):
		error_label.text = ""

func _resolve_auth_manager() -> Node:
	var auth_manager: Node = null
	
	# Try tree root first
	if get_tree() != null and get_tree().root != null:
		auth_manager = get_tree().root.get_node_or_null("FirebaseAuthManager")
		if auth_manager != null:
			print("✓ Found FirebaseAuthManager in tree root")
			return auth_manager
	
	# Try singleton
	if Engine.has_singleton("FirebaseAuthManager"):
		auth_manager = Engine.get_singleton("FirebaseAuthManager")
		if auth_manager != null:
			print("✓ Found FirebaseAuthManager as singleton")
			return auth_manager
	
	push_error("✗ FirebaseAuthManager not found in tree or as singleton")
	return null

func _resolve_session() -> Node:
	if get_tree() != null and get_tree().root != null:
		var session: Node = get_tree().root.get_node_or_null("UserSession")
		if session != null:
			return session
	if Engine.has_singleton("UserSession"):
		return Engine.get_singleton("UserSession")
	return null
