extends SceneTree

## Adds gamepad bindings to every action in the input map.
##
## Written as a script rather than edited into project.godot by hand: input
## events are stored there as serialised `Object(InputEventJoypadMotion, ...)`
## strings with a dozen fields each, and a single wrong number produces a
## binding that silently does nothing. Building the real event objects and
## letting Godot serialise them cannot get that wrong.
##
## Re-running is safe — an action that already has a joypad event is left
## alone, so this can be run again after new actions are added.
##
##   Godot --headless --script tools/bind_gamepad.gd
##
## Stick axes use a generous deadzone here, but the player applies its own
## radial deadzone on top: a per-axis deadzone lets a stick pushed diagonally
## register as a clean cardinal direction, which is why stick movement in a lot
## of games feels like it snaps to eight directions.

const AXIS_BINDINGS := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	# The right trigger, not a face button. Firing belongs under the index
	# finger on a controller for the same reason it belongs under the left
	# mouse button.
	"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}

const BUTTON_BINDINGS := {
	"jump": JOY_BUTTON_A,
	"reload": JOY_BUTTON_X,
	"throw_decoy": JOY_BUTTON_RIGHT_SHOULDER,
	"restart": JOY_BUTTON_Y,
	"pause": JOY_BUTTON_START,
}

## Actions the map may not have yet, with the keyboard fallback they need.
## Look is on the arrow keys as well so the game is playable without a mouse.
const NEW_ACTIONS := {
	"look_left": KEY_LEFT,
	"look_right": KEY_RIGHT,
	"look_up": KEY_UP,
	"look_down": KEY_DOWN,
	"throw_decoy": KEY_G,
}

const DEADZONE := 0.2


func _initialize() -> void:
	var added := 0

	for action in NEW_ACTIONS:
		if _ensure_action(action, NEW_ACTIONS[action]):
			added += 1

	for action in AXIS_BINDINGS:
		var binding: Array = AXIS_BINDINGS[action]
		var event := InputEventJoypadMotion.new()
		event.axis = binding[0]
		event.axis_value = binding[1]
		if _add_event(action, event):
			added += 1

	for action in BUTTON_BINDINGS:
		var event := InputEventJoypadButton.new()
		event.button_index = BUTTON_BINDINGS[action]
		if _add_event(action, event):
			added += 1

	if added == 0:
		print("input map already has every gamepad binding; nothing to do")
		quit(0)
		return

	var error := ProjectSettings.save()
	if error != OK:
		printerr("FAIL: could not save project settings (error %d)" % error)
		quit(1)
		return

	print("added %d binding(s) and saved project.godot" % added)
	quit(0)


## Create an action with a keyboard event if the map does not have it yet.
func _ensure_action(action: String, keycode: Key) -> bool:
	var path := "input/%s" % action
	if ProjectSettings.has_setting(path):
		return false

	var key := InputEventKey.new()
	key.physical_keycode = keycode

	ProjectSettings.set_setting(path, {
		"deadzone": DEADZONE,
		"events": [key],
	})
	print("created action %s" % action)
	return true


## Append an event to an action, unless an event of that type is already bound.
func _add_event(action: String, event: InputEvent) -> bool:
	var path := "input/%s" % action
	if not ProjectSettings.has_setting(path):
		printerr("FAIL: no such action %s" % action)
		return false

	var entry: Dictionary = ProjectSettings.get_setting(path)
	var events: Array = entry.get("events", [])

	for existing in events:
		# Matching on type rather than on the exact event: an action that
		# already responds to *some* joypad input has been bound deliberately,
		# and a second binding would fight it.
		if existing.get_class() == event.get_class():
			if existing is InputEventJoypadMotion and existing.axis != event.axis:
				continue
			return false

	events.append(event)
	entry["events"] = events
	ProjectSettings.set_setting(path, entry)

	print("bound %s -> %s" % [action, event.as_text()])
	return true
