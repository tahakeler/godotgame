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
signal groaned(groan_position: Vector3)

@export_group("Movement")
@export var move_speed := 3.2
@export var turn_speed := 9.0
## How often the navigation target is refreshed. Every frame is wasteful and
## produces no visible improvement at this speed.
@export var repath_interval := 0.15
## Steepest surface a zombie will walk up rather than treat as a wall.
@export var floor_climb_angle_degrees := 80.0

@export_group("Combat")
@export var contact_damage := 12.0
@export var attack_range := 1.9
@export var attack_cooldown := 1.1

@export_group("Hearing")
## How far this zombie can hear a noise of loudness 1.0.
##
## Set per kind by configure(): a Brute hears furthest, which means the thing
## you least want to attract is the thing a shot is most likely to bring.
@export var hearing_range := 26.0
## How long it keeps heading for a sound before giving up on it.
@export var investigate_duration := 7.0
## Inside this distance the player is the only thing that matters and noise is
## ignored completely.
@export var engaged_range := 7.0

@export_group("Feel")
@export var groan_interval := Vector2(3.5, 9.0)
@export var corpse_collapse_time := 0.9

var _target: Node3D
var _attack_remaining := 0.0
var _repath_remaining := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _groan_remaining := 0.0
## Where a heard noise came from, and how long this zombie still cares.
var _investigate_point := Vector3.ZERO
var _investigate_remaining := 0.0

## Set by configure(); read by the spawner when this zombie dies.
var kind: ZombieTypes.Kind = ZombieTypes.Kind.SHAMBLER
var experience_value := 1
var ammo_value := 3

## Capsule radius as a fraction of the body's height. A human figure is roughly
## four and a half times as tall as it is wide through the shoulders.
const BODY_RADIUS_RATIO := 0.22
## Height the exported attack_range below was tuned against.
const REFERENCE_HEIGHT := 2.0
## Close enough to a sound to count as having reached it.
const ARRIVAL_DISTANCE := 2.0

var base_attack_range := 1.9

@onready var health: Health = $Health
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: ZombieVisual = $Visual
@onready var _collider: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = attack_range * 0.7

	_groan_remaining = randf_range(groan_interval.x, groan_interval.y)

	# The cave floor meets doorways in steep rocky lips. At the default 45° a
	# zombie treats those as walls and stops dead; a steep limit lets it walk up
	# them while still being blocked by the near-vertical walls themselves.
	floor_max_angle = deg_to_rad(floor_climb_angle_degrees)


func _physics_process(delta: float) -> void:
	_attack_remaining = maxf(0.0, _attack_remaining - delta)
	_tick_groan(delta)
	_visual.update_locomotion(Vector2(velocity.x, velocity.z).length())

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if _target == null or health.is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_tick_investigation(delta)
	_tick_repath(delta)
	_move_toward_target(delta)
	_try_attack()

	move_and_slide()


## Apply a kind's stats and look. Called by the spawner before the zombie
## enters the fight, so health is set before _ready reads max_health.
func configure(zombie_kind: ZombieTypes.Kind) -> void:
	kind = zombie_kind
	var definition := ZombieTypes.definition(kind)

	move_speed = definition.speed
	contact_damage = definition.damage
	experience_value = definition.experience
	ammo_value = definition.ammo
	hearing_range = definition.hearing

	health.max_health = definition.health
	health.current_health = definition.health

	var height: float = definition.height
	_visual.apply_kind(height, definition.tint)

	# The capsule is built from the same height the model was scaled to, so
	# what you shoot at is what you hit. These used to come from separate
	# numbers and ended up a factor of two apart: the hitbox sat around the
	# zombie's legs while the player was aiming at its chest, and most shots
	# that looked like hits passed straight through.
	_collider.shape = _collider.shape.duplicate()
	_collider.shape.height = height
	_collider.shape.radius = height * BODY_RADIUS_RATIO
	_collider.position.y = height * 0.5

	# A Brute is wider as well as taller, and reach has to grow with the body
	# or it cannot land a blow its arms clearly reach.
	attack_range = base_attack_range * (height / REFERENCE_HEIGHT)


## Assign the node this zombie hunts. Called by the spawner.
func set_target(target: Node3D) -> void:
	_target = target
	if is_inside_tree() and target != null:
		_agent.target_position = target.global_position


## Damage entry point used by the weapon's raycast.
func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO,
		_direction: Vector3 = Vector3.ZERO) -> float:
	return health.take_damage(amount)


## React to a noise somewhere in the cave.
##
## The zombie heads for where the sound came from rather than for the player,
## which is the whole point: a gunshot should cost the shooter their position,
## not just a bullet. It does not reveal the player, only the place.
##
## Two things are deliberately immune. A zombie already close enough to be a
## threat ignores noise entirely — something mauling you does not wander off
## because a gun went off nearby, and letting it would make firing a panic
## button rather than a cost. And a noise further away than this zombie can
## hear does nothing at all, which is what makes distance a real defence.
## Returns true only when the noise actually diverted this zombie.
func hear_noise(noise_position: Vector3, loudness: float) -> bool:
	if health.is_dead:
		return false

	if global_position.distance_to(noise_position) > hearing_range * loudness:
		return false

	if _target != null and global_position.distance_to(_target.global_position) <= engaged_range:
		return false

	_investigate_point = noise_position
	_investigate_remaining = investigate_duration
	return true


## True while this zombie is heading for a sound rather than for the player.
func is_investigating() -> bool:
	return _investigate_remaining > 0.0


## Where this zombie is currently trying to get to.
func _move_goal() -> Vector3:
	return _investigate_point if is_investigating() else _target.global_position


## Count down the investigation, and end it early on arrival or on getting
## close enough to the player that the sound stops being the interesting thing.
func _tick_investigation(delta: float) -> void:
	if not is_investigating():
		return

	_investigate_remaining -= delta

	if global_position.distance_to(_investigate_point) <= ARRIVAL_DISTANCE:
		_investigate_remaining = 0.0
		return

	if _target != null and global_position.distance_to(_target.global_position) <= engaged_range:
		_investigate_remaining = 0.0


func _tick_repath(delta: float) -> void:
	_repath_remaining -= delta
	if _repath_remaining > 0.0:
		return

	_repath_remaining = repath_interval
	_agent.target_position = _move_goal()


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


func _tick_groan(delta: float) -> void:
	_groan_remaining -= delta
	if _groan_remaining > 0.0:
		return

	_groan_remaining = randf_range(groan_interval.x, groan_interval.y)
	groaned.emit(global_position)


func _on_damaged(_amount: float, _current: float, _maximum: float) -> void:
	_visual.flash()


func _on_died() -> void:
	died.emit(self, global_position)

	# Hand the body off before the node goes, so the kill leaves something
	# behind without keeping a dead zombie in the alive list.
	_visual.detach_as_corpse(corpse_collapse_time)

	# Stop participating in the fight immediately; the node is freed by the
	# spawner after the death signal is handled.
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	queue_free()
