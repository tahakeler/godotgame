extends SceneTree

## Verifies the arena actually generates. The failure this exists to catch is a
## navigation mesh that bakes to zero polygons — Godot reports no error for it,
## the game boots fine, and zombies simply never move.

const MINIMUM_SPAWN_POINTS := 6
const MINIMUM_OBSTACLES := 8

var _arena: Node3D


func _initialize() -> void:
	var scene: PackedScene = load("res://src/arena/arena.tscn")
	_arena = scene.instantiate()
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	var failures: Array[String] = []

	var nav_mesh: NavigationMesh = _arena.navigation_mesh
	if nav_mesh == null:
		failures.append("no navigation mesh assigned after bake")
	elif nav_mesh.get_polygon_count() == 0:
		failures.append("navigation mesh baked to 0 polygons — zombies would not move")

	var spawn_count: int = _arena.spawn_points.size()
	if spawn_count < MINIMUM_SPAWN_POINTS:
		failures.append("only %d spawn points generated, need %d" % [
			spawn_count, MINIMUM_SPAWN_POINTS
		])

	var obstacles := 0
	for child in _arena.get_children():
		if String(child.name).begins_with("Obstacle"):
			obstacles += 1
	if obstacles < MINIMUM_OBSTACLES:
		failures.append("only %d obstacles placed, need %d" % [obstacles, MINIMUM_OBSTACLES])

	if failures.is_empty():
		print("PASS: navmesh %d polys, %d spawn points, %d obstacles" % [
			nav_mesh.get_polygon_count(), spawn_count, obstacles
		])
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)

	return true
