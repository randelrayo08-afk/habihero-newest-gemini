extends Node

const DESIGN_WIDTH := 520.0
const DESIGN_HEIGHT := 800.0

var _refresh_pending := false
var _last_applied_scale := Vector2.ONE
var _last_applied_offset := Vector2.ZERO

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	_get_tree_root().size_changed.connect(_on_viewport_resized)
	_last_scene = get_tree().current_scene
	call_deferred("_refresh_scene_layout")

func _on_viewport_resized() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_refresh_scene_layout")

func _refresh_scene_layout() -> void:
	_refresh_pending = false
	var scene = get_tree().current_scene
	if scene == null:
		return
	
	var root_control = _find_scene_root(scene)
	if root_control == null:
		return
	
	_lock_scene_to_design(root_control)

func _find_scene_root(node: Node) -> Control:
	if node is Control:
		var parent = node.get_parent()
		if parent == null or parent == _get_tree_root():
			return node
		if parent is Window:
			return node
	
	for child in node.get_children():
		var found = _find_scene_root(child)
		if found != null:
			return found
	return null

func _lock_scene_to_design(control: Control) -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(DESIGN_WIDTH, DESIGN_HEIGHT)
	
	var fit_scale = min(viewport_size.x / DESIGN_WIDTH, viewport_size.y / DESIGN_HEIGHT)
	var design_size = Vector2(DESIGN_WIDTH, DESIGN_HEIGHT) * fit_scale
	var offset = (viewport_size - design_size) * 0.5
	
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + design_size.x
	control.offset_bottom = offset.y + design_size.y
	control.scale = Vector2(fit_scale, fit_scale)
	control.pivot_offset = Vector2.ZERO
	control.position = Vector2.ZERO
	
	_last_applied_scale = control.scale
	_last_applied_offset = Vector2(offset.x, offset.y)

func _get_tree_root() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root

func _process(_delta: float) -> void:
	if get_tree() == null:
		return
	var scene = get_tree().current_scene
	if scene != _last_scene:
		_last_scene = scene
		call_deferred("_refresh_scene_layout")

var _last_scene: Node = null
