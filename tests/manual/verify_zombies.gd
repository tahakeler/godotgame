extends SceneTree

## Integration check for the zombie loop: they spawn, they actually navigate
## toward the player, and killing one awards reserve ammunition.
##
## Navigation is the part worth testing. A zombie that spawns but never moves
## produces no error — it just stands at the arena edge, and the game looks
## finished until you play it.

const GAME_SCENE := "res://src/core/game.tscn"
const SPAWN_WAIT := 1.2
const MOVE_WAIT := 2.4
const MOVEMENT_THRESHOLD := 1.0

var _game: Game
var _elapsed := 0.0
var _spawn_positions: Dictionary = {}
var _failures: Array[String] = []
var _phase := 0


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(delta: float) -> bool:
	# Pacing is compressed here rather than in _initialize(): @onready vars are
	# still null until _ready() runs at the start of the first frame, so
	# _game.spawner would not exist yet. Timing only — no behaviour changes.
	if _phase == -1 or _game.spawner == null:
		return false

	if _elapsed == 0.0:
		var spawner: ZombieSpawner = _game.spawner
		spawner.grace_period = 0.0
		spawner.initial_interval = 0.05
		spawner.minimum_spawn_distance = 0.0

	_elapsed += delta

	if _phase == 0 and _elapsed >= SPAWN_WAIT:
		_phase = 1
		_capture_spawn_positions()

	elif _phase == 1 and _elapsed >= MOVE_WAIT:
		_phase = 2
		_check_movement()
		_check_kill_awards_ammo()
		_report()
		return true

	return false


func _capture_spawn_positions() -> void:
	var zombies := _living_zombies()

	if zombies.is_empty():
		_failures.append("no zombies spawned after %.1fs" % SPAWN_WAIT)
		return

	for zombie in zombies:
		_spawn_positions[zombie.get_instance_id()] = zombie.global_position


func _check_movement() -> void:
	if _spawn_positions.is_empty():
		return

	var moved := 0
	var tracked := 0

	for zombie in _living_zombies():
		var id := zombie.get_instance_id()
		if not _spawn_positions.has(id):
			continue

		tracked += 1
		if zombie.global_position.distance_to(_spawn_positions[id]) >= MOVEMENT_THRESHOLD:
			moved += 1

	if tracked == 0:
		_failures.append("no tracked zombies survived to the movement check")
	elif moved == 0:
		_failures.append(
			"%d zombies tracked, none moved %.1fm — navigation is not working"
			% [tracked, MOVEMENT_THRESHOLD]
		)
	else:
		print("PASS: %d/%d tracked zombies navigated toward the player" % [moved, tracked])


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


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
