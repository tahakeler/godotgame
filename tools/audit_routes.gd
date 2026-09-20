extends SceneTree

## Answers two questions about the level that cannot be answered by looking at
## it: can everything reach everything, and how much choice does the player
## actually have about how to get there.
##
## REACHABILITY asks the navigation server for a real path between every pair
## that matters — each zombie spawn to the player, the player to each supply
## cache — and checks the path arrives. A route the navmesh does not cover is a
## route zombies cannot follow you down, which is not a dead end but an exploit.
##
## CHOKEPOINTS is the interesting one. A cell is a chokepoint if removing it
## splits the map in two, which is the graph-theoretic way of saying "there is
## no other way round". Every chokepoint is a place the player can be cornered
## with no alternative, so the count is a direct measure of how interconnected
## the cave really is — and unlike a screenshot, it cannot be fooled by a map
## that merely looks busy.
##
##   Godot --headless --script tools/audit_routes.gd

const GAME_SCENE := "res://src/core/game.tscn"

## How close a path's last point must come to count as having arrived. The
## navmesh is eroded by the agent radius, so a path legitimately stops short of
## a target standing near a wall.
const ARRIVAL_TOLERANCE := 2.5

## A path more than this many times the straight-line distance is a sign of a
## missing connection rather than an interesting route.
const DETOUR_LIMIT := 3.0

var _game: Node
var _arena: Arena
var _frames := 0
var _problems: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	# The navigation map is synchronised on its own schedule; asking for a path
	# before it has settled returns nothing and every route reads as broken.
	_frames += 1
	if _frames < 6:
		return false

	_arena = _find_arena(_game)
	if _arena == null:
		printerr("FAIL: no arena in the scene")
		quit(1)
		return true

	_audit_reachability()
	_audit_chokepoints()
	_report()
	return true


## --- Reachability -----------------------------------------------------------


func _audit_reachability() -> void:
	var map: RID = _arena.get_navigation_map()
	NavigationServer3D.map_force_update(map)

	var player_spawn := Vector3.ZERO
	var reached := 0
	var worst_detour := 0.0
	var worst_label := ""

	print("--- reachability ---")

	for index in _arena.spawn_points.size():
		var from: Vector3 = _arena.spawn_points[index]
		var detour := _check_route(map, from, player_spawn, "zombie spawn %d" % index)
		if detour >= 0.0:
			reached += 1
			if detour > worst_detour:
				worst_detour = detour
				worst_label = "zombie spawn %d" % index

	print("  %d/%d zombie spawns can reach the player" % [
		reached, _arena.spawn_points.size()
	])

	var caches := 0
	for cache in _arena.ammo_caches:
		var label := "cache %s" % cache.name
		if _check_route(map, player_spawn, cache.global_position, label) >= 0.0:
			caches += 1

	print("  %d/%d supply caches can be reached by the player" % [
		caches, _arena.ammo_caches.size()
	])

	if not worst_label.is_empty():
		print("  longest detour: %s at %.1fx the straight line" % [
			worst_label, worst_detour
		])


## Path length as a multiple of the straight-line distance, or -1 if the route
## does not arrive at all.
func _check_route(map: RID, from: Vector3, to: Vector3, label: String) -> float:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)

	if path.is_empty():
		_problems.append("%s has no path to its target at all" % label)
		return -1.0

	var arrival: float = path[path.size() - 1].distance_to(to)
	if arrival > ARRIVAL_TOLERANCE:
		_problems.append(
			"%s only gets within %.1fm of its target — the route is cut off"
			% [label, arrival]
		)
		return -1.0

	var travelled := 0.0
	for index in range(1, path.size()):
		travelled += path[index].distance_to(path[index - 1])

	var direct: float = from.distance_to(to)
	if direct < 1.0:
		return 1.0

	var detour := travelled / direct
	if detour > DETOUR_LIMIT:
		_problems.append(
			"%s has to walk %.1fx the straight-line distance (%.0fm for %.0fm)"
			% [label, detour, travelled, direct]
		)

	return detour


## --- Chokepoints ------------------------------------------------------------


## Cells whose removal would split the map into disconnected pieces.
##
## Found by removing each cell in turn and re-counting connected components,
## which is slower than a proper articulation-point search but is a handful of
## milliseconds at this size and is obviously correct, which matters more in a
## tool whose answer nobody can check by eye.
func _audit_chokepoints() -> void:
	var cells: Dictionary = _arena._occupied_cells()
	var total := cells.size()
	var chokepoints: Array[Vector2i] = []

	for cell in cells:
		var without := cells.duplicate()
		without.erase(cell)
		if _components(without) > 1:
			chokepoints.append(cell)

	print("")
	print("--- route choice ---")
	print("  cells:       %d" % total)
	print("  chokepoints: %d (%.0f%% of the map)" % [
		chokepoints.size(), 100.0 * float(chokepoints.size()) / float(maxi(total, 1))
	])
	print("    a chokepoint is a cell with no way round — somewhere you can be cornered")

	if chokepoints.is_empty():
		return

	var listed: Array[String] = []
	for cell in chokepoints:
		listed.append("(%d, %d)" % [cell.x * 4, cell.y * 4])
	print("  at: %s" % ", ".join(listed))


func _components(cells: Dictionary) -> int:
	var seen: Dictionary = {}
	var found := 0

	for start in cells:
		if seen.has(start):
			continue
		found += 1
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = cell + offset
				if cells.has(next) and not seen.has(next):
					seen[next] = true
					queue.append(next)

	return found


## --- Helpers ----------------------------------------------------------------


func _find_arena(node: Node) -> Arena:
	if node is Arena:
		return node

	for child in node.get_children():
		var found := _find_arena(child)
		if found != null:
			return found

	return null


func _report() -> void:
	if _problems.is_empty():
		print("")
		print("routes: everything reachable, no broken paths")
		quit(0)
		return

	print("")
	for problem in _problems:
		printerr("FAIL: %s" % problem)
	printerr("%d route problems" % _problems.size())
	quit(1)
