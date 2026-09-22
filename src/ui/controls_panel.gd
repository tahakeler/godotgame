class_name ControlsPanel
extends Control

## The control reference, generated from the live InputMap.
##
## Nothing here lists a key. The bindings are read from `InputMap` at runtime,
## so an action added to project.godot appears on this screen the next time it
## opens, whether or not anyone remembered to update the UI.
##
## That is the whole point. The screen this replaces was a single hand-typed
## line in main_menu.tscn, and it went stale twice: the flashlight was missing
## from it for several commits, and sprint and crouch had to be added by hand
## after the fact. A player reading a wrong control list is worse off than one
## reading none, because they stop looking for the control that does exist.
##
## What IS hand-written is the label and the grouping — "move_forward" is not a
## sentence, and a flat alphabetical list buries Fire between Flashlight and
## Jump. An action with no entry in the table still renders, under Other, with
## its name tidied up; it is never dropped.

signal closed()

## Engine-supplied menu navigation actions. Filtered out because "ui_accept" is
## not a game control, and a player hunting for the reload key should not have
## to read past twenty of them first.
const BUILTIN_PREFIX := "ui_"

## action name -> the words a player would use for it.
const ACTION_LABELS := {
	"move_forward": "Move forward",
	"move_back": "Move back",
	"move_left": "Strafe left",
	"move_right": "Strafe right",
	"sprint": "Sprint",
	"crouch": "Crouch",
	"jump": "Jump",
	"look_left": "Look left",
	"look_right": "Look right",
	"look_up": "Look up",
	"look_down": "Look down",
	"fire": "Fire",
	"reload": "Reload",
	"flashlight": "Flashlight",
	"throw_decoy": "Throw decoy",
	"pause": "Pause",
	"restart": "Restart round",
}

## Display order. Actions are drawn group by group in this order; anything the
## table does not mention falls through to the trailing Other group, which is
## how a newly added action reaches the screen without this file changing.
const GROUPS := [
	{
		"title": "M O V E M E N T",
		"actions": [
			"move_forward", "move_back", "move_left", "move_right",
			"sprint", "crouch", "jump",
		],
	},
	{
		"title": "L O O K",
		"actions": ["look_up", "look_down", "look_left", "look_right"],
	},
	{
		"title": "C O M B A T",
		"actions": ["fire", "reload"],
	},
	{
		"title": "E Q U I P M E N T",
		"actions": ["flashlight", "throw_decoy"],
	},
	{
		"title": "S Y S T E M",
		"actions": ["pause", "restart"],
	},
]

const OTHER_GROUP_TITLE := "O T H E R"

## Xbox-style face names. The project's pad bindings are authored against this
## layout, and it is the one printed on most PC controllers.
const MOUSE_BUTTON_NAMES := {
	MOUSE_BUTTON_LEFT: "Left Mouse",
	MOUSE_BUTTON_RIGHT: "Right Mouse",
	MOUSE_BUTTON_MIDDLE: "Middle Mouse",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
}

## Shown for the one input the InputMap cannot describe: the mouse itself is
## not bound to an action, it is read as relative motion by the player camera.
const MOUSE_LOOK_NOTE := "Aiming with a mouse is always available — the camera reads it as motion rather than as a binding."

## Placeholder for an action with no binding of that kind at all.
const UNBOUND := "—"

@onready var _entries: VBoxContainer = %Entries
@onready var _back_button: Button = %BackButton

var _listed_actions: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: closed.emit())
	rebuild()


## Move focus onto something a d-pad can drive. Every screen owns an entry
## point for focus rather than assuming a click put it somewhere, because the
## game's primary input has no cursor.
func focus_first_control() -> void:
	_back_button.grab_focus()


## Every action this screen is currently displaying. Exposed so a test can
## assert the screen has not silently dropped one.
func listed_actions() -> PackedStringArray:
	return _listed_actions


## The game actions worth showing, in InputMap order. Static so a test can ask
## the same question without building the scene.
static func game_actions() -> PackedStringArray:
	var actions := PackedStringArray()
	for action in InputMap.get_actions():
		if String(action).begins_with(BUILTIN_PREFIX):
			continue
		actions.append(String(action))
	return actions


## Read the InputMap and lay the screen out from scratch. Called on open rather
## than only from _ready, so the screen is correct even if a binding changed
## while it was closed.
func rebuild() -> void:
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()

	_listed_actions = PackedStringArray()

	var remaining := game_actions()

	for group in GROUPS:
		var present: Array[String] = []
		for action in group.actions:
			if remaining.has(action):
				present.append(action)

		if present.is_empty():
			continue

		_add_group(group.title, present)
		for action in present:
			remaining.remove_at(remaining.find(action))

	# Whatever the table did not claim. This branch is the anti-staleness
	# guarantee: an action nobody told this screen about still reaches a player.
	if not remaining.is_empty():
		var leftovers: Array[String] = []
		for action in remaining:
			leftovers.append(action)
		_add_group(OTHER_GROUP_TITLE, leftovers)

	_add_spacer(14)
	_add_note(MOUSE_LOOK_NOTE)


func _add_group(title: String, actions: Array[String]) -> void:
	_add_heading(title)
	for action in actions:
		_add_row(action)
	_add_spacer(16)


func _add_row(action: String) -> void:
	_listed_actions.append(action)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, 30)

	row.add_child(_cell(label_for(action), 220, Color(0.792, 0.808, 0.839)))
	row.add_child(_cell(keyboard_binding(action), 230, Color(0.957, 0.949, 0.933)))

	_entries.add_child(row)


func _cell(text: String, width: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", colour)
	return label


## Human-readable name for an action, falling back to a tidied version of the
## action string so an unknown action is still readable rather than raw.
static func label_for(action: String) -> String:
	if ACTION_LABELS.has(action):
		return ACTION_LABELS[action]
	return action.replace("_", " ").capitalize()


## The keyboard and mouse bindings for an action, or a dash when it has none.
static func keyboard_binding(action: String) -> String:
	return _join(_describe(action))




static func _join(parts: Array[String]) -> String:
	if parts.is_empty():
		return UNBOUND
	return "  /  ".join(parts)


## Describe every event bound to an action, keeping either the pad events or
## everything else. Unknown event types fall back to the engine's own text, so
## a binding is never silently invisible.
static func _describe(action: String) -> Array[String]:
	var parts: Array[String] = []

	if not InputMap.has_action(action):
		return parts

	for event in InputMap.action_get_events(action):
		var text := _describe_event(event)
		if text != "" and not parts.has(text):
			parts.append(text)

	return parts


static func _describe_event(event: InputEvent) -> String:
	if event is InputEventKey:
		# Physical codes are what this project binds, so that a French keyboard
		# gets the same three keys under the same three fingers as a US one.
		var key_event := event as InputEventKey
		var code: int = key_event.physical_keycode
		if code == 0:
			code = key_event.keycode
		return OS.get_keycode_string(code as Key)

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return MOUSE_BUTTON_NAMES.get(
			mouse_event.button_index, "Mouse %d" % mouse_event.button_index
		)

	return event.as_text()



func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.878, 0.631, 0.235))
	_entries.add_child(label)
	_add_spacer(8)


func _add_note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.514, 0.541, 0.588))
	_entries.add_child(label)


func _add_spacer(height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	_entries.add_child(spacer)
