class_name Player
extends CharacterBody3D

## First-person controller. Movement, look, and mouse capture live here; health
## is a separate Health component and the weapon is a separate node, so each can
## be tested and tuned on its own.
##
## FEATURE 1 — Player Health.
## Implements design/gdd/game-concept.md "Feature 1 — Player Health".
##
##   Trigger:      zombie contact calls take_damage()
##   State change: Health.current_health decrements
##   Result:       damage_taken drives the HUD health bar and the directional
##                 damage indicator; reaching zero emits died, ending the round

signal look_sensitivity_changed(value: float)
## `direction_angle` is radians relative to where the player is looking:
## 0 is dead ahead, positive is to the right, +/-PI is directly behind.
signal damage_taken(amount: float, direction_angle: float)
signal died()
signal footstep_taken()
## Carries a Stance value. Typed as int because the enum is declared below the
## signals, and GDScript resolves a signal's argument types at parse time.
signal stance_changed(stance: int)
## Relative mouse movement, so the viewmodel can lag behind the look.
signal look_moved(relative: Vector2)

## How the player is carrying themselves. Not a modifier on speed but a choice
## with three consequences at once — how fast you are, how loud you are, and how
## tall you are — which is what makes it a decision rather than a comfort key.
enum Stance { WALKING, SPRINTING, CROUCHING }

@export_group("Movement")
## Base walking speed. Every other stance is a multiple of this, so the
## progression perk that raises it raises all three together.
@export var move_speed := 4.6
@export var sprint_multiplier := 1.55
@export var crouch_multiplier := 0.48
@export var acceleration := 60.0
@export var friction := 70.0
@export var jump_velocity := 6.5
## Fraction of normal acceleration available while airborne.
@export_range(0.0, 1.0) var air_control := 0.25
## Distance travelled between footstep sounds.
@export var footstep_distance := 2.1
## Tallest lip the player walks over instead of stopping dead against.
@export var step_height := 0.45

@export_group("Stance")
@export var stand_height := 1.8
@export var crouch_height := 1.15
@export var stand_eye_height := 1.6
@export var crouch_eye_height := 1.05
## How quickly the view drops and rises between stances, in metres per second.
@export var stance_ease_speed := 7.0
## Noise made per footstep, relative to a walk. Crouching is the quietest thing
## a player can do while still moving; sprinting is close to a gunshot.
@export var crouch_noise_scale := 0.3
@export var sprint_noise_scale := 2.0
## Sprinting widens the view a little. Nothing else in the game changes FOV, so
## this reads purely as speed rather than as a competing effect.
@export var sprint_fov_bonus := 7.0

@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var pitch_limit_degrees := 89.0
@export var invert_look_y := false

@export_group("Gamepad")
## Turn rate in radians per second at full stick deflection.
@export var gamepad_sensitivity := 2.7
@export_range(0.0, 0.9) var gamepad_deadzone := 0.18
## Exponent applied to stick deflection before it becomes a turn rate.
##
## A stick mapped straight to turn rate is either too slow to spin round when
## something bites you from behind or too twitchy to hold an aim. Curving it
## gives fine control near the centre and full speed at the edge, which is why
## every shooter that plays well on a pad does this.
@export var gamepad_response_curve := 2.4

@export_group("Camera shake")
@export var shake_decay := 2.4
@export var shake_frequency := 26.0
@export var shake_yaw := 0.035
@export var shake_roll := 0.05
@export var shake_offset := 0.06
## Fraction of the authored shake actually applied, from the accessibility
## settings. Zero disables camera shake completely.
var shake_scale := 1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var health: Health = $Health
@onready var flashlight: Flashlight = $Head/Camera/Flashlight
@onready var interactor: Interactor = $Interactor
@onready var _collider: CollisionShape3D = $CollisionShape3D
@onready var _body_mesh: MeshInstance3D = $Body

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _look_enabled := true
var _spawn_transform: Transform3D
var _distance_since_footstep := 0.0
## Shake builds up from events and decays continuously. Squaring it on use
## means small knocks stay subtle while a burst of hits reads as violent.
var _trauma := 0.0
var _shake_time := 0.0
var _stance: int = Stance.WALKING
## Eye height is eased rather than snapped, so dropping into a crouch reads as
## the body moving instead of the camera teleporting.
var _eye_height := 0.0
var _base_fov := 0.0


func _ready() -> void:
	_spawn_transform = global_transform
	_base_fov = camera.fov
	_eye_height = stand_eye_height
	head.position.y = stand_eye_height
	_apply_collider_height(stand_height)
	health.died.connect(func() -> void: died.emit())
	capture_mouse()


## How easy the player currently is to see, as a multiplier on a looker's sight
## range. Above 1.0 while the torch is lit.
##
## Exposed on the player rather than only on the flashlight so that anything
## hunting by sight asks one question of one object, and future sources of
## visibility — a flare, a muzzle flash, standing in a lit chamber — can be
## folded in here without every zombie learning about each of them.
func visibility_scale() -> float:
	return flashlight.visibility_scale()


## Damage entry point used by zombies on contact. Returns the amount actually
## absorbed — zero while the player is inside their invulnerability window,
## which stops a surrounding crowd from deleting a full health bar in one second.
func take_damage(amount: float, from_position := Vector3.ZERO,
		_direction := Vector3.ZERO) -> float:
	var applied := health.take_damage(amount)
	if applied <= 0.0:
		return 0.0

	damage_taken.emit(applied, get_angle_to_source(from_position))
	return applied


## Add camera shake. 0.2 is a gunshot, 0.6 is being hit.
##
## Scaled by the player's accessibility setting at the point of entry rather
## than inside _tick_shake, so a setting of zero adds nothing at all and the
## shake system stays entirely idle instead of running against a zero
## multiplier every frame.
func add_trauma(amount: float) -> void:
	var scaled := amount * shake_scale
	if scaled <= 0.0:
		return

	_trauma = clampf(_trauma + scaled, 0.0, 1.0)


## Shake is applied to the camera's yaw, roll and position — never its pitch,
## which the weapon already drives for recoil. Two systems writing the same
## axis fight each other and the result reads as stutter rather than impact.
func _tick_shake(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - shake_decay * delta)

	if is_zero_approx(_trauma):
		camera.position = Vector3.ZERO
		camera.rotation.z = 0.0
		return

	_shake_time += delta * shake_frequency
	var strength := _trauma * _trauma

	camera.rotation.y = sin(_shake_time * 1.7) * strength * shake_yaw
	camera.rotation.z = sin(_shake_time * 2.3) * strength * shake_roll
	camera.position = Vector3(
		sin(_shake_time * 3.1) * strength * shake_offset,
		cos(_shake_time * 2.7) * strength * shake_offset,
		0.0
	)


## Bearing of a world position relative to where the player is facing.
func get_angle_to_source(world_position: Vector3) -> float:
	var to_source := world_position - global_position
	to_source.y = 0.0

	if to_source.is_zero_approx():
		return 0.0

	var local := global_transform.basis.inverse() * to_source
	return atan2(local.x, -local.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _look_enabled:
		# Deliberately not gated on the mouse being captured. It used to be, and
		# that turned any failure to capture into a camera that could not turn
		# at all — which is what happened on a macOS trackpad in fullscreen.
		# Capture stops the cursor escaping the window; it is not what makes
		# looking work, and treating it as a precondition made a cosmetic
		# problem into an unplayable one.
		_apply_look(event.relative)

	elif event is InputEventMouseButton and event.pressed:
		# Clicking back into the window re-captures, so the player does not have
		# to hunt for a key after alt-tabbing.
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and _look_enabled:
			capture_mouse()


## macOS in particular can hand focus back without the capture surviving, and a
## player who alt-tabbed out would return to a view that no longer turns.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN and _look_enabled:
		capture_mouse()


## Stick look runs on the render frame rather than the physics tick, so turning
## stays smooth on a display faster than the physics rate. Rotation is safe to
## change here — unlike velocity, nothing integrates it.
func _process(delta: float) -> void:
	_tick_gamepad_look(delta)

	# Taken here rather than in _unhandled_input so it is ignored while a menu
	# has focus, which is the same rule the weapon follows.
	if _look_enabled and Input.is_action_just_pressed("flashlight"):
		flashlight.toggle()


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	_tick_stance(input_vector, delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and _stance != Stance.CROUCHING:
		# A crouched player cannot jump. Allowing it would mean either popping
		# up into a ceiling or springing out of the one stance that exists to
		# keep you unnoticed — and since crouch is held rather than toggled,
		# letting go and jumping is already a single motion.
		velocity.y = jump_velocity

	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	var control := 1.0 if is_on_floor() else air_control
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if direction.is_zero_approx():
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * control * delta)
	else:
		horizontal = horizontal.move_toward(
			direction * current_speed(), acceleration * control * delta
		)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	_try_step_up(delta)
	move_and_slide()
	_tick_footsteps(delta)
	_tick_shake(delta)


## Footsteps are driven by distance covered rather than a timer, so the rhythm
## follows actual movement instead of running while the player is against a wall.
func _tick_footsteps(delta: float) -> void:
	if not is_on_floor():
		return

	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.6:
		return

	_distance_since_footstep += speed * delta
	if _distance_since_footstep >= footstep_distance:
		_distance_since_footstep = 0.0
		footstep_taken.emit()


## Point the camera using a relative mouse delta.
func _apply_look(relative: Vector2) -> void:
	_apply_look_radians(
		-relative.x * mouse_sensitivity, -relative.y * mouse_sensitivity
	)
	look_moved.emit(relative)


## Turn the player by an angular delta, in radians.
##
## Both input paths end here: the mouse converts pixels into radians with its
## sensitivity, the stick produces a turn rate directly. Sharing one function
## means the pitch clamp and the invert setting cannot drift apart between the
## two devices.
func _apply_look_radians(yaw: float, pitch: float) -> void:
	rotate_y(yaw)

	if invert_look_y:
		pitch = -pitch

	var limit := deg_to_rad(pitch_limit_degrees)
	head.rotation.x = clampf(head.rotation.x + pitch, -limit, limit)


## Turn using the right stick.
##
## Run per frame rather than per input event: a held stick reports a position,
## not a stream of deltas, so there is no event to drive it. That position is a
## rate, which is what makes the delta scaling below necessary — without it the
## turn speed would depend on the frame rate.
func _tick_gamepad_look(delta: float) -> void:
	if not _look_enabled:
		return

	var stick := Input.get_vector(
		"look_left", "look_right", "look_up", "look_down", gamepad_deadzone
	)

	var deflection := stick.length()
	if is_zero_approx(deflection):
		return

	# Curve the magnitude, not each axis. Curving the axes separately bends a
	# diagonal push toward the nearest cardinal, and the aim feels like it
	# snaps to eight directions.
	var rate: float = pow(minf(deflection, 1.0), gamepad_response_curve)
	var step := stick.normalized() * rate * gamepad_sensitivity * delta

	_apply_look_radians(-step.x, -step.y)

	# The viewmodel sways from a pixel delta, because the mouse is what
	# normally feeds it. Converting back means an equivalent turn produces an
	# equivalent sway whichever device caused it.
	if mouse_sensitivity > 0.0:
		look_moved.emit(step / mouse_sensitivity)


func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Disable look without releasing the node — used while a menu or the end-of-round
## overlay is showing.
func set_look_enabled(enabled: bool) -> void:
	_look_enabled = enabled
	if enabled:
		capture_mouse()
	else:
		release_mouse()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = value
	look_sensitivity_changed.emit(value)


## Return the player to their starting position, health, and orientation.
func reset_to_spawn() -> void:
	velocity = Vector3.ZERO
	global_transform = _spawn_transform
	head.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.fov = _base_fov
	_eye_height = stand_eye_height
	head.position.y = stand_eye_height
	_set_stance(Stance.WALKING)
	health.reset()


## --- Stance -----------------------------------------------------------------


## The stance the player is currently in, as a Stance value.
func stance() -> int:
	return _stance


## Movement speed for the current stance.
##
## The ladder this produces is the point of the whole system. A Brute moves at
## 2.0 and a crouch at 2.2; a Walker at 3.2 and a walk at 4.6; a Runner at 5.8
## and a sprint at 7.1. Every stance outruns something and is outrun by
## something, so choosing one is a read on what is actually chasing you rather
## than a preference. Holding sprint everywhere is not free either — see
## stance_noise_scale.
func current_speed() -> float:
	match _stance:
		Stance.SPRINTING:
			return move_speed * sprint_multiplier
		Stance.CROUCHING:
			return move_speed * crouch_multiplier
	return move_speed


## Footstep loudness for the current stance, as a multiple of a walking step.
##
## This is the other half of the choice. Zombies hunt by sound, so a sprint
## across an open chamber buys distance by spending position, and a crouch buys
## silence by spending the ability to get away from anything quick.
func stance_noise_scale() -> float:
	match _stance:
		Stance.SPRINTING:
			return sprint_noise_scale
		Stance.CROUCHING:
			return crouch_noise_scale
	return 1.0


## Pick the stance the held keys are asking for, then ease the view into it.
##
## Sprint needs a forward lean as well as the key: sprinting sideways and
## backwards at full speed turns every retreat into a free escape, and the
## danger of turning your back is most of what makes a retreat a decision.
func _tick_stance(input_vector: Vector2, delta: float) -> void:
	var wants_crouch := Input.is_action_pressed("crouch")
	var wants_sprint := (
		Input.is_action_pressed("sprint")
		and is_on_floor()
		and input_vector.y < -0.1
	)

	var next := Stance.WALKING
	if wants_crouch or (_stance == Stance.CROUCHING and not _has_room_to_stand()):
		# Releasing crouch under a low ceiling keeps you crouched rather than
		# pushing your head through the rock.
		next = Stance.CROUCHING
	elif wants_sprint:
		next = Stance.SPRINTING

	if next != _stance:
		_set_stance(next)

	_tick_eye_height(delta)


func _set_stance(next: int) -> void:
	_stance = next
	_apply_collider_height(
		crouch_height if next == Stance.CROUCHING else stand_height
	)
	stance_changed.emit(next)


## Resize the capsule about the player's feet rather than about its centre, so
## crouching lowers the head instead of sinking the body halfway into the floor.
func _apply_collider_height(height: float) -> void:
	var shape := _collider.shape as CapsuleShape3D
	if shape != null:
		shape.height = height
		_collider.position.y = height * 0.5

	var mesh := _body_mesh.mesh as CapsuleMesh
	if mesh != null:
		mesh.height = height
		_body_mesh.position.y = height * 0.5


## Whether the standing capsule would fit where the crouched one is.
##
## Sweeping the crouched capsule upward by the height difference traces exactly
## the volume a standing capsule occupies — the union of where it starts and
## where it ends is the full standing height — so this is an exact answer rather
## than a ray that could thread a gap in an uneven rock ceiling.
func _has_room_to_stand() -> bool:
	var rise := stand_height - crouch_height
	if rise <= 0.0:
		return true

	return not test_move(global_transform, Vector3.UP * rise)


## Ease the camera between stance heights and widen it while sprinting.
func _tick_eye_height(delta: float) -> void:
	var target := (
		crouch_eye_height if _stance == Stance.CROUCHING else stand_eye_height
	)
	_eye_height = move_toward(_eye_height, target, stance_ease_speed * delta)
	head.position.y = _eye_height

	var fov_target := (
		_base_fov + sprint_fov_bonus if _stance == Stance.SPRINTING else _base_fov
	)
	camera.fov = move_toward(camera.fov, fov_target, sprint_fov_bonus * 4.0 * delta)


## Walk over a low lip instead of stopping dead against it.
##
## CharacterBody3D has no step height of its own: anything taller than the
## collision margin is a wall to it. A cave assembled from kit tiles has seams,
## thresholds and loose rock everywhere, and being stopped by a two-centimetre
## edge reads as the level being broken rather than as an obstacle.
##
## Runs before move_and_slide and only ever moves the body vertically. The
## horizontal half of the step is left to move_and_slide, which is what stops a
## successful step from also handing the player a free extra frame of travel.
func _try_step_up(delta: float) -> void:
	if not is_on_floor():
		return

	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	var ahead := KinematicCollision3D.new()
	if motion.is_zero_approx() or not test_move(global_transform, motion, ahead):
		return

	# A walkable slope is not a step. test_move reports a hit against a ramp
	# just as readily as against a wall, so without this the assist fires on
	# every staircase in the game and adds a climb move_and_slide is already
	# making.
	#
	# Today that extra lift is small enough to be swallowed by floor snapping,
	# so removing this line changes nothing you can see — the cost is three
	# wasted shape casts per frame on every slope. It stops being invisible as
	# soon as the lift exceeds floor_snap_length, which a faster stance or a
	# steeper staircase would do, and then the player is thrown off the top.
	if ahead.get_normal().angle_to(Vector3.UP) <= floor_max_angle:
		return

	var lift := Vector3.UP * step_height
	if test_move(global_transform, lift):
		return  # nothing to rise into

	var raised := global_transform.translated(lift)
	if test_move(raised, motion):
		return  # still blocked a step up, so it is a wall and not a step

	# Something has to be underneath, or this is a ledge over a hole.
	var landing := KinematicCollision3D.new()
	if not test_move(raised.translated(motion), -lift, landing):
		return

	if landing.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return  # the top of the step is too steep to have stood on anyway

	var climb := step_height - landing.get_travel().length()
	if climb <= 0.001:
		return

	global_position.y += climb
	velocity.y = maxf(velocity.y, 0.0)
