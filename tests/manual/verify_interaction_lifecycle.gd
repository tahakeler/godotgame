extends SceneTree

## Verifies that the interaction system stops when the round does, and that a
## hold cannot be carried across a restart.
##
## verify_interaction.gd covers what a hold does while a round is running. This
## file covers the boundaries either side of it, which is where the interaction
## system meets the round state machine — the two landed in parallel and had
## never been exercised together.
##
## The failures guarded here are invisible in a screenshot. A dead player
## holding E on a crate still sees a results screen; the crate quietly empties
## behind it, spends its 55-second recharge, and emits a world noise event from
## a round that is already over. A hold begun at 1.1s of 1.2 and then restarted
## hands the player a free cache on the first frame of the new round.
##
## Driven through Interactor.tick() rather than through Input, for the same
## reason verify_interaction.gd is: a key press cannot be synthesised under
## --headless --script.
##
##   Godot --headless --script tests/manual/verify_interaction_lifecycle.gd

const GAME_SCENE := "res://src/core/game.tscn"
const STEP := 1.0 / 60.0
## Comfortably past AmmoCache.resupply_hold_seconds (1.2s).
const FULL_HOLD := 1.5

var _game: Game
var _failures: Array[String] = []
var _frames := 0
var _cache: AmmoCache


func _initialize() -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		# Autoloads exist under --script, but not until after _initialize.
		DeterministicSettings.apply(root)
		return false

	_game.start_round()

	test_a_cache_is_lootable_while_the_round_is_running()
	test_a_cache_cannot_be_looted_after_the_player_dies()
	test_looting_works_again_once_a_new_round_begins()
	test_a_hold_does_not_survive_a_restart()
	test_caches_are_not_destroyed_by_a_full_player()

	_report()
	return true


## The control case. Without it the three below would pass on a system that
## simply never works.
func test_a_cache_is_lootable_while_the_round_is_running() -> void:
	# Arrange
	var cache := _place_cache()
	var interactor := _interactor()

	# Act
	_hold_for(interactor, FULL_HOLD)

	# Assert
	if cache.stock() != 0:
		_failures.append(
			"a full hold on a stocked cache left %d rounds in it" % cache.stock()
		)
	else:
		print("PASS: a full hold empties a cache while the round is running")


## Death takes the weapon and the look away. It has to take the interact key
## too, or the results screen is a place where the map can still be looted.
func test_a_cache_cannot_be_looted_after_the_player_dies() -> void:
	# Arrange
	_game.start_round()
	var cache := _place_cache()
	var interactor := _interactor()

	# Act
	_game.player.health.take_damage(_game.player.health.max_health * 2.0)
	if not _game.is_round_over():
		_failures.append("killing the player did not end the round")
		return
	_hold_for(interactor, FULL_HOLD)

	# Assert
	if cache.stock() != cache.capacity:
		_failures.append(
			"a dead player emptied a cache: %d of %d left"
			% [cache.stock(), cache.capacity]
		)
	else:
		print("PASS: holding interact after death loots nothing")


## The other half of the gate. Disabling interaction on death is only correct
## if the next round hands it back.
func test_looting_works_again_once_a_new_round_begins() -> void:
	# Arrange
	_game.start_round()
	var cache := _place_cache()
	var interactor := _interactor()

	# Act
	_hold_for(interactor, FULL_HOLD)

	# Assert
	if cache.stock() != 0:
		_failures.append("a restart left interaction disabled")
	else:
		print("PASS: a fresh round restores interaction")


## Progress is paid in one uninterrupted stretch. A restart is the largest
## possible interruption, so it must forfeit the same as letting go does.
func test_a_hold_does_not_survive_a_restart() -> void:
	# Arrange: 1.0s into a 1.2s hold, then restart.
	_game.start_round()
	var cache := _place_cache()
	var interactor := _interactor()
	_hold_for(interactor, 1.0)
	if interactor.hold_progress() <= 0.0:
		_failures.append("the arrange step never started a hold")
		return

	# Act: the restart moves the player, so put the crate back in front of them
	# before ticking — otherwise losing focus would mask the carried progress.
	_game.start_round()
	cache = _place_cache(cache)
	_hold_for(interactor, 0.3)

	# Assert
	if cache.stock() != cache.capacity:
		_failures.append(
			"0.3s of holding after a restart emptied a 1.2s cache — the hold "
			+ "carried across the round boundary"
		)
	else:
		print("PASS: a hold in progress is forfeited by a restart")


func _interactor() -> Interactor:
	return _game.player.interactor


## A stocked cache 1.5m dead ahead of wherever the player currently stands.
## Reusing the node when one is passed in keeps a test's focus identity stable
## across a restart, which is exactly what that test is probing.
func _place_cache(existing: AmmoCache = null) -> AmmoCache:
	var player: Player = _game.player
	var forward := -player.global_transform.basis.z

	var cache := existing
	if cache == null:
		if _cache != null and is_instance_valid(_cache):
			_cache.free()
		cache = AmmoCache.new()
		_game.add_child(cache)
		_cache = cache

	cache.reset()
	cache.global_position = player.global_position + forward * 1.5
	return cache


func _hold_for(interactor: Interactor, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		interactor.tick(STEP, true)
		elapsed += STEP


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


## A crate must never be spent on a player who cannot carry what is in it.
##
## Found by the QA pass and reported rather than fixed, because the obvious
## repairs all had the crate asking what a magazine is. The drain and the 55
## second recharge used to run unconditionally, while every piece of feedback —
## the resupply sound, the pickup chime, the world noise the zombies hunt by —
## was gated behind "did the reserve actually go up". So a full player emptied
## a crate, heard nothing at all, and had no way to tell that from a good loot.
func test_caches_are_not_destroyed_by_a_full_player() -> void:
	# Arrange
	var cache: AmmoCache = _game.arena.ammo_caches[0]
	cache.reset()
	var weapon := _game.weapon
	weapon.reserve_ammo = weapon.max_reserve

	# Act
	var offered := cache.can_interact(_game.player)
	cache.interact(_game.player)
	var left_when_full := cache.stock()

	# Now make room for exactly two rounds and try again.
	weapon.reserve_ammo = weapon.max_reserve - 2
	cache.interact(_game.player)
	var left_when_nearly_full := cache.stock()

	weapon.reserve_ammo = 0

	# Assert
	if offered:
		_failures.append("a full player was still offered a resupply prompt")
	elif left_when_full < cache.capacity:
		_failures.append(
			"a full player drained a cache to %d of %d" % [left_when_full, cache.capacity]
		)
	elif left_when_nearly_full != cache.capacity - 2:
		_failures.append(
			"a cache gave %d rounds to a player with room for 2"
			% [cache.capacity - left_when_nearly_full]
		)
	else:
		print("PASS: a cache gives only what fits and keeps the rest")
