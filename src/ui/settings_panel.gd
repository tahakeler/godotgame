class_name SettingsPanel
extends Control

## Reusable settings form. Instanced by both the main menu and the pause menu
## so the two never drift apart.

signal closed()

## Sensitivity is stored in radians-per-pixel, which is a meaningless number to
## a player. The slider works in 1-10 and converts at the boundary.
const SENSITIVITY_MIN := 0.0008
const SENSITIVITY_MAX := 0.0055

## Stick turn rate in radians per second at full deflection. The floor is a
## deliberate half-turn per second: anything slower cannot get you facing a
## zombie that has walked up behind you.

@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _invert_check: Button = %InvertCheck
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value: Label = %VolumeValue
@onready var _music_slider: HSlider = %MusicSlider
@onready var _music_value: Label = %MusicValue
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _sfx_value: Label = %SfxValue
@onready var _fov_slider: HSlider = %FovSlider
@onready var _fov_value: Label = %FovValue
@onready var _fullscreen_check: Button = %FullscreenCheck
@onready var _difficulty_options: OptionButton = %DifficultyOptions
@onready var _quality_options: OptionButton = %QualityOptions
@onready var _difficulty_detail: Label = %DifficultyDetail
@onready var _colour_mode_options: OptionButton = %ColourModeOptions
@onready var _interface_scale_slider: HSlider = %InterfaceScaleSlider
@onready var _interface_scale_value: Label = %InterfaceScaleValue
@onready var _shake_slider: HSlider = %ShakeSlider
@onready var _shake_value: Label = %ShakeValue
@onready var _flash_check: Button = %FlashCheck
@onready var _back_button: Button = %BackButton

var _settings: GameSettings


func _ready() -> void:
	_settings = GameSettings.instance(self)
	_populate_difficulties()
	_populate_qualities()
	_populate_colour_modes()
	_back_button.pressed.connect(func() -> void: closed.emit())

	# No autoload means this scene was loaded by a headless check rather than
	# by the game. The form still builds; it just has nothing to bind to.
	if _settings == null:
		return

	_load_from_settings()

	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_invert_check.toggled.connect(_on_invert_toggled)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_fov_slider.value_changed.connect(_on_fov_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_difficulty_options.item_selected.connect(_on_difficulty_selected)
	_quality_options.item_selected.connect(_on_quality_selected)
	_colour_mode_options.item_selected.connect(_on_colour_mode_selected)
	_interface_scale_slider.value_changed.connect(_on_interface_scale_changed)
	_shake_slider.value_changed.connect(_on_shake_changed)
	_flash_check.toggled.connect(_on_flash_toggled)


func focus_first_control() -> void:
	_sensitivity_slider.grab_focus()


func _populate_qualities() -> void:
	_quality_options.clear()
	for value in GameSettings.QUALITY_NAMES:
		_quality_options.add_item(GameSettings.QUALITY_NAMES[value], value)


func _on_quality_selected(index: int) -> void:
	_settings.quality = _quality_options.get_item_id(index) as GameSettings.Quality
	_settings.save_settings()


func _populate_colour_modes() -> void:
	_colour_mode_options.clear()
	for value in GameSettings.COLOUR_MODE_NAMES:
		_colour_mode_options.add_item(GameSettings.COLOUR_MODE_NAMES[value], value)


## Colour choices apply immediately. A player picking a colour mode is trying
## to find out whether they can read the HUD, and that question is unanswerable
## if the change only takes effect on the next round.
func _on_colour_mode_selected(index: int) -> void:
	_settings.colour_mode = (
		_colour_mode_options.get_item_id(index) as GameSettings.ColourMode
	)
	_settings.save_settings()


func _on_interface_scale_changed(value: float) -> void:
	_settings.interface_scale = value / 100.0
	_interface_scale_value.text = "%d%%" % roundi(value)
	_settings.apply_interface_scale()
	_settings.save_settings()


func _on_shake_changed(value: float) -> void:
	_settings.shake_scale = value / 100.0
	_shake_value.text = "%d%%" % roundi(value)
	_settings.save_settings()


func _on_flash_toggled(pressed: bool) -> void:
	_settings.reduce_flashing = pressed
	_flash_check.text = "ON" if pressed else "OFF"
	_settings.save_settings()


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
	_invert_check.text = "ON" if _settings.invert_look_y else "OFF"
	_volume_slider.value = _settings.master_volume * 100.0
	_update_volume_label()
	_music_slider.value = _settings.music_volume * 100.0
	_music_value.text = "%d%%" % roundi(_music_slider.value)
	_sfx_slider.value = _settings.sfx_volume * 100.0
	_sfx_value.text = "%d%%" % roundi(_sfx_slider.value)
	_fov_slider.value = _settings.field_of_view
	_fov_value.text = "%d" % roundi(_fov_slider.value)
	_fullscreen_check.button_pressed = _settings.fullscreen
	_fullscreen_check.text = "ON" if _settings.fullscreen else "OFF"
	_colour_mode_options.select(
		_colour_mode_options.get_item_index(_settings.colour_mode)
	)
	_interface_scale_slider.value = _settings.interface_scale * 100.0
	_interface_scale_value.text = "%d%%" % roundi(_interface_scale_slider.value)
	_shake_slider.value = _settings.shake_scale * 100.0
	_shake_value.text = "%d%%" % roundi(_shake_slider.value)
	_flash_check.button_pressed = _settings.reduce_flashing
	_flash_check.text = "ON" if _settings.reduce_flashing else "OFF"

	_difficulty_options.select(_difficulty_options.get_item_index(_settings.difficulty))
	_quality_options.select(_quality_options.get_item_index(_settings.quality))
	_update_difficulty_detail()


func _on_sensitivity_changed(value: float) -> void:
	_settings.mouse_sensitivity = lerpf(
		SENSITIVITY_MIN, SENSITIVITY_MAX, (value - 1.0) / 9.0
	)
	_update_sensitivity_label()
	_settings.save_settings()






func _on_music_changed(value: float) -> void:
	_settings.music_volume = value / 100.0
	_music_value.text = "%d%%" % roundi(value)
	_settings.apply_audio()
	_settings.save_settings()


func _on_sfx_changed(value: float) -> void:
	_settings.sfx_volume = value / 100.0
	_sfx_value.text = "%d%%" % roundi(value)
	_settings.apply_audio()
	_settings.save_settings()


## FOV reaches the camera through the settings `changed` signal, which Game
## listens to — the panel never touches the player itself. Wide FOV is a
## motion-sickness remedy, so it has to be adjustable mid-round and visible
## while being adjusted, not on the next restart.
func _on_fov_changed(value: float) -> void:
	_settings.field_of_view = value
	_fov_value.text = "%d" % roundi(value)
	_settings.save_settings()


func _on_invert_toggled(pressed: bool) -> void:
	_settings.invert_look_y = pressed
	_invert_check.text = "ON" if pressed else "OFF"
	_settings.save_settings()


func _on_volume_changed(value: float) -> void:
	_settings.master_volume = value / 100.0
	_update_volume_label()
	_settings.apply_audio()
	_settings.save_settings()


func _on_fullscreen_toggled(pressed: bool) -> void:
	_settings.fullscreen = pressed
	_fullscreen_check.text = "ON" if pressed else "OFF"
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
