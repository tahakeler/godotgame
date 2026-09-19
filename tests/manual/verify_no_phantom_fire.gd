extends SceneTree

## Asserts the weapon never fires without input.
##
## Screenshot captures kept coming back with rounds missing from a magazine
## nobody had fired. In a game whose whole premise is counting bullets, ammunition
## leaving the magazine on its own is not a cosmetic issue — it silently breaks
## the only resource the design runs on.

const GAME_SCENE := "res://src/core/game.tscn"
const WATCH_SECONDS := 6.0

var _game: Game
var _elapsed := 0.0
var _started := false
var _magazine_at_start := -1
var _reserve_at_start := -1
var _dry_fires := 0
var _shots := 0


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(delta: float) -> bool:
	if _game == null or _game.weapon == null:
		return false

	if not _started:
		_started = true
		_magazine_at_start = _game.weapon.magazine_ammo
		_reserve_at_start = _game.weapon.reserve_ammo
		_game.weapon.fired.connect(func(_from: Vector3, _to: Vector3) -> void:
			_shots += 1
		)
		_game.weapon.dry_fired.connect(func() -> void: _dry_fires += 1)
		return false

	_elapsed += delta
	if _elapsed < WATCH_SECONDS:
		return false

	_report()
	return true


func _report() -> void:
	var failures: Array[String] = []
	var magazine: int = _game.weapon.magazine_ammo

	if _shots > 0:
		failures.append("weapon fired %d times with no input" % _shots)
	if _dry_fires > 0:
		failures.append("weapon dry-fired %d times with no input" % _dry_fires)
	if magazine != _magazine_at_start:
		failures.append("magazine changed from %d to %d" % [_magazine_at_start, magazine])

	# The reserve is allowed to grow: zombies dying feed it, and that is the
	# intended behaviour rather than a leak.
	if _game.weapon.reserve_ammo < _reserve_at_start:
		failures.append("reserve fell from %d to %d" % [
			_reserve_at_start, _game.weapon.reserve_ammo
		])

	root.remove_child(_game)
	_game.free()
	_game = null

	if failures.is_empty():
		print("PASS: no shots fired in %.0fs of no input (magazine held at %d)" % [
			WATCH_SECONDS, magazine
		])
		quit(0)
		return

	for failure in failures:
		printerr("FAIL: %s" % failure)
	quit(1)
