extends Control

var _auth: Node

func _ready() -> void:
	_auth = get_tree().root.get_node_or_null("FirebaseAuthManager")
	if _auth == null:
		_auth = Engine.get_singleton("FirebaseAuthManager")
	if _auth == null:
		push_warning("FirebaseAuthManager autoload is not available")

func _get_field_text(path: String) -> String:
	var node: Node = get_node_or_null(path)
	if node is LineEdit:
		return (node as LineEdit).text
	if node is TextEdit:
		return (node as TextEdit).text
	return ""

func _set_field_text(path: String, value: String) -> void:
	var node: Node = get_node_or_null(path)
	if node is LineEdit:
		(node as LineEdit).text = value
	if node is TextEdit:
		(node as TextEdit).text = value

func _collect_signup_payload() -> Dictionary:
	return {
		"name": _get_field_text("LineEdit"),
		"email": _get_field_text("LineEdit/LineEdit2"),
		"password": _get_field_text("LineEdit/LineEdit3")
	}
