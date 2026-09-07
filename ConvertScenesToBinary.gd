@tool
extends EditorScript

func _run() -> void:
	convert_scene("res://login.tscn")
	convert_scene("res://signup.tscn")
	convert_scene("res://edit_profile.tscn")
	convert_scene("res://forgotpass.tscn")

func convert_scene(tscn_path: String) -> void:
	print("\n" + "=".repeat(50))
	print("Converting: ", tscn_path)
	print("=".repeat(50))
	
	if not ResourceLoader.exists(tscn_path):
		print("✗ File not found: ", tscn_path)
		return
	
	# Load the scene
	var scene = load(tscn_path)
	if not scene:
		print("✗ Failed to load scene")
		return
	
	# Generate binary path
	var scn_path = tscn_path.trim_suffix(".tscn") + ".scn"
	
	# Check file size before
	var file = FileAccess.open(tscn_path, FileAccess.READ)
	if file:
		var original_size_mb = file.get_length() / (1024.0 * 1024.0)
		print("Original size: %.2f MB" % original_size_mb)
	
	# Save as binary with compression
	var error = ResourceSaver.save(scene, scn_path, ResourceSaver.FLAG_COMPRESS)
	
	if error == OK:
		file = FileAccess.open(scn_path, FileAccess.READ)
		var new_size_mb = file.get_length() / (1024.0 * 1024.0) if file else 0.0
		print("✓ Converted successfully!")
		print("New binary path: ", scn_path)
		print("New size: %.2f MB" % new_size_mb)
	else:
		print("✗ Error during conversion (code: ", error, ")")
	
	print()
