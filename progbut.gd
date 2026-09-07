extends Button


func _on_progbut_pressed() -> void:
	_change_scene_to_file("res://progress.tscn")

func _change_scene_to_file(target_scene: String) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		push_warning("Scene tree is not available yet; cannot change scene.")
		return
	if not is_inside_tree():
		push_warning("Node is not in the scene tree yet; cannot change scene.")
		return
	tree.change_scene_to_file(target_scene)
