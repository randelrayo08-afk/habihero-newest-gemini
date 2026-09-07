extends Control
# Privacy Navigation - Manages privacy policy screen

var _nav_handler: Node

var _checkbox: CheckBox
var _agree_button: Button
var _back_button: Button
var _is_from_signup: bool = false

func _ready() -> void:
	_nav_handler = get_tree().root.get_node_or_null("NavigationHandler")
	
	_checkbox = get_node_or_null("Panel/VBoxContainer/AgreeCheckBox")
	_agree_button = get_node_or_null("Panel/VBoxContainer/AgreeButton")
	_back_button = get_node_or_null("Panel4/backs3")
	if _back_button == null:
		_back_button = get_node_or_null("Panel4/Button2")
	if _back_button == null:
		_back_button = get_node_or_null("BackButton")
	
	# Check if coming from signup
	if get_tree().root.has_meta("privacy_from_signup"):
		_is_from_signup = get_tree().root.get_meta("privacy_from_signup")
	
	# Connect signals
	if _checkbox:
		_checkbox.toggled.connect(_on_checkbox_toggled)
	if _agree_button:
		_agree_button.pressed.connect(_on_agree_pressed)
	if _back_button:
		_back_button.pressed.connect(_on_back_pressed)
	
	# Initially disable agree button
	if _agree_button:
		_agree_button.disabled = true

func _on_checkbox_toggled(pressed: bool) -> void:
	"""Enable agree button only when checkbox is checked"""
	if _agree_button:
		_agree_button.disabled = not pressed

func _on_agree_pressed() -> void:
	"""User agreed to privacy policy"""
	if not _checkbox or not _checkbox.button_pressed:
		print("Error: Must check the checkbox first")
		return
	
	# Navigate back to where user came from
	if _is_from_signup:
		if _nav_handler and _nav_handler.has_method("go_to_signup"):
			_nav_handler.call("go_to_signup")
	else:
		if _nav_handler and _nav_handler.has_method("go_to_settings"):
			_nav_handler.call("go_to_settings")

func _on_back_pressed() -> void:
	"""Return to Settings when this screen was opened from the Settings menu."""
	if _nav_handler and _nav_handler.has_method("go_to_settings"):
		_nav_handler.call("go_to_settings")
	elif get_tree() != null:
		get_tree().change_scene_to_file("res://settings.tscn")
