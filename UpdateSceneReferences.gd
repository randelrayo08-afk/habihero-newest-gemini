@tool
extends EditorScript

# After converting scenes to binary, run this script to update all references
# in GDScript files and the project settings

func _run() -> void:
	print("\n" + "=".repeat(60))
	print("Updating scene references from .tscn to .scn")
	print("=".repeat(60) + "\n")
	
	var replacements = {
		"res://login.tscn": "res://login.scn",
		"res://signup.tscn": "res://signup.scn",
		"res://edit_profile.tscn": "res://edit_profile.scn",
		"res://forgotpass.tscn": "res://forgotpass.scn"
	}
	
	# Find all GDScript files
	var gd_files = []
	find_gd_files("res://", gd_files)
	
	print("Found %d GDScript files to check\n" % gd_files.size())
	
	var total_replacements = 0
	
	for file_path in gd_files:
		var file = FileAccess.open(file_path, FileAccess.READ)
		if not file:
			continue
		
		var content = file.get_as_text()
		var modified = false
		
		for old_path in replacements:
			var new_path = replacements[old_path]
			if old_path in content:
				content = content.replace(old_path, new_path)
				modified = true
				print("✓ Updated: ", file_path)
				total_replacements += 1
		
		if modified:
			# Write back the file
			file = FileAccess.open(file_path, FileAccess.WRITE)
			file.store_string(content)
	
	print("\n" + "=".repeat(60))
	print("Completed! Updated %d files" % total_replacements)
	print("=".repeat(60))
	print("\nNext steps:")
	print("1. In Godot Editor, go to Project Settings")
	print("2. Look for 'run/main_scene' setting")
	print("3. If it references a .tscn scene, update it to .scn")
	print("\n(Or search project.godot for 'run/main_scene' and update manually)")

func find_gd_files(dir_path: String, file_list: Array) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		
		var full_path = dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name in ["godot_examples", ".godot", "addons"]:
				find_gd_files(full_path, file_list)
		else:
			if file_name.ends_with(".gd"):
				file_list.append(full_path)
		
		file_name = dir.get_next()
