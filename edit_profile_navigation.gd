extends Control

var _db: Node = null

func _ready() -> void:
	# Remove debug input processing for edit profile scene
	# set_process_input(true)
	# set_process_unhandled_input(true)
	print("EditProfileNavigation: _ready() attached to node=", self.name, " path=", get_path())
	# Connect top-left back button and nested button (common pattern in scenes)
	var back_button: Button = get_node_or_null("Button") as Button
	if back_button != null:
		# Ensure button properties allow input
		back_button.disabled = false
		back_button.visible = true
		back_button.focus_mode = Control.FOCUS_ALL
		back_button.raise()
		# Connect signals and debug gui_input
		var pressed_cb: Callable = Callable(self, "_on_back_pressed")
		if not back_button.is_connected("pressed", pressed_cb):
			back_button.pressed.connect(pressed_cb)
		var gui_cb: Callable = Callable(self, "_on_back_gui_input")
		if not back_button.is_connected("gui_input", gui_cb):
			back_button.gui_input.connect(gui_cb)
	else:
		push_warning("Back button not found in edit_profile scene.")
	var nested: Button = get_node_or_null("Button/Button") as Button
	if nested != null:
		nested.disabled = false
		nested.visible = true
		nested.focus_mode = Control.FOCUS_ALL
		nested.raise()
		var nested_cb: Callable = Callable(self, "_on_back_pressed")
		if not nested.is_connected("pressed", nested_cb):
			nested.pressed.connect(nested_cb)
		var nested_gui_cb: Callable = Callable(self, "_on_back_gui_input")
		if not nested.is_connected("gui_input", nested_gui_cb):
			nested.gui_input.connect(nested_gui_cb)

	# Populate fields from session
	_resolve_db()
	_populate_user_info()

	# Deferred setup to ensure UI order is stable
	call_deferred("_deferred_setup_back")

	# Connect Save Changes button
	var save_btn: Button = get_node_or_null("Button2") as Button
	if save_btn != null:
		if not save_btn.is_connected("pressed", Callable(self, "_on_save_pressed")):
			save_btn.pressed.connect(_on_save_pressed)

func _on_back_pressed() -> void:
	print("EditProfile: back pressed")
	# Prefer going back via recorded history if available
	var history: Node = _resolve_history()
	if history != null and history.has_method("get_previous_scene"):
		var prev: String = history.get_previous_scene()
		if not prev.is_empty():
			_change_scene_to_file(prev)
			return
	# Fallback to shared_nav go_back if available
	var root_nav: Node = null
	if get_tree() != null and get_tree().root != null:
		root_nav = get_tree().root.get_node_or_null("SharedNav")
	if root_nav != null and root_nav.has_method("_go_back"):
		root_nav._go_back()
		return
	# Final fallback: load settings scene directly
	_change_scene_to_file("res://settings.tscn")


func _on_back_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			print("EditProfile: back gui_input mouse pressed at %s" % str(event.position))
		else:
			print("EditProfile: back gui_input mouse released at %s" % str(event.position))


func _input(event: InputEvent) -> void:
	# Log global mouse button events to determine whether input reaches the scene
	if not is_inside_tree() or get_tree() == null:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return
	if event is InputEventMouseButton:
		if event.pressed:
			var pos: Vector2 = event.position
			print("EditProfile: GLOBAL mouse pressed at %s" % str(pos))
			var top: Node = _find_top_control_at(current_scene, pos)
			if top != null:
				print("EditProfile: top control at pos -> ", str(top), " (name=", top.name, ")")
			else:
				print("EditProfile: no control found at pos")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			print("EditProfile: UNHANDLED mouse pressed at %s" % str(event.position))


func _find_top_control_at(root: Node, pos: Vector2) -> Node:
	if root == null:
		return null
	# traverse children in reverse so later (top) nodes are checked first
	for i in range(root.get_child_count() - 1, -1, -1):
		var child: Node = root.get_child(i)
		if not (child is Control):
			# continue searching inside non-Control containers
			var nested: Node = _find_top_control_at(child, pos)
			if nested != null:
				return nested
			continue
		var ctrl: Control = child as Control
		var global_pos: Vector2 = ctrl.get_global_position()
		var rect_size: Vector2 = ctrl.size
		var rect: Rect2 = Rect2(global_pos, rect_size)
		if rect.has_point(pos):
			# check children for a more specific control
			var nested_in_child: Node = _find_top_control_at(child, pos)
			return nested_in_child if nested_in_child != null else ctrl
	return null


func _ensure_back_proxy(back_button: Button) -> void:
	# Create a transparent Button over the back button to capture clicks reliably
	if back_button == null:
		return
	if not back_button.is_inside_tree():
		return
	var root_scene: Node = get_tree().current_scene
	if root_scene == null or not root_scene.is_inside_tree():
		return
	# Remove existing proxy if present
	var existing: Button = root_scene.get_node_or_null("BackClickProxy") as Button
	if existing != null:
		existing.queue_free()
	var proxy: Button = Button.new()
	proxy.name = "BackClickProxy"
	proxy.text = ""
	proxy.mouse_filter = Control.MOUSE_FILTER_STOP
	proxy.focus_mode = Control.FOCUS_NONE
	proxy.disabled = false
	proxy.visible = true
	# Match size and global position
	proxy.size = back_button.size
	proxy.set_global_position(back_button.get_global_position())
	root_scene.add_child(proxy)
	proxy.raise()
	if not proxy.is_connected("pressed", Callable(self, "_on_back_pressed")):
		proxy.pressed.connect(_on_back_pressed)
	print("EditProfile: Back proxy created")


func _deferred_setup_back() -> void:
	# Run after the scene is ready to ensure overlays/children are present
	if not is_inside_tree():
		return
	var back_button: Button = get_node_or_null("Button") as Button
	if back_button == null:
		back_button = get_node_or_null("Button/Button") as Button
	if back_button == null:
		print("EditProfile: no back button found during deferred setup")
		return
	# raise and ensure proxy
	back_button.raise()
	back_button.visible = true
	back_button.disabled = false
	_ensure_back_proxy(back_button)

	# Find overlapping controls and set them to ignore mouse so back is clickable
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var bpos: Vector2 = back_button.get_global_position()
	var brect: Rect2 = Rect2(bpos, back_button.size)
	for child in scene.get_children():
		if child == back_button:
			continue
		if child is Control:
			var ctrl: Control = child as Control
			var rect: Rect2 = Rect2(ctrl.get_global_position(), ctrl.size)
			if rect.intersects(brect):
				# only change controls that are visible and would block input
				if ctrl.mouse_filter != Control.MOUSE_FILTER_IGNORE:
					ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
					print("EditProfile: set mouse_filter IGNORE on ", ctrl.name)

func _resolve_history() -> Node:
	if get_tree() != null and get_tree().root != null:
		var history: Node = get_tree().root.get_node_or_null("NavigationHistory")
		if history != null:
			return history
	if Engine.has_singleton("NavigationHistory"):
		return Engine.get_singleton("NavigationHistory")
	return null


func _resolve_db() -> void:
	if _db != null:
		return
	if get_tree() != null and get_tree().root != null:
		_db = get_tree().root.get_node_or_null("FirebaseRTDB")
	if _db == null and Engine.has_singleton("FirebaseRTDB"):
		_db = Engine.get_singleton("FirebaseRTDB")
	if _db == null:
		push_warning("FirebaseRTDB autoload is not available")

func _change_scene_to_file(target_scene: String) -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	if not is_inside_tree():
		return
	var scene_resource: Variant = load(target_scene)
	if not (scene_resource is PackedScene):
		push_warning("Scene resource could not be loaded: %s" % target_scene)
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if tree.has_method("change_scene_to_packed"):
		tree.change_scene_to_packed(scene_resource)
	elif tree.has_method("change_scene_to_file"):
		tree.change_scene_to_file(target_scene)

func _populate_user_info() -> void:
	var session: Node = null
	if get_tree() != null and get_tree().root != null:
		session = get_tree().root.get_node_or_null("UserSession")
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	var user_name: String = ""
	if session != null and session.has_method("get_current_user_name"):
		user_name = str(session.call("get_current_user_name"))
	# Find LineEdit node for Name and set its text
	var name_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/NameInputRow/LineEdit") as LineEdit
	if name_edit == null:
		name_edit = get_node_or_null("LineEdit") as LineEdit
	if name_edit != null and user_name.strip_edges() != "":
		name_edit.text = user_name

	# If DB is available, prefer live data from Firebase profile
	# reuse the `session` variable declared above
	if session == null and get_tree() != null and get_tree().root != null:
		session = get_tree().root.get_node_or_null("UserSession")
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	if session != null and _db != null and session.has_method("get_current_user_id"):
		var uid: String = str(session.get_current_user_id())
		if uid.strip_edges() != "":
			_db.read_json("users/" + uid, func(result: int, response_code: int, body: Variant) -> void:
				var ok: bool = result == OK and response_code >= 200 and response_code < 300
				if ok and body is Dictionary:
					var profile: Dictionary = {}
					if body.has("profile") and body.get("profile") is Dictionary:
						profile = body.get("profile")
					elif body.has("name"):
						profile = body
					if profile.has("name") and name_edit != null:
						name_edit.text = str(profile.get("name"))
					# populate other fields if present
					var grade_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/GradeInputRow/LineEdit2") as LineEdit
					if grade_edit != null and profile.has("grade_level"):
						grade_edit.text = str(profile.get("grade_level"))
					var section_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/SectionInputRow/LineEdit3") as LineEdit
					if section_edit != null and profile.has("section"):
						section_edit.text = str(profile.get("section"))
					var birthday_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/BirthdayInputRow/BirthdayEdit") as LineEdit
					if birthday_edit != null and profile.has("birthday"):
						birthday_edit.text = str(profile.get("birthday"))
			)
func _on_save_pressed() -> void:
	# Gather fields
	var name_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/NameInputRow/LineEdit") as LineEdit
	if name_edit == null:
		name_edit = get_node_or_null("LineEdit") as LineEdit
	var grade_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/GradeInputRow/LineEdit2") as LineEdit
	var section_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/SectionInputRow/LineEdit3") as LineEdit
	var birthday_edit: LineEdit = get_node_or_null("Panel2/InputFieldsContainer/VBoxContainer/BirthdayInputRow/BirthdayEdit") as LineEdit
	var about_box: TextEdit = get_node_or_null("Panel2/Panel2/TextEdit") as TextEdit
	var payload: Dictionary = {}
	if name_edit != null:
		payload["name"] = str(name_edit.text).strip_edges()
	if grade_edit != null:
		payload["grade_level"] = str(grade_edit.text).strip_edges()
	if section_edit != null:
		payload["section"] = str(section_edit.text).strip_edges()
	if birthday_edit != null:
		payload["birthday"] = str(birthday_edit.text).strip_edges()
	if about_box != null:
		payload["about"] = str(about_box.text).strip_edges()

	# Resolve user id
	var session: Node = null
	if get_tree() != null and get_tree().root != null:
		session = get_tree().root.get_node_or_null("UserSession")
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	var uid: String = ""
	if session != null and session.has_method("get_current_user_id"):
		uid = str(session.get_current_user_id())
	if uid.strip_edges() == "":
		push_warning("Cannot save profile: no user id available")
		return

	# Write to Firebase profile node
	if _db != null and _db.has_method("write_json"):
		_db.write_json("users/" + uid + "/profile", payload, func(result: int, response_code: int, body: Variant) -> void:
			var ok: bool = result == OK and response_code >= 200 and response_code < 300
			if ok:
				# update session name
				if session != null and payload.has("name"):
					session.current_user_name = str(payload.get("name"))
				# simple feedback
				push_warning("Profile saved to Firebase")
			else:
				push_warning("Failed to save profile: %s" % str(body))
		)
	else:
		# Fallback: no DB, just update session
		if session != null and payload.has("name"):
			session.current_user_name = str(payload.get("name"))
		push_warning("Profile saved locally")
