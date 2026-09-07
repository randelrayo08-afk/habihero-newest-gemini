extends Node

const MAX_HISTORY: int = 24
var _stack: Array[String] = []
var _current_scene: String = ""

func record_scene(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	if _stack.is_empty() or _stack[-1] != scene_path:
		_stack.append(scene_path)
		if _stack.size() > MAX_HISTORY:
			_stack.remove_at(0)
	_current_scene = scene_path

func record_transition(from_scene: String, to_scene: String) -> void:
	if from_scene.is_empty() or from_scene == to_scene:
		return
	if _current_scene != from_scene:
		_current_scene = from_scene
	record_scene(to_scene)

func get_previous_scene() -> String:
	if _stack.size() < 2:
		return ""
	_stack.pop_back()
	var previous_scene: String = _stack[-1]
	_current_scene = previous_scene
	return previous_scene

func clear() -> void:
	_stack.clear()
	_current_scene = ""

func current_scene() -> String:
	return _current_scene
