@tool
extends EditorScript

# This script converts all large .tscn scene files to binary .scn format
# to reduce disk size and improve load/save performance.
# To use: Right-click in FileSystem, attach this script to a scene, then run it.

func _run() -> void:
	var scenes_to_convert = [
		"res://login.tscn",
		"res://signup.tscn",
		"res://edit_profile.tscn",
		"res://forgotpass.tscn"
	]
	
	for scene_path in scenes_to_convert:
		if ResourceLoader.exists(scene_path):
			print("Converting: ", scene_path)
			var scene = load(scene_path)
			if scene:
				var binary_path = scene_path.trim_suffix(".tscn") + ".scn"
				var error = ResourceSaver.save(scene, binary_path, ResourceSaver.FLAG_COMPRESS)
				if error == OK:
					print("✓ Saved as: ", binary_path)
					# Optionally delete the old .tscn file
					# DirAccess.remove_absolute(scene_path)
				else:
					print("✗ Error saving: ", scene_path, " (error code: ", error, ")")
		else:
			print("✗ Scene not found: ", scene_path)
	
	print("\nConversion complete!")
	print("Note: Old .tscn files still exist. You can delete them manually if desired.")
	print("Also update any scene references in code from .tscn to .scn")
