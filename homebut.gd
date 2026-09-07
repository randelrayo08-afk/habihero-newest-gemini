extends Button

var _firebase_db: Node
var _auth_manager: Node
var _session: Node

func _ready() -> void:
	_resolve_firebase_db()
	_resolve_auth_manager()
	_resolve_session()
	_create_ui_elements()
	_refresh_data()
	# Refresh data every 30 seconds for real-time updates
	set_process(true)
	var timer: Timer = Timer.new()
	timer.wait_time = 30.0
	timer.timeout.connect(_refresh_data)
	add_child(timer)
	timer.start()

func _resolve_firebase_db() -> void:
	if get_tree() == null or get_tree().root == null:
		return

	var firebase_node: Node = get_tree().root.get_node_or_null("FirebaseRTDB")
	if firebase_node != null:
		_firebase_db = firebase_node
		return

	if Engine.has_singleton("FirebaseRTDB"):
		_firebase_db = Engine.get_singleton("FirebaseRTDB")
		return

	var script_resource: Script = load("res://FirebaseRTDB.gd")
	if script_resource != null:
		var fallback_db: Node = script_resource.new()
		fallback_db.name = "FirebaseRTDB"
		get_tree().root.add_child.call_deferred(fallback_db)
		_firebase_db = fallback_db
		return

	push_error("FirebaseRTDB autoload could not be resolved")

func _resolve_auth_manager() -> void:
	if get_tree() == null or get_tree().root == null:
		return
	var auth_node: Node = get_tree().root.get_node_or_null("FirebaseAuthManager")
	if auth_node != null:
		_auth_manager = auth_node
		return
	if Engine.has_singleton("FirebaseAuthManager"):
		_auth_manager = Engine.get_singleton("FirebaseAuthManager")

func _resolve_session() -> void:
	if get_tree() == null or get_tree().root == null:
		return
	var session_node: Node = get_tree().root.get_node_or_null("UserSession")
	if session_node != null:
		_session = session_node
		return
	if Engine.has_singleton("UserSession"):
		_session = Engine.get_singleton("UserSession")

func _create_ui_elements() -> void:
	"""Leave the home HUD without the floating level or mood text."""
	var panel4: Panel = get_tree().root.get_node_or_null("Home/Panel4") if get_tree() != null and get_tree().root != null else null
	if panel4 == null:
		return

	var old_exp_bar: Node = panel4.get_node_or_null("ExpProgress")
	if old_exp_bar != null:
		old_exp_bar.queue_free()
	var old_exp_label: Node = panel4.get_node_or_null("ExpLabel")
	if old_exp_label != null:
		old_exp_label.queue_free()
	var old_level_label: Node = panel4.get_node_or_null("LevelLabel")
	if old_level_label != null:
		old_level_label.queue_free()
	var old_mood_label: Node = panel4.get_node_or_null("MoodLabel")
	if old_mood_label != null:
		old_mood_label.queue_free()

func _refresh_data() -> void:
	"""Keep the home HUD free of floating text; mood/level are displayed elsewhere or not at all."""
	if _session == null or not _session.has_method("get_current_user_id"):
		return
	if _auth_manager == null:
		return
	
	var user_id: String = _session.get_current_user_id()
	
	# Experience is handled by the circular shared XP arc only.
	if _auth_manager.has_method("load_experience"):
		_auth_manager.load_experience(user_id, func(ok: bool, _exp_value: Variant):
			if ok and _auth_manager.has_method("load_level"):
				_auth_manager.load_level(user_id, func(_ok: bool, _level: Variant):
					pass
				)
		)

func _on_progbut_pressed() -> void:
	_save_home_state()
	_change_scene_to_file("res://progress.tscn")

func _on_jourbut_pressed() -> void:
	_save_home_state()
	_change_scene_to_file("res://journal.tscn")

func _change_scene_to_file(target_scene: String) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		push_warning("Scene tree is not available yet; cannot change scene.")
		return
	if not is_inside_tree():
		push_warning("Node is not in the scene tree yet; cannot change scene.")
		return
	tree.change_scene_to_file(target_scene)

func _save_home_state() -> void:
	if _firebase_db == null:
		return
	if not _firebase_db.has_method("write_json"):
		print("FirebaseRTDB node is not ready or does not expose write_json")
		return

	var payload: Dictionary = {
		"scene": "home",
		"timestamp": Time.get_datetime_string_from_system(false,false),
		"goal": "daily goal"
	}
	_firebase_db.write_json("sessions/current", payload, func(result, _response_code, _body):
		if result == OK:
			print("Home state saved to Firebase")
		else:
			print("Firebase save failed: ", result)
	)
