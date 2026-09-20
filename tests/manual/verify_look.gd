extends SceneTree

## Verifies that mouse motion actually turns the camera.
##
## Diagnostic first, regression test second. A player reported that a trackpad
## would not turn the view at all, and the interesting question is not whether
## _apply_look does the right arithmetic — it does — but whether the event ever
## reaches it. So this injects a real motion event at the viewport and asks
## whether the player rotated, which is the same path a hand on a trackpad takes.
##
##   Godot --headless --script tests/manual/verify_look.gd

const GAME_SCENE := "res://src/core/game.tscn"

## Big enough that a failure cannot be rounding.
const MOTION := Vector2(220.0, 90.0)

enum Step { WARMUP, SEND, ASSERT, DONE }

var _game: Game
var _step: int = Step.WARMUP
var _failures: Array[String] = []
var _yaw_before := 0.0
var _pitch_before := 0.0


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	match _step:
		Step.WARMUP:
			# Godot 4.7 loads autoloads under --script, and they do not exist
			# until after _initialize. Pinning here, then restarting the round,
			# stops the test inheriting the menu choices saved on this machine.
			DeterministicSettings.apply(root)
			_game.start_round()

		Step.SEND:
			print("mouse mode after a round starts: %s" % _mode_name())
			_yaw_before = _game.player.rotation.y
			_pitch_before = _game.player.head.rotation.x
			_send_motion(MOTION)

		Step.ASSERT:
			test_look_mouse_motion_turns_the_player()
			test_look_mouse_motion_pitches_the_camera()
			test_look_pitch_is_clamped()
			test_look_invert_reverses_pitch_only()
			test_look_sensitivity_scales_the_turn()
			test_look_disabled_releases_the_cursor_and_ignores_input()

		Step.DONE:
			_report()
			return true

	_step += 1
	return false


func test_look_mouse_motion_turns_the_player() -> void:
	# Arrange / Act: a horizontal motion event was delivered last frame.
	var turned: float = absf(_game.player.rotation.y - _yaw_before)

	# Assert
	if is_zero_approx(turned):
		_failures.append(
			"mouse motion did not turn the player at all — "
			+ "the event never reached the look handler"
		)
	else:
		print("PASS: mouse motion turns the player (%.3f rad)" % turned)


func test_look_mouse_motion_pitches_the_camera() -> void:
	# Arrange / Act: the same event carried vertical motion.
	var pitched: float = absf(_game.player.head.rotation.x - _pitch_before)

	# Assert
	if is_zero_approx(pitched):
		_failures.append("mouse motion did not pitch the camera")
	else:
		print("PASS: mouse motion pitches the camera (%.3f rad)" % pitched)


## Deliver motion the way the windowing system would.
##
## These assertions check only that rotation happened, never how much. An
## injected event can be flushed more than once in a frame, so the resulting
## angle is not a meaningful number — the pitch here reaches its clamp. What is
## meaningful is the difference between "turned" and "did not turn at all",
## which is the bug this guards.
func _send_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	event.velocity = relative
	Input.parse_input_event(event)


func _mode_name() -> String:
	match Input.get_mouse_mode():
		Input.MOUSE_MODE_VISIBLE:
			return "VISIBLE"
		Input.MOUSE_MODE_HIDDEN:
			return "HIDDEN"
		Input.MOUSE_MODE_CAPTURED:
			return "CAPTURED"
		Input.MOUSE_MODE_CONFINED:
			return "CONFINED"
		Input.MOUSE_MODE_CONFINED_HIDDEN:
			return "CONFINED_HIDDEN"
	return "UNKNOWN"


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)


## --- Phase 1 contract -------------------------------------------------------
##
## The rest of what "a proper FPS camera" means, asserted rather than assumed.
## Each of these looks fine in a screenshot and is wrong the moment somebody
## actually plays.


func test_look_pitch_is_clamped() -> void:
	# Arrange: an absurd upward drag, far past vertical.
	var player := _game.player
	player.head.rotation.x = 0.0

	# Act
	for push in 40:
		player._apply_look(Vector2(0.0, -400.0))

	# Assert: without a clamp the view rolls over, the world turns upside down,
	# and a mouse cannot recover from it.
	var limit := deg_to_rad(player.pitch_limit_degrees)
	if player.head.rotation.x > limit + 0.001:
		_failures.append(
			"pitch ran past its limit: %.2f rad against a %.2f rad clamp"
			% [player.head.rotation.x, limit]
		)
		return

	player.head.rotation.x = 0.0
	for push in 40:
		player._apply_look(Vector2(0.0, 400.0))

	if player.head.rotation.x < -limit - 0.001:
		_failures.append("pitch ran past its lower limit: %.2f rad" % player.head.rotation.x)
	else:
		print("PASS: vertical look is clamped in both directions")


func test_look_invert_reverses_pitch_only() -> void:
	# Arrange
	var player := _game.player
	player.invert_look_y = false
	player.head.rotation.x = 0.0
	player.rotation.y = 0.0

	# Act
	player._apply_look(Vector2(50.0, 50.0))
	var normal_pitch := player.head.rotation.x
	var normal_yaw := player.rotation.y

	player.invert_look_y = true
	player.head.rotation.x = 0.0
	player.rotation.y = 0.0
	player._apply_look(Vector2(50.0, 50.0))
	var inverted_pitch := player.head.rotation.x
	var inverted_yaw := player.rotation.y

	player.invert_look_y = false

	# Assert: inverting flips pitch and leaves yaw alone. Flipping both is a
	# classic bug that makes the setting feel broken rather than inverted.
	if not is_equal_approx(inverted_pitch, -normal_pitch):
		_failures.append(
			"invert did not mirror pitch: %.4f against %.4f"
			% [inverted_pitch, normal_pitch]
		)
	elif not is_equal_approx(inverted_yaw, normal_yaw):
		_failures.append("invert also reversed yaw, which it must not touch")
	else:
		print("PASS: invert mirrors pitch and leaves yaw alone")


func test_look_sensitivity_scales_the_turn() -> void:
	# Arrange
	var player := _game.player
	var original := player.mouse_sensitivity

	# Act
	player.rotation.y = 0.0
	player._apply_look(Vector2(100.0, 0.0))
	var slow := absf(player.rotation.y)

	player.rotation.y = 0.0
	player.mouse_sensitivity = original * 2.0
	player._apply_look(Vector2(100.0, 0.0))
	var fast := absf(player.rotation.y)

	player.mouse_sensitivity = original

	# Assert
	if not is_equal_approx(fast, slow * 2.0):
		_failures.append(
			"doubling sensitivity did not double the turn: %.4f against %.4f"
			% [fast, slow]
		)
	else:
		print("PASS: sensitivity scales the turn proportionally")


func test_look_disabled_releases_the_cursor_and_ignores_input() -> void:
	# Arrange: this is exactly what opening a menu does.
	var player := _game.player
	player.set_look_enabled(false)
	player.rotation.y = 0.0

	# Act
	player._unhandled_input(_motion(Vector2(250.0, 0.0)))
	var turned := absf(player.rotation.y)
	var released := Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED

	player.set_look_enabled(true)

	# Assert
	if turned > 0.0:
		_failures.append("the camera still turned while look was disabled")
	elif not released:
		_failures.append("the cursor stayed captured while look was disabled")
	else:
		print("PASS: disabling look frees the cursor and stops the camera")


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	return event
