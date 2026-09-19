extends SceneTree

## Verifies the progression loop: kills earn experience, levels arrive, the
## upgrade screen opens with distinct choices, picking one applies its effect
## and hands control back, and restarting strips upgrades off again.
##
## The restart case is the one worth guarding. Upgrades mutate the player and
## weapon directly, so without an explicit reset the next round silently
## inherits every upgrade from the last and the difficulty curve stops meaning
## anything — with no error anywhere.

const GAME_SCENE := "res://src/core/game.tscn"

var _game: Game
var _failures: Array[String] = []
var _started := false


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	# @onready vars are null until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	_test_kills_earn_a_level()
	_test_choices_are_distinct()
	_test_upgrade_applies()
	_test_restart_strips_upgrades()

	_report()
	return true


func _test_kills_earn_a_level() -> void:
	_game.start_round()
	var needed: int = _game.progression.requirement

	for i in needed:
		_game.progression.add_kill_experience()

	if _game.progression.level != 2:
		_failures.append("after %d kills expected level 2, got %d" % [
			needed, _game.progression.level
		])
	elif not _game.upgrade_menu.is_open():
		_failures.append("levelling up did not open the upgrade screen")
	else:
		print("PASS: %d kills reached level 2 and opened the upgrade screen" % needed)


func _test_choices_are_distinct() -> void:
	var choices := _game.progression.roll_choices()
	var seen: Array[int] = []

	for choice in choices:
		if choice.id in seen:
			_failures.append("upgrade choices repeated an option")
			return
		seen.append(choice.id)

	if choices.size() != _game.progression.choices_per_level:
		_failures.append("expected %d choices, got %d" % [
			_game.progression.choices_per_level, choices.size()
		])
	else:
		print("PASS: %d distinct upgrade choices offered" % choices.size())


func _test_upgrade_applies() -> void:
	_game.start_round()
	var before: int = _game.weapon.magazine_size

	_game._apply_upgrade(Progression.Upgrade.MAGAZINE)

	if _game.weapon.magazine_size != before + 3:
		_failures.append("magazine upgrade expected %d, got %d" % [
			before + 3, _game.weapon.magazine_size
		])
	elif _game.upgrade_menu.is_open():
		_failures.append("upgrade screen stayed open after a choice")
	else:
		print("PASS: upgrade applied and control returned")


func _test_restart_strips_upgrades() -> void:
	_game.start_round()
	var baseline_magazine: int = _game.weapon.magazine_size
	var baseline_speed: float = _game.player.move_speed

	_game._apply_upgrade(Progression.Upgrade.MAGAZINE)
	_game._apply_upgrade(Progression.Upgrade.ADRENALINE)
	_game.start_round()

	var problems: Array[String] = []
	if _game.weapon.magazine_size != baseline_magazine:
		problems.append("magazine=%d" % _game.weapon.magazine_size)
	if not is_equal_approx(_game.player.move_speed, baseline_speed):
		problems.append("speed=%.2f" % _game.player.move_speed)
	if _game.progression.level != 1:
		problems.append("level=%d" % _game.progression.level)

	if problems.is_empty():
		print("PASS: restart stripped upgrades and reset progression")
	else:
		_failures.append("restart kept upgrades: %s" % ", ".join(problems))


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
