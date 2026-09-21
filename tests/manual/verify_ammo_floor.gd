extends SceneTree

## Verifies the last-resort ammo floor against the *arsenal*, not against the
## weapon in hand.
##
## Weapon.dry_resupply is the rule that stops a run from becoming unwinnable:
## when you have nothing left at all, the game scrounges dry_resupply_amount
## rounds every dry_resupply_interval seconds so you are never stood in a cave
## with a club. It is a floor, and a floor that triggers early is not a floor,
## it is a tap.
##
## The seam here is that a weapon carries three slots but only one set of live
## ammo fields. is_fully_dry() reads the live fields, so it answers "the thing
## in my hands is empty", which is the right answer for the HUD caption and the
## wrong one for the floor. verify_ammo.gd covers the floor with a single
## weapon, where the two questions have the same answer, so this was never seen.
##
##   Godot --headless --script tests/manual/verify_ammo_floor.gd

const GAME_SCENE := "res://src/core/game.tscn"
## Comfortably past Weapon.dry_resupply_interval (7.0s), in one step, so the
## floor fires at most once per call and the count is unambiguous.
const PAST_INTERVAL := 8.0

var _game: Game
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		# Autoloads exist under --script, but not until after _initialize.
		DeterministicSettings.apply(root)
		return false

	_game.start_round()

	test_the_floor_holds_off_while_another_weapon_still_has_ammo()
	test_the_floor_still_fires_when_the_whole_arsenal_is_dry()
	test_the_floor_holds_off_while_a_holstered_magazine_is_loaded()

	_report()
	return true


## The defect. Empty the pistol to nothing while the shotgun and rifle are
## untouched, and the pistol quietly refills itself for free — hold the empty
## gun, wait, and the run never runs out. The player is not out of ammo; they
## are one key press away from twenty shells.
func test_the_floor_holds_off_while_another_weapon_still_has_ammo() -> void:
	# Arrange
	var weapon := _game.weapon
	weapon.magazine_ammo = 0
	weapon.reserve_ammo = 0
	var stocked := _other_slot_reserve_total(weapon)

	# Act
	weapon._tick_dry_resupply(PAST_INTERVAL)

	# Assert
	if stocked <= 0:
		_failures.append(
			"the test is vacuous: the holstered weapons held %d reserve" % stocked
		)
	elif weapon.reserve_ammo != 0:
		_failures.append(
			"the ammo floor handed out %d rounds while %d reserve sat in the other slots"
			% [weapon.reserve_ammo, stocked]
		)
	else:
		print("PASS: the ammo floor holds off while another weapon still has ammo")


## The control. Without it the test above passes on a floor that never fires at
## all, which would be the worse bug of the two.
func test_the_floor_still_fires_when_the_whole_arsenal_is_dry() -> void:
	# Arrange
	var weapon := _game.weapon
	_strip_every_slot(weapon)

	# Act
	weapon._tick_dry_resupply(PAST_INTERVAL)

	# Assert
	if weapon.reserve_ammo != weapon.dry_resupply_amount:
		_failures.append(
			"a fully dry arsenal scrounged %d rounds, expected %d"
			% [weapon.reserve_ammo, weapon.dry_resupply_amount]
		)
	else:
		print("PASS: the ammo floor still fires when the whole arsenal is dry")


## A loaded magazine in a holstered weapon is ammo too. Reserve alone is not
## the question: a shotgun sat in its slot with six shells chambered is six
## shells the player can reach with one key press.
func test_the_floor_holds_off_while_a_holstered_magazine_is_loaded() -> void:
	# Arrange
	var weapon := _game.weapon
	_strip_every_slot(weapon)
	var holstered := _any_other_kind(weapon)
	weapon._slots[holstered].magazine = 4

	# Act
	weapon._tick_dry_resupply(PAST_INTERVAL)

	# Assert
	if weapon.reserve_ammo != 0:
		_failures.append(
			"the ammo floor handed out %d rounds while a holstered magazine held 4"
			% weapon.reserve_ammo
		)
	else:
		print("PASS: the ammo floor counts a holstered magazine as ammo")


## Reserve held by every weapon that is not the one in hand.
func _other_slot_reserve_total(weapon: Weapon) -> int:
	var total := 0
	for slot_kind in weapon._slots:
		if slot_kind != weapon.kind:
			total += int(weapon._slots[slot_kind].reserve)
	return total


## Zero every slot and the live fields, so nothing anywhere can be fired.
func _strip_every_slot(weapon: Weapon) -> void:
	for slot_kind in weapon._slots:
		weapon._slots[slot_kind].magazine = 0
		weapon._slots[slot_kind].reserve = 0
	weapon.magazine_ammo = 0
	weapon.reserve_ammo = 0


func _any_other_kind(weapon: Weapon) -> int:
	for slot_kind in weapon._slots:
		if slot_kind != weapon.kind:
			return slot_kind
	return weapon.kind


func _report() -> void:
	if _failures.is_empty():
		print("verify_ammo_floor: PASS")
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	printerr("verify_ammo_floor: FAIL (%d)" % _failures.size())
	quit(1)
