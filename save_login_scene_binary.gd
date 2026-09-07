extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://login.tscn") as PackedScene
	if scene == null:
		push_error("Failed to load res://login.tscn")
		quit(1)
		return
	var err := ResourceSaver.save(scene, "res://login.scn")
	if err != OK:
		push_error("Failed to save binary scene: %s" % err)
		quit(1)
		return
	print("Saved binary scene to res://login.scn")
	quit(0)
