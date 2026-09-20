extends SceneTree

## Verifies the threat level: what counts as danger and what does not.
##
## This one figure drives the audio mix and the weight of the frame, so getting
## it wrong is felt everywhere at once without anything looking broken. The
## failure that matters most is subtle: a meter that counted every nearby
## zombie rather than only the hunting ones would go back to measuring how
## crowded the room is, throwing away the entire distinction the awareness
## system exists to make.
##
##   Godot --headless --script tests/manual/verify_tension.gd

const SPAWNER_SCRIPT := "res://src/gameplay/zombie/zombie_spawner.gd"
const ZOMBIE_SCENE := "res://src/gameplay/zombie/zombie.tscn"

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	test_an_empty_cave_is_not_threatening()
	test_zombies_that_have_not_seen_you_do_not_count()
	test_a_hunter_up_close_reads_hotter_than_one_far_away()
	test_more_hunters_read_hotter()
	test_the_meter_saturates()
	test_the_pulse_is_silent_below_its_threshold()

	_report()
	return true


func test_an_empty_cave_is_not_threatening() -> void:
	# Arrange
	var spawner := _spawner()

	# Act / Assert
	if not is_zero_approx(spawner.threat_level(Vector3.ZERO)):
		_failures.append("an empty cave registered danger")
	else:
		print("PASS: an empty cave reads as no threat")

	spawner.free()


## The failure that would quietly undo the awareness system.
func test_zombies_that_have_not_seen_you_do_not_count() -> void:
	# Arrange: three zombies standing on top of the player, none of which has
	# any idea it is there.
	var spawner := _spawner()
	for index in 3:
		_add_zombie(spawner, Vector3(1.0, 0.0, 0.0), Zombie.Awareness.UNAWARE)

	# Act
	var threat := spawner.threat_level(Vector3.ZERO)

	# Assert
	if threat > 0.0:
		_failures.append(
			"three oblivious zombies at arm's length registered %.2f threat — "
			% threat
			+ "the meter is counting bodies, not danger"
		)
	else:
		print("PASS: zombies that have not seen you are not a threat")

	spawner.free()


func test_a_hunter_up_close_reads_hotter_than_one_far_away() -> void:
	# Arrange
	var near_spawner := _spawner()
	_add_zombie(near_spawner, Vector3(3.0, 0.0, 0.0), Zombie.Awareness.HUNTING)

	var far_spawner := _spawner()
	_add_zombie(far_spawner, Vector3(45.0, 0.0, 0.0), Zombie.Awareness.HUNTING)

	# Act
	var near_threat := near_spawner.threat_level(Vector3.ZERO)
	var far_threat := far_spawner.threat_level(Vector3.ZERO)

	# Assert
	if near_threat <= far_threat:
		_failures.append(
			"a hunter 3m away (%.2f) read no hotter than one 45m away (%.2f)"
			% [near_threat, far_threat]
		)
	else:
		print("PASS: closing distance raises the threat (%.2f vs %.2f)" % [
			near_threat, far_threat
		])

	near_spawner.free()
	far_spawner.free()


func test_more_hunters_read_hotter() -> void:
	# Arrange
	var one := _spawner()
	_add_zombie(one, Vector3(8.0, 0.0, 0.0), Zombie.Awareness.HUNTING)

	var three := _spawner()
	for index in 3:
		_add_zombie(three, Vector3(8.0, 0.0, 0.0), Zombie.Awareness.HUNTING)

	# Act / Assert
	if three.threat_level(Vector3.ZERO) <= one.threat_level(Vector3.ZERO):
		_failures.append("three hunters read no hotter than one")
	else:
		print("PASS: a crowd of hunters reads hotter than a single one")

	one.free()
	three.free()


func test_the_meter_saturates() -> void:
	# Arrange: past a point the difference between five and nine is not
	# something the player can act on differently, and an unbounded figure
	# would drive the mix straight through the ceiling.
	var spawner := _spawner()
	for index in 12:
		_add_zombie(spawner, Vector3(2.0, 0.0, 0.0), Zombie.Awareness.HUNTING)

	# Act
	var threat := spawner.threat_level(Vector3.ZERO)

	# Assert
	if threat > 1.0:
		_failures.append("threat ran past its ceiling at %.2f" % threat)
	elif threat < 0.99:
		_failures.append("twelve hunters at arm's length only read %.2f" % threat)
	else:
		print("PASS: the meter saturates at 1.0 rather than climbing forever")

	spawner.free()


func test_the_pulse_is_silent_below_its_threshold() -> void:
	# Arrange: a single distant hunter must not start a heartbeat.
	var ambience := Ambience.new()
	root.add_child(ambience)

	# Act
	ambience.set_threat(ambience.pulse_threshold * 0.5, 100.0)
	var quiet := ambience._pulse.volume_db if ambience._pulse != null else -80.0

	ambience.set_threat(1.0, 100.0)
	var loud := ambience._pulse.volume_db if ambience._pulse != null else 0.0

	# Assert
	if quiet > -60.0:
		_failures.append(
			"the tension pulse was audible (%.1f dB) below its threshold" % quiet
		)
	elif loud <= quiet:
		_failures.append("the pulse did not rise with the threat")
	else:
		print("PASS: the pulse stays silent until danger is real (%.0f -> %.0f dB)" % [
			quiet, loud
		])

	ambience.free()


## Built straight from the script rather than by attaching it to a bare Node3D.
## set_script leaves the static type as Node3D, so every typed assignment
## afterwards fails; constructing the GDScript gives a properly typed spawner.
func _spawner() -> ZombieSpawner:
	var script: GDScript = load(SPAWNER_SCRIPT)
	var spawner: ZombieSpawner = script.new()
	root.add_child(spawner)
	return spawner


## Put a zombie into the spawner's alive list in a known state.
func _add_zombie(spawner: ZombieSpawner, at: Vector3, state: Zombie.Awareness) -> void:
	var zombie: Zombie = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	spawner.add_child(zombie)
	zombie.configure(ZombieTypes.Kind.SHAMBLER)
	zombie.global_position = at
	zombie.awareness = state
	spawner._alive.append(zombie)


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
