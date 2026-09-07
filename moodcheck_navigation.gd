extends Control

var _auth_manager: Node
var _session: Node
var _selected_button: Button = null
var _selected_mood: String = ""
var _continue_button: Button = null
var _original_button_styles: Dictionary = {}

func _ready() -> void:
	_auth_manager = _resolve_auth_manager()
	_session = _resolve_session()
	_continue_button = _find_button_by_text("Continue")
	if _continue_button != null:
		_continue_button.disabled = true
		_continue_button.pressed.connect(_on_continue_pressed)
	_wire_mood_buttons()
	_update_continue_state()

func _wire_mood_buttons() -> void:
	var buttons: Array[Button] = _collect_buttons()
	for button in buttons:
		if button == null:
			continue
		if button.text == "Continue":
			continue
		button.toggle_mode = true
		button.button_pressed = false
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		if not _original_button_styles.has(button):
			var original_style: StyleBox = button.get_theme_stylebox("normal")
			if original_style != null:
				_original_button_styles[button] = original_style.duplicate()
		_apply_selection_visual(button, false)
		var callback: Callable = Callable(self, "_on_mood_button_pressed").bind(button)
		if not button.pressed.is_connected(callback):
			button.pressed.connect(callback)

func _collect_buttons() -> Array[Button]:
	var results: Array[Button] = []
	var root_panel: Panel = get_node_or_null("Panel") as Panel
	if root_panel == null:
		return results
	for child in root_panel.get_children():
		if child is Button:
			results.append(child as Button)
	return results

func _find_button_by_text(target_text: String) -> Button:
	for child in get_children():
		var button: Button = _find_button_in_branch(child, target_text)
		if button != null:
			return button
	return null

func _find_button_in_branch(node: Node, target_text: String) -> Button:
	if node is Button:
		var button: Button = node as Button
		if button.text == target_text:
			return button
	for child in node.get_children():
		var nested: Button = _find_button_in_branch(child, target_text)
		if nested != null:
			return nested
	return null

func _on_mood_button_pressed(button: Button) -> void:
	var selected_now: bool = button.button_pressed
	if not selected_now:
		if _selected_button == button:
			_selected_button = null
			_selected_mood = ""
		_apply_selection_visual(button, false)
		_update_continue_state()
		return
	if _selected_button != null and _selected_button != button and is_instance_valid(_selected_button):
		_selected_button.button_pressed = false
		_apply_selection_visual(_selected_button, false)
	_selected_button = button
	_selected_mood = _mood_label_for(button)
	_apply_selection_visual(button, true)
	_update_continue_state()

func _check_today_mood_exists() -> void:
	"""Check if user already submitted mood today for daily validation"""
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = _session.get_current_user_id()
	if _auth_manager == null or not _auth_manager.has_method("get_todays_mood"):
		return
	_auth_manager.get_todays_mood(user_id, func(ok: bool, mood: Variant):
		var mood_str: String = str(mood).strip_edges()
		if ok and mood_str != "not_set" and not mood_str.is_empty():
			print("Mood already set today: ", mood_str)
			# Optionally show message that mood was already tracked
			_show_mood_info("You already checked in your mood today! Current mood: " + mood_str)
	)

func _apply_selection_visual(button: Button, selected: bool) -> void:
	if button == null:
		return
	if selected:
		var selected_style: StyleBox = _build_selected_button_style(button)
		button.add_theme_stylebox_override("normal", selected_style)
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("hover", selected_style)
	else:
		var default_style: StyleBox = _original_button_styles.get(button)
		if default_style != null:
			button.add_theme_stylebox_override("normal", default_style)
			button.add_theme_stylebox_override("pressed", default_style)
			button.add_theme_stylebox_override("hover", default_style)
	button.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _build_selected_button_style(button: Button) -> StyleBox:
	var default_style: StyleBox = _original_button_styles.get(button)
	if default_style == null:
		default_style = button.get_theme_stylebox("normal")
	if default_style == null:
		var fallback: StyleBoxFlat = StyleBoxFlat.new()
		fallback.bg_color = Color(0.98, 0.96, 0.92, 1.0)
		fallback.corner_radius_top_left = 18
		fallback.corner_radius_top_right = 18
		fallback.corner_radius_bottom_left = 18
		fallback.corner_radius_bottom_right = 18
		fallback.border_width_left = 4
		fallback.border_width_right = 4
		fallback.border_width_top = 4
		fallback.border_width_bottom = 4
		fallback.border_color = Color(1.0, 0.70, 0.18, 1.0)
		return fallback
	var selected_style: StyleBox = default_style.duplicate()
	if selected_style is StyleBoxFlat:
		var flat_style: StyleBoxFlat = selected_style as StyleBoxFlat
		flat_style.border_width_left = 4
		flat_style.border_width_right = 4
		flat_style.border_width_top = 4
		flat_style.border_width_bottom = 4
		flat_style.border_color = Color(1.0, 0.70, 0.18, 1.0)
		flat_style.bg_color = flat_style.bg_color.lightened(0.08)
	return selected_style

func _mood_label_for(button: Button) -> String:
	var label: Label = _first_label_under(button)
	if label != null and not label.text.strip_edges().is_empty():
		return label.text.strip_edges()
	if button.text.strip_edges().is_empty():
		return button.name.strip_edges()
	return button.text.strip_edges()

func _first_label_under(node: Node) -> Label:
	if node is Label:
		return node as Label
	for child in node.get_children():
		var nested: Label = _first_label_under(child)
		if nested != null:
			return nested
	return null

func _update_continue_state() -> void:
	if _continue_button == null:
		return
	_continue_button.disabled = _selected_mood.is_empty()

func _on_continue_pressed() -> void:
	if _selected_mood.is_empty():
		push_warning("Please select a mood before continuing.")
		return
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = _session.get_current_user_id()
	
	var current_date: String = Time.get_datetime_string_from_system(false, false).substr(0, 10)
	var mood_payload: Dictionary = {
		"scene": "moodcheck",
		"mood": _selected_mood,
		"selected_at": Time.get_datetime_string_from_system(false, true),
		"date": current_date,  # Add date for validation
		"user_id": user_id,
		"authenticated": _session != null and _session.has_method("is_authenticated") and _session.is_authenticated()
	}
	
	if _auth_manager != null:
		if _auth_manager.has_method("save_moodcheck_entry"):
			_auth_manager.save_moodcheck_entry(user_id, mood_payload, func(ok, body):
				# Re-check that auth_manager is still valid
				if _auth_manager == null or not is_instance_valid(_auth_manager):
					print("Auth manager was freed after mood save callback")
					return
				if ok:
					print("Mood check history saved to Firebase: ", _selected_mood)
					# Reward experience for mood check - with extra safety checks
					if _auth_manager.has_method("add_experience") and is_instance_valid(_auth_manager):
						_auth_manager.add_experience(user_id, 10, func(_ok, _exp):
							# Final safety check before accepting callback
							if is_instance_valid(self):
								print("Mood check reward: +10 EXP")
						)
				else:
					print("Mood check save failed: ", body)
			)
		elif _auth_manager.has_method("save_progress"):
			_auth_manager.save_progress(user_id, mood_payload, func(ok, body):
				if ok:
					print("Mood check saved to Firebase")
				else:
					print("Mood check save failed: ", body)
			)
		else:
			push_warning("FirebaseAuthManager has no mood save method.")
	else:
		push_warning("FirebaseAuthManager is unavailable for mood save.")
	_change_scene_to_file("res://home.tscn")

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

func _show_mood_info(message: String) -> void:
	"""Display info message about mood status"""
	var info_label: Label = get_node_or_null("InfoLabel") as Label
	if info_label == null:
		info_label = get_node_or_null("Panel/InfoLabel") as Label
	if info_label != null:
		info_label.text = message
		# Auto-clear after 5 seconds
		_schedule_clear_info.call_deferred(info_label)

func _schedule_clear_info(info_label: Label) -> void:
	"""Deferred function to clear info after timeout"""
	await get_tree().create_timer(5.0).timeout
	if info_label != null and is_instance_valid(info_label):
		info_label.text = ""

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
