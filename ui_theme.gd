extends Node

# UI theme autoload: adds inner padding to LineEdit and TextEdit globally
func _ready() -> void:
	var theme: Theme = Theme.new()

	# StyleBox for single-line inputs (LineEdit) - generous margins
	var sb_line: StyleBoxFlat = StyleBoxFlat.new()
	sb_line.content_margin_left = 12
	sb_line.content_margin_top = 10
	sb_line.content_margin_right = 12
	sb_line.content_margin_bottom = 10
	sb_line.bg_color = Color(0, 0, 0, 0)

	# StyleBox for multi-line inputs (TextEdit) - even larger padding
	var sb_text: StyleBoxFlat = StyleBoxFlat.new()
	sb_text.content_margin_left = 12
	sb_text.content_margin_top = 12
	sb_text.content_margin_right = 12
	sb_text.content_margin_bottom = 12
	sb_text.bg_color = Color(0, 0, 0, 0)

	# Apply styleboxes to the theme for both normal and focus states
	theme.set_stylebox("normal", "LineEdit", sb_line)
	theme.set_stylebox("focus", "LineEdit", sb_line)
	theme.set_stylebox("read_only", "LineEdit", sb_line)
	
	theme.set_stylebox("normal", "TextEdit", sb_text)
	theme.set_stylebox("focus", "TextEdit", sb_text)
	theme.set_stylebox("read_only", "TextEdit", sb_text)

	# Assign theme to root so it cascades to all controls
	if get_tree() != null and get_tree().root != null:
		get_tree().root.theme = theme

