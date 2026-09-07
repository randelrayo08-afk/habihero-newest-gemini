extends Control
# Settings Navigation - Manages settings screen buttons

const NAV_MAP: Dictionary = {
	"edit_profile": "res://edit_profile.tscn",
	"about": "res://about.tscn",
	"terms": "res://terms.tscn",
	"privacy": "res://privacy.tscn",
	"helpsupport": "res://helpsupport.tscn",
	"login": "res://login.tscn",
	"home": "res://home.tscn"
}

var _edit_button: Button
var _about_button: Button
var _terms_button: Button
var _privacy_button: Button
var _help_button: Button
var _logout_button: Button
var _back_button: Button

func _ready() -> void:
	# Try multiple possible button paths
	_edit_button = _find_button_by_path("Panel/VBoxContainer/EditButton")
	if _edit_button == null:
		_edit_button = _find_button_by_label("Edit Profile")
	
	_about_button = _find_button_by_path("Panel/VBoxContainer/AboutButton")
	if _about_button == null:
		_about_button = _find_button_by_label("About")
	
	_terms_button = _find_button_by_path("Panel/VBoxContainer/TermsButton")
	if _terms_button == null:
		_terms_button = _find_button_by_label("Terms")
	
	_privacy_button = _find_button_by_path("Panel/VBoxContainer/PrivacyButton")
	if _privacy_button == null:
		_privacy_button = _find_button_by_label("Privacy")
	
	_help_button = _find_button_by_path("Panel/VBoxContainer/HelpButton")
	if _help_button == null:
		_help_button = _find_button_by_label("Help")
	
	_logout_button = _find_button_by_path("Panel/VBoxContainer/LogoutButton")
	if _logout_button == null:
		_logout_button = _find_button_by_label("Logout")
	
	_back_button = _find_button_by_path("Button")
	if _back_button == null:
		_back_button = _find_button_by_label("Back")
	
	# Connect signals
	if _edit_button:
		_edit_button.pressed.connect(_on_edit_pressed)
	if _about_button:
		_about_button.pressed.connect(_on_about_pressed)
	if _terms_button:
		_terms_button.pressed.connect(_on_terms_pressed)
	if _privacy_button:
		_privacy_button.pressed.connect(_on_privacy_pressed)
	if _help_button:
		_help_button.pressed.connect(_on_help_pressed)
	if _logout_button:
		_logout_button.pressed.connect(_on_logout_pressed)
	if _back_button:
		_back_button.pressed.connect(_on_back_pressed)

func _find_button_by_path(node_path: String) -> Button:
	var node = get_node_or_null(node_path)
	if node is Button:
		return node
	return null

func _find_button_by_label(label_text: String) -> Button:
	for child in get_children():
		var found = _search_branch_for_button(child, label_text)
		if found != null:
			return found
	return null

func _search_branch_for_button(node: Node, label_text: String) -> Button:
	if node == null:
		return null
	
	if node is Button:
		var button = node as Button
		if button.text == label_text:
			return button
		var label = _first_label_under(button)
		if label != null and label.text == label_text:
			return button
	
	for child in node.get_children():
		var found = _search_branch_for_button(child, label_text)
		if found != null:
			return found
	
	return null

func _first_label_under(node: Node) -> Label:
	if node == null:
		return null
	
	for child in node.get_children():
		if child is Label:
			return child as Label
		var nested = _first_label_under(child)
		if nested != null:
			return nested
	return null

func _on_edit_pressed() -> void:
	"""Go to edit profile screen"""
	_change_scene(NAV_MAP["edit_profile"])

func _on_about_pressed() -> void:
	"""Go to about screen"""
	_change_scene(NAV_MAP["about"])

func _on_terms_pressed() -> void:
	"""Go to terms screen"""
	_change_scene(NAV_MAP["terms"])

func _on_privacy_pressed() -> void:
	"""Go to privacy screen"""
	_change_scene(NAV_MAP["privacy"])

func _on_help_pressed() -> void:
	"""Go to help and support screen"""
	_change_scene(NAV_MAP["helpsupport"])

func _on_logout_pressed() -> void:
	"""Logout and go to login screen"""
	_change_scene(NAV_MAP["login"])

func _on_back_pressed() -> void:
	"""Go back to home screen"""
	_change_scene(NAV_MAP["home"])

func _change_scene(target_scene: String) -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	if not is_inside_tree():
		return
	
	var root = get_tree().root
	if target_scene in [NAV_MAP["about"], NAV_MAP["terms"], NAV_MAP["privacy"], NAV_MAP["helpsupport"]]:
		root.set_meta("opened_from_settings", true)
	else:
		if root.has_meta("opened_from_settings"):
			root.remove_meta("opened_from_settings")
	
	var scene_resource = load(target_scene)
	if not (scene_resource is PackedScene):
		push_warning("Scene resource could not be loaded: %s" % target_scene)
		return
	
	var tree = get_tree()
	if tree == null:
		return
	
	if tree.has_method("change_scene_to_packed"):
		tree.change_scene_to_packed(scene_resource)
	elif tree.has_method("change_scene_to_file"):
		tree.change_scene_to_file(target_scene)
