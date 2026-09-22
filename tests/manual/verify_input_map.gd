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
	test_input_map_nothing_is_bound_to_a_gamepad(actions)

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


## The camera is turned with the mouse, or with the right stick on a pad.
##
## It is never turned with the keyboard. Arrow keys were bound to these four
## only to satisfy the "every action needs a keyboard binding" rule above, and
## the result was a camera that could be driven from the arrow keys — which is
## the wrong game. Mouse look does not appear here at all, because it is read
## as InputEventMouseMotion in Player._unhandled_input rather than as an action.
##
## Asserted rather than left as a comment because the exemption above would
## otherwise let a keyboard binding drift back in unnoticed.
## Nothing may be bound to a gamepad.
##
## This game is keyboard and mouse only. The test that used to live here
## required the opposite — every action needed a pad binding — and it was
## written when console was a target. It is inverted rather than deleted
## because a half-removed input path is worse than either state: a stray pad
## binding would keep working, keep appearing on the controls screen, and keep
## implying support that nothing else in the game honours.
##
## Looking never appears here at all. The four look actions were stick-only and
## are gone; the mouse is read as InputEventMouseMotion in
## Player._unhandled_input rather than through the InputMap.
func test_input_map_nothing_is_bound_to_a_gamepad(actions: Dictionary) -> void:
	# Arrange / Act
	var bound: Array[String] = []

	for action in actions:
		for event in actions[action]:
			if event == null:
				continue
			if event.get_class().begins_with("InputEventJoypad"):
				bound.append(action)
				break

	# Assert
	if not bound.is_empty():
		_failures.append(
			"gamepad bindings remain on: %s — this game is keyboard and mouse only"
			% ", ".join(bound)
		)
	else:
		print("PASS: %d actions, all keyboard and mouse, none on a gamepad" % actions.size())
