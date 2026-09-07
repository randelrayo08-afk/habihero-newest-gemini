extends Node
# AppSetup - Initialize global managers and handlers
# This should be added to Project → Project Settings → Autoload as "AppSetup"

func _ready() -> void:
	# Initialize Navigation Handler
	_init_navigation_handler()
	
	# Initialize Profile Manager
	_init_profile_manager()

	# Set default voice IDs (can be replaced with real provider voice IDs)
	var root = get_tree().root
	if root != null:
		# Only set defaults if not already configured elsewhere
		if not root.has_meta("voice_id_male"):
			root.set_meta("voice_id_male", "alloy")
		if not root.has_meta("voice_id_female"):
			root.set_meta("voice_id_female", "nova")
		print("AppSetup: voice_id_male/female defaults set to alloy/nova")

func _init_navigation_handler() -> void:
	"""Ensure NavigationHandler is available globally"""
	var existing = get_tree().root.get_node_or_null("NavigationHandler")
	if existing != null:
		return
	
	var nav_handler = load("res://navigation_handler.gd").new()
	nav_handler.name = "NavigationHandler"
	get_tree().root.add_child.call_deferred(nav_handler)

func _init_profile_manager() -> void:
	"""Ensure ProfileManager is available globally"""
	var existing = get_tree().root.get_node_or_null("ProfileManager")
	if existing != null:
		return
	
	var profile_mgr = load("res://profile_manager.gd").new()
	profile_mgr.name = "ProfileManager"
	get_tree().root.add_child.call_deferred(profile_mgr)
