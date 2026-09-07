extends Node2D

# Character Animation Manager for home.tscn
# Handles gender-based character selection and animation states

signal animation_state_changed(new_state: String)

enum AnimationState {
	IDLE,
	LISTENING,
	TALKING
}

var current_animation_state: AnimationState = AnimationState.IDLE
var current_gender: String = "boy"  # Default to boy
var character_sprite: AnimatedSprite2D = null
var character_container: Node2D = null
var _is_listening: bool = false
var _is_ai_talking: bool = false
var _return_to_idle_timer: Timer = null
@export var return_to_idle_seconds: float = 1.5

# Animation scene paths
const BOY_IDLE_SCENE = "res://IDLE_BOY.tscn"
const GIRL_IDLE_SCENE = "res://IDLE.tscn"  # Using IDLE.tscn for girl character
const BOY_LISTENING_SCENE = "res://listening_boy.tscn"  # Boy-specific listening animation
const GIRL_LISTENING_SCENE = "res://listening.tscn"  # Current listening animation for girls
const BOY_TALKING_SCENE = "res://talkin_boy.tscn"  # Boy-specific talking animation (note spelling)
const GIRL_TALKING_SCENE = "res://talking.tscn"  # Current talking animation for girls

# Consistent character size - made larger as requested
const CHARACTER_SCALE = Vector2(1.2, 1.2)
const CHARACTER_POSITION = Vector2(-100, 50)  # Position character on left side

func _ready() -> void:
	_load_user_gender()
	_setup_character_container()
	_load_idle_character()
	_connect_voice_signals()

	# Ensure timer exists for delayed back-to-idle behavior
	_return_to_idle_timer = Timer.new()
	_return_to_idle_timer.one_shot = true
	_return_to_idle_timer.wait_time = return_to_idle_seconds
	add_child(_return_to_idle_timer)
	_return_to_idle_timer.timeout.connect(Callable(self, "_on_return_to_idle_timeout"))

func _load_user_gender() -> void:
	# First try to get from user profile (persists across login)
	if Engine.has_singleton("UserSession"):
		var session = Engine.get_singleton("UserSession")
		if session != null:
			# Try multiple methods to get user profile
			if session.has_method("get_user_profile"):
				var profile = session.call("get_user_profile")
				if profile is Dictionary and profile.has("gender"):
					current_gender = str(profile["gender"]).strip_edges().to_lower()
					print("CharacterAnimationManager: Loaded gender from profile: ", current_gender)
					return
			# Try alternative method names
			if session.has_method("get_profile"):
				var profile = session.call("get_profile")
				if profile is Dictionary and profile.has("gender"):
					current_gender = str(profile["gender"]).strip_edges().to_lower()
					print("CharacterAnimationManager: Loaded gender from profile: ", current_gender)
					return
	
	# Try to get from Firebase auth manager profile
	var auth_manager = get_tree().root.get_node_or_null("FirebaseAuthManager")
	if auth_manager == null and Engine.has_singleton("FirebaseAuthManager"):
		auth_manager = Engine.get_singleton("FirebaseAuthManager")
	
	if auth_manager != null:
		if auth_manager.has_method("get_current_user_profile"):
			var profile = auth_manager.call("get_current_user_profile")
			if profile is Dictionary and profile.has("gender"):
				current_gender = str(profile["gender"]).strip_edges().to_lower()
				print("CharacterAnimationManager: Loaded gender from auth profile: ", current_gender)
				return
		if auth_manager.has_method("load_profile"):
			# Try loading profile for current user
			var user_id = _get_current_user_id()
			if not user_id.is_empty():
				auth_manager.call("load_profile", user_id, Callable(self, "_on_profile_loaded"))
				return
		# Try direct profile loading method
		if auth_manager.has_method("get_profile"):
			var user_id = _get_current_user_id()
			if not user_id.is_empty():
				var profile = auth_manager.call("get_profile", user_id)
				if profile is Dictionary and profile.has("gender"):
					current_gender = str(profile["gender"]).strip_edges().to_lower()
					print("CharacterAnimationManager: Loaded gender from auth get_profile: ", current_gender)
					return
	
	# Fallback: try to get from question_12 answers (temporary, for current session)
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta("question_answers", {})
	
	for key in answers.keys():
		if key.contains("question_12") or key.contains("question12"):
			if key.contains("_gender"):
				current_gender = str(answers[key]).strip_edges().to_lower()
				print("CharacterAnimationManager: Loaded gender from answers: ", current_gender)
				# Save to profile for persistence (only once)
				_save_gender_to_profile(current_gender)
				return
	
	print("CharacterAnimationManager: No gender found, defaulting to: ", current_gender)

func _on_profile_loaded(success: bool, profile: Variant) -> void:
	if success and profile is Dictionary and profile.has("gender"):
		current_gender = str(profile["gender"]).strip_edges().to_lower()
		print("CharacterAnimationManager: Loaded gender from async profile load: ", current_gender)
		_load_idle_character()

func _get_current_user_id() -> String:
	var user_id: String = ""
	
	if Engine.has_singleton("UserSession"):
		var session = Engine.get_singleton("UserSession")
		if session != null and session.has_method("get_current_user_id"):
			user_id = str(session.call("get_current_user_id")).strip_edges()
	
	if user_id.is_empty():
		var auth_manager = get_tree().root.get_node_or_null("FirebaseAuthManager")
		if auth_manager == null and Engine.has_singleton("FirebaseAuthManager"):
			auth_manager = Engine.get_singleton("FirebaseAuthManager")
		if auth_manager != null and auth_manager.has_method("get_current_user"):
			var user = auth_manager.call("get_current_user")
			if user is Dictionary and user.has("uid"):
				user_id = str(user["uid"]).strip_edges()
	
	return user_id

func _save_gender_to_profile(gender: String) -> void:
	var user_id = _get_current_user_id()
	if user_id.is_empty():
		# Silent fail - no need to spam logs
		return
	
	var auth_manager = get_tree().root.get_node_or_null("FirebaseAuthManager")
	if auth_manager == null and Engine.has_singleton("FirebaseAuthManager"):
		auth_manager = Engine.get_singleton("FirebaseAuthManager")
	
	if auth_manager != null and auth_manager.has_method("save_profile_attributes"):
		var profile_update = {"gender": gender}
		auth_manager.call("save_profile_attributes", user_id, profile_update)

func _setup_character_container() -> void:
	character_container = Node2D.new()
	character_container.name = "CharacterContainer"
	# Position character on the left side of the screen
	character_container.position = CHARACTER_POSITION
	character_container.scale = CHARACTER_SCALE
	character_container.z_index = 1  # Ensure character is above background
	add_child(character_container)

func _load_idle_character() -> void:
	_clear_current_character()
	
	var idle_scene_path = BOY_IDLE_SCENE if current_gender == "boy" else GIRL_IDLE_SCENE
	var idle_scene = load(idle_scene_path)
	
	if idle_scene == null:
		print("CharacterAnimationManager: Failed to load idle scene: ", idle_scene_path)
		return
	
	var character_instance = idle_scene.instantiate()
	if character_instance == null:
		print("CharacterAnimationManager: Failed to instantiate idle scene")
		return
	
	character_container.add_child(character_instance)
	
	# Try multiple paths to find the AnimatedSprite2D
	character_sprite = character_instance.get_node_or_null("CharacterBody2D/AnimatedSprite2D") as AnimatedSprite2D
	if character_sprite == null:
		character_sprite = character_instance.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	
	if character_sprite != null:
		_play_animation_for_state(character_sprite, "idle")
		character_sprite.scale = Vector2(1, 1)
		print("CharacterAnimationManager: Successfully loaded idle character for gender: ", current_gender)
	else:
		print("CharacterAnimationManager: Could not find AnimatedSprite2D in character scene")
	
	current_animation_state = AnimationState.IDLE
	emit_signal("animation_state_changed", "idle")

func _clear_current_character() -> void:
	if character_container != null:
		for child in character_container.get_children():
			child.queue_free()
	character_sprite = null

func _connect_voice_signals() -> void:
	# Connect to voice recording signals from parent (shared_nav.gd)
	var parent = get_parent()
	if parent != null and parent.has_method("_on_voice_button_down"):
		# We'll connect to these when the parent calls them
		print("CharacterAnimationManager: Parent has voice methods, will connect via overrides")
	
	# Alternatively, we can connect to the LiveKit voice manager if available
	var livekit_manager = get_tree().root.get_node_or_null("LiveKitVoiceManager")
	if livekit_manager != null:
		if livekit_manager.has_signal("livekit_state_changed"):
			livekit_manager.connect("livekit_state_changed", Callable(self, "_on_livekit_state_changed"))
			print("CharacterAnimationManager: Connected to LiveKit state changes")

func set_animation_state(state: AnimationState) -> void:
	if current_animation_state == state:
		return
	
	print("CharacterAnimationManager: Changing animation state from ", current_animation_state, " to ", state)
	
	match state:
		AnimationState.IDLE:
			_load_idle_character()
		AnimationState.LISTENING:
			_load_listening_animation()
		AnimationState.TALKING:
			_load_talking_animation()
	
	current_animation_state = state
	
	var state_name = "idle" if state == AnimationState.IDLE else "listening" if state == AnimationState.LISTENING else "talking"
	emit_signal("animation_state_changed", state_name)

func _play_animation_for_state(sprite: AnimatedSprite2D, state_name: String) -> void:
	if sprite == null:
		return
	if sprite.sprite_frames == null:
		if sprite.has_animation("default"):
			sprite.play("default")
		return
	var preferred_name: String = state_name
	if sprite.sprite_frames.has_animation(preferred_name):
		sprite.play(preferred_name)
		return
	if state_name == "idle" and sprite.sprite_frames.has_animation("default"):
		sprite.play("default")
		return
	if state_name == "listening" and sprite.sprite_frames.has_animation("listen"):
		sprite.play("listen")
		return
	if state_name == "talking" and sprite.sprite_frames.has_animation("talk"):
		sprite.play("talk")
		return
	if sprite.sprite_frames.has_animation("default"):
		sprite.play("default")
		return
	if sprite.get_animation() != "":
		sprite.play()
		return

func _load_listening_animation() -> void:
	_clear_current_character()
	
	var listening_scene_path = GIRL_LISTENING_SCENE if current_gender == "girl" else BOY_LISTENING_SCENE
	var listening_scene = load(listening_scene_path)
	if listening_scene == null:
		print("CharacterAnimationManager: Failed to load listening scene: ", listening_scene_path)
		_load_idle_character()  # Fallback to idle
		return
	
	var character_instance = listening_scene.instantiate()
	if character_instance == null:
		print("CharacterAnimationManager: Failed to instantiate listening scene")
		_load_idle_character()  # Fallback to idle
		return
	
	character_container.add_child(character_instance)
	character_sprite = character_instance.get_node_or_null("CharacterBody2D/AnimatedSprite2D") as AnimatedSprite2D
	
	if character_sprite != null:
		_play_animation_for_state(character_sprite, "listening")
		character_sprite.scale = Vector2(1, 1)
		print("CharacterAnimationManager: Loaded listening animation for gender: ", current_gender)
	else:
		print("CharacterAnimationManager: Could not find AnimatedSprite2D in listening scene")
		_load_idle_character()  # Fallback to idle

func _load_talking_animation() -> void:
	_clear_current_character()
	
	var talking_scene_path = GIRL_TALKING_SCENE if current_gender == "girl" else BOY_TALKING_SCENE
	var talking_scene = load(talking_scene_path)
	if talking_scene == null:
		print("CharacterAnimationManager: Failed to load talking scene: ", talking_scene_path)
		_load_idle_character()  # Fallback to idle
		return
	
	var character_instance = talking_scene.instantiate()
	if character_instance == null:
		print("CharacterAnimationManager: Failed to instantiate talking scene")
		_load_idle_character()  # Fallback to idle
		return
	
	character_container.add_child(character_instance)
	character_sprite = character_instance.get_node_or_null("CharacterBody2D/AnimatedSprite2D") as AnimatedSprite2D
	
	if character_sprite != null:
		_play_animation_for_state(character_sprite, "talking")
		character_sprite.scale = Vector2(1, 1)
		print("CharacterAnimationManager: Loaded talking animation for gender: ", current_gender)
	else:
		print("CharacterAnimationManager: Could not find AnimatedSprite2D in talking scene")
		_load_idle_character()  # Fallback to idle

func _on_livekit_state_changed(state: String) -> void:
	print("CharacterAnimationManager: LiveKit state changed: ", state)
	
	match state:
		"connecting":
			set_animation_state(AnimationState.LISTENING)
		"connected":
			# Stay in listening until AI starts talking
			pass
		"disconnected":
			set_animation_state(AnimationState.IDLE)
		_:
			pass

# Public methods to be called from shared_nav.gd
func on_voice_recording_started() -> void:
	print("CharacterAnimationManager: Voice recording started")
	_is_listening = true
	# Cancel any pending return-to-idle while user is speaking
	if _return_to_idle_timer != null and _return_to_idle_timer.is_stopped() == false:
		_return_to_idle_timer.stop()
	set_animation_state(AnimationState.LISTENING)

func on_voice_recording_stopped() -> void:
	print("CharacterAnimationManager: Voice recording stopped")
	_is_listening = false
	# If AI is not talking, schedule return to idle after delay
	if not _is_ai_talking:
		if _return_to_idle_timer != null:
			_return_to_idle_timer.start()

func on_ai_started_talking() -> void:
	print("CharacterAnimationManager: AI started talking")
	_is_ai_talking = true
	# Cancel any pending return-to-idle while AI is talking
	if _return_to_idle_timer != null and _return_to_idle_timer.is_stopped() == false:
		_return_to_idle_timer.stop()
	set_animation_state(AnimationState.TALKING)

func on_ai_stopped_talking() -> void:
	print("CharacterAnimationManager: AI stopped talking")
	_is_ai_talking = false
	# If user is not listening, schedule return to idle after delay
	if not _is_listening:
		if _return_to_idle_timer != null:
			_return_to_idle_timer.start()
	else:
		# If user is listening, switch to listening animation
		set_animation_state(AnimationState.LISTENING)

func _on_return_to_idle_timeout() -> void:
	# Timeout handler: ensure neither listening nor AI talking is active
	if not _is_listening and not _is_ai_talking:
		set_animation_state(AnimationState.IDLE)

func update_character_gender(new_gender: String) -> void:
	new_gender = new_gender.strip_edges().to_lower()
	if new_gender not in ["boy", "girl"]:
		print("CharacterAnimationManager: Invalid gender: ", new_gender)
		return
	
	if current_gender != new_gender:
		current_gender = new_gender
		print("CharacterAnimationManager: Gender updated to: ", current_gender)
		_save_gender_to_profile(current_gender)  # Save for persistence
		_load_idle_character()  # Reload with new gender
