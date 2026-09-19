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
## Relative mouse movement, so the viewmodel can lag behind the look.
signal look_moved(relative: Vector2)

@export_group("Movement")
@export var move_speed := 6.5
@export var acceleration := 60.0
@export var friction := 70.0
@export var jump_velocity := 6.5
## Fraction of normal acceleration available while airborne.
@export_range(0.0, 1.0) var air_control := 0.25
## Distance travelled between footstep sounds.
@export var footstep_distance := 2.1

@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var pitch_limit_degrees := 89.0
@export var invert_look_y := false

@export_group("Camera shake")
@export var shake_decay := 2.4
@export var shake_frequency := 26.0
@export var shake_yaw := 0.035
@export var shake_roll := 0.05
@export var shake_offset := 0.06

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var health: Health = $Health

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _look_enabled := true
var _spawn_transform: Transform3D
var _distance_since_footstep := 0.0
## Shake builds up from events and decays continuously. Squaring it on use
## means small knocks stay subtle while a burst of hits reads as violent.
var _trauma := 0.0
var _shake_time := 0.0


func _ready() -> void:
	_spawn_transform = global_transform
	health.died.connect(func() -> void: died.emit())
	capture_mouse()


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
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


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
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_apply_look(event.relative)

	elif event is InputEventMouseButton and event.pressed:
		# Clicking back into the window re-captures, so the player does not have
		# to hunt for a key after alt-tabbing.
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE and _look_enabled:
			capture_mouse()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_vector := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	var control := 1.0 if is_on_floor() else air_control
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if direction.is_zero_approx():
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * control * delta)
	else:
		horizontal = horizontal.move_toward(
			direction * move_speed, acceleration * control * delta
		)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

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
	rotate_y(-relative.x * mouse_sensitivity)

	var pitch_delta := -relative.y * mouse_sensitivity
	if invert_look_y:
		pitch_delta = -pitch_delta

	var limit := deg_to_rad(pitch_limit_degrees)
	head.rotation.x = clampf(head.rotation.x + pitch_delta, -limit, limit)


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
	health.reset()
