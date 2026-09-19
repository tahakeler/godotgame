extends SceneTree

## Verifies what zombies know and how they come to know it.
##
## Zombies used to read the player's live position every frame, which meant
## noise could only ever distract them — there was nothing left to learn. They
## now hold a *belief*, and sight, sound and each other are the three channels
## that update it. A belief can be stale, wrong, or planted, and all three are
## things the player can work with.
##
## None of this fails loudly if it breaks. Zombies would still arrive, still
## attack, still die; the game would quietly go back to being about aim.
##
##   Godot --headless --script tests/manual/verify_noise.gd

const ARENA_SCENE := "res://src/arena/arena.tscn"
const ZOMBIE_SCENE := "res://src/gameplay/zombie/zombie.tscn"

## Measured with a probe rather than guessed. From the arena centre a sound
## straight up the north corridor travels almost exactly its straight-line
## distance, while one diagonally into the rock between two arms has to go the
## long way round — 22.6m apart in space, 42.8m apart by any route a sound
## could actually take.
const DOWN_THE_CORRIDOR := Vector3(0.0, 0.1, 20.0)
const THROUGH_THE_ROCK := Vector3(-16.0, 0.1, 16.0)

var _arena: Arena
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	# The navigation server syncs its maps on a physics step, and every hearing
	# check below is a path query against it.
	_frames += 1
	if _frames < 30:
		return false

	test_a_spawned_zombie_already_believes_the_player_is_somewhere()
	test_a_sound_within_range_is_heard()
	test_a_sound_beyond_range_is_not_heard()
	test_sound_travels_through_the_map_not_through_rock()
	test_a_brute_hears_further_than_a_shambler()
	test_a_hunting_zombie_ignores_noise()
	test_an_alert_spreads_a_belief()
	test_a_belief_decays_to_unaware()

	_report()
	return true


## The safeguard that keeps the horde relentless. Without it, spawned zombies
## would wander off into empty chambers and the pressure the whole game is
## built on would drain away without anything looking broken.
func test_a_spawned_zombie_already_believes_the_player_is_somewhere() -> void:
	# Arrange
	var player := _marker(Vector3(0.0, 0.1, 0.0))
	var zombie := _zombie(ZombieTypes.Kind.SHAMBLER, DOWN_THE_CORRIDOR)

	# Act
	zombie.set_target(player)

	# Assert
	if not zombie.is_investigating():
		_failures.append(
			"a newly spawned zombie had no idea where the player was — "
			+ "spawns would wander instead of arriving"
		)
	elif not zombie.last_known_position.is_equal_approx(player.global_position):
		_failures.append("a spawned zombie believed the wrong position")
	else:
		print("PASS: a spawned zombie arrives already looking for the player")

	zombie.free()
	player.free()


func test_a_sound_within_range_is_heard() -> void:
	# Arrange: a Shambler at the centre hears 26m, and this sound is 20m up an
	# open corridor.
	var zombie := _targeted_zombie(ZombieTypes.Kind.SHAMBLER, Vector3(0.0, 0.1, 0.0))

	# Act
	var heard: bool = zombie.hear_noise(DOWN_THE_CORRIDOR, 1.0)

	# Assert
	if not heard:
		_failures.append("a sound 20m up an open corridor was not heard at all")
	elif not zombie.last_known_position.is_equal_approx(DOWN_THE_CORRIDOR):
		_failures.append("a heard sound did not become the zombie's belief")
	else:
		print("PASS: a sound carries 20m down an open corridor")

	_free_targeted(zombie)


func test_a_sound_beyond_range_is_not_heard() -> void:
	# Arrange
	var zombie := _targeted_zombie(ZombieTypes.Kind.SHAMBLER, Vector3(0.0, 0.1, 0.0))

	# Act
	var heard: bool = zombie.hear_noise(Vector3(200.0, 0.1, 0.0), 1.0)

	# Assert
	if heard:
		_failures.append("a sound 200m away was heard — distance is no defence")
	else:
		print("PASS: a sound far beyond hearing range is ignored")

	_free_targeted(zombie)


## The headline. A sound comfortably inside straight-line hearing range must
## still be inaudible when the only route to it goes two chambers round.
## Without this, rock does not muffle, and the cave's acoustics are a lie the
## player cannot learn.
func test_sound_travels_through_the_map_not_through_rock() -> void:
	# Arrange
	var zombie := _targeted_zombie(ZombieTypes.Kind.SHAMBLER, Vector3(0.0, 0.1, 0.0))
	var straight_line := Vector3(0.0, 0.1, 0.0).distance_to(THROUGH_THE_ROCK)

	# Act
	var heard: bool = zombie.hear_noise(THROUGH_THE_ROCK, 1.0)

	# Assert
	if straight_line > zombie.hearing_range:
		_failures.append(
			"the test point is %.1fm away, outside the %.1fm hearing range, so "
			% [straight_line, zombie.hearing_range]
			+ "this proves nothing — pick a closer one"
		)
	elif heard:
		_failures.append(
			"a sound %.1fm away in a straight line was heard through solid rock"
			% straight_line
		)
	else:
		print("PASS: rock muffles — %.1fm away in space, too far by any route" % straight_line)

	_free_targeted(zombie)


func test_a_brute_hears_further_than_a_shambler() -> void:
	# Arrange: 32m up the corridor sits between a Shambler's 26m and a Brute's
	# 42m, and the route there is a straight run.
	var far_up_the_corridor := Vector3(0.0, 0.1, 32.0)
	var shambler := _targeted_zombie(ZombieTypes.Kind.SHAMBLER, Vector3(0.0, 0.1, 0.0))
	var brute := _targeted_zombie(ZombieTypes.Kind.BRUTE, Vector3(0.0, 0.1, 0.0))

	# Act
	var shambler_heard: bool = shambler.hear_noise(far_up_the_corridor, 1.0)
	var brute_heard: bool = brute.hear_noise(far_up_the_corridor, 1.0)

	# Assert
	if shambler_heard or not brute_heard:
		_failures.append(
			"at 32m the Brute should hear and the Shambler should not "
			+ "(Shambler: %s, Brute: %s)" % [str(shambler_heard), str(brute_heard)]
		)
	else:
		print("PASS: a Brute hears a shot the Shambler beside it misses")

	_free_targeted(shambler)
	_free_targeted(brute)


func test_a_hunting_zombie_ignores_noise() -> void:
	# Arrange: something with eyes on you must not wander off because a gun
	# went off nearby, or firing becomes an escape rather than a cost.
	var zombie := _targeted_zombie(ZombieTypes.Kind.SHAMBLER, Vector3(0.0, 0.1, 0.0))
	zombie.awareness = Zombie.Awareness.HUNTING

	# Act
	var heard: bool = zombie.hear_noise(DOWN_THE_CORRIDOR, 1.0)

	# Assert
	if heard or zombie.is_investigating():
		_failures.append(
			"a zombie that could see the player was distracted by a noise"
		)
	else:
		print("PASS: a zombie with eyes on the player ignores noise")

	_free_targeted(zombie)


func test_an_alert_spreads_a_belief() -> void:
	# Arrange
	var zombie := _targeted_zombie(ZombieTypes.Kind.SHAMBLER, Vector3(0.0, 0.1, 0.0))
	var shouted_about := Vector3(8.0, 0.1, -6.0)

	# Act
	zombie.receive_alert(shouted_about)

	# Assert
	if not zombie.last_known_position.is_equal_approx(shouted_about):
		_failures.append("an alert from another zombie did not change the belief")
	elif not zombie.is_investigating():
		_failures.append("an alerted zombie did not go and look")
	else:
		print("PASS: one zombie's alarm becomes another's belief")

	_free_targeted(zombie)


func test_a_belief_decays_to_unaware() -> void:
	# Arrange: a zombie standing exactly where it believes the player to be, so
	# it arrives immediately and starts searching.
	var here := Vector3(0.0, 0.1, 0.0)
	var zombie := _targeted_zombie(ZombieTypes.Kind.SHAMBLER, here)
	zombie.receive_alert(here)

	# Act: arrive, search, and run the search out.
	zombie._tick_awareness(0.1)
	zombie._tick_awareness(zombie.search_duration + 0.1)

	# Assert
	if zombie.awareness != Zombie.Awareness.UNAWARE:
		_failures.append(
			"a zombie searched an empty spot forever instead of giving up"
		)
	else:
		print("PASS: a belief that finds nothing decays to unaware")

	_free_targeted(zombie)


func _marker(at: Vector3) -> Node3D:
	var marker := Node3D.new()
	root.add_child(marker)
	marker.global_position = at
	return marker


func _zombie(kind: ZombieTypes.Kind, at: Vector3) -> Zombie:
	var zombie: Zombie = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	root.add_child(zombie)
	zombie.configure(kind)
	zombie.global_position = at
	return zombie


## A zombie with a player far enough away that sight never interferes.
func _targeted_zombie(kind: ZombieTypes.Kind, at: Vector3) -> Zombie:
	var zombie := _zombie(kind, at)
	zombie.set_target(_marker(Vector3(0.0, 0.1, -400.0)))
	return zombie


func _free_targeted(zombie: Zombie) -> void:
	var target: Node3D = zombie._target
	zombie.free()
	if target != null and is_instance_valid(target):
		target.free()


func _report() -> void:
	if _arena != null and is_instance_valid(_arena):
		root.remove_child(_arena)
		_arena.free()
		_arena = null

	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
