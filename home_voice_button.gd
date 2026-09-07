extends Button

func _ready() -> void:
	pressed.connect(_on_pressed)
	tooltip_text = "Press to talk to the AI"

func _on_pressed() -> void:
	print("Voice button pressed: native in-game mic path should handle recording here.")
	# This button is intentionally simplified. The actual press-to-talk flow
	# is now wired through shared_nav.gd / Home scene voice button logic.
