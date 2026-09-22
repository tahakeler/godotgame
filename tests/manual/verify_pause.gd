extends SceneTree

## Verifies the pause control both opens and closes the pause menu.
##
## Regression test. Pausing was polled from Game._process, and Game stops
## processing the moment the tree pauses — so the control opened the menu and
## then went dead, leaving the mouse and the Resume button as the only way back
## into the round. A laptop trackpad is awkward mid-fight, so the
## round was simply unrecoverable.
##
## This drives real input events rather than calling the handlers, because the
## bug was not in the handlers. Both were correct; the input never arrived.
##
##   Godot --headless --script tests/manual/verify_pause.gd

const GAME_SCENE := "res://src/core/game.tscn"

## Steps run one per frame: an injected event is not delivered until the next
## input flush, so asserting in the same frame that sent it would always read
## the state from before the press.
enum Step { WARMUP, SEND_OPEN, ASSERT_OPEN, ASSERT_CLOSED, DONE }

var _game: Game
var _step: int = Step.WARMUP
var _failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	match _step:
		Step.WARMUP:
			# @onready vars are not assigned until _ready() runs.
			pass

		Step.SEND_OPEN:
			test_pause_starts_closed()
			_press("pause")

		Step.ASSERT_OPEN:
			test_pause_action_opens_the_menu_and_pauses_the_tree()
			_press("pause")

		Step.ASSERT_CLOSED:
			test_pause_action_closes_the_menu_and_resumes_the_tree()

		Step.DONE:
			_report()
			return true

	_step += 1
	return false


func test_pause_starts_closed() -> void:
	# Arrange / Act: a round has just started.
	# Assert
	if _game.pause_menu.is_open():
		_failures.append("the pause menu was already open when the round began")
	elif root.get_tree().paused:
		_failures.append("the tree was already paused when the round began")
	else:
		print("PASS: a round starts unpaused")


func test_pause_action_opens_the_menu_and_pauses_the_tree() -> void:
	# Arrange / Act: the pause action was pressed on the previous frame.
	# Assert
	if not _game.pause_menu.is_open():
		_failures.append("the pause action did not open the pause menu")
	elif not root.get_tree().paused:
		_failures.append("the pause menu opened but the tree kept running")
	else:
		print("PASS: the pause action opens the menu and pauses the round")


func test_pause_action_closes_the_menu_and_resumes_the_tree() -> void:
	# Arrange / Act: the pause action was pressed again while paused.
	# Assert
	if _game.pause_menu.is_open():
		_failures.append(
			"the pause action did not close the menu it opened — "
			+ "the round can only be resumed with a mouse"
		)
	elif root.get_tree().paused:
		_failures.append("the pause menu closed but the tree stayed paused")
	else:
		print("PASS: the pause action closes the menu and resumes the round")


## Inject a press and release of an action, as the input system would deliver
## it. The release matters: a held action left pressed would make the next
## is_action_pressed read as a fresh press.
func _press(action: String) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)

	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
