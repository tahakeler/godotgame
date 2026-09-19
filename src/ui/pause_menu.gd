class_name PauseMenu
extends CanvasLayer

## In-round pause. Shares the same SettingsPanel scene as the main menu, so a
## change made mid-round behaves identically to one made before starting.

signal resumed()
signal quit_to_menu()

const MAIN_MENU_SCENE := "res://src/ui/main_menu.tscn"

@onready var _root: Control = %Root
@onready var _buttons: Control = %Buttons
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _menu_button: Button = %MenuButton

var _is_open := false


func _ready() -> void:
	# Keep processing while the tree is paused, otherwise the menu cannot
	# receive the input that closes it.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root.visible = false
	_settings_panel.visible = false

	_resume_button.pressed.connect(close)
	_settings_button.pressed.connect(_on_settings_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_settings_panel.closed.connect(_on_settings_closed)


func is_open() -> bool:
	return _is_open


func open() -> void:
	if _is_open:
		return

	_is_open = true
	_root.visible = true
	_buttons.visible = true
	_settings_panel.visible = false

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


func _on_menu_pressed() -> void:
	# Unpause before leaving, or the menu scene inherits a paused tree.
	get_tree().paused = false
	_is_open = false
	quit_to_menu.emit()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
