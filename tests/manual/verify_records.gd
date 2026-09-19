extends SceneTree

## Verifies personal bests, where "better" means something different per mode.
##
## Extraction is a race, so finishing beats not finishing and faster beats
## slower. Last Stand and Endless are endurance, so more is better. Getting any
## of those comparisons backwards would quietly record the *worst* run as the
## best, and nothing would report it.

const MODES := [
	GameSettings.Mode.EXTRACTION,
	GameSettings.Mode.TIMED,
	GameSettings.Mode.ENDLESS,
]

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return false

	_clear_records()
	_test_first_run_is_a_record()
	_test_extraction_prefers_finishing_then_speed()
	_test_endless_prefers_longer()
	_test_modes_are_independent()
	_clear_records()

	_report()
	return true


func _test_first_run_is_a_record() -> void:
	var recorded := Records.submit(
		GameSettings.Mode.ENDLESS, GameSettings.Difficulty.SOLDIER, 10, 60.0, false
	)

	if not recorded:
		_failures.append("the first run of a mode was not recorded as a best")
	else:
		print("PASS: first run of a mode records a best")


func _test_extraction_prefers_finishing_then_speed() -> void:
	var mode := GameSettings.Mode.EXTRACTION
	var difficulty := GameSettings.Difficulty.VETERAN

	Records.submit(mode, difficulty, 40, 90.0, false)

	if not Records.submit(mode, difficulty, 5, 200.0, true):
		_failures.append("a completed extraction did not beat an incomplete one")
		return

	if not Records.submit(mode, difficulty, 1, 120.0, true):
		_failures.append("a faster extraction did not beat a slower one")
		return

	if Records.submit(mode, difficulty, 99, 400.0, true):
		_failures.append("a slower extraction was accepted as a new best")
		return

	print("PASS: extraction prefers finishing, then finishing faster")


func _test_endless_prefers_longer() -> void:
	var mode := GameSettings.Mode.ENDLESS
	var difficulty := GameSettings.Difficulty.RECRUIT

	Records.submit(mode, difficulty, 5, 100.0, false)

	if not Records.submit(mode, difficulty, 1, 150.0, false):
		_failures.append("a longer endless run did not beat a shorter one")
		return

	if Records.submit(mode, difficulty, 500, 20.0, false):
		_failures.append("a shorter endless run was accepted despite more kills")
		return

	print("PASS: endless prefers surviving longer, regardless of kills")


func _test_modes_are_independent() -> void:
	var difficulty := GameSettings.Difficulty.SOLDIER

	Records.submit(GameSettings.Mode.TIMED, difficulty, 77, 300.0, true)

	var timed := Records.best(GameSettings.Mode.TIMED, difficulty)
	var endless := Records.best(GameSettings.Mode.ENDLESS, difficulty)

	if timed.get("kills", 0) != 77:
		_failures.append("Last Stand record did not store its own kills")
	elif endless.get("kills", 0) == 77:
		_failures.append("one mode's record leaked into another")
	else:
		print("PASS: each mode and difficulty keeps its own record")


func _clear_records() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.PATH))


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
