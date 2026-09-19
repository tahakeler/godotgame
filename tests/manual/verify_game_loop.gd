extends SceneTree

## Verifies the round loop: kills shorten extraction, the clock reaching zero
## wins, death loses, and restart restores every system to its opening state.
##
## Restart is the case worth guarding. It resets systems in place rather than
## reloading the scene, so a value left behind — leftover zombies, a partially
## spent magazine, a half-drained clock — would silently carry into the next
## round and only show up as "the game gets harder every time you retry".

const GAME_SCENE := "res://src/core/game.tscn"

var _game: Game
var _failures: Array[String] = []
var _started := false


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	_test_kill_shortens_extraction()
	_test_player_death_loses_round()
	_test_restart_restores_opening_state()
	_test_clock_reaching_zero_wins()

	_report()
	return true


func _test_kill_shortens_extraction() -> void:
	_game.start_round()

	var time_before: float = _game.time_remaining
	var reserve_before: int = _game.weapon.reserve_ammo

	_game._on_zombie_died(Vector3.ZERO)

	var expected_time := time_before - _game.seconds_per_kill
	var expected_reserve := mini(
		reserve_before + _game.ammo_per_kill, _game.weapon.max_reserve
	)

	if not is_equal_approx(_game.time_remaining, expected_time):
		_failures.append("kill did not shorten extraction: expected %.1f, got %.1f" % [
			expected_time, _game.time_remaining
		])
	elif _game.kills != 1:
		_failures.append("kill count expected 1, got %d" % _game.kills)
	elif _game.weapon.reserve_ammo != expected_reserve:
		_failures.append("kill ammo reward expected %d, got %d" % [
			expected_reserve, _game.weapon.reserve_ammo
		])
	else:
		print("PASS: kill removed %.1fs from the clock and awarded %d ammo" % [
			_game.seconds_per_kill, _game.ammo_per_kill
		])


func _test_player_death_loses_round() -> void:
	_game.start_round()
	_game.player.health.invulnerability_duration = 0.0

	_game.player.take_damage(_game.player.health.max_health + 10.0, Vector3.ZERO)

	if _game.state != _game.RoundState.LOST:
		_failures.append("player death did not set state LOST (got %d)" % _game.state)
	elif not _game.is_round_over():
		_failures.append("is_round_over() false after death")
	else:
		print("PASS: player death ended the round as a loss")


func _test_restart_restores_opening_state() -> void:
	# Arrange — dirty every system the restart is supposed to clean up.
	_game.start_round()
	_game.weapon.magazine_ammo = 1
	_game.weapon.reserve_ammo = 0
	_game.time_remaining = 12.0
	_game.kills = 7
	_game.player.health.current_health = 3.0
	_game.player.global_position = Vector3(9, 1, -9)

	# Act
	_game.start_round()

	# Assert
	var problems: Array[String] = []
	if _game.state != _game.RoundState.PLAYING:
		problems.append("state not PLAYING")
	if _game.kills != 0:
		problems.append("kills=%d" % _game.kills)
	if not is_equal_approx(_game.time_remaining, _game.extraction_duration):
		problems.append("time=%.1f" % _game.time_remaining)
	if _game.weapon.magazine_ammo != _game.weapon.magazine_size:
		problems.append("magazine=%d" % _game.weapon.magazine_ammo)
	if _game.weapon.reserve_ammo != _game.weapon.starting_reserve:
		problems.append("reserve=%d" % _game.weapon.reserve_ammo)
	if not is_equal_approx(_game.player.health.current_health, _game.player.health.max_health):
		problems.append("health=%.1f" % _game.player.health.current_health)
	if _game.spawner.get_alive_count() != 0:
		problems.append("zombies=%d" % _game.spawner.get_alive_count())

	if problems.is_empty():
		print("PASS: restart restored player, weapon, clock, kills, and zombies")
	else:
		_failures.append("restart left stale state: %s" % ", ".join(problems))


func _test_clock_reaching_zero_wins() -> void:
	_game.start_round()
	_game.time_remaining = 0.05

	_game._process(0.2)

	if _game.state != _game.RoundState.WON:
		_failures.append("clock reaching zero did not win (state %d)" % _game.state)
	else:
		print("PASS: extraction clock reaching zero won the round")


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
