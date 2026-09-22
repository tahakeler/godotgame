class_name PauseMenu
extends CanvasLayer

## In-round pause. Shares the same SettingsPanel scene as the main menu, so a
## change made mid-round behaves identically to one made before starting.

signal resumed()
signal quit_to_menu()
## Asked for, not done. The pause menu does not know how to restart a round and
## must not learn: Game owns round state, and a UI that reset it directly would
## be the one place in the project where a screen mutates the game.
signal restart_requested()

const MAIN_MENU_SCENE := "res://src/ui/main_menu.tscn"

@onready var _root: Control = %Root
@onready var _buttons: Control = %Buttons
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _controls_panel: ControlsPanel = %ControlsPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _settings_button: Button = %SettingsButton
@onready var _controls_button: Button = %ControlsButton
@onready var _menu_button: Button = %MenuButton
@onready var _quit_button: Button = %QuitButton

var _is_open := false


func _ready() -> void:
	# Keep processing while the tree is paused, otherwise the menu cannot
	# receive the input that closes it.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root.visible = false
	_settings_panel.visible = false
	_controls_panel.visible = false

	_resume_button.pressed.connect(close)
	_restart_button.pressed.connect(_on_restart_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_controls_button.pressed.connect(_on_controls_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_panel.closed.connect(_on_settings_closed)
	_controls_panel.closed.connect(_on_controls_closed)


## Closing is handled here rather than in Game, which is paused and therefore
## receives no input at all while this menu is up. The pause control has to
## close what it opened, and a trackpad is awkward enough that the keyboard must reach Resume
## with in the first place.
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or not event.is_action_pressed("pause"):
		return

	# Step back out of settings rather than out of the game: a player deep in a
	# submenu means to leave the submenu.
	if _settings_panel.visible:
		_on_settings_closed()
	elif _controls_panel.visible:
		_on_controls_closed()
	else:
		close()

	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _is_open


func open() -> void:
	if _is_open:
		return

	_is_open = true
	_root.visible = true
	_buttons.visible = true
	_settings_panel.visible = false
	_controls_panel.visible = false

	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_resume_button.grab_focus()


func close() -> void:
	if not _is_open:
		return

	_is_open = false
	_root.visible = false
	get_tree().paused = false
	resumed.emit()


func _on_settings_pressed() -> void:
	_buttons.visible = false
	_settings_panel.visible = true
	_settings_panel.focus_first_control()


func _on_settings_closed() -> void:
	_settings_panel.visible = false
	_buttons.visible = true
	_resume_button.grab_focus()


func _on_controls_pressed() -> void:
	_buttons.visible = false
	_controls_panel.visible = true
	# Rebuilt on open: a control list is only worth having if it is current.
	_controls_panel.rebuild()
	_controls_panel.focus_first_control()


func _on_controls_closed() -> void:
	_controls_panel.visible = false
	_buttons.visible = true
	_controls_button.grab_focus()


## Restarting closes the menu first. The round Game is about to build should
## start with the tree running and the cursor captured, exactly as it would
## from a fresh Play — a restart that begins paused reads as a hang.
func _on_restart_pressed() -> void:
	close()
	restart_requested.emit()


func _on_quit_pressed() -> void:
	# Unpause on the way out so nothing is left half-stopped if the quit is
	# vetoed by the window manager.
	get_tree().paused = false
	get_tree().quit()


func _on_menu_pressed() -> void:
	# Unpause before leaving, or the menu scene inherits a paused tree.
	get_tree().paused = false
	_is_open = false
	quit_to_menu.emit()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
