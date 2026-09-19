class_name Player
extends CharacterBody3D

## First-person controller. Owns movement, look, and mouse capture only —
## health and the weapon are separate components so each can be tested and
## tuned on its own.

signal look_sensitivity_changed(value: float)

@export_group("Movement")
@export var move_speed := 6.5
@export var acceleration := 60.0
@export var friction := 70.0
@export var jump_velocity := 6.5
## Fraction of normal acceleration available while airborne.
@export_range(0.0, 1.0) var air_control := 0.25

@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var pitch_limit_degrees := 89.0
@export var invert_look_y := false

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _look_enabled := true
var _spawn_transform: Transform3D


func _ready() -> void:
	_spawn_transform = global_transform
	capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _look_enabled:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_apply_look(event.relative)

	elif event.is_action_pressed("ui_release_mouse"):
		release_mouse()

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


## Return the player to their starting position and clear momentum.
func reset_to_spawn() -> void:
	velocity = Vector3.ZERO
	global_transform = _spawn_transform
	head.rotation = Vector3.ZERO
