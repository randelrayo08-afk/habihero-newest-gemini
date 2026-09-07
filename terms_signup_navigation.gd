extends Control
# Terms Signup Navigation - Manages terms screen during signup process

var _nav_handler: Node
var _checkbox: CheckBox
var _agree_button: Button

func _ready() -> void:
	_nav_handler = get_tree().root.get_node_or_null("NavigationHandler")

	_checkbox = get_node_or_null("Panel/Panel4/CheckBox") as CheckBox
	_agree_button = get_node_or_null("Panel/Panel4/Button2") as Button

	if _checkbox:
		_checkbox.focus_mode = Control.FOCUS_NONE
		_checkbox.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_checkbox.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_checkbox.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		_checkbox.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		_checkbox.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		_checkbox.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		_checkbox.add_theme_stylebox_override("checked", StyleBoxEmpty.new())
		_checkbox.add_theme_stylebox_override("checked_hover", StyleBoxEmpty.new())
		_checkbox.add_theme_stylebox_override("checked_pressed", StyleBoxEmpty.new())
		_checkbox.add_theme_stylebox_override("checked_disabled", StyleBoxEmpty.new())
		_checkbox.toggled.connect(_on_checkbox_toggled)
		_checkbox.button_pressed = false

	if _agree_button:
		_agree_button.disabled = true
		_agree_button.pressed.connect(_on_agree_pressed)

	_update_agree_button_state()

func _update_agree_button_state() -> void:
	if _agree_button == null:
		return
	_agree_button.disabled = _checkbox == null or not _checkbox.button_pressed

func _on_checkbox_toggled(_pressed: bool) -> void:
	"""Enable agree button only when checkbox is checked."""
	_update_agree_button_state()

func _on_agree_pressed() -> void:
	"""User agreed to terms, then return to signup."""
	if _checkbox == null or not _checkbox.button_pressed:
		print("Error: Must check the checkbox first")
		if _agree_button:
			_agree_button.disabled = true
		return

	if _nav_handler and _nav_handler.has_method("go_to_signup"):
		_nav_handler.call("go_to_signup")
	else:
		get_tree().change_scene_to_file("res://signup.tscn")
