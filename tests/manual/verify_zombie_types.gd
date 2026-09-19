extends SceneTree

## Verifies the three zombie kinds are actually different, and that the ones
## meant to be rare stay locked until the round has run long enough.
##
## The risk this guards is silent sameness: a stats table that is wired up but
## never read produces three identical enemies wearing different names, and
## nothing anywhere reports a problem.

const ZOMBIE_SCENE := "res://src/gameplay/zombie/zombie.tscn"

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return false

	_test_kinds_differ()
	_test_rare_kinds_are_locked_early()
	_test_late_rounds_mix()

	_report()
	return true


func _test_kinds_differ() -> void:
	var scene: PackedScene = load(ZOMBIE_SCENE)
	var seen_health: Array[float] = []
	var seen_speed: Array[float] = []

	for kind in ZombieTypes.Kind.values():
		var zombie: Zombie = scene.instantiate()
		root.add_child(zombie)
		zombie.configure(kind)

		var definition := ZombieTypes.definition(kind)

		if not is_equal_approx(zombie.health.max_health, definition.health):
			_failures.append("%s health not applied: %.0f vs %.0f" % [
				definition.name, zombie.health.max_health, definition.health
			])
		if not is_equal_approx(zombie.move_speed, definition.speed):
			_failures.append("%s speed not applied" % definition.name)

		seen_health.append(zombie.health.max_health)
		seen_speed.append(zombie.move_speed)

		root.remove_child(zombie)
		zombie.free()

	# Distinct on both axes, or they are the same enemy in three hats.
	if seen_health.size() != _unique(seen_health).size():
		_failures.append("two kinds share the same health pool")
	elif seen_speed.size() != _unique(seen_speed).size():
		_failures.append("two kinds share the same speed")
	else:
		print("PASS: %d kinds differ in both health and speed" % seen_health.size())


func _test_rare_kinds_are_locked_early() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	for i in 200:
		var kind := ZombieTypes.pick(0.0, rng)
		if kind != ZombieTypes.Kind.SHAMBLER:
			_failures.append("%s appeared at the start of a round" % [
				ZombieTypes.definition(kind).name
			])
			return

	print("PASS: only Shamblers spawn in the opening seconds")


func _test_late_rounds_mix() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 999

	var seen: Dictionary = {}
	for i in 400:
		seen[ZombieTypes.pick(120.0, rng)] = true

	if seen.size() < ZombieTypes.Kind.values().size():
		_failures.append("late rounds only produced %d of %d kinds" % [
			seen.size(), ZombieTypes.Kind.values().size()
		])
	else:
		print("PASS: late rounds mix all %d kinds" % seen.size())


func _unique(values: Array[float]) -> Array[float]:
	var result: Array[float] = []
	for value in values:
		if not result.any(func(seen: float) -> bool: return is_equal_approx(seen, value)):
			result.append(value)
	return result


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
