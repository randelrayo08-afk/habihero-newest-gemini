extends Button

func _ready() -> void:
	print("BackButtonHandler: _ready() attached to ", get_path())
	if not pressed.is_connected(Callable(self, "_on_pressed")):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	print("BackButtonHandler: pressed")
	var tree: SceneTree = get_tree()
	if tree == null:
		print("BackButtonHandler: no tree")
		return
	if tree.has_method("change_scene_to_file"):
		print("BackButtonHandler: changing scene to login.tscn via change_scene_to_file")
		tree.change_scene_to_file("res://login.tscn")
	elif tree.has_method("change_scene_to_packed"):
		# fallback: try loading PackedScene directly
		var res = load("res://login.tscn")
		if res is PackedScene:
			print("BackButtonHandler: changing scene to login.tscn via packed scene")
			tree.change_scene_to_packed(res)
