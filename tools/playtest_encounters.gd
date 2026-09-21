extends SceneTree

## Runs specific mixed-kind encounters and reports what the player would
## actually experience in them.
##
## This is a probe, not a gate step. The archetype suite already proves each
## kind does its own thing in isolation; what it cannot tell anyone is whether
## two of them in the same room produce an interesting decision or just a
## louder pile. That question has no pass/fail, so it does not belong in
## check.sh — it belongs here, run by hand, read by a person.
##
## Everything printed is measured rather than asserted. Where a number looks
## wrong the answer is to change a tuning value and run it again, not to add
## an assertion.
##
##   Godot --headless --script tools/playtest_encounters.gd -- --scenario=all
##   Godot --headless --script tools/playtest_encounters.gd -- --scenario=cascade --seconds=30

const GAME_SCENE := "res://src/core/game.tscn"

## Within this of the player counts as being on them.
const CONTACT_DISTANCE := 2.6
## How often the timeline is sampled. Four times a second is finer than any
## decision a player makes and coarse enough not to drown the output.
const SAMPLE_INTERVAL := 0.25

## Compositions, as lists of kinds. Named for the question each one asks.
const SCENARIOS := {
	"shambler_runner": [0, 0, 0, 1],
	"runner_screamer": [1, 4],
	"stalker_shamblers": [3, 0, 0],
	"brute_shamblers": [2, 0, 0, 0],
	"mixed_wave": [0, 0, 0, 0, 1, 1, 2, 3, 4],
	## Three Screamers and a chamber full of things for them to recruit. The
	## specific risk: one scream pulling the map, or worse, a scream that
	## recruits a second Screamer which screams again.
	"cascade": [4, 4, 4, 0, 0, 0, 0, 0, 1, 1, 2, 3],
	## One Stalker, and a player who keeps looking straight at it.
	"stalker_watch": [3],
	## One Shambler, instrumented gate by gate. Every run above showed zombies
	## arriving on top of the player having never entered HUNTING, which would
	## mean the strongest readability tell, the threat meter and the Screamer's
	## entire mechanic are all gated on a flag that mostly does not set.
	"sight": [0],
}

var _game: Game
var _scenario := "all"
var _seconds := 30.0
var _queue: Array[String] = []

var _elapsed := 0.0
var _sample_remaining := 0.0
var _started := false
var _tracked: Array[Dictionary] = []

## Cascade bookkeeping.
var _alarms := 0
var _recruits := 0
var _first_alarm_at := -1.0
var _awake_timeline: Array[String] = []

## Stalker bookkeeping.
var _stalker: Zombie
var _stalker_samples := 0
var _stalker_behind := 0
var _stalker_retreats := 0
var _stalker_stalled := 0
var _stalker_reversals := 0
var _stalker_last_heading := Vector3.ZERO
var _stalker_was_retreating := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="):
			_scenario = argument.split("=")[1]
		elif argument.begins_with("--seconds="):
			_seconds = float(argument.split("=")[1])

	if _scenario == "all":
		for name in SCENARIOS:
			_queue.append(str(name))
	else:
		_queue.append(_scenario)

	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		DeterministicSettings.apply(root)
		_game.start_round()
		_begin_next()
		return false

	if _queue.is_empty():
		_teardown()
		quit(0)
		return true

	_elapsed += delta
	_sample_remaining -= delta

	if _sample_remaining <= 0.0:
		_sample_remaining = SAMPLE_INTERVAL
		_sample()

	if _elapsed < _seconds:
		return false

	_report()
	_queue.pop_front()

	if _queue.is_empty():
		_teardown()
		quit(0)
		return true

	_begin_next()
	return false


## Clear the arena and set up the next composition.
##
## Zombies are placed on real spawn points rather than at made-up offsets, so
## every one of them is provably on the navmesh and the distances are the ones
## the map actually produces.
func _begin_next() -> void:
	var name: String = _queue[0]
	var kinds: Array = SCENARIOS[name]

	var spawner := _game.spawner
	spawner.stop()
	spawner.clear_all()

	_elapsed = 0.0
	_sample_remaining = 0.0
	_tracked.clear()
	_alarms = 0
	_recruits = 0
	_first_alarm_at = -1.0
	_awake_timeline.clear()
	_stalker = null
	_stalker_samples = 0
	_stalker_behind = 0
	_stalker_retreats = 0
	_stalker_stalled = 0
	_stalker_reversals = 0
	_stalker_last_heading = Vector3.ZERO
	_stalker_was_retreating = false

	var player := _game.player
	var points := _points_by_distance(player.global_position)

	print("")
	print("=".repeat(66))
	print("%s — %d zombies, %.0fs" % [name, kinds.size(), _seconds])
	print("=".repeat(66))

	for index in kinds.size():
		var kind: int = kinds[index]
		var point: Vector3 = points[index % points.size()]

		var zombie: Zombie = spawner.zombie_scene.instantiate()
		spawner.add_child(zombie)
		zombie.configure(kind)
		zombie.alarm_radius = (
			spawner.alert_radius * ZombieTypes.definition(kind).alarm_radius_scale
		)
		zombie.global_position = point + Vector3.UP * 0.1
		zombie.set_target(player)

		# The spawner is switched off here, so its alarm relay is not wired up.
		# Wire it by hand, or a Screamer scenario measures nothing at all.
		zombie.raised_alarm.connect(_on_alarm_raised)

		if kind == ZombieTypes.Kind.STALKER and _stalker == null:
			_stalker = zombie

		_tracked.append({
			"zombie": zombie,
			"kind": kind,
			"start": point.distance_to(player.global_position),
			"contact_at": -1.0,
			"hunting_at": -1.0,
			"closest": point.distance_to(player.global_position),
		})

	# Everything starts genuinely unaware, so "when did it notice you" is a
	# real measurement rather than a consequence of the setup. A wave that is
	# woken on spawn cannot show which kind finds you first.
	spawner._alive.assign(_tracked.map(func(entry: Dictionary) -> Zombie: return entry.zombie))


## One zombie's shout, relayed to everything in its own alarm radius.
##
## Duplicated from the spawner deliberately: this counts how many zombies each
## scream actually recruits, which the spawner has no reason to report.
func _on_alarm_raised(raiser: Zombie, believed: Vector3) -> void:
	if raiser.alarm_radius <= 0.0:
		return

	_alarms += 1
	if _first_alarm_at < 0.0:
		_first_alarm_at = _elapsed

	for entry in _tracked:
		var zombie: Zombie = entry.zombie
		if not is_instance_valid(zombie) or zombie == raiser:
			continue
		if zombie.global_position.distance_to(raiser.global_position) > raiser.alarm_radius:
			continue

		var was_ignorant := zombie.awareness == Zombie.Awareness.UNAWARE
		zombie.receive_alert(believed)
		if was_ignorant and zombie.awareness != Zombie.Awareness.UNAWARE:
			_recruits += 1


func _sample() -> void:
	var player := _game.player
	var player_position := player.global_position

	var awake := 0

	for entry in _tracked:
		var zombie: Zombie = entry.zombie
		if not is_instance_valid(zombie) or zombie.health.is_dead:
			continue

		var distance := zombie.global_position.distance_to(player_position)
		entry.closest = minf(entry.closest, distance)

		if zombie.awareness != Zombie.Awareness.UNAWARE:
			awake += 1
		if entry.hunting_at < 0.0 and zombie.is_hunting():
			entry.hunting_at = _elapsed
		if entry.contact_at < 0.0 and distance <= CONTACT_DISTANCE:
			entry.contact_at = _elapsed

	_awake_timeline.append("%.0f:%d" % [_elapsed, awake])

	if _queue[0] == "sight":
		_sample_sight(player_position)

	if _stalker != null and is_instance_valid(_stalker):
		_sample_stalker(player)


## Break _can_see_target() into its three gates and report which one is
## refusing, once a second.
##
## "It never noticed you" is not actionable on its own: range, the sight cone
## and the line-of-sight ray fail for completely different reasons and want
## completely different fixes.
func _sample_sight(player_position: Vector3) -> void:
	if roundi(_elapsed * 4.0) % 4 != 0:
		return

	var zombie: Zombie = _tracked[0].zombie
	if not is_instance_valid(zombie):
		return

	var to_target := player_position - zombie.global_position
	var distance := to_target.length()
	var facing := zombie.facing()
	var dot := facing.dot(to_target / maxf(distance, 0.001))
	var cone_limit := cos(deg_to_rad(zombie.sight_cone_degrees * 0.5))

	var eye_height: float = zombie._collider.shape.height * 0.85
	var query := PhysicsRayQueryParameters3D.create(
		zombie.global_position + Vector3.UP * eye_height,
		player_position + Vector3.UP * 1.5
	)
	query.collision_mask = 1
	query.exclude = [zombie.get_rid()]
	var blocker := zombie.get_world_3d().direct_space_state.intersect_ray(query)

	print("  %4.0fs  %5.1fm  dot %+.2f (need %+.2f)  %-14s  %-12s  %s" % [
		_elapsed,
		distance,
		dot,
		cone_limit,
		"IN RANGE" if distance <= zombie.sight_range else "TOO FAR",
		"FACING" if dot >= cone_limit else "LOOKING AWAY",
		"clear" if blocker.is_empty() else "blocked by %s" % blocker.collider.name,
	])


## The Stalker's own readability questions: is it where the player is not
## looking, and does it move like something with a plan.
func _sample_stalker(player: Node3D) -> void:
	_stalker_samples += 1

	var to_stalker := _stalker.global_position - player.global_position
	to_stalker.y = 0.0
	var facing := -player.global_transform.basis.z
	facing.y = 0.0

	if to_stalker.length() > 0.01 and facing.length() > 0.01:
		# Outside the player's own 140-degree cone, using the same half-angle
		# the zombies' sight uses, so "behind you" means the same thing on both
		# sides of the fight.
		if facing.normalized().dot(to_stalker.normalized()) < cos(deg_to_rad(70.0)):
			_stalker_behind += 1

	var retreating := _stalker.is_retreating()
	if retreating and not _stalker_was_retreating:
		_stalker_retreats += 1
	_stalker_was_retreating = retreating

	var velocity := Vector3(_stalker.velocity.x, 0.0, _stalker.velocity.z)

	# Wedged: trying to be somewhere else and getting nowhere. Distinguished
	# from a wind-up, which is supposed to hold it still.
	if velocity.length() < 0.35 and _stalker._attack_state == Zombie.AttackState.READY:
		_stalker_stalled += 1

	if velocity.length() > 0.5:
		var heading := velocity.normalized()
		if _stalker_last_heading != Vector3.ZERO \
				and heading.dot(_stalker_last_heading) < -0.3:
			_stalker_reversals += 1
		_stalker_last_heading = heading


func _report() -> void:
	var name: String = _queue[0]

	# Ordered by when each one first got on top of the player: this is the
	# order the player has to deal with them in, which is the whole question.
	var order := _tracked.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: float = a.contact_at if a.contact_at >= 0.0 else 9999.0
		var right: float = b.contact_at if b.contact_at >= 0.0 else 9999.0
		return left < right
	)

	print("  %-10s %8s %8s %8s %8s" % ["kind", "start", "noticed", "contact", "closest"])
	for entry in order:
		print("  %-10s %7.1fm %7s %8s %7.1fm" % [
			_kind_name(entry.kind),
			entry.start,
			_seconds_or_never(entry.hunting_at),
			_seconds_or_never(entry.contact_at),
			entry.closest,
		])

	var reached := order.filter(func(e: Dictionary) -> bool: return e.contact_at >= 0.0)
	print("  reached the player: %d / %d" % [reached.size(), _tracked.size()])

	if _alarms > 0 or name == "cascade":
		print("")
		print("  alarms raised:      %d (first at %s)"
			% [_alarms, _seconds_or_never(_first_alarm_at)])
		print("  zombies recruited:  %d of %d"
			% [_recruits, maxi(_tracked.size() - 1, 1)])
		print("  awake over time:    %s" % " ".join(_thinned_timeline()))

	if _stalker_samples > 0:
		print("")
		print("  stalker out of view:   %d%% of the encounter"
			% roundi(100.0 * float(_stalker_behind) / float(_stalker_samples)))
		print("  stalker break-offs:    %d" % _stalker_retreats)
		print("  stalker stalled:       %d%% of samples"
			% roundi(100.0 * float(_stalker_stalled) / float(_stalker_samples)))
		print("  stalker reversals:     %d (%.2f/s)"
			% [_stalker_reversals, float(_stalker_reversals) / maxf(_elapsed, 0.01)])


## One entry per second rather than per sample, or the line is unreadable.
func _thinned_timeline() -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for entry in _awake_timeline:
		var second: String = entry.split(":")[0]
		if seen.has(second):
			continue
		seen[second] = true
		out.append(entry)
	return out


## Spawn points sorted near-to-far, so a composition's first listed kind is
## always the closest one and the orderings below are comparable run to run.
func _points_by_distance(from: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = _game.arena.spawn_points.duplicate()
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_to(from) < b.distance_to(from)
	)
	return points


func _seconds_or_never(at: float) -> String:
	return "never" if at < 0.0 else "%.1fs" % at


func _kind_name(kind: int) -> String:
	return str((ZombieTypes.Kind.keys() as Array)[kind])


func _teardown() -> void:
	if _game != null and is_instance_valid(_game):
		root.remove_child(_game)
		_game.free()
		_game = null
