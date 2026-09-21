extends SceneTree

## Verifies that the five archetypes behave differently, rather than merely
## carrying different numbers.
##
## This is the test the stats table cannot write for itself. verify_zombie_types
## already proves no two kinds share a health pool or a speed, and five kinds
## can pass that while all doing exactly the same thing: walk the shortest path
## at the player, bite on arrival, forget them on a timer. That failure is
## completely silent — the game still runs, the horde still kills you, and the
## only symptom is that target priority stops being a decision.
##
## So everything asserted below is a *structural* difference: something one kind
## does that another simply cannot. Numbers are only ever checked where a number
## is the mechanism (a stagger of zero seconds is not a short stagger, it is the
## absence of staggering).
##
##   Godot --headless --script tests/manual/verify_zombie_behaviour.gd

const ZOMBIE_SCENE := "res://src/gameplay/zombie/zombie.tscn"

## Directions a zombie might approach a stationary player from. Sixteen points
## on a circle, fixed rather than random, so the flanking comparison below is
## the same every run.
const APPROACH_SAMPLES := 16

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	test_every_kind_owns_a_rule_no_other_kind_has()
	test_a_brute_cannot_be_staggered_but_a_shambler_can()
	test_a_brute_ignores_a_decoy_a_shambler_chases()
	test_a_runner_that_misses_keeps_going_and_a_shambler_stops()
	test_a_runner_forgets_the_player_soonest_and_a_brute_latest()
	test_shamblers_pull_together_and_runners_do_not()
	test_a_stalker_approaches_from_outside_the_view_more_than_a_shambler()
	test_a_stalker_backs_off_when_looked_at()
	test_a_stalker_never_tells_anyone_anything()
	test_a_screamer_runs_to_other_zombies_instead_of_the_player()
	test_a_screamers_alarm_recruits_the_ones_that_can_hear_it()
	test_a_losing_zombie_keeps_leading_the_player()
	test_a_zombie_that_loses_the_player_works_the_area()
	test_every_kind_still_paths_and_still_attacks()
	test_stopping_the_round_stops_the_zombies()
	test_a_stopped_zombie_can_be_put_back_to_work()
	test_a_screamer_will_not_cross_the_player_to_reach_an_ally()
	test_a_screamer_with_nobody_near_backs_away_instead()
	test_a_watched_stalker_keeps_one_retreat_direction()
	test_a_screamer_is_silent_while_it_draws_breath()
	test_a_stalker_that_is_already_on_you_ignores_being_looked_at()

	_report()
	return true


## D3. ZombieSpawner.stop() used to set a flag that only governed spawning, so
## every zombie already in the cave carried on pathing, biting and groaning
## behind the results overlay — damage flashes, hurt audio and contact pings
## firing on a screen nobody is playing, at the CPU cost of a full horde.
##
## The round is over: the horde has to be over with it.
func test_stopping_the_round_stops_the_zombies() -> void:
	# Arrange: a zombie in range of a target, mid-fight.
	var spawner := _spawner()
	var zombie := _zombie_in(ZombieTypes.Kind.SHAMBLER, spawner)
	var dummy := _marker(Vector3(0.9, 0.0, 0.0))
	zombie.set_target(dummy)
	zombie.awareness = Zombie.Awareness.HUNTING
	spawner._alive = [zombie]

	var hits := [0]
	var groans := [0]
	zombie.hit_player.connect(func(_d: float, _p: Vector3) -> void: hits[0] += 1)
	zombie.groaned.connect(func(_at: Vector3) -> void: groans[0] += 1)

	# Act
	spawner.stop()

	# A full attack cycle and a groan that would both have fired a moment ago.
	zombie._tick_attack(0.001)
	zombie._tick_attack(zombie.attack_windup + 0.01)
	zombie._tick_attack(0.01)
	zombie._groan_remaining = 0.0
	zombie._tick_groan(0.01)

	# Assert
	if hits[0] != 0:
		_failures.append(
			"a zombie landed %d hits after the round was stopped — the player is "
			% hits[0] + "taking damage behind the results screen"
		)
	elif groans[0] != 0:
		_failures.append("a zombie was still making noise after the round was stopped")
	elif zombie.is_physics_processing():
		_failures.append(
			"a stopped zombie is still running physics — a full horde is still "
			+ "pathing on a screen nobody is playing"
		)
	elif not zombie.is_stopped:
		_failures.append("stop() did not mark the zombie as stopped")
	else:
		print("PASS: stopping the round freezes the horde as well as the spawning")

	spawner._alive = []
	_free_group(spawner)
	dummy.free()


## The other half of D3, and the part that is easy to break while fixing it:
## restarting has to put a frozen zombie back into the fight. Anything that
## freezes without an inverse turns a stop into a leak.
func test_a_stopped_zombie_can_be_put_back_to_work() -> void:
	# Arrange
	var spawner := _spawner()
	var zombie := _zombie_in(ZombieTypes.Kind.SHAMBLER, spawner)
	var dummy := _marker(Vector3(0.9, 0.0, 0.0))
	zombie.set_target(dummy)
	spawner._alive = [zombie]
	spawner.stop()

	var hits := [0]
	zombie.hit_player.connect(func(_d: float, _p: Vector3) -> void: hits[0] += 1)

	# Act
	zombie.resume_fighting()
	zombie._tick_attack(0.001)
	zombie._tick_attack(zombie.attack_windup + 0.01)
	zombie._tick_attack(0.01)

	# Assert
	if zombie.is_stopped or not zombie.is_physics_processing():
		_failures.append("a resumed zombie was still frozen")
	elif hits[0] == 0:
		_failures.append(
			"a resumed zombie could not land a hit — stopping a round would "
			+ "permanently disarm anything that survived it"
		)
	else:
		print("PASS: a stopped zombie goes back to work when the fight resumes")

	spawner._alive = []
	_free_group(spawner)
	dummy.free()


## D2. The nearest-ally search had no distance cap, so any zombie anywhere in
## the cave counted. If the only other zombie was on the far side of the
## player, the Screamer's destination was on the far side of the player — the
## one kind designed never to approach you would charge straight through you
## to get to it.
func test_a_screamer_will_not_cross_the_player_to_reach_an_ally() -> void:
	# Arrange: player between the Screamer and a distant zombie.
	var group := _group()
	var screamer := _zombie_in(ZombieTypes.Kind.SCREAMER, group)
	var distant_ally := _zombie_in(ZombieTypes.Kind.SHAMBLER, group)
	var player := _marker(Vector3(0.0, 0.0, -10.0))
	screamer.global_position = Vector3.ZERO
	distant_ally.global_position = Vector3(0.0, 0.0, -40.0)
	screamer.set_target(player)
	screamer.awareness = Zombie.Awareness.HUNTING

	# Act
	screamer._compute_separation()
	var goal: Vector3 = screamer._move_goal()

	# Assert
	if goal.is_equal_approx(distant_ally.global_position):
		_failures.append(
			"a Screamer chose an ally %.0fm away on the far side of the player — "
			% screamer.global_position.distance_to(distant_ally.global_position)
			+ "it would path straight through the thing it is running from"
		)
	elif goal.distance_to(player.global_position) \
			< screamer.global_position.distance_to(player.global_position):
		_failures.append(
			"a Screamer's destination is closer to the player (%.1fm) than it is "
			% goal.distance_to(player.global_position) + "itself"
		)
	else:
		print("PASS: a Screamer will not cross the player to reach a distant ally")

	_free_group(group)
	player.free()


## The other consequence of the missing cap: the "nothing to hide behind"
## fallback only ran when the Screamer was the last zombie alive in the whole
## arena, which is not what it was written for. With no ally *nearby* it has to
## back away rather than commit to a march across the map.
func test_a_screamer_with_nobody_near_backs_away_instead() -> void:
	# Arrange: an ally on the Screamer's own side of the player, but far
	# outside any sensible refuge range.
	var group := _group()
	var screamer := _zombie_in(ZombieTypes.Kind.SCREAMER, group)
	var far_ally := _zombie_in(ZombieTypes.Kind.SHAMBLER, group)
	var player := _marker(Vector3(0.0, 0.0, -10.0))
	screamer.global_position = Vector3.ZERO
	far_ally.global_position = Vector3(0.0, 0.0, screamer.cohesion_radius * 6.0)
	screamer.set_target(player)
	screamer.awareness = Zombie.Awareness.HUNTING

	# Act
	screamer._compute_separation()
	var goal: Vector3 = screamer._move_goal()

	# Assert
	if goal.is_equal_approx(far_ally.global_position):
		_failures.append(
			"a Screamer set off on a %.0fm march to the only other zombie in the "
			% far_ally.global_position.z
			+ "cave — the alone-and-backing-away case is unreachable"
		)
	elif goal.distance_to(player.global_position) \
			<= screamer.global_position.distance_to(player.global_position):
		_failures.append(
			"a Screamer with nobody near it did not back away from the player"
		)
	else:
		print("PASS: a Screamer with no ally within %.0fm backs away instead"
			% screamer.cohesion_radius)

	_free_group(group)
	player.free()


## F1. Break-off had no guard against already being retreating, so while the
## player kept looking, every sight tick re-rolled the lateral component of the
## withdrawal and reset the clock. The outward direction was stable and the
## sideways one was not, which reads as a zigzag rather than a retreat.
##
## Continuing to back off while watched is intended. Choosing a new direction
## to back off in, five times a second, is not.
func test_a_watched_stalker_keeps_one_retreat_direction() -> void:
	# Arrange: a Stalker in the player's view, already withdrawing.
	var stalker := _zombie(ZombieTypes.Kind.STALKER)
	var player := _marker(Vector3.ZERO)
	stalker.set_target(player)
	stalker.global_position = Vector3(0.0, 0.0, -6.0)
	stalker._begin_break_off()

	var first_heading := (
		stalker._retreat_position - stalker.global_position
	).normalized()

	# Act: exactly what a second sight tick under a steady gaze does.
	stalker._retreat_remaining = stalker.break_off_duration * 0.5
	stalker._begin_break_off()

	var second_heading := (
		stalker._retreat_position - stalker.global_position
	).normalized()

	# Assert
	if not stalker.is_retreating():
		_failures.append("a Stalker dropped out of its retreat on the second tick")
	elif not first_heading.is_equal_approx(second_heading):
		_failures.append(
			"a watched Stalker re-rolled its withdrawal direction (%v then %v) — "
			% [first_heading, second_heading] + "it would zigzag instead of leaving"
		)
	elif stalker._retreat_remaining < stalker.break_off_duration:
		_failures.append(
			"a Stalker under a steady gaze stopped extending its retreat"
		)
	else:
		print("PASS: a watched Stalker keeps backing off along one heading")

	stalker.free()
	player.free()


## The headline. Every kind must differ from every other kind on at least one
## behavioural rule, not on a stat. If a sixth archetype is ever added as a
## pure stat block, this is what says so.
func test_every_kind_owns_a_rule_no_other_kind_has() -> void:
	# Arrange: the keys that change what a zombie *does*. Speed, health and
	# damage are deliberately absent — differing on those is what this test
	# exists to reject as sufficient.
	var behavioural_keys := [
		"stagger_duration", "noise_floor", "sight_memory_scale",
		"overrun_duration", "cohesion_strength", "flank_distance",
		"breaks_off_when_watched", "alarm_radius_scale", "alarm_interval",
		"flees_to_allies",
	]

	# Act
	var signatures: Dictionary = {}
	for kind in ZombieTypes.Kind.values():
		var definition := ZombieTypes.definition(kind)
		var signature := ""
		for key in behavioural_keys:
			signature += "%s=%s;" % [key, str(definition[key])]
		signatures[signature] = definition.name

	# Assert
	if signatures.size() != ZombieTypes.Kind.values().size():
		_failures.append(
			"%d kinds share only %d distinct behaviour profiles — at least two "
			% [ZombieTypes.Kind.values().size(), signatures.size()]
			+ "of them are the same enemy with different numbers"
		)
	else:
		print("PASS: all %d kinds behave differently, not just differ in stats"
			% signatures.size())


## Shooting a zombie that is winding up is supposed to buy the attack back.
## Against a Brute it is supposed to buy nothing at all, which is what forces
## the player to move instead of shoot.
func test_a_brute_cannot_be_staggered_but_a_shambler_can() -> void:
	# Arrange: both mid-windup, a metre from a target.
	var shambler := _zombie(ZombieTypes.Kind.SHAMBLER)
	var brute := _zombie(ZombieTypes.Kind.BRUTE)
	var dummy := _marker(Vector3(1.0, 0.0, 0.0))
	shambler.set_target(dummy)
	brute.set_target(dummy)
	shambler._begin_windup()
	brute._begin_windup()

	# Act: one bullet each.
	shambler.take_damage(1.0)
	brute.take_damage(1.0)

	# Assert
	if shambler._attack_state != Zombie.AttackState.READY:
		_failures.append(
			"shooting a Shambler mid-windup did not interrupt it — a hit has to "
			+ "buy the attack back or shooting the thing on top of you is pointless"
		)
	elif brute._attack_state != Zombie.AttackState.WINDING_UP:
		_failures.append(
			"a Brute's windup was interrupted by a single bullet — the Brute's "
			+ "whole point is that you cannot shoot your way out of it"
		)
	else:
		print("PASS: a bullet stops a Shambler's swing and does nothing to a Brute's")

	shambler.free()
	brute.free()
	dummy.free()


## The decoy is the tool that peels anything off. A Brute's noise floor is the
## one place it does not work, which turns the decoy from an answer into a
## delaying tactic for everything else in the room.
##
## Only the negative half is asserted here, and deliberately so: proving a
## Shambler *does* chase a quiet noise needs a baked navmesh, because hearing is
## measured along it. verify_noise already does that on the real arena. What
## cannot be checked there is the gate that runs before any of it, so that is
## what this checks — at point-blank range, where nothing except the floor could
## possibly be the reason the Brute is unmoved.
func test_a_brute_ignores_a_decoy_a_shambler_chases() -> void:
	# Arrange
	var shambler := _zombie(ZombieTypes.Kind.SHAMBLER)
	var brute := _zombie(ZombieTypes.Kind.BRUTE)
	var point_blank := brute.global_position
	var quieter_than_a_shot := brute.noise_floor - 0.05

	# Act
	var brute_heard := brute.hear_noise(point_blank, quieter_than_a_shot)

	# Assert
	if brute.noise_floor <= 0.0:
		_failures.append("a Brute has no noise floor — a decoy works on it like anything else")
	elif brute.noise_floor >= 1.0:
		_failures.append(
			"a Brute's noise floor of %.2f is at or above a gunshot, so nothing "
			% brute.noise_floor + "at all can draw it"
		)
	elif brute_heard:
		_failures.append(
			"a Brute reacted to a noise at point-blank range that was quieter "
			+ "than its %.2f floor" % brute.noise_floor
		)
	elif shambler.noise_floor != 0.0:
		_failures.append("a Shambler has a noise floor too — only the Brute should")
	else:
		print("PASS: noises below %.2f are beneath a Brute and never beneath a Shambler"
			% brute.noise_floor)

	shambler.free()
	brute.free()


## A Runner that misses has to be punished for it, or being the fastest thing in
## the cave costs nothing. It sails on past at lunge speed, unable to steer,
## stop, or bite — and that window is the entire counterplay.
func test_a_runner_that_misses_keeps_going_and_a_shambler_stops() -> void:
	# Arrange: both lunging, target already gone.
	var runner := _zombie(ZombieTypes.Kind.RUNNER)
	var shambler := _zombie(ZombieTypes.Kind.SHAMBLER)
	var far_away := _marker(Vector3(0.0, 0.0, -200.0))
	runner.set_target(far_away)
	shambler.set_target(far_away)
	runner._begin_lunge()
	shambler._begin_lunge()

	# Act: run each lunge out past its commit window.
	runner._tick_attack(runner.attack_commit_duration + 0.01)
	shambler._tick_attack(shambler.attack_commit_duration + 0.01)

	# Assert
	if shambler._attack_state != Zombie.AttackState.READY:
		_failures.append(
			"a Shambler was still committed after its lunge ended — only the "
			+ "Runner is supposed to overshoot"
		)
	elif runner._attack_state != Zombie.AttackState.OVERRUNNING:
		_failures.append(
			"a Runner stopped dead at the end of its lunge instead of overrunning "
			+ "— the fastest enemy in the game has no weakness without this"
		)
	else:
		print("PASS: a Runner charges past its own lunge; a Shambler pulls up")

	# And the overrun genuinely cannot attack: its target is 200m away, so any
	# hit here would mean the state is not actually committed.
	var hits := [0]
	runner.hit_player.connect(func(_d: float, _p: Vector3) -> void: hits[0] += 1)
	runner._tick_attack(0.05)
	if hits[0] != 0:
		_failures.append("an overrunning Runner still managed to land a hit")

	runner.free()
	shambler.free()
	far_away.free()


## Breaking line of sight has to be worth a different amount against different
## things, or the answer to every enemy is the same corner.
func test_a_runner_forgets_the_player_soonest_and_a_brute_latest() -> void:
	# Arrange
	var runner := _zombie(ZombieTypes.Kind.RUNNER)
	var shambler := _zombie(ZombieTypes.Kind.SHAMBLER)
	var brute := _zombie(ZombieTypes.Kind.BRUTE)

	# Assert
	if not (runner.lose_sight_duration < shambler.lose_sight_duration
			and shambler.lose_sight_duration < brute.lose_sight_duration):
		_failures.append(
			"sight memory is not ordered Runner < Shambler < Brute (%.1f / %.1f / %.1f)"
			% [
				runner.lose_sight_duration, shambler.lose_sight_duration,
				brute.lose_sight_duration
			]
		)
	else:
		print("PASS: hiding buys %.1fs from a Runner and only %.1fs from a Brute"
			% [runner.lose_sight_duration, brute.lose_sight_duration])

	runner.free()
	shambler.free()
	brute.free()


## The Shambler's distinguishing feature is the only one that has to be visible
## at a distance, because it is the kind the player sees most: they arrive in
## loose clumps rather than as a spread of individuals.
func test_shamblers_pull_together_and_runners_do_not() -> void:
	# Arrange: two pairs, each spaced beyond shoving range and inside
	# grouping range, so separation is silent and only cohesion can speak.
	var group := _group()
	var shambler := _zombie_in(ZombieTypes.Kind.SHAMBLER, group)
	var shambler_mate := _zombie_in(ZombieTypes.Kind.SHAMBLER, group)
	shambler.global_position = Vector3.ZERO
	shambler_mate.global_position = Vector3(5.0, 0.0, 0.0)

	var loner_group := _group()
	var runner := _zombie_in(ZombieTypes.Kind.RUNNER, loner_group)
	var runner_mate := _zombie_in(ZombieTypes.Kind.RUNNER, loner_group)
	runner.global_position = Vector3.ZERO
	runner_mate.global_position = Vector3(5.0, 0.0, 0.0)

	# Act
	var shambler_push: Vector3 = shambler._compute_separation()
	var runner_push: Vector3 = runner._compute_separation()

	# Assert
	if shambler_push.x <= 0.0:
		_failures.append(
			"a Shambler 5m from another Shambler was not drawn toward it "
			+ "(push %.2f on X) — the horde would arrive as a spread, not a crowd"
			% shambler_push.x
		)
	elif not runner_push.is_zero_approx():
		_failures.append(
			"a Runner was drawn toward another Runner — only Shamblers group up"
		)
	else:
		print("PASS: Shamblers close up on each other (%.2f m/s); Runners travel alone"
			% shambler_push.x)

	_free_group(group)
	_free_group(loner_group)


## The Stalker's whole character. Measured over a fixed ring of starting
## positions rather than a live chase, so the comparison is exact: for how many
## approach angles does each kind's chosen destination sit outside the cone the
## player is actually looking down?
func test_a_stalker_approaches_from_outside_the_view_more_than_a_shambler() -> void:
	# Arrange: a player at the origin looking down -Z.
	var stalker := _zombie(ZombieTypes.Kind.STALKER)
	var shambler := _zombie(ZombieTypes.Kind.SHAMBLER)
	var player_position := Vector3.ZERO
	var player_facing := Vector3(0.0, 0.0, -1.0)

	# Act
	var stalker_outside := _approaches_from_outside_view(
		stalker, player_position, player_facing
	)
	var shambler_outside := _approaches_from_outside_view(
		shambler, player_position, player_facing
	)

	# Assert
	if shambler_outside != 0:
		_failures.append(
			"a Shambler aimed somewhere other than straight at the player on %d "
			% shambler_outside + "of %d approaches" % APPROACH_SAMPLES
		)
	elif stalker_outside <= shambler_outside:
		_failures.append(
			"a Stalker chose a spot outside the player's view on %d of %d "
			% [stalker_outside, APPROACH_SAMPLES]
			+ "approaches, no better than a Shambler's %d — it is not flanking"
			% shambler_outside
		)
	elif stalker_outside < APPROACH_SAMPLES:
		_failures.append(
			"a Stalker only got behind the player on %d of %d approaches"
			% [stalker_outside, APPROACH_SAMPLES]
		)
	else:
		print("PASS: a Stalker aims behind the player on %d/%d approaches, a Shambler on %d"
			% [stalker_outside, APPROACH_SAMPLES, shambler_outside])

	stalker.free()
	shambler.free()


## Looking straight at one has to be enough to make it leave, or it is just a
## quiet Runner. And nothing else may do this — a whole horde that scatters when
## looked at would be a different game.
func test_a_stalker_backs_off_when_looked_at() -> void:
	# Arrange: a player looking down -Z with a Stalker directly in front.
	var stalker := _zombie(ZombieTypes.Kind.STALKER)
	var player := _marker(Vector3.ZERO)
	stalker.set_target(player)
	stalker.global_position = Vector3(0.0, 0.0, -6.0)
	var watched := stalker._is_being_watched()

	# Act
	stalker._begin_break_off()

	# Assert
	if not watched:
		_failures.append(
			"a Stalker 6m directly in front of the player did not count as watched"
		)
	elif not stalker.is_retreating():
		_failures.append("a Stalker that was looked at did not break off")
	elif stalker._retreat_position.distance_to(player.global_position) \
			<= stalker.global_position.distance_to(player.global_position):
		_failures.append(
			"a Stalker broke off toward the player rather than away from them"
		)
	else:
		print("PASS: a watched Stalker withdraws %.1fm and comes back another way"
			% stalker._retreat_position.distance_to(stalker.global_position))

	# The behaviour must be the Stalker's alone.
	var shambler := _zombie(ZombieTypes.Kind.SHAMBLER)
	if shambler.breaks_off_when_watched:
		_failures.append("a Shambler also breaks off when watched")

	shambler.free()
	stalker.free()
	player.free()


## A chamber with a Stalker in it has to sound empty. If it could shout, the
## crowd would tell the player exactly what the Stalker spent its whole design
## trying not to.
func test_a_stalker_never_tells_anyone_anything() -> void:
	# Arrange
	var stalker := _zombie(ZombieTypes.Kind.STALKER)
	var player := _marker(Vector3(0.0, 0.0, -3.0))
	stalker.set_target(player)
	stalker.alarm_radius = 0.0
	stalker.awareness = Zombie.Awareness.HUNTING
	var alarms := [0]
	stalker.raised_alarm.connect(
		func(_z: Zombie, _at: Vector3) -> void: alarms[0] += 1
	)

	# Act: force a groan, which is how every other kind alerts the crowd.
	stalker._groan_remaining = 0.0
	stalker._tick_groan(0.01)

	# Assert
	if alarms[0] != 0:
		_failures.append(
			"a hunting Stalker raised the alarm — the one enemy that is supposed "
			+ "to keep what it knows to itself"
		)
	elif ZombieTypes.definition(ZombieTypes.Kind.STALKER).alarm_radius_scale != 0.0:
		_failures.append("the Stalker's alarm radius scale is not zero")
	else:
		print("PASS: a hunting Stalker stays silent")

	stalker.free()
	player.free()


## The Screamer does not fight. It puts a body between itself and the player and
## shouts from behind it, which is what makes killing it a positioning problem
## and not just an aiming one.
func test_a_screamer_runs_to_other_zombies_instead_of_the_player() -> void:
	# Arrange: a Screamer between the player and another zombie.
	var group := _group()
	var screamer := _zombie_in(ZombieTypes.Kind.SCREAMER, group)
	var ally := _zombie_in(ZombieTypes.Kind.SHAMBLER, group)
	var player := _marker(Vector3(0.0, 0.0, -10.0))
	screamer.global_position = Vector3.ZERO
	# Behind the Screamer relative to the player, and inside the range at which
	# a neighbour counts as somewhere to hide. Derived rather than typed in, so
	# retuning that range cannot silently move the ally out of reach and turn
	# this into a test of the fallback instead.
	ally.global_position = Vector3(0.0, 0.0, screamer.cohesion_radius * 0.75)
	screamer.set_target(player)
	screamer.awareness = Zombie.Awareness.HUNTING

	# Act: the neighbour scan is what finds the ally, and it runs on the
	# repath cadence rather than every frame.
	screamer._compute_separation()
	var goal: Vector3 = screamer._move_goal()

	# Assert
	if goal.is_equal_approx(player.global_position):
		_failures.append(
			"a hunting Screamer walked straight at the player — it is supposed "
			+ "to be the one kind that will not close with you"
		)
	elif not goal.is_equal_approx(ally.global_position):
		_failures.append(
			"a hunting Screamer went to %v instead of to the zombie at %v"
			% [goal, ally.global_position]
		)
	else:
		print("PASS: a hunting Screamer runs to the nearest zombie, not to the player")

	_free_group(group)
	player.free()


## The mechanic the whole archetype exists for, and the half of it that is easy
## to get wrong: an alarm that reached everybody would make the Screamer a
## global "you lose" button rather than a thing you can outrun.
func test_a_screamers_alarm_recruits_the_ones_that_can_hear_it() -> void:
	# Arrange: a spawner, a Screamer, one zombie inside the scream and one
	# outside it. Distances are derived from the tuning rather than typed in,
	# so retuning the alarm cannot silently make this test meaningless.
	var spawner := _spawner()
	var screamer := _zombie_in(ZombieTypes.Kind.SCREAMER, spawner)
	var scale: float = ZombieTypes.definition(ZombieTypes.Kind.SCREAMER).alarm_radius_scale
	screamer.alarm_radius = spawner.alert_radius * scale

	var within := _zombie_in(ZombieTypes.Kind.SHAMBLER, spawner)
	var beyond := _zombie_in(ZombieTypes.Kind.SHAMBLER, spawner)
	screamer.global_position = Vector3.ZERO
	within.global_position = Vector3(screamer.alarm_radius * 0.5, 0.0, 0.0)
	beyond.global_position = Vector3(screamer.alarm_radius * 1.5, 0.0, 0.0)
	spawner._alive = [screamer, within, beyond]

	var believed := Vector3(3.0, 0.0, 4.0)

	# Act: exactly what a scream does.
	spawner._on_alarm_raised(screamer, believed)

	# Assert
	if not within.is_investigating():
		_failures.append(
			"a zombie %.1fm from a Screamer did not react to the scream"
			% within.global_position.x
		)
	elif not within.last_known_position.is_equal_approx(believed):
		_failures.append("a recruited zombie did not adopt the Screamer's belief")
	elif beyond.is_investigating():
		_failures.append(
			"a zombie %.1fm away, outside the %.1fm scream, was recruited anyway "
			% [beyond.global_position.x, screamer.alarm_radius]
			+ "— the alarm has no range and the Screamer is unavoidable"
		)
	else:
		print("PASS: a scream reaches %.0fm and recruits only what is inside it"
			% screamer.alarm_radius)

	# And it reaches much further than an ordinary zombie's groan, or it is not
	# worth killing first.
	var shambler := _zombie_in(ZombieTypes.Kind.SHAMBLER, spawner)
	shambler.alarm_radius = spawner.alert_radius
	if screamer.alarm_radius <= shambler.alarm_radius * 2.0:
		_failures.append(
			"a Screamer's alarm (%.0fm) is not meaningfully louder than a "
			% screamer.alarm_radius + "Shambler's (%.0fm)" % shambler.alarm_radius
		)

	spawner._alive = []
	_free_group(spawner)


## Losing sight has to be gradual. Freezing the belief on the spot the player
## was standing made walking in a straight line the reliable way to shake
## anything; a zombie that leads you is dangerous for a few seconds after the
## line breaks, which is when it should be most dangerous.
func test_a_losing_zombie_keeps_leading_the_player() -> void:
	# Arrange: a zombie that has seen the player moving along +X, with the
	# line now broken.
	var zombie := _zombie(ZombieTypes.Kind.SHAMBLER)
	var player := _marker(Vector3(0.0, 0.0, -300.0)) # far enough never to be seen
	zombie.set_target(player)
	zombie.awareness = Zombie.Awareness.HUNTING
	zombie.last_known_position = Vector3(10.0, 0.0, 0.0)
	zombie._seen_velocity = Vector3(4.0, 0.0, 0.0)
	zombie._lost_sight_remaining = zombie.lose_sight_duration
	var believed_at_break := zombie.last_known_position

	# Act: one sight tick with no line of sight.
	zombie._sight_remaining = 0.0
	zombie._tick_senses(0.0)

	# Assert
	if not zombie.is_hunting():
		_failures.append(
			"a zombie dropped out of the hunt on the first tick it lost sight"
		)
	elif zombie.last_known_position.x <= believed_at_break.x:
		_failures.append(
			"a zombie that lost sight froze its belief on the spot (%.2f) instead "
			% zombie.last_known_position.x
			+ "of leading the player — walking in a straight line would shake it"
		)
	else:
		print("PASS: a zombie that loses you keeps leading you (%.1f -> %.1f on X)"
			% [believed_at_break.x, zombie.last_known_position.x])

	zombie.free()
	player.free()


## Searching has to look like searching. A four-second countdown spent standing
## on one coordinate is a body waiting for a timer, and the player reads it as
## one.
func test_a_zombie_that_loses_the_player_works_the_area() -> void:
	# Arrange: a zombie standing on the spot it believes the player to be, so
	# it arrives and gives up on the belief immediately.
	var zombie := _zombie(ZombieTypes.Kind.SHAMBLER)
	var player := _marker(Vector3(0.0, 0.0, -300.0))
	zombie.set_target(player)
	var believed := Vector3(6.0, 0.0, 2.0)
	zombie.global_position = believed
	zombie.receive_alert(believed)

	# Act: arrive, then run the search forward in steps.
	zombie._tick_awareness(0.05)
	var goals: Array[Vector3] = [zombie.last_known_position]
	for _step in 6:
		zombie._tick_awareness(zombie.search_leg_duration + 0.01)
		if zombie.awareness == Zombie.Awareness.UNAWARE:
			break
		goals.append(zombie.last_known_position)

	# Assert
	var distinct := 0
	for index in range(1, goals.size()):
		if not goals[index].is_equal_approx(goals[index - 1]):
			distinct += 1

	var strayed := 0.0
	for goal in goals:
		strayed = maxf(strayed, goal.distance_to(believed))

	if goals.size() < 2 or distinct < 2:
		_failures.append(
			"a searching zombie picked %d destinations in %d legs — it is standing "
			% [distinct + 1, goals.size()] + "still waiting for a timer, not searching"
		)
	elif strayed > zombie.search_radius + zombie.search_overshoot + 0.01:
		_failures.append(
			"a searching zombie wandered %.1fm from the place it was searching"
			% strayed
		)
	else:
		print("PASS: a zombie that finds nothing works %d spots within %.1fm of the belief"
			% [distinct + 1, strayed])

	# And it still gives up eventually rather than searching forever.
	zombie._tick_awareness(zombie.search_duration + 1.0)
	if zombie.awareness != Zombie.Awareness.UNAWARE:
		_failures.append("a search that found nothing never ended")

	zombie.free()
	player.free()


## The floor under everything above. Behaviour that makes a kind distinctive is
## worth nothing if it also makes the kind unable to take part in the fight: all
## five must still choose a goal and still be able to land a hit.
func test_every_kind_still_paths_and_still_attacks() -> void:
	for kind in ZombieTypes.Kind.values():
		var name: String = ZombieTypes.definition(kind).name

		# Arrange: a target inside attack range of a hunting zombie.
		var zombie := _zombie(kind)
		var dummy := _marker(Vector3(0.9, 0.0, 0.0))
		zombie.set_target(dummy)
		zombie.awareness = Zombie.Awareness.HUNTING

		# Act: a goal to walk to, and a full attack cycle.
		var goal: Vector3 = zombie._move_goal()

		var hits := [0]
		zombie.hit_player.connect(func(_d: float, _p: Vector3) -> void: hits[0] += 1)
		zombie._tick_attack(0.001)
		zombie._tick_attack(zombie.attack_windup + 0.01)
		zombie._tick_attack(0.01)

		# Assert
		if not goal.is_finite():
			_failures.append("a %s produced no usable destination" % name)
		elif hits[0] == 0:
			_failures.append(
				"a %s in range never landed a hit — its behaviour has made it " % name
				+ "unable to take part in the fight"
			)

		zombie.free()
		dummy.free()

	if _failures.is_empty():
		print("PASS: all %d kinds still path to a goal and still land a hit"
			% ZombieTypes.Kind.values().size())


## How many of a fixed ring of approach angles end with this kind aiming at a
## point outside the cone the player is looking down.
func _approaches_from_outside_view(
	zombie: Zombie, player_position: Vector3, player_facing: Vector3
) -> int:
	var outside := 0

	for index in APPROACH_SAMPLES:
		var angle := TAU * float(index) / float(APPROACH_SAMPLES)
		zombie.global_position = player_position + Vector3(
			cos(angle) * 10.0, 0.0, sin(angle) * 10.0
		)

		var approach := zombie.preferred_approach_point(player_position, player_facing)
		var offset := approach - player_position
		offset.y = 0.0
		if offset.length() < 0.01:
			continue

		# Behind the player's shoulder line counts as out of view.
		if player_facing.normalized().dot(offset.normalized()) < 0.0:
			outside += 1

	return outside


## The Screamer's telegraph, and the only reason "kill it first" is advice
## rather than a slogan.
##
## Measured before it existed: one Screamer recruited 8 of 8 sleepers in a
## single tick 4.1s into the encounter. Killing it first was impossible, not
## hard — there was no interval between noticing and screaming for the player
## to act in. A silent wind-up would be no better than none, so this asserts
## the silence as well as the eventual noise.
func test_a_screamer_is_silent_while_it_draws_breath() -> void:
	# Arrange
	var screamer := _zombie(ZombieTypes.Kind.SCREAMER)
	var player := _marker(Vector3(0.0, 0.0, -8.0))
	screamer.set_target(player)
	var alarms := [0]
	screamer.raised_alarm.connect(
		func(_z: Zombie, _at: Vector3) -> void: alarms[0] += 1
	)

	# Act: noticing starts the inhale rather than the alarm.
	screamer._set_awareness(Zombie.Awareness.HUNTING)
	screamer._tick_alarm(screamer.alarm_windup - 0.05)
	var during_the_breath: int = alarms[0]

	screamer._tick_alarm(0.1)
	var after_the_breath: int = alarms[0]

	# Assert
	if screamer.alarm_windup <= 0.0:
		_failures.append("a Screamer has no wind-up — it screams the instant it sees you")
	elif during_the_breath != 0:
		_failures.append(
			"a Screamer raised %d alarms while still drawing breath — there is no "
			% during_the_breath + "window in which killing it prevents anything"
		)
	elif after_the_breath != 1:
		_failures.append(
			"a Screamer that finished its %.1fs wind-up raised %d alarms, expected 1"
			% [screamer.alarm_windup, after_the_breath]
		)
	else:
		print("PASS: a Screamer is silent for %.1fs before it screams"
			% screamer.alarm_windup)

	# And a hit during the breath costs it the whole wind-up, which is what the
	# archetype table has always claimed a stagger buys against this kind.
	screamer._set_awareness(Zombie.Awareness.INVESTIGATING)
	screamer._set_awareness(Zombie.Awareness.HUNTING)
	screamer._tick_alarm(screamer.alarm_windup - 0.05)
	screamer.take_damage(1.0)
	screamer._tick_alarm(0.1)

	if alarms[0] != after_the_breath:
		_failures.append(
			"shooting a Screamer a frame before it screamed did not interrupt it"
		)
	else:
		print("PASS: a hit mid-breath costs a Screamer its whole wind-up")

	screamer.free()
	player.free()


## Noticing a Stalker has to stop working once it is already on top of you, or
## looking at it is a free and total counter and the enemy is trivia.
##
## Asserted as a *pair*, because either half alone is satisfiable by something
## broken: a Stalker that never breaks off would pass the near case, and one
## that always breaks off would pass the far case. The threshold is the claim,
## so both sides of it get checked.
func test_a_stalker_that_is_already_on_you_ignores_being_looked_at() -> void:
	# Arrange: a player at the origin looking down -Z, staring straight at a
	# Stalker that is well inside the range at which it stops manoeuvring.
	var near := _watched_stalker(0.5)
	var far := _watched_stalker(1.5)

	# Act
	near._tick_senses(0.0)
	far._tick_senses(0.0)

	# Assert
	if near.is_retreating():
		_failures.append(
			"a Stalker %.1fm away — inside its %.1fm commitment range — still "
			% [
				near.global_position.distance_to(near._target.global_position),
				near.flank_commit_distance,
			]
			+ "backed off when looked at, so staring at one is a free counter"
		)
	elif not far.is_retreating():
		_failures.append(
			"a Stalker %.1fm away did not break off when stared at — the "
			% far.global_position.distance_to(far._target.global_position)
			+ "threshold is not a threshold, it has simply stopped retreating"
		)
	else:
		print("PASS: a Stalker inside %.1fm is committed; outside it, looking still works"
			% near.flank_commit_distance)

	_free_targeted(near)
	_free_targeted(far)


## A Stalker at the given multiple of its commitment range, facing a player who
## is facing straight back at it.
func _watched_stalker(commit_range_multiple: float) -> Zombie:
	var stalker := _zombie(ZombieTypes.Kind.STALKER)
	var player := _marker(Vector3.ZERO)
	stalker.set_target(player)
	stalker.global_position = Vector3(
		0.0, 0.0, -stalker.flank_commit_distance * commit_range_multiple
	)
	# Both looking at each other: the Stalker must be able to see the player at
	# all before being watched can mean anything, and look_at points -Z, which
	# is what facing() reads.
	stalker.look_at(player.global_position, Vector3.UP)
	stalker.awareness = Zombie.Awareness.HUNTING
	stalker._sight_remaining = 0.0
	return stalker


func _free_targeted(zombie: Zombie) -> void:
	var target: Node3D = zombie._target
	zombie.free()
	if target != null and is_instance_valid(target):
		target.free()


func _zombie(kind: ZombieTypes.Kind) -> Zombie:
	var zombie: Zombie = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	root.add_child(zombie)
	zombie.configure(kind)
	return zombie


func _zombie_in(kind: ZombieTypes.Kind, parent: Node3D) -> Zombie:
	var zombie: Zombie = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	parent.add_child(zombie)
	zombie.configure(kind)
	return zombie


## A stand-in parent, since the neighbour scan looks at a zombie's siblings.
func _group() -> Node3D:
	var group := Node3D.new()
	root.add_child(group)
	return group


## A real spawner, because the alarm is only half implemented inside the zombie
## — the propagation rule lives here, and testing the zombie's half alone would
## prove nothing about whether a scream actually recruits anybody.
func _spawner() -> ZombieSpawner:
	var spawner := ZombieSpawner.new()
	root.add_child(spawner)
	return spawner


func _marker(at: Vector3) -> Node3D:
	var marker := Node3D.new()
	root.add_child(marker)
	marker.global_position = at
	return marker


func _free_group(group: Node3D) -> void:
	for child in group.get_children():
		child.free()
	group.free()


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
