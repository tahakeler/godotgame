extends SceneTree

## Verifies where zombies are chosen to come from.
##
## Spawn selection is deliberately random, so these are statistical
## assertions over many draws rather than checks on a single pick. The
## thresholds are loose on purpose — they are there to catch the selector
## being broken or reverting to uniform random, not to pin down exact ratios.
##
## What would otherwise go unnoticed: zombies appearing in front of the player
## out of nothing, or the same doorway being used over and over, which reads as
## a spawn closet rather than a cave with things in it.
##
##   Godot --headless --script tests/manual/verify_spawn_director.gd

const ARENA_SCENE := "res://src/arena/arena.tscn"
const DRAWS := 600
const MINIMUM_DISTANCE := 14.0

var _arena: Arena
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	test_spawn_director_respects_the_minimum_distance()
	test_spawn_director_prefers_arrivals_behind_the_player()
	test_spawn_director_spreads_across_chambers()

	_report()
	return true


func test_spawn_director_respects_the_minimum_distance() -> void:
	# Arrange
	var origin := Vector3.ZERO
	var facing := Vector3.FORWARD
	var closest := INF

	# Act
	for draw in DRAWS:
		var point := _arena.pick_spawn_point(origin, MINIMUM_DISTANCE, facing)
		closest = minf(closest, Vector2(point.x, point.z).length())

	# Assert
	if closest < MINIMUM_DISTANCE:
		_failures.append(
			"a zombie was spawned %.1fm away, inside the %.1fm minimum"
			% [closest, MINIMUM_DISTANCE]
		)
	else:
		print("PASS: no spawn closer than %.1fm (nearest %.1fm)" % [
			MINIMUM_DISTANCE, closest
		])


func test_spawn_director_prefers_arrivals_behind_the_player() -> void:
	# Arrange: the player stands at the origin looking down -Z.
	var origin := Vector3.ZERO
	var facing := Vector3.FORWARD
	var behind := 0

	# Act
	for draw in DRAWS:
		var point := _arena.pick_spawn_point(origin, MINIMUM_DISTANCE, facing)
		var offset := point - origin
		offset.y = 0.0
		if facing.dot(offset.normalized()) < 0.0:
			behind += 1

	# Assert: uniform random would sit near half.
	var share := float(behind) / float(DRAWS)
	if share < 0.6:
		_failures.append(
			"only %.0f%% of spawns came from behind the player — they are "
			% (share * 100.0)
			+ "appearing in plain view"
		)
	else:
		print("PASS: %.0f%% of spawns arrive behind the player" % (share * 100.0))


func test_spawn_director_spreads_across_chambers() -> void:
	# Arrange
	var origin := Vector3.ZERO
	var facing := Vector3.FORWARD
	var used := {}
	var immediate_repeats := 0
	var previous := -1

	# Act
	for draw in DRAWS:
		var point := _arena.pick_spawn_point(origin, MINIMUM_DISTANCE, facing)
		var chamber := _chamber_of(point)
		used[chamber] = true

		if chamber == previous:
			immediate_repeats += 1
		previous = chamber

	# Assert
	if used.size() < 4:
		_failures.append(
			"spawns only ever used %d chambers out of %d"
			% [used.size(), Arena.SPAWN_CELLS.size()]
		)
		return

	var repeat_share := float(immediate_repeats) / float(DRAWS)
	if repeat_share > 0.25:
		_failures.append(
			"%.0f%% of spawns reused the chamber they just used" % (repeat_share * 100.0)
		)
		return

	print("PASS: spawns used %d chambers, %.0f%% back-to-back repeats" % [
		used.size(), repeat_share * 100.0
	])


## Which chamber a returned point belongs to.
func _chamber_of(point: Vector3) -> int:
	for index in _arena.spawn_points.size():
		if _arena.spawn_points[index].is_equal_approx(point):
			return _arena.spawn_chambers[index]
	return -1


func _report() -> void:
	if _arena != null and is_instance_valid(_arena):
		root.remove_child(_arena)
		_arena.free()
		_arena = null

	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
