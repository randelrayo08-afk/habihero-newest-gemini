extends Control
# Voice Companion Integration Example
# Wire this to your home screen or guidance screen UI

@export var show_voice_ui: bool = true
@export var show_text_ui: bool = true

var _voice_companion: Node = null
var _voice_button: Button = null
var _status_label: Label = null
var _transcript_label: Label = null
var _reply_label: Label = null
var _chat_input: LineEdit = null
var _chat_send_button: Button = null

func _ready() -> void:
	# Get or create voice companion
	_voice_companion = _get_or_create_voice_companion()
	if _voice_companion == null:
		print("VoiceCompanionUI: failed to initialize voice companion")
		return
	
	# Connect signals
	_voice_companion.voice_started.connect(_on_voice_started)
	_voice_companion.voice_stopped.connect(_on_voice_stopped)
	_voice_companion.processing_started.connect(_on_processing_started)
	_voice_companion.processing_finished.connect(_on_processing_finished)
	_voice_companion.transcription_received.connect(_on_transcription_received)
	_voice_companion.reply_received.connect(_on_reply_received)
	_voice_companion.error_occurred.connect(_on_error_occurred)
	
	# Setup UI elements
	if show_voice_ui:
		_setup_voice_ui()
	
	if show_text_ui:
		_setup_text_ui()
	
	print("VoiceCompanionUI: ready")

func _get_or_create_voice_companion() -> Node:
	"""Get existing voice companion or create new one"""
	if get_tree() != null and get_tree().root != null:
		var existing = get_tree().root.get_node_or_null("VoiceCompanionRest")
		if existing != null:
			return existing
	
	# Create new voice companion
	var companion = load("res://voice_companion_rest.gd").new()
	get_tree().root.add_child.call_deferred(companion)
	companion.name = "VoiceCompanionRest"
	return companion

func _setup_voice_ui() -> void:
	"""Create voice control UI elements"""
	# Status label
	_status_label = Label.new()
	_status_label.text = "Ready to talk"
	_status_label.add_theme_font_size_override("font_size", 14)
	add_child(_status_label)
	
	# Transcript display
	_transcript_label = Label.new()
	_transcript_label.text = ""
	_transcript_label.add_theme_font_size_override("font_size", 12)
	_transcript_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_transcript_label)
	
	# Reply display
	_reply_label = Label.new()
	_reply_label.text = ""
	_reply_label.add_theme_font_size_override("font_size", 12)
	_reply_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_reply_label)
	
	# Voice button
	_voice_button = Button.new()
	_voice_button.text = "🎤 Press to Talk"
	_voice_button.pressed.connect(_on_voice_button_pressed)
	_voice_button.released.connect(_on_voice_button_released)
	add_child(_voice_button)

func _setup_text_ui() -> void:
	"""Create text chat UI elements"""
	# Chat input
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Type your message..."
	add_child(_chat_input)
	
	# Send button
	_chat_send_button = Button.new()
	_chat_send_button.text = "Send"
	_chat_send_button.pressed.connect(_on_chat_send_pressed)
	add_child(_chat_send_button)

func _on_voice_button_pressed() -> void:
	"""Start recording when button is pressed"""
	if _voice_companion:
		_voice_companion.start_voice_recording()
		if _voice_button:
			_voice_button.text = "🎤 Recording..."

func _on_voice_button_released() -> void:
	"""Stop recording when button is released"""
	if _voice_companion:
		_voice_companion.stop_voice_recording()
		if _voice_button:
			_voice_button.text = "🎤 Processing..."

func _on_voice_started() -> void:
	if _status_label:
		_status_label.text = "Recording voice..."

func _on_voice_stopped() -> void:
	if _status_label:
		_status_label.text = "Processing audio..."

func _on_processing_started() -> void:
	if _voice_button:
		_voice_button.disabled = true
	if _chat_send_button:
		_chat_send_button.disabled = true

func _on_processing_finished() -> void:
	if _voice_button:
		_voice_button.disabled = false
		_voice_button.text = "🎤 Press to Talk"
	if _chat_send_button:
		_chat_send_button.disabled = false

func _on_transcription_received(text: String) -> void:
	print("VoiceCompanionUI: you said '%s'" % text)
	if _transcript_label:
		_transcript_label.text = "You: " + text

func _on_reply_received(text: String, audio_data: PackedByteArray) -> void:
	print("VoiceCompanionUI: companion replied '%s'" % text)
	if _reply_label:
		_reply_label.text = "Habi: " + text
	if _status_label:
		_status_label.text = "✓ Reply played" if not audio_data.is_empty() else "✓ Reply received"

func _on_error_occurred(error_msg: String) -> void:
	print("VoiceCompanionUI: error - " + error_msg)
	if _status_label:
		_status_label.text = "Error: " + error_msg
	if _voice_button:
		_voice_button.disabled = false
		_voice_button.text = "🎤 Press to Talk"

func _on_chat_send_pressed() -> void:
	"""Send text message"""
	if not _chat_input or _chat_input.text.is_empty():
		return
	
	var message = _chat_input.text
	_chat_input.clear()
	
	if _transcript_label:
		_transcript_label.text = "You: " + message
	
	if _voice_companion:
		_voice_companion.send_text_message(message)

# ─────────────────────────────────────────────────
# Public API for voice control
# ─────────────────────────────────────────────────

func start_voice_recording() -> void:
	if _voice_companion:
		_voice_companion.start_voice_recording()

func stop_voice_recording() -> void:
	if _voice_companion:
		_voice_companion.stop_voice_recording()

func send_text_message(message: String) -> void:
	if _voice_companion:
		_voice_companion.send_text_message(message)

func synthesize_text(text: String) -> void:
	if _voice_companion:
		_voice_companion.synthesize_text(text)
