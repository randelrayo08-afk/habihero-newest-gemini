extends "res://shared_nav.gd"

var _mood_graph: Control

func _ready() -> void:
	super._ready()
	var close_button: Button = _find_button_by_text("CLOSE")
	if close_button != null:
		close_button.pressed.connect(_go_back)
	else:
		push_warning("Close button not found in My Progress scene.")
	_load_mood_history()

func _load_mood_history() -> void:
	_mood_graph = _MoodGraph.new()
	_mood_graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mood_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chart_panel: Control = get_node_or_null("Panel4/Panel") as Control
	if chart_panel == null:
		return
	chart_panel.add_child(_mood_graph)
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = str(_session.call("get_current_user_id"))
	if _auth_manager != null and _auth_manager.has_method("load_moodcheck_entries"):
		_auth_manager.load_moodcheck_entries(user_id, Callable(self, "_on_mood_history_loaded"))

func _on_mood_history_loaded(ok: bool, entries: Variant) -> void:
	if _mood_graph == null or not is_instance_valid(_mood_graph):
		return
	var mood_entries: Dictionary = entries if ok and entries is Dictionary else {}
	_mood_graph.call("set_entries", mood_entries)
	_render_mood_history(mood_entries)

func _render_mood_history(entries: Dictionary) -> void:
	var history_panel: Panel = get_node_or_null("Panel2") as Panel
	if history_panel == null:
		return
	history_panel.z_index = 4
	var summary_label := history_panel.get_node_or_null("BestMoodLabel") as Label
	if summary_label == null:
		summary_label = Label.new()
		summary_label.name = "BestMoodLabel"
		summary_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		summary_label.add_theme_color_override("font_color", Color("#40362f"))
		summary_label.add_theme_font_size_override("font_size", 12)
		summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		history_panel.add_child(summary_label)
	summary_label.text = _best_mood_summary(entries)

	var viewport: Panel = history_panel.get_node_or_null("Panel2") as Panel
	if viewport == null:
		return
	viewport.position = Vector2(-126.0, 71.0)
	viewport.size = Vector2(432.0, 252.0)
	viewport.clip_contents = true
	for child in viewport.get_children():
		child.queue_free()
	viewport.add_theme_stylebox_override("panel", _history_style(Color(1.0, 1.0, 1.0, 0.0), 24, 0))

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8.0
	scroll.offset_top = 8.0
	scroll.offset_right = -8.0
	scroll.offset_bottom = -8.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	viewport.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.x = 400.0
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	var records: Array[Dictionary] = []
	for entry in entries.values():
		if entry is Dictionary and not str(entry.get("mood", "")).strip_edges().is_empty():
			records.append(entry)
	records.sort_custom(Callable(self, "_sort_mood_records"))
	if records.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No mood check-ins yet."
		empty_label.add_theme_color_override("font_color", Color("#75685e"))
		list.add_child(empty_label)
		return
	for entry in records:
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0, 64)
		row.add_theme_stylebox_override("panel", _history_style(Color("#ffffff"), 16, 2))
		list.add_child(row)
		var row_content := HBoxContainer.new()
		row_content.add_theme_constant_override("separation", 8)
		row.add_child(row_content)
		var mood_dot := Label.new()
		mood_dot.text = "●"
		mood_dot.add_theme_color_override("font_color", _mood_color(str(entry.get("mood", ""))))
		mood_dot.add_theme_font_size_override("font_size", 22)
		mood_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row_content.add_child(mood_dot)
		var row_label := Label.new()
		var mood_name := str(entry.get("mood", "Mood")).capitalize()
		var note := str(entry.get("note", entry.get("notes", ""))).strip_edges()
		row_label.text = "%s, %s\n%s" % [_format_mood_date(entry), mood_name, note if not note.is_empty() else "Mood check-in recorded"]
		row_label.add_theme_color_override("font_color", Color("#40362f"))
		row_label.add_theme_font_size_override("font_size", 12)
		row_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_content.add_child(row_label)

func _history_style(background: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color("#7c6a5b")
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

func _best_mood_summary(entries: Dictionary) -> String:
	var best_mood := "No mood check-ins yet"
	var best_value: float = 0.0
	var best_date := ""
	var today := Time.get_date_dict_from_system()
	var today_unix := Time.get_unix_time_from_datetime_dict(today)
	var week_start_unix := today_unix - int(today.weekday) * 86400
	for entry in entries.values():
		if not entry is Dictionary:
			continue
		var timestamp := _mood_timestamp(entry)
		if timestamp.is_valid_float() and int(timestamp.to_float()) < week_start_unix:
			continue
		var mood := str(entry.get("mood", "")).strip_edges().to_lower()
		var mood_value: float = float(_MoodGraph.MOOD_VALUES.get(mood, 0.0))
		if mood_value > best_value:
			best_value = mood_value
			best_mood = mood.capitalize()
			best_date = _format_mood_weekday(entry)
	if best_date.is_empty():
		return best_mood
	return "You felt best on %s" % best_date

func _mood_color(mood: String) -> Color:
	return _MoodGraph.MOOD_COLORS.get(mood.strip_edges().to_lower(), Color("#8c8176"))

func _sort_mood_records(left: Dictionary, right: Dictionary) -> bool:
	return _mood_timestamp(left) > _mood_timestamp(right)

func _mood_timestamp(entry: Dictionary) -> String:
	return str(entry.get("selected_at", entry.get("saved_at", "")))

func _format_mood_date(entry: Dictionary) -> String:
	var timestamp := _mood_timestamp(entry)
	if timestamp.is_empty():
		return "Unknown date"
	if timestamp.is_valid_float():
		var date_dict := Time.get_date_dict_from_unix_time(int(timestamp.to_float()))
		var weekdays: Array[String] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
		var months: Array[String] = ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
		return "%s, %s %d" % [weekdays[date_dict.weekday], months[date_dict.month], date_dict.day]
	return timestamp.replace("T", " ").substr(0, 16)

func _format_mood_weekday(entry: Dictionary) -> String:
	var timestamp := _mood_timestamp(entry)
	var date_dict: Dictionary = {}
	if timestamp.is_valid_float():
		date_dict = Time.get_date_dict_from_unix_time(int(timestamp.to_float()))
	else:
		date_dict = Time.get_datetime_dict_from_datetime_string(timestamp, false)
		if not date_dict.has("weekday") and date_dict.has("year"):
			var parsed_unix: int = int(Time.get_unix_time_from_datetime_dict(date_dict))
			date_dict = Time.get_date_dict_from_unix_time(parsed_unix)
	var weekdays: Array[String] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	if date_dict.has("weekday") and int(date_dict.weekday) >= 0 and int(date_dict.weekday) < weekdays.size():
		return weekdays[int(date_dict.weekday)]
	return ""

class _MoodGraph extends Control:
	const MOOD_VALUES: Dictionary = {
		"worried": 1.0, "sad": 2.0, "angry": 3.0, "calm": 4.0,
		"curious": 5.0, "proud": 6.0, "excited": 7.0, "loved": 8.0, "happy": 9.0
	}
	const MOOD_COLORS: Dictionary = {
		"worried": Color("#7b61a8"), "sad": Color("#4f86c6"),
		"angry": Color("#d94b4b"), "calm": Color("#58a889"),
		"curious": Color("#35a9b7"), "proud": Color("#d67b32"),
		"excited": Color("#ef9b2d"), "loved": Color("#e579a5"),
		"happy": Color("#e7b24c")
	}
	var _entries: Dictionary = {}

	func set_entries(entries: Dictionary) -> void:
		_entries = entries
		queue_redraw()

	func _draw() -> void:
		var chart_rect := Rect2(22.0, 10.0, max(20.0, size.x - 44.0), max(20.0, size.y - 34.0))
		var font := ThemeDB.fallback_font
		for index in range(5):
			var y := chart_rect.position.y + chart_rect.size.y * float(index) / 4.0
			draw_line(Vector2(chart_rect.position.x, y), Vector2(chart_rect.end.x, y), Color(0.55, 0.50, 0.45, 0.20), 1.0)
		var today := Time.get_date_dict_from_system()
		var today_unix := Time.get_unix_time_from_datetime_dict(today)
		var week_start_unix := today_unix - int(today.weekday) * 86400
		var points: Array[Vector2] = []
		for day_index in range(7):
			var point := Vector2.ZERO
			if day_index <= int(today.weekday):
				var date_dict := Time.get_date_dict_from_unix_time(week_start_unix + day_index * 86400)
				var mood := _mood_for_date(date_dict)
				if not mood.is_empty():
					var mood_value: float = MOOD_VALUES[mood]
					point = Vector2(chart_rect.position.x + chart_rect.size.x * float(day_index) / 6.0, chart_rect.end.y - chart_rect.size.y * (mood_value - 1.0) / 8.0)
					draw_circle(point, 5.0, MOOD_COLORS[mood])
					draw_string(font, point + Vector2(-22.0, 16.0), mood.capitalize(), HORIZONTAL_ALIGNMENT_CENTER, 44, 7, Color("#5f5147"))
			points.append(point)
		for index in range(points.size() - 1):
			if points[index] != Vector2.ZERO and points[index + 1] != Vector2.ZERO:
				draw_line(points[index], points[index + 1], Color("#e7b24c"), 3.0, true)

	func _mood_for_date(date_dict: Dictionary) -> String:
		var target_date := "%04d-%02d-%02d" % [date_dict.year, date_dict.month, date_dict.day]
		var result := ""
		for entry in _entries.values():
			if not entry is Dictionary:
				continue
			var timestamp := str(entry.get("selected_at", entry.get("saved_at", "")))
			if timestamp.begins_with(target_date):
				result = str(entry.get("mood", "")).strip_edges().to_lower()
		return result if MOOD_VALUES.has(result) else ""

func _find_button_by_text(target_text: String) -> Button:
	for child in get_children():
		var button := child as Button
		if button != null and button.text == target_text:
			return button

		var nested_button: Button = _find_button_in_branch(child, target_text)
		if nested_button != null:
			return nested_button

	return null

func _find_button_in_branch(node: Node, target_text: String) -> Button:
	for child in node.get_children():
		var button := child as Button
		if button != null and button.text == target_text:
			return button

		var nested_button: Button = _find_button_in_branch(child, target_text)
		if nested_button != null:
			return nested_button

	return null

func _go_back() -> void:
	var previous_scene: String = _previous_scene_from_history()
	if previous_scene.is_empty():
		previous_scene = "res://progress.tscn"
	_change_scene_to_file(previous_scene)

func _previous_scene_from_history() -> String:
	var history: Node = _resolve_history()
	if history != null and history.has_method("get_previous_scene"):
		return history.get_previous_scene()
	return ""

func _resolve_history() -> Node:
	if get_tree() != null and get_tree().root != null:
		var history: Node = get_tree().root.get_node_or_null("NavigationHistory")
		if history != null:
			return history
	if Engine.has_singleton("NavigationHistory"):
		return Engine.get_singleton("NavigationHistory")
	return null

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
