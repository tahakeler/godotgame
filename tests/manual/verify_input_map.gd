extends SceneTree

## Verifies every game action is reachable from both a keyboard/mouse and a
## gamepad, which `.claude/rules/ui-code.md` requires.
##
## This checks the whole input map rather than a fixed list, so it fails when
## somebody adds a *new* action and binds only a key. That is the failure worth
## catching: gamepad support does not break loudly, it just quietly stops
## covering the newest thing in the game, and nobody notices until a player
## without a keyboard cannot do it.
##
##   Godot --headless --script tests/manual/verify_input_map.gd

const PREFIX := "input/"
const PROJECT_FILE := "res://project.godot"

var _failures: Array[String] = []


func _initialize() -> void:
	var actions := _project_actions()

	if actions.is_empty():
		_failures.append("no actions found in the input map at all")

	test_input_map_every_action_has_a_keyboard_or_mouse_binding(actions)
	test_input_map_every_action_has_a_gamepad_binding(actions)
	test_input_map_stick_axes_are_bound_in_opposing_pairs(actions)

	_report()


func test_input_map_every_action_has_a_keyboard_or_mouse_binding(
		actions: Dictionary) -> void:
	# Arrange / Act
	var missing := _actions_without(actions, [
		"InputEventKey", "InputEventMouseButton",
	])

	# Assert
	if missing.is_empty():
		print("PASS: every action has a keyboard or mouse binding")
	else:
		_failures.append(
			"no keyboard or mouse binding for: %s" % ", ".join(missing)
		)


func test_input_map_every_action_has_a_gamepad_binding(actions: Dictionary) -> void:
	# Arrange / Act
	var missing := _actions_without(actions, [
		"InputEventJoypadButton", "InputEventJoypadMotion",
	])

	# Assert
	if missing.is_empty():
		print("PASS: every action has a gamepad binding")
	else:
		_failures.append("no gamepad binding for: %s" % ", ".join(missing))


## Both directions of a stick axis must exist, or the player can turn one way
## and not back — which reads as the stick being broken rather than unbound.
func test_input_map_stick_axes_are_bound_in_opposing_pairs(actions: Dictionary) -> void:
	# Arrange: collect the signed axis values bound for each joypad axis.
	var by_axis := {}

	for action in actions:
		for event in actions[action]:
			if not (event is InputEventJoypadMotion):
				continue
			var values: Array = by_axis.get(event.axis, [])
			values.append(event.axis_value)
			by_axis[event.axis] = values

	# Act / Assert
	var broken: Array[String] = []

	for axis in by_axis:
		var values: Array = by_axis[axis]
		# A trigger rests at one end and only ever reads positive, so a single
		# direction is correct there rather than a missing half.
		if axis == JOY_AXIS_TRIGGER_LEFT or axis == JOY_AXIS_TRIGGER_RIGHT:
			continue

		var has_negative := values.any(func(v: float) -> bool: return v < 0.0)
		var has_positive := values.any(func(v: float) -> bool: return v > 0.0)

		if not (has_negative and has_positive):
			broken.append("axis %d" % axis)

	if broken.is_empty():
		print("PASS: every stick axis is bound in both directions")
	else:
		_failures.append("only one direction bound on: %s" % ", ".join(broken))


## action name -> its bound events, for actions this project declares.
##
## Read from project.godot rather than from ProjectSettings.get_property_list(),
## which also reports the ~90 built-in `ui_*` editor actions. Those are the
## engine's, not ours, and most are text-editing commands that have no business
## being on a gamepad — asserting over them buries the actions that matter in
## noise. The file's [input] section is exactly what this project declared.
func _project_actions() -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(PROJECT_FILE)

	if error != OK:
		_failures.append("could not read %s (error %d)" % [PROJECT_FILE, error])
		return {}

	if not config.has_section("input"):
		_failures.append("project.godot declares no [input] section")
		return {}

	var actions := {}

	for action in config.get_section_keys("input"):
		# Values come back through ProjectSettings so the events arrive as real
		# InputEvent objects regardless of how the file spells them.
		var entry = ProjectSettings.get_setting(PREFIX + action)
		if entry is Dictionary:
			actions[action] = entry.get("events", [])

	return actions


## Actions bound to none of the given event classes.
func _actions_without(actions: Dictionary, classes: Array) -> Array[String]:
	var missing: Array[String] = []

	for action in actions:
		var found := false
		for event in actions[action]:
			if event != null and event.get_class() in classes:
				found = true
				break

		if not found:
			missing.append(action)

	missing.sort()
	return missing


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
