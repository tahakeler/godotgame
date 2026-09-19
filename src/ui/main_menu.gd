extends Control

## Entry scene. Starts a round, opens settings, or quits.

const GAME_SCENE := "res://src/core/game.tscn"

@onready var _main_panel: Control = %MainPanel
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _play_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _difficulty_hint: Label = %DifficultyHint

var _settings: GameSettings


func _ready() -> void:
	# Arriving from a round leaves the cursor captured.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_settings = GameSettings.instance(self)

	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_panel.closed.connect(_on_settings_closed)

	_settings_panel.visible = false
	_play_button.grab_focus()
	_refresh_difficulty_hint()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_settings_pressed() -> void:
	_main_panel.visible = false
	_settings_panel.visible = true
	_settings_panel.focus_first_control()


func _on_settings_closed() -> void:
	_settings_panel.visible = false
	_main_panel.visible = true
	_play_button.grab_focus()
	_refresh_difficulty_hint()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _refresh_difficulty_hint() -> void:
	if _settings == null:
		return
	_difficulty_hint.text = "Difficulty: %s" % _settings.get_difficulty_name()
