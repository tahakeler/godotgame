extends SceneTree

## Verifies the two ends of the ammo economy: the magazine refilling itself,
## and what happens when there is nothing left to refill it from.
##
## The dead end is the case worth guarding. Reserve ammo comes from kills and
## kills need ammo, so a player who spent their last round used to be stuck
## watching a round they could not influence until something ate them. That is
## not difficulty, it is a softlock with a countdown.
##
##   Godot --headless --script tests/manual/verify_ammo.gd

const WEAPON_SCENE := "res://src/gameplay/weapon/weapon.tscn"

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	test_weapon_empty_magazine_reloads_itself()
	test_weapon_manual_reload_still_tops_up_a_partial_magazine()
	test_weapon_fully_dry_scrounges_rounds_back()
	test_weapon_with_ammo_never_scrounges()

	_report()
	return true


func test_weapon_empty_magazine_reloads_itself() -> void:
	# Arrange
	var weapon := _build()
	weapon.magazine_ammo = 0
	weapon.reserve_ammo = 10

	# Act: one frame of the weapon's own processing.
	weapon._process(0.016)

	# Assert
	if not weapon.is_reloading():
		_failures.append("an empty magazine did not start reloading on its own")
	else:
		print("PASS: an empty magazine reloads itself")

	weapon.free()


func test_weapon_manual_reload_still_tops_up_a_partial_magazine() -> void:
	# Arrange: auto reload only covers an empty magazine, so a half-full one
	# must still be reloadable by hand or the habit stops working.
	var weapon := _build()
	weapon.magazine_ammo = 3
	weapon.reserve_ammo = 10

	# Act
	var started: bool = weapon.try_reload()

	# Assert
	if not started:
		_failures.append("a partial magazine could not be reloaded by hand")
	else:
		print("PASS: a partial magazine still reloads on request")

	weapon.free()


func test_weapon_fully_dry_scrounges_rounds_back() -> void:
	# Arrange
	var weapon := _build()
	weapon.magazine_ammo = 0
	weapon.reserve_ammo = 0

	# Act: wait out the resupply interval.
	weapon._tick_dry_resupply(weapon.dry_resupply_interval + 0.1)

	# Assert
	if weapon.reserve_ammo <= 0:
		_failures.append(
			"a completely dry weapon never recovered — the round is unwinnable "
			+ "and cannot be influenced"
		)
	else:
		print("PASS: a dry weapon scrounges %d rounds back" % weapon.reserve_ammo)

	weapon.free()


func test_weapon_with_ammo_never_scrounges() -> void:
	# Arrange: the trickle must not quietly top players up mid-fight.
	var weapon := _build()
	weapon.magazine_ammo = 1
	weapon.reserve_ammo = 4

	# Act
	weapon._tick_dry_resupply(weapon.dry_resupply_interval * 5.0)

	# Assert
	if weapon.reserve_ammo != 4:
		_failures.append(
			"reserve ammo changed while the player still had rounds (4 -> %d)"
			% weapon.reserve_ammo
		)
	else:
		print("PASS: a weapon with ammo left is never topped up")

	weapon.free()


func _build() -> Weapon:
	var weapon: Weapon = (load(WEAPON_SCENE) as PackedScene).instantiate()
	root.add_child(weapon)
	return weapon


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
