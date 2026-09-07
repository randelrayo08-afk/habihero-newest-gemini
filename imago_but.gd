extends Button

func _ready() -> void:
	pressed.connect(_on_done_pressed)

func _on_done_pressed() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.change_scene_to_file("res://spiritual.tscn")
