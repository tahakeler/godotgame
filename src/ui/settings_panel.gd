class_name SettingsPanel
extends Control

## Reusable settings form. Instanced by both the main menu and the pause menu
## so the two never drift apart.

signal closed()

## Sensitivity is stored in radians-per-pixel, which is a meaningless number to
## a player. The slider works in 1-10 and converts at the boundary.
const SENSITIVITY_MIN := 0.0008
const SENSITIVITY_MAX := 0.0055

@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _invert_check: CheckButton = %InvertCheck
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value: Label = %VolumeValue
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _difficulty_options: OptionButton = %DifficultyOptions
@onready var _difficulty_detail: Label = %DifficultyDetail
@onready var _back_button: Button = %BackButton

var _settings: GameSettings


func _ready() -> void:
	_settings = GameSettings.instance(self)
	_populate_difficulties()
	_back_button.pressed.connect(func() -> void: closed.emit())

	# No autoload means this scene was loaded by a headless check rather than
	# by the game. The form still builds; it just has nothing to bind to.
	if _settings == null:
		return

	_load_from_settings()

	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_invert_check.toggled.connect(_on_invert_toggled)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_difficulty_options.item_selected.connect(_on_difficulty_selected)


func focus_first_control() -> void:
	_sensitivity_slider.grab_focus()


func _populate_difficulties() -> void:
	_difficulty_options.clear()
	for value in GameSettings.DIFFICULTY_NAMES:
		_difficulty_options.add_item(GameSettings.DIFFICULTY_NAMES[value], value)


func _load_from_settings() -> void:
	var sensitivity_fraction := inverse_lerp(
		SENSITIVITY_MIN, SENSITIVITY_MAX, _settings.mouse_sensitivity
	)
	_sensitivity_slider.value = clampf(sensitivity_fraction, 0.0, 1.0) * 9.0 + 1.0
	_update_sensitivity_label()

	_invert_check.button_pressed = _settings.invert_look_y
	_volume_slider.value = _settings.master_volume * 100.0
	_update_volume_label()
	_fullscreen_check.button_pressed = _settings.fullscreen
	_difficulty_options.select(_difficulty_options.get_item_index(_settings.difficulty))
	_update_difficulty_detail()


func _on_sensitivity_changed(value: float) -> void:
	_settings.mouse_sensitivity = lerpf(
		SENSITIVITY_MIN, SENSITIVITY_MAX, (value - 1.0) / 9.0
	)
	_update_sensitivity_label()
	_settings.save_settings()


func _on_invert_toggled(pressed: bool) -> void:
	_settings.invert_look_y = pressed
	_settings.save_settings()


func _on_volume_changed(value: float) -> void:
	_settings.master_volume = value / 100.0
	_update_volume_label()
	_settings.apply_audio()
	_settings.save_settings()


func _on_fullscreen_toggled(pressed: bool) -> void:
	_settings.fullscreen = pressed
	_settings.apply_window()
	_settings.save_settings()


func _on_difficulty_selected(index: int) -> void:
	_settings.difficulty = _difficulty_options.get_item_id(index) as GameSettings.Difficulty
	_update_difficulty_detail()
	_settings.save_settings()


func _update_sensitivity_label() -> void:
	_sensitivity_value.text = "%.1f" % _sensitivity_slider.value


func _update_volume_label() -> void:
	_volume_value.text = "%d%%" % roundi(_volume_slider.value)


func _update_difficulty_detail() -> void:
	var profile := _settings.get_profile()
	_difficulty_detail.text = (
		"%ds extraction  ·  %d spare rounds  ·  %s damage taken  ·  %s spawn rate"
		% [
			int(profile.extraction_duration),
			profile.starting_reserve,
			_format_scale(profile.damage_scale),
			_format_scale(1.0 / profile.spawn_interval_scale),
		]
	)


func _format_scale(scale: float) -> String:
	return "%d%%" % roundi(scale * 100.0)
