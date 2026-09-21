extends SceneTree

## Verifies the interaction system: what the prompt says, when it appears, and
## that a hold has to be paid in full.
##
## The failures worth guarding here are all silent ones. A prompt that shows
## through a wall or from behind you still looks like a working prompt in a
## screenshot. A hold that completes on release instead of on duration still
## heals you. A medkit usable at full health still plays its animation. Only
## the state either side of the call says which one you have.
##
## Driven through Interactor.tick() rather than through Input, because a key
## press cannot be synthesised meaningfully under --headless --script — and a
## system reachable only through a key press is a system nothing asserts on.
##
##   Godot --headless --script tests/manual/verify_interaction.gd

const GAME_SCENE := "res://src/core/game.tscn"
const STEP := 1.0 / 60.0

var _game: Game
var _failures: Array[String] = []
var _frames := 0
## Generous, but finite. The assertions are reached on frame 3.
const WATCHDOG_FRAMES := 600

var _watchdog := 0
var _prompts: Array[String] = []


func _initialize() -> void:
	var scene := load(GAME_SCENE) as PackedScene
	if scene == null:
		# Loading the game scene can fail inside a full gate run while passing
		# standalone. Saying so here is the difference between one readable
		# line and a test that errors every frame forever — this file had no
		# guard and no watchdog, and a failed load produced a 24MB log of
		# repeated null access before anyone could see what went wrong.
		printerr("FAIL: could not load %s" % GAME_SCENE)
		quit(1)
		return

	_game = scene.instantiate() as Game
	if _game == null:
		printerr("FAIL: %s loaded but did not instantiate a Game" % GAME_SCENE)
		quit(1)
		return

	root.add_child(_game)


func _process(_delta: float) -> bool:
	# A hard ceiling, for the same reason verify_zombies.gd has one: without it
	# any failure to reach the assertions spins the loop until the run is
	# killed by hand.
	_watchdog += 1
	if _watchdog > WATCHDOG_FRAMES:
		printerr("FAIL: gave up after %d frames without reaching the assertions"
			% WATCHDOG_FRAMES)
		quit(1)
		return true

	if _game == null:
		printerr("FAIL: the game scene went away before the assertions ran")
		quit(1)
		return true

	_frames += 1
	if _frames < 3:
		# Autoloads exist under --script, but not until after _initialize.
		DeterministicSettings.apply(root)
		return false

	_game.player.interactor.prompt_changed.connect(
		func(text: String) -> void: _prompts.append(text)
	)

	test_nothing_in_range_shows_no_prompt_and_pressing_does_nothing()
	test_a_medkit_in_range_and_in_view_shows_its_prompt()
	test_a_medkit_behind_the_player_shows_no_prompt()
	test_a_medkit_out_of_reach_shows_no_prompt()
	test_a_hold_released_early_does_nothing()
	test_a_hold_carried_to_term_heals_and_consumes_the_kit()
	test_a_medkit_is_refused_at_full_health()
	test_a_cache_declares_itself_a_held_interaction()

	_report()
	return true


## The most common thing a player will ever do with the key is press it at
## nothing. That has to be silent: no prompt, no call, and above all no error.
func test_nothing_in_range_shows_no_prompt_and_pressing_does_nothing() -> void:
	# Arrange
	var interactor := _interactor()
	interactor.reset()
	_prompts.clear()

	# Act
	interactor.tick(STEP, true)
	interactor.tick(STEP, false)

	# Assert
	if interactor.focus() != null:
		_failures.append("something was focused in an empty room")
	elif _prompts.any(func(text: String) -> bool: return text != ""):
		_failures.append("a prompt appeared with nothing in range: %s" % _prompts)
	else:
		print("PASS: pressing interact at nothing does nothing")


func test_a_medkit_in_range_and_in_view_shows_its_prompt() -> void:
	# Arrange: hurt, so the kit is willing to be used at all.
	var interactor := _interactor()
	_game.player.health.take_damage(50.0)
	var kit := _spawn_kit(1.4)

	# Act
	interactor.tick(STEP, false)

	# Assert
	if interactor.focus() != kit:
		_failures.append("a kit 1.4m ahead was not focused")
	elif _last_prompt() != "Hold E — Bandage":
		_failures.append("prompt read %s" % [_last_prompt()])
	else:
		print("PASS: a kit in range and in view prompts 'Hold E — Bandage'")

	kit.free()


## Turning your back on something has to drop the prompt, or the prompt stops
## being information about where you are looking.
func test_a_medkit_behind_the_player_shows_no_prompt() -> void:
	# Arrange
	var interactor := _interactor()
	var kit := _spawn_kit(-1.4)

	# Act
	interactor.tick(STEP, false)

	# Assert
	if interactor.focus() != null:
		_failures.append("a kit directly behind the player was focused")
	elif _last_prompt() != "":
		_failures.append("a prompt survived the player turning away")
	else:
		print("PASS: a kit behind the player shows no prompt")

	kit.free()


func test_a_medkit_out_of_reach_shows_no_prompt() -> void:
	# Arrange: well past the kit's own reach, still dead ahead.
	var interactor := _interactor()
	var kit := _spawn_kit(9.0)

	# Act
	interactor.tick(STEP, false)

	# Assert
	if interactor.focus() != null:
		_failures.append("a kit 9m away was focused — reach is not enforced")
	else:
		print("PASS: a kit out of reach shows no prompt")

	kit.free()


## The whole reason the medkit is a hold is that the player may change their
## mind halfway through. Letting go has to cost them nothing but the seconds.
func test_a_hold_released_early_does_nothing() -> void:
	# Arrange
	var interactor := _interactor()
	var kit := _spawn_kit(1.4)
	var before := _game.player.health.current_health

	# Act: most of the way, then let go.
	_hold_for(interactor, kit.hold_seconds * 0.8, true)
	interactor.tick(STEP, false)

	# Assert
	if not is_equal_approx(_game.player.health.current_health, before):
		_failures.append("releasing early still healed the player")
	elif kit.is_consumed():
		_failures.append("releasing early still consumed the kit")
	elif interactor.hold_progress() > 0.0:
		_failures.append("releasing early left the hold part-completed")
	else:
		print("PASS: a hold released early heals nothing and keeps the kit")

	kit.free()


func test_a_hold_carried_to_term_heals_and_consumes_the_kit() -> void:
	# Arrange
	var interactor := _interactor()
	var kit := _spawn_kit(1.4)
	var before := _game.player.health.current_health
	var expected := minf(
		_game.player.health.max_health, before + kit.heal_amount
	)

	# Act
	_hold_for(interactor, kit.hold_seconds + STEP, true)

	# Assert
	if not is_equal_approx(_game.player.health.current_health, expected):
		_failures.append(
			"a completed hold left health at %.1f, expected %.1f"
			% [_game.player.health.current_health, expected]
		)
	elif not kit.is_consumed():
		_failures.append("a used kit was not consumed and can be used twice")
	else:
		print("PASS: a hold carried to term heals %.0f and consumes the kit"
			% kit.heal_amount)


## A kit spent at full health is a kit deleted by accident, which teaches the
## player never to pick one up. Refusing costs nothing and teaches the rule.
func test_a_medkit_is_refused_at_full_health() -> void:
	# Arrange
	var interactor := _interactor()
	_game.player.health.reset()
	var kit := _spawn_kit(1.4)

	# Act
	interactor.tick(STEP, false)
	var focused := interactor.focus()
	var accepted := kit.interact(_game.player)

	# Assert
	if focused != null:
		_failures.append("a kit prompted at full health")
	elif accepted:
		_failures.append("a kit was spent at full health")
	elif kit.is_consumed():
		_failures.append("a refused kit was consumed anyway")
	else:
		print("PASS: a kit is refused, not wasted, at full health")

	kit.free()


## The caches predate the interaction system and used to collect on contact.
## They must now answer the same contract as everything else, or the player has
## two different rules to learn for two crates that look alike.
func test_a_cache_declares_itself_a_held_interaction() -> void:
	# Arrange
	var cache: AmmoCache = _game.arena.ammo_caches[0]
	cache.reset()

	# Act
	var prompt := cache.interaction_prompt(_game.player)
	var hold := cache.interaction_hold_time(_game.player)
	var usable_when_full := cache.can_interact(_game.player)
	cache._collect()
	var usable_when_empty := cache.can_interact(_game.player)

	# Assert
	if prompt != "Resupply":
		_failures.append("a cache prompts %s" % [prompt])
	elif hold <= 0.0:
		_failures.append("a cache is instant — rummaging must cost time")
	elif not usable_when_full:
		_failures.append("a stocked cache refused the player")
	elif usable_when_empty:
		_failures.append("an empty cache still prompts, promising nothing")
	else:
		print("PASS: a cache is a %.1fs held 'Resupply' only while stocked"
			% hold)

	cache.reset()


func _interactor() -> Interactor:
	return _game.player.interactor


## A kit `distance` metres along the player's facing. Negative puts it behind.
func _spawn_kit(distance: float) -> Medkit:
	var player: Player = _game.player
	var forward := -player.global_transform.basis.z
	return Medkit.spawn(_game, player.global_position + forward * distance)


func _hold_for(interactor: Interactor, seconds: float, held: bool) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		interactor.tick(STEP, held)
		elapsed += STEP


func _last_prompt() -> String:
	if _prompts.is_empty():
		return ""
	return _prompts[-1]


func _report() -> void:
	if _game != null and is_instance_valid(_game):
		root.remove_child(_game)
		_game.free()
		_game = null

	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
