extends SceneTree

## Verifies that gunfire pulls zombies toward the sound.
##
## This is the mechanic that makes the game's first pillar true. Ammunition
## scarcity alone means a bullet costs a bullet; noise means it also costs
## position. If the diversion quietly stopped working, nothing would look
## broken — zombies would still arrive, still attack, still die. The game would
## just go back to being about aim, and no error would say so.
##
##   Godot --headless --script tests/manual/verify_noise.gd

const ZOMBIE_SCENE := "res://src/gameplay/zombie/zombie.tscn"

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	test_noise_in_range_diverts_a_zombie()
	test_noise_out_of_range_is_ignored()
	test_an_engaged_zombie_ignores_noise()
	test_a_brute_hears_further_than_a_shambler()
	test_investigation_expires()

	_report()
	return true


func test_noise_in_range_diverts_a_zombie() -> void:
	# Arrange: a player far away, a zombie, and a shot between them.
	var player := _build_marker(Vector3(0.0, 0.0, 60.0))
	var zombie := _build_zombie(ZombieTypes.Kind.SHAMBLER, Vector3.ZERO)
	zombie.set_target(player)

	# Act
	var heard: bool = zombie.hear_noise(Vector3(10.0, 0.0, 0.0), 1.0)

	# Assert
	if not heard or not zombie.is_investigating():
		_failures.append("a shot within hearing range did not divert the zombie")
	else:
		print("PASS: a shot within hearing range diverts a zombie")

	zombie.free()
	player.free()


func test_noise_out_of_range_is_ignored() -> void:
	# Arrange
	var player := _build_marker(Vector3(0.0, 0.0, 60.0))
	var zombie := _build_zombie(ZombieTypes.Kind.SHAMBLER, Vector3.ZERO)
	zombie.set_target(player)

	# Act: well past a Shambler's 26m hearing.
	var heard: bool = zombie.hear_noise(Vector3(200.0, 0.0, 0.0), 1.0)

	# Assert
	if heard or zombie.is_investigating():
		_failures.append(
			"a shot 200m away still diverted a zombie — distance is no defence"
		)
	else:
		print("PASS: a shot beyond hearing range is ignored")

	zombie.free()
	player.free()


func test_an_engaged_zombie_ignores_noise() -> void:
	# Arrange: the player is right on top of this zombie.
	var player := _build_marker(Vector3(1.0, 0.0, 0.0))
	var zombie := _build_zombie(ZombieTypes.Kind.SHAMBLER, Vector3.ZERO)
	zombie.set_target(player)

	# Act
	var heard: bool = zombie.hear_noise(Vector3(12.0, 0.0, 0.0), 1.0)

	# Assert: something mauling you must not wander off because a gun went
	# off nearby, or firing becomes a panic button instead of a cost.
	if heard or zombie.is_investigating():
		_failures.append(
			"a zombie already on the player was distracted by a noise — "
			+ "firing would be an escape rather than a cost"
		)
	else:
		print("PASS: a zombie already engaged ignores noise")

	zombie.free()
	player.free()


func test_a_brute_hears_further_than_a_shambler() -> void:
	# Arrange: a distance between the two hearing ranges.
	var distance := Vector3(34.0, 0.0, 0.0)
	var player := _build_marker(Vector3(0.0, 0.0, 60.0))

	var shambler := _build_zombie(ZombieTypes.Kind.SHAMBLER, Vector3.ZERO)
	shambler.set_target(player)
	var brute := _build_zombie(ZombieTypes.Kind.BRUTE, Vector3.ZERO)
	brute.set_target(player)

	# Act
	var shambler_heard: bool = shambler.hear_noise(distance, 1.0)
	var brute_heard: bool = brute.hear_noise(distance, 1.0)

	# Assert
	if shambler_heard or not brute_heard:
		_failures.append(
			"at %.0fm the Brute should hear and the Shambler should not "
			% distance.x
			+ "(Shambler heard: %s, Brute heard: %s)"
			% [str(shambler_heard), str(brute_heard)]
		)
	else:
		print("PASS: a Brute hears a shot the Shambler beside it misses")

	shambler.free()
	brute.free()
	player.free()


func test_investigation_expires() -> void:
	# Arrange
	var player := _build_marker(Vector3(0.0, 0.0, 60.0))
	var zombie := _build_zombie(ZombieTypes.Kind.SHAMBLER, Vector3.ZERO)
	zombie.set_target(player)
	zombie.hear_noise(Vector3(10.0, 0.0, 0.0), 1.0)

	# Act: wait out the investigation without ever reaching the sound.
	zombie._tick_investigation(zombie.investigate_duration + 0.1)

	# Assert
	if zombie.is_investigating():
		_failures.append("a zombie kept investigating a sound forever")
	else:
		print("PASS: an investigation gives up and returns to the hunt")

	zombie.free()
	player.free()


## A stand-in for the player: the zombie only reads its global position.
func _build_marker(at: Vector3) -> Node3D:
	var marker := Node3D.new()
	root.add_child(marker)
	marker.global_position = at
	return marker


func _build_zombie(kind: ZombieTypes.Kind, at: Vector3) -> Zombie:
	var zombie: Zombie = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	root.add_child(zombie)
	zombie.configure(kind)
	zombie.global_position = at
	return zombie


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
