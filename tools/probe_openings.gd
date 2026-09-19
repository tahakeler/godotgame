extends SceneTree

## Dev tool: reports which sides of each cave piece are actually open.
##
## The kit's rooms have decorative indentations that look like doorways from
## above but are solid rock, and an unrotated corridor runs along X rather than
## Z. Both cost real debugging time when assumed rather than checked. This
## builds each piece with its collision and fires a ray outward through each
## wall midpoint, so the layout can be designed against fact.
##
##   Godot --headless --script tools/probe_openings.gd -- --models=corridor,room-small

const CAVE_PATH := "res://assets/models/cave/%s.glb"
const DEFAULT_MODELS := [
	"corridor", "corridor-corner", "corridor-intersection", "corridor-junction",
	"corridor-end", "room-small", "room-large", "room-wide", "room-corner",
]

## Fired at head height, so a raised floor lip does not read as a blocked wall.
const PROBE_HEIGHT := 1.2

var _models: Array[String] = []
var _frames := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--models="):
			for name in argument.trim_prefix("--models=").split(",", false):
				_models.append(name)

	if _models.is_empty():
		for name in DEFAULT_MODELS:
			_models.append(name)


func _process(_delta: float) -> bool:
	# Collision bodies are attached deferred, so they are not queryable on the
	# frame the piece is built.
	_frames += 1
	if _frames < 3:
		if _frames == 1:
			_build_all()
		return false

	_report()
	quit(0)
	return true


var _instances: Dictionary = {}


func _build_all() -> void:
	var offset := 0.0

	for name in _models:
		var scene: PackedScene = load(CAVE_PATH % name)
		if scene == null:
			printerr("could not load %s" % name)
			continue

		var instance: Node3D = scene.instantiate()
		root.add_child(instance)
		# Spread pieces far apart so one never blocks another's probe.
		instance.position = Vector3(offset, 0.0, 0.0)
		offset += 200.0

		for mesh_instance in _find_meshes(instance):
			mesh_instance.create_trimesh_collision()

		_instances[name] = instance


func _report() -> void:
	var space := root.world_3d.direct_space_state

	print("piece                          -X    +X    -Z    +Z")
	print("-".repeat(58))

	for name in _models:
		if not _instances.has(name):
			continue

		var instance: Node3D = _instances[name]
		var centre: Vector3 = instance.position + Vector3.UP * PROBE_HEIGHT
		var extent := _half_extent(instance)

		var results: Array[String] = []
		for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var reach: float = absf(direction.x) * extent.x + absf(direction.z) * extent.z
			var query := PhysicsRayQueryParameters3D.create(
				centre, centre + direction * (reach + 1.5)
			)
			var hit := space.intersect_ray(query)
			results.append("WALL " if not hit.is_empty() else "open ")

		print("%-30s %s %s %s %s" % [name, results[0], results[1], results[2], results[3]])


func _half_extent(node: Node3D) -> Vector3:
	var bounds := AABB()

	for mesh_instance in _find_meshes(node):
		var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		bounds = mesh_bounds if bounds.size == Vector3.ZERO else bounds.merge(mesh_bounds)

	return bounds.size * 0.5


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []

	if node is MeshInstance3D and node.mesh != null:
		found.append(node)

	for child in node.get_children():
		found.append_array(_find_meshes(child))

	return found
