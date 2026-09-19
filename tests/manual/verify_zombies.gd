extends SceneTree

## Integration check for the zombie loop.
##
## The meaningful question is not "did a zombie move" — a zombie nudged by
## gravity moves. It is whether zombies spawned in the outer chambers actually
## path through the corridors and close on the player. A navmesh that bakes but
## does not connect the ring leaves them milling about in their spawn room
## forever, and reports no error anywhere.

const GAME_SCENE := "res://src/core/game.tscn"

## Let zombies spawn and settle before the first distance sample.
const SETTLE_SECONDS := 1.5
## How long they then get to close the gap.
const PURSUIT_SECONDS := 7.0
## Distance a zombie must close to count as genuinely pursuing.
const REQUIRED_APPROACH := 4.0
## Fraction of tracked zombies that must be pursuing.
const REQUIRED_PURSUIT_RATIO := 0.6

const WATCHDOG_TIMEOUT := 45.0

var _game: Game
var _elapsed := 0.0
var _watchdog := 0.0
var _phase := 0
var _configured := false
var _start_distances: Dictionary = {}
var _failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(delta: float) -> bool:
	# Hard ceiling. Without it, a game scene that fails to initialise leaves
	# this loop spinning forever and the run has to be killed by hand.
	_watchdog += delta
	if _watchdog > WATCHDOG_TIMEOUT:
		printerr("FAIL: timed out after %.0fs — game scene never initialised" % WATCHDOG_TIMEOUT)
		_teardown()
		quit(1)
		return true

	# @onready vars are null until _ready() runs at the start of the first frame.
	if _game == null or _game.spawner == null:
		return false

	if not _configured:
		_configured = true
		# Compress pacing only. Spawn distance keeps its real value, so zombies
		# still start in the outer chambers rather than beside the player.
		_game.spawner.grace_period = 0.0
		_game.spawner.initial_interval = 0.35

	_elapsed += delta

	if _phase == 0 and _elapsed >= SETTLE_SECONDS:
		_phase = 1
		_record_start_distances()

	elif _phase == 1 and _elapsed >= SETTLE_SECONDS + PURSUIT_SECONDS:
		_phase = 2
		_check_pursuit()
		_check_kill_awards_ammo()
		_report()
		return true

	return false


func _record_start_distances() -> void:
	var player_position: Vector3 = _game.player.global_position

	for zombie in _living_zombies():
		_start_distances[zombie.get_instance_id()] = \
			player_position.distance_to(zombie.global_position)

	if _start_distances.is_empty():
		_failures.append("no zombies spawned after %.1fs" % SETTLE_SECONDS)


func _check_pursuit() -> void:
	if _start_distances.is_empty():
		return

	var player_position: Vector3 = _game.player.global_position
	var tracked := 0
	var pursuing := 0
	var best_approach := 0.0

	for zombie in _living_zombies():
		var id := zombie.get_instance_id()
		if not _start_distances.has(id):
			continue

		tracked += 1
		var distance_now: float = player_position.distance_to(zombie.global_position)
		var approach: float = _start_distances[id] - distance_now
		best_approach = maxf(best_approach, approach)

		# A zombie already in contact cannot close any further, so it counts.
		if approach >= REQUIRED_APPROACH or distance_now <= zombie.attack_range:
			pursuing += 1

	if tracked == 0:
		_failures.append("no tracked zombies survived to the pursuit check")
		return

	var ratio := float(pursuing) / float(tracked)

	if ratio < REQUIRED_PURSUIT_RATIO:
		_failures.append(
			"only %d of %d zombies closed %.0fm on the player (%.0f%%, need %.0f%%); "
			% [pursuing, tracked, REQUIRED_APPROACH, ratio * 100.0,
				REQUIRED_PURSUIT_RATIO * 100.0]
			+ "best approach %.1fm — the navmesh may not connect the ring" % best_approach
		)
	else:
		print("PASS: %d/%d zombies pursued from the outer chambers (best %.1fm closed)" % [
			pursuing, tracked, best_approach
		])


func _check_kill_awards_ammo() -> void:
	var zombies := _living_zombies()
	if zombies.is_empty():
		_failures.append("no living zombie available for the kill check")
		return

	var weapon: Weapon = _game.weapon
	var reserve_before: int = weapon.reserve_ammo
	var kills_before: int = _game.kills

	var victim: Zombie = zombies[0]
	victim.take_damage(victim.health.max_health)

	var expected_reserve := mini(reserve_before + _game.ammo_per_kill, weapon.max_reserve)

	if _game.kills != kills_before + 1:
		_failures.append("kill count did not increment: %d -> %d" % [
			kills_before, _game.kills
		])
	elif weapon.reserve_ammo != expected_reserve:
		_failures.append("kill awarded wrong ammo: expected %d, got %d" % [
			expected_reserve, weapon.reserve_ammo
		])
	else:
		print("PASS: kill awarded %d reserve ammo (%d -> %d)" % [
			_game.ammo_per_kill, reserve_before, weapon.reserve_ammo
		])


func _living_zombies() -> Array[Zombie]:
	var result: Array[Zombie] = []

	for child in _game.spawner.get_children():
		if child is Zombie and is_instance_valid(child) and not child.is_queued_for_deletion():
			result.append(child)

	return result


## Tear the scene down before quitting. The sound bank holds preloaded audio
## streams, and leaving them referenced at exit is reported as "resources still
## in use", which the check treats as a real error.
func _teardown() -> void:
	if _game != null and is_instance_valid(_game):
		root.remove_child(_game)
		_game.free()
		_game = null


func _report() -> void:
	_teardown()

	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
