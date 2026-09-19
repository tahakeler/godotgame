class_name Zombie
extends CharacterBody3D

## Pursues the player across the baked navmesh and attacks on contact.
##
## Zombies collide with world geometry only, never with each other or the
## player. Letting bodies push each other turns a crowd into a physics pile-up
## and lets zombies shove the player through the arena, which reads as a bug
## rather than a threat.

signal died(zombie: Zombie, death_position: Vector3)
signal hit_player(damage: float, from_position: Vector3)

@export_group("Movement")
@export var move_speed := 3.2
@export var turn_speed := 9.0
## How often the navigation target is refreshed. Every frame is wasteful and
## produces no visible improvement at this speed.
@export var repath_interval := 0.15

@export_group("Combat")
@export var contact_damage := 12.0
@export var attack_range := 1.9
@export var attack_cooldown := 1.1

@export_group("Feel")
@export var hit_flash_duration := 0.09

var _target: Node3D
var _attack_remaining := 0.0
var _repath_remaining := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _flash_remaining := 0.0

@onready var health: Health = $Health
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: Node3D = $Visual
@onready var _body_meshes: Array[MeshInstance3D] = [$Visual/Torso, $Visual/Head]

var _normal_material: Material
var _flash_material: StandardMaterial3D


func _ready() -> void:
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = attack_range * 0.7

	_normal_material = _body_meshes[0].get_surface_override_material(0)
	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color(1.0, 0.85, 0.85)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1.0, 0.35, 0.3)
	_flash_material.emission_energy_multiplier = 3.0


func _physics_process(delta: float) -> void:
	_attack_remaining = maxf(0.0, _attack_remaining - delta)
	_tick_flash(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if _target == null or health.is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_tick_repath(delta)
	_move_toward_target(delta)
	_try_attack()

	move_and_slide()


## Assign the node this zombie hunts. Called by the spawner.
func set_target(target: Node3D) -> void:
	_target = target
	if is_inside_tree() and target != null:
		_agent.target_position = target.global_position


## Damage entry point used by the weapon's raycast.
func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO,
		_direction: Vector3 = Vector3.ZERO) -> float:
	return health.take_damage(amount)


func _tick_repath(delta: float) -> void:
	_repath_remaining -= delta
	if _repath_remaining > 0.0:
		return

	_repath_remaining = repath_interval
	_agent.target_position = _target.global_position


func _move_toward_target(delta: float) -> void:
	var next_position := _agent.get_next_path_position()
	var to_next := next_position - global_position
	to_next.y = 0.0

	if to_next.length() < 0.05:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var direction := to_next.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	# Face travel direction. Interpolated so zombies do not snap around when
	# the path bends around a crate.
	var desired_yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, turn_speed * delta)


func _try_attack() -> void:
	if _attack_remaining > 0.0:
		return

	var distance := global_position.distance_to(_target.global_position)
	if distance > attack_range:
		return

	_attack_remaining = attack_cooldown
	hit_player.emit(contact_damage, global_position)

	if _target.has_method("take_damage"):
		_target.take_damage(contact_damage, global_position, Vector3.ZERO)


func _tick_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return

	_flash_remaining -= delta
	if _flash_remaining <= 0.0:
		for mesh in _body_meshes:
			mesh.set_surface_override_material(0, _normal_material)


func _on_damaged(_amount: float, _current: float, _maximum: float) -> void:
	_flash_remaining = hit_flash_duration
	for mesh in _body_meshes:
		mesh.set_surface_override_material(0, _flash_material)


func _on_died() -> void:
	died.emit(self, global_position)

	# Stop participating in the fight immediately; the node is freed by the
	# spawner after the death signal is handled.
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	queue_free()
