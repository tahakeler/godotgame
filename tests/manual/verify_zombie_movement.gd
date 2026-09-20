extends SceneTree

## Verifies the physical movement layer added on top of the awareness system:
## acceleration with weight, per-kind differentiation, per-individual
## variation, separation from crowding, and an attack that can be dodged.
##
## Before this, velocity was assigned outright every physics frame — a
## Shambler, a Runner and a Brute all snapped straight to their speed with no
## way to tell one body's momentum from another's, and a contact hit was a
## damage tick with nothing to see or react to first. None of that failed
## loudly: a zombie missing this layer still arrives, still hits, still dies.
## It just reads as a shoal of identical units sliding along paths.
##
##   Godot --headless --script tests/manual/verify_zombie_movement.gd

const ZOMBIE_SCENE := "res://src/gameplay/zombie/zombie.tscn"

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	test_acceleration_ramps_rather_than_snapping_to_speed()
	test_a_brute_accelerates_slower_than_a_runner()
	test_individual_zombies_of_the_same_kind_vary_in_speed_and_gait()
	test_separation_pushes_overlapping_zombies_apart()
	test_separation_does_nothing_between_distant_zombies()
	test_an_attack_does_not_land_before_its_windup_finishes()
	test_a_landed_attack_lands_only_once()
	test_a_committed_lunge_can_whiff_if_the_target_gets_away()

	_report()
	return true


## The headline regression for #2: velocity used to be `direction * move_speed`
## every frame, an instant snap. If that ever comes back, this is the first
## thing that catches it — a zombie accelerating from a stop would already be
## at 90%+ of its top speed after a single 1/60s step.
func test_acceleration_ramps_rather_than_snapping_to_speed() -> void:
	# Arrange
	var zombie := _zombie(ZombieTypes.Kind.SHAMBLER)
	zombie.velocity = Vector3.ZERO
	var desired := Vector3(0.0, 0.0, -1.0) * zombie.move_speed

	# Act
	zombie._accelerate_toward(desired, 1.0 / 60.0)
	var after_one_tick := zombie.velocity.length()

	for _i in 240:
		zombie._accelerate_toward(desired, 1.0 / 60.0)
	var after_many_ticks := zombie.velocity.length()

	# Assert
	if after_one_tick >= zombie.move_speed * 0.9:
		_failures.append(
			"a single physics tick reached %.2f of move_speed %.2f — velocity is "
			% [after_one_tick, zombie.move_speed]
			+ "still being snapped straight to its target instead of ramping"
		)
	elif absf(after_many_ticks - zombie.move_speed) > zombie.move_speed * 0.05:
		_failures.append(
			"after 4s of continuous acceleration, speed was %.2f, not close to "
			% after_many_ticks + "the %.2f it was accelerating toward" % zombie.move_speed
		)
	else:
		print(
			"PASS: a zombie ramps from %.2f to %.2f m/s over time rather than snapping"
			% [after_one_tick, after_many_ticks]
		)

	zombie.free()


## #2's other half: a Brute should feel heavy to get moving. Same desired
## velocity, same elapsed time, and the kind with the lower acceleration must
## end up slower — this is the whole reason two kinds should ever feel
## different to walk toward you.
func test_a_brute_accelerates_slower_than_a_runner() -> void:
	# Arrange
	var brute := _zombie(ZombieTypes.Kind.BRUTE)
	var runner := _zombie(ZombieTypes.Kind.RUNNER)
	var desired := Vector3(0.0, 0.0, -1.0) * 100.0 # far above either top speed,
	# so the whole step is governed by acceleration, not by arriving at a cap.

	# Act
	brute._accelerate_toward(desired, 0.1)
	runner._accelerate_toward(desired, 0.1)

	# Assert
	if brute.acceleration >= runner.acceleration:
		_failures.append(
			"a Brute's acceleration (%.1f) is not lower than a Runner's (%.1f) — "
			% [brute.acceleration, runner.acceleration]
			+ "they were meant to feel different to get moving"
		)
	elif brute.velocity.length() >= runner.velocity.length():
		_failures.append(
			"after the same 0.1s, the Brute reached %.2f m/s and the Runner only "
			% brute.velocity.length() + "%.2f — the Brute should be the slower one to get moving"
			% runner.velocity.length()
		)
	else:
		print("PASS: a Brute (%.2f m/s) gets moving slower than a Runner (%.2f m/s)" % [
			brute.velocity.length(), runner.velocity.length()
		])

	brute.free()
	runner.free()


## #3: two Shamblers must not be the same zombie wearing two bodies. Each
## draws its speed/turn/gait jitter from its own seeded RNG in _ready(), so a
## sample of them should not all land on the same numbers.
func test_individual_zombies_of_the_same_kind_vary_in_speed_and_gait() -> void:
	# Arrange
	const SAMPLE_SIZE := 10
	var speed_scales: Array[float] = []
	var gait_offsets: Array[float] = []
	var zombies: Array[Zombie] = []

	for _i in SAMPLE_SIZE:
		var zombie := _zombie(ZombieTypes.Kind.SHAMBLER)
		zombies.append(zombie)
		speed_scales.append(zombie._speed_scale)
		gait_offsets.append(zombie._visual._gait_offset)

	# Act
	var distinct_speeds := 0
	var distinct_gaits := 0
	for i in range(1, SAMPLE_SIZE):
		if not is_equal_approx(speed_scales[i], speed_scales[0]):
			distinct_speeds += 1
		if not is_equal_approx(gait_offsets[i], gait_offsets[0]):
			distinct_gaits += 1

	# Assert
	if distinct_speeds == 0:
		_failures.append(
			"%d Shamblers were sampled and every one had the identical speed "
			% SAMPLE_SIZE + "multiplier %.4f — individuality is not wired up" % speed_scales[0]
		)
	elif distinct_gaits == 0:
		_failures.append(
			"%d Shamblers were sampled and every one had the identical gait "
			% SAMPLE_SIZE + "phase %.4f — a crowd would animate in lockstep" % gait_offsets[0]
		)
	else:
		print("PASS: %d/%d Shamblers sampled differ in speed, %d/%d differ in gait" % [
			distinct_speeds, SAMPLE_SIZE - 1, distinct_gaits, SAMPLE_SIZE - 1
		])

	for zombie in zombies:
		zombie.free()


## #1: this is the only thing standing between a crowd and a single stack of
## overlapping bodies, since zombies deliberately do not physically collide
## with each other. Two zombies placed on top of each other must be pushed
## apart, away from one another.
func test_separation_pushes_overlapping_zombies_apart() -> void:
	# Arrange: a stand-in for the spawner, since separation looks at siblings
	# under this zombie's parent.
	var group := _group()
	var a := _zombie_in(ZombieTypes.Kind.SHAMBLER, group)
	var b := _zombie_in(ZombieTypes.Kind.SHAMBLER, group)
	a.global_position = Vector3(0.1, 0.0, 0.0)
	b.global_position = Vector3(-0.1, 0.0, 0.0)

	# Act
	var push: Vector3 = a._compute_separation()

	# Assert
	if push.is_zero_approx():
		_failures.append(
			"two zombies standing on top of each other produced no separation "
			+ "push — a crowd would stack into one point"
		)
	elif push.x <= 0.0:
		_failures.append(
			"zombie A sits on the +X side of zombie B, but its separation push "
			+ "pointed the wrong way (%.2f, %.2f, %.2f)" % [push.x, push.y, push.z]
		)
	else:
		print("PASS: overlapping zombies push apart (%.2f m/s toward +X)" % push.x)

	_free_group(group)


## The other side of the same feature: separation must not reach across the
## whole map. A push that never turns off would be a permanent, invisible
## force keeping every zombie at arm's length from every other one.
func test_separation_does_nothing_between_distant_zombies() -> void:
	# Arrange
	var group := _group()
	var a := _zombie_in(ZombieTypes.Kind.SHAMBLER, group)
	var b := _zombie_in(ZombieTypes.Kind.SHAMBLER, group)
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(50.0, 0.0, 0.0)

	# Act
	var push: Vector3 = a._compute_separation()

	# Assert
	if not push.is_zero_approx():
		_failures.append(
			"zombies 50m apart still produced a separation push of length %.3f"
			% push.length()
		)
	else:
		print("PASS: separation is silent between zombies that are not crowding")

	_free_group(group)


## #4: a contact hit used to be an invisible damage tick — in range, off
## cooldown, damage applied, same frame. Now it must wind up first. Anything
## that fires hit_player before the windup elapses is the old behaviour back.
func test_an_attack_does_not_land_before_its_windup_finishes() -> void:
	# Arrange
	var zombie := _zombie(ZombieTypes.Kind.SHAMBLER)
	var dummy := _dummy(Vector3(1.0, 0.0, 0.0)) # inside attack_range
	zombie.set_target(dummy)
	var hits := [0]
	zombie.hit_player.connect(func(_d: float, _p: Vector3) -> void: hits[0] += 1)

	# Act: enter range and commit — this must only start the windup.
	var committed: bool = zombie._tick_attack(0.001)
	var hits_at_commit: int = hits[0]

	# Advance to just short of the windup completing.
	zombie._tick_attack(maxf(zombie.attack_windup - 0.02, 0.0))
	var hits_before_windup_ends: int = hits[0]

	# Assert
	if not committed or zombie._attack_state != Zombie.AttackState.WINDING_UP:
		_failures.append("entering range and being off cooldown did not start a windup")
	elif hits_at_commit != 0 or hits_before_windup_ends != 0:
		_failures.append(
			"damage landed during the windup — a contact hit is still an "
			+ "instant, undodgeable tick"
		)
	else:
		print("PASS: an attack winds up before it can possibly land")

	zombie.free()
	dummy.free()


## A hit must register exactly once per commitment, even though _try_land_hit
## is checked every physics frame for the whole lunge window.
func test_a_landed_attack_lands_only_once() -> void:
	# Arrange
	var zombie := _zombie(ZombieTypes.Kind.SHAMBLER)
	var dummy := _dummy(Vector3(1.0, 0.0, 0.0))
	zombie.set_target(dummy)
	var hits := [0]
	zombie.hit_player.connect(func(_d: float, _p: Vector3) -> void: hits[0] += 1)

	# Act: commit, run out the windup, then tick through the whole lunge in
	# small steps — _try_land_hit runs once per step.
	zombie._tick_attack(0.001)
	zombie._tick_attack(zombie.attack_windup + 0.001)
	var lunge_elapsed := 0.0
	while lunge_elapsed < zombie.attack_commit_duration + 0.05:
		zombie._tick_attack(0.02)
		lunge_elapsed += 0.02

	# Assert
	if hits[0] != 1:
		_failures.append(
			"a stationary target within range was hit %d times by one lunge, expected 1"
			% hits[0]
		)
	elif zombie._attack_state != Zombie.AttackState.READY or zombie._attack_remaining <= 0.0:
		_failures.append("a finished lunge did not return to cooldown")
	else:
		print("PASS: one commitment lands exactly one hit, then goes on cooldown")

	zombie.free()
	dummy.free()


## The point of the whole feature: once a zombie has locked in a lunge
## direction, it cannot re-aim. If the target gets out of attack_range before
## the lunge's hit check runs, it must whiff rather than track.
func test_a_committed_lunge_can_whiff_if_the_target_gets_away() -> void:
	# Arrange
	var zombie := _zombie(ZombieTypes.Kind.SHAMBLER)
	var dummy := _dummy(Vector3(1.0, 0.0, 0.0))
	zombie.set_target(dummy)
	var hits := [0]
	zombie.hit_player.connect(func(_d: float, _p: Vector3) -> void: hits[0] += 1)

	# Act: commit to the windup, then the target steps well out of range
	# before the lunge fires.
	zombie._tick_attack(0.001)
	dummy.global_position = Vector3(50.0, 0.0, 0.0)
	zombie._tick_attack(zombie.attack_windup + 0.001)
	zombie._tick_attack(zombie.attack_commit_duration + 0.05)

	# Assert
	if hits[0] != 0:
		_failures.append(
			"a target that moved out of range before the lunge fired was still hit — "
			+ "the lunge re-aimed instead of committing"
		)
	else:
		print("PASS: a target that escapes before the lunge lands is not hit")

	zombie.free()
	dummy.free()


func _zombie(kind: ZombieTypes.Kind) -> Zombie:
	var zombie: Zombie = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	root.add_child(zombie)
	zombie.configure(kind)
	return zombie


func _group() -> Node3D:
	var group := Node3D.new()
	root.add_child(group)
	return group


func _zombie_in(kind: ZombieTypes.Kind, parent: Node3D) -> Zombie:
	var zombie: Zombie = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	parent.add_child(zombie)
	zombie.configure(kind)
	return zombie


func _free_group(group: Node3D) -> void:
	root.remove_child(group)
	group.free()


func _dummy(at: Vector3) -> Node3D:
	var marker := Node3D.new()
	root.add_child(marker)
	marker.global_position = at
	return marker


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
