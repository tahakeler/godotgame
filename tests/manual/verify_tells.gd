extends SceneTree

## Verifies that a zombie's state is visible and audible.
##
## Every zombie has had a mental model since the awareness system landed, and
## for a while none of it reached the player. A system you cannot read is
## indistinguishable from one that cheats: a crowd converges and you have no
## way to know whether you were seen, heard, or told about. The tells are what
## turn the model into something you can play against, so they are worth
## asserting rather than eyeballing once.
##
##   Godot --headless --script tests/manual/verify_tells.gd

const ZOMBIE_SCENE := "res://src/gameplay/zombie/zombie.tscn"

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	test_an_unaware_zombie_does_not_glow()
	test_investigating_and_hunting_glow_differently()
	test_becoming_a_hunter_announces_itself()
	test_the_announcement_happens_once_per_transition()
	test_a_hit_flash_does_not_wipe_the_tell()

	_report()
	return true


func test_an_unaware_zombie_does_not_glow() -> void:
	# Arrange: a cave full of glowing outlines would cost more atmosphere than
	# it buys clarity, so the default state is unlit.
	var zombie := _zombie()

	# Act
	zombie._set_awareness(Zombie.Awareness.UNAWARE)

	# Assert
	if _glow_energy(zombie) > 0.0:
		_failures.append("a zombie that knows nothing was still glowing")
	else:
		print("PASS: an unaware zombie gives nothing away")

	zombie.free()


func test_investigating_and_hunting_glow_differently() -> void:
	# Arrange: "it heard something" and "it is coming for you" are different
	# situations and must not look the same.
	var zombie := _zombie()

	# Act
	zombie._set_awareness(Zombie.Awareness.INVESTIGATING)
	var investigating_colour := _glow_colour(zombie)
	var investigating_energy := _glow_energy(zombie)

	zombie._set_awareness(Zombie.Awareness.HUNTING)
	var hunting_colour := _glow_colour(zombie)
	var hunting_energy := _glow_energy(zombie)

	# Assert
	if investigating_energy <= 0.0:
		_failures.append("an investigating zombie showed no tell at all")
	elif investigating_colour.is_equal_approx(hunting_colour):
		_failures.append("investigating and hunting are the same colour")
	elif hunting_energy <= investigating_energy:
		_failures.append(
			"hunting (%.2f) is no brighter than investigating (%.2f)"
			% [hunting_energy, investigating_energy]
		)
	else:
		print("PASS: heard-something and seen-you read differently")

	zombie.free()


func test_becoming_a_hunter_announces_itself() -> void:
	# Arrange
	var zombie := _zombie()
	var announcements := [0]
	zombie.noticed_player.connect(
		func(_at: Vector3, _kind: ZombieTypes.Kind) -> void: announcements[0] += 1
	)

	# Act
	zombie._set_awareness(Zombie.Awareness.HUNTING)

	# Assert
	if announcements[0] != 1:
		_failures.append(
			"starting to hunt raised %d announcements, expected 1" % announcements[0]
		)
	else:
		print("PASS: a zombie that notices you says so")

	zombie.free()


func test_the_announcement_happens_once_per_transition() -> void:
	# Arrange: the alert rasp has to mean "something changed". Re-announcing
	# every frame a zombie is already hunting would turn a signal into a drone.
	var zombie := _zombie()
	var announcements := [0]
	zombie.noticed_player.connect(
		func(_at: Vector3, _kind: ZombieTypes.Kind) -> void: announcements[0] += 1
	)

	# Act
	zombie._set_awareness(Zombie.Awareness.HUNTING)
	zombie._set_awareness(Zombie.Awareness.HUNTING)
	zombie._set_awareness(Zombie.Awareness.HUNTING)

	# Assert
	if announcements[0] != 1:
		_failures.append(
			"staying in the hunt raised %d announcements, expected 1"
			% announcements[0]
		)
	else:
		print("PASS: the alert fires on the change, not on the state")

	zombie.free()


func test_a_hit_flash_does_not_wipe_the_tell() -> void:
	# Arrange: flashing swaps the whole material out. Restoring the old one
	# without the glow would silently clear the tell the moment you shot
	# something — exactly when knowing its state matters most.
	var zombie := _zombie()
	zombie._set_awareness(Zombie.Awareness.HUNTING)
	var before := _glow_energy(zombie)

	# Act
	var visual: ZombieVisual = zombie.get_node("Visual")
	visual.flash()
	visual._process(1.0)

	# Assert
	if not is_equal_approx(_glow_energy(zombie), before):
		_failures.append(
			"a hit flash cleared the awareness tell (%.2f -> %.2f)"
			% [before, _glow_energy(zombie)]
		)
	else:
		print("PASS: shooting a zombie does not hide what it knows")

	zombie.free()


func _zombie() -> Zombie:
	var zombie: Zombie = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	root.add_child(zombie)
	zombie.configure(ZombieTypes.Kind.SHAMBLER)
	return zombie


func _skin(zombie: Zombie) -> StandardMaterial3D:
	var visual: ZombieVisual = zombie.get_node("Visual")
	return visual._skin_material


func _glow_energy(zombie: Zombie) -> float:
	var skin := _skin(zombie)
	if skin == null or not skin.emission_enabled:
		return 0.0
	return skin.emission_energy_multiplier


func _glow_colour(zombie: Zombie) -> Color:
	var skin := _skin(zombie)
	return Color.BLACK if skin == null else skin.emission


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
