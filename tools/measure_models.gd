extends SceneTree

## Dev tool: prints the bounding box of each model in a directory so modular
## pieces can be laid out on their true grid instead of a guessed one.
##
##   Godot --headless --script tools/measure_models.gd -- --dir=res://assets/models/cave

var _directory := "res://assets/models/cave"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dir="):
			_directory = argument.trim_prefix("--dir=")

	var names := DirAccess.get_files_at(_directory)
	if names.is_empty():
		printerr("no files in %s" % _directory)
		quit(1)
		return

	for file_name in names:
		if not file_name.ends_with(".glb"):
			continue
		_report(file_name)

	quit(0)


func _report(file_name: String) -> void:
	var scene: PackedScene = load("%s/%s" % [_directory, file_name])
	if scene == null:
		printerr("%-38s LOAD FAILED" % file_name)
		return

	var instance: Node = scene.instantiate()
	root.add_child(instance)

	var bounds := _aabb_of(instance, AABB())

	print("%-38s size=(%6.2f,%6.2f,%6.2f)  min=(%6.2f,%6.2f,%6.2f)" % [
		file_name,
		bounds.size.x, bounds.size.y, bounds.size.z,
		bounds.position.x, bounds.position.y, bounds.position.z,
	])

	root.remove_child(instance)
	instance.free()


func _aabb_of(node: Node, current: AABB) -> AABB:
	if node is MeshInstance3D and node.mesh != null:
		var mesh_bounds: AABB = node.global_transform * node.mesh.get_aabb()
		current = mesh_bounds if current.size == Vector3.ZERO else current.merge(mesh_bounds)

	for child in node.get_children():
		current = _aabb_of(child, current)

	return current
