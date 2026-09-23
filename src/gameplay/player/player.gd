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

@export_group("Landing")
## Fall speed below which a landing is not worth feeling, in metres per second.
##
## Stepping off a ledge and walking down a ramp both land at some speed, and a
## dip on every one of those reads as a camera that cannot keep still.
@export var landing_speed_floor := 4.5
## Fall speed at which the landing dip is at full depth.
@export var landing_speed_full := 13.0
## How far the view drops at full depth, in metres.
@export var landing_dip := 0.16
## How quickly the view falls into the dip and rises back out of it.
@export var landing_fall_speed := 3.4
@export var landing_recover_speed := 1.9
## Camera shake added by a landing at full depth. Small: a landing is a thud
## underfoot, not an explosion, and the drop is doing most of the work.
@export var landing_trauma := 0.22

@export_group("Lean")
## How far the view rolls into a sideways move, in degrees.
##
## Deliberately small. Enough that strafing has a direction rather than being a
## slide, not so much that the horizon becomes something the player is fighting.
@export var lean_degrees := 1.3
## How quickly the roll follows the input, and returns when it stops.
@export var lean_speed := 7.0

@export_group("Hit flinch")
## How far the view is shoved sideways/back at full strength, in metres. Small
## on purpose — this reads as a shove, not a stagger the player has to fight.
@export var flinch_distance := 0.06
## How far the view rolls to match the shove, in degrees. Composed into the
## same head.rotation.z assignment _tick_lean already owns, not a second write.
@export var flinch_roll_degrees := 2.5
## How quickly the view reaches the shoved position — fast, so it reads as an
## impact rather than a lean.
@export var flinch_out_speed := 0.6
## How quickly the view settles back afterwards — slower than the shove out,
## so the return does not itself read as a second hit.
@export var flinch_recover_speed := 0.17
## Damage at which the flinch reaches full strength. A Brute's claw is close
## to this; a Shambler's graze is a fraction of it.
@export var flinch_full_damage := 35.0

@export_group("Camera shake")
@export var shake_decay := 2.4
@export var shake_frequency := 26.0
@export var shake_yaw := 0.035
@export var shake_roll := 0.05
@export var shake_offset := 0.06
## Fraction of the authored shake actually applied, from the accessibility
## settings. Zero disables camera shake completely.
var shake_scale := 1.0

@export_group("Death")
## How long the collapse takes from the killing blow to fully down, in
## seconds.
@export var death_duration := 0.9
## Eye height once the collapse finishes, in metres. Near the floor rather
## than flat on it, so the last frame still reads as a body coming to rest
## instead of the camera clipping into the ground.
@export var death_eye_height := 0.35
## How far the view has rolled to one side by the time the collapse
## finishes, in degrees.
@export var death_roll_degrees := 70.0
## Fraction of the collapse's timeline spent on the initial knee-buckle,
## before the slower body-fall takes over.
@export_range(0.0, 1.0) var death_knee_fraction := 0.15
## Fraction of the total drop covered during that initial knee-buckle, so the
## first visible motion reads as the knees giving out rather than the whole
## body already sinking.
@export_range(0.0, 1.0) var death_knee_depth_fraction := 0.35
## Camera shake added the instant death starts — the same kind of jolt a hard
## landing gives, scaled up for a body giving out entirely. Routed through
## add_trauma(), same as landing_trauma, so a player who turned shake off
## does not get shaken by this either.
@export var death_trauma := 0.35

@export_group("Head bob")
## How far the view dips vertically per step at a walk, in metres. Kept small
## on purpose — the weapon viewmodel already carries its own bob (see
## weapon.gd bob_amount), and two big bobs stacked together reads as seasick.
@export var head_bob_height := 0.012
## How far the view sways sideways per step, in metres. Smaller than the
## vertical dip, so the sway reads as weight shifting underfoot rather than a
## second beat competing with the footstep rhythm.
@export var head_bob_side := 0.006
## Amplitude multiplier while crouched, on top of the speed-based scale
## below. A crouching player is placing each foot deliberately, not striding.
@export var head_bob_crouch_scale := 0.5
## Horizontal speed at which the bob reaches its authored size. Sprint speed
## sits above this, so sprinting still overshoots to a bigger bob rather than
## capping out at the same size as a walk.
@export var head_bob_reference_speed := 4.5
## How quickly bob amplitude chases its speed-based target, so starting or
## stopping a stride fades the bob in and out instead of snapping the camera
## level the instant the player releases a movement key.
@export var head_bob_ease := 8.0

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
## Current landing drop, in metres, composed into the stance eye height.
var _landing_offset := 0.0
var _landing_target := 0.0
## Directional hit flinch, in the head's local x/z plane: x is sideways, y
## (despite the name) stands in for local z, forward/back. head.position.x
## and head.position.z have no other writer, which is what makes this safe.
var _flinch := Vector2.ZERO
var _flinch_target := Vector2.ZERO
## Head bob amplitude, eased toward a speed-based target every frame rather
## than snapping — see _tick_head_bob. _bob_vertical and _bob_side are the
## per-frame offsets composed into head.position.y (_tick_eye_height) and
## head.position.x (_tick_flinch), the two functions that already own those
## axes. _step_sign flips on every footstep (in _tick_footsteps) so the
## sideways sway alternates left/right instead of swaying the same way twice
## in a row.
var _bob_amplitude := 0.0
var _bob_vertical := 0.0
var _bob_side := 0.0
var _step_sign := 1.0
## The lean must lerp from its own value, not from the composed
## head.rotation.z — anything else composed onto that axis (the flinch roll)
## would otherwise feed back into the lean's source every frame and linger.
var _lean_roll := 0.0
## Whether the player was on the floor last frame, and how fast they were
## falling before they touched it. Sampled before move_and_slide, because that
## is the call that zeroes the downward velocity on contact.
var _was_on_floor := true
var _fall_speed := 0.0
## Shake builds up from events and decays continuously. Squaring it on use
## means small knocks stay subtle while a burst of hits reads as violent.
var _trauma := 0.0
var _shake_time := 0.0
var _stance: int = Stance.WALKING
## Eye height is eased rather than snapped, so dropping into a crouch reads as
## the body moving instead of the camera teleporting.
var _eye_height := 0.0
var _base_fov := 0.0
## True from the moment health reaches zero. Gates _tick_death and tells
## _tick_head_bob / _tick_lean to stop reacting to residual velocity or
## input, so a corpse does not keep wobbling on whatever motion it had at the
## instant it died.
var _dying := false
var _death_time := 0.0
## Composed into head.position.y by _tick_eye_height, the axis's one writer.
var _death_drop := 0.0
## Composed into head.rotation.z by _tick_lean, the axis's one writer.
var _death_roll := 0.0
## Which way the collapse rolls, captured once at the moment of death from
## whichever side the last hit had already shoved the view toward — a body
## drops toward the side it was leaning, not a fixed direction chosen ahead
## of time.
var _death_roll_sign := 1.0

## The ZombieTypes.Kind of whichever zombie most recently landed contact,
## or -1 when nothing has. Kept separate from take_damage() rather than added
## as a parameter there: take_damage() is also called by non-zombie sources
## (and its signature is depended on by other callers), so attribution is
## recorded as its own step immediately before the damage call instead of
## widening a shared entry point for one caller's bookkeeping.
var last_attacker_kind := -1


func _ready() -> void:
	_spawn_transform = global_transform
	_base_fov = camera.fov
	_eye_height = stand_eye_height
	head.position.y = stand_eye_height
	_apply_collider_height(stand_height)
	health.died.connect(_on_health_died)
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

	var bearing := get_angle_to_source(from_position)
	damage_taken.emit(applied, bearing)

	# Scaled by the accessibility shake setting at the point of entry, same as
	# add_trauma below — a player who turned shake off has said they do not
	# want the view shoved either, not just that they do not want it shaken.
	var strength := clampf(applied / flinch_full_damage, 0.0, 1.0) * shake_scale
	_flinch_target = Vector2(-sin(bearing), cos(bearing)) * flinch_distance * strength

	return applied


## Records which zombie kind is about to land a hit, for the STATS screen's
## "killed by" breakdown. Called by the attacker immediately before its own
## take_damage() call rather than folded into take_damage() itself, since
## take_damage() is a shared entry point other, non-zombie sources also call
## and its signature must not change for them.
func note_attacker(kind: int) -> void:
	last_attacker_kind = kind


## Starts the death collapse (see _tick_death) and forwards the Health
## component's signal on as the player's own died signal, which is what the
## round manager and HUD actually listen for.
func _on_health_died() -> void:
	_dying = true
	_death_time = 0.0
	_death_roll_sign = -1.0 if _flinch.x < 0.0 else 1.0
	add_trauma(death_trauma)
	died.emit()


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
		_apply_look(_look_delta(event))

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

	# Taken here rather than in _unhandled_input so it is ignored while a menu
	# has focus, which is the same rule the weapon follows.
	if _look_enabled and Input.is_action_just_pressed("flashlight"):
		flashlight.toggle()


func _physics_process(delta: float) -> void:
	# Runs first: _tick_stance (below) calls _tick_eye_height, which composes
	# _death_drop into head.position.y this same frame, so the collapse has to
	# be current before that read rather than a frame behind it.
	_tick_death(delta)

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

	# Sampled before the move: move_and_slide zeroes the downward velocity the
	# moment the floor is touched, so afterwards there is nothing left to say
	# how hard the landing was.
	_fall_speed = maxf(0.0, -velocity.y)

	move_and_slide()
	_tick_landing(delta)
	_tick_lean(input_vector, delta)
	_tick_flinch(delta)
	_tick_head_bob(delta)
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
		_step_sign = -_step_sign
		footstep_taken.emit()


## How far a pointing device moved, in physical screen pixels.
##
## `screen_relative`, not `relative`. This project stretches its canvas
## (`window/stretch/mode="canvas_items"` against a 1920x1080 base), and Godot
## divides `relative` by that stretch scale before the event arrives — so the
## same physical swipe turns the camera a different amount depending on how big
## the window is. Fullscreen on a Retina MacBook is the worst case: the scale
## there is around 1.6, so `relative` reports roughly two thirds of the motion
## the hand actually made, and the trackpad feels sluggish in fullscreen and
## fine in a window while nothing about the trackpad has changed. That is the
## kind of bug that gets blamed on the device.
##
## `screen_relative` is unscaled physical pixels, so `mouse_sensitivity` means
## the same thing on every display and in every window size. It exists from
## Godot 4.3 onward, which this project is well past.
##
## Falls back to `relative` when `screen_relative` is empty, because a
## synthesised event — `Input.parse_input_event` in the headless tests, or any
## remapper — may fill only one of the two, and dropping that motion would be a
## camera that does not turn. A real macOS trackpad fills both.
func _look_delta(event: InputEventMouseMotion) -> Vector2:
	if not event.screen_relative.is_zero_approx():
		return event.screen_relative
	return event.relative


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


## Set the resting field of view in degrees.
##
## Sprint widens the view from this figure rather than from a constant, so the
## sprint bonus keeps working at any player-chosen FOV. Applied to the camera
## immediately unless the sprint stretch is mid-flight, in which case the next
## frame's ease carries it there instead of snapping.
func set_base_fov(degrees: float) -> void:
	_base_fov = degrees
	if _stance != Stance.SPRINTING:
		camera.fov = degrees


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
	_flinch = Vector2.ZERO
	_flinch_target = Vector2.ZERO
	_lean_roll = 0.0
	_distance_since_footstep = 0.0
	_bob_amplitude = 0.0
	_bob_vertical = 0.0
	_bob_side = 0.0
	_step_sign = 1.0
	head.position.x = 0.0
	head.position.z = 0.0
	head.rotation.z = 0.0
	# Stand the player back up instantly rather than easing out of the
	# collapse — a restart is a clean slate, not a recovery the player watches.
	_dying = false
	_death_time = 0.0
	_death_drop = 0.0
	_death_roll = 0.0
	_death_roll_sign = 1.0
	_set_stance(Stance.WALKING)
	health.reset()
	last_attacker_kind = -1


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
	# The landing drop, the head bob, and the death collapse are all composed
	# into the stance height rather than written separately, because all four
	# want to own head.position.y and the last writer in a frame would
	# otherwise simply erase the others.
	head.position.y = _eye_height - _landing_offset + _bob_vertical - _death_drop

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


## Drop the view when the player hits the ground, in proportion to the fall.
##
## The weight of a first-person character is almost entirely implied — there is
## no body on screen to land on its feet — so the only thing that says a fall
## had any mass is what the camera does when it stops. Without this a two-storey
## drop and a step off a kerb are the same event.
##
## Falls quickly and recovers slowly, because that asymmetry is what reads as
## absorbing an impact rather than bouncing off one.
func _tick_landing(delta: float) -> void:
	var grounded := is_on_floor()

	if grounded and not _was_on_floor:
		var over := _fall_speed - landing_speed_floor
		if over > 0.0:
			var span := maxf(landing_speed_full - landing_speed_floor, 0.01)
			var depth := clampf(over / span, 0.0, 1.0)
			_landing_target = landing_dip * depth
			# Routed through add_trauma so the accessibility shake setting
			# applies to it like everything else — a player who turned shake
			# off has said they do not want the camera shaken by impacts.
			add_trauma(landing_trauma * depth)

	_was_on_floor = grounded

	# Toward the dip fast, back out of it slowly.
	if _landing_offset < _landing_target:
		_landing_offset = move_toward(
			_landing_offset, _landing_target, landing_fall_speed * delta
		)
		if is_equal_approx(_landing_offset, _landing_target):
			_landing_target = 0.0
	else:
		_landing_offset = move_toward(
			_landing_offset, 0.0, landing_recover_speed * delta
		)
		_landing_target = 0.0


## Collapse the view on death: knees buckle first in a quick partial drop,
## then the rest of the fall eases out so the view lands rather than slides
## to a stop. Composes into head.position.y (_tick_eye_height) and
## head.rotation.z (_tick_lean), the two axes that already own those writes.
func _tick_death(delta: float) -> void:
	if not _dying:
		return

	_death_time = minf(_death_time + delta, death_duration)
	var t := _death_time / maxf(death_duration, 0.001)
	var progress := _death_collapse_progress(t)

	# Drop relative to the eye height the player actually had, not always
	# standing height — stance input is disabled on death so _eye_height holds
	# still, but a player who died crouched (_eye_height == crouch_eye_height,
	# 1.05) has less distance to fall than a standing one, and computing this
	# against stand_eye_height unconditionally put the crouched case's camera
	# under the floor. Clamped at zero for the same reason: death_eye_height
	# (0.35) sits below crouch_eye_height, but nothing here guarantees that
	# ordering stays true if either is retuned.
	_death_drop = progress * maxf(_eye_height - death_eye_height, 0.0)
	_death_roll = progress * deg_to_rad(death_roll_degrees) * _death_roll_sign


## 0..1 collapse progress for a given 0..1 point in the death timeline.
##
## Two eased phases chained on one timeline rather than a single ease-out for
## the whole duration, because one curve reads as gentle from the very first
## frame — this needs the opening instant to read as a knee giving out, and
## only then the slower, heavier fall that finishes by easing to a stop
## instead of sliding into it.
func _death_collapse_progress(t: float) -> float:
	var knee_span := maxf(death_knee_fraction, 0.001)
	if t <= death_knee_fraction:
		var knee_t := t / knee_span
		return death_knee_depth_fraction * (1.0 - pow(1.0 - knee_t, 2.0))

	var rest_span := maxf(1.0 - death_knee_fraction, 0.001)
	var rest_t := (t - death_knee_fraction) / rest_span
	var rest_ease := 1.0 - pow(1.0 - rest_t, 3.0)
	return death_knee_depth_fraction + (1.0 - death_knee_depth_fraction) * rest_ease


## Roll the view into a sideways move.
##
## On the head rather than on the camera, deliberately. _tick_shake owns the
## camera's roll and zeroes it whenever trauma runs out, so a lean written
## there would be erased every time the player stopped being shot at — the same
## trap that comment warns about for pitch. Two nodes, one writer each, and the
## two rotations compose on their own.
func _tick_lean(input_vector: Vector2, delta: float) -> void:
	var wanted := 0.0

	# Only while actually moving under power, and never while dying — input is
	# disabled on death, but velocity can still be non-zero for a moment, and a
	# corpse leaning into that reads as a bug, not a collapse.
	if not _dying and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.6:
		wanted = -input_vector.x * deg_to_rad(lean_degrees)

	_lean_roll = lerpf(_lean_roll, wanted, clampf(lean_speed * delta, 0.0, 1.0))

	# The flinch's roll and the death roll both ride on top of the lean rather
	# than through a second write to head.rotation.z — _tick_lean is the one
	# place that axis is assigned, so every effect has to leave through this
	# single line.
	var flinch_roll := -_flinch.x / maxf(flinch_distance, 0.001) * deg_to_rad(flinch_roll_degrees)
	head.rotation.z = _lean_roll + flinch_roll + _death_roll


## Knock the view away from a hit, then settle it back.
##
## head.position.z has no other writer, which is what makes it safe to push
## here — unlike the axes _tick_shake, _tick_lean and _tick_eye_height already
## own, where a second write would just fight the first one every frame.
## head.position.x is shared with the head bob's sideways sway; the two are
## composed together in the assignment below rather than each writing on its
## own, for the same reason. take_damage sets _flinch_target the instant a
## hit lands; this only ever chases that target and, once caught, chases zero.
func _tick_flinch(delta: float) -> void:
	# A live (non-zero) target means the shove is still outbound; once it is
	# reached the target drops to zero and every later call is the recovery
	# leg, which is what lets one move_toward serve both speeds.
	var chasing_shove := not _flinch_target.is_zero_approx()
	var speed := flinch_out_speed if chasing_shove else flinch_recover_speed
	_flinch = _flinch.move_toward(_flinch_target, speed * delta)

	if chasing_shove and _flinch.is_equal_approx(_flinch_target):
		_flinch_target = Vector2.ZERO

	head.position.x = _flinch.x + _bob_side
	head.position.z = _flinch.y


## Head bob rides the same distance accumulator the footstep sound uses
## (_distance_since_footstep) instead of running its own timer, so the bob
## can never drift apart from the footfall it is supposed to land on. Runs
## before _tick_footsteps in _physics_process, so phase is one frame behind
## the distance travelled this tick — the same lag _tick_eye_height already
## accepts from _landing_offset, and just as imperceptible here.
func _tick_head_bob(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var stance_scale := head_bob_crouch_scale if _stance == Stance.CROUCHING else 1.0

	var target := 0.0
	# A dying body can still be sliding on residual velocity for a moment;
	# without the _dying check the bob would keep reading footsteps off a
	# corpse instead of easing out with the rest of the collapse.
	if is_on_floor() and not _dying:
		target = clampf(horizontal_speed / head_bob_reference_speed, 0.0, 1.4)
	target *= stance_scale * shake_scale

	# Eased rather than snapped, so releasing the move key fades the bob out
	# instead of the camera jumping back to level mid-stride.
	_bob_amplitude = lerpf(_bob_amplitude, target, clampf(head_bob_ease * delta, 0.0, 1.0))

	# 0..1 across one footstep, resetting to 0 exactly when the accumulator
	# wraps — the same instant the footstep sound fires.
	var phase := _distance_since_footstep / maxf(footstep_distance, 0.001)
	# cos(phase * TAU) is +1 at phase 0 and 1 (the footfall) and -1 at phase
	# 0.5 (mid-stride), so negating it puts the dip — the low point — right
	# on the footfall, which is the whole point of driving this off the
	# footstep accumulator rather than an independent timer.
	_bob_vertical = -head_bob_height * _bob_amplitude * cos(phase * TAU)
	# Half that frequency, and sign-flipped by _tick_footsteps on every
	# footfall, so the sway crosses centre on each step and alternates which
	# way it leans instead of swaying the same direction twice in a row.
	_bob_side = head_bob_side * _bob_amplitude * _step_sign * sin(phase * PI)
