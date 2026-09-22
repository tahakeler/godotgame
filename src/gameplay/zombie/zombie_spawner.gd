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
## A zombie has just started hunting the player.
signal zombie_noticed_player(at: Vector3, kind: ZombieTypes.Kind)
## A Screamer has drawn breath and is about to raise the alarm.
##
## The single most important sound in a round: it is the only warning the
## player gets that the room is about to fill up, and the whole reason the
## Screamer has a wind-up at all is so there is something to react to. Relayed
## here rather than left on the zombie because listeners should not have to
## reach into the population to find one — every other per-zombie event a
## listener cares about already arrives this way.
signal zombie_winding_up(at: Vector3, kind: ZombieTypes.Kind)

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
## How far a hunting zombie's alarm passes to the ones around it.
@export var alert_radius := 14.0

@export_group("Response")
## Interval multiplier when the cave is completely empty, easing back to 1.0 as
## the population approaches the cap. Below 1.0 means an empty cave refills
## faster than a full one tops up.
@export_range(0.05, 1.0) var catch_up_scale := 0.35

@export_group("Threat")
## Distance over which a hunter's contribution halves.
@export var threat_falloff := 12.0
## Weighted hunters needed to read as maximum danger.
@export var threat_saturation := 2.6

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

	# Symmetry with stop(). A restart normally clears the population first, so
	# there is usually nothing here to thaw — but begin() must not be the thing
	# that leaves a frozen zombie standing in a live round if it is ever called
	# without a reset in between.
	for zombie in _alive:
		if is_instance_valid(zombie):
			zombie.resume_fighting()


## End the round: stop producing zombies, and stop the ones already out there.
##
## This used to set the flag and nothing else, which stopped the spawn tick and
## left the existing horde untouched — still pathing, still biting, still
## groaning behind the results overlay. The flag governs whether new zombies
## arrive; it never governed the ones that already had.
##
## Deliberately fixed here rather than in game.gd. "The round is over, so the
## horde stops" is a fact about the horde, and a caller that has to remember to
## walk the population itself is a caller that will eventually forget.
func stop() -> void:
	_active = false

	for zombie in _alive:
		if is_instance_valid(zombie):
			zombie.stop_fighting()


## How much danger the player is actually in, from 0 to 1.
##
## Counts only zombies that are hunting — something wandering a chamber away
## is not a threat however close it happens to be standing, and something that
## has seen you is a threat even at range. That distinction is the whole reason
## the awareness system exists, and a meter built on raw proximity would throw
## it away and go back to measuring how crowded the room is.
##
## Each hunter contributes on a falloff, so three closing in reads hotter than
## three across the map, and the total saturates rather than climbing forever:
## past a certain point the difference between five and nine is not something
## the player can act on differently.
func threat_level(from: Vector3) -> float:
	var total := 0.0

	for zombie in _alive:
		if not is_instance_valid(zombie) or not zombie.is_hunting():
			continue

		var distance := zombie.global_position.distance_to(from)
		total += 1.0 / (1.0 + distance / threat_falloff)

	return clampf(total / maxf(threat_saturation, 0.01), 0.0, 1.0)


## Pass one zombie's belief to the ones near it.
##
## Straight-line range on purpose, unlike hearing. This is a crowd noticing
## which way the one next to it is going, not a sound carrying down a corridor,
## and it should not reach through a wall into the next chamber.
## The radius is the raiser's own rather than the spawner's flat one, because
## how far a zombie's voice carries is a property of the zombie. A Screamer
## reaches most of a chamber complex; a Stalker reaches nobody at all. Both are
## still expressed as multiples of alert_radius, so this stays the one knob
## that governs how quickly a crowd converges.
func _on_alarm_raised(raiser: Zombie, believed_position: Vector3) -> void:
	if raiser.alarm_radius <= 0.0:
		return

	for zombie in _alive:
		if not is_instance_valid(zombie) or zombie == raiser:
			continue
		if zombie.global_position.distance_to(raiser.global_position) > raiser.alarm_radius:
			continue

		zombie.receive_alert(believed_position)


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

	# Spawn faster the emptier the cave is.
	#
	# The ramp is a function of elapsed time alone, which means the director has
	# no idea how the player is doing, and measurement showed both ends of that
	# going wrong. A stand-in killing at a modest 0.55/s outran it completely:
	# the population sat at zero or one for the first fifty-five seconds and
	# pressure only arrived after t=90. A stand-in killing nothing hit the cap
	# at t=50 and stayed pinned there for the rest of the round.
	#
	# Same root cause, opposite symptoms — the rate never responds to what is
	# actually in the cave. Scaling the interval by how far under the ceiling
	# the population is closes that loop with one multiply.
	#
	# Deliberately one-directional: this can only ever make zombies arrive
	# sooner, never later, so it cannot quietly starve anything that depends on
	# the horde showing up.
	var shortfall := 1.0 - float(_alive.size()) / float(maxi(_current_max_alive(), 1))
	interval *= lerpf(1.0, catch_up_scale, clampf(shortfall, 0.0, 1.0))

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
	var kind := ZombieTypes.pick(_elapsed, _rng)
	zombie.configure(kind)

	# How far this one's shout carries. Kept here rather than in configure()
	# because it is a multiple of the crowd's alert radius, which belongs to
	# the spawner — a zombie has no business knowing how the horde is tuned.
	zombie.alarm_radius = alert_radius * ZombieTypes.definition(kind).alarm_radius_scale

	zombie.global_position = spawn_position + Vector3.UP * 0.1
	zombie.contact_damage *= damage_scale
	zombie.set_target(_target)

	zombie.raised_alarm.connect(_on_alarm_raised)
	zombie.noticed_player.connect(
		func(at: Vector3, kind: ZombieTypes.Kind) -> void:
			zombie_noticed_player.emit(at, kind)
	)
	zombie.died.connect(_on_zombie_died)
	zombie.hit_player.connect(_on_zombie_hit_player)
	zombie.groaned.connect(func(groan_position: Vector3) -> void:
		zombie_groaned.emit(groan_position, zombie.kind)
	)
	zombie.alarm_winding_up.connect(
		func(_raiser: Zombie, at: Vector3) -> void:
			zombie_winding_up.emit(at, zombie.kind)
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
