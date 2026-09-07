extends Node

func _ready() -> void:
	call_deferred("_wire_audio_settings")

func _wire_audio_settings() -> void:
	var root: Node = get_parent()
	if root == null:
		return

	var sfx_toggle: CheckButton = root.get_node_or_null("Panel3/Button2/CheckButton") as CheckButton
	var music_toggle: CheckButton = root.get_node_or_null("Panel3/Button3/Panel4/Label/CheckButton") as CheckButton
	var notifications_toggle: CheckButton = root.get_node_or_null("Panel3/Button4/Panel4/Label/CheckButton") as CheckButton

	if sfx_toggle == null:
		sfx_toggle = _find_check_button_by_text(root, "Sound Effects")
	if music_toggle == null:
		music_toggle = _find_check_button_by_text(root, "Background Music")
	if notifications_toggle == null:
		notifications_toggle = _find_check_button_by_text(root, "Notifications")

	if sfx_toggle != null:
		var bus_index: int = AudioServer.get_bus_index("SFX")
		var enabled: bool = true
		if bus_index >= 0:
			enabled = not AudioServer.is_bus_mute(bus_index)
		sfx_toggle.button_pressed = enabled
		sfx_toggle.toggled.connect(func(value: bool) -> void:
			var audio_manager: Node = get_node_or_null("/root/AdventureAudio")
			if audio_manager != null and audio_manager.has_method("set_sound_effects_enabled"):
				audio_manager.call("set_sound_effects_enabled", value)
			ProjectSettings.set_setting("game/sound_effects_enabled", value)
		)

	if music_toggle != null:
		var bus_index: int = AudioServer.get_bus_index("Music")
		var enabled: bool = true
		if bus_index >= 0:
			enabled = not AudioServer.is_bus_mute(bus_index)
		music_toggle.button_pressed = enabled
		music_toggle.toggled.connect(func(value: bool) -> void:
			var audio_manager: Node = get_node_or_null("/root/AdventureAudio")
			if audio_manager != null and audio_manager.has_method("set_music_enabled"):
				audio_manager.call("set_music_enabled", value)
			ProjectSettings.set_setting("game/music_enabled", value)
		)

	if notifications_toggle != null:
		notifications_toggle.button_pressed = bool(ProjectSettings.get_setting("game/notifications_enabled", true))
		notifications_toggle.toggled.connect(func(value: bool) -> void:
			ProjectSettings.set_setting("game/notifications_enabled", value)
		)

func _find_check_button_by_text(root: Node, label_text: String) -> CheckButton:
	for child in root.get_children():
		var found: CheckButton = _search_branch_for_check_button(child, label_text)
		if found != null:
			return found
	return null

func _search_branch_for_check_button(node: Node, label_text: String) -> CheckButton:
	if node == null:
		return null
	if node is CheckButton:
		var check_button: CheckButton = node as CheckButton
		var parent: Node = check_button.get_parent()
		if parent != null:
			var label: Label = parent.get_node_or_null("Label") as Label
			if label != null and label.text == label_text:
				return check_button
		if check_button.text == label_text:
			return check_button
	for child in node.get_children():
		var found: CheckButton = _search_branch_for_check_button(child, label_text)
		if found != null:
			return found
	return null
