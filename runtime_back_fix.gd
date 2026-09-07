extends Node

# Autoload helper: ensure Edit Profile back button always connects to settings
func _ready() -> void:
	call_deferred("_attach_back_handler")

func _attach_back_handler() -> void:
	var root = get_tree().root
	if root == null:
		print("runtime_back_fix: no root")
		return
	var edit = root.get_node_or_null("editProfile")
	if edit == null:
		# try common names
		edit = root.get_node_or_null("EditProfile")
	if edit == null:
		print("runtime_back_fix: editProfile node not found at root")
		return
	# find top-left button
	var back_button: Button = edit.get_node_or_null("Button") as Button
	if back_button == null:
		back_button = edit.get_node_or_null("Button/Button") as Button
	if back_button == null:
		print("runtime_back_fix: back button not found under editProfile")
		return
	print("runtime_back_fix: found back button -> %s" % back_button.get_path())
	# Print diagnostics about the back button
	print("  visible=", back_button.visible, " disabled=", back_button.disabled, " mouse_filter=", back_button.mouse_filter)
	if back_button.get_script() != null:
		print("  script=", str(back_button.get_script().resource_path))
	else:
		print("  script= (none)")
	print("  pressed connected=", back_button.is_connected("pressed", Callable(self, "_on_back_pressed")))

	# Inspect top-level children for overlap
	var bpos: Vector2 = back_button.get_global_position()
	var brect: Rect2 = Rect2(bpos, back_button.size)
	print("runtime_back_fix: scanning top-level children for overlaps...")
	for child in root.get_children():
		if not (child is Control):
			continue
		var ctrl: Control = child as Control
		var rect = Rect2(ctrl.get_global_position(), ctrl.size)
		if rect.intersects(brect):
			print("  overlapping: ", ctrl.get_path(), " name=", ctrl.name, " visible=", ctrl.visible, " disabled=", ctrl.disabled, " mouse_filter=", ctrl.mouse_filter)
			if ctrl.get_script() != null:
				print("    script=", str(ctrl.get_script().resource_path))

	# Connect handler
	if not back_button.is_connected("pressed", Callable(self, "_on_back_pressed")):
		back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	print("runtime_back_fix: back pressed, changing to settings")
	var tree = get_tree()
	if tree == null:
		return
	if tree.has_method("change_scene_to_file"):
		tree.change_scene_to_file("res://settings.tscn")
	else:
		var res = load("res://settings.tscn")
		if res is PackedScene:
			tree.change_scene_to_packed(res)
