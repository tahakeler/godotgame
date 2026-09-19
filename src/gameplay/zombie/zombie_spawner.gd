class_name ZombieSpawner
extends Node3D

## Feeds zombies into the arena at an accelerating rate.
##
## Pressure ramps rather than arriving in discrete waves, because the concept's
## flow-state design calls for difficulty that rises with the player's warm-up
## instead of spiking between rounds.

signal zombie_died(death_position: Vector3)
signal zombie_hit_player(damage: float, from_position: Vector3)
signal population_changed(alive: int)

@export var zombie_scene: PackedScene

@export_group("Pacing")
## Seconds before the first zombie appears, so the player can orient.
@export var grace_period := 5.0
@export var initial_interval := 2.6
@export var minimum_interval := 0.75
## How long it takes to reach minimum_interval.
@export var ramp_duration := 90.0

@export_group("Limits")
@export var max_alive := 20
## Zombies never spawn closer to the player than this.
@export var minimum_spawn_distance := 14.0

var _arena: Arena
var _target: Node3D
var _alive: Array[Zombie] = []
var _spawn_remaining := 0.0
var _elapsed := 0.0
var _active := false


func _process(delta: float) -> void:
	if not _active:
		return

	_elapsed += delta

	if _elapsed < grace_period:
		return

	_spawn_remaining -= delta
	if _spawn_remaining > 0.0:
		return

	_spawn_remaining = _current_interval()
	if _alive.size() < max_alive:
		_spawn_one()


## Wire up the spawner and begin producing zombies.
func begin(arena: Arena, target: Node3D) -> void:
	_arena = arena
	_target = target
	_elapsed = 0.0
	_spawn_remaining = 0.0
	_active = true


func stop() -> void:
	_active = false


## Remove every living zombie. Used by restart.
func clear_all() -> void:
	for zombie in _alive:
		if is_instance_valid(zombie):
			zombie.died.disconnect(_on_zombie_died)
			zombie.hit_player.disconnect(_on_zombie_hit_player)
			zombie.queue_free()

	_alive.clear()
	population_changed.emit(0)


## Clear the arena and restart pacing from zero.
func reset() -> void:
	clear_all()
	_elapsed = 0.0
	_spawn_remaining = 0.0


func get_alive_count() -> int:
	return _alive.size()


## Current seconds-between-spawns, interpolated across the ramp.
func _current_interval() -> float:
	var ramp_progress := clampf(
		(_elapsed - grace_period) / maxf(ramp_duration, 0.001), 0.0, 1.0
	)
	return lerpf(initial_interval, minimum_interval, ramp_progress)


func _spawn_one() -> void:
	if zombie_scene == null or _arena == null or _target == null:
		return

	var spawn_position := _arena.pick_spawn_point(
		_target.global_position, minimum_spawn_distance
	)

	var zombie: Zombie = zombie_scene.instantiate()
	add_child(zombie)
	zombie.global_position = spawn_position + Vector3.UP * 0.1
	zombie.set_target(_target)

	zombie.died.connect(_on_zombie_died)
	zombie.hit_player.connect(_on_zombie_hit_player)

	_alive.append(zombie)
	population_changed.emit(_alive.size())


func _on_zombie_died(zombie: Zombie, death_position: Vector3) -> void:
	_alive.erase(zombie)
	population_changed.emit(_alive.size())
	zombie_died.emit(death_position)


func _on_zombie_hit_player(damage: float, from_position: Vector3) -> void:
	zombie_hit_player.emit(damage, from_position)
