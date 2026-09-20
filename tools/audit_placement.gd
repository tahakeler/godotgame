extends SceneTree

## Checks that nothing in the arena is standing inside anything else.
##
## The layout tables are hand-authored and have been edited many times — decks
## and ramps were added after the cover rocks, caches after both, and spawn
## points spread out after that. Nothing in the build reports a collision
## between two decorations, so a crate buried in a deck or a zombie spawning
## inside a supply crate looks completely normal right up until someone walks
## into it.
##
## Everything is read from the live tree rather than recomputed from the
## tables. An audit that re-derives where things ought to be can only ever
## confirm the maths it already shares with the builder; reading the nodes
## catches the case where the builder and the table disagree.
##
##   Godot --headless --script tools/audit_placement.gd

const ARENA_SCENE := "res://src/arena/arena.tscn"

## Footprint sizes in metres for things whose collision is not a box.
## `template-detail` is 2.64 x 2.81 before scaling.
const COVER_FOOTPRINT := 2.8
## The cache's own trigger cylinder is 1.6m across, plus the crate.
const CACHE_FOOTPRINT := 3.2
const PROP_FOOTPRINT := 1.6
## A zombie or the player needs about this much room to stand.
const BODY_FOOTPRINT := 1.2

var _arena: Arena
var _problems: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	# The navigation server syncs its maps on a physics step.
	_frames += 1
	if _frames < 30:
		return false

	var solids := _collect_solids()
	print("auditing %d placed objects and %d spawn points" % [
		solids.size(), _arena.spawn_points.size()
	])

	_check_solids_do_not_overlap(solids)
	_check_spawn_points_are_clear(solids)
	_check_player_spawn_is_clear(solids)
	_check_points_are_on_the_navmesh()

	_report()
	return true


## Everything a body could be standing inside, as an XZ rectangle.
func _collect_solids() -> Array[Dictionary]:
	var solids: Array[Dictionary] = []

	for node in _descendants(_arena):
		if node is AmmoCache:
			solids.append(_square(node.global_position, CACHE_FOOTPRINT, "cache"))
			continue

		if not (node is Node3D):
			continue

		match str(node.name).split("_")[0]:
			"Cover":
				var width: float = COVER_FOOTPRINT * node.scale.x
				solids.append(_square(node.global_position, width, "cover"))
			"Prop":
				solids.append(_square(node.global_position, PROP_FOOTPRINT, "prop"))
			"DeckBody", "RampBody":
				var box := _box_of(node)
				if box.size != Vector2.ZERO:
					solids.append({
						"rect": box,
						"label": "%s %s" % [
							"deck" if str(node.name).begins_with("Deck") else "ramp",
							node.name
						],
					})

	return solids


## The XZ footprint of a StaticBody3D's first box shape, in world space.
func _box_of(body: Node3D) -> Rect2:
	for child in body.get_children():
		if not (child is CollisionShape3D):
			continue

		var shape: Shape3D = child.shape
		if not (shape is BoxShape3D):
			continue

		var centre: Vector3 = child.global_position
		# The ramp is tilted, so its flat footprint is shorter than the slab.
		# Using the untilted size overstates it, which is the safe direction
		# for an overlap check.
		var size: Vector3 = shape.size
		return Rect2(
			centre.x - size.x * 0.5, centre.z - size.z * 0.5, size.x, size.z
		)

	return Rect2()


func _check_solids_do_not_overlap(solids: Array[Dictionary]) -> void:
	var clashes := 0

	for first in solids.size():
		for second in range(first + 1, solids.size()):
			var a: Dictionary = solids[first]
			var b: Dictionary = solids[second]

			# A ramp is supposed to meet its own deck, and the decks are built
			# from blocks that sit flush. Only unrelated pairs are a problem.
			if _are_related(a.label, b.label):
				continue

			if a.rect.intersects(b.rect):
				var overlap: Rect2 = a.rect.intersection(b.rect)
				_problems.append(
					"%s overlaps %s by %.1fm x %.1fm"
					% [a.label, b.label, overlap.size.x, overlap.size.y]
				)
				clashes += 1

	if clashes == 0:
		print("PASS: no two placed objects overlap")


## A ramp and the deck it climbs to are meant to touch.
func _are_related(first: String, second: String) -> bool:
	if not (first.contains("_") and second.contains("_")):
		return false

	# Deck and ramp names carry the platform's cell: "deck DeckBody_-4_5".
	return first.split(" ")[1].trim_prefix("DeckBody").trim_prefix("RampBody") \
		== second.split(" ")[1].trim_prefix("DeckBody").trim_prefix("RampBody")


## A zombie must never arrive standing inside the scenery.
func _check_spawn_points_are_clear(solids: Array[Dictionary]) -> void:
	var blocked := 0

	for point in _arena.spawn_points:
		var body := _square(point, BODY_FOOTPRINT, "spawn")

		for solid in solids:
			if body.rect.intersects(solid.rect):
				_problems.append(
					"a spawn point at (%.1f, %.1f) is inside %s"
					% [point.x, point.z, solid.label]
				)
				blocked += 1
				break

	if blocked == 0:
		print("PASS: all %d spawn points are clear of scenery" % _arena.spawn_points.size())


func _check_player_spawn_is_clear(solids: Array[Dictionary]) -> void:
	# The player starts at the origin of the central chamber.
	var body := _square(Vector3.ZERO, BODY_FOOTPRINT * 1.5, "player spawn")
	var blocked := false

	for solid in solids:
		if body.rect.intersects(solid.rect):
			_problems.append("the player spawns inside %s" % solid.label)
			blocked = true

	if not blocked:
		print("PASS: the player spawn is clear")


## A spawn point or a cache off the navmesh is unreachable, whatever it looks
## like from above.
func _check_points_are_on_the_navmesh() -> void:
	var map: RID = _arena.get_world_3d().navigation_map
	var stranded := 0

	for point in _arena.spawn_points:
		var nearest := NavigationServer3D.map_get_closest_point(map, point)
		if nearest.distance_to(point) > 2.0:
			_problems.append(
				"a spawn point at (%.1f, %.1f) is %.1fm off the navmesh"
				% [point.x, point.z, nearest.distance_to(point)]
			)
			stranded += 1

	for cache in _arena.ammo_caches:
		var nearest := NavigationServer3D.map_get_closest_point(map, cache.global_position)
		if nearest.distance_to(cache.global_position) > 3.0:
			_problems.append(
				"a cache at (%.1f, %.1f) is %.1fm off the navmesh — unreachable"
				% [cache.global_position.x, cache.global_position.z,
					nearest.distance_to(cache.global_position)]
			)
			stranded += 1

	if stranded == 0:
		print("PASS: every spawn point and cache sits on walkable ground")


func _square(at: Vector3, width: float, label: String) -> Dictionary:
	return {
		"rect": Rect2(at.x - width * 0.5, at.z - width * 0.5, width, width),
		"label": label,
	}


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []

	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))

	return found


func _report() -> void:
	if _arena != null and is_instance_valid(_arena):
		root.remove_child(_arena)
		_arena.free()
		_arena = null

	if _problems.is_empty():
		print("RESULT: placement is clean")
		quit(0)
		return

	for problem in _problems:
		printerr("PROBLEM: %s" % problem)

	printerr("RESULT: %d placement problems" % _problems.size())
	quit(1)
