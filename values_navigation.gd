extends Control
# Values Navigation - Manages the daily value lesson scene.

const DAILY_VALUES: Array = [
	{
		"title": "RESPECT",
		"description": "Respect means treating everyone with kindness, listening carefully, and valuing others even when they are different from us.",
		"reflection": "How did you show respect today?",
		"challenges": [
			"Listen without interrupting when a classmate speaks.",
			"Use polite and encouraging words in group work.",
			"Include someone in a game or activity today."
		]
	},
	{
		"title": "HONESTY",
		"description": "Honesty means telling the truth, being accountable, and choosing to do what is right even when no one is watching.",
		"reflection": "When did you choose honesty today?",
		"challenges": [
			"Tell the truth even when it is difficult.",
			"Own up to one mistake and fix it.",
			"Share the truth kindly without blaming others."
		]
	},
	{
		"title": "KINDNESS",
		"description": "Kindness is noticing the needs of others and showing care through your words, actions, and attitude.",
		"reflection": "How did you show kindness to someone today?",
		"challenges": [
			"Say one kind compliment to someone today.",
			"Help a classmate without being asked.",
			"Use gentle words when speaking to others."
		]
	},
	{
		"title": "RESPONSIBILITY",
		"description": "Responsibility means taking care of your tasks, your choices, and the people around you with maturity and follow-through.",
		"reflection": "What responsibility did you do today?",
		"challenges": [
			"Finish one task before playing or resting.",
			"Put your materials back where they belong.",
			"Take care of a responsibility without being reminded."
		]
	},
	{
		"title": "EMPATHY",
		"description": "Empathy means trying to understand how someone else feels and responding with patience, care, and understanding.",
		"reflection": "How did you practice empathy today?",
		"challenges": [
			"Notice how someone feels and ask if they are okay.",
			"Listen carefully without rushing to judge.",
			"Support someone who is feeling sad or left out."
		]
	},
	{
		"title": "GRATITUDE",
		"description": "Gratitude helps us notice what is good, appreciate people, and grow thankful for the blessings around us.",
		"reflection": "What are you grateful for today?",
		"challenges": [
			"Thank one person who helped you today.",
			"Notice one good thing in your classroom or home.",
			"Share appreciation for something you used today."
		]
	},
	{
		"title": "PERSEVERANCE",
		"description": "Perseverance means continuing to try your best even when a task is hard, and not giving up after a mistake or setback.",
		"reflection": "What did you keep trying at today, even when it was hard?",
		"challenges": [
			"Try a difficult task again instead of giving up.",
			"Encourage a classmate who is struggling with something.",
			"Finish something you started, even if it takes extra effort."
		]
	},
	{
		"title": "GENEROSITY",
		"description": "Generosity means willingly sharing your time, belongings, or attention with others without expecting anything in return.",
		"reflection": "How did you share with or give to someone today?",
		"challenges": [
			"Share a material or snack with someone today.",
			"Give your full attention and time to help a classmate.",
			"Offer to share credit or spotlight with a teammate."
		]
	},
	{
		"title": "HUMILITY",
		"description": "Humility means recognizing your strengths without bragging, and being willing to learn from others and admit when you're wrong.",
		"reflection": "How did you show humility today?",
		"challenges": [
			"Let a classmate go first or take the lead today.",
			"Accept feedback or correction without arguing.",
			"Celebrate someone else's success as much as your own."
		]
	},
	{
		"title": "COURAGE",
		"description": "Courage means doing what is right or trying something new even when you feel scared, nervous, or unsure.",
		"reflection": "When did you show courage today?",
		"challenges": [
			"Speak up for someone who is being treated unfairly.",
			"Try something new even if you're afraid to fail.",
			"Say sorry or admit a mistake, even if it's hard."
		]
	}
]

var _auth_manager: Node
var _session: Node
var _current_user_id: String = ""
var _reflection_button: Button
var _back_button: Button

func _ready() -> void:
	_auth_manager = _resolve_auth_manager()
	_session = _resolve_session()
	_current_user_id = _get_current_user_id()
	
	_reflection_button = get_node_or_null("Panel/Panel4/Button")
	if _reflection_button == null:
		_reflection_button = _find_button_by_label("REFLECTION")
	
	_back_button = get_node_or_null("Button")
	if _back_button == null:
		_back_button = _find_button_by_label("Back")
	
	if _reflection_button != null:
		_reflection_button.pressed.connect(_on_reflection_button_pressed)
		print("Values: Reflection button connected")
	else:
		print("Values: Reflection button not found")
	
	if _back_button != null:
		_back_button.pressed.connect(_on_back_button_pressed)
		print("Values: Back button connected")
	else:
		print("Values: Back button not found")
	
	_apply_daily_value()
	_load_values_data()

func _resolve_auth_manager() -> Node:
	if get_tree() != null and get_tree().root != null:
		var manager: Node = get_tree().root.get_node_or_null("FirebaseAuthManager")
		if manager != null:
			return manager
	if Engine.has_singleton("FirebaseAuthManager"):
		return Engine.get_singleton("FirebaseAuthManager")
	return null

func _resolve_session() -> Node:
	if get_tree() != null and get_tree().root != null:
		var session: Node = get_tree().root.get_node_or_null("UserSession")
		if session != null:
			return session
	if Engine.has_singleton("UserSession"):
		return Engine.get_singleton("UserSession")
	return null

func _get_current_user_id() -> String:
	if _session != null and _session.has_method("get_current_user_id"):
		var uid: String = str(_session.call("get_current_user_id")).strip_edges()
		if not uid.is_empty():
			return uid
	return "guest_user"

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

func _apply_daily_value() -> void:
	var value = _get_daily_value()
	var title_label: Label = _find_label(["Panel3/ValueTitle", "Panel/Panel3/ValueTitle", "Panel/Panel3/Panel3/ValueTitle"])
	if title_label != null:
		title_label.text = str(value["title"])

	var description_label: Label = _find_label(["Panel3/ValueDescription", "Panel/Panel3/Panel3/ValueDescription", "Panel/Panel3/Panel3/ValueDescription"])
	if description_label != null:
		description_label.text = str(value["description"])

	var reflection_label: Label = get_node_or_null("Panel/Panel4/Label")
	if reflection_label != null:
		reflection_label.text = str(value["reflection"])

	_apply_daily_challenges(value["challenges"])
	_apply_daily_value_picture(value["title"])

func _find_label(paths: Array) -> Label:
	for path in paths:
		var node = get_node_or_null(path)
		if node is Label:
			return node as Label
	return null

func _apply_daily_challenges(challenges: Array) -> void:
	for i in range(1, 4):
		var label: Label = _find_label([
			"Panel/Panel3/Panel3/Challenge%s" % i,
			"Panel/Panel3/Challenge%s" % i,
			"Panel/Panel3/Panel3/Panel/Challenge%s" % i
		])
		if label == null:
			continue
		if i - 1 < challenges.size():
			label.text = "• %s" % str(challenges[i - 1])
		else:
			label.text = "• Stay mindful and keep growing."

func _apply_daily_value_picture(value_title: String) -> void:
	"""Change the value picture based on the current value's title."""
	# Convert title to proper filename format (e.g., "RESPECT" -> "Respect.png")
	var picture_name = value_title.to_lower().capitalize() + ".png"
	var picture_path = "res://" + picture_name
	
	# Try multiple possible paths for the values_picture node
	var picture_paths = [
		"Panel3/Panel3/values_picture",
		"Panel/Panel3/Panel3/values_picture",
		"Panel3/values_picture",
		"values_picture"
	]
	
	var picture_node: Node = null
	for path in picture_paths:
		var node = get_node_or_null(path)
		if node != null:
			picture_node = node
			break
	
	if picture_node != null:
		var texture = load(picture_path)
		if texture != null:
			# If it's a TextureRect, set the texture directly
			if picture_node is TextureRect:
				(picture_node as TextureRect).texture = texture
				print("Values: Picture updated to %s" % picture_name)
			# For Panel, texture is applied via StyleBoxTexture in the scene definition
			else:
				print("Values: Picture node is not a TextureRect, skipping texture load")
		else:
			print("Values: Picture not found at %s" % picture_path)
	else:
		print("Values: values_picture node not found")

func _get_daily_value() -> Dictionary:
	var current_date = Time.get_date_dict_from_system()
	var day_seed: int = int(current_date["year"]) * 10000 + int(current_date["month"]) * 100 + int(current_date["day"])
	var index: int = day_seed % DAILY_VALUES.size()
	return DAILY_VALUES[index]

func _on_reflection_button_pressed() -> void:
	"""Navigate to popup values for reflection"""
	print("Values: Reflection button pressed - navigating to popup_values.tscn")
	get_tree().change_scene_to_file("res://popup_values.tscn")

func _on_back_button_pressed() -> void:
	"""Navigate back to home screen"""
	print("Values: Back button pressed - navigating to home.tscn")
	get_tree().change_scene_to_file("res://home.tscn")

func _load_values_data() -> void:
	"""Load values data from Firebase or local storage."""
	print("Values: Loading data for user: ", _current_user_id)
	if _auth_manager != null and _auth_manager.has_method("load_scene_input"):
		_auth_manager.load_scene_input(_current_user_id, "values", func(ok: bool, data: Variant):
			if ok and data is Dictionary:
				print("Values: Data loaded successfully: ", data)
			else:
				print("Values: No saved data found, using defaults")
		)
