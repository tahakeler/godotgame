extends SceneTree

## Dev tool: prints the node tree of an imported scene, so a model's actual
## structure (skeletons, animation players, mesh surfaces) can be checked
## before writing code against it.
##
##   Godot --headless --script tools/inspect_scene.gd -- --scene=res://path/to.fbx

var _scene_path := ""
var _live := false
var _instance: Node


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			_scene_path = argument.trim_prefix("--scene=")
		elif argument == "--live":
			_live = true

	if _scene_path.is_empty():
		printerr("pass --scene=res://...")
		quit(1)
		return

	var scene: PackedScene = load(_scene_path)
	if scene == null:
		printerr("could not load %s" % _scene_path)
		quit(1)
		return

	_instance = scene.instantiate()

	if not _live:
		print("--- %s (as imported) ---" % _scene_path)
		_print_node(_instance, 0)
		_instance.free()
		quit(0)
		return

	# --live adds the scene to the tree so _ready runs first, which is the only
	# way to see nodes a script builds at runtime.
	root.add_child(_instance)


func _process(_delta: float) -> bool:
	if not _live:
		return true

	print("--- %s (live, after _ready) ---" % _scene_path)
	_print_node(_instance, 0)

	root.remove_child(_instance)
	_instance.free()
	quit(0)
	return true


func _print_node(node: Node, depth: int) -> void:
	var detail := ""

	if node is MeshInstance3D and node.mesh != null:
		detail = "  [mesh surfaces=%d, aabb=%v]" % [
			node.mesh.get_surface_count(), node.mesh.get_aabb().size
		]
	elif node is Skeleton3D:
		detail = "  [bones=%d]" % node.get_bone_count()
	elif node is AnimationPlayer:
		detail = "  [animations=%s]" % str(node.get_animation_list())

	print("%s%s (%s)%s" % ["  ".repeat(depth), node.name, node.get_class(), detail])

	for child in node.get_children():
		_print_node(child, depth + 1)
