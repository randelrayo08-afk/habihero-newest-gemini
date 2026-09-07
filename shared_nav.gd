extends Control

const NAV_MAP: Dictionary = {
	"home": "res://home.tscn",
	"progress": "res://progress.tscn",
	"journal": "res://journal.tscn",
	"shop": "res://Shop.tscn",
	"guidance": "res://guidance.tscn",
	"myprog": "res://myprog.tscn",
	"myjournal": "res://myjournal.tscn",
	"moodcheck": "res://moodcheck.tscn",
	"settings": "res://settings.tscn",
	"login": "res://login.tscn",
	"edit_profile": "res://edit_profile.tscn",
	"about": "res://about.tscn",
	"terms": "res://terms.tscn",
	"privacy": "res://privacy.tscn",
	"helpsupport": "res://helpsupport.tscn",
	"values": "res://values.tscn",
	"spiritual": "res://spiritual.tscn",
	"popupspiritual": "res://popupspiritual.tscn",
	"imago_dei": "res://imago_dei.tscn",
	"notification": "res://Notification.tscn"
}

var _nav_wired: bool = false
var _auth_manager: Node
var _session: Node
var _last_synced_scene: String = ""
var _voice_recording_active: bool = false
var _input_active: bool = false
var _voice_record_player: AudioStreamPlayer
var _voice_playback_player: AudioStreamPlayer
var _voice_record_effect: AudioEffectRecord
var _voice_capture_effect: AudioEffectCapture
var _gemini_audio_playback: AudioStreamGeneratorPlayback
var _gemini_audio_queue: PackedVector2Array = PackedVector2Array()
var _shared_xp_arc: Control
var _gemini_client: Node
var _ai_talking_active: bool = false
var _voice_button_wired: bool = false

var _voice_debug: bool = false
var _gemini_response_timeout: float = 6.0
var _gemini_response_timer: Timer = null


const VOICE_RECORD_FILE: String = "user://voice_input.wav"
const VOICE_CAPTURE_BUS: String = "VoiceCapture"
const VOICE_SILENCE_BUS: String = "VoiceSilence"

var _music_volume_before_recording: float = -18.0
var _music_mute_before_recording: bool = false

func _ready() -> void:
	_auth_manager = _resolve_auth_manager()
	_session = _resolve_session()
	_setup_gemini_client()
	call_deferred("_wire_settings_audio_controls")
	# Connect to AudioManager playback_finished to detect end of TTS playback
	if Engine.has_singleton("AudioManager"):
		var am = Engine.get_singleton("AudioManager")
		if am != null and am.has_signal("playback_finished") and not am.is_connected("playback_finished", Callable(self, "_on_audio_playback_finished")):
			am.connect("playback_finished", Callable(self, "_on_audio_playback_finished"))
	if _auth_manager != null and _auth_manager.has_signal("profile_updated"):
		var profile_callback := Callable(self, "_on_profile_updated")
		if not _auth_manager.profile_updated.is_connected(profile_callback):
			_auth_manager.profile_updated.connect(profile_callback)
	_record_current_scene()
	call_deferred("_wire_bottom_nav")
	call_deferred("_update_coin_balance")
	call_deferred("_update_checkin_streak")
	if name == "Progress" and has_method("_load_experience"):
		call_deferred("_load_experience")
	else:
		call_deferred("_setup_shared_experience")
		call_deferred("_load_shared_experience")
	if name == "Journal":
		call_deferred("_load_journal_entries_view")
	# Show a friendly greeting when the app starts for this session/user
	call_deferred("_maybe_show_greeting")

func _maybe_show_greeting() -> void:
	var root = get_tree().root
	if root == null:
		return

	# Resolve current user id and name (fallbacks)
	var user_id: String = "guest_user"
	var user_name: String = "there"
	if _session != null:
		if _session.has_method("get_current_user_id"):
			user_id = str(_session.call("get_current_user_id")).strip_edges()
		if _session.has_method("get_current_user_name"):
			user_name = str(_session.call("get_current_user_name")).strip_edges()
	if user_name == "" or user_name.to_lower() == "guest":
		user_name = "there"

	# Track whether we've shown the greeting to this specific user before
	var seen_key: String = "habi_greeting_seen_%s" % user_id
	var is_new_user: bool = not root.has_meta(seen_key)

	var greeting_text: String = ""
	if is_new_user:
		greeting_text = "Hi there, %s... I'm Habi, your Habihero.\nI'm not just an app — think of me as a friend who's always here to listen, whenever you need to talk.\nThere's no pressure, no judgment... just a space that's yours. So, how are you feeling right now?" % user_name
		root.set_meta(seen_key, Time.get_datetime_string_from_system(false, true))
	else:
		var options: Array = [
			"Hi, %s... it's Habi. I'm really glad you're back.\nWhatever the last few hours looked like for you, know that this little space is still here, just for you.\nTake your time... there's no rush. So... how are you feeling today?" % user_name,
			"Hey, %s... welcome back. I've been here, waiting to talk with you.\nIt doesn't matter if it's been a long day or a quiet one — I'm just happy you came by.\nWhat's on your mind right now? I'm all ears." % user_name,
			"Hi, %s... good to see you again.\nWhatever kind of day you're having, I'm here for it — happy, tired, frustrated, or somewhere in between.\nYou don't need a reason to talk to me... I just like knowing how you're doing." % user_name
		]
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var idx: int = rng.randi_range(0, options.size() - 1)
		greeting_text = options[idx]

	# Speak greeting using preferred voice (backend handles default if empty)
	var backend: Node = _resolve_habi_backend()
	if backend != null:
		# Notify character animation manager so it switches to talking.
		_notify_character_animation("ai_started_talking")
		var voice_id: String = _get_preferred_voice_id()
		backend.companion_tts(greeting_text, voice_id, Callable(self, "_on_tts_result"))

	# Transient on-screen notification disabled per request (removed labeling across scenes)
	# _show_transient_notification(greeting_text)

func _show_transient_notification(text: String, duration: float = 6.0) -> void:
	if not is_inside_tree():
		return
	var label := Label.new()
	label.name = "HabiGreetingLabel"
	label.text = text
	# Godot 4 uses `autowrap_mode` instead of a boolean `autowrap`
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	# Godot 4: set a minimum size and explicit size before computing pivot
	label.custom_minimum_size = Vector2(400, 80)
	label.size = label.custom_minimum_size
	label.anchor_left = 0.5
	label.anchor_top = 0.0
	label.anchor_right = 0.5
	label.anchor_bottom = 0.0
	# Use Godot 4 margin setters instead of legacy `margin_*` properties
	# Center horizontally at anchor 0.5 and offset by half the width
	label.pivot_offset = label.size * 0.5
	label.position = Vector2(-200, 12)
	label.add_theme_color_override("font_color", Color(1,1,1,1))
	label.add_theme_font_size_override("font_size", 16)
	add_child(label)

	var t := Timer.new()
	t.one_shot = true
	t.wait_time = duration
	add_child(t)
	t.start()
	t.timeout.connect(func() -> void:
		if is_instance_valid(label):
			label.queue_free()
		if is_instance_valid(t):
			t.queue_free()
	)

func _setup_shared_experience() -> void:
	if name == "Progress":
		return
	var badge: Control = get_node_or_null("experience") as Control
	if badge == null:
		badge = get_node_or_null("Panel6") as Control
	if badge == null or badge.get_node_or_null("SharedXPArc") != null:
		return
	var arc := _SharedXPArc.new()
	arc.name = "SharedXPArc"
	arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arc.z_index = 5
	badge.add_child(arc)
	_shared_xp_arc = arc
	var center_panel: Control = badge.get_node_or_null("Panel5") as Control
	if center_panel != null:
		center_panel.z_index = 6
	var level_label: Label = badge.get_node_or_null("Label") as Label
	if level_label != null:
		level_label.z_index = 7
	call_deferred("_resize_shared_experience", arc)
	_load_shared_experience()

func _resize_shared_experience(arc: Control) -> void:
	var badge: Control = get_node_or_null("experience") as Control
	if badge == null:
		badge = get_node_or_null("Panel6") as Control
	if badge == null or not is_instance_valid(arc):
		return
	arc.position = Vector2.ZERO
	arc.size = badge.size
	arc.queue_redraw()

func _load_shared_experience() -> void:
	if _auth_manager == null or not _auth_manager.has_method("load_experience"):
		return
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = str(_session.call("get_current_user_id")).strip_edges()
	if user_id.is_empty():
		user_id = "guest_user"
	_auth_manager.load_experience(user_id, Callable(self, "_on_shared_experience_loaded"))

func _on_shared_experience_loaded(ok: bool, experience: Variant) -> void:
	if not ok or _shared_xp_arc == null or not is_instance_valid(_shared_xp_arc):
		return
	var total_experience: int = 0
	var resolved_value: Variant = experience
	if resolved_value is Dictionary:
		if resolved_value.has("experience"):
			resolved_value = resolved_value.get("experience")
		elif resolved_value.has("xp"):
			resolved_value = resolved_value.get("xp")
	if resolved_value is String:
		resolved_value = resolved_value.strip_edges()
		if resolved_value.is_valid_int():
			resolved_value = int(resolved_value)
		else:
			resolved_value = 0
	if resolved_value is int or resolved_value is float:
		total_experience = max(0, int(resolved_value))
	var level: int = int(float(total_experience) / 500.0) + 1
	var current_xp: int = total_experience % 500
	var level_label: Label = get_node_or_null("experience/Label") as Label
	if level_label != null:
		level_label.text = str(level)
	if _shared_xp_arc.has_method("set_progress_ratio"):
		_shared_xp_arc.call("set_progress_ratio", float(current_xp) / 500.0)

class _SharedXPArc extends Control:
	var progress_ratio: float = 0.0:
		set(value):
			progress_ratio = clampf(value, 0.0, 1.0)
			queue_redraw()

	func set_progress_ratio(value: float) -> void:
		progress_ratio = value

	func _draw() -> void:
		if size.x <= 0 or size.y <= 0:
			return
		var center: Vector2 = size / 2.0
		var radius: float = minf(size.x, size.y) / 2.0 - 8.0
		if radius <= 0:
			return
		draw_arc(center, radius, 0.0, TAU, 96, Color("#d9d1c5"), 10.0, true)
		if progress_ratio > 0.0:
			draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * progress_ratio, 96, Color("#4aa63b"), 10.0, true)

func _update_coin_balance() -> void:
	var coin_label: Label = get_node_or_null("Button/Panel/Label") as Label
	if coin_label == null:
		return
	coin_label.text = "0"
	if _auth_manager == null or not _auth_manager.has_method("load_coin_balance"):
		return
	var user_id := "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = str(_session.call("get_current_user_id"))
	_auth_manager.load_coin_balance(user_id, Callable(self, "_on_coin_balance_loaded"))

func _on_coin_balance_loaded(ok: bool, balance: Variant) -> void:
	if not ok or not is_instance_valid(self):
		return
	var coin_label: Label = get_node_or_null("Button/Panel/Label") as Label
	if coin_label != null:
		coin_label.text = str(max(0, int(balance)))

func _on_profile_updated(user_id: String) -> void:
	var current_user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		current_user_id = str(_session.call("get_current_user_id"))
	if user_id != current_user_id.to_lower().replace("@", "_").replace(".", "_"):
		return
	call_deferred("_update_coin_balance")
	call_deferred("_update_checkin_streak")
	call_deferred("_setup_shared_experience")

func _update_checkin_streak() -> void:
	var streak_panel: Control = get_node_or_null("Panel5/Panel") as Control
	if streak_panel == null:
		return
	var streak_label: Label = streak_panel.get_node_or_null("StreakLabel") as Label
	if streak_label == null:
		streak_label = Label.new()
		streak_label.name = "StreakLabel"
		streak_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		streak_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
		streak_label.add_theme_font_size_override("font_size", 16)
		streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		streak_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		streak_label.z_index = 4
		streak_panel.add_child(streak_label)
	streak_label.text = "0"
	if _auth_manager == null or not _auth_manager.has_method("load_checkin_streak"):
		return
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = str(_session.call("get_current_user_id"))
	_auth_manager.load_checkin_streak(user_id, Callable(self, "_on_checkin_streak_loaded"))

func _on_checkin_streak_loaded(ok: bool, streak: Variant) -> void:
	if not ok or not is_instance_valid(self):
		return
	var streak_label: Label = get_node_or_null("Panel5/Panel/StreakLabel") as Label
	if streak_label != null:
		streak_label.text = str(max(0, int(streak)))

func _wire_bottom_nav() -> void:
	if _nav_wired or not is_inside_tree():
		return
	_nav_wired = true

	_attach_button("homebut", "Home", "home")
	_attach_button("progbut", "Progress", "progress")
	_attach_button("jourbut", "Journal", "journal")
	_attach_button("shopbut", "Shop", "shop")
	_attach_button("guibot", "Guidance", "guidance")

	# Some scenes use generic button names such as Button, Button2, Button3.
	# If the expected named buttons do not exist, we simply skip them and keep the scene usable.
	if _locate_button("homebut", "Home") == null:
		_attach_button_by_label("Home", "home")
	if _locate_button("progbut", "Progress") == null:
		_attach_button_by_label("Progress", "progress")
	if _locate_button("jourbut", "Journal") == null:
		_attach_button_by_label("Journal", "journal")
	if _locate_button("shopbut", "Shop") == null:
		_attach_button_by_label("Shop", "shop")
	if _locate_button("guibot", "Guidance") == null:
		_attach_button_by_label("Guidance", "guidance")

	if _current_scene_path().to_lower().ends_with("progress.tscn"):
		_attach_button_by_path("Panel4/Button", "myprog")
	_attach_button_by_label("CLOSE", "back")
	_attach_button_by_label("Back", "back")
	print("\n🔍 DEBUG: Attempting to wire 'new entry' button")
	_attach_button_by_label("new entry", "myjournal")
	_wire_settings_button()
	_wire_moodcheck_button()
	if has_method("_wire_values_button"):
		call_deferred("_wire_values_button")
	if has_method("_wire_spiritual_button"):
		call_deferred("_wire_spiritual_button")
	if has_method("_wire_notification_button"):
		call_deferred("_wire_notification_button")
	_wire_voice_button()
	if name == "Settings":
		_wire_settings_option_buttons()
		_wire_settings_back_buttons()
	elif name in ["About", "terms", "PRIVACY POLICY", "helpsupport"]:
		_wire_info_scene_back_button()

func _wire_info_scene_back_button() -> void:
	# Wire back button on info scenes (About, Terms, Privacy, Help) to navigate to Settings
	var back_button: Button = null
	
	match name:
		"About":
			back_button = get_node_or_null("Panel2/about_but") as Button
		"terms":
			back_button = get_node_or_null("Panel/Panel4/Button2") as Button
		"PRIVACY POLICY":
			back_button = get_node_or_null("Panel4/Button2") as Button
		"helpsupport":
			back_button = get_node_or_null("Panel2/help_but") as Button
	
	if back_button != null:
		var callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP["settings"])
		if not back_button.pressed.is_connected(callback):
			back_button.pressed.connect(callback)
			print("✓ Info scene back button wired to navigate to settings from ", name)
	else:
		print("✗ Info scene back button not found on ", name)

func _wire_settings_button() -> void:
	var settings_button: Button = get_node_or_null("Panel5/Button") as Button
	if settings_button == null:
		return
	var callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP["settings"])
	if not settings_button.pressed.is_connected(callback):
		settings_button.pressed.connect(callback)

func _wire_settings_option_buttons() -> void:
	# Explicit settings redirects required for this scene
	_attach_button_by_path("Panel/Panel4/aboutset_but", "about")
	_attach_button_by_path("Panel/Panel4/termsset_but", "terms")
	_attach_button_by_path("Panel/Panel4/privacyset_but", "privacy")
	_attach_button_by_path("Panel/Panel4/helpset_but", "helpsupport")
	_attach_button_by_path("Panel2/edit_but", "edit_profile")

	var logout_button: Button = get_node_or_null("logoutbut") as Button
	if logout_button != null:
		var logout_callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP["login"])
		if not logout_button.pressed.is_connected(logout_callback):
			logout_button.pressed.connect(logout_callback)
		print("✓ Settings logout button wired to login.tscn")
	else:
		var fallback_logout_button: Button = _find_button_by_label("Log Out")
		if fallback_logout_button != null:
			var fallback_logout_callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP["login"])
			if not fallback_logout_button.pressed.is_connected(fallback_logout_callback):
				fallback_logout_button.pressed.connect(fallback_logout_callback)
			print("✓ Settings logout fallback button wired to login.tscn")
		else:
			print("✗ Settings logout button not found")

	# Keep the generic wiring as a fallback too.
	_attach_button_by_path("Panel2/edit_but", "edit_profile")
	_attach_button_by_path("Panel/Panel4/aboutset_but", "about")
	_attach_button_by_path("Panel/Panel4/termsset_but", "terms")
	_attach_button_by_path("Panel/Panel4/privacyset_but", "privacy")
	_attach_button_by_path("Panel/Panel4/helpset_but", "helpsupport")

func _attach_button_by_path(node_path: String, scene_key: String) -> void:
	var button: Button = get_node_or_null(node_path) as Button
	if button == null:
		return
	var callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP[scene_key])
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)

func _wire_moodcheck_button() -> void:
	var mood_button: Button = null
	if _current_scene_path().to_lower().ends_with("home.tscn"):
		mood_button = get_node_or_null("Panel5/LIT/MOOD CHECK/moodbut") as Button
		if mood_button == null:
			mood_button = get_node_or_null("Panel5/LIT/MOOD CHECK/Button") as Button
	else:
		mood_button = get_node_or_null("Panel5/Panel5/Button") as Button
	if mood_button == null:
		mood_button = _find_button_by_label("MOOD CHECK")
	if mood_button == null:
		return
	var callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP["moodcheck"])
	if not mood_button.pressed.is_connected(callback):
		mood_button.pressed.connect(callback)


func _wire_values_button() -> void:
	# Try multiple possible button locations and labels
	var values_button: Button = get_node_or_null("Panel5/VALUES/valbut") as Button
	if values_button == null:
		values_button = _find_button_by_label("VALUES")
	if values_button == null:
		values_button = _find_button_by_label("Values")
	if values_button == null:
		values_button = _find_button_by_label("values")
	
	if values_button != null:
		var callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP["values"])
		if not values_button.pressed.is_connected(callback):
			values_button.pressed.connect(callback)
			print("Values button connected")
	else:
		print("Values button not found - attempted multiple locations")


func _wire_spiritual_button() -> void:
	var spiritual_button: Button = get_node_or_null("Panel5/LIT/litbut") as Button
	if spiritual_button == null:
		return
	var callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP["spiritual"])
	if not spiritual_button.pressed.is_connected(callback):
		spiritual_button.pressed.connect(callback)


func _wire_notification_button() -> void:
	var outer_notification_panel: Button = get_node_or_null("Button/notifbutton") as Button
	var icon_notification_button: Button = get_node_or_null("Button/notifbutton/notificon") as Button
	var notification_button: Button = outer_notification_panel if outer_notification_panel != null else icon_notification_button
	if notification_button == null:
		notification_button = get_node_or_null("Panel5/NOTIFICATION/notifbut") as Button
	if notification_button == null:
		notification_button = _find_button_by_label("NOTIFICATION")
	if notification_button == null:
		notification_button = _find_button_by_label("Notification")
	if notification_button == null:
		notification_button = _find_button_by_label("Bell")
	if notification_button == null:
		notification_button = _find_button_by_label("Notifications")
	
	if outer_notification_panel != null:
		var panel_normal_box = outer_notification_panel.get_theme_stylebox("normal")
		if panel_normal_box != null:
			outer_notification_panel.add_theme_stylebox_override("hover", panel_normal_box)
			outer_notification_panel.add_theme_stylebox_override("focus", panel_normal_box)
			outer_notification_panel.add_theme_stylebox_override("pressed", panel_normal_box)
		outer_notification_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		outer_notification_panel.pivot_offset = outer_notification_panel.size * 0.5
		outer_notification_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		outer_notification_panel.focus_mode = Control.FOCUS_NONE
	
	if icon_notification_button != null:
		var icon_normal_box = icon_notification_button.get_theme_stylebox("normal")
		if icon_normal_box != null:
			icon_notification_button.add_theme_stylebox_override("hover", icon_normal_box)
			icon_notification_button.add_theme_stylebox_override("focus", icon_normal_box)
			icon_notification_button.add_theme_stylebox_override("pressed", icon_normal_box)
		icon_notification_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		icon_notification_button.pivot_offset = icon_notification_button.size * 0.5
		icon_notification_button.mouse_filter = Control.MOUSE_FILTER_PASS
		icon_notification_button.focus_mode = Control.FOCUS_NONE
		if not icon_notification_button.mouse_entered.is_connected(_on_notification_hover_enter):
			icon_notification_button.mouse_entered.connect(_on_notification_hover_enter.bind(icon_notification_button))
		if not icon_notification_button.mouse_exited.is_connected(_on_notification_hover_exit):
			icon_notification_button.mouse_exited.connect(_on_notification_hover_exit.bind(icon_notification_button))

	var parent_button: Button = get_node_or_null("Button") as Button
	if parent_button != null:
		parent_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if notification_button != null:
		var callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP["notification"])
		if not notification_button.pressed.is_connected(callback):
			notification_button.pressed.connect(callback)
			print("Notification button connected")

func _on_notification_hover_enter(button: Button) -> void:
	if button == null:
		return
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	var tween = button.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(1.08, 1.08), 0.16)

func _on_notification_hover_exit(button: Button) -> void:
	if button == null:
		return
	var tween = button.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.16)


func _setup_voice_recording() -> void:
	if _voice_record_player != null:
		return

	_voice_record_player = AudioStreamPlayer.new()
	_voice_record_player.name = "VoiceRecordPlayer"
	_voice_record_player.stream = AudioStreamMicrophone.new()
	_voice_record_player.bus = VOICE_CAPTURE_BUS
	_voice_record_player.volume_db = 0.0
	_voice_record_player.autoplay = true
	add_child(_voice_record_player)

	_voice_playback_player = AudioStreamPlayer.new()
	_voice_playback_player.name = "VoicePlaybackPlayer"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 24000
	generator.buffer_length = 4.0
	_voice_playback_player.stream = generator
	_voice_playback_player.bus = "Master"
	_voice_playback_player.autoplay = false
	add_child(_voice_playback_player)

	var capture_bus_index: int = AudioServer.get_bus_index(VOICE_CAPTURE_BUS)
	if capture_bus_index < 0:
		AudioServer.add_bus()
		capture_bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(capture_bus_index, VOICE_CAPTURE_BUS)
	var silence_bus_index: int = AudioServer.get_bus_index(VOICE_SILENCE_BUS)
	if silence_bus_index < 0:
		AudioServer.add_bus()
		silence_bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(silence_bus_index, VOICE_SILENCE_BUS)
	AudioServer.set_bus_volume_db(capture_bus_index, 0.0)
	AudioServer.set_bus_volume_db(silence_bus_index, -80.0)
	AudioServer.set_bus_send(capture_bus_index, VOICE_SILENCE_BUS)
	_voice_record_effect = AudioEffectRecord.new()
	AudioServer.add_bus_effect(capture_bus_index, _voice_record_effect)
	_voice_capture_effect = AudioEffectCapture.new()
	_voice_capture_effect.buffer_length = 2.0
	AudioServer.add_bus_effect(capture_bus_index, _voice_capture_effect)
	set_process(true)

func _process(_delta: float) -> void:
	_drain_gemini_audio()
	if not _voice_recording_active or _voice_capture_effect == null:
		return
	if _gemini_client == null or not _gemini_client.is_connected_to_agent():
		return
	var frames_available: int = _voice_capture_effect.get_frames_available()
	if frames_available <= 0:
		return
	var frames: PackedVector2Array = _voice_capture_effect.get_buffer(frames_available)
	var pcm: PackedByteArray = _audio_frames_to_pcm(frames)
	if not pcm.is_empty():
		if _voice_debug:
			print("shared_nav: _process - frames_available=", frames_available, " pcm_bytes=", pcm.size())
		# send PCM to Gemini
		if _gemini_client != null and _gemini_client.is_connected_to_agent():
			if _voice_debug:
				print("shared_nav: sending PCM to Gemini (bytes=", pcm.size(), ")")
			_gemini_client.send_pcm(pcm)
		else:
			if _voice_debug:
				print("shared_nav: gemini client unavailable when attempting to send pcm")

func _drain_gemini_audio() -> void:
	if _gemini_audio_queue.is_empty() or _voice_playback_player == null:
		# Check if AI was talking and now should stop
		if _ai_talking_active:
			if _voice_playback_player != null and not _voice_playback_player.playing:
				_notify_character_animation("ai_stopped_talking")
				_ai_talking_active = false
		return
	if not _voice_playback_player.playing:
		_voice_playback_player.play()
	if _gemini_audio_playback == null:
		_gemini_audio_playback = _voice_playback_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _gemini_audio_playback == null:
		return
	var available_frames: int = _gemini_audio_playback.get_frames_available()
	if available_frames <= 0:
		return
	var frames_to_push: int = min(available_frames, _gemini_audio_queue.size())
	_gemini_audio_playback.push_buffer(_gemini_audio_queue.slice(0, frames_to_push))
	_gemini_audio_queue = _gemini_audio_queue.slice(frames_to_push)

func _audio_frames_to_pcm(frames: PackedVector2Array) -> PackedByteArray:
	if frames.is_empty():
		return PackedByteArray()
	var source_rate: int = 44100
	if AudioServer.has_method("get_input_mix_rate"):
		source_rate = int(AudioServer.get_input_mix_rate())
	elif AudioServer.has_method("get_mix_rate"):
		source_rate = int(AudioServer.get_mix_rate())
	var output_count: int = max(1, int(ceil(float(frames.size()) * 16000.0 / float(source_rate))))
	var pcm := PackedByteArray()
	pcm.resize(output_count * 2)
	for output_index in range(output_count):
		var source_index: int = min(frames.size() - 1, int(float(output_index) * float(source_rate) / 16000.0))
		var sample_float: float = (frames[source_index].x + frames[source_index].y) * 0.5
		var sample: int = clampi(int(sample_float * 32767.0), -32768, 32767)
		pcm[output_index * 2] = sample & 0xFF
		pcm[output_index * 2 + 1] = (sample >> 8) & 0xFF
	return pcm

func _toggle_voice_recording() -> void:
	if _voice_recording_active:
		_stop_voice_recording()
	else:
		_start_voice_recording()

func _start_voice_recording() -> void:
	if _voice_recording_active:
		return
	if _voice_record_effect == null:
		_setup_voice_recording()
	if _voice_record_effect == null:
		print("Unable to start voice recording: record effect unavailable")
		return
	if _voice_debug:
		print("shared_nav: _start_voice_recording() invoked")
	if not _select_voice_input_device():
		print("Voice recording unavailable: no valid input device detected on this machine.")
		return
	# Do not force device activation here. On Windows this can trigger an OS audio selection / permission popup
	# and block the app while the user is trying to talk. Use the default system input instead.
	_input_active = true
	await get_tree().process_frame
	if AudioServer.has_method("get_input_device"):
		print("Confirmed input device: ", AudioServer.get_input_device())

	var music_bus_index: int = AudioServer.get_bus_index("Music")
	if music_bus_index >= 0:
		_music_mute_before_recording = AudioServer.is_bus_mute(music_bus_index)
		_music_volume_before_recording = AudioServer.get_bus_volume_db(music_bus_index)
		if not _music_mute_before_recording:
			var faded_music_volume: float = max(_music_volume_before_recording - 14.0, -45.0)
			AudioServer.set_bus_volume_db(music_bus_index, faded_music_volume)

	if _voice_playback_player != null:
		_voice_playback_player.stop()
		_gemini_audio_playback = null
		_gemini_audio_queue.clear()
		_voice_playback_player.volume_db = -80.0
		_voice_playback_player.stream_paused = true
	if _voice_record_player != null:
		_voice_record_player.volume_db = -80.0
		_voice_record_player.play()
	_voice_record_effect.set_recording_active(true)
	if _voice_capture_effect != null:
		_voice_capture_effect.clear_buffer()
	_voice_recording_active = true
	print("Voice recording started (push-to-talk); music volume faded to keep background audio while recording")
	if _voice_debug:
		print("shared_nav: voice recording active, _voice_record_effect=", _voice_record_effect, " _voice_capture_effect=", _voice_capture_effect)

func _select_voice_input_device() -> bool:
	# Avoid forcing the OS input device. On Windows this can open a second microphone/device popup
	# and lock the app while the user is trying to talk. Use the default device instead.
	if AudioServer.has_method("get_input_device_list"):
		var input_devices: Array = AudioServer.get_input_device_list()
		if not input_devices.is_empty():
			var current_device: String = ""
			if AudioServer.has_method("get_input_device"):
				current_device = str(AudioServer.get_input_device()).strip_edges()
			if current_device.is_empty() and not input_devices.is_empty():
				current_device = str(input_devices[0]).strip_edges()
			if not current_device.is_empty():
				print("Using default microphone input: ", current_device)
			return true
		print("No audio input devices detected.")
		return false
	return true

func _stop_voice_recording() -> void:
	if not _voice_recording_active:
		return
	if _voice_record_effect == null:
		return
	var use_gemini: bool = _gemini_client != null and _gemini_client.is_connected_to_agent()
	# Shared locals used for both Gemini and REST fallback paths
	var recording: AudioStreamWAV = null
	var save_err: int = OK
	_voice_record_effect.set_recording_active(false)
	_voice_recording_active = false
	if _voice_capture_effect != null and use_gemini:
		var remaining_frames: PackedVector2Array = _voice_capture_effect.get_buffer(_voice_capture_effect.get_frames_available())
		var remaining_pcm: PackedByteArray = _audio_frames_to_pcm(remaining_frames)
		if _voice_debug:
			print("shared_nav: _stop_voice_recording - use_gemini=", use_gemini, " remaining_pcm_bytes=", remaining_pcm.size())
		if _voice_record_effect != null:
			recording = _voice_record_effect.get_recording()
			if recording != null and recording.data != null and recording.data.size() > 0:
				save_err = recording.save_to_wav(VOICE_RECORD_FILE)
				if save_err == OK:
					if _voice_debug:
						print("shared_nav: saved fallback recording to", VOICE_RECORD_FILE)
				else:
					print("shared_nav: failed to save fallback recording: ", save_err)
		if not remaining_pcm.is_empty():
			if _voice_debug:
				print("shared_nav: sending remaining PCM to Gemini (bytes=", remaining_pcm.size(), ")")
			_gemini_client.send_pcm(remaining_pcm)
		if _voice_debug:
			print("shared_nav: calling Gemini end_turn()")
		_gemini_client.end_turn()
		if _gemini_response_timer == null:
			_gemini_response_timer = Timer.new()
			_gemini_response_timer.one_shot = true
			_gemini_response_timer.wait_time = _gemini_response_timeout
			add_child(_gemini_response_timer)
			_gemini_response_timer.timeout.connect(func() -> void:
				print("shared_nav: Gemini response timeout; falling back to REST companion_voice")
				if _is_file_valid(VOICE_RECORD_FILE):
					_send_voice_recording_for_transcription(VOICE_RECORD_FILE)
				else:
					print("shared_nav: no fallback recording available for REST fallback")
				if is_instance_valid(_gemini_response_timer):
					_gemini_response_timer.queue_free()
				_gemini_response_timer = null
			)
			_gemini_response_timer.start()
	await get_tree().process_frame

	if not use_gemini and _voice_record_effect != null:
		recording = _voice_record_effect.get_recording()

	if _voice_record_player != null:
		_voice_record_player.stop()
		_voice_record_player.volume_db = 0.0
	if _voice_playback_player != null:
		_voice_playback_player.volume_db = 0.0
		_voice_playback_player.stream_paused = false
	var music_bus_index: int = AudioServer.get_bus_index("Music")
	if music_bus_index >= 0:
		AudioServer.set_bus_volume_db(music_bus_index, _music_volume_before_recording)
		AudioServer.set_bus_mute(music_bus_index, _music_mute_before_recording)
	_input_active = false

	if use_gemini:
		print("Gemini Live voice turn sent; realtime cleanup complete")
		return

	if recording == null:
		print("Voice recording stopped but no audio was captured. Hold the button while speaking.")
		return
	if recording.data == null or recording.data.size() < 16000:
		print("Voice recording is silent or too short. Please speak clearly for at least one second while holding the button.")
		return
	print("Captured voice recording bytes: ", recording.data.size())

	save_err = recording.save_to_wav(VOICE_RECORD_FILE)
	if save_err != OK:
		print("Failed to save voice recording: ", save_err)
		return

	if not _wav_has_meaningful_audio(VOICE_RECORD_FILE):
		print("Voice recording is silent or too short. Please speak louder and try again.")
		return
	_log_recording_signal(recording)

	print("Voice recording saved:", VOICE_RECORD_FILE)
	if _voice_debug:
		print("shared_nav: sending saved recording to backend for transcription (file=", VOICE_RECORD_FILE, ")")
	_send_voice_recording_for_transcription(VOICE_RECORD_FILE)

func _log_recording_signal(recording: AudioStreamWAV) -> void:
	if recording == null or recording.data == null or recording.data.size() < 2:
		return
	var peak: int = 0
	var sum_squares: float = 0.0
	var sample_count: int = 0
	for index in range(0, recording.data.size() - 1, 2):
		var sample: int = int(recording.data[index]) | (int(recording.data[index + 1]) << 8)
		if sample >= 32768:
			sample -= 65536
		var magnitude: int = abs(sample)
		peak = max(peak, magnitude)
		sum_squares += float(sample * sample)
		sample_count += 1
	var rms: float = sqrt(sum_squares / float(sample_count)) if sample_count > 0 else 0.0
	print("Recorded PCM signal: peak=", peak, " rms=", snapped(rms, 0.1), " samples=", sample_count)

func _wav_has_meaningful_audio(file_path: String) -> bool:
	var wav: AudioStreamWAV = AudioStreamWAV.load_from_file(file_path)
	if wav == null:
		print("Recorded WAV was null")
		return false

	var data: PackedByteArray = wav.data
	print("Saved WAV bytes: ", data.size())
	# Reject recordings that are too small (less than ~1s at typical rates) to avoid empty STT results
	if data.size() < 16000:
		print("Recorded WAV is too small to be real audio")
		return false
	return true

func _send_voice_recording_for_transcription(file_path: String) -> void:
	if _gemini_client != null and _gemini_client.has_method("is_connected_to_agent") and _gemini_client.is_connected_to_agent():
		var wav: AudioStreamWAV = AudioStreamWAV.load_from_file(file_path)
		if wav != null and wav.data != null and not wav.data.is_empty():
			print("Sending voice recording to Gemini Live WebSocket")
			_gemini_client.send_pcm(wav.data)
			return

	var backend: Node = _resolve_habi_backend()
	if backend == null:
		print("HabiBackend singleton unavailable")
		return

	var audio_base64: String = _load_file_base64(file_path)
	if audio_base64 == "":
		print("Recorded audio file is empty")
		return

	backend.companion_voice(audio_base64, "audio/wav", "", "Habi Friend", Callable(self, "_on_companion_voice_result"))

func _setup_gemini_client() -> void:
	if _gemini_client != null and is_instance_valid(_gemini_client):
		return
	var existing_client: Node = get_node_or_null("GeminiVoiceClient")
	if existing_client != null and is_instance_valid(existing_client):
		_gemini_client = existing_client
		if _gemini_client.has_signal("audio_received") and not _gemini_client.audio_received.is_connected(_on_gemini_audio_received):
			_gemini_client.audio_received.connect(_on_gemini_audio_received)
		if _gemini_client.has_signal("text_received") and not _gemini_client.text_received.is_connected(_on_gemini_text_received):
			_gemini_client.text_received.connect(_on_gemini_text_received)
		if _gemini_client.has_signal("connection_failed") and not _gemini_client.connection_failed.is_connected(_on_gemini_connection_failed):
			_gemini_client.connection_failed.connect(_on_gemini_connection_failed)
		return
	var client_script: Script = load("res://gemini_voice_client.gd") as Script
	if client_script == null:
		return
	_gemini_client = client_script.new()
	_gemini_client.name = "GeminiVoiceClient"
	add_child(_gemini_client)
	_gemini_client.audio_received.connect(_on_gemini_audio_received)
	_gemini_client.text_received.connect(_on_gemini_text_received)
	_gemini_client.connection_failed.connect(_on_gemini_connection_failed)
	_gemini_client.connect_agent()

func _on_gemini_connection_failed(message: String) -> void:
	print(message, "; REST voice fallback remains enabled")

func _on_gemini_audio_received(audio: PackedByteArray) -> void:
	if _voice_playback_player == null:
		_setup_voice_recording()
	if _voice_playback_player == null or audio.is_empty():
		return
	
	# Notify character animation manager that AI is talking (only once)
	if not _ai_talking_active:
		_notify_character_animation("ai_started_talking")
		_ai_talking_active = true

	if _voice_debug:
		print("shared_nav: _on_gemini_audio_received - audio_bytes=", audio.size())

	var frames := PackedVector2Array()
	frames.resize(int(audio.size() / 2.0))
	for index in range(frames.size()):
		var sample: int = int(audio[index * 2]) | (int(audio[index * 2 + 1]) << 8)
		if sample >= 32768:
			sample -= 65536
		var sample_float: float = float(sample) / 32768.0
		frames[index] = Vector2(sample_float, sample_float)
	_gemini_audio_queue.append_array(frames)

	# Cancel response timeout if running
	if _gemini_response_timer != null and is_instance_valid(_gemini_response_timer):
		_gemini_response_timer.stop()
		_gemini_response_timer.queue_free()
		_gemini_response_timer = null

func _on_gemini_text_received(text: String) -> void:
	if not text.strip_edges().is_empty():
		print("Gemini AI reply: ", text)

	# Cancel response timeout if running
	if _gemini_response_timer != null and is_instance_valid(_gemini_response_timer):
		_gemini_response_timer.stop()
		_gemini_response_timer.queue_free()
		_gemini_response_timer = null

func _on_companion_voice_result(success: bool, payload: Variant) -> void:
	if not success:
		print("Companion voice failed: ", payload)
		return

	if not (payload is Dictionary):
		print("Unexpected companion voice payload:", payload)
		return

	var transcript: String = str(payload.get("transcript", ""))
	var reply: String = str(payload.get("reply", ""))
	var audio_base64: String = str(payload.get("audioBase64", ""))
	var content_type: String = str(payload.get("audioContentType", "audio/wav"))

	print("User said: ", transcript)
	print("AI reply: ", reply)

	if audio_base64.strip_edges().is_empty():
		print("Companion voice returned no audio")
		return

	var audio_bytes: PackedByteArray = Marshalls.base64_to_raw(audio_base64)
	_notify_character_animation("ai_started_talking")
	_ai_talking_active = true
	_play_audio_bytes(audio_bytes, content_type)

func _on_stt_result(success: bool, payload: Variant) -> void:
	if not success:
		print("STT failed: ", payload)
		return

	var transcript: String = ""
	if payload is Dictionary:
		transcript = str(payload.get("text", payload.get("transcript", "")))
	else:
		transcript = str(payload)

	if transcript.strip_edges().is_empty():
		print("STT returned empty transcript")
		return

	print("User said: ", transcript)

	var backend: Node = _resolve_habi_backend()
	if backend == null:
		return
	backend.companion_chat(transcript, "Habi Friend", Callable(self, "_on_chat_result"))

func _on_chat_result(success: bool, payload: Variant) -> void:
	if not success:
		print("Chat failed: ", payload)
		return

	var reply: String = ""
	if payload is Dictionary:
		reply = str(payload.get("reply", payload.get("text", "")))
	else:
		reply = str(payload)

	if reply.strip_edges().is_empty():
		print("Chat response was empty")
		return

	print("AI reply: ", reply)

	var backend: Node = _resolve_habi_backend()
	if backend == null:
		return
	var voice_id: String = _get_preferred_voice_id()
	backend.companion_tts(reply, voice_id, Callable(self, "_on_tts_result"))

func _on_tts_result(success: bool, payload: Variant) -> void:
	if not success:
		print("TTS failed: ", payload)
		return

	var audio_bytes: PackedByteArray = PackedByteArray()
	var content_type: String = "audio/wav"

	if payload is Dictionary:
		if payload.has("bytes") and payload["bytes"] is PackedByteArray:
			audio_bytes = payload["bytes"]
			content_type = str(payload.get("content_type", "audio/wav"))
		elif payload.has("bytes_base64"):
			audio_bytes = Marshalls.base64_to_raw(str(payload["bytes_base64"]))
			content_type = str(payload.get("content_type", "audio/wav"))
		else:
			print("Unexpected TTS payload:", payload)
			return
	else:
		print("Unexpected TTS payload:", payload)
		return

	_play_audio_bytes(audio_bytes, content_type)

func _play_audio_bytes(bytes: PackedByteArray, content_type: String) -> void:
	# Prefer global AudioManager singleton if present (simpler, more reliable)
	if Engine.has_singleton("AudioManager"):
		var mgr = Engine.get_singleton("AudioManager")
		if mgr != null and mgr.has_method("play_audio_bytes"):
			mgr.call("play_audio_bytes", bytes, content_type)
			# Ensure animation notification will be fired when playback ends
			# If AudioManager has no finished signal, fall back to notify on next idle
			return

	# Fallback: local playback using existing player
	var stream: AudioStream = null
	if content_type.findn("wav") != -1:
		var wav: AudioStreamWAV = AudioStreamWAV.load_from_buffer(bytes)
		if wav != null:
			stream = wav
		else:
			var fallback_wav = AudioStreamWAV.new()
			fallback_wav.data = bytes
			fallback_wav.mix_rate = 44100
			fallback_wav.format = AudioStreamWAV.FORMAT_16_BITS
			stream = fallback_wav
	else:
		var mp3 = AudioStreamMP3.new()
		mp3.data = bytes
		stream = mp3

	if _voice_playback_player == null:
		_setup_voice_recording()
	if _voice_playback_player != null:
		# Connect to finished signal if not already connected
		if not _voice_playback_player.finished.is_connected(_on_audio_playback_finished):
			_voice_playback_player.finished.connect(_on_audio_playback_finished)

		_voice_playback_player.volume_db = -2.0
		_voice_playback_player.stream = stream
		_voice_playback_player.play()

func _on_audio_playback_finished() -> void:
	# Notify character animation manager that AI stopped talking
	_notify_character_animation("ai_stopped_talking")
	print("shared_nav: Audio playback finished")

func _load_file_base64(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return Marshalls.raw_to_base64(data)

func _is_file_valid(path: String) -> bool:
	if path == null or path == "":
		return false
	if not FileAccess.file_exists(path):
		return false
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var fsize = f.get_length()
	f.close()
	return fsize > 0

func _resolve_habi_backend() -> Node:
	var backend: Node = get_tree().root.get_node_or_null("HabiBackend")
	if backend != null:
		return backend
	if Engine.has_singleton("HabiBackend"):
		return Engine.get_singleton("HabiBackend")
	return null

func _get_selected_gender() -> String:
	var root = get_tree().root if get_tree() != null else null
	if root == null:
		return ""

	var candidates: Array[String] = [
		"selected_gender",
		"character_gender",
		"user_gender",
		"gender"
	]
	for key in candidates:
		if root.has_meta(key):
			var value = str(root.get_meta(key)).strip_edges().to_lower()
			if value.find("girl") != -1 or value.find("female") != -1 or value.find("boy") != -1 or value.find("male") != -1:
				return value

	if root.has_meta("question_answers"):
		var answers: Dictionary = root.get_meta("question_answers") as Dictionary
		for key in answers.keys():
			var value = str(answers[key]).strip_edges().to_lower()
			if value.find("girl") != -1 or value.find("female") != -1 or value.find("boy") != -1 or value.find("male") != -1:
				return value

	return ""

func _get_preferred_voice_id() -> String:
	# Return a voiceId string based on currently selected gender or meta-configured defaults.
	# Uses a female voice for girl/female selection and keeps the current/default male voice for boy/male.
	var root = get_tree().root if get_tree() != null else null
	if root == null:
		return "alloy"

	var gender: String = _get_selected_gender()
	var female_voice: String = "nova"
	var male_voice: String = "alloy"
	if root.has_meta("voice_id_female"):
		female_voice = str(root.get_meta("voice_id_female")).strip_edges()
	if root.has_meta("voice_id_male"):
		male_voice = str(root.get_meta("voice_id_male")).strip_edges()
	if female_voice.is_empty():
		female_voice = "nova"
	if male_voice.is_empty():
		male_voice = "alloy"

	if gender.find("girl") != -1 or gender.find("female") != -1:
		return female_voice
	if gender.find("boy") != -1 or gender.find("male") != -1:
		return male_voice

	if root.has_meta("voice_id_female") and str(root.get_meta("voice_id_female")).strip_edges() != "":
		return str(root.get_meta("voice_id_female")).strip_edges()
	if root.has_meta("voice_id_male") and str(root.get_meta("voice_id_male")).strip_edges() != "":
		return str(root.get_meta("voice_id_male")).strip_edges()
	return "alloy"

func _wire_voice_button() -> void:
	if _voice_button_wired:
		return
	var button: Button = null
	var candidate_paths: Array[String] = [
		"Panel5/MIC/Button",
		"Panel5/MicButton",
		"MIC/Button",
		"MicButton",
		"VoiceButton",
		"Panel/MIC/Button",
		"Panel2/MIC/Button"
	]
	for path in candidate_paths:
		button = get_node_or_null(path) as Button
		if button != null:
			break
	if button == null:
		for candidate in get_all_buttons():
			var name_lower: String = str(candidate.name).to_lower()
			var text_lower: String = str(candidate.text if candidate.text != null else "").to_lower()
			if name_lower.contains("mic") or name_lower.contains("voice") or text_lower.contains("mic") or text_lower.contains("voice") or text_lower.contains("talk"):
				button = candidate
				break
	if button == null:
		return
	var down_callback := Callable(self, "_on_voice_button_down")
	var up_callback := Callable(self, "_on_voice_button_up")
	if button.button_down.is_connected(down_callback):
		button.button_down.disconnect(down_callback)
	if button.button_up.is_connected(up_callback):
		button.button_up.disconnect(up_callback)
	if button.pressed.is_connected(down_callback):
		button.pressed.disconnect(down_callback)
	if button.pressed.is_connected(up_callback):
		button.pressed.disconnect(up_callback)
	button.button_down.connect(down_callback)
	button.button_up.connect(up_callback)
	button.set_meta("_habi_voice_button_wired", true)
	_voice_button_wired = true

func _on_voice_button_down() -> void:
	if _voice_recording_active:
		return
	_start_voice_recording()
	# Notify character animation manager
	_notify_character_animation("voice_recording_started")

func _on_voice_button_up() -> void:
	if not _voice_recording_active:
		return
	_stop_voice_recording()
	# Notify character animation manager
	_notify_character_animation("voice_recording_stopped")

func _notify_character_animation(event: String) -> void:
	# Notify the character animation manager if it exists.
	# Try a few common locations: as a child, under the scene root, or as an Engine singleton.
	var character_manager = null
	# 1) Local child
	if has_node("CharacterAnimationManager"):
		character_manager = get_node("CharacterAnimationManager")
	# 2) Scene root
	if character_manager == null and get_tree() != null and get_tree().root != null:
		var root_mgr = get_tree().root.get_node_or_null("CharacterAnimationManager")
		if root_mgr != null:
			character_manager = root_mgr
	# 3) Engine singleton
	if character_manager == null and Engine.has_singleton("CharacterAnimationManager"):
		character_manager = Engine.get_singleton("CharacterAnimationManager")

	if character_manager != null and character_manager.has_method("on_" + event):
		character_manager.call("on_" + event)
		print("shared_nav: Notified character animation manager of event: ", event)
	else:
		print("shared_nav: CharacterAnimationManager not found or missing method for event:", event)

func _on_settings_volume_changed(value: float, slider_name: String) -> void:
	# Generic handler to map slider values to audio bus volume (dB)
	var raw_val: float = float(value)
	var norm: float = 0.0
	if raw_val > 1.0:
		norm = clamp(raw_val / 100.0, 0.0, 1.0)
	else:
		norm = clamp(raw_val, 0.0, 1.0)
	var db: float = lerp(-80.0, 0.0, norm)
	var bus: String = "Master"
	var lname: String = str(slider_name).to_lower()
	if lname.find("music") != -1:
		bus = "Music"
	elif lname.find("sfx") != -1 or lname.find("effects") != -1:
		bus = "SFX"
	elif lname.find("voice") != -1:
		bus = "Voice"
	var idx: int = AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)
		print("shared_nav: set bus", bus, "volume to", db)

func _on_voice_selection_changed(index: int) -> void:
	var sel_node := get_node_or_null("Panel/Panel4/VoiceSelect") if get_tree() != null and get_tree().root != null else null
	if sel_node == null:
		sel_node = get_node_or_null("VoiceSelect")
	if sel_node == null or not sel_node is OptionButton:
		return
	var voice_id: String = sel_node.get_item_text(index).strip_edges()
	if voice_id == "":
		return
	var root = get_tree().root if get_tree() != null else null
	if root != null:
		root.set_meta("selected_voice", voice_id)
		print("shared_nav: selected voice set to", voice_id)

func _wire_settings_back_buttons() -> void:
	var home_callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP["home"])

	var sett2home_button: Button = get_node_or_null("sett2home") as Button
	if sett2home_button != null:
		if not sett2home_button.pressed.is_connected(home_callback):
			sett2home_button.pressed.connect(home_callback)

	var back_button: Button = get_node_or_null("Button") as Button
	if back_button != null:
		if not back_button.pressed.is_connected(home_callback):
			back_button.pressed.connect(home_callback)
	var close_button: Button = get_node_or_null("Button/Button") as Button
	if close_button != null:
		if not close_button.pressed.is_connected(home_callback):
			close_button.pressed.connect(home_callback)

func _wire_settings_audio_controls() -> void:
	# Ensure this method exists so deferred callers won't error.
	# Attempt to wire basic audio sliders and voice selector in Settings scene if present.
	if name != "Settings" or not is_inside_tree():
		return
	var wired: bool = false
	# Common slider locations/names used across scenes
	var slider_paths: Array = [
		"Panel/Panel4/MusicSlider",
		"Panel/Panel4/Music_Volume",
		"Panel2/MusicSlider",
		"MusicSlider",
		"music_slider",
		"Music_Volume",
		"Panel/Panel4/SFXSlider",
		"SFXSlider",
		"EffectsSlider",
		"effects_slider"
	]
	for path in slider_paths:
		var s = get_node_or_null(path)
		if s != null:
			# Connect a generic handler to update the corresponding audio bus
			if s.has_method("value_changed"):
				var conn = Callable(self, "_on_settings_volume_changed").bind(s.name)
				if not s.value_changed.is_connected(conn):
					s.value_changed.connect(conn)
				wired = true

	# Wire a simple voice selection control (OptionButton) if present
	var voice_select: Node = get_node_or_null("Panel/Panel4/VoiceSelect")
	if voice_select == null:
		voice_select = get_node_or_null("VoiceSelect")
	if voice_select != null and voice_select is OptionButton:
		if not voice_select.item_selected.is_connected(Callable(self, "_on_voice_selection_changed")):
			voice_select.item_selected.connect(Callable(self, "_on_voice_selection_changed"))
		wired = true

	if not wired:
		print("shared_nav: settings audio controls not found on Settings scene")

func _attach_button(node_name: String, fallback_label: String, scene_key: String) -> void:
	var button: Button = _locate_button(node_name, fallback_label)
	if button == null:
		return

	var callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP[scene_key])
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)

func _attach_button_by_label(label_text: String, scene_key: String) -> void:
	print("\n  [_attach_button_by_label] Looking for button: '", label_text, "' scene_key: '", scene_key, "'")
	var button: Button = _find_button_by_label(label_text)
	if button == null:
		print("  ✗ Button NOT found for label: '", label_text, "'")
		print("  📋 Available buttons on this scene:")
		for btn in get_all_buttons():
			print("      - '", btn.text, "' (node: ", btn.name, ")")
		return
	
	print("  ✓ Button found: '", button.text, "' at path: ", button.get_path())
	
	var callback: Callable
	if scene_key == "back":
		callback = Callable(self, "_go_back")
	else:
		if not NAV_MAP.has(scene_key):
			print("  ✗ Scene key '", scene_key, "' not found in NAV_MAP")
			return
		callback = Callable(self, "_switch_to_scene").bind(NAV_MAP[scene_key])
	
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)
		print("  ✓ Connected button to callback (target: ", NAV_MAP.get(scene_key, "back"), ")")
	else:
		print("  ℹ Button already connected")

func _switch_to_scene(target_scene: String) -> void:
	print("\n🔄 _switch_to_scene called: target='", target_scene, "'")
	var from_scene: String = _current_scene_path()
	print("  Current scene: '", from_scene, "'")
	if from_scene == target_scene:
		print("  ⚠️  Already on target scene, skipping")
		return

	var root: Node = get_tree().root if get_tree() != null else null
	var info_scenes: Array[String] = [
		NAV_MAP["about"],
		NAV_MAP["terms"],
		NAV_MAP["privacy"],
		NAV_MAP["helpsupport"]
	]
	if root != null:
		if info_scenes.has(target_scene) and from_scene.to_lower().ends_with("settings.tscn"):
			root.set_meta("opened_from_settings", true)
		else:
			if root.has_meta("opened_from_settings"):
				root.remove_meta("opened_from_settings")

	_history_record_transition(from_scene, target_scene)
	_sync_progress(target_scene)
	_safe_change_scene(target_scene)

func _go_back() -> void:
	var previous_scene: String = _history_previous_scene()
	if previous_scene.is_empty():
		# No history available — use smart fallback
		previous_scene = _get_smart_fallback_scene()
		if previous_scene.is_empty():
			return
		print("NavigationHistory empty — using smart fallback: %s" % previous_scene)
		_history_record_transition(_current_scene_path(), previous_scene)
		_safe_change_scene(previous_scene)
		return
	_history_record_transition(_current_scene_path(), previous_scene)
	_safe_change_scene(previous_scene)

func _get_smart_fallback_scene() -> String:
	var current = _current_scene_path().to_lower()
	
	# Smart fallback based on current scene
	if current.contains("values"):
		return NAV_MAP.get("home", "res://home.tscn")
	if current.contains("notification"):
		return NAV_MAP.get("home", "res://home.tscn")
	if current.contains("settings"):
		return NAV_MAP.get("home", "res://home.tscn")
	if current.contains("spiritual"):
		return NAV_MAP.get("home", "res://home.tscn")
	if current.contains("guidance"):
		return NAV_MAP.get("home", "res://home.tscn")
	if current.contains("shop"):
		return NAV_MAP.get("home", "res://home.tscn")
	if current.contains("popup"):
		# For popup scenes, return to the main scene
		if current.contains("values"):
			return NAV_MAP.get("values", "res://values.tscn")
		if current.contains("spiritual"):
			return NAV_MAP.get("spiritual", "res://spiritual.tscn")
		return NAV_MAP.get("home", "res://home.tscn")
	
	# Default fallback to home
	return NAV_MAP.get("home", "res://home.tscn")

func _safe_change_scene(target_scene: String) -> void:
	print("  [_safe_change_scene] Loading: '", target_scene, "'")
	if not is_instance_valid(self) or is_queued_for_deletion():
		print("  ✗ Node not valid or queued for deletion")
		return
	if not is_inside_tree():
		print("  ✗ Node not in tree")
		return
	var scene_resource: Variant = load(target_scene)
	if not (scene_resource is PackedScene):
		print("  ✗ Scene resource could not be loaded")
		push_warning("Scene resource could not be loaded: %s" % target_scene)
		return
	print("  ✓ Scene resource loaded: ", scene_resource)
	var tree: SceneTree = get_tree()
	if tree == null:
		print("  ✗ SceneTree is null")
		return
	if tree.has_method("change_scene_to_packed"):
		print("  ✓ Using change_scene_to_packed")
		tree.change_scene_to_packed(scene_resource)
	elif tree.has_method("change_scene_to_file"):
		print("  ✓ Using change_scene_to_file")
		tree.change_scene_to_file(target_scene)
	else:
		print("  ✗ No scene change method available")

func _sync_progress(target_scene: String) -> void:
	if _last_synced_scene == target_scene:
		return
	if _auth_manager == null:
		_auth_manager = _resolve_auth_manager()
	if _session == null:
		_session = _resolve_session()
	if _auth_manager == null or _session == null:
		return
	var payload: Dictionary = {
		"scene": _scene_key_for(target_scene),
		"user_id": _session.get_current_user_id(),
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"authenticated": _session.is_authenticated
	}
	_last_synced_scene = target_scene
	_auth_manager.save_progress(_session.get_current_user_id(), payload, func(ok, body):
		if ok:
			print("Progress synced to Firebase")
		else:
			print("Progress sync failed: ", body)
	)

func _record_current_scene() -> void:
	var history: Node = _resolve_history()
	if history != null and history.has_method("record_scene"):
		history.record_scene(_current_scene_path())

func _current_scene_path() -> String:
	if get_tree() != null and get_tree().current_scene != null:
		var current_scene_path: String = get_tree().current_scene.scene_file_path
		if not current_scene_path.is_empty():
			return current_scene_path
	return get_script().resource_path

func _history_record_transition(from_scene: String, to_scene: String) -> void:
	var history: Node = _resolve_history()
	if history != null and history.has_method("record_transition"):
		history.record_transition(from_scene, to_scene)

func _history_previous_scene() -> String:
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

func _scene_key_for(target_scene: String) -> String:
	if target_scene.contains("myprog"):
		return "myprog"
	if target_scene.contains("moodcheck"):
		return "moodcheck"
	if target_scene.contains("settings"):
		return "settings"
	if target_scene.contains("myjournal"):
		return "myjournal"
	if target_scene.contains("progress"):
		return "progress"
	if target_scene.contains("journal"):
		return "journal"
	if target_scene.contains("Shop"):
		return "shop"
	if target_scene.contains("guidance"):
		return "guidance"
	return "home"



func _get_user_gender() -> String:
	# Get user's gender from stored answers or profile
	# Get gender from stored answers
	var root: Window = get_tree().root
	var answers: Dictionary = root.get_meta("question_answers", {})
	
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

func _load_journal_entries_view() -> void:
	print("\n📖 [_load_journal_entries_view] Starting journal load")
	if name != "Journal" or not has_method("_show_journal_entries"):
		print("  ✗ Scene is not Journal or _show_journal_entries method not found")
		return
	var journal_renderer: Callable = Callable(self, "_show_journal_entries")
	if not journal_renderer.is_valid():
		print("  ✗ Journal renderer callable is invalid")
		return
	if _auth_manager == null:
		_auth_manager = _resolve_auth_manager()
	if _session == null:
		_session = _resolve_session()
	var user_id: String = "guest_user"
	if _session != null and _session.has_method("get_current_user_id"):
		user_id = _session.get_current_user_id()
	print("  User ID: ", user_id)
	if _auth_manager == null or not _auth_manager.has_method("load_journal_entries"):
		print("  ✗ Auth manager unavailable, using empty dict")
		journal_renderer.call({})
		return
	_auth_manager.load_journal_entries(user_id, func(ok, body):
		print("  📦 Callback received: ok=", ok, " body type=", typeof(body))
		if not is_instance_valid(self) or not journal_renderer.is_valid():
			print("  ✗ Scene or renderer is invalid")
			return
		journal_renderer.call(body if ok and body is Dictionary else {})
	)

func _show_journal_entries(entries_body: Dictionary) -> void:
	print("\n📖 [_show_journal_entries] Rendering ", entries_body.size(), " entries")
	var panel_host: Control = get_node_or_null("Panel3/Panel") as Control
	if panel_host == null:
		panel_host = get_node_or_null("Panel3") as Control
	if panel_host == null:
		panel_host = self

	print("  Panel host: ", str(panel_host.name) if panel_host != null else "null")
	for child in panel_host.get_children():
		if child.name == "JournalScroll" or child.name == "EntryList" or child.name.begins_with("EntryPanel"):
			child.queue_free()

	var scroll_area: ScrollContainer = panel_host.get_node_or_null("JournalScroll") as ScrollContainer
	if scroll_area == null:
		scroll_area = ScrollContainer.new()
		scroll_area.name = "JournalScroll"
		scroll_area.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll_area.offset_left = 8
		scroll_area.offset_top = 8
		scroll_area.offset_right = -8
		scroll_area.offset_bottom = -8
		scroll_area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_area.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		panel_host.add_child(scroll_area)

	var list: VBoxContainer = scroll_area.get_node_or_null("EntryList") as VBoxContainer
	if list == null:
		list = VBoxContainer.new()
		list.name = "EntryList"
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 12)
		scroll_area.add_child(list)

	if entries_body.is_empty():
		var empty_label: Label = Label.new()
		empty_label.name = "EntryPanel_Empty"
		empty_label.text = "No journal entries yet."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.custom_minimum_size = Vector2(0, 60)
		list.add_child(empty_label)
		_apply_journal_scrollbar(scroll_area, list, panel_host)
		return

	var entry_keys: Array = entries_body.keys()
	entry_keys.sort_custom(func(a, b): return str(a) > str(b))
	print("  📋 Entry keys: ", entry_keys)
	var rendered_count: int = 0
	for key in entry_keys:
		var item: Variant = entries_body.get(key)
		if not (item is Dictionary):
			print("    ✗ Skipping key='", key, "' - not a dictionary")
			continue
		var entry_text: String = str(item.get("entry", "")).strip_edges()
		var created_at: String = str(item.get("created_at", "")).strip_edges()
		if entry_text.is_empty():
			print("    ✗ Skipping key='", key, "' - empty entry text")
			continue

		print("    ✓ Rendering key='", key, "' created_at='", created_at, "'")
		rendered_count += 1
		var card: Panel = Panel.new()
		card.name = "EntryPanel_" + str(key)
		card.custom_minimum_size = Vector2(0, 96)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
		style.border_color = Color(0.8, 0.8, 0.8, 1.0)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 18
		style.corner_radius_top_right = 18
		style.corner_radius_bottom_right = 18
		style.corner_radius_bottom_left = 18
		card.add_theme_stylebox_override("panel", style)
		list.add_child(card)

		var date_label: Label = Label.new()
		date_label.name = "EntryDate_" + str(key)
		date_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		date_label.offset_left = 18
		date_label.offset_top = 10
		date_label.offset_right = -18
		date_label.offset_bottom = 0
		date_label.add_theme_font_size_override("font_size", 12)
		date_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1.0))
		date_label.text = created_at if not created_at.is_empty() else "Recent entry"
		card.add_child(date_label)

		var entry_label: Label = Label.new()
		entry_label.name = "EntryLabel_" + str(key)
		entry_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		entry_label.anchor_right = 1.0
		entry_label.anchor_bottom = 1.0
		entry_label.offset_left = 18
		entry_label.offset_top = 34
		entry_label.offset_right = -18
		entry_label.offset_bottom = -12
		entry_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		entry_label.add_theme_font_size_override("font_size", 15)
		entry_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12, 1.0))
		entry_label.text = entry_text
		card.add_child(entry_label)

	print("  ✓ Rendered ", rendered_count, " entries")
	_apply_journal_scrollbar(scroll_area, list, panel_host)

func _apply_journal_scrollbar(scroll_area: ScrollContainer, list: VBoxContainer, container: Control) -> void:
	var visible_height: float = max(1.0, container.size.y - 16.0)
	var content_height: float = max(visible_height, list.get_combined_minimum_size().y + 16.0)
	list.custom_minimum_size = Vector2(0.0, content_height)
	list.size = Vector2(scroll_area.size.x - 28.0, content_height)
	scroll_area.set_deferred("vertical_scroll_mode", ScrollContainer.SCROLL_MODE_AUTO)
	scroll_area.set_deferred("horizontal_scroll_mode", ScrollContainer.SCROLL_MODE_DISABLED)
	scroll_area.set_deferred("follow_focus", true)
	var scrollbar: Control = get_node_or_null("Panel3/journal/VScrollBar") as Control
	if scrollbar != null:
		scrollbar.queue_free()

func _update_journal_scroll(_value: float, _scroll_area: ScrollContainer) -> void:
	return

func _find_or_create_entries_label() -> Label:
	return Label.new()

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

func _locate_button(node_name: String, fallback_label: String) -> Button:
	var direct_match: Node = find_child(node_name, true, false)
	if direct_match is Button:
		return direct_match as Button

	return _find_button_by_label(fallback_label)

func _find_button_by_label(label_text: String) -> Button:
	var found_buttons: Array = []
	var search_text = label_text.to_lower()
	
	for child in get_children():
		var found: Button = _search_branch_for_button(child, label_text, found_buttons)
		if found != null:
			return found
	
	# Not found - show what we found instead
	if not found_buttons.is_empty():
		print("    [_find_button_by_label] NOT found '", label_text, "' but found these buttons:")
		for btn in found_buttons:
			var button = btn as Button
			if button != null:
				print("      - '", button.text, "' (match: ", button.text.to_lower() == search_text, ")")
	
	return null

func get_all_buttons() -> Array:
	var buttons: Array = []
	_collect_all_buttons(self, buttons)
	return buttons

func _collect_all_buttons(node: Node, buttons: Array) -> void:
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		_collect_all_buttons(child, buttons)

func _find_button_by_label_debug_only(label_text: String) -> Button:
	var debug_buttons: Array = []
	for child in get_children():
		var found: Button = _search_branch_for_button(child, label_text, debug_buttons)
		if found != null:
			return found
	return null

func _search_branch_for_button(node: Node, label_text: String, found_buttons: Array = []) -> Button:
	if node == null:
		return null

	if node is Button:
		var button: Button = node as Button
		found_buttons.append(button)
		
		# Exact match
		if button.text == label_text:
			return button
		
		# Case-insensitive match
		if button.text.to_lower() == label_text.to_lower():
			return button
		
		# Check label inside button
		var label: Label = _first_label_under(button)
		if label != null:
			if label.text == label_text or label.text.to_lower() == label_text.to_lower():
				return button

	for child in node.get_children():
		var found: Button = _search_branch_for_button(child, label_text, found_buttons)
		if found != null:
			return found

	return null

func _first_label_under(node: Node) -> Label:
	if node == null:
		return null

	for child in node.get_children():
		if child is Label:
			return child as Label
		var nested: Label = _first_label_under(child)
		if nested != null:
			return nested
	return null

func _debug_button_pressed(node_path: String, target_scene: String) -> void:
	print("[shared_nav DEBUG] button pressed:", node_path, "->", target_scene)
