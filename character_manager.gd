extends Node

## Character Manager - Handles gender-based character loading and display
## This script manages character selection based on user's gender choice
## and displays the appropriate character with idle animation

const ANSWER_STORE_KEY := "question_answers"
var current_character: AnimatedSprite2D = null
var current_gender: String = ""

## Initialize the character manager
func _ready() -> void:
	print("Character Manager initialized")

## Load character based on user's gender selection
func load_character_based_on_gender(character_container: Node) -> void:
	var user_gender := _get_user_gender()
	print("Loading character for gender: ", user_gender)
	
	if user_gender.is_empty():
		print("No gender selection found, using default (boy)")
		user_gender = "boy"
	
	current_gender = user_gender
	
	# Remove existing character if any
	if current_character != null:
		current_character.queue_free()
		current_character = null
	
	# Create new character sprite
	current_character = AnimatedSprite2D.new()
	
	# Load appropriate sprite frames based on gender
	if user_gender == "girl":
		_load_girl_character()
	else:
		_load_boy_character()
	
	# Position in the center of the container
	if character_container != null:
		current_character.position = Vector2.ZERO
		character_container.add_child(current_character)
		
		# Start idle animation
		if current_character.sprite_frames != null:
			current_character.play("default")
			current_character.autoplay = "default"
		
		print("Character loaded and positioned in container")

func _load_boy_character() -> void:
	# Load boy character sprite
	var boy_texture = load("res://boy.png")
	if boy_texture != null:
		var sprite_frames = SpriteFrames.new()
		sprite_frames.add_frame("default", boy_texture, 1.0)
		current_character.sprite_frames = sprite_frames
		print("Boy character loaded")
	else:
		print("Failed to load boy character texture")

func _load_girl_character() -> void:
	# Load girl character animation frames
	var girl_frames = []
	for i in range(1, 5):  # GIRL1.png to GIRL4.png
		var frame_path = "res://GIRL%d.png" % i
		var frame_texture = load(frame_path)
		if frame_texture != null:
			girl_frames.append(frame_texture)
			print("Loaded girl frame: ", frame_path)
		else:
			print("Failed to load girl frame: ", frame_path)
	
	if girl_frames.size() > 0:
		var sprite_frames = SpriteFrames.new()
		for frame in girl_frames:
			sprite_frames.add_frame("default", frame, 0.2)  # 0.2 seconds per frame for smooth animation
		current_character.sprite_frames = sprite_frames
		print("Girl character loaded with ", girl_frames.size(), " frames")
	else:
		print("No girl character frames found, using fallback")
		# Fallback to boy character if girl frames not available
		_load_boy_character()

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

func get_current_gender() -> String:
	return current_gender

func get_current_character() -> AnimatedSprite2D:
	return current_character