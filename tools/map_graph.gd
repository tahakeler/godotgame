extends SceneTree

## Prints the arena as a map, and says how interconnected it actually is.
##
## Connectivity is the hardest thing to judge by reading a table of cells, and
## the easiest to judge by looking at a picture. This draws one, then answers
## the three questions that matter for a level you are chased through:
##
##   - how many ways out does each room have?
##   - how many independent loops are there? (a corridor you can be cornered in
##     has none; a ring has one)
##   - which cells are dead ends, and is there a reason to go down them?
##
## The loop count is the cyclomatic number of the walkable graph, E - V + C.
## One loop is one way to get behind something that is chasing you.
##
##   Godot --headless --script tools/map_graph.gd

const ARENA_SCENE := "res://src/arena/arena.tscn"

var _arena: Arena
var _frames := 0


func _initialize() -> void:
	var scene: PackedScene = load(ARENA_SCENE)
	_arena = scene.instantiate()
	_arena.bake_navigation = false
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	var cells := _walkable_cells()
	_draw(cells)
	_report_connectivity(cells)
	quit(0)
	return true


## Cells a player can actually stand in, which is the layout's footprint.
func _walkable_cells() -> Dictionary:
	return _arena._occupied_cells()


func _draw(cells: Dictionary) -> void:
	var min_cell := Vector2i(9999, 9999)
	var max_cell := Vector2i(-9999, -9999)
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))

	print("--- arena map (%d cells, %d x %d) ---" % [
		cells.size(), max_cell.x - min_cell.x + 1, max_cell.y - min_cell.y + 1
	])
	print("    . walkable   S player spawn   Z zombie spawn   C cache   # dead end")
	print("")

	var landmarks := _landmarks()

	for y in range(min_cell.y, max_cell.y + 1):
		var line := "%4d " % (y * 4)
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)
			if not cells.has(cell):
				line += "  "
				continue
			if landmarks.has(cell):
				line += landmarks[cell] + " "
			elif _exits_from(cell, cells) <= 1:
				line += "# "
			else:
				line += ". "
		print(line)
	print("")


## Cells worth calling out, so the picture is readable as a place.
func _landmarks() -> Dictionary:
	var marks: Dictionary = {}

	for node in _arena.get_children():
		if node is AmmoCache:
			marks[_cell_of(node.global_position)] = "C"

	for point in _arena.spawn_points:
		var cell := _cell_of(point)
		if not marks.has(cell):
			marks[cell] = "Z"

	marks[Vector2i.ZERO] = "S"
	return marks


func _cell_of(at: Vector3) -> Vector2i:
	return Vector2i(roundi(at.x / Arena.CELL), roundi(at.z / Arena.CELL))


func _exits_from(cell: Vector2i, cells: Dictionary) -> int:
	var exits := 0
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if cells.has(cell + offset):
			exits += 1
	return exits


func _report_connectivity(cells: Dictionary) -> void:
	var edges := 0
	var dead_ends: Array[Vector2i] = []

	for cell in cells:
		var exits := _exits_from(cell, cells)
		edges += exits
		if exits <= 1:
			dead_ends.append(cell)

	# Each edge was counted from both ends.
	edges /= 2

	var components := _count_components(cells)
	var loops := edges - cells.size() + components

	print("--- connectivity ---")
	print("  cells:           %d" % cells.size())
	print("  connections:     %d" % edges)
	print("  separate areas:  %d" % components)
	print("  independent loops: %d" % loops)
	print("  dead-end cells:  %d" % dead_ends.size())

	if not dead_ends.is_empty():
		var listed: Array[String] = []
		for cell in dead_ends:
			listed.append("(%d, %d)" % [cell.x * 4, cell.y * 4])
		print("    at: %s" % ", ".join(listed))

	if components > 1:
		printerr("FAIL: the map is in %d disconnected pieces" % components)
		quit(1)


func _count_components(cells: Dictionary) -> int:
	var seen: Dictionary = {}
	var components := 0

	for start in cells:
		if seen.has(start):
			continue
		components += 1
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = cell + offset
				if cells.has(next) and not seen.has(next):
					seen[next] = true
					queue.append(next)

	return components
