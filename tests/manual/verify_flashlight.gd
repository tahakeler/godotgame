extends SceneTree

## Verifies the torch toggles, reports, and does not start lit.
##
## The failure worth guarding is silent: a torch wired to an action that has no
## binding, or a light left permanently visible, both look like a working
## flashlight in a screenshot. Only the state transitions say otherwise.
##
##   Godot --headless --script tests/manual/verify_flashlight.gd

const GAME_SCENE := "res://src/core/game.tscn"

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
