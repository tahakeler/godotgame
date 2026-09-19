extends SceneTree

## Assignment test evidence: one normal case and one boundary case per feature.
## Prints an expected-vs-actual table and exits non-zero if any check fails, so
## tools/check.sh blocks a merge on a broken feature.
##
## Run directly with:
##   /Applications/Godot47.app/Contents/MacOS/Godot --headless --script tests/feature_tests.gd

const WEAPON_SCENE := "res://src/gameplay/weapon/weapon.tscn"

var _results: Array[Dictionary] = []


## Tests run on the first processed frame, not in _initialize(). Nodes added
## before the tree starts running do not get _ready() called yet, so exported
## defaults would read as zero.
func _process(_delta: float) -> bool:
	_run_weapon_tests()
	_report()
	return true


## --- Feature 2: Ammunition and Reload -------------------------------------

func _run_weapon_tests() -> void:
	test_weapon_fire_with_ammo_decrements_magazine()
	test_weapon_fire_with_empty_magazine_is_blocked()
	test_weapon_reload_refills_magazine_from_reserve()
	test_weapon_reload_with_empty_reserve_is_blocked()


func test_weapon_fire_with_ammo_decrements_magazine() -> void:
	# Arrange
	var weapon := _make_weapon()
	var starting_magazine: int = weapon.magazine_ammo

	# Act
	var did_fire: bool = weapon.try_fire()

	# Assert
	_check(
		"weapon_fire_with_ammo_decrements_magazine",
		"NORMAL",
		"fired=true, magazine=%d" % (starting_magazine - 1),
		"fired=%s, magazine=%d" % [str(did_fire).to_lower(), weapon.magazine_ammo]
	)
	weapon.queue_free()


func test_weapon_fire_with_empty_magazine_is_blocked() -> void:
	# Arrange
	var weapon := _make_weapon()
	weapon.magazine_ammo = 0
	var dry_fire_count := {"value": 0}
	weapon.dry_fired.connect(func() -> void: dry_fire_count.value += 1)

	# Act
	var did_fire: bool = weapon.try_fire()

	# Assert
	_check(
		"weapon_fire_with_empty_magazine_is_blocked",
		"BOUNDARY",
		"fired=false, magazine=0, dry_fired=1",
		"fired=%s, magazine=%d, dry_fired=%d" % [
			str(did_fire).to_lower(), weapon.magazine_ammo, dry_fire_count.value
		]
	)
	weapon.queue_free()


func test_weapon_reload_refills_magazine_from_reserve() -> void:
	# Arrange
	var weapon := _make_weapon()
	weapon.magazine_ammo = 3
	weapon.reserve_ammo = 24

	# Act
	var did_reload: bool = weapon.try_reload()
	weapon._tick_reload(weapon.reload_duration + 0.1)

	# Assert — 5 rounds move from reserve to magazine
	_check(
		"weapon_reload_refills_magazine_from_reserve",
		"NORMAL",
		"reload=true, magazine=8, reserve=19",
		"reload=%s, magazine=%d, reserve=%d" % [
			str(did_reload).to_lower(), weapon.magazine_ammo, weapon.reserve_ammo
		]
	)
	weapon.queue_free()


func test_weapon_reload_with_empty_reserve_is_blocked() -> void:
	# Arrange
	var weapon := _make_weapon()
	weapon.magazine_ammo = 0
	weapon.reserve_ammo = 0

	# Act
	var did_reload: bool = weapon.try_reload()
	var fully_dry: bool = weapon.is_fully_dry()

	# Assert
	_check(
		"weapon_reload_with_empty_reserve_is_blocked",
		"BOUNDARY",
		"reload=false, magazine=0, fully_dry=true",
		"reload=%s, magazine=%d, fully_dry=%s" % [
			str(did_reload).to_lower(), weapon.magazine_ammo, str(fully_dry).to_lower()
		]
	)
	weapon.queue_free()


## --- Harness ---------------------------------------------------------------

func _make_weapon() -> Node:
	var scene: PackedScene = load(WEAPON_SCENE)
	var weapon: Node = scene.instantiate()
	root.add_child(weapon)
	return weapon


func _check(test_name: String, kind: String, expected: String, actual: String) -> void:
	_results.append({
		"name": test_name,
		"kind": kind,
		"expected": expected,
		"actual": actual,
		"passed": expected == actual,
	})


func _report() -> void:
	var failed := 0

	print("")
	print("LAST MAGAZINE — feature test evidence")
	print("=".repeat(96))

	for result in _results:
		var status := "PASS" if result.passed else "FAIL"
		if not result.passed:
			failed += 1

		print("[%s] %-8s %s" % [status, result.kind, result.name])
		print("         expected: %s" % result.expected)
		print("         actual:   %s" % result.actual)

	print("=".repeat(96))
	print("%d checks, %d passed, %d failed" % [_results.size(), _results.size() - failed, failed])
	print("")

	quit(1 if failed > 0 else 0)
