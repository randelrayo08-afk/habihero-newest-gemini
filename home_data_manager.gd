extends Node
## Manages displaying user data on home.tscn including level, experience, and mood

var _auth_manager: Node
var _session: Node
var _level_label: Label
var _exp_label: Label
var _exp_progress_bar: ProgressBar
var _mood_label: Label
var _mood_panel: Panel

func setup(
	level_label: Label,
	exp_label: Label,
	exp_progress: ProgressBar,
	mood_label: Label,
	mood_panel: Panel
) -> void:
	"""Configure the UI elements to be managed"""
	_level_label = level_label
	_exp_label = exp_label
	_exp_progress_bar = exp_progress
	_mood_label = mood_label
	_mood_panel = mood_panel
	_auth_manager = _resolve_auth_manager()
	_session = _resolve_session()
	_refresh_all_data()

func _refresh_all_data() -> void:
	"""Refresh all user data from Firebase"""
	if _session == null or not _session.has_method("get_current_user_id"):
		return
	var user_id: String = _session.get_current_user_id()
	_refresh_level_and_experience(user_id)
	_refresh_mood(user_id)

func _refresh_level_and_experience(user_id: String) -> void:
	"""Load and display level and experience bar"""
	if _auth_manager == null:
		return
	
	# Load level
	if _auth_manager.has_method("load_level"):
		_auth_manager.load_level(user_id, func(ok: bool, level: Variant):
			if ok and _level_label != null:
				_level_label.text = "Level " + str(int(level))
		)
	
	# Load experience
	if _auth_manager.has_method("load_experience"):
		_auth_manager.load_experience(user_id, func(ok: bool, exp_value: Variant):
			if ok:
				var current_exp: int = int(exp_value)
				# Calculate level and exp for progress bar
				_auth_manager.load_level(user_id, func(_ok: bool, level: Variant):
					var current_level: int = max(1, int(level))
					var exp_required: int = current_level * 100
					
					# Display experience
					if _exp_label != null:
						_exp_label.text = "%d / %d EXP" % [current_exp, exp_required]
					
					# Update progress bar
					if _exp_progress_bar != null:
						_exp_progress_bar.min_value = 0
						_exp_progress_bar.max_value = float(exp_required)
						_exp_progress_bar.value = float(current_exp)
				)
		)

func _refresh_mood(user_id: String) -> void:
	"""Load and display today's mood"""
	if _auth_manager == null or _mood_label == null:
		return
	
	if _auth_manager.has_method("get_todays_mood"):
		_auth_manager.get_todays_mood(user_id, func(ok: bool, mood: Variant):
			if ok:
				var mood_str: String = str(mood).strip_edges()
				if mood_str != "not_set" and not mood_str.is_empty():
					_mood_label.text = "Today's Mood: " + mood_str.capitalize()
					_update_mood_color(mood_str)
				else:
					_mood_label.text = "Today's Mood: Not set"
					_update_mood_color("")
		)

func _update_mood_color(mood: String) -> void:
	"""Update the mood panel color based on mood type"""
	if _mood_panel == null:
		return
	
	var color: Color = Color.WHITE
	match mood.to_lower():
		"happy":
			color = Color(1.0, 0.92, 0.0, 0.7)  # Gold
		"sad":
			color = Color(0.3, 0.5, 1.0, 0.7)  # Blue
		"angry":
			color = Color(1.0, 0.3, 0.3, 0.7)  # Red
		"calm":
			color = Color(0.3, 0.8, 0.3, 0.7)  # Green
		"excited":
			color = Color(1.0, 0.5, 0.0, 0.7)  # Orange
		_:
			color = Color(0.7, 0.7, 0.7, 0.5)  # Gray
	
	if _mood_panel.get_theme_stylebox("panel") is StyleBoxFlat:
		var style: StyleBoxFlat = _mood_panel.get_theme_stylebox("panel").duplicate()
		style.bg_color = color
		_mood_panel.add_theme_stylebox_override("panel", style)

func _resolve_auth_manager() -> Node:
	var auth_manager: Node = null
	if get_tree() != null and get_tree().root != null:
		auth_manager = get_tree().root.get_node_or_null("FirebaseAuthManager")
	if auth_manager == null and Engine.has_singleton("FirebaseAuthManager"):
		auth_manager = Engine.get_singleton("FirebaseAuthManager")
	return auth_manager

func _resolve_session() -> Node:
	var session: Node = null
	if get_tree() != null and get_tree().root != null:
		session = get_tree().root.get_node_or_null("UserSession")
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	return session
