extends SceneTree

## Verifies the torch toggles, reports, and does not start lit.
##
## The failure worth guarding is silent: a torch wired to an action that has no
## binding, or a light left permanently visible, both look like a working
## flashlight in a screenshot. Only the state transitions say otherwise.
##
##   Godot --headless --script tests/manual/verify_flashlight.gd

const GAME_SCENE := "res://src/core/game.tscn"

## Short enough that both the unlit and the lit range fit down a corridor.
const TEST_SIGHT_RANGE := 8.0
## Eye height the player is seen at, matching Zombie._can_see_target.
const PLAYER_EYE_HEIGHT := 1.5
## Compass directions tried when hunting for a clear line.
const HEADING_SAMPLES := 72

var _game: Game
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		# Godot 4.7 loads autoloads under --script, but not until after
		# _initialize. Pinning here keeps the test off the player's own menus.
		DeterministicSettings.apply(root)
		return false

	test_flashlight_starts_off()
	test_flashlight_toggles_and_reports()
	test_flashlight_follows_the_camera()
	test_flashlight_action_is_bound()
	test_flashlight_costs_the_player_visibility()

	_report()
	return true


func test_flashlight_starts_off() -> void:
	# Arrange / Act: a fresh round.
	var torch := _game.player.flashlight

	# Assert: the cave should be met as it is lit, so turning the torch on is
	# the player's own decision rather than the default state.
	if torch.is_on or torch.visible:
		_failures.append("the torch was already lit at the start of a round")
	else:
		print("PASS: the torch starts off")


func test_flashlight_toggles_and_reports() -> void:
	# Arrange
	var torch := _game.player.flashlight
	var reports := []
	torch.toggled.connect(func(on: bool) -> void: reports.append(on))

	# Act
	torch.toggle()
	var lit := torch.is_on and torch.visible
	torch.toggle()
	var dark := not torch.is_on and not torch.visible

	# Assert
	if not lit:
		_failures.append("toggling on did not light the torch")
	elif not dark:
		_failures.append("toggling off did not extinguish the torch")
	elif reports != [true, false]:
		_failures.append("the torch did not report both changes, got %s" % str(reports))
	else:
		print("PASS: the torch toggles and reports each change")


func test_flashlight_follows_the_camera() -> void:
	# Arrange: a torch that lagged the aim would be worse than none, because
	# the thing you want to see is the thing you are pointing at.
	var torch := _game.player.flashlight

	# Act / Assert
	if not torch.is_inside_tree():
		_failures.append("the torch is not in the scene")
	elif torch.get_parent() != _game.player.camera:
		_failures.append(
			"the torch hangs off %s rather than the camera" % torch.get_parent().name
		)
	else:
		print("PASS: the torch is parented to the camera")


func test_flashlight_action_is_bound() -> void:
	# Arrange / Act: a torch wired to an unbound action looks identical to a
	# working one until someone presses the key.
	var bound := InputMap.has_action("flashlight") \
		and not InputMap.action_get_events("flashlight").is_empty()

	# Assert
	if not bound:
		_failures.append("the flashlight action has no input bound to it")
	else:
		print("PASS: the flashlight action is bound")


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)


## The torch has to cost something, or switching it on is not a decision.
##
## Asserted at the zombie rather than at the player, because the player side is
## only half the mechanism: the flashlight reports a multiplier, and the value
## of that multiplier is entirely in whether anything reads it. This is the
## seam where a refactor quietly drops the cost and nothing else notices — the
## light still works, the cave is still lit, and the game just gets easier.
##
## The zombie used to be stood a fixed distance down +Z, which worked on the
## open procedural cave and is meaningless on an authored labyrinth: there is
## no 24m sightline anywhere on it, so the ray hit a wall and the test read a
## blocked view as a broken multiplier. It now shortens the zombie's own sight
## range to something a corridor can hold and hunts for a line that is actually
## clear, which is a property of the level rather than of the mechanism under
## test. The assertion itself is unchanged: unlit is unseen, lit is seen.
func test_flashlight_costs_the_player_visibility() -> void:
	# Arrange
	var player := _game.player
	var flashlight := player.flashlight

	var zombie: Zombie = load("res://src/gameplay/zombie/zombie.tscn").instantiate()
	_game.add_child(zombie)
	zombie.configure(ZombieTypes.Kind.SHAMBLER)
	zombie.set_target(player)

	# Short enough that the band between unlit and lit range fits down a
	# corridor. The multiplier is what is on trial, not how far a Shambler sees.
	zombie.sight_range = TEST_SIGHT_RANGE

	# Stand it just beyond its own sight range, looking straight at the player.
	var gap: float = zombie.sight_range * 1.2
	var heading := _clear_heading(player, zombie, gap)

	if heading == Vector3.ZERO:
		_failures.append(
			"no clear %.1fm sightline anywhere around the player — the "
			% gap
			+ "visibility test could not be set up on this map"
		)
		zombie.queue_free()
		return

	zombie.global_position = player.global_position + heading * gap
	zombie.look_at(player.global_position, Vector3.UP)

	# Act
	flashlight.set_on(false)
	var seen_dark := zombie._can_see_target()

	flashlight.set_on(true)
	var seen_lit := zombie._can_see_target()

	flashlight.set_on(false)
	zombie.queue_free()

	# Assert
	var scale := flashlight.lit_visibility_scale
	if scale <= 1.0:
		_failures.append("a lit player is no more visible than an unlit one")
	elif gap > zombie.sight_range * scale:
		# The test itself would be meaningless — the zombie could not see the
		# player at either setting, so both answers would be "no".
		_failures.append(
			"the test stood the zombie %.1fm away, past even the lit range of %.1fm"
			% [gap, zombie.sight_range * scale]
		)
	elif seen_dark:
		_failures.append("an unlit player was spotted from beyond sight_range")
	elif not seen_lit:
		_failures.append(
			"switching the torch on did not extend how far the player is seen"
		)
	else:
		print(
			"PASS: the torch is seen %.0fm further off (%.0fm dark, %.0fm lit)"
			% [
				zombie.sight_range * (scale - 1.0),
				zombie.sight_range,
				zombie.sight_range * scale,
			]
		)


## Find a direction with an unbroken view back to the player at `gap` metres.
##
## The ray cast here is deliberately the same one `_can_see_target` will cast —
## same endpoints, same mask, same exclusions — so a heading this accepts
## cannot then be rejected by the code under test for a reason the setup never
## considered. Returns Vector3.ZERO when the level offers no such line.
func _clear_heading(player: Node3D, zombie: Zombie, gap: float) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var target := player.global_position + Vector3.UP * PLAYER_EYE_HEIGHT
	var eye_height: float = zombie._collider.shape.height * 0.85

	for index in HEADING_SAMPLES:
		var angle := TAU * float(index) / float(HEADING_SAMPLES)
		var heading := Vector3(cos(angle), 0.0, sin(angle))
		var stand := player.global_position + heading * gap

		var query := PhysicsRayQueryParameters3D.create(
			stand + Vector3.UP * eye_height, target
		)
		query.collision_mask = 1
		query.exclude = [zombie.get_rid(), player.get_rid()]

		if space.intersect_ray(query).is_empty():
			return heading

	return Vector3.ZERO
