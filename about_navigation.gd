extends Control
# About Navigation - Manages about habihero screen

var _nav_handler: Node
var _back_button: Button

func _ready() -> void:
	_nav_handler = get_tree().root.get_node_or_null("NavigationHandler")
	
	_back_button = get_node_or_null("Panel2/backs1")
	if _back_button == null:
		_back_button = get_node_or_null("Panel2/about_but")
	if _back_button == null:
		_back_button = get_node_or_null("BackButton")
	
	if _back_button:
		_back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	"""Return to Settings when this screen was opened from the Settings menu."""
	if _nav_handler and _nav_handler.has_method("go_to_settings"):
		_nav_handler.call("go_to_settings")
	elif get_tree() != null:
		get_tree().change_scene_to_file("res://settings.tscn")
