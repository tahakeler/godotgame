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
	## One Screamer among eight sleepers: how far does a single scream reach?
	"one_screamer": [4, 0, 0, 0, 0, 1, 1, 2, 3],
	## One Stalker, and a player who keeps looking straight at it.
	"stalker_watch": [3],
	## Not a composition at all: the real spawner, left to run a real round
	## against a stand-in that cannot die. Every scenario above places zombies
	## by hand, which is the only way to ask a controlled question and the wrong
	## way to ask what a round actually feels like.
	"live": [],
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

## Live-round bookkeeping, keyed by zombie instance id.
var _seen: Dictionary = {}
var _stalker_break_offs_live := 0
var _stalker_contacts := 0
## Stand-in for a player who is actually shooting. Zero means nothing dies,
## which turns every pacing measurement into a measurement of the cap.
var _kills_per_second := 0.0
var _kill_remaining := 0.0
var _kills := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="):
			_scenario = argument.split("=")[1]
		elif argument.begins_with("--seconds="):
			_seconds = float(argument.split("=")[1])
		elif argument.begins_with("--kills="):
			_kills_per_second = float(argument.split("=")[1])

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

	# A live round runs the director rather than a fixture, so there is nothing
	# to place and nothing to put to sleep.
	if name == "live":
		_seen.clear()
		_stalker_break_offs_live = 0
		_stalker_contacts = 0
		_kills = 0
		_kill_remaining = 0.0
		spawner.begin(_game.arena, player)
		print("  %5s %6s %5s %5s %7s   %s" % [
			"t", "alive", "hunt", "<10m", "nearest", "composition"
		])
		return

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

	spawner._alive.assign(_tracked.map(func(entry: Dictionary) -> Zombie: return entry.zombie))

	if name == "cascade" or name == "one_screamer":
		_send_everything_but_screamers_to_sleep()


## Put every non-Screamer back to sleep, so recruitment can be counted.
##
## set_target() deliberately hands a fresh zombie a belief about where the
## player is — that is the safeguard that stops real spawns wandering off into
## empty chambers. It also means a cascade run starts with the entire
## population already awake, nobody in UNAWARE, and therefore *nothing left to
## recruit*: the first measured attempt reported 36 alarms and 0 recruits of 11,
## which said nothing about the Screamer and everything about the fixture.
##
## Clearing the belief is not enough on its own. An UNAWARE zombie still walks
## to last_known_position, so it would stroll to the player's start anyway;
## pointing the belief at its own feet is what actually leaves it standing in
## its chamber the way an undisturbed zombie should.
##
## The Screamers keep their spawn belief, so they walk in, see the player, hunt
## and shout — which is the only honest way to ask how far one scream travels.
func _send_everything_but_screamers_to_sleep() -> void:
	for entry in _tracked:
		if entry.kind == ZombieTypes.Kind.SCREAMER:
			continue

		var zombie: Zombie = entry.zombie
		zombie.awareness = Zombie.Awareness.UNAWARE
		zombie.last_known_position = zombie.global_position


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

	if _queue[0] == "live":
		_sample_live(player)
		return

	if _queue[0] == "sight":
		_sample_sight(player_position)

	# A player who never turns their head can never look at a Stalker, and a
	# Stalker that is never looked at never breaks off. Two rounds of
	# measurement reported "break-offs: 0" and both times that was the fixture
	# standing still, not the behaviour failing. Tracking it is the only way the
	# retreat gets exercised in play rather than by unit assertion.
	if _queue[0] == "stalker_watch" and _stalker != null and is_instance_valid(_stalker):
		_stare_at(player, _stalker.global_position)

	if _stalker != null and is_instance_valid(_stalker):
		_sample_stalker(player)


## Watch a real round: what the director actually sends, and what a Stalker
## does inside a crowd rather than alone.
##
## The stand-in is kept alive by hand. The question is what the round *becomes*
## over a minute and a half, and a player who dies at t=40 cannot answer it.
func _sample_live(player: Node3D) -> void:
	if player.has_node("Health"):
		var health: Health = player.get_node("Health")
		health.current_health = health.max_health

	# Held open by hand. Killing zombies feeds progression, and something
	# downstream of that stops the director — measured: spawning ceased after
	# four kills and the cave stayed empty for the remaining 110 seconds. That
	# is Game's business and possibly correct; it is not what this probe is
	# asking about, and a director that has switched itself off cannot answer a
	# question about pacing.
	# And unpaused. Kills feed progression, progression opens the upgrade
	# screen, and that pauses the tree — which stops the director and the horde
	# while this probe's own _process carries on, so the round looks empty
	# rather than paused.
	paused = false

	_game.spawner._active = true

	_simulate_shooting(player)

	var counts := PackedInt32Array([0, 0, 0, 0, 0])
	var alive := 0
	var hunting := 0
	var close := 0
	var nearest := INF

	for child in _game.spawner.get_children():
		var zombie := child as Zombie
		if zombie == null or not is_instance_valid(zombie) or zombie.health.is_dead:
			continue

		alive += 1
		counts[zombie.kind] += 1
		if zombie.is_hunting():
			hunting += 1

		var distance := zombie.global_position.distance_to(player.global_position)
		nearest = minf(nearest, distance)
		if distance < 10.0:
			close += 1

		_track_live_stalker(zombie, distance)

	if roundi(_elapsed * 4.0) % 20 != 0:
		return

	var composition := ""
	for kind in ZombieTypes.Kind.values():
		composition += "%s:%d " % [
			str((ZombieTypes.Kind.keys() as Array)[kind]).substr(0, 2), counts[kind]
		]

	print("  %4.0fs %6d %5d %5d %6.1fm   %s" % [
		_elapsed, alive, hunting, close, nearest, composition
	])


## Kill the nearest zombie on a fixed cadence, standing in for a player who is
## actually fighting.
##
## Without this the population can only ever rise, so the cap is reached and
## the round freezes: every measurement of pacing becomes a measurement of the
## cap. It also hides the composition entirely — nothing dies, no slot frees,
## and whatever spawned before the cap filled is what the player faces for the
## rest of the round.
##
## Nearest-first because that is what a cornered player does. A player picking
## targets well is a different and much harder thing to model, and the point
## here is the director's behaviour rather than the player's.
func _simulate_shooting(player: Node3D) -> void:
	if _kills_per_second <= 0.0:
		return

	_kill_remaining -= SAMPLE_INTERVAL
	if _kill_remaining > 0.0:
		return

	_kill_remaining = 1.0 / _kills_per_second

	var nearest: Zombie = null
	var nearest_distance := INF

	for child in _game.spawner.get_children():
		var zombie := child as Zombie
		if zombie == null or not is_instance_valid(zombie) or zombie.health.is_dead:
			continue

		var distance := zombie.global_position.distance_to(player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = zombie

	if nearest != null:
		_kills += 1
		nearest.take_damage(nearest.health.max_health)


## Per-Stalker bookkeeping across a live round.
##
## The solo fixture answered "what does a Stalker do when it is the only thing
## in the room and you never stop looking at it", which is a deliberately
## extreme case. This answers the question that actually matters: inside a
## crowd, with the player busy, does the break-off limit ever get reached at
## all, or does a Stalker read the way it did before the limit existed?
func _track_live_stalker(zombie: Zombie, distance: float) -> void:
	if zombie.kind != ZombieTypes.Kind.STALKER:
		return

	var id := zombie.get_instance_id()
	var was_retreating: bool = _seen.get(id, false)
	var retreating := zombie.is_retreating()

	if retreating and not was_retreating:
		_stalker_break_offs_live += 1
	_seen[id] = retreating

	if distance <= CONTACT_DISTANCE and not _seen.has("contact_%d" % id):
		_seen["contact_%d" % id] = true
		_stalker_contacts += 1


## Point the player's body at a spot, the way a player who has noticed
## something keeps it on screen.
##
## Yaw only. The Stalker's watched-check reads the body's facing on the
## horizontal plane, and the camera's pitch lives on a separate node, so
## rolling the whole body to look down at a thing 2m away would be both wrong
## and untrue to how the player actually moves.
func _stare_at(player: Node3D, at: Vector3) -> void:
	var to_target := at - player.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return

	player.global_rotation.y = atan2(-to_target.x, -to_target.z)


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

	# Is it orbiting a goal that keeps moving, or parked on a goal it has
	# already reached? Those look identical from the outside and want opposite
	# fixes, so print the goal alongside the body once a second.
	if _queue[0] == "stalker_watch" and roundi(_elapsed * 4.0) % 4 == 0:
		var goal: Vector3 = _stalker._move_goal()
		print("  %4.0fs  to player %5.1fm   to its own goal %5.1fm   goal %6.1f,%6.1f   %s" % [
			_elapsed,
			_stalker.global_position.distance_to(player.global_position),
			_stalker.global_position.distance_to(goal),
			goal.x, goal.z,
			Zombie.Awareness.keys()[_stalker.awareness],
		])

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

	if _alarms > 0 or name.ends_with("screamer") or name == "cascade":
		print("")
		print("  alarms raised:      %d (first at %s)"
			% [_alarms, _seconds_or_never(_first_alarm_at)])
		print("  zombies recruited:  %d of %d"
			% [_recruits, maxi(_tracked.size() - 1, 1)])
		print("  awake over time:    %s" % " ".join(_thinned_timeline()))

	if _queue[0] == "live":
		print("")
		print("  stalker break-offs across the round: %d" % _stalker_break_offs_live)
		print("  stalkers that reached the player:    %d" % _stalker_contacts)
		print("  simulated kills:                     %d (%.1f/s)" % [_kills, _kills_per_second])
		return

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
