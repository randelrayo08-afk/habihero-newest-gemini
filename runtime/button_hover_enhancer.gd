extends Node

@export var hover_scale: float = 1.02
@export var pressed_scale: float = 0.98

func _ready() -> void:
	get_tree().connect("node_added", Callable(self, "_on_node_added"))
	_scan_tree_for_buttons(get_tree().root)

func _scan_tree_for_buttons(root: Node) -> void:
	for node in root.get_children():
		_maybe_enhance(node)
		if node.get_child_count() > 0:
			_scan_tree_for_buttons(node)

func _on_node_added(node: Node) -> void:
	_maybe_enhance(node)
	for child in node.get_children():
		_maybe_enhance(child)

func _maybe_enhance(node: Node) -> void:
	if not (node is Button):
		return
	if node.get_parent() is Button:
		return
	if node.has_meta("hover_enhanced"):
		return
	node.set_meta("hover_enhanced", true)
	_set_button_state_styles(node)
	node.connect("mouse_entered", Callable(self, "_on_mouse_entered").bind(node))
	node.connect("mouse_exited", Callable(self, "_on_mouse_exited").bind(node))
	node.connect("gui_input", Callable(self, "_on_gui_input").bind(node))

func _set_button_state_styles(button: Button) -> void:
	var normal_style = button.get_theme_stylebox("normal", "Button")
	if normal_style == null:
		return
	var hover_style = normal_style.duplicate(true)
	var pressed_style = normal_style.duplicate(true)
	var focus_style = normal_style.duplicate(true)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", focus_style)

func _on_mouse_entered(button: Node) -> void:
	if not (button is CanvasItem):
		return
	if button.has_meta("hover_tween"):
		var old = button.get_meta("hover_tween")
		if old and is_instance_valid(old):
			old.kill()
	var tw = button.create_tween()
	button.set_meta("hover_tween", tw)
	tw.tween_property(button, "scale", Vector2(1, hover_scale), 0.12)
	tw.play()

func _on_mouse_exited(button: Node) -> void:
	if not (button is CanvasItem):
		return
	if button.has_meta("hover_tween"):
		var old = button.get_meta("hover_tween")
		if old and is_instance_valid(old):
			old.kill()
	var tw = button.create_tween()
	button.set_meta("hover_tween", tw)
	tw.tween_property(button, "scale", Vector2(1,1), 0.12)
	tw.play()

func _on_gui_input(button, event) -> void:
	if not (button is CanvasItem):
		return
	if not (event is InputEventMouseButton):
		return
	var mbe := event as InputEventMouseButton
	if mbe.pressed:
		if button.has_meta("hover_tween"):
			var old = button.get_meta("hover_tween")
			if old and is_instance_valid(old):
				old.kill()
		var tw = button.create_tween()
		button.set_meta("hover_tween", tw)
		tw.tween_property(button, "scale", Vector2(1, pressed_scale), 0.06)
		tw.play()
	else:
		var mouse_pos = get_viewport().get_mouse_position()
		var gpos = button.get_global_position()
		var rect = Rect2(gpos, button.size)
		var target_scale = Vector2(1,1)
		if rect.has_point(mouse_pos):
			target_scale = Vector2(1, hover_scale)
		if button.has_meta("hover_tween"):
			var old2 = button.get_meta("hover_tween")
			if old2 and is_instance_valid(old2):
				old2.kill()
		var tw2 = button.create_tween()
		button.set_meta("hover_tween", tw2)
		tw2.tween_property(button, "scale", target_scale, 0.12)
		tw2.play()
