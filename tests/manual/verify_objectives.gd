extends SceneTree

## Verifies the relay chain: design/gdd/objectives-and-exploration.md §8.
##
## The claims under test are all about a relay advancing for exactly one
## reason and no other. A relay that arms on a timer, banks partial credit,
## survives a restart, finishes a hold after the player is dead, or broadcasts
## without the noise ring reporting it, is each a different way of quietly
## taking the cost out of the objective — and the cost is the design.
##
## Two of those are not hypothetical. QA found interaction state surviving a
## lifecycle boundary twice on this project: the interact key worked after
## death, and a hold at 1.1s of 1.2 completed on the first frame of the next
## round. Restart and death are asserted separately here because they are
## separate code paths and the bug was in exactly one of them.

const GAME_SCENE := "res://src/core/game.tscn"

var _game: Game
var _failures: Array[String] = []
var _started := false
## What the HUD was actually handed, as opposed to what the chain believes.
## The claim is that the player was told, so the assertion is made against the
## text that reached the readout.
var _hud_text := ""


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame,
	# and autoloads do not exist until after _initialize returns.
	if not _started:
		_started = true
		DeterministicSettings.apply(root)
		# Pinned here rather than in DeterministicSettings: that file is shared,
		# and verify_game_loop and verify_progression are written against
		# Extraction. A mode override belongs to the test that needs it.
		_set_mode(GameSettings.Mode.RELAY)
		_game.objective_changed.connect(
			func(text: String, _t: Vector3, _b: bool) -> void: _hud_text = text
		)
		_game.start_round()
		return false

	_test_relay_advances_only_on_completed_hold()
	_test_interrupted_hold_banks_no_progress()
	_test_hud_objective_text_matches_state()
	_test_extraction_only_available_after_full_chain()
	_test_extraction_hold_is_required()
	_test_restart_resets_every_relay()
	_test_hold_does_not_survive_death()
	_test_relay_noise_routes_through_game()
	_test_existing_modes_unchanged()

	_report()
	return true


func _set_mode(mode: GameSettings.Mode) -> void:
	var settings := GameSettings.instance(_game)
	if settings != null:
		settings.mode = mode


func _chain() -> RelayObjective:
	return _game.relays


func _arm_all() -> void:
	for relay in _chain().relays:
		_chain().force_hold(relay, relay.relay_hold_duration)


## A relay advances on one condition only: an unbroken hold that reaches the
## full duration. Not at 99%, and never on elapsed time alone.
func _test_relay_advances_only_on_completed_hold() -> void:
	_game.start_round()
	var relay: SignalRelay = _chain().relays[0]

	_chain().force_hold(relay, relay.relay_hold_duration - 0.01)

	if relay.is_armed():
		_failures.append("relay armed at 99%% of its hold")
		return
	if _chain().armed_count() != 0:
		_failures.append("armed count moved before any relay armed")
		return

	_chain().force_hold(relay, 0.02)

	if not relay.is_armed():
		_failures.append("relay did not arm after a completed hold")
		return
	if _chain().armed_count() != 1:
		_failures.append("armed count %d after one arm" % _chain().armed_count())
		return

	# The other half of the claim: time alone must move nothing.
	_game.start_round()
	var idle: SignalRelay = _chain().relays[1]
	_chain().tick_idle(relay.relay_hold_duration * 10.0)

	if idle.state() != SignalRelay.State.DORMANT or _chain().armed_count() != 0:
		_failures.append("a relay armed on elapsed time with nobody holding it")
		return

	print("PASS: a relay arms on a completed hold and on nothing else")


## No partial banking. An interrupted hold costs the whole hold.
func _test_interrupted_hold_banks_no_progress() -> void:
	_game.start_round()
	var relay: SignalRelay = _chain().relays[0]

	_chain().force_hold(relay, relay.relay_hold_duration * 0.9)
	relay.break_hold()

	if not is_zero_approx(relay.hold_progress()):
		_failures.append("broken hold banked %.2f progress" % relay.hold_progress())
		return

	# A fresh full duration must still be required, less one frame.
	_chain().force_hold(relay, relay.relay_hold_duration - 0.01)
	if relay.is_armed():
		_failures.append("resumed hold armed early — progress was banked")
		return

	_chain().force_hold(relay, 0.02)
	if not relay.is_armed():
		_failures.append("relay would not arm after a fresh full hold")
		return

	print("PASS: an interrupted hold banks nothing and must be paid again in full")


func _test_hud_objective_text_matches_state() -> void:
	_game.start_round()

	var expected_zero := "SIGNAL RELAYS — 0 OF %d ARMED" % _chain().relay_count_required
	if _hud_text != expected_zero:
		_failures.append("objective line at 0 armed was %s" % _hud_text)
		return

	for index in range(_chain().relays.size()):
		var relay: SignalRelay = _chain().relays[index]
		_chain().force_hold(relay, relay.relay_hold_duration * 0.5)

		var arming := "ARMING RELAY — %s" % relay.label
		if _hud_text != arming:
			_failures.append("objective line while arming was %s" % _hud_text)
			return

		_chain().force_hold(relay, relay.relay_hold_duration)

		var armed := index + 1
		var expected := (
			"EXTRACT — RETURN TO THE ARENA" if armed >= _chain().relay_count_required
			else "SIGNAL RELAYS — %d OF %d ARMED" % [armed, _chain().relay_count_required]
		)
		if _hud_text != expected:
			_failures.append("objective line at %d armed was %s" % [armed, _hud_text])
			return

	print("PASS: the HUD was handed the right objective line at every step")


func _test_extraction_only_available_after_full_chain() -> void:
	_game.start_round()
	_game.player.global_position = _chain().extraction_point

	# Two of three: standing at the extraction point must do nothing at all.
	_chain().force_hold(_chain().relays[0], _chain().relays[0].relay_hold_duration)
	_chain().force_hold(_chain().relays[1], _chain().relays[1].relay_hold_duration)
	_chain().tick_idle(_chain().extraction_hold_duration * 2.0)

	if _game.state != _game.RoundState.PLAYING:
		_failures.append("extraction completed with only 2 of 3 relays armed")
		return

	_chain().force_hold(_chain().relays[2], _chain().relays[2].relay_hold_duration)
	_game.player.global_position = _chain().extraction_point
	_chain().tick_idle(_chain().extraction_hold_duration + 0.01)

	if _game.state != _game.RoundState.WON:
		_failures.append("full chain plus extraction hold did not win (state %d)" % _game.state)
		return

	print("PASS: extraction opens only after the full chain and ends the round as a win")


## Entering the radius is not a win. A win the player trips over by accident is
## not a win they earned.
func _test_extraction_hold_is_required() -> void:
	_game.start_round()
	_arm_all()
	_game.player.global_position = _chain().extraction_point

	_chain().tick_idle(0.016)

	if _game.state != _game.RoundState.PLAYING:
		_failures.append("one frame inside the extraction radius won the round")
		return

	print("PASS: standing in the extraction radius for a frame does not win")


func _test_restart_resets_every_relay() -> void:
	_game.start_round()
	_arm_all()

	if _chain().armed_count() != _chain().relay_count_required:
		_failures.append("could not arm the chain to set the restart case up")
		return

	_game.start_round()

	var problems: Array[String] = []
	for relay in _chain().relays:
		if relay.state() != SignalRelay.State.DORMANT:
			problems.append("%s state=%d" % [relay.label, relay.state()])
		if relay.is_broadcasting():
			problems.append("%s still broadcasting" % relay.label)
	if _chain().armed_count() != 0:
		problems.append("armed=%d" % _chain().armed_count())
	if _hud_text != "SIGNAL RELAYS — 0 OF %d ARMED" % _chain().relay_count_required:
		problems.append("objective line=%s" % _hud_text)

	if problems.is_empty():
		print("PASS: a restart returned every relay to dormant with nothing pending")
	else:
		_failures.append("restart left stale relay state: %s" % ", ".join(problems))


## The other lifecycle boundary, asserted separately because it is a separate
## code path — and QA found a bug in exactly one of the two.
func _test_hold_does_not_survive_death() -> void:
	_game.start_round()
	var relay: SignalRelay = _chain().relays[0]

	_chain().force_hold(relay, relay.relay_hold_duration - 0.01)

	_game.player.health.invulnerability_duration = 0.0
	_game.player.take_damage(_game.player.health.max_health + 10.0, Vector3.ZERO)

	if _game.state != _game.RoundState.LOST:
		_failures.append("player did not die while a relay hold was in progress")
		return
	if relay.is_armed():
		_failures.append("a relay armed from a hold that outlived the player")
		return

	# And the hold must not finish itself on the first frame of the next round.
	_game.start_round()
	_chain().tick_idle(0.016)

	if relay.state() != SignalRelay.State.DORMANT or _chain().armed_count() != 0:
		_failures.append("a hold paid before death completed in the next round")
		return

	print("PASS: a hold in progress does not survive a death or reach into the next round")


## A relay must not be able to be loud silently. Every pulse goes through
## Game._make_noise(), which is the one call that both broadcasts to the
## spawner and reports the cost to the HUD's noise ring.
func _test_relay_noise_routes_through_game() -> void:
	_game.start_round()
	var relay: SignalRelay = _chain().relays[0]

	var routed := false
	for connection in relay.noise_pulsed.get_connections():
		var callable: Callable = connection.callable
		if callable.get_object() == _game and callable.get_method() == "_make_noise":
			routed = true

	if not routed:
		_failures.append("relay noise is not wired to Game._make_noise")
		return

	# GDScript lambdas capture locals by value, so the counter has to live in
	# something the closure can reach through a reference.
	var pulses := [0]
	relay.noise_pulsed.connect(
		func(_at: Vector3, loudness: float) -> void:
			if loudness > 0.0:
				pulses[0] += 1
	)
	_chain().force_hold(relay, relay.relay_hold_duration)

	if pulses[0] <= 0:
		_failures.append("arming a relay emitted no noise at all")
		return

	print("PASS: arming emitted %d pulses, all routed through Game._make_noise" % pulses[0])


## Cheap regression. Mode.RELAY is appended last, so nothing before it may move.
func _test_existing_modes_unchanged() -> void:
	if int(GameSettings.Mode.EXTRACTION) != 0:
		_failures.append("Mode.EXTRACTION is no longer 0")
		return
	if int(GameSettings.Mode.RELAY) != 3:
		_failures.append("Mode.RELAY is not the last entry")
		return

	_set_mode(GameSettings.Mode.EXTRACTION)
	_game.start_round()

	if not is_equal_approx(_game.time_remaining, _game.extraction_duration):
		_failures.append("an Extraction round no longer opens on its full clock")
		_set_mode(GameSettings.Mode.RELAY)
		return

	_set_mode(GameSettings.Mode.RELAY)
	print("PASS: the existing modes are untouched by the new one")


## Tear the scene down before quitting. The sound bank holds preloaded audio
## streams, and leaving them referenced at exit is reported as "resources still
## in use", which the check treats as a real error.
func _teardown() -> void:
	if _game != null and is_instance_valid(_game):
		root.remove_child(_game)
		_game.free()
		_game = null


func _report() -> void:
	_teardown()

	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
