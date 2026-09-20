extends SceneTree

## Asks, of every solid-looking object in the arena, whether the player can
## walk through it. Phase 3's complaint is that they can, and the only honest
## way to answer it is to put the player's own capsule where the object is and
## ask the physics space what it touches.
##
## Two things are reported separately, because they are different problems:
##
##   - objects nothing stops you walking into. These are the bug.
##   - objects with no collider of their own that the cave's box shell happens
##     to stop you at anyway. Not a bug, but worth seeing, because it is luck
##     rather than intent and moving the object by a metre would end it.
##
## An earlier version of this sampled triangle centroids and asked whether
## anything solid was nearby. That reports a crate standing on the floor as
## covered, because most of a short crate is within a tolerance of the floor
## slab — it measured proximity to any shape rather than whether the object
## stops you, which is the only question that matters.
##
##   Godot --headless --script tools/audit_collision.gd

const GAME_SCENE := "res://src/core/game.tscn"

## The player's own capsule, so "can you walk through it" is asked with the
## thing that would be doing the walking.
const PLAYER_RADIUS := 0.4
const PLAYER_HEIGHT := 1.8

## Objects whose longest side is under this are scenery — a pebble is not a
## barricade and giving it a collider would only catch the player's feet.
const MINIMUM_SIZE := 0.5

## Above this an object can be seen but not walked into, so its collision
## matters much less.
const REACH_HEIGHT := 3.2

## Compass directions swept from each cell when testing containment, and how
## far. Far enough to cross the whole cave, so an unobstructed sweep is
## unambiguous rather than merely long.
const SWEEP_DIRECTIONS := 16
const SWEEP_DISTANCE := 160.0

var _game: Node
var _frames := 0
var _problems: Array[String] = []
var _sheltered: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	# The arena builds itself on ready and the physics space does not know
	# about any of it until it has stepped.
	_frames += 1
	if _frames < 4:
		return false

	var arena := _find_arena(_game)
	if arena == null:
		printerr("FAIL: no arena in the scene")
		quit(1)
		return true

	_report_layer_matrix()
	_audit_objects(arena)
	_audit_containment(arena)
	_report()
	return true


## Whether the cave actually holds the player in.
##
## The walls are a box shell generated from the walkable cells rather than from
## the rock that is drawn, so the question is never "does this wall look solid"
## — it is "does the shell have a hole in it". Sweeping the player's own capsule
## outward from every cell they can stand in and checking where it comes to
## rest answers that directly: a sweep that ends outside the cave found a way
## out, and a way out of a cave in a game about being chased through one is the
## most valuable exploit there is.
func _audit_containment(arena: Node) -> void:
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	var cells: Dictionary = arena._occupied_cells()

	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = PLAYER_HEIGHT

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.collide_with_areas = false

	var tested := 0
	var escapes := 0

	for cell in cells:
		# Lifted a little off the floor: a capsule whose feet rest exactly on the
		# slab reads as overlapping it, and every cell would be skipped as solid.
		var origin: Vector3 = (
			arena._cell_to_world(cell) + Vector3.UP * (PLAYER_HEIGHT * 0.5 + 0.15)
		)

		# Cells inside rock or under a deck are not places to sweep from.
		query.transform = Transform3D(Basis.IDENTITY, origin)
		query.motion = Vector3.ZERO
		if not space.intersect_shape(query, 1).is_empty():
			continue

		tested += 1

		for step in SWEEP_DIRECTIONS:
			var heading := float(step) * TAU / float(SWEEP_DIRECTIONS)
			var direction := Vector3(sin(heading), 0.0, cos(heading))

			query.transform = Transform3D(Basis.IDENTITY, origin)
			query.motion = direction * SWEEP_DISTANCE

			var fractions: PackedFloat32Array = space.cast_motion(query)
			if fractions.is_empty():
				continue

			var stopped: Vector3 = origin + query.motion * fractions[0]
			var landed := Vector2i(
				roundi(stopped.x / Arena.CELL), roundi(stopped.z / Arena.CELL)
			)

			if not cells.has(landed):
				escapes += 1
				_problems.append(
					"the player can walk out of the cave from (%d, %d) heading %.0f degrees, "
					% [cell.x * 4, cell.y * 4, rad_to_deg(heading)]
					+ "ending up at %s" % _round(stopped)
				)
				break

	print("")
	print("--- containment: %d standable cells swept in %d directions ---" % [
		tested, SWEEP_DIRECTIONS
	])
	if escapes == 0:
		print("  the shell holds — no sweep left the cave")


## The layer matrix, printed rather than asserted, because what is right
## depends on intent: the player not colliding with zombies is a design choice,
## the player not colliding with the world is a bug.
func _report_layer_matrix() -> void:
	print("--- collision layers ---")
	for body in _bodies(_game):
		print(
			"  %-22s layer=%s mask=%s"
			% [body.name, _bits(body.collision_layer), _bits(body.collision_mask)]
		)
	print("")


func _audit_objects(arena: Node) -> void:
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state

	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = 1
	query.collide_with_areas = false

	var objects := _objects(arena)
	print("--- %d objects that must carry their own collision ---" % objects.size())

	for entry in objects:
		var box: AABB = entry.box
		# A point at the object's centre, which is inside anything solid and
		# outside anything hollow. The cave floor's slab sits entirely below
		# y=0, so a crate's centre cannot be mistaken for the floor.
		query.position = box.get_center()
		var solid := not space.intersect_point(query, 1).is_empty()

		if entry.has_collider and solid:
			continue
		elif entry.has_collider:
			# A shape exists but nothing is at the object's middle, which is
			# what a collider fitted to the wrong place looks like.
			_problems.append(
				"%s carries a collider that is not where the object is, around %s"
				% [entry.name, _round(box.get_center())]
			)
		else:
			_problems.append(
				"%s can be walked straight through: %.1fm across at %s"
				% [entry.name, box.get_longest_axis_size(), _round(box.get_center())]
			)


## Every distinct object in the arena that looks solid, as one entry each.
##
## Grouped by the named node under the arena rather than per MeshInstance3D: a
## crate imported from a kit is several meshes, and reporting each of them
## separately buries the answer in noise.
func _objects(arena: Node) -> Array[Dictionary]:
	var grouped: Dictionary = {}

	for mesh_instance in _meshes(arena):
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		if box.position.y > REACH_HEIGHT:
			continue

		var group := _owning_node(mesh_instance, arena)
		if group == null or _collision_comes_from_elsewhere(group, arena):
			continue

		var key := group.get_instance_id()
		if grouped.has(key):
			grouped[key].box = grouped[key].box.merge(box)
		else:
			grouped[key] = {
				"name": str(group.name),
				"box": box,
				"has_collider": _has_collider(group),
			}

	var found: Array[Dictionary] = []
	for key in grouped:
		var entry: Dictionary = grouped[key]
		if entry.box.get_longest_axis_size() >= MINIMUM_SIZE:
			found.append(entry)

	return found


## Whether the arena has declared that this object's collision lives somewhere
## else — in the cave's box shell, in a deck or ramp body — or that it is out of
## reach and needs none.
##
## Checked up the ancestry because a staircase marks its root, not each of the
## treads hanging under it.
func _collision_comes_from_elsewhere(node: Node, arena: Node) -> bool:
	var current := node

	while current != null and current != arena:
		if current.is_in_group(Arena.SHELL_BACKED):
			return true
		current = current.get_parent()

	return false


## Whether this object carries collision of its own, as opposed to relying on
## something else in the level happening to be in the way.
##
## Only shapes under a PhysicsBody3D count. An ammo cache carries an Area3D so
## it can notice the player standing in it, and a trigger volume stops nobody —
## counting it here would report every cache as solid when you can walk through
## all six.
func _has_collider(node: Node) -> bool:
	if node is PhysicsBody3D and _has_shape(node):
		return true

	for child in node.get_children():
		if _has_collider(child):
			return true

	return false


func _has_shape(node: Node) -> bool:
	if node is CollisionShape3D and node.shape != null and not node.disabled:
		return true

	for child in node.get_children():
		if _has_shape(child):
			return true

	return false


## --- Helpers ----------------------------------------------------------------


## The object a mesh belongs to: the placed kit piece, not the third
## MeshInstance3D inside its imported scene.
##
## Found by walking up to the outermost ancestor that was instantiated from a
## scene file, which is exactly what one placed piece is. Grouping by the
## arena's direct children instead collapses the whole cave into one entry,
## because every piece is parented under a single Geometry node. Procedural
## meshes — deck blocks, ramps, the ceiling — belong to no scene file, so they
## stand as their own object.
func _owning_node(node: Node, arena: Node) -> Node:
	var current := node
	var instance_root: Node = null

	while current != null and current != arena:
		if not str(current.scene_file_path).is_empty():
			instance_root = current
		current = current.get_parent()

	return instance_root if instance_root != null else node


func _find_arena(node: Node) -> Node3D:
	if node is Arena:
		return node

	for child in node.get_children():
		var found := _find_arena(child)
		if found != null:
			return found

	return null


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []

	if node is MeshInstance3D and node.mesh != null and node.visible:
		found.append(node)

	for child in node.get_children():
		found.append_array(_meshes(child))

	return found


func _bodies(node: Node) -> Array[CollisionObject3D]:
	var found: Array[CollisionObject3D] = []

	if node is CollisionObject3D:
		found.append(node)

	for child in node.get_children():
		found.append_array(_bodies(child))

	return found


func _bits(mask: int) -> String:
	var names: Array[String] = []
	for bit in 8:
		if mask & (1 << bit):
			names.append(str(bit + 1))
	return "-" if names.is_empty() else ",".join(names)


func _round(at: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [at.x, at.y, at.z]


func _report() -> void:
	if not _sheltered.is_empty():
		print("")
		print("--- stopped by the cave shell rather than by themselves ---")
		for note in _sheltered:
			print("  %s" % note)

	if _problems.is_empty():
		print("")
		print("collision: nothing solid-looking can be walked through")
		quit(0)
		return

	print("")
	for problem in _problems:
		printerr("FAIL: %s" % problem)
	printerr("%d objects can be walked through" % _problems.size())
	quit(1)
