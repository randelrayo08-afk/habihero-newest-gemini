extends Control

## Home Character Manager - Displays gender-based character in home scene
## This script loads and displays the appropriate character (boy/girl) 
## based on the user's selection in question_12, positioned in the center

const ANSWER_STORE_KEY := "question_answers"
var character_scene: PackedScene = null
var character_instance: Node2D = null

func _ready() -> void:
	print("Home Character Manager initialized")
	
	# Load and display the appropriate character
	_load_character_based_on_gender()

func _load_character_based_on_gender() -> void:
	var user_gender := _get_user_gender()
	print("Loading character for gender: ", user_gender)
	
	if user_gender.is_empty():
		print("No gender selection found, using default (boy)")
		user_gender = "boy"
	
	# Remove existing character if any
	if character_instance != null:
		character_instance.queue_free()
		character_instance = null
	
	# Load appropriate character scene based on gender
	if user_gender == "girl":
		character_scene = load("res://GIRL_IDLE.tscn")
		print("Loading girl character scene")
	else:
		character_scene = load("res://BOY_IDLE.tscn")
		print("Loading boy character scene")
	
	if character_scene != null:
		character_instance = character_scene.instantiate()
		if character_instance != null:
			# Position the character in the center of this control
			character_instance.position = Vector2(size.x / 2, size.y / 2)
			
			# Scale the character appropriately
			var sprite = character_instance.get_node_or_null("CharacterBody2D/AnimatedSprite2D")
			if sprite != null:
				sprite.scale = Vector2(0.8, 0.8)  # Adjust scale as needed
			
			add_child(character_instance)
			print("Character loaded and displayed: ", user_gender)
		else:
			print("Failed to instantiate character scene")
	else:
		print("Failed to load character scene")

func _get_user_gender() -> String:
	# Get gender from stored answers
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta(ANSWER_STORE_KEY, {})
	
	# Check for question_12 gender
	for key in answers.keys():
		if key.contains("gender"):
			var gender = str(answers[key]).strip_edges().to_lower()
			if gender in ["boy", "girl"]:
				return gender
	
	# Also check UserSession profile if available
	if Engine.has_singleton("UserSession"):
		var session = Engine.get_singleton("UserSession")
		if session != null and session.has_method("get_user_profile"):
			var profile = session.call("get_user_profile")
			if profile is Dictionary and profile.has("gender"):
				var gender = str(profile["gender"]).strip_edges().to_lower()
				if gender in ["boy", "girl"]:
					return gender
	
	return ""

func _exit_tree() -> void:
	# Clean up character instance when scene is unloaded
	if character_instance != null:
		character_instance.queue_free()