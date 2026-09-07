extends Control

func _ready() -> void:
	var back_button: Button = _find_button_by_text("Back")
	if back_button != null:
		back_button.pressed.connect(_on_back_pressed)
	else:
		push_warning("Back button not found in forgot password scene.")

	var send_button: Button = _find_button_by_text("Send Reset Link")
	if send_button != null:
		send_button.pressed.connect(_on_send_reset_link_pressed)
	else:
		push_warning("Send Reset Link button not found in forgot password scene.")

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

func _on_back_pressed() -> void:
	_change_scene_to_file("res://login.tscn")

func _on_send_reset_link_pressed() -> void:
	var email_edit: LineEdit = get_node_or_null("InputContainer/VBoxContainer/LineEdit") as LineEdit
	var email: String = (email_edit.text if email_edit != null else "").strip_edges()
	if email.is_empty():
		_show_alert("Please enter your email address so we can send a reset link.", true)
		return
	if not email.contains("@") or not email.contains("."):
		_show_alert("Please enter a valid email address.", true)
		return

	var info_label: Label = get_node_or_null("Label2") as Label
	if info_label != null:
		info_label.text = "Reset link sent to %s" % email

	var send_button: Button = _find_button_by_text("Send Reset Link")
	if send_button != null:
		send_button.text = "Sent!"

	_show_alert("A password reset link has been sent to %s." % email, false)
	print("Password reset requested for: %s" % email)

func _show_alert(message: String, is_error: bool) -> void:
	var label: Label = get_node_or_null("AlertLabel") as Label
	if label == null:
		return
	label.visible = true
	label.text = message
	label.modulate = Color(0.9, 0.15, 0.15, 1.0) if is_error else Color(0.1, 0.7, 0.2, 1.0)

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
