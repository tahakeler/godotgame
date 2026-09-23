extends SceneTree

## Measures the ammunition economy by playing rounds, rather than by reading
## the tuning table and guessing.
##
## A probe, not a gate step. There is no pass/fail here — the two failure modes
## the design names ("ammunition that feels infinite" and "long stretches where
## the player cannot meaningfully fight") are judgements about figures, not
## assertions, so this prints and a person reads.
##
## An autopilot stands in for the player: it faces the nearest zombie, picks a
## weapon by range, fires when it can, reloads by the weapon's own rules, and
## swings the melee once everything is dry. It is a better shot than a human and
## never retreats, so every number below is an *upper* bound on how long the
## ammunition lasts. If the supply looks thin here it is thinner in practice.
##
## The autopilot is kept alive on purpose (`--immortal`, on by default). The question is
## whether the ammunition supply keeps up with the spawn rate; a run that ends
## because the stand-in player was eaten answers a different question.
##
##   Godot --headless --script tools/playtest_ammo.gd -- --seconds=150
##   Godot --headless --script tools/playtest_ammo.gd -- --only=shotgun

const GAME_SCENE := "res://src/core/game.tscn"
## Simulated seconds are cheap; real ones are not. Anything the autopilot does
## is frame-rate independent, so running the clock fast changes how long the
## probe takes and not what it measures.
## Left at 1.0. An earlier version of this probe ran the clock at 5x and
## measured a mean population of 1.0 zombies where a directly instrumented
## round reaches 8 by twenty-five seconds — the spawner is fine, the time
## scale was starving it. A measurement that has to distort the clock to be
## affordable is not a measurement.
const TIME_SCALE := 1.0
## How far a zombie can be before the autopilot stops bothering to aim at it.
const ENGAGE_RANGE := 45.0
## Ranges the autopilot picks weapons at. Chosen to match what each weapon is
## for rather than to flatter any of them.
const SHOTGUN_RANGE := 8.0
const RIFLE_RANGE := 40.0
## Seconds the autopilot must prefer a different weapon before it acts on the
## preference. A player picks a weapon and lives with it; re-deciding every
## frame is indecision, not policy.
const SWITCH_COMMIT := 2.0
## Seconds between reserve samples. Coarse on purpose — this is looking for a
## trend across a round, not a transient after one kill.
const TIMELINE_INTERVAL := 15.0

## How close the stand-in has to get to a waypoint before it takes the next.
const WAYPOINT_REACHED := 1.2
## How long it will chase one roaming destination before picking another. A
## stand-in that cannot reach its goal must not spend the whole run trying.
const ROAM_PATIENCE := 25.0
## A contact is a zombie within this. Separate from ENGAGE_RANGE, which is
## about whether a shot is worth taking; this is about whether the player is
## being pressed, which is the pacing question.
const CONTACT_RANGE := 6.0
## Deadband on the movement decision, so a direction almost perpendicular to
## an axis does not chatter that key on and off every frame.
const MOVE_DEADBAND := 0.25

const MOVE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right"
]

var _game: Game
var _started := false
var _elapsed := 0.0
var _seconds := 150.0
var _only := ""
var _immortal := true
## Fixed by default so two runs of the same build agree; --seed= to resample.
var _seed := 20260922
## Declines every perk, isolating what the base economy pays on its own.
var _no_upgrades := false
var _last_wanted: WeaponTypes.Kind = WeaponTypes.Kind.PISTOL
var _wanted_for := 0.0
## An upgrade offered but not yet taken. Applied a frame late on purpose — see
## _instrument.
var _pending_upgrade := -1

## Per kind: rounds fired, seconds held, and when it first ran completely out.
var _per_weapon := {}
## Seconds the whole arsenal has been empty, and how many separate times.
var _dry_total := 0.0
var _dry_episodes := 0
var _dry_longest := 0.0
var _dry_current := 0.0
var _was_dry := false
## The same bookkeeping for the state the player would call being out: the
## weapon in hand is empty while another still has rounds. This is what
## `is_arsenal_dry()` named before it was tightened to require all three.
var _held_dry_total := 0.0
var _held_dry_episodes := 0
var _held_dry_longest := 0.0
var _held_dry_current := 0.0
var _was_held_dry := false
## Switches the autopilot was forced into by running the held weapon out, as
## opposed to switches it chose for range. A forced switch is the design
## working; the question is how often it happens.
var _forced_switches := 0

var _melee_swings := 0
var _melee_hits := 0
var _reloads := 0
var _reserve_gained := 0
## Seconds the autopilot spent with a visible target in range — the only part
## of the clock in which ammunition is actually being spent.
var _engaged := 0.0
var _last_delta := 0.0
## Seconds of clear shots lost to each cause.
var _blocked_switching := 0.0
var _blocked_reloading := 0.0
var _blocked_empty := 0.0
var _blocked_cooldown := 0.0
## Reserve per weapon, sampled on a slow clock. Totals hide the failure this
## is looking for: with income going to the emptiest weapon, one weapon can
## quietly accumulate while the player fights with the other two, and "the
## fallback is always full" is its own flavour of infinite ammunition.
var _reserve_timeline: Array[Dictionary] = []
var _timeline_remaining := 0.0
var _alive_samples := 0
var _alive_total := 0

## Whether the stand-in walks the map. On by default: it used to stand where it
## spawned, which was a fair stand-in for an open cave the zombies crossed in
## seconds and is no stand-in at all for a labyrinth. Rooted on the authored
## map it measured 17.9 zombies alive and 2% engaged time — a reading about the
## probe, not about the game.
var _roam := true
var _roam_path: PackedVector3Array = PackedVector3Array()
var _roam_index := 0
var _roam_age := 0.0
## Seconds spent with a zombie inside CONTACT_RANGE.
var _contact_time := 0.0
## Distance to the nearest zombie, sampled every frame, for a mean.
var _nearest_total := 0.0
var _nearest_samples := 0
var _distance_walked := 0.0
## Seeded so a run can be repeated. The roaming destinations were drawn from
## the global RNG at first, which made every run a different walk and every
## comparison between two settings a comparison of two different walks.
var _rng := RandomNumberGenerator.new()
var _last_position := Vector3.ZERO


func _initialize() -> void:
	_parse_arguments()
	_game = (load(GAME_SCENE) as PackedScene).instantiate()
	root.add_child(_game)


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			_seconds = float(argument.split("=")[1])
		elif argument.begins_with("--only="):
			_only = argument.split("=")[1].to_lower()
		elif argument == "--mortal":
			_immortal = false
		elif argument == "--stationary":
			_roam = false
		elif argument.begins_with("--seed="):
			_seed = int(argument.split("=")[1])
		elif argument == "--no-upgrades":
			_no_upgrades = true


func _process(delta: float) -> bool:
	if _game == null or _game.weapon == null:
		return false

	if not _started:
		_started = true
		DeterministicSettings.apply(root)
		_rng.seed = _seed
		Engine.time_scale = TIME_SCALE
		# Endless, because an extraction round ends on its own clock and stops
		# the spawner. The first attempt at this measurement ran in extraction
		# mode and spent most of its window on a round that had already been
		# won, which is how it reported an ammunition supply that never ran out.
		_game.mode = GameSettings.Mode.ENDLESS
		_game.start_round()
		# start_round calls _apply_mode, which puts the mode back to whatever the
		# settings say — so asking for endless before it is not enough. Pushing
		# the win clock past the measurement window is what actually stops the
		# round ending and the spawner freezing mid-measurement. A previous run
		# spent its last sixty seconds on a round that had already been won.
		_game.round_duration = _seconds * 4.0
		_game.time_remaining = _game.round_duration
		_instrument()
		return false

	# Everything measured is in simulated seconds. `delta` already carries the
	# time scale, so the clock and the game agree without a correction here.
	_elapsed += delta

	_keep_playing()

	_last_delta = delta
	_drive(delta)
	_roam_step(delta)
	_sample(delta)

	if _elapsed < _seconds:
		return false

	_report()
	return true


## Refuse to sit in a paused tree.
##
## A level-up pauses the game and waits for a choice nobody is here to make.
## Taking the offer a frame late was not enough: the menu can re-pause, and a
## paused tree stops `Weapon._process`, so `_cooldown_remaining` never ticks and
## every shot is refused. Twice now that has shown up as a run reporting 93%
## engaged time and 25 rounds fired in three minutes — the probe looked busy and
## was frozen. Checking the condition every frame rather than reacting to the
## event is the difference between handling the case and hoping.
##
## This is a probe, so it is allowed to be blunt about it.
func _keep_playing() -> void:
	if _pending_upgrade == -2:
		# Declined. Closing the menu unpauses, but handing the weapon and the
		# player back is a separate job — _apply_upgrade ends by doing it, and
		# skipping it leaves the stand-in alive, unpaused and unable to shoot,
		# which would read as an ammunition surplus.
		_pending_upgrade = -1
		_game.upgrade_menu.close()
		_game._on_resumed()
	elif _pending_upgrade >= 0:
		var upgrade := _pending_upgrade
		_pending_upgrade = -1
		_game._apply_upgrade(upgrade)

	if not paused:
		return

	paused = false
	_game.weapon.set_input_enabled(true)
	_game.player.set_look_enabled(true)


func _instrument() -> void:
	var weapon: Weapon = _game.weapon

	for kind in WeaponTypes.order():
		_per_weapon[kind] = {
			"name": WeaponTypes.display_name(kind),
			"fired": 0,
			"held": 0.0,
			"emptied_at": -1.0,
			"emptied": 0,
			"had_rounds": true,
			"loadout": _loadout_size(kind),
		}

	weapon.fired.connect(func(_from: Vector3, _to: Vector3) -> void:
		_per_weapon[weapon.kind].fired += 1
	)
	weapon.melee_swung.connect(func(hit: bool, _staggered: bool, _at: Vector3) -> void:
		_melee_swings += 1
		if hit:
			_melee_hits += 1
	)
	# A level-up takes the weapon out of the player's hands until a choice is
	# made, and nobody is here to make one. Taking the first offer immediately
	# keeps the run going; which upgrade lands is noise next to whether the
	# ammunition holds out, and the upgrades that touch ammunition are declared
	# in the report by the reserve figures themselves.
	_game.progression.levelled_up.connect(
		func(_level: int, choices: Array[Dictionary]) -> void:
			if _no_upgrades:
				# The level-up still has to be dismissed or the round stays
				# paused waiting for a choice; it just does not take one.
				_pending_upgrade = -2
				return
			if not choices.is_empty():
				_pending_upgrade = choices[0].id
	)
	weapon.reload_started.connect(func(_duration: float) -> void: _reloads += 1)
	weapon.scrounged.connect(func(amount: int) -> void: _reserve_gained += amount)


## Magazine plus reserve for a kind, read out of the weapon's own slots so the
## figure reflects the difficulty scaling rather than the raw table.
func _loadout_size(kind: WeaponTypes.Kind) -> int:
	var slot: Dictionary = _game.weapon._slots.get(kind, {})
	if slot.is_empty():
		return 0
	return int(slot.magazine) + int(slot.reserve)


func _alive() -> Array:
	return _game.spawner._alive


func _nearest() -> Zombie:
	var best: Zombie = null
	var best_distance := ENGAGE_RANGE

	for zombie in _alive():
		if not is_instance_valid(zombie):
			continue
		var distance: float = zombie.global_position.distance_to(
			_game.player.global_position
		)
		if distance < best_distance:
			best_distance = distance
			best = zombie

	return best


## Stand in for the player for one frame.
func _drive(_unused: float) -> void:
	var player: Player = _game.player
	var weapon: Weapon = _game.weapon

	# Keeping the stand-in alive isolates the question. Survivability is a
	# different measurement with a different tool.
	if _immortal:
		player.health.heal(player.health.max_health)

	var target := _nearest()
	if target == null:
		return

	var aim: Vector3 = target.global_position + Vector3.UP * 1.1
	var offset: Vector3 = aim - player.head.global_position
	var flat := Vector2(offset.x, offset.z).length()

	player.rotation.y = atan2(-offset.x, -offset.z)
	player.head.rotation.x = clampf(atan2(offset.y, flat), -1.4, 1.4)

	var distance: float = offset.length()
	var wanted := _preferred_kind(distance)

	# Commit to a weapon rather than re-deciding every frame.
	#
	# Without this the probe measures nothing but its own indecision. The first
	# run with diagnostics spent 82 of 86 engaged seconds mid-swap: a zombie
	# walking towards you crosses the 8m shotgun boundary constantly, and each
	# crossing started a fresh 0.55-0.85s raise, so the autopilot swapped for
	# almost the whole round and fired 22 rounds in 100 seconds. A player picks
	# a weapon and lives with it for a few seconds; so does this now.
	#
	# Running out is the exception — that switch is forced and immediate,
	# because it is exactly the moment the design is trying to create.
	if wanted != weapon.kind:
		var forced := weapon.magazine_ammo <= 0 and weapon.reserve_ammo <= 0
		_wanted_for = 0.0 if wanted != _last_wanted else _wanted_for + _last_delta
		_last_wanted = wanted

		if forced or _wanted_for >= SWITCH_COMMIT:
			if not weapon.is_switching():
				if forced:
					_forced_switches += 1
				weapon.equip(wanted)
				_wanted_for = 0.0
			return
	else:
		_wanted_for = 0.0
		_last_wanted = wanted

	if weapon.is_switching():
		return

	if weapon.is_arsenal_dry():
		if distance <= weapon.melee_range:
			weapon.try_melee()
		return

	if distance > weapon.shot_range:
		return
	if not _can_see(aim):
		# A player does not empty a magazine into the rock between them and a
		# groan. Without this the probe measures the arena's sightlines rather
		# than the ammunition supply.
		return

	_engaged += _last_delta

	# Why a frame with a clear shot did not produce one. Without this the probe
	# can report "engaged 96% of the run, 24 rounds fired" and leave no way to
	# tell a starved spawner from a weapon that was busy.
	if weapon.is_switching():
		_blocked_switching += _last_delta
	elif weapon.is_reloading():
		_blocked_reloading += _last_delta
	elif weapon.magazine_ammo <= 0:
		_blocked_empty += _last_delta
	elif not weapon.try_fire():
		_blocked_cooldown += _last_delta


## True when a shot taken now would reach something worth hitting.
##
## Asks the question the same way the weapon does — mask `1 | 4`, the owner
## excluded — rather than inventing a second rule. The previous version used
## mask 1 and treated "nothing hit" as visible, which was wrong twice over: a
## nearer zombie between you and the one you picked counted as a clear shot,
## and, far worse, a zombie standing *on* you counted as cover.
##
## That second case is why an earlier run reported 9.4 engaged seconds out of
## 180 while nineteen of twenty zombies were hunting and within three metres.
## `intersect_ray` does not report a shape whose interior the ray starts in
## unless `hit_from_inside` is set, so a target close enough to be touching the
## player was invisible to a query that worked perfectly at ten metres — the
## probe was blind at exactly the range the game is most dangerous.
func _can_see(aim: Vector3) -> bool:
	var origin: Vector3 = _game.player.head.global_position

	# A ray this short is degenerate, and anything this close is in contact.
	if origin.distance_to(aim) < 0.2:
		return true

	var query := PhysicsRayQueryParameters3D.create(origin, aim)
	query.collision_mask = 1 | 4
	query.exclude = [_game.player.get_rid()]
	query.hit_from_inside = true

	var hit := _game.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true

	# Whatever the ray stopped on is what the bullet would stop on. If that is
	# something that can be damaged, the shot is worth taking even when it is
	# not the zombie that was aimed at.
	var collider: Node = hit.get("collider")
	return collider != null and collider.has_method("take_damage")


## Which weapon the autopilot reaches for, given the range and what is loaded.
##
## Falls through to anything with rounds left, which is the behaviour that makes
## "how often is the player fully dry" mean what it says: a dry weapon is only
## counted against the run once every weapon is dry.
func _preferred_kind(distance: float) -> WeaponTypes.Kind:
	var weapon: Weapon = _game.weapon
	var order: Array = []

	if _only != "":
		order = [_kind_named(_only)]
	elif distance <= SHOTGUN_RANGE:
		order = [
			WeaponTypes.Kind.SHOTGUN, WeaponTypes.Kind.RIFLE,
			WeaponTypes.Kind.PISTOL,
		]
	elif distance <= RIFLE_RANGE:
		order = [
			WeaponTypes.Kind.RIFLE, WeaponTypes.Kind.PISTOL,
			WeaponTypes.Kind.SHOTGUN,
		]
	else:
		order = [
			WeaponTypes.Kind.PISTOL, WeaponTypes.Kind.RIFLE,
			WeaponTypes.Kind.SHOTGUN,
		]

	for kind in order:
		if _has_rounds(kind):
			return kind

	return weapon.kind


func _kind_named(name: String) -> WeaponTypes.Kind:
	for kind in WeaponTypes.order():
		if WeaponTypes.display_name(kind).to_lower() == name:
			return kind
	return WeaponTypes.Kind.PISTOL


func _has_rounds(kind: WeaponTypes.Kind) -> bool:
	var weapon: Weapon = _game.weapon
	if kind == weapon.kind:
		return weapon.magazine_ammo > 0 or weapon.reserve_ammo > 0
	var slot: Dictionary = weapon._slots.get(kind, {})
	if slot.is_empty():
		return false
	return int(slot.magazine) > 0 or int(slot.reserve) > 0


func _sample(delta: float) -> void:
	var weapon: Weapon = _game.weapon
	_per_weapon[weapon.kind].held += delta

	for kind in _per_weapon:
		var entry: Dictionary = _per_weapon[kind]
		var has := _has_rounds(kind)
		if entry.emptied_at < 0.0 and not has:
			entry.emptied_at = _elapsed
		# How many separate times this weapon bottomed out, not just the first.
		# A loadout that empties once is a duration; one that empties six times
		# is a rhythm, and only the second is a resource decision.
		if not has and entry.had_rounds:
			entry.emptied += 1
		entry.had_rounds = has

	_timeline_remaining -= delta
	if _timeline_remaining <= 0.0:
		_timeline_remaining = TIMELINE_INTERVAL
		var row := {"at": _elapsed}
		for kind in WeaponTypes.order():
			row[kind] = weapon.reserve_for(kind)
		_reserve_timeline.append(row)

	_alive_samples += 1
	_alive_total += _game.spawner.get_alive_count()

	_sample_pressure(delta)

	var dry := weapon.is_arsenal_dry()

	if dry:
		_dry_total += delta
		_dry_current += delta
		if not _was_dry:
			_dry_episodes += 1
	elif _was_dry:
		_dry_longest = maxf(_dry_longest, _dry_current)
		_dry_current = 0.0

	_was_dry = dry
	_sample_held_dry(delta)


## Track the state the *player* would call being out: the weapon in your hands
## has nothing, while something else still does.
##
## This is the condition `is_arsenal_dry()` used to name before it was tightened
## to require all three weapons empty. Measuring both separately is the only way
## to settle whether the old rule was an accidental cushion or the only version
## of the check that could ever fire in practice — and whether the gap between
## them is a real experience or an artifact of a policy that hoards shells in a
## weapon it never draws.
##
## Deliberately measured and not acted on. The autopilot still only swings the
## melee on arsenal-dry, because that is the shipped rule and a probe that
## quietly played by a different one would be measuring a game nobody is going
## to ship.
func _sample_held_dry(delta: float) -> void:
	var weapon: Weapon = _game.weapon
	var held_empty: bool = weapon.magazine_ammo <= 0 and weapon.reserve_ammo <= 0

	# Only counts while an alternative exists. With nothing anywhere this is
	# arsenal-dry, which is already counted above, and double-counting it would
	# make the comparison between the two rules meaningless.
	var elsewhere := false
	for kind in WeaponTypes.order():
		if kind != weapon.kind and _has_rounds(kind):
			elsewhere = true
			break

	var held_dry := held_empty and elsewhere

	if held_dry:
		_held_dry_total += delta
		_held_dry_current += delta
		if not _was_held_dry:
			_held_dry_episodes += 1
	elif _was_held_dry:
		_held_dry_longest = maxf(_held_dry_longest, _held_dry_current)
		_held_dry_current = 0.0

	_was_held_dry = held_dry


func _report() -> void:
	Engine.time_scale = 1.0
	_dry_longest = maxf(_dry_longest, _dry_current)

	var accuracy := 0.0
	if _game.shots_fired > 0:
		accuracy = 100.0 * float(_game.shots_hit) / float(_game.shots_fired)

	print("")
	print("AMMO ECONOMY — %.0fs simulated%s" % [
		_elapsed, "" if _only == "" else (", %s only" % _only)
	])
	print("weapon    loadout  fired  held(s)  first empty(s)  times empty")

	for kind in _per_weapon:
		var entry: Dictionary = _per_weapon[kind]
		print("%-9s %7d %6d %8.1f  %-14s %d" % [
			entry.name, entry.loadout, entry.fired, entry.held,
			"never" if entry.emptied_at < 0.0 else "%.1f" % entry.emptied_at,
			entry.emptied,
		])

	print("")
	print("roamed               %.0fm walked, %s" % [
		_distance_walked, "roaming" if _roam else "stationary"
	])
	print("nearest zombie       %.1fm mean, in contact (<%.0fm) %.0fs of %.0fs (%.0f%%)" % [
		_nearest_total / maxf(1.0, float(_nearest_samples)),
		CONTACT_RANGE, _contact_time, _seconds,
		100.0 * _contact_time / maxf(1.0, _seconds)
	])
	print("engaged time         %.1fs of %.0fs (%.0f%%), mean %.1f zombies alive" % [
		_engaged, _elapsed, 100.0 * _engaged / maxf(_elapsed, 0.01),
		float(_alive_total) / maxf(float(_alive_samples), 1.0)
	])
	print("kills                %d" % _game.kills)
	print("shots fired / hit    %d / %d (%.0f%% accuracy)" % [
		_game.shots_fired, _game.shots_hit, accuracy
	])
	print("reloads              %d" % _reloads)
	print("scrounged rounds     %d" % _reserve_gained)
	print("melee swings / hits  %d / %d" % [_melee_swings, _melee_hits])
	print("fully dry            %d episode(s), %.1fs total (%.0f%% of the run)" % [
		_dry_episodes, _dry_total, 100.0 * _dry_total / maxf(_elapsed, 0.01)
	])
	print("longest dry spell    %.1fs" % _dry_longest)

	# The comparison the whole metric exists for. `is_arsenal_dry()` gates the
	# melee, dry_resupply and the Screamer-versus-a-dry-player interaction; the
	# held-weapon figure is what those systems would have fired on under the
	# older, looser rule. If arsenal-dry stays at zero while held-dry does not,
	# the emergency systems are gated on a condition the game cannot reach.
	_held_dry_longest = maxf(_held_dry_longest, _held_dry_current)
	print("held weapon dry      %d episode(s), %.1fs total (%.0f%% of the run)" % [
		_held_dry_episodes, _held_dry_total,
		100.0 * _held_dry_total / maxf(_elapsed, 0.01)
	])
	print("longest held-dry     %.1fs" % _held_dry_longest)
	print("forced switches      %d (ran the held weapon out)" % _forced_switches)
	print("clear shots lost to  switching %.1fs, reloading %.1fs, empty mag %.1fs, cooldown %.1fs" % [
		_blocked_switching, _blocked_reloading, _blocked_empty, _blocked_cooldown
	])
	print("round state at end   %d (0 = still playing)" % _game.state)
	_report_reserves()
	quit(0)


## Reserve per weapon across the round, as a curve rather than a total.
##
## A totals-only report cannot see the failure this is looking for. Income now
## goes to whichever weapon is emptiest relative to its own ceiling, which is
## what stops the fallback starving — but it means the weapon with the most room
## absorbs the most, and the pistol's ceiling of 72 is the largest of the three.
## If it quietly fills while the player fights with the other two, that is a
## second flavour of infinite ammunition wearing a different hat, and it would
## be completely invisible in an arsenal-wide figure.
##
## Printed as absolute rounds and as a percentage of each weapon's own ceiling,
## because the routing ranks on the percentage and that is the number that
## explains why the rounds went where they did.
func _report_reserves() -> void:
	if _reserve_timeline.is_empty():
		return

	var weapon: Weapon = _game.weapon

	print("")
	print("RESERVE OVER TIME — rounds (% of that weapon's ceiling)")

	var header := "    t   "
	for kind in WeaponTypes.order():
		header += "%-16s" % WeaponTypes.display_name(kind)
	print(header)

	for row in _reserve_timeline:
		var line := "%5.0fs  " % row.at
		for kind in WeaponTypes.order():
			var reserve: int = row[kind]
			var ceiling: int = weapon.reserve_ceiling_for(kind)
			line += "%-16s" % ("%d (%.0f%%)" % [
				reserve, 100.0 * float(reserve) / maxf(float(ceiling), 1.0)
			])
		print(line)

	# The verdict the curve exists to deliver: did anything end the round
	# holding materially more than it started with?
	print("")
	var first: Dictionary = _reserve_timeline[0]
	var last: Dictionary = _reserve_timeline[-1]

	for kind in WeaponTypes.order():
		var change: int = int(last[kind]) - int(first[kind])
		var verdict := "steady"
		if change > 0:
			verdict = "ACCUMULATING"
		elif change < 0:
			verdict = "draining"
		print("%-9s %+4d rounds across the run — %s" % [
			WeaponTypes.display_name(kind), change, verdict
		])


## Walk the map, so the measurement is about the level and not about a statue.
##
## Movement goes through the real input actions rather than by writing to the
## player's position, because the player's own _physics_process owns speed,
## acceleration, crouch and the collide-and-slide. A probe that teleports its
## stand-in measures a player who cannot be blocked by a doorway, which on a
## labyrinth is the entire question.
##
## The destination is any walkable point far enough to be a journey. What the
## stand-in is doing is closer to "sweep the level" than to "hunt", which is
## what a player in an extraction round is actually doing between fights.
func _roam_step(delta: float) -> void:
	var player: Player = _game.player

	if not _roam:
		_release_movement()
		return

	_roam_age += delta

	if _roam_index >= _roam_path.size() or _roam_age > ROAM_PATIENCE:
		_choose_destination()

	if _roam_index >= _roam_path.size():
		_release_movement()
		return

	var here := player.global_position
	var waypoint: Vector3 = _roam_path[_roam_index]

	# Compared on the flat. The path rides the navmesh and the player rides the
	# floor, and the height difference between the two never closes.
	if Vector2(waypoint.x - here.x, waypoint.z - here.z).length() < WAYPOINT_REACHED:
		_roam_index += 1
		if _roam_index >= _roam_path.size():
			_release_movement()
			return
		waypoint = _roam_path[_roam_index]

	_press_towards(waypoint - here)


## Hold whichever movement keys carry the stand-in in a world direction.
##
## Translated into the player's own frame first, because the player moves
## relative to where it is looking and the autopilot is looking at whatever it
## is shooting — which is usually not where it is going. That mismatch is the
## point: it is how a person plays, backing away from one thing while facing
## another.
func _press_towards(world_direction: Vector3) -> void:
	var player: Player = _game.player
	var flat := Vector3(world_direction.x, 0.0, world_direction.z)

	if flat.length_squared() < 0.0001:
		_release_movement()
		return

	var local := player.global_transform.basis.inverse() * flat.normalized()

	_hold(&"move_right", local.x > MOVE_DEADBAND)
	_hold(&"move_left", local.x < -MOVE_DEADBAND)
	# Godot's forward is -Z, and move_back is the positive half of the axis.
	_hold(&"move_back", local.z > MOVE_DEADBAND)
	_hold(&"move_forward", local.z < -MOVE_DEADBAND)


func _hold(action: StringName, wanted: bool) -> void:
	if wanted == Input.is_action_pressed(action):
		return

	if wanted:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_movement() -> void:
	for action in MOVE_ACTIONS:
		if Input.is_action_pressed(action):
			Input.action_release(action)


## Pick somewhere worth walking to, and the route there.
func _choose_destination() -> void:
	_roam_path = PackedVector3Array()
	_roam_index = 0
	_roam_age = 0.0

	var arena: Arena = _game.arena
	var map_rid := arena.get_navigation_map()
	if not map_rid.is_valid():
		return

	var here: Vector3 = _game.player.global_position
	var candidates: Array[Vector3] = arena.spawn_points

	if candidates.is_empty():
		return

	# Tried a few times rather than once: the nearest spawn point is often the
	# room the stand-in is already in, and walking two metres and stopping is
	# not a sweep of anything.
	for attempt in 8:
		var goal: Vector3 = candidates[_rng.randi_range(0, candidates.size() - 1)]
		if here.distance_to(goal) < 15.0:
			continue

		var path := NavigationServer3D.map_get_path(map_rid, here, goal, true)
		if path.size() >= 2:
			_roam_path = path
			_roam_index = 1
			return


## How hard the level is pressing, as distinct from how much it is shooting.
##
## Engaged time answers "was there a shot worth taking". These answer "was
## anything near me", which on a labyrinth is a different question with a very
## different answer: a large live population separated from the player by four
## corners is a number on a HUD rather than a threat.
func _sample_pressure(delta: float) -> void:
	var here: Vector3 = _game.player.global_position

	if _last_position != Vector3.ZERO:
		_distance_walked += Vector2(
			here.x - _last_position.x, here.z - _last_position.z
		).length()
	_last_position = here

	var nearest := INF
	for zombie in _game.spawner.get_children():
		if not (zombie is Zombie) or not is_instance_valid(zombie):
			continue
		nearest = minf(nearest, here.distance_to((zombie as Zombie).global_position))

	if is_inf(nearest):
		return

	_nearest_total += nearest
	_nearest_samples += 1

	if nearest <= CONTACT_RANGE:
		_contact_time += delta
