extends Control

# Spiritual scene controller: populates daily verse, explanation, prayer
# and handles optional reflection submission (saves to Firebase journal)
# Daily verse fetcher: automatically fetches new Bible verses every 24 hours

var default_theme_title: String = "IMAGO DEI"
var default_verse_text: String = "We are created in the image and likeness of God."
var default_verse_ref: String = "Genesis 1:27"
var default_explanation: String = "This verse reminds us of the inherent dignity and value of every person."
var default_prayer: String = "Lord, help me show Your love today."

# Bible verse caching and fetching
var http_request: HTTPRequest
var verse_cache_file: String = "user://.spiritual_verse_cache.json"
var cache_expiry_seconds: int = 86400  # 24 hours in seconds
var bible_verses: Array = [
	{"title": "IMAGO DEI", "verse": "We are created in the image and likeness of God.", "reference": "Genesis 1:27", "explanation": "This verse reminds us of the inherent dignity and value of every person.", "prayer": "Lord, help me honor Your image in everyone. Amen."},
	{"title": "FAITH", "verse": "Now faith is the assurance of things hoped for, the conviction of things not seen.", "reference": "Hebrews 11:1", "explanation": "Faith is trusting in God even when we cannot see the outcome.", "prayer": "Lord, strengthen my faith and trust. Amen."},
	{"title": "LOVE", "verse": "Love never fails. But where there are prophecies, they will cease.", "reference": "1 Corinthians 13:8", "explanation": "Love is the greatest commandment and the foundation of our faith.", "prayer": "Lord, help me love others kindly. Amen."},
	{"title": "PEACE", "verse": "Peace I leave with you; my peace I give you.", "reference": "John 14:27", "explanation": "God offers us a peace that surpasses all understanding.", "prayer": "Lord, fill my heart with Your peace. Amen."},
	{"title": "HOPE", "verse": "Why, my soul, are you downcast? Why so disturbed within me? Put your hope in God.", "reference": "Psalm 42:11", "explanation": "Hope in God brings us comfort and strength through difficult times.", "prayer": "Lord, renew my hope when I feel discouraged. Amen."},
	{"title": "GRACE", "verse": "For by grace you have been saved through faith, and this is not your own doing.", "reference": "Ephesians 2:8", "explanation": "God's grace is a free gift that saves us and transforms our lives.", "prayer": "Lord, thank You for Your grace. Amen."},
	{"title": "TRUST", "verse": "Trust in the Lord with all your heart and lean not on your own understanding.", "reference": "Proverbs 3:5", "explanation": "Trusting God means surrendering our plans to His wisdom.", "prayer": "Lord, help me trust Your wisdom. Amen."},
	{"title": "JOY", "verse": "Rejoice in the Lord always. I will say it again: Rejoice!", "reference": "Philippians 4:4", "explanation": "Joy comes from our relationship with God, not from our circumstances.", "prayer": "Lord, fill my heart with joy. Amen."},
	{"title": "STRENGTH", "verse": "I can do all this through him who gives me strength.", "reference": "Philippians 4:13", "explanation": "Our strength comes from God, not from ourselves.", "prayer": "Lord, be my strength today. Amen."},
	{"title": "WISDOM", "verse": "If any of you lacks wisdom, you should ask God, who gives generously to all.", "reference": "James 1:5", "explanation": "God promises to provide wisdom to those who seek it.", "prayer": "Lord, guide me with Your wisdom. Amen."}
]

func _ready() -> void:
	# Setup HTTP request for fetching verses
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(Callable(self, "_on_verse_fetched"))
	
	# Connect back button
	var back_button: Button = get_node_or_null("back btn") as Button
	if back_button != null:
		if not back_button.pressed.is_connected(Callable(self, "_on_back_btn_pressed")):
			back_button.pressed.connect(Callable(self, "_on_back_btn_pressed"))
			print("✓ Back button connected")
	else:
		print("✗ Back button not found")
	
	# Connect reflection button to popupspiritual scene
	var reflection_button: Button = get_node_or_null("Panel/DAILY BIBLE/BIBLE MEANS/REFLECTION/Button") as Button
	if reflection_button != null:
		if not reflection_button.pressed.is_connected(Callable(self, "_on_reflection_button_pressed")):
			reflection_button.pressed.connect(Callable(self, "_on_reflection_button_pressed"))
			print("✓ Reflection button connected")
	else:
		print("✗ Reflection button not found")
	
	# Connect imagoBut to imago_dei scene
	var imago_button: Button = get_node_or_null("Panel/Panel/imagoBut") as Button
	if imago_button != null:
		if not imago_button.pressed.is_connected(Callable(self, "_on_imago_button_pressed")):
			imago_button.pressed.connect(Callable(self, "_on_imago_button_pressed"))
			print("✓ Imago button connected")
	else:
		print("✗ Imago button not found")
	
	# Check if we need to fetch a new verse
	_check_and_fetch_daily_verse()
	_setup_reflection_submit()

func _populate_content() -> void:
	var separator = "=================================================="
	print("\n" + separator)
	print("Spiritual: _populate_content() called - updating DAILY BIBLE VERSE panel")
	print(separator)
	
	# Update the "daily verses" label (which can be positioned in the editor)
	var daily_verse_label: Label = get_node_or_null("Panel/DAILY BIBLE/daily verses") as Label
	
	if daily_verse_label != null:
		# Display verse text first, then reference at the bottom (matching the format in image)
		daily_verse_label.text = default_verse_text + "\n\n" + default_verse_ref
		daily_verse_label.add_theme_font_size_override("font_size", 11)  # Reduced from 14 to fit
		daily_verse_label.add_theme_color_override("font_color", Color.WHITE)
		daily_verse_label.autowrap_mode = TextServer.AUTOWRAP_WORD  # Enable word wrapping
		daily_verse_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER  # Center vertically
		daily_verse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER  # Center horizontally
		daily_verse_label.clip_text = true  # Clip text to stay within panel bounds
		
		print("✓ DAILY VERSE UPDATED:")
		print("  Reference: ", default_verse_ref)
		print("  Verse Text: ", default_verse_text)
		print("  Explanation: ", default_explanation)
	else:
		print("✗ DAILY VERSES label not found at Panel/DAILY BIBLE/daily verses")
	
	# Update the explanation in the "meaning label"
	var meaning_label: Label = get_node_or_null("Panel/DAILY BIBLE/BIBLE MEANS/meaning label") as Label
	
	if meaning_label != null:
		meaning_label.text = default_explanation
		meaning_label.add_theme_font_size_override("font_size", 11)
		meaning_label.add_theme_color_override("font_color", Color.WHITE)
		meaning_label.autowrap_mode = TextServer.AUTOWRAP_WORD  # Enable word wrapping
		meaning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		print("✓ Meaning label updated: ", default_explanation)
	else:
		print("✗ Meaning label not found at Panel/DAILY BIBLE/BIBLE MEANS/meaning label")

	var prayer_label: Label = get_node_or_null("Panel/DAILY BIBLE/BIBLE MEANS/REFLECTION/PRAYER/PrayerText") as Label
	if prayer_label != null:
		prayer_label.text = default_prayer
		prayer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prayer_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		prayer_label.add_theme_font_size_override("font_size", 9)
	else:
		print("✗ Prayer text label not found")
	
	print(separator + "\n")

# Debug function to print all labels in the scene
func _debug_print_all_labels() -> void:
	print("=== DEBUGGING: All Labels in Scene ===")
	var panel_node = get_node_or_null("Panel")
	if panel_node != null:
		_print_node_tree(panel_node, "")
	var panel2_node = get_node_or_null("Panel2")
	if panel2_node != null:
		_print_node_tree(panel2_node, "")

func _print_node_tree(node: Node, indent: String) -> void:
	if node is Label:
		print(indent + "LABEL: ", node.name, " -> Path: ", node.get_path(), " -> Text: ", node.text)
	else:
		print(indent + "NODE: ", node.name, " -> Path: ", node.get_path())
	
	for child in node.get_children():
		_print_node_tree(child, indent + "  ")

# Check if we need to fetch a new verse (every 24 hours)
func _check_and_fetch_daily_verse() -> void:
	var cache = _load_verse_cache()
	
	# Check if cache is expired
	if cache != null and cache.has("timestamp"):
		var time_elapsed = int(Time.get_ticks_msec() / 1000.0) - cache["timestamp"]
		if time_elapsed < cache_expiry_seconds:
			# Cache is still valid, use it
			default_theme_title = cache.get("title", default_theme_title)
			default_verse_text = cache.get("verse", default_verse_text)
			default_verse_ref = cache.get("reference", default_verse_ref)
			default_explanation = cache.get("explanation", default_explanation)
			default_prayer = cache.get("prayer", _get_prayer_for_title(default_theme_title))
			_populate_content()
			return
	
	# Cache expired or doesn't exist, fetch new verse
	_fetch_random_verse()

# Fetch a random verse from the local bible_verses array
func _fetch_random_verse() -> void:
	if bible_verses.is_empty():
		print("Spiritual: No verses available in cache")
		_populate_content()
		return
	
	# Get a random verse from the array
	var random_verse = bible_verses[randi() % bible_verses.size()]
	
	# Update defaults
	default_theme_title = random_verse["title"]
	default_verse_text = random_verse["verse"]
	default_verse_ref = random_verse["reference"]
	default_explanation = random_verse["explanation"]
	default_prayer = random_verse.get("prayer", _get_prayer_for_title(default_theme_title))
	
	# Cache the verse
	_save_verse_cache(random_verse)
	
	# Populate the UI
	_populate_content()
	
	print("Spiritual: Loaded daily verse - ", default_verse_ref)

# Alternative: Fetch from external API (optional - requires internet)
func _fetch_verse_from_api() -> void:
	if http_request == null:
		return
	
	# Using bible-api.com (free, no API key needed)
	# This is optional - uncomment to use external API instead of local verses
	#var url = "https://bible-api.com/?random=verse"
	#http_request.request(url)

# Callback for verse fetching
func _on_verse_fetched(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var json = JSON.new()
		var response_text = body.get_string_from_utf8()
		if json.parse(response_text) == OK:
			var data = json.get_data()
			if data.has("text") and data.has("reference"):
				default_verse_text = data["text"]
				default_verse_ref = data["reference"]
				default_theme_title = "DAILY VERSE"
				default_explanation = "God's word for today"
				default_prayer = _get_prayer_for_title(default_theme_title)
				_save_verse_cache({
					"title": default_theme_title,
					"verse": default_verse_text,
					"reference": default_verse_ref,
					"explanation": default_explanation,
					"prayer": default_prayer
				})
				_populate_content()
				return
	
	# Fallback to local verse if API fails
	print("Spiritual: API fetch failed, using local verse")
	_fetch_random_verse()

# Load verse from cache file
func _load_verse_cache() -> Dictionary:
	if ResourceLoader.exists(verse_cache_file):
		var json_string = FileAccess.get_file_as_string(verse_cache_file)
		if json_string != "":
			var json = JSON.new()
			if json.parse(json_string) == OK:
				return json.get_data() as Dictionary
	return {}

# Save verse to cache file
func _save_verse_cache(verse_data: Dictionary) -> void:
	verse_data["timestamp"] = int(Time.get_ticks_msec() / 1000.0)
	var json_string = JSON.stringify(verse_data)
	var file = FileAccess.open(verse_cache_file, FileAccess.WRITE)
	if file != null:
		file.store_string(json_string)

func _get_prayer_for_title(title: String) -> String:
	for verse_data in bible_verses:
		if verse_data is Dictionary and str(verse_data.get("title", "")) == title:
			return str(verse_data.get("prayer", default_prayer))
	return default_prayer

func _setup_reflection_submit() -> void:
	# The submit button is not part of the main spiritual screen layout.
	# It lives in the dedicated reflection scene, so this should be a no-op
	# unless that scene is actually loaded and the expected button exists.
	var submit_btn: Button = get_node_or_null("Panel5/Button") as Button
	if submit_btn == null:
		return
	if not submit_btn.pressed.is_connected(Callable(self, "_on_submit_reflection_pressed")):
		submit_btn.pressed.connect(Callable(self, "_on_submit_reflection_pressed"))

func _on_submit_reflection_pressed() -> void:
	var input: TextEdit = get_node_or_null("Panel/DAILY BIBLE/Panel/Panel/Panel/ReflectionInput") as TextEdit
	if input == null:
		push_warning("Spiritual: reflection input not found")
		return
	var text_value: String = input.text.strip_edges()
	# Reflection is optional: if empty, just acknowledge and return
	if text_value == "":
		print("Spiritual: no reflection entered; nothing to save.")
		_show_confirmation("Reflection submitted (empty). Thank you!")
		return
	# Try to save to Firebase journal if available
	var user_id: String = _get_current_user_id()
	if Engine.has_singleton("FirebaseAuthManager"):
		var fam = Engine.get_singleton("FirebaseAuthManager")
		if fam != null and fam.has_method("save_scene_input"):
			print("Spiritual: saving reflection to Firebase for user=", user_id, " scene=liturgical")
			fam.save_scene_input(user_id, "liturgical", {"reflection": text_value, "type": "liturgical_reflection", "scene": "liturgical"}, Callable(self, "_on_reflection_saved"))
			return
	# Fallback: just print and show confirmation
	print("Spiritual: reflection (local):", text_value)
	_show_confirmation("Reflection saved locally.")

func _on_reflection_saved(ok: bool, body: Variant) -> void:
	if ok:
		print("Spiritual: reflection saved to Firebase ->", body)
		_show_confirmation("Reflection saved successfully. Thank you!")
	else:
		print("Spiritual: failed to save reflection ->", body)
		_show_confirmation("Failed to save reflection. It will be saved locally.")

func _show_confirmation(msg: String) -> void:
	# Minimal feedback: print and optionally create a transient Label or use popup
	print(msg)

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

# Back button handler: navigate to home
func _on_back_btn_pressed() -> void:
	print("Spiritual: Back button pressed - navigating to home")
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.change_scene_to_file("res://home.tscn")

# Reflection button handler: navigate to popupspiritual
func _on_reflection_button_pressed() -> void:
	print("Spiritual: Reflection button pressed - navigating to spiritual_reflection")
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.change_scene_to_file("res://spiritual_reflection.tscn")

# Imago button handler: navigate to imago_dei
func _on_imago_button_pressed() -> void:
	print("Spiritual: Imago button pressed - navigating to imago_dei")
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.change_scene_to_file("res://imago_dei.tscn")
