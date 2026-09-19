extends SceneTree

## Checks that the baked navmesh is actually *connected*: that a path exists
## from every zombie spawn point to the centre of the arena.
##
## A navmesh can bake hundreds of polygons and still be split into islands — a
## corridor whose floor does not quite meet the room's, an agent radius that
## pinches a doorway shut. Nothing reports an error; zombies simply never
## arrive. Polygon count alone cannot catch that, so this queries real paths.

const ARENA_SCENE := "res://src/arena/arena.tscn"

## A path is considered to arrive if its last point is within this of the goal.
const ARRIVAL_TOLERANCE := 2.0

var _arena: Arena
var _frames := 0


func _initialize() -> void:
	var scene: PackedScene = load(ARENA_SCENE)
	_arena = scene.instantiate()
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	# The navigation server syncs its maps on a physics step, so queries made
	# on the first frame come back empty regardless of the bake.
	_frames += 1
	if _frames < 30:
		return false

	var map: RID = _arena.get_world_3d().navigation_map
	print("DEBUG map valid=%s regions=%d region_map_matches=%s enabled=%s polys=%d" % [
		str(map.is_valid()), NavigationServer3D.map_get_regions(map).size(),
		str(NavigationServer3D.region_get_map(_arena.get_rid()) == map),
		str(_arena.enabled), _arena.navigation_mesh.get_polygon_count()])
	var goal := Vector3.ZERO
	var failures: Array[String] = []

	for point in _arena.spawn_points:
		var path := NavigationServer3D.map_get_path(map, point, goal, true)

		if path.is_empty():
			failures.append("no path from spawn %v to centre" % point)
			continue

		var arrival: float = path[path.size() - 1].distance_to(goal)
		if arrival > ARRIVAL_TOLERANCE:
			failures.append(
				"path from spawn %v stops %.1fm short of the centre" % [point, arrival]
			)

	if failures.is_empty():
		print("PASS: all %d spawn points have a connected path to the centre" % [
			_arena.spawn_points.size()
		])
		_teardown()
		quit(0)
		return true

	for failure in failures:
		printerr("FAIL: %s" % failure)

	_teardown()
	quit(1)
	return true


func _teardown() -> void:
	if _arena != null and is_instance_valid(_arena):
		root.remove_child(_arena)
		_arena.free()
		_arena = null
