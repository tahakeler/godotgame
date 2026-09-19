extends Node3D

## Entry scene. The cave itself is the backdrop — a slow camera orbit inside the
## real arena rather than a flat image, so the menu shows the game it leads into.

const GAME_SCENE := "res://src/core/game.tscn"

@export_group("Backdrop camera")
@export var orbit_radius := 9.0
@export var orbit_height := 5.2
@export var orbit_speed := 0.055
@export var look_height := 0.3

@export_group("Presentation")
@export var fade_duration := 0.9

@onready var _camera: Camera3D = $MenuCamera
@onready var _main_panel: Control = %MainPanel
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _play_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _difficulty_hint: Label = %DifficultyHint
@onready var _fade: ColorRect = %Fade

var _settings: GameSettings
var _orbit_angle := 0.0


func _ready() -> void:
	# Arriving back from a round leaves the cursor captured.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_settings = GameSettings.instance(self)

	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_panel.closed.connect(_on_settings_closed)

	_settings_panel.visible = false
	_play_button.grab_focus()
	_refresh_difficulty_hint()
	_fade_in()


func _process(delta: float) -> void:
	_orbit_angle += orbit_speed * delta

	_camera.position = Vector3(
		cos(_orbit_angle) * orbit_radius,
		orbit_height,
		sin(_orbit_angle) * orbit_radius
	)
	_camera.look_at(Vector3(0.0, look_height, 0.0), Vector3.UP)


func _fade_in() -> void:
	_fade.color.a = 1.0
	create_tween().tween_property(_fade, "color:a", 0.0, fade_duration)


func _on_play_pressed() -> void:
	# Fade out before switching, so the round does not snap in.
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.35)
	tween.tween_callback(func() -> void:
		get_tree().change_scene_to_file(GAME_SCENE)
	)


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
	_difficulty_hint.text = _settings.get_difficulty_name().to_upper()
