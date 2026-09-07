extends Button

func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var home_scene: Resource = load("res://home.tscn")
	if home_scene is PackedScene and tree.has_method("change_scene_to_packed"):
		tree.change_scene_to_packed(home_scene)
	elif tree.has_method("change_scene_to_file"):
		tree.change_scene_to_file("res://home.tscn")
