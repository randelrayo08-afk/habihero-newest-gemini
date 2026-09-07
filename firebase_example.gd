extends Node

var db: Node

func _ready() -> void:
	if get_tree() != null and get_tree().root != null:
		db = get_tree().root.get_node_or_null("FirebaseRTDB")
	if db == null and Engine.has_singleton("FirebaseRTDB"):
		db = Engine.get_singleton("FirebaseRTDB")
	if db == null:
		var script_resource: Script = load("res://FirebaseRTDB.gd")
		if script_resource != null:
			db = script_resource.new()
			db.name = "FirebaseRTDB"
			get_tree().root.add_child.call_deferred(db)
	if db == null:
		print("FirebaseRTDB autoload is not loaded. Add it as an autoload named FirebaseRTDB.")
		return

	if db != null and db.has_method("write_json"):
		# Example: save player progress under a test key.
		db.write_json("players/demo", {"name": "Alice", "score": 120}, func(result, response_code, body):
			print("Write result:", result, "response_code:", response_code, "body:", body)
		)

		# Example: read it back.
		db.read_json("players/demo", func(result, response_code, body):
			print("Read result:", result, "response_code:", response_code, "body:", body)
		)
