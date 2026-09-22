extends SceneTree

## Verifies the out-of-game menus: the controls screen, the settings form, the
## navigation between screens, and keyboard reachability.
##
## These assert on the things that rot silently. A menu does not break loudly —
## it keeps rendering a control list that stopped being true three commits ago,
## or a slider whose signal was never connected, and nothing reports it until a
## player writes in. So each test here is aimed at a specific way this UI has
## gone wrong or could:
##
##   - the control list was hand-typed and went stale twice
##   - a settings row can be added to the scene and never wired to the settings
##     object, which looks identical to a working one until you restart
##   - a screen can become unreachable when a button is renamed
##   - a control with focus_mode NONE is invisible to a d-pad, and this game's
##     primary input is a keyboard and mouse
##
##   Godot --headless --script tests/manual/verify_menus.gd

const MAIN_MENU_SCENE := "res://src/ui/main_menu.tscn"
const SETTINGS_SCENE := "res://src/ui/settings_panel.tscn"
const CONTROLS_SCENE := "res://src/ui/controls_panel.tscn"

## Settings values written during the round-trip test. Chosen to differ from
## every default, so a value that survives cannot have survived by accident.
const PROBE_MOUSE_SENSITIVITY := 0.0031
const PROBE_MUSIC := 0.42
const PROBE_SFX := 0.31
const PROBE_FOV := 96.0
const PROBE_SHAKE := 0.25
const PROBE_INTERFACE_SCALE := 1.25

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# Autoloads exist under --script, but not until the first processed frame,
	# and @onready vars are not assigned before _ready runs either.
	if not _started:
		_started = true
		DeterministicSettings.apply(root)
		return false

	test_every_input_action_appears_on_the_controls_screen()
	test_every_action_on_the_controls_screen_shows_a_binding()
	test_settings_values_survive_a_save_and_load_round_trip()
	test_every_settings_control_is_connected_to_something()
	test_every_menu_screen_can_be_opened_and_closed()
	test_every_interactive_control_is_reachable_by_keyboard_focus()

	_report()
	return true


## The anti-staleness test. If someone adds an action to project.godot and
## tells this screen nothing, the screen must still show it.
func test_every_input_action_appears_on_the_controls_screen() -> void:
	# Arrange
	var panel := _build_controls_panel()

	# Act
	var listed := panel.listed_actions()
	var expected := ControlsPanel.game_actions()

	# Assert
	var missing: Array[String] = []
	for action in expected:
		if not listed.has(action):
			missing.append(action)

	if missing.is_empty():
		print("PASS: all %d input actions appear on the controls screen" % expected.size())
	else:
		_failures.append(
			"the controls screen does not list %s — it has gone stale against the InputMap"
			% ", ".join(missing)
		)

	panel.free()


## A row with two dashes in it is a row that tells a player nothing. Every
## action must resolve to at least one binding a person could press.
func test_every_action_on_the_controls_screen_shows_a_binding() -> void:
	# Arrange / Act
	var unbound: Array[String] = []

	for action in ControlsPanel.game_actions():
		var keyboard := ControlsPanel.keyboard_binding(action)
		if keyboard == ControlsPanel.UNBOUND:
			unbound.append(action)

	# Assert
	if unbound.is_empty():
		print("PASS: every listed action resolves to a real binding")
	else:
		_failures.append("no binding could be described for %s" % ", ".join(unbound))


## A setting that does not persist is a setting that does not exist. This
## writes through the live settings object and reads back with a second one, so
## the assertion covers the file rather than the in-memory copy.
func test_settings_values_survive_a_save_and_load_round_trip() -> void:
	# Arrange
	var settings := GameSettings.instance(root)
	if settings == null:
		_failures.append("the Settings autoload was missing, so nothing could be saved")
		return

	var restore := _snapshot(settings)

	# Act
	settings.mouse_sensitivity = PROBE_MOUSE_SENSITIVITY
	settings.music_volume = PROBE_MUSIC
	settings.sfx_volume = PROBE_SFX
	settings.field_of_view = PROBE_FOV
	settings.shake_scale = PROBE_SHAKE
	settings.interface_scale = PROBE_INTERFACE_SCALE
	settings.colour_mode = GameSettings.ColourMode.TRITANOPIA
	settings.save_settings()

	var reloaded := GameSettings.new()
	reloaded.load_settings()

	# Assert
	var drifted: Array[String] = []
	_expect_close(drifted, "mouse sensitivity", reloaded.mouse_sensitivity, PROBE_MOUSE_SENSITIVITY)
	_expect_close(drifted, "music volume", reloaded.music_volume, PROBE_MUSIC)
	_expect_close(drifted, "effects volume", reloaded.sfx_volume, PROBE_SFX)
	_expect_close(drifted, "field of view", reloaded.field_of_view, PROBE_FOV)
	_expect_close(drifted, "camera shake", reloaded.shake_scale, PROBE_SHAKE)
	_expect_close(drifted, "interface scale", reloaded.interface_scale, PROBE_INTERFACE_SCALE)

	if reloaded.colour_mode != GameSettings.ColourMode.TRITANOPIA:
		drifted.append("colour mode did not survive the save")

	if drifted.is_empty():
		print("PASS: settings survive a save and load round trip")
	else:
		_failures.append_array(drifted)

	reloaded.free()

	# Teardown: the player's own config file is external state, and a test that
	# overwrites it has broken their game to prove a point.
	_restore(settings, restore)
	settings.save_settings()


## Every interactive row in the settings form must have a listener. An
## unconnected slider slides, shows a number, and changes nothing — the exact
## failure `.claude/rules/ui-code.md` forbids.
func test_every_settings_control_is_connected_to_something() -> void:
	# Arrange
	var panel: SettingsPanel = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	root.add_child(panel)

	# Act
	var dead: Array[String] = []
	for control in _interactive_controls(panel):
		var signal_name := _change_signal_for(control)
		if signal_name == "":
			continue
		if control.get_signal_connection_list(signal_name).is_empty():
			dead.append("%s has no %s listener" % [control.name, signal_name])

	# Assert
	if dead.is_empty():
		print("PASS: every settings control is wired to a live handler")
	else:
		_failures.append_array(dead)

	panel.queue_free()


## Each screen must be reachable from the front menu and must give the player a
## way back. A screen you cannot leave from the keyboard is a soft lock.
func test_every_menu_screen_can_be_opened_and_closed() -> void:
	# Arrange
	var menu: Node = (load(MAIN_MENU_SCENE) as PackedScene).instantiate()
	root.add_child(menu)

	var screens := {
		"SettingsButton": "SettingsPanel",
		"ControlsButton": "ControlsPanel",
		"CreditsButton": "CreditsPanel",
	}

	# Act / Assert
	var broken: Array[String] = []
	for button_name in screens:
		var button := menu.find_child(button_name, true, false) as Button
		var panel := menu.find_child(screens[button_name], true, false) as Control

		if button == null or panel == null:
			broken.append("%s or %s is missing from the main menu" % [
				button_name, screens[button_name]
			])
			continue

		button.pressed.emit()
		if not panel.visible:
			broken.append("%s did not open %s" % [button_name, screens[button_name]])
			continue

		panel.closed.emit()
		if panel.visible:
			broken.append("%s could not be closed again" % screens[button_name])

	if broken.is_empty():
		print("PASS: every menu screen opens and closes (%d screens)" % screens.size())
	else:
		_failures.append_array(broken)

	menu.queue_free()


## The keyboard must reach everything: a laptop trackpad is awkward enough that
## control the player is expected to operate must be able to hold focus.
func test_every_interactive_control_is_reachable_by_keyboard_focus() -> void:
	# Arrange
	var scenes := [SETTINGS_SCENE, CONTROLS_SCENE]
	var unreachable: Array[String] = []
	var checked := 0

	# Act
	for path in scenes:
		var panel: Control = (load(path) as PackedScene).instantiate()
		root.add_child(panel)

		for control in _interactive_controls(panel):
			checked += 1
			if control.focus_mode == Control.FOCUS_NONE:
				unreachable.append("%s in %s cannot take focus" % [control.name, path])

		panel.queue_free()

	# Assert
	if unreachable.is_empty():
		print("PASS: all %d interactive controls can take keyboard focus" % checked)
	else:
		_failures.append_array(unreachable)


func _build_controls_panel() -> ControlsPanel:
	var panel: ControlsPanel = (load(CONTROLS_SCENE) as PackedScene).instantiate()
	root.add_child(panel)
	return panel


## Every control a player is meant to operate, anywhere under `node`.
func _interactive_controls(node: Node) -> Array[Control]:
	var found: Array[Control] = []

	for child in node.get_children():
		if child is Button or child is Slider or child is OptionButton:
			found.append(child as Control)
		found.append_array(_interactive_controls(child))

	return found


## The signal a given control emits when the player changes it.
func _change_signal_for(control: Control) -> String:
	if control is OptionButton:
		return "item_selected"
	if control is Slider:
		return "value_changed"
	if control is Button:
		# Toggles report through toggled; plain buttons through pressed.
		return "toggled" if (control as Button).toggle_mode else "pressed"
	return ""


func _expect_close(
	into: Array[String], label: String, actual: float, expected: float
) -> void:
	if absf(actual - expected) > 0.0001:
		into.append("%s came back as %s, not %s" % [label, actual, expected])


func _snapshot(settings: GameSettings) -> Dictionary:
	return {
		"mouse_sensitivity": settings.mouse_sensitivity,
		"music_volume": settings.music_volume,
		"sfx_volume": settings.sfx_volume,
		"field_of_view": settings.field_of_view,
		"shake_scale": settings.shake_scale,
		"interface_scale": settings.interface_scale,
		"colour_mode": settings.colour_mode,
	}


func _restore(settings: GameSettings, values: Dictionary) -> void:
	settings.mouse_sensitivity = values.mouse_sensitivity
	settings.music_volume = values.music_volume
	settings.sfx_volume = values.sfx_volume
	settings.field_of_view = values.field_of_view
	settings.shake_scale = values.shake_scale
	settings.interface_scale = values.interface_scale
	settings.colour_mode = values.colour_mode


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
