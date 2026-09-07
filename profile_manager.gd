extends Node
# Profile Manager - Handles loading and saving user profile data
# This should be added to Project Settings → Autoload as "ProfileManager"
# OR referenced via get_tree().root.get_node_or_null("ProfileManager")

var _auth_manager: Node

func _ready() -> void:
	set_process_mode(PROCESS_MODE_ALWAYS)
	_resolve_auth_manager()

func _resolve_auth_manager() -> Node:
	if _auth_manager != null:
		return _auth_manager
	if get_tree() != null and get_tree().root != null:
		_auth_manager = get_tree().root.get_node_or_null("FirebaseAuthManager")
	if _auth_manager == null and Engine.has_singleton("FirebaseAuthManager"):
		_auth_manager = Engine.get_singleton("FirebaseAuthManager")
	return _auth_manager

func load_user_profile(user_id: String, callback: Callable) -> void:
	"""Load user profile from Firebase"""
	var auth = _resolve_auth_manager()
	if auth != null and auth.has_method("load_profile"):
		auth.load_profile(user_id, callback)
	else:
		callback.call(false, {})

func save_user_profile(user_id: String, profile_data: Dictionary, callback: Callable) -> void:
	"""Save user profile to Firebase"""
	var auth = _resolve_auth_manager()
	if auth != null and auth.has_method("save_profile_attributes"):
		auth.save_profile_attributes(user_id, profile_data, callback)
	else:
		callback.call(false)

func get_profile_field(profile: Dictionary, field: String, default_value: String = "") -> String:
	"""Safely get a field from profile dictionary"""
	var value = profile.get(field, default_value)
	return str(value) if value != null else default_value
