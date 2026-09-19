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
			pass

		Step.SEND:
			print("mouse mode after a round starts: %s" % _mode_name())
			_yaw_before = _game.player.rotation.y
			_pitch_before = _game.player.head.rotation.x
			_send_motion(MOTION)

		Step.ASSERT:
			test_look_mouse_motion_turns_the_player()
			test_look_mouse_motion_pitches_the_camera()

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
