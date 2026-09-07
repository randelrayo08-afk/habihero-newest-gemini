extends "res://shared_nav.gd"

var _mood_graph: Control
var _goal_progress_panel: Control
var _xp_arc: Control

func _ready() -> void:
	super._ready()
	_mood_graph = _MoodGraph.new()
	_mood_graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var chart_panel: Control = get_node_or_null("Panel4/Panel") as Control
	if chart_panel != null:
		_mood_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chart_panel.add_child(_mood_graph)
	_wire_details_button()
	_load_mood_history()
	_load_goal_progress()
	_refresh_assigned_task_status()
	_setup_xp_arc()
	_load_experience()

func _setup_xp_arc() -> void:
	var badge: Control = get_node_or_null("experience") as Control
	if badge == null:
		badge = get_node_or_null("Panel6") as Control
	if badge == null:
		return
	_xp_arc = _XPArc.new()
	_xp_arc.name = "XPArc"
	_xp_arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_arc.z_index = 5
	badge.add_child(_xp_arc)
	call_deferred("_resize_xp_arc")
	var center_panel: Control = badge.get_node_or_null("Panel5") as Control
	if center_panel != null:
		center_panel.z_index = 6
	var level_label: Label = badge.get_node_or_null("Label") as Label
	if level_label != null:
		level_label.z_index = 7

func _resize_xp_arc() -> void:
	if _xp_arc == null or not is_instance_valid(_xp_arc):
		return
	var badge: Control = get_node_or_null("experience") as Control
	if badge == null:
		badge = get_node_or_null("Panel6") as Control
	if badge == null:
		return
	_xp_arc.position = Vector2.ZERO
	_xp_arc.size = badge.size
	_xp_arc.queue_redraw()

func _load_experience() -> void:
	var experience_panel: Control = get_node_or_null("experience") as Control
	if experience_panel == null:
		experience_panel = get_node_or_null("Panel6") as Control
	var level_label: Label = experience_panel.get_node_or_null("Label") as Label if experience_panel != null else null
	var xp_bar: ProgressBar = experience_panel.get_node_or_null("XPProgress") as ProgressBar if experience_panel != null else null
	var xp_label: Label = experience_panel.get_node_or_null("XPLabel") as Label if experience_panel != null else null
	if level_label == null or xp_bar == null or xp_label == null:
		return
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = str(_session.call("get_current_user_id")).strip_edges()
	print("Progress: loading experience for user_id=", user_id)
	if _auth_manager != null and _auth_manager.has_method("load_experience"):
		_auth_manager.load_experience(user_id, Callable(self, "_on_experience_loaded"))

func _on_experience_loaded(ok: bool, experience: Variant) -> void:
	print("Progress: experience callback ok=", ok, " value=", experience)
	if not ok or not is_instance_valid(self):
		return
	var experience_panel: Control = get_node_or_null("experience") as Control
	var level_label: Label = experience_panel.get_node_or_null("Label") as Label if experience_panel != null else null
	var xp_bar: ProgressBar = experience_panel.get_node_or_null("XPProgress") as ProgressBar if experience_panel != null else null
	var xp_label: Label = experience_panel.get_node_or_null("XPLabel") as Label if experience_panel != null else null
	if level_label == null or xp_bar == null or xp_label == null:
		return
	var total_experience: int = max(0, int(experience))
	var level: int = int(float(total_experience) / 500.0) + 1
	var current_xp: int = total_experience % 500
	level_label.text = str(level)
	xp_bar.value = current_xp
	xp_label.text = "XP: %d / 500" % current_xp
	if _xp_arc != null and _xp_arc.has_method("set_progress_ratio"):
		_xp_arc.call("set_progress_ratio", float(current_xp) / 500.0)

class _XPArc extends Control:
	var progress_ratio: float = 0.0:
		set(value):
			progress_ratio = clampf(value, 0.0, 1.0)
			queue_redraw()

	func set_progress_ratio(value: float) -> void:
		progress_ratio = value

	func _draw() -> void:
		var center := size / 2.0
		var radius: float = minf(size.x, size.y) / 2.0 - 8.0
		var track_color := Color("#d9d1c5")
		var fill_color := Color("#4aa63b")
		draw_arc(center, radius, 0.0, TAU, 96, track_color, 10.0, true)
		if progress_ratio > 0.0:
			draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * progress_ratio, 96, fill_color, 10.0, true)

func _load_goal_progress() -> void:
	_goal_progress_panel = get_node_or_null("Panel3/Panel") as Control
	if _goal_progress_panel == null:
		return
	var sections: Control = _goal_progress_panel.get_node_or_null("ScrollContainer/GoalSections") as Control
	if sections == null:
		return
	var completed_panel: Panel = sections.get_node_or_null("CompletedPanel") as Panel
	var ongoing_panel: Panel = sections.get_node_or_null("OngoingPanel") as Panel
	if completed_panel == null or ongoing_panel == null:
		return
	_clear_goal_panel(completed_panel)
	_clear_goal_panel(ongoing_panel)

	var state := _read_daily_task_state()
	var completed_titles: Dictionary = state.get("completed_task_titles", {})
	var active_titles: Dictionary = state.get("active_task_titles", {})
	var completed_ids: Array = state.get("completed_task_ids", [])
	var active_ids: Array = state.get("active_task_ids", [])
	var completed_assigned_ids: Array = state.get("completed_assigned_task_ids", [])
	if completed_assigned_ids == null:
		completed_assigned_ids = []
	var assigned_lookup: Dictionary = state.get("assigned_task_lookup", {})
	if assigned_lookup is Dictionary:
		for task_id in assigned_lookup.keys():
			var title: String = str(assigned_lookup.get(task_id, "")).strip_edges()
			if title.is_empty():
				continue
			var id_key: String = str(task_id)
			if id_key in completed_assigned_ids:
				continue
			if id_key not in completed_ids and id_key not in active_ids:
				active_ids.append(id_key)
				active_titles[id_key] = title
			if id_key in completed_ids:
				completed_titles[id_key] = title
	for completed_assignment_id in completed_assigned_ids:
		active_ids.erase(completed_assignment_id)
		active_titles.erase(completed_assignment_id)

	_add_goal_section(completed_panel, "COMPLETED TODAY", completed_titles, completed_ids, Color("#3b8f64"))
	_add_goal_section(ongoing_panel, "ONGOING", active_titles, active_ids, Color("#a56a2b"))

func _refresh_assigned_task_status() -> void:
	var database: Node = get_tree().root.get_node_or_null("FirebaseRTDB") if get_tree() != null and get_tree().root != null else null
	if database == null or not database.has_method("read_json"):
		return
	var user_key: String = ""
	if _session != null and _session.has_method("get_current_user_email"):
		user_key = str(_session.call("get_current_user_email")).strip_edges().to_lower()
	if user_key.is_empty() and _session != null and _session.has_method("get_current_user_id"):
		user_key = str(_session.call("get_current_user_id")).strip_edges().to_lower()
	if user_key.is_empty() or user_key == "guest_user":
		return
	for character in ["@", ".", "#", "$", "[", "]", " "]:
		user_key = user_key.replace(character, "_")
	database.read_json("users/%s/tasks" % user_key, func(result: int, response_code: int, body: Variant) -> void:
		if result != OK or response_code < 200 or response_code >= 300 or not body is Dictionary:
			return
		var state: Dictionary = _read_daily_task_state()
		var completed_assignments: Array = state.get("completed_assigned_task_ids", [])
		if completed_assignments == null:
			completed_assignments = []
		var assigned_lookup: Variant = state.get("assigned_task_lookup", {})
		for task_key in body.keys():
			var task_entry: Variant = body.get(task_key)
			if not task_entry is Dictionary or not bool(task_entry.get("completed", false)):
				continue
			var task_id: String = str(task_entry.get("task_id", task_key)).strip_edges()
			if task_id.is_empty():
				continue
			if task_id not in completed_assignments:
				completed_assignments.append(task_id)
			if assigned_lookup is Dictionary:
				assigned_lookup.erase(task_id)
		state["completed_assigned_task_ids"] = completed_assignments
		state["assigned_task_lookup"] = assigned_lookup
		_save_progress_task_state(state)
		_load_goal_progress()
	)

func _save_progress_task_state(state: Dictionary) -> void:
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = str(_session.call("get_current_user_id")).strip_edges().to_lower()
	for character in ["@", ".", "#", "$", "[", "]", " "]:
		user_id = user_id.replace(character, "_")
	var file := FileAccess.open("user://daily_task_state_%s.json" % user_id, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state))
		file.close()

func _clear_goal_panel(panel: Panel) -> void:
	for child in panel.get_children():
		child.queue_free()

func _add_goal_section(panel: Panel, heading: String, titles: Dictionary, ids: Array, heading_color: Color) -> void:
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10.0
	content.offset_top = 8.0
	content.offset_right = -10.0
	content.offset_bottom = -8.0
	content.add_theme_constant_override("separation", 3)
	panel.add_child(content)

	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.add_theme_color_override("font_color", heading_color)
	heading_label.add_theme_font_size_override("font_size", 13)
	content.add_child(heading_label)

	if ids.is_empty() and titles.is_empty():
		var empty_label := Label.new()
		empty_label.text = "None"
		empty_label.add_theme_color_override("font_color", Color("#6f665f"))
		empty_label.add_theme_font_size_override("font_size", 12)
		content.add_child(empty_label)
		return

	var shown_ids: Array = ids.duplicate()
	for title_id in titles:
		if title_id not in shown_ids:
			shown_ids.append(title_id)
	for task_id in shown_ids:
		var task_title := str(titles.get(task_id, task_id)).strip_edges()
		if task_title.is_empty():
			task_title = str(task_id)
		var row := Label.new()
		row.text = "- " + task_title
		row.clip_text = true
		row.add_theme_color_override("font_color", Color("#2f2924"))
		row.add_theme_font_size_override("font_size", 12)
		content.add_child(row)
	panel.custom_minimum_size.y = max(82.0, 34.0 + shown_ids.size() * 22.0)

func _read_daily_task_state() -> Dictionary:
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = str(_session.call("get_current_user_id")).strip_edges().to_lower()
	for character in ["@", ".", "#", "$", "[", "]", " "]:
		user_id = user_id.replace(character, "_")
	var state_path: String = "user://daily_task_state_%s.json" % user_id
	if not FileAccess.file_exists(state_path):
		return {}
	var file := FileAccess.open(state_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _wire_details_button() -> void:
	var details_button: Button = get_node_or_null("Panel4/Button") as Button
	if details_button == null or not has_method("_switch_to_scene"):
		return
	var callback := Callable(self, "_switch_to_scene").bind("res://myprog.tscn")
	if not details_button.pressed.is_connected(callback):
		details_button.pressed.connect(callback)

func _load_mood_history() -> void:
	var user_id := "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		var session_id := str(_session.call("get_current_user_id")).strip_edges()
		if not session_id.is_empty():
			user_id = session_id
	if _auth_manager != null and _auth_manager.has_method("load_moodcheck_entries"):
		_auth_manager.load_moodcheck_entries(user_id, _on_mood_history_loaded)
	else:
		_mood_graph.call("set_entries", {})

func _on_mood_history_loaded(ok: bool, entries: Variant) -> void:
	if ok and entries is Dictionary:
		_mood_graph.call("set_entries", entries)
	else:
		_mood_graph.call("set_entries", {})

class _MoodGraph extends Control:
	const MOOD_VALUES: Dictionary = {
		"worried": 1.0,
		"sad": 2.0,
		"angry": 3.0,
		"calm": 4.0,
		"curious": 5.0,
		"proud": 6.0,
		"excited": 7.0,
		"loved": 8.0,
		"happy": 9.0
	}
	const MOOD_COLORS: Dictionary = {
		"worried": Color("#7b61a8"),
		"sad": Color("#4f86c6"),
		"angry": Color("#d94b4b"),
		"calm": Color("#58a889"),
		"curious": Color("#35a9b7"),
		"proud": Color("#d67b32"),
		"excited": Color("#ef9b2d"),
		"loved": Color("#e579a5"),
		"happy": Color("#e7b24c")
	}
	var _entries: Dictionary = {}

	func set_entries(entries: Dictionary) -> void:
		_entries = entries
		queue_redraw()

	func _draw() -> void:
		var chart_rect := Rect2(22.0, 10.0, max(20.0, size.x - 44.0), max(20.0, size.y - 28.0))
		var axis_color := Color("#8c8176")
		var line_color := Color("#e7b24c")
		var label_color := Color("#5f5147")
		var font := ThemeDB.fallback_font
		for index in range(5):
			var y := chart_rect.position.y + chart_rect.size.y * float(index) / 4.0
			draw_line(Vector2(chart_rect.position.x, y), Vector2(chart_rect.end.x, y), Color(0.55, 0.50, 0.45, 0.20), 1.0)
		var points: Array[Vector2] = []
		var today := Time.get_date_dict_from_system()
		var today_unix := Time.get_unix_time_from_datetime_dict(today)
		var week_start_unix := today_unix - int(today.weekday) * 86400
		for day_index in range(7):
			if day_index > int(today.weekday):
				points.append(Vector2.ZERO)
				continue
			var day_unix := week_start_unix + day_index * 86400
			var date_dict := Time.get_date_dict_from_unix_time(day_unix)
			var point_x := chart_rect.position.x + chart_rect.size.x * float(day_index) / 6.0
			var mood_value := _mood_value_for_date(date_dict)
			if mood_value > 0.0:
				var point_y := chart_rect.end.y - chart_rect.size.y * (mood_value - 1.0) / 8.0
				points.append(Vector2(point_x, point_y))
				var mood_label := _mood_label_for_value(mood_value)
				draw_circle(Vector2(point_x, point_y), 5.0, _mood_color_for_value(mood_value))
				draw_string(font, Vector2(point_x - 24.0, point_y + 15.0), mood_label, HORIZONTAL_ALIGNMENT_CENTER, 48, 7, label_color)
			else:
				points.append(Vector2.ZERO)
		if points.size() > 1:
			for index in range(points.size() - 1):
				if points[index] != Vector2.ZERO and points[index + 1] != Vector2.ZERO:
					draw_line(points[index], points[index + 1], line_color, 3.0, true)
		draw_line(Vector2(chart_rect.position.x, chart_rect.end.y), chart_rect.end, axis_color, 1.5)

	func _mood_value_for_date(date_dict: Dictionary) -> float:
		var target_date := "%04d-%02d-%02d" % [date_dict.year, date_dict.month, date_dict.day]
		var best_value := 0.0
		for entry in _entries.values():
			if not entry is Dictionary:
				continue
			var timestamp := str(entry.get("selected_at", entry.get("saved_at", "")))
			if not _timestamp_matches_date(timestamp, target_date):
				continue
			var mood := str(entry.get("mood", "")).strip_edges().to_lower()
			best_value = MOOD_VALUES.get(mood, 0.0)
		return best_value

	func _mood_label_for_value(mood_value: float) -> String:
		for mood in MOOD_VALUES:
			if is_equal_approx(float(MOOD_VALUES[mood]), mood_value):
				return str(mood).capitalize()
		return "Mood"

	func _mood_color_for_value(mood_value: float) -> Color:
		for mood in MOOD_VALUES:
			if is_equal_approx(float(MOOD_VALUES[mood]), mood_value):
				return MOOD_COLORS.get(mood, Color("#e7b24c"))
		return Color("#e7b24c")

	func _timestamp_matches_date(timestamp: String, target_date: String) -> bool:
		if timestamp.begins_with(target_date):
			return true
		if not timestamp.is_valid_float():
			return false
		var unix_time := timestamp.to_float()
		var date_dict := Time.get_date_dict_from_unix_time(int(unix_time))
		var actual_date := "%04d-%02d-%02d" % [date_dict.year, date_dict.month, date_dict.day]
		return actual_date == target_date