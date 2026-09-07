extends Node
# Navigation Handler - Manages scene transitions
# This should be added to Project Settings → Autoload as "NavigationHandler"
# OR referenced via get_tree().root.get_node_or_null("NavigationHandler")

func _ready() -> void:
	# Ensure this node stays alive between scene changes
	set_process_mode(PROCESS_MODE_ALWAYS)

func navigate_to_scene(scene_path: String) -> void:
	"""Navigate to a different scene"""
	get_tree().change_scene_to_file(scene_path)

func go_to_login() -> void:
	navigate_to_scene("res://login.tscn")

func go_to_home() -> void:
	navigate_to_scene("res://home.tscn")

func go_to_settings() -> void:
	navigate_to_scene("res://settings.tscn")

func go_to_edit_profile() -> void:
	navigate_to_scene("res://edit_profile.tscn")

func go_to_about() -> void:
	navigate_to_scene("res://about.tscn")

func go_to_terms() -> void:
	navigate_to_scene("res://terms.tscn")

func go_to_terms_signup() -> void:
	navigate_to_scene("res://terms_signup.tscn")

func go_to_privacy() -> void:
	navigate_to_scene("res://privacy.tscn")

func go_to_privacy_signup() -> void:
	navigate_to_scene("res://privacy_signup.tscn")

func go_to_help_support() -> void:
	navigate_to_scene("res://helpsupport.tscn")

func go_to_signup() -> void:
	navigate_to_scene("res://signup.tscn")

func go_back() -> void:
	"""Go back to the previous scene when available; otherwise return home."""
	if get_tree().root.has_meta("previous_scene"):
		var previous_scene = get_tree().root.get_meta("previous_scene")
		navigate_to_scene(previous_scene)
	else:
		go_to_home()
