extends SceneTree

## Verifies Phase 2 — player movement: the stance system, the speed ladder it
## creates against the three zombie kinds, the step-up assist, and the feel
## constraints that stop the whole thing going floaty.
##
## Most of what is asserted here is design rather than plumbing. Sprint and
## crouch are trivial to implement as two multipliers and worthless that way:
## they only become a decision if each one wins a specific race and loses a
## different one, and if the fast one is loud while the slow one is quiet.
## Those relationships are invisible in the code — they live in the gap between
## two files — so this is where they are written down and defended.
##
##   Godot --headless --script tests/manual/verify_movement.gd

const PLAYER_SCENE := "res://src/gameplay/player/player.tscn"
const TICK := 1.0 / 60.0

## Top of the lip the player should walk over without stopping.
const LOW_LIP_HEIGHT := 0.3

## Headroom under the test ceiling: enough for a crouch, not for standing.
const CEILING_CLEARANCE := 1.3

## Slope of the test ramp, near what the arena's stairs run at.
const RAMP_DEGREES := 26.0

## Height of the ramp's centre. The ramp floats above the main floor so the
## player starts on its surface rather than walking into its end face.
const RAMP_CENTRE_Y := 1.9

const GRAVITY := 20.0

## Generous enough that a tick of a few milliseconds still covers the distance,
## and every loop below stops early once it has what it needs.
const MAX_TICKS := 800

enum Step { BUILD, SETTLE, ASSERT, DONE }

var _world: Node3D
var _player: Player
var _step: int = Step.BUILD
var _failures: Array[String] = []


func _initialize() -> void:
	_world = Node3D.new()
	root.add_child(_world)

	# A floor, a lip low enough to step over, and a wall too tall to climb.
	# Built here rather than borrowing the arena so the geometry under test is
	# stated in the test instead of being whatever the level happens to contain.
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	_add_box(Vector3(0.0, LOW_LIP_HEIGHT * 0.5, -3.0), Vector3(6.0, LOW_LIP_HEIGHT, 2.0))
	_add_box(Vector3(0.0, 1.5, 3.0), Vector3(6.0, 3.0, 2.0))

	# A ramp at the angle the arena's stairs run at, off to one side.
	var ramp := _add_box(Vector3(-12.0, RAMP_CENTRE_Y, 0.0), Vector3(8.0, 0.5, 8.0))
	ramp.rotation.x = deg_to_rad(RAMP_DEGREES)

	# A ceiling slab off to one side with only crouch clearance beneath it.
	# Built here with the rest of the world rather than inside the test that
	# uses it: the physics space does not learn about a new body until it
	# steps, so one created mid-assertion is invisible to test_move.
	_add_box(
		Vector3(12.0, CEILING_CLEARANCE + 0.5, 0.0), Vector3(4.0, 1.0, 4.0)
	)

	var scene: PackedScene = load(PLAYER_SCENE)
	_player = scene.instantiate()
	_world.add_child(_player)


func _process(_delta: float) -> bool:
	match _step:
		Step.SETTLE:
			# The physics space does not know about the static bodies until it
			# has stepped at least once, and test_move asks the space.
			_player.global_position = Vector3.ZERO

		Step.ASSERT:
			test_movement_sprint_is_faster_and_crouch_is_slower_than_a_walk()
			test_movement_speed_ladder_beats_and_loses_to_every_zombie_kind()
			test_movement_sprint_needs_a_forward_lean()
			test_movement_crouch_lowers_the_body_and_the_eye()
			test_movement_crouch_is_quiet_and_sprint_is_loud()
			test_movement_a_ceiling_keeps_the_player_crouched()
			test_movement_steps_over_a_low_lip()
			test_movement_does_not_climb_a_wall()
			test_movement_does_not_step_while_airborne()
			test_movement_the_step_assist_ignores_a_walkable_slope()
			test_movement_walks_up_a_ramp_at_the_slope_it_is()
			test_movement_jump_is_not_floaty()
			test_movement_reaches_full_speed_over_time_rather_than_at_once()

		Step.DONE:
			_report()
			return true

	_step += 1
	return false


func test_movement_sprint_is_faster_and_crouch_is_slower_than_a_walk() -> void:
	# Arrange / Act
	var walk := _speed_in(Player.Stance.WALKING)
	var sprint := _speed_in(Player.Stance.SPRINTING)
	var crouch := _speed_in(Player.Stance.CROUCHING)

	# Assert
	if not (crouch < walk and walk < sprint):
		_failures.append(
			"stances are not ordered: crouch %.2f, walk %.2f, sprint %.2f"
			% [crouch, walk, sprint]
		)
	else:
		print(
			"PASS: crouch %.2f < walk %.2f < sprint %.2f m/s"
			% [crouch, walk, sprint]
		)


## The assertion the whole stance system exists for.
##
## A Brute is slower than a crouch, so you can creep away from one. A Shambler
## is slower than a walk but faster than a crouch, so crouching near one that
## has already seen you is a mistake. A Runner is faster than a walk and slower
## than a sprint, so it is the thing sprint is *for* — and sprinting is the
## loudest way to move, so escaping one tends to call the next one over.
##
## If any of these inequalities flips, a stance silently stops being a choice.
func test_movement_speed_ladder_beats_and_loses_to_every_zombie_kind() -> void:
	# Arrange
	var crouch := _speed_in(Player.Stance.CROUCHING)
	var walk := _speed_in(Player.Stance.WALKING)
	var sprint := _speed_in(Player.Stance.SPRINTING)
	var shambler: float = ZombieTypes.definition(ZombieTypes.Kind.SHAMBLER).speed
	var runner: float = ZombieTypes.definition(ZombieTypes.Kind.RUNNER).speed
	var brute: float = ZombieTypes.definition(ZombieTypes.Kind.BRUTE).speed

	# Act / Assert
	var broken: Array[String] = []
	if crouch <= brute:
		broken.append("a crouch (%.2f) cannot escape a Brute (%.2f)" % [crouch, brute])
	if crouch >= shambler:
		broken.append("a crouch (%.2f) outruns a Shambler (%.2f), so crouching near one costs nothing" % [crouch, shambler])
	if walk <= shambler:
		broken.append("a walk (%.2f) cannot escape a Shambler (%.2f)" % [walk, shambler])
	if walk >= runner:
		broken.append("a walk (%.2f) outruns a Runner (%.2f), so sprint is never needed" % [walk, runner])
	if sprint <= runner:
		broken.append("a sprint (%.2f) cannot escape a Runner (%.2f)" % [sprint, runner])

	if broken.is_empty():
		print(
			"PASS: speed ladder holds — Brute %.1f < crouch %.1f < Shambler %.1f < walk %.1f < Runner %.1f < sprint %.1f"
			% [brute, crouch, shambler, walk, runner, sprint]
		)
	else:
		_failures.append("; ".join(broken))


## Sprinting sideways or backwards at full speed turns every retreat into a
## free escape, and having to turn your back is most of what makes retreating
## a decision.
func test_movement_sprint_needs_a_forward_lean() -> void:
	# Arrange
	_player.global_position = Vector3.ZERO
	Input.action_press("sprint")

	# Act
	_player._tick_stance(Vector2(0.0, 1.0), TICK)
	var backwards := _player.stance()

	_player._tick_stance(Vector2(0.0, -1.0), TICK)
	var forwards := _player.stance()

	Input.action_release("sprint")
	_player._tick_stance(Vector2.ZERO, 1.0)

	# Assert
	if backwards == Player.Stance.SPRINTING:
		_failures.append("sprint engaged while running backwards")
	elif forwards != Player.Stance.SPRINTING:
		_failures.append("sprint did not engage while running forwards")
	else:
		print("PASS: sprint needs a forward lean, not just the key")


func test_movement_crouch_lowers_the_body_and_the_eye() -> void:
	# Arrange
	_player.global_position = Vector3.ZERO
	var standing_eye := _player.head.position.y
	var shape := _player._collider.shape as CapsuleShape3D
	var standing_capsule := shape.height

	# Act: a full second of easing, so the view has finished moving.
	Input.action_press("crouch")
	_player._tick_stance(Vector2.ZERO, 1.0)
	var crouched_eye := _player.head.position.y
	var crouched_capsule := shape.height
	var feet := _player._collider.position.y - crouched_capsule * 0.5

	Input.action_release("crouch")
	_player._tick_stance(Vector2.ZERO, 1.0)

	# Assert
	if crouched_capsule >= standing_capsule:
		_failures.append("crouching did not shrink the collision capsule")
	elif crouched_eye >= standing_eye:
		_failures.append("crouching did not lower the camera")
	elif not is_zero_approx(feet):
		# Resizing about the capsule's centre instead of its feet sinks the
		# body halfway into the floor, which looks like falling through it.
		_failures.append("the crouched capsule's feet sit at %.3f, not on the floor" % feet)
	elif _player.head.position.y <= crouched_eye:
		_failures.append("releasing crouch did not raise the camera again")
	else:
		print(
			"PASS: crouch drops the eye %.2fm and the capsule %.2fm, feet stay on the floor"
			% [standing_eye - crouched_eye, standing_capsule - crouched_capsule]
		)


func test_movement_crouch_is_quiet_and_sprint_is_loud() -> void:
	# Arrange / Act
	var crouch := _noise_in(Player.Stance.CROUCHING)
	var walk := _noise_in(Player.Stance.WALKING)
	var sprint := _noise_in(Player.Stance.SPRINTING)

	# Assert: the trade only exists if the fast stance is the loud one.
	if not (crouch < walk and walk < sprint):
		_failures.append(
			"stance noise is not ordered: crouch %.2f, walk %.2f, sprint %.2f"
			% [crouch, walk, sprint]
		)
	elif crouch >= walk * 0.5:
		_failures.append(
			"a crouch at %.2f is not meaningfully quieter than a walk at %.2f"
			% [crouch, walk]
		)
	else:
		print(
			"PASS: footstep noise runs crouch %.2f < walk %.2f < sprint %.2f"
			% [crouch, walk, sprint]
		)


## Releasing crouch under a low ceiling must not push the player's head through
## the rock. The test stands them under the wall's overhang, which is solid to
## a height of three metres.
func test_movement_a_ceiling_keeps_the_player_crouched() -> void:
	# Arrange: stand under the slab, which has only crouch clearance beneath it.
	_player.global_position = Vector3(12.0, 0.0, 0.0)
	Input.action_press("crouch")
	_player._tick_stance(Vector2.ZERO, 1.0)

	# Act
	Input.action_release("crouch")
	_player._tick_stance(Vector2.ZERO, 1.0)
	var under_ceiling := _player.stance()

	_player.global_position = Vector3.ZERO
	_player._tick_stance(Vector2.ZERO, 1.0)
	var in_the_open := _player.stance()

	# Assert
	if under_ceiling != Player.Stance.CROUCHING:
		_failures.append(
			"the player stood up into a ceiling %.2fm above them" % CEILING_CLEARANCE
		)
	elif in_the_open != Player.Stance.WALKING:
		_failures.append("the player stayed crouched once the ceiling was gone")
	else:
		print("PASS: a low ceiling holds the crouch, open air releases it")


func test_movement_steps_over_a_low_lip() -> void:
	# Arrange: walking forward into a lip a third of a metre high.
	_player.global_position = Vector3(0.0, 0.0, -1.9)
	var before := _player.global_position.y

	# Act
	for _tick in MAX_TICKS:
		_player.velocity.z = -_player.move_speed
		_step_physics()
		if _player.global_position.z < -2.6:
			break

	# Assert
	var climbed := _player.global_position.y - before
	if climbed < LOW_LIP_HEIGHT - 0.05:
		_failures.append(
			"walking into a %.2fm lip only raised the player %.3fm — "
			% [LOW_LIP_HEIGHT, climbed]
			+ "they are stuck against it"
		)
	elif _player.global_position.z > -2.0:
		_failures.append("the player rose but never got over the lip")
	else:
		print("PASS: a %.2fm lip is stepped over, not stopped at" % LOW_LIP_HEIGHT)


## The other half of the step assist, and the one that goes wrong quietly: a
## step-up that does not check the height of what it is climbing lets the
## player walk up the side of any wall in the level.
func test_movement_does_not_climb_a_wall() -> void:
	# Arrange
	_player.global_position = Vector3(0.0, 0.0, 1.5)
	var before := _player.global_position.y

	# Act
	for _tick in MAX_TICKS:
		_player.velocity.z = _player.move_speed
		_step_physics()

	# Assert
	var climbed := _player.global_position.y - before
	if climbed > 0.05:
		_failures.append("the player climbed %.3fm up a 3m wall" % climbed)
	else:
		print("PASS: a wall is a wall — no climbing")


func test_movement_does_not_step_while_airborne() -> void:
	# Arrange: mid-jump, moving into the lip.
	_player.global_position = Vector3(0.0, 1.2, -1.9)
	_player.velocity = Vector3(0.0, 0.0, -_player.move_speed)
	var before := _player.global_position.y

	# Act
	_player._try_step_up(TICK)

	# Assert: stepping in mid-air is how a player ends up riding the tops of
	# walls they merely brushed against on the way past.
	if not is_equal_approx(_player.global_position.y, before):
		_failures.append("the step assist fired while the player was airborne")
	else:
		print("PASS: the step assist is grounded-only")

	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3.ZERO


## The guard inside the step assist, asserted directly.
##
## test_move reports a hit against a walkable ramp just as readily as against a
## wall, so an assist that only asks "am I blocked?" fires on every staircase in
## the game and lifts the player while move_and_slide is already carrying them
## up the slope.
##
## This is asserted at the assist rather than through the resulting motion on
## purpose: at the speeds and slopes the game currently uses the duplicated
## climb is smaller than floor_snap_length and gets quietly snapped back out, so
## a behavioural test of the ramp passes either way. It stops being invisible
## once the lift exceeds the snap distance, which a faster stance or a steeper
## staircase would manage, and by then it is a launch ramp.
func test_movement_the_step_assist_ignores_a_walkable_slope() -> void:
	# Arrange: on the ramp, walking up it.
	if not _settle_on_the_ramp():
		return
	_player.velocity = Vector3(0.0, 0.0, -_player.move_speed)
	var before := _player.global_position.y

	# Act
	_player._try_step_up(TICK)

	# Assert
	var lifted := _player.global_position.y - before
	if lifted > 0.0:
		_failures.append(
			"the step assist lifted the player %.4fm on a %.0f degree slope, "
			% [lifted, RAMP_DEGREES] + "which move_and_slide already climbs"
		)
	else:
		print("PASS: the step assist leaves walkable slopes to move_and_slide")

	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3.ZERO


## That a ramp is climbed at the rate its slope gives, and with both feet down
## the whole way. The assist is off here — this is the baseline it must not
## disturb.
func test_movement_walks_up_a_ramp_at_the_slope_it_is() -> void:
	# Arrange: standing on the low end of the ramp, facing up it.
	if not _settle_on_the_ramp():
		return
	var start := _player.global_position

	# Act
	var left_the_ground := false
	for _tick in MAX_TICKS:
		_player.velocity.z = -_player.move_speed
		_step_physics()
		if not _player.is_on_floor():
			left_the_ground = true
		if absf(_player.global_position.z - start.z) > 2.0:
			break

	# Assert: the rise should match the ramp, not double it.
	var travelled: float = absf(_player.global_position.z - start.z)
	var expected: float = travelled * tan(deg_to_rad(RAMP_DEGREES))
	var risen: float = _player.global_position.y - start.y

	if left_the_ground:
		_failures.append("walking up a %.0f degree ramp threw the player off it" % RAMP_DEGREES)
	elif travelled < 0.5:
		_failures.append("the player did not get up the ramp at all")
	elif risen > expected + 0.2:
		_failures.append(
			"climbing %.2fm of ramp raised the player %.2fm, not the %.2fm the slope gives"
			% [travelled, risen, expected]
		)
	elif risen < expected * 0.8:
		# The opposite failure: an assist that refuses to fire is fine on a
		# ramp, but a ramp the player cannot get up at all is not.
		_failures.append(
			"climbing %.2fm of ramp only raised the player %.2fm of an expected %.2fm"
			% [travelled, risen, expected]
		)
	else:
		print(
			"PASS: a %.0f degree ramp raises the player %.2fm over %.2fm, feet down throughout"
			% [RAMP_DEGREES, risen, travelled]
		)

	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3.ZERO


## "Do not make movement feel floaty" is the one requirement in this phase with
## no natural home in the code, so it gets pinned to numbers here. A jump is
## ballistic, so its apex height and hang time follow from gravity and the
## launch speed alone.
func test_movement_jump_is_not_floaty() -> void:
	# Arrange
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)

	# Act
	var apex_height: float = (_player.jump_velocity * _player.jump_velocity) / (2.0 * gravity)
	var hang_time: float = 2.0 * _player.jump_velocity / gravity

	# Assert
	if hang_time > 0.9:
		_failures.append("a jump hangs for %.2fs, which is moon gravity" % hang_time)
	elif apex_height < 0.7:
		_failures.append(
			"a jump only reaches %.2fm, too low to clear anything" % apex_height
		)
	elif apex_height > 1.8:
		_failures.append("a jump reaches %.2fm, higher than the player is tall" % apex_height)
	else:
		print(
			"PASS: a jump peaks at %.2fm after %.2fs and is over in %.2fs"
			% [apex_height, hang_time * 0.5, hang_time]
		)


## Weight, the same property the zombies are tested for. Assigning velocity
## outright makes a player who starts and stops like a cursor.
func test_movement_reaches_full_speed_over_time_rather_than_at_once() -> void:
	# Arrange
	var target := _player.move_speed

	# Act
	var after_one_tick: float = minf(_player.acceleration * TICK, target)
	var ticks_to_full: float = target / _player.acceleration / TICK

	# Assert
	if after_one_tick >= target * 0.9:
		_failures.append(
			"one tick of acceleration reaches %.2f of %.2f m/s — movement snaps"
			% [after_one_tick, target]
		)
	elif ticks_to_full > 30.0:
		_failures.append(
			"it takes %.0f ticks to reach full speed, which reads as ice" % ticks_to_full
		)
	else:
		print(
			"PASS: full speed arrives after %.0f ticks (%.2fs), not instantly"
			% [ticks_to_full, ticks_to_full * TICK]
		)


## --- Helpers ----------------------------------------------------------------


## One tick of the player's real movement loop, pinned to a fixed 1/60.
##
## Two things here are easy to get wrong and both silently invalidate every
## distance this file measures.
##
## Gravity is applied only while airborne, as the real loop does. Applying it
## on every tick instead drags the player back down every slope, and the climb
## rate the ramp test exists to measure comes out about a third of the truth.
##
## The delta is the harder one. move_and_slide picks its own: the physics delta
## inside a physics frame, the idle delta outside one — and a SceneTree test
## script only ever runs outside one. A headless idle frame is measured rather
## than capped, is not affected by Engine.max_fps, and has been seen here at
## fifty microseconds, at which point move_and_slide advances nothing at all
## and every loop below runs out of iterations having moved a millimetre.
##
## So the velocity handed to it is pre-scaled by TICK/delta. move_and_slide
## multiplies by delta again and moves exactly one sixtieth of a second's worth
## whatever the frame rate, and the result is unscaled on the way back out
## because sliding rewrites it. Floor snapping and the collision margin are
## distances rather than rates, so neither is disturbed.
func _step_physics() -> void:
	var delta := _player.get_process_delta_time()
	if delta <= 0.0:
		return

	_player._try_step_up(TICK)
	if not _player.is_on_floor():
		_player.velocity.y -= GRAVITY * TICK

	var stretch := TICK / delta
	_player.velocity *= stretch
	_player.move_and_slide()
	_player.velocity /= stretch


## Drop the player onto the low end of the test ramp. False if they never
## landed, in which case the caller has nothing worth measuring.
func _settle_on_the_ramp() -> bool:
	_player.global_position = Vector3(-12.0, 1.2, 3.2)
	_player.velocity = Vector3.ZERO

	for _settle in 120:
		_step_physics()
		if _player.is_on_floor():
			return true

	_failures.append("the test never landed the player on the ramp")
	return false


func _speed_in(stance: int) -> float:
	_player._stance = stance
	return _player.current_speed()


func _noise_in(stance: int) -> float:
	_player._stance = stance
	return _player.stance_noise_scale()


func _add_box(centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	# Local rather than global: during _initialize the nodes are not yet
	# considered inside the tree, and global_position silently does nothing
	# there. _world sits at the origin, so the two are the same anyway.
	body.position = centre
	_world.add_child(body)
	return body


func _report() -> void:
	if _failures.is_empty():
		print("movement: all checks passed")
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
