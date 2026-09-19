class_name ZombieSpawner
extends Node3D

## Feeds zombies into the arena at an accelerating rate.
##
## Pressure ramps rather than arriving in discrete waves, because the concept's
## flow-state design calls for difficulty that rises with the player's warm-up
## instead of spiking between rounds.

signal zombie_died(death_position: Vector3, experience: int, ammo: int)
signal zombie_hit_player(damage: float, from_position: Vector3)
signal zombie_groaned(groan_position: Vector3, kind: ZombieTypes.Kind)
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

@export_group("Endless")
## Set by Game when the endless mode is chosen.
@export var endless := false
## Interval multiplier applied every 30s past the end of the normal ramp.
@export var endless_interval_decay := 0.88
@export var endless_interval_floor := 0.28
@export var endless_seconds_per_extra_zombie := 22.0

## Difficulty multipliers, applied by Game from the player's chosen difficulty.
## Below 1.0 on the interval means zombies arrive faster.
var interval_scale := 1.0
var damage_scale := 1.0

var _arena: Arena
var _target: Node3D
var _alive: Array[Zombie] = []
var _spawn_remaining := 0.0
var _elapsed := 0.0
var _active := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


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
	if _alive.size() < _current_max_alive():
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


## Tell every living zombie that something was heard here.
##
## Broadcast to all of them and let each decide, rather than querying the ones
## in range: the spawner would need a spatial structure to answer that, and the
## population is capped low enough that a distance check per zombie is cheaper
## than maintaining one. Each zombie knows its own hearing range anyway, which
## differs by kind.
func broadcast_noise(noise_position: Vector3, loudness := 1.0) -> int:
	var heard := 0

	for zombie in _alive:
		if not is_instance_valid(zombie):
			continue
		if zombie.hear_noise(noise_position, loudness):
			heard += 1

	return heard


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
##
## In endless mode the ramp does not stop at its floor: the interval keeps
## shrinking and the population cap keeps rising, so pressure always eventually
## exceeds what the player can hold. A survival mode you cannot lose is a
## screensaver.
func _current_interval() -> float:
	var ramp_progress := clampf(
		(_elapsed - grace_period) / maxf(ramp_duration, 0.001), 0.0, 1.0
	)
	var interval := lerpf(initial_interval, minimum_interval, ramp_progress) * interval_scale

	if endless:
		var overtime := maxf(0.0, _elapsed - grace_period - ramp_duration)
		interval *= pow(endless_interval_decay, overtime / 30.0)

	return maxf(interval, endless_interval_floor)


## Population ceiling, which endless raises over time.
func _current_max_alive() -> int:
	if not endless:
		return max_alive

	var overtime := maxf(0.0, _elapsed - grace_period - ramp_duration)
	return max_alive + int(overtime / endless_seconds_per_extra_zombie)


func _spawn_one() -> void:
	if zombie_scene == null or _arena == null or _target == null:
		return

	# Hand the arena which way the player is looking, so arrivals can be
	# weighted behind them instead of appearing out of nothing in plain view.
	var spawn_position := _arena.pick_spawn_point(
		_target.global_position,
		minimum_spawn_distance,
		-_target.global_transform.basis.z
	)

	var zombie: Zombie = zombie_scene.instantiate()
	add_child(zombie)

	# Configure before positioning: the kind resizes the capsule, and a Brute
	# placed first would spend its first frame half inside the floor.
	zombie.configure(ZombieTypes.pick(_elapsed, _rng))
	zombie.global_position = spawn_position + Vector3.UP * 0.1
	zombie.contact_damage *= damage_scale
	zombie.set_target(_target)

	zombie.died.connect(_on_zombie_died)
	zombie.hit_player.connect(_on_zombie_hit_player)
	zombie.groaned.connect(func(groan_position: Vector3) -> void:
		zombie_groaned.emit(groan_position, zombie.kind)
	)

	_alive.append(zombie)
	population_changed.emit(_alive.size())


func _on_zombie_died(zombie: Zombie, death_position: Vector3) -> void:
	_alive.erase(zombie)
	population_changed.emit(_alive.size())
	# Rewards travel with the kind that died, so a Brute is worth the magazine
	# it took to bring down.
	zombie_died.emit(death_position, zombie.experience_value, zombie.ammo_value)


func _on_zombie_hit_player(damage: float, from_position: Vector3) -> void:
	zombie_hit_player.emit(damage, from_position)
