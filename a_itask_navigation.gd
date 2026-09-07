extends Control

var proof_image_path: String = ""
var _proof_image_source: String = ""
var _previous_response_text: String = ""
var _completion_in_progress: bool = false
var current_character: AnimatedSprite2D = null
var character_animation_state: String = "idle"  # idle, listening, talking
var _talking_timer: Timer = null  # Timer for automatic idle transition
var _mic_release_timer: Timer = null  # Timer for mic button release transition
var _mic_inactivity_timer: Timer = null # Timer to auto-return to idle if mic unused
var _mic_active: bool = false

func _ready() -> void:
	var selected_task: String = ""
	var estimated_time: String = "15 mins."
	var difficulty: String = "Easy"
	var category: String = "Academic"

	if get_tree().root.has_meta("selected_task_data"):
		var selected_task_data: Dictionary = get_tree().root.get_meta("selected_task_data") as Dictionary
		if selected_task_data != null:
			if selected_task_data.has("title"):
				selected_task = str(selected_task_data["title"])
			if selected_task_data.has("estimated_time"):
				estimated_time = str(selected_task_data["estimated_time"])
			if selected_task_data.has("difficulty"):
				difficulty = str(selected_task_data["difficulty"])
			if selected_task_data.has("category"):
				category = str(selected_task_data["category"])

	if selected_task == "" and get_tree().root.has_meta("selected_task"):
		selected_task = str(get_tree().root.get_meta("selected_task"))

	var objective_value_label: Label = get_node_or_null("Panel2/Panel2/ObjectiveValue") as Label
	if objective_value_label != null:
		objective_value_label.text = "Quest Details"

	var objective_line_label: Label = get_node_or_null("Panel2/Panel2/ObjectiveLine") as Label
	if objective_line_label != null:
		if selected_task != "":
			objective_line_label.text = "Objective: %s" % selected_task
		else:
			objective_line_label.text = "Objective: Select a task from Home."

	var category_badge: Label = get_node_or_null("Panel2/CategoryBadgePanel/CategoryBadge") as Label
	if category_badge == null:
		category_badge = get_node_or_null("Panel2/CategoryBadge") as Label
	var title_label: Label = get_node_or_null("Panel2/TitleLabel") as Label

	var estimated_time_label: Label = get_node_or_null("Panel2/Panel2/EstimatedTimeLabel") as Label
	var difficulty_label: Label = get_node_or_null("Panel2/Panel2/DifficultyLabel") as Label
	var category_label: Label = get_node_or_null("Panel2/Panel2/CategoryLabel") as Label
	var reward_coins_label: Label = get_node_or_null("Panel2/Panel4/RewardCoinsLabel") as Label
	var reward_exp_label: Label = get_node_or_null("Panel2/Panel4/RewardEXPLabel") as Label
	var response_text: TextEdit = get_node_or_null("Panel2/Panel3/TextEdit") as TextEdit
	var response_char_count: Label = get_node_or_null("Panel2/Panel3/TextEdit/Label") as Label
	var proof_image_label: Label = get_node_or_null("Panel2/Panel3/ProofImageLabel") as Label

	if selected_task != "" and not get_tree().root.has_meta("selected_task_data"):
		var lower_task = selected_task.to_lower()
		if lower_task.find("pray") != -1 or lower_task.find("bible") != -1 or lower_task.find("verse") != -1 or lower_task.find("church") != -1 or lower_task.find("worship") != -1:
			estimated_time = "10 mins."
			difficulty = "Easy"
			category = "Religion"
		elif lower_task.find("read") != -1 or lower_task.find("study") != -1 or lower_task.find("learn") != -1 or lower_task.find("write") != -1:
			estimated_time = "15 mins."
			difficulty = "Easy"
			category = "Academic"
		elif lower_task.find("serve") != -1 or lower_task.find("help") != -1 or lower_task.find("share") != -1:
			estimated_time = "20 mins."
			difficulty = "Medium"
			category = "Service"

	if estimated_time_label != null:
		estimated_time_label.text = "Estimated Time: %s" % estimated_time
	if difficulty_label != null:
		difficulty_label.text = "Difficulty: %s" % difficulty
	if category_label != null:
		category_label.text = "Category: %s" % category
	# Populate rewards (coins and exp) if available
	if reward_coins_label != null or reward_exp_label != null:
		var coins_text: String = ""
		var exp_text: String = ""
		if get_tree().root.has_meta("selected_task_data"):
			var sel: Dictionary = get_tree().root.get_meta("selected_task_data") as Dictionary
			if sel != null:
				var reward_coins: int = max(0, int(sel.get("coins", sel.get("reward_coins", 0))))
				var reward_exp: int = max(0, int(sel.get("exp", sel.get("xp", sel.get("experience", 0)))))
				if reward_coins > 0 or sel.has("coins") or sel.has("reward_coins"):
					coins_text = str(reward_coins) + " coins"
				if reward_exp > 0 or sel.has("exp") or sel.has("xp") or sel.has("experience"):
					exp_text = str(reward_exp) + " exp"
		# defaults if none provided
		if coins_text == "":
			coins_text = "5 coins"
		if exp_text == "":
			exp_text = "25 exp"
		if reward_coins_label != null:
			reward_coins_label.text = coins_text
		if reward_exp_label != null:
			reward_exp_label.text = exp_text

	# Populate top title/subtitle/category badge
	if title_label != null:
		title_label.text = selected_task if selected_task != "" else "Select a task from Home."

	if response_text != null and response_char_count != null:
		_update_response_char_count(response_text, response_char_count)
		var callback: Callable = Callable(self, "_on_response_text_changed")
		if not response_text.is_connected("text_changed", callback):
			response_text.text_changed.connect(callback)
		response_text.placeholder_text = "Describe what you did on the task or attach a photo"

	if proof_image_label == null:
		proof_image_label = Label.new()
		proof_image_label.name = "ProofImageLabel"
		if response_char_count != null:
			var proof_font = response_char_count.get("theme_override_fonts/font")
			if proof_font != null:
				proof_image_label.add_theme_font_override("font", proof_font)
		proof_image_label.set("theme_override_font_sizes/font_size", 10)
		proof_image_label.horizontal_alignment = 0 as HorizontalAlignment
		proof_image_label.valign = 1 as VerticalAlignment
		proof_image_label.text = ""
		var panel3 = get_node_or_null("Panel2/Panel3")
		if panel3 != null:
			panel3.add_child(proof_image_label)

	_update_proof_image_label(proof_image_label)
	_setup_proof_buttons()
	_setup_proof_file_dialog()

	if category_badge != null:
		var lower_cat: String = category.to_lower()
		if lower_cat.find("relig") != -1 or lower_cat.find("worship") != -1 or lower_cat.find("church") != -1:
			category_badge.text = "RELIGION"
		elif lower_cat.find("academic") != -1 or lower_cat.find("education") != -1 or lower_cat.find("study") != -1 or lower_cat.find("read") != -1:
			category_badge.text = "ACADEMIC"
		elif lower_cat.find("service") != -1 or lower_cat.find("help") != -1 or lower_cat.find("share") != -1:
			category_badge.text = "SERVICE"
		elif lower_cat.find("health") != -1 or lower_cat.find("exercise") != -1 or lower_cat.find("fitness") != -1:
			category_badge.text = "HEALTH"
		else:
			category_badge.text = category.to_upper()

	var badge_panel: Panel = get_node_or_null("Panel2/CategoryBadgePanel") as Panel
	if badge_panel != null:
		var lower_cat: String = category.to_lower()
		var panel_style: StyleBoxFlat = StyleBoxFlat.new()
		panel_style.corner_radius_top_left = 10
		panel_style.corner_radius_top_right = 10
		panel_style.corner_radius_bottom_right = 10
		panel_style.corner_radius_bottom_left = 10
		panel_style.border_width_top = 0
		panel_style.border_width_left = 0
		panel_style.border_width_right = 0
		panel_style.border_width_bottom = 0
		if lower_cat.find("academic") != -1:
			panel_style.bg_color = Color(0.2, 0.4, 0.8, 1)
			badge_panel.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		elif lower_cat.find("education") != -1:
			panel_style.bg_color = Color(0.8, 0.3, 0.1, 1)
			badge_panel.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		elif lower_cat.find("service") != -1:
			panel_style.bg_color = Color(0.9, 0.55, 0.1, 1)
			badge_panel.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		elif lower_cat.find("health") != -1:
			panel_style.bg_color = Color(0.2, 0.6, 0.2, 1)
			badge_panel.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		elif lower_cat.find("relig") != -1 or lower_cat.find("liturgical") != -1:
			panel_style.bg_color = Color(0.8, 0.1, 0.1, 1)
			badge_panel.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		else:
			panel_style.bg_color = Color(0.7, 0.7, 0.7, 1)
			badge_panel.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		badge_panel.set("theme_override_styles/panel", panel_style)

	# Set header icon based on category
	var header_icon: TextureRect = get_node_or_null("Panel2/HeaderIcon") as TextureRect
	if header_icon != null:
		var tex_path: String = "res://book.png"
		var lower_cat: String = category.to_lower()
		if lower_cat.find("relig") != -1:
			tex_path = "res://bible.png"
		elif lower_cat.find("academic") != -1 or lower_cat.find("read") != -1:
			tex_path = "res://open-book.png"
		elif lower_cat.find("health") != -1:
			tex_path = "res://basketball.png"
		# try to load texture, fall back to book
		var tex: Texture = null
		if ResourceLoader.exists(tex_path):
			tex = load(tex_path)
		if tex == null:
			if ResourceLoader.exists("res://book.png"):
				tex = load("res://book.png")
		header_icon.texture = tex

	var submit_button: Button = get_node_or_null("Button2") as Button
	if submit_button != null:
		if not submit_button.pressed.is_connected(Callable(self, "_on_submit_pressed")):
			submit_button.pressed.connect(Callable(self, "_on_submit_pressed"))
	else:
		push_warning("A_ITask navigation: submit button not found")

	var back_button: Button = get_node_or_null("BACKBTN") as Button
	if back_button != null:
		if not back_button.pressed.is_connected(Callable(self, "_on_back_pressed")):
			back_button.pressed.connect(Callable(self, "_on_back_pressed"))
	else:
		push_warning("A_ITask navigation: back button not found")

	# Ensure labels wrap and resize after layout to avoid runtime overflow
	call_deferred("_adjust_label_sizes")
	# Load character after UI is set up to prevent shifting
	call_deferred("_load_character_by_gender")
	# Wire mic button for listening/talking animation flow
	call_deferred("_setup_mic_button")

func _on_response_text_changed() -> void:
	var response_text: TextEdit = get_node_or_null("Panel2/Panel3/TextEdit") as TextEdit
	var response_char_count: Label = get_node_or_null("Panel2/Panel3/TextEdit/Label") as Label
	if response_text != null and response_char_count != null:
		_update_response_char_count(response_text, response_char_count)

func _update_response_char_count(response_text: TextEdit, response_char_count: Label) -> void:
	var text_value: String = response_text.text
	var count: int = text_value.length()
	if count > 300:
		response_text.text = _previous_response_text
		count = _previous_response_text.length()
	else:
		_previous_response_text = text_value

	response_char_count.text = "%d/300" % count
	if count >= 300:
		response_char_count.add_theme_color_override("font_color", Color(1, 0, 0, 1))
	else:
		response_char_count.add_theme_color_override("font_color", Color(0.21176471, 0.14509805, 0.03529412, 1))

func _on_submit_pressed() -> void:
	if _completion_in_progress:
		return
	var response_text: TextEdit = get_node_or_null("Panel2/Panel3/TextEdit") as TextEdit
	if response_text == null:
		push_warning("Submit action failed: response text box missing")
		return

	var text_value: String = response_text.text.strip_edges()
	if text_value == "" and proof_image_path == "":
		push_warning("Please enter proof text or attach a photo before submitting.")
		return
	_completion_in_progress = true
	var submit_button: Button = get_node_or_null("Button2") as Button
	if submit_button != null:
		submit_button.disabled = true

	if text_value.length() > 300:
		text_value = text_value.substr(0, 300)
		response_text.text = text_value

	var submission_data: Dictionary = {}
	if get_tree().root.has_meta("selected_task_data"):
		var selected_task_data: Dictionary = get_tree().root.get_meta("selected_task_data") as Dictionary
		if selected_task_data != null:
			submission_data = selected_task_data

	var task_id: String = ""
	if submission_data.has("id"):
		task_id = str(submission_data["id"])
	if task_id.strip_edges().is_empty():
		var title_key := str(submission_data.get("title", "task")).strip_edges().to_lower()
		task_id = "generated_%s" % str(abs(title_key.hash()))
		submission_data["id"] = task_id
	print("A_ITask navigation: resolved task_id=", task_id, "submission_data=", submission_data)

	submission_data["proof_text"] = text_value
	if proof_image_path != "":
		submission_data["proof_image_path"] = proof_image_path
	submission_data["submitted"] = true
	get_tree().root.set_meta("selected_task_data", submission_data)

	var auth_manager: Node = _resolve_auth_manager()
	if auth_manager == null or not auth_manager.has_method("complete_task_and_award_rewards"):
		_on_task_completion_finished(false, "FirebaseAuthManager completion service unavailable")
		return
	var proof_payload: Dictionary = {}
	if text_value != "":
		proof_payload["proofText"] = text_value
	if proof_image_path != "":
		proof_payload["proofImagePath"] = proof_image_path
	proof_payload["scene"] = "tasks"
	auth_manager.complete_task_and_award_rewards(_get_current_user_id(), submission_data, proof_payload, Callable(self, "_on_task_completion_finished"))
	print("Task proof submitted:", text_value)

func _on_task_completion_finished(success: bool, data: Variant) -> void:
	if not success:
		_completion_in_progress = false
		var submit_button: Button = get_node_or_null("Button2") as Button
		if submit_button != null:
			submit_button.disabled = false
		push_warning("Task completion failed: %s" % str(data))
		return
	print("A_ITask navigation: task completion and rewards succeeded: ", data)
	var tree: SceneTree = get_tree()
	if tree != null and tree.has_method("change_scene_to_file"):
		tree.change_scene_to_file("res://home.tscn")

func _resolve_auth_manager() -> Node:
	if get_tree() != null and get_tree().root != null:
		var auth_manager: Node = get_tree().root.get_node_or_null("FirebaseAuthManager") as Node
		if auth_manager != null:
			return auth_manager
	if Engine.has_singleton("FirebaseAuthManager"):
		return Engine.get_singleton("FirebaseAuthManager") as Node
	return null

func _resolve_backend() -> Node:
	if get_tree() != null and get_tree().root != null:
		var backend: Node = get_tree().root.get_node_or_null("HabiBackend") as Node
		if backend != null:
			return backend
	if Engine.has_singleton("HabiBackend"):
		return Engine.get_singleton("HabiBackend") as Node
	return null

func _on_back_pressed() -> void:
	var tree: SceneTree = get_tree()
	if tree.has_method("change_scene_to_file"):
		tree.change_scene_to_file("res://home.tscn")
	elif tree.has_method("change_scene_to_packed"):
		var home_scene: Resource = load("res://home.tscn")
		if home_scene is PackedScene:
			tree.change_scene_to_packed(home_scene)
		else:
			push_error("Failed to load home.tscn as PackedScene")
	else:
		push_error("SceneTree change scene method unavailable")

func _on_task_marked_complete(success: bool, data: Variant) -> void:
	if success:
		print("A_ITask navigation: task marked complete")
	else:
		print("A_ITask navigation: failed to mark task complete: %s" % str(data))

func _setup_proof_buttons() -> void:
	var attach_button: Button = get_node_or_null("Panel2/AttachButton") as Button
	if attach_button != null:
		if not attach_button.pressed.is_connected(Callable(self, "_on_attach_file_pressed")):
			attach_button.pressed.connect(Callable(self, "_on_attach_file_pressed"))
	else:
		push_warning("A_ITask navigation: attach file button not found")

	var photo_button: Button = get_node_or_null("Panel2/TakePhotoButton") as Button
	if photo_button != null:
		if not photo_button.pressed.is_connected(Callable(self, "_on_take_photo_pressed")):
			photo_button.pressed.connect(Callable(self, "_on_take_photo_pressed"))
	else:
		push_warning("A_ITask navigation: take photo button not found")

func _setup_proof_file_dialog() -> void:
	var dialog: FileDialog = get_node_or_null("ProofFileDialog") as FileDialog
	if dialog == null:
		dialog = FileDialog.new()
		dialog.name = "ProofFileDialog"
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.set_title("Select an image")
		dialog.current_path = "user://"
		dialog.add_filter("*.png ; PNG Images")
		dialog.add_filter("*.jpg ; JPEG Images")
		dialog.add_filter("*.jpeg ; JPEG Images")
		dialog.add_filter("*.webp ; WebP Images")
		dialog.connect("file_selected", Callable(self, "_on_proof_file_selected"))
		add_child(dialog)

func _on_attach_file_pressed() -> void:
	_proof_image_source = "attach"
	var dialog: FileDialog = get_node_or_null("ProofFileDialog") as FileDialog
	if dialog != null:
		dialog.popup_centered_ratio()

func _on_take_photo_pressed() -> void:
	# On desktop this uses file selection as a substitute for camera input.
	_proof_image_source = "photo"
	var dialog: FileDialog = get_node_or_null("ProofFileDialog") as FileDialog
	if dialog != null:
		dialog.popup_centered_ratio()

func _on_proof_file_selected(path: String) -> void:
	if not _is_image_file(path):
		push_warning("Selected file is not a supported image. Please choose a PNG, JPG, JPEG, or WEBP file.")
		return
	proof_image_path = path
	var proof_image_label: Label = get_node_or_null("Panel2/Panel3/ProofImageLabel") as Label
	_update_proof_image_label(proof_image_label)
	_update_attachment_button_styles()

func _is_image_file(path: String) -> bool:
	var lower_path: String = path.to_lower()
	return lower_path.ends_with(".png") or lower_path.ends_with(".jpg") or lower_path.ends_with(".jpeg") or lower_path.ends_with(".webp")

func _update_proof_image_label(proof_image_label: Label) -> void:
	if proof_image_label == null:
		return
	if proof_image_path == "":
		proof_image_label.text = ""
		return
	var filename: String = proof_image_path.get_file()
	proof_image_label.text = "Attached image: %s" % filename

func _update_attachment_button_styles() -> void:
	var attach_button: Button = get_node_or_null("Panel2/AttachButton") as Button
	var photo_button: Button = get_node_or_null("Panel2/TakePhotoButton") as Button
	if attach_button != null:
		_set_button_glow(attach_button, proof_image_path != "" and _proof_image_source == "attach")
	if photo_button != null:
		_set_button_glow(photo_button, proof_image_path != "" and _proof_image_source == "photo")

func _set_button_glow(button: Button, active: bool) -> void:
	if button == null:
		return
	if active:
		var glow_style: StyleBoxFlat = StyleBoxFlat.new()
		glow_style.bg_color = Color(0.0, 0.5, 0.1, 0.7)
		glow_style.border_width_top = 2
		glow_style.border_width_left = 2
		glow_style.border_width_right = 2
		glow_style.border_width_bottom = 2
		glow_style.border_color = Color(0.5, 1, 0.5, 1)
		glow_style.corner_radius_top_left = 8
		glow_style.corner_radius_top_right = 8
		glow_style.corner_radius_bottom_right = 8
		glow_style.corner_radius_bottom_left = 8
		button.set("theme_override_styles/normal", glow_style)
		button.set("theme_override_styles/hover", glow_style)
		button.set("theme_override_styles/pressed", glow_style)
		return

	button.set("theme_override_styles/normal", null)
	button.set("theme_override_styles/hover", null)
	button.set("theme_override_styles/pressed", null)

func _get_current_user_id() -> String:
	var session = get_tree().root.get_node_or_null("UserSession")
	if session == null and Engine.has_singleton("UserSession"):
		session = Engine.get_singleton("UserSession")
	if session != null:
		if session.has_method("get_current_user_id"):
			var uid: String = str(session.call("get_current_user_id")).strip_edges()
			if not uid.is_empty():
				return uid

	if Engine.has_singleton("FirebaseAuthManager"):
		var auth = Engine.get_singleton("FirebaseAuthManager")
		if auth != null and auth.has_method("get_current_user"):
			var user = auth.call("get_current_user")
			if user != null and user is Dictionary and user.has("uid"):
				var uid_auth: String = str(user["uid"]).strip_edges()
				if not uid_auth.is_empty():
					return uid_auth

	return "guest_user"

func _adjust_label_sizes() -> void:
	var title_label: Label = get_node_or_null("Panel2/TitleLabel") as Label
	var objective_line_label: Label = get_node_or_null("Panel2/Panel2/ObjectiveLine") as Label

	if title_label != null:
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		title_label.clip_text = false
		var min_title = title_label.get_minimum_size()
		if min_title.y > 0:
			var cur = title_label.custom_minimum_size
			title_label.custom_minimum_size = Vector2(cur.x, min_title.y)

	if objective_line_label != null:
		objective_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		objective_line_label.clip_text = false
		var min_obj = objective_line_label.get_minimum_size()
		if min_obj.y > 0:
			var cur2 = objective_line_label.custom_minimum_size
			objective_line_label.custom_minimum_size = Vector2(cur2.x, min_obj.y)

# Character loading and animation management
func _load_character_by_gender() -> void:
	var character_container: Control = get_node_or_null("CharacterContainer") as Control
	if character_container == null:
		push_warning("CharacterContainer not found in scene")
		return
	
	# Determine gender
	var gender: String = _get_user_gender()
	if gender.is_empty():
		gender = "boy"  # Default to boy if no gender found
	
	# Load appropriate character scene (CORRECT PATHS - in root directory)
	var character_scene_path: String = ""
	if gender == "girl":
		character_scene_path = "res://IDLE.tscn"
	else:
		character_scene_path = "res://IDLE_BOY.tscn"
	
	var character_scene = load(character_scene_path)
	if character_scene == null:
		push_error("Failed to load character scene: %s" % character_scene_path)
		return
	
	# Instantiate and add to container
	var scene_root: Node = character_scene.instantiate()
	if scene_root == null:
		push_error("Failed to instantiate character scene")
		return
	
	# Try to get AnimatedSprite2D from the scene
	if scene_root is AnimatedSprite2D:
		current_character = scene_root as AnimatedSprite2D
	else:
		# Look for AnimatedSprite2D child
		current_character = scene_root.find_child("*", true, false) as AnimatedSprite2D
		if current_character == null:
			push_error("Could not find AnimatedSprite2D in character scene: %s" % character_scene_path)
			scene_root.queue_free()
			return
	
	character_container.add_child(scene_root)
	
	# Center the character in the container
	current_character.position = Vector2(100, 100)  # Center of 200x200 container
	current_character.scale = Vector2(1.5, 1.5)  # Consistent scale for all animations
	
	# Play idle animation
	if current_character.sprite_frames != null:
		current_character.play("default")
		current_character.autoplay = "default"
	
	character_animation_state = "idle"
	print("Character loaded: %s" % character_scene_path)

func _get_user_gender() -> String:
	# Check if gender is stored in tree metadata
	if get_tree().root.has_meta("selected_gender"):
		return str(get_tree().root.get_meta("selected_gender")).to_lower()
	
	# Check for question answers
	if get_tree().root.has_meta("question_answers"):
		var answers: Dictionary = get_tree().root.get_meta("question_answers") as Dictionary
		for key in answers.keys():
			if key.contains("gender") or key.contains("character"):
				var value = str(answers[key]).to_lower()
				if value in ["boy", "girl"]:
					return value
	
	return ""  # Return empty string to use default

func change_character_animation(state: String, duration_seconds: float = 0.0) -> void:
	"""
	Change character animation state. Sequence: 'idle' -> 'listening' -> 'talking' -> 'idle'
	"""
	if current_character == null:
		return
	
	character_animation_state = state
	var gender: String = _get_user_gender()
	if gender.is_empty():
		gender = "boy"
	
	var new_character_scene_path: String = ""
	
	match state:
		"idle":
			if gender == "girl":
				new_character_scene_path = "res://IDLE.tscn"
			else:
				new_character_scene_path = "res://IDLE_BOY.tscn"
		"listening":
			if gender == "girl":
				new_character_scene_path = "res://listening.tscn"
			else:
				new_character_scene_path = "res://listening_BOY.tscn"
		"talking":
			if gender == "girl":
				new_character_scene_path = "res://talking.tscn"
			else:
				new_character_scene_path = "res://talkin_boy.tscn"
	
	if new_character_scene_path.is_empty():
		return
	
	# Load new scene
	var new_character_scene = load(new_character_scene_path)
	if new_character_scene == null:
		push_error("Failed to load character scene: %s" % new_character_scene_path)
		return
	
	# Get character container
	var character_container: Control = get_node_or_null("CharacterContainer") as Control
	if character_container == null:
		return
	
	# Remove old character
	if current_character != null:
		current_character.queue_free()
	
	# Instantiate and add new character
	current_character = new_character_scene.instantiate() as AnimatedSprite2D
	if current_character == null:
		push_error("Instantiated character is not an AnimatedSprite2D")
		return
	
	character_container.add_child(current_character)
	
	# Position and scale consistently - center in 200x200 container
	current_character.position = Vector2(100, 100)
	current_character.scale = Vector2(1.5, 1.5)
	
	_play_animation_state_for_sprite(current_character, state)
	
	print("Character animation changed to: %s" % state)
	
	if state == "talking" and duration_seconds > 0:
		_setup_auto_idle_transition(duration_seconds)

func get_character_animation_state() -> String:
	"""Get the current character animation state"""
	return character_animation_state

func _setup_auto_idle_transition(duration_seconds: float) -> void:
	"""Automatically transition character back to idle after specified duration"""
	# Kill existing timer if any
	if _talking_timer != null:
		_talking_timer.queue_free()
		_talking_timer = null
	
	# Create new timer for auto-idle transition
	_talking_timer = Timer.new()
	add_child(_talking_timer)
	_talking_timer.wait_time = duration_seconds
	_talking_timer.one_shot = true
	_talking_timer.timeout.connect(Callable(self, "_on_talking_completed"))
	_talking_timer.start()

func _on_talking_completed() -> void:
	"""Called when AI finishes talking - automatically return to idle"""
	if _talking_timer != null:
		_talking_timer.queue_free()
		_talking_timer = null
	
	# Automatically return to idle
	if character_animation_state == "talking":
		change_character_animation("idle")
		print("AI finished talking, returning to idle")

func _setup_mic_button() -> void:
	"""Wire the mic button for listening/talking animation flow"""
	var mic_button: Button = get_node_or_null("MicButton") as Button
	if mic_button == null:
		push_warning("MicButton not found in scene")
		return
	
	# Connect button signals
	if not mic_button.button_down.is_connected(Callable(self, "_on_mic_button_down")):
		mic_button.button_down.connect(Callable(self, "_on_mic_button_down"))
	if not mic_button.button_up.is_connected(Callable(self, "_on_mic_button_up")):
		mic_button.button_up.connect(Callable(self, "_on_mic_button_up"))
	
	print("Mic button wired for character animations")

func _on_mic_button_down() -> void:
	"""Called when user presses the mic button - start listening animation"""
	print("Mic button pressed - starting listening")
	# Kill any pending mic release timer
	if _mic_release_timer != null:
		_mic_release_timer.queue_free()
		_mic_release_timer = null
	# Enter listening state and mark mic active
	_mic_active = true
	change_character_animation("listening")

	# Reset/start inactivity timer - if no AI or further interaction in 3s, return to idle
	if _mic_inactivity_timer != null:
		_mic_inactivity_timer.queue_free()
		_mic_inactivity_timer = null
	_mic_inactivity_timer = Timer.new()
	add_child(_mic_inactivity_timer)
	_mic_inactivity_timer.wait_time = 3.0
	_mic_inactivity_timer.one_shot = true
	_mic_inactivity_timer.timeout.connect(Callable(self, "_on_mic_inactivity_timeout"))
	_mic_inactivity_timer.start()

func _on_mic_button_up() -> void:
	"""Called when user releases the mic button - transition to talking after brief delay"""
	print("Mic button released - waiting for AI response")
	# Mark mic inactive; keep listening until AI starts talking or inactivity timer elapses
	_mic_active = false
	# reset/start inactivity timer to ensure we don't stay listening forever
	if _mic_inactivity_timer != null:
		_mic_inactivity_timer.queue_free()
		_mic_inactivity_timer = null
	_mic_inactivity_timer = Timer.new()
	add_child(_mic_inactivity_timer)
	_mic_inactivity_timer.wait_time = 3.0
	_mic_inactivity_timer.one_shot = true
	_mic_inactivity_timer.timeout.connect(Callable(self, "_on_mic_inactivity_timeout"))
	_mic_inactivity_timer.start()

func _on_mic_release_transition() -> void:
	"""Transition from listening to talking after mic button released"""
	if _mic_release_timer != null:
		_mic_release_timer.queue_free()
		_mic_release_timer = null
	print("Mic release transition deprecated; waiting for AI to speak or inactivity timeout")
	if _mic_inactivity_timer == null:
		_mic_inactivity_timer = Timer.new()
		add_child(_mic_inactivity_timer)
		_mic_inactivity_timer.wait_time = 3.0
		_mic_inactivity_timer.one_shot = true
		_mic_inactivity_timer.timeout.connect(Callable(self, "_on_mic_inactivity_timeout"))
		_mic_inactivity_timer.start()

	return

func _on_mic_inactivity_timeout() -> void:
	"""Called when mic is inactive for a while; return to idle to avoid stale listening state."""
	if _mic_inactivity_timer != null:
		_mic_inactivity_timer.queue_free()
		_mic_inactivity_timer = null
	# Only transition to idle if we are currently in listening and AI is not talking
	if character_animation_state == "listening":
		change_character_animation("idle")
		print("Mic inactivity timeout: returning to idle")

func on_ai_started_talking() -> void:
	"""External hook: call this when AI begins speaking. Switch to talking immediately."""
	print("AI started talking (a_itask): switching to talking animation")
	# cancel inactivity timer
	if _mic_inactivity_timer != null:
		_mic_inactivity_timer.queue_free()
		_mic_inactivity_timer = null
	# cancel mic release timer
	if _mic_release_timer != null:
		_mic_release_timer.queue_free()
		_mic_release_timer = null
	# Switch to talking; let talking handler auto-return to idle when done
	change_character_animation("talking")

func on_ai_stopped_talking() -> void:
	"""External hook: call this when AI finishes speaking. Auto-return to idle after 3s."""
	print("AI stopped talking (a_itask): scheduling return to idle in 3s")
	# Ensure we return to idle after 3 seconds if no further conversation
	_setup_auto_idle_transition(3.0)

func _play_animation_state_for_sprite(sprite: AnimatedSprite2D, state: String) -> void:
	if sprite == null:
		return
	if sprite.sprite_frames == null:
		if sprite.has_animation("default"):
			sprite.play("default")
		return
	if sprite.sprite_frames.has_animation(state):
		sprite.play(state)
		return
	if state == "idle" and sprite.sprite_frames.has_animation("default"):
		sprite.play("default")
		return
	if state == "listening" and sprite.sprite_frames.has_animation("listen"):
		sprite.play("listen")
		return
	if state == "talking" and sprite.sprite_frames.has_animation("talk"):
		sprite.play("talk")
		return
	if sprite.sprite_frames.has_animation("default"):
		sprite.play("default")
		return
	if sprite.get_animation() != "":
		sprite.play()
		return
