extends Control

func _ready() -> void:
	var start_button: Button = get_node_or_null("Button") as Button
	if start_button != null:
		start_button.pressed.connect(_on_start_pressed)
	else:
		push_warning("Start button not found in start scene.")

func _on_start_pressed() -> void:
	_change_scene_to_file("res://login.tscn")

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
