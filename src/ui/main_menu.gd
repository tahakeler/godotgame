extends Node3D

## Entry scene. The level itself is the backdrop — a slow camera pan inside the
## real arena rather than a flat image, so the menu shows the game it leads into.
##
## The camera stands in the level and looks outward. It used to orbit overhead
## at 5.2m looking down into the middle, which suited an open cave and puts the
## camera inside the ceiling of an authored dungeon — the backdrop came out
## completely black, because there is nothing to see from inside a ceiling.

const GAME_SCENE := "res://src/core/game.tscn"

## What actually changes at each difficulty, in play terms rather than raw
## multipliers. GameSettings.DIFFICULTY_PROFILES holds the numbers this
## describes, but the project's standing rule is that player-facing UI never
## shows a raw stat — so this file owns the prose translation of that table,
## the same way GameSettings.MODE_BLURBS owns the prose for modes.
const DIFFICULTY_BLURBS := {
	GameSettings.Difficulty.RECRUIT: "Zombies react slower and hit softer. Ammunition goes further.",
	GameSettings.Difficulty.SOLDIER: "The default fight — balanced pressure, balanced supply.",
	GameSettings.Difficulty.VETERAN: "Zombies notice you sooner and hit harder. Ammunition is scarcer.",
}

@export_group("Backdrop camera")
## Where the camera stands, how far it circles, and at what eye height.
##
## Small and low: the pan has to stay inside one chamber, or it walks the
## camera through a wall every few seconds.
@export var orbit_centre := Vector3.ZERO
## Where in the circle the pan begins, in degrees. Chosen so the menu opens on
## a view worth looking at rather than on whichever wall angle zero happens to
## face — in an enclosed level most bearings are a wall in shadow.
@export var orbit_start_degrees := 240.0
@export var orbit_radius := 1.6
@export var orbit_height := 1.7
@export var orbit_speed := 0.055
## How far down the corridor the camera looks, and at what height.
@export var look_distance := 9.0
@export var look_height := 1.5

@export_group("Presentation")
@export var fade_duration := 0.9

@onready var _camera: Camera3D = $MenuCamera
@onready var _main_panel: Control = %MainPanel
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _credits_panel: CreditsPanel = %CreditsPanel
@onready var _controls_panel: ControlsPanel = %ControlsPanel
@onready var _controls_button: Button = %ControlsButton
@onready var _controls_hint: Label = %ControlsHint
@onready var _credits_button: Button = %CreditsButton
@onready var _play_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _mode_panel: Control = %ModePanel
@onready var _stats_button: Button = %StatsButton
@onready var _stats_panel: Control = %StatsPanel
@onready var _stats_career: Label = %Career
@onready var _stats_breakdown: Label = %Breakdown
@onready var _stats_back_button: Button = %StatsBackButton
@onready var _mode_entries: VBoxContainer = %ModeEntries
@onready var _difficulty_panel: Control = %DifficultyPanel
@onready var _difficulty_entries: VBoxContainer = %DifficultyEntries
@onready var _fade: ColorRect = %Fade

var _settings: GameSettings

## Built once in _ready(), keyed by the enum value each button selects. Lets
## focus-on-open jump straight to the player's last choice instead of always
## landing on the first row.
var _mode_buttons: Dictionary = {}
var _mode_record_labels: Dictionary = {}
var _difficulty_buttons: Dictionary = {}

var _orbit_angle := 0.0


func _ready() -> void:
	# Arriving back from a round leaves the cursor captured.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_settings = GameSettings.instance(self)

	_play_button.pressed.connect(_on_play_pressed)
	_stats_button.pressed.connect(_on_stats_pressed)
	_stats_back_button.pressed.connect(_close_stats_panel)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_panel.closed.connect(_on_settings_closed)
	_credits_button.pressed.connect(_on_credits_pressed)
	_credits_panel.closed.connect(_on_credits_closed)
	_controls_button.pressed.connect(_on_controls_pressed)
	_controls_panel.closed.connect(_on_controls_closed)

	_settings_panel.visible = false
	_credits_panel.visible = false
	_controls_panel.visible = false
	_mode_panel.visible = false
	_difficulty_panel.visible = false
	_build_mode_panel()
	_build_difficulty_panel()
	_play_button.grab_focus()
	_refresh_controls_hint()
	_orbit_angle = deg_to_rad(orbit_start_degrees)
	_fade_in()


func _process(delta: float) -> void:
	_orbit_angle += orbit_speed * delta

	var radial := Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle))

	_camera.position = (
		orbit_centre + radial * orbit_radius + Vector3.UP * orbit_height
	)
	_camera.look_at(
		orbit_centre
			+ radial * (orbit_radius + look_distance)
			+ Vector3.UP * look_height,
		Vector3.UP
	)


## Esc backs out one step of the play flow. Settings/Controls/Credits already
## close themselves on Esc through their own `closed` signal (see
## _on_settings_closed and friends) — this only covers the two panels added
## for the flow below, which have no script of their own to own that logic.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	if _stats_panel.visible:
		get_viewport().set_input_as_handled()
		_close_stats_panel()
	elif _difficulty_panel.visible:
		get_viewport().set_input_as_handled()
		_close_difficulty_panel()
	elif _mode_panel.visible:
		get_viewport().set_input_as_handled()
		_close_mode_panel()


func _fade_in() -> void:
	_fade.color.a = 1.0
	create_tween().tween_property(_fade, "color:a", 0.0, fade_duration)


## PLAY no longer drops straight into a round. It opens the mode panel, which
## opens the difficulty panel, which is what actually starts the round — see
## _start_round(). A returning player who wants exactly what they played last
## time still only has to press Enter three times: this screen focuses their
## last mode, the next focuses their last difficulty.
func _on_play_pressed() -> void:
	_main_panel.visible = false
	_mode_panel.visible = true
	_refresh_mode_entries()
	_focus_mode_button(_settings.mode if _settings != null else GameSettings.Mode.EXTRACTION)


func _close_mode_panel() -> void:
	_mode_panel.visible = false
	_main_panel.visible = true
	_play_button.grab_focus()


## Build one row per mode: a button carrying the name, and beneath it a label
## carrying the win-condition blurb and the player's best. The blurb text and
## the best-record lookup both already existed for the old single-screen
## layout (GameSettings.get_mode_blurb, Records.best/Records.describe) — this
## just repeats them once per mode instead of once for whichever mode the
## inline cycler currently showed.
func _build_mode_panel() -> void:
	for mode: GameSettings.Mode in GameSettings.MODE_NAMES.keys():
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 4)

		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 50)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 20)
		button.text = GameSettings.MODE_NAMES[mode].to_upper()
		button.pressed.connect(_on_mode_selected.bind(mode))
		entry.add_child(button)

		var info := Label.new()
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64, 1))
		info.add_theme_font_size_override("font_size", 15)
		entry.add_child(info)

		_mode_entries.add_child(entry)
		_mode_buttons[mode] = button
		_mode_record_labels[mode] = info


## Refreshed on every open rather than trusted from _build_mode_panel(), so a
## round played earlier in this session shows up in the best-record line —
## the same reasoning ControlsPanel.rebuild() uses for its rows.
func _refresh_mode_entries() -> void:
	if _settings == null:
		return

	for mode: GameSettings.Mode in _mode_record_labels.keys():
		var label: Label = _mode_record_labels[mode]
		var record := Records.best(mode, _settings.difficulty)
		label.text = "%s     BEST  %s" % [
			GameSettings.MODE_BLURBS[mode], Records.describe(mode, record)
		]


func _focus_mode_button(mode: GameSettings.Mode) -> void:
	var button: Button = _mode_buttons.get(mode)
	if button == null and not _mode_buttons.is_empty():
		button = _mode_buttons.values()[0]
	if button != null:
		button.grab_focus()


func _on_mode_selected(mode: GameSettings.Mode) -> void:
	if _settings == null:
		return

	_settings.mode = mode
	_settings.save_settings()
	_open_difficulty_panel()


func _open_difficulty_panel() -> void:
	_mode_panel.visible = false
	_difficulty_panel.visible = true
	_focus_difficulty_button(
		_settings.difficulty if _settings != null else GameSettings.Difficulty.SOLDIER
	)


func _close_difficulty_panel() -> void:
	_difficulty_panel.visible = false
	_mode_panel.visible = true
	_refresh_mode_entries()
	_focus_mode_button(_settings.mode if _settings != null else GameSettings.Mode.EXTRACTION)


## One row per difficulty: a button carrying the name, and beneath it what the
## difficulty actually changes in play, worded from DIFFICULTY_BLURBS above
## rather than the raw scales in GameSettings.DIFFICULTY_PROFILES.
func _build_difficulty_panel() -> void:
	for difficulty: GameSettings.Difficulty in GameSettings.DIFFICULTY_NAMES.keys():
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 4)

		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 50)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 20)
		button.text = GameSettings.DIFFICULTY_NAMES[difficulty].to_upper()
		button.pressed.connect(_on_difficulty_selected.bind(difficulty))
		entry.add_child(button)

		var info := Label.new()
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64, 1))
		info.add_theme_font_size_override("font_size", 15)
		info.text = DIFFICULTY_BLURBS[difficulty]
		entry.add_child(info)

		_difficulty_entries.add_child(entry)
		_difficulty_buttons[difficulty] = button


func _focus_difficulty_button(difficulty: GameSettings.Difficulty) -> void:
	var button: Button = _difficulty_buttons.get(difficulty)
	if button == null and not _difficulty_buttons.is_empty():
		button = _difficulty_buttons.values()[0]
	if button != null:
		button.grab_focus()


func _on_difficulty_selected(difficulty: GameSettings.Difficulty) -> void:
	if _settings == null:
		return

	_settings.difficulty = difficulty
	_settings.save_settings()
	_start_round()


## The actual scene switch, unchanged from what _on_play_pressed used to do
## directly before the flow grew a mode and a difficulty step in front of it.
func _start_round() -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.35)
	tween.tween_callback(func() -> void:
		get_tree().change_scene_to_file(GAME_SCENE)
	)


## Credits are reachable from the front screen rather than buried, because a
## game that ships other people's work should say so where a player can find
## it without going looking.
func _on_credits_pressed() -> void:
	_main_panel.visible = false
	_credits_panel.visible = true
	_credits_panel.focus_first_control()


func _on_credits_closed() -> void:
	_credits_panel.visible = false
	_main_panel.visible = true
	_credits_button.grab_focus()


## The full control list gets its own screen. What stays on the front page is a
## single line naming the two or three controls a new player needs before they
## can look anything up — and even that is read from the InputMap rather than
## typed, because the line it replaced was typed and went wrong twice.
func _refresh_controls_hint() -> void:
	var highlights := ["move_forward", "fire", "reload", "pause"]
	var parts: Array[String] = []

	for action in highlights:
		if not InputMap.has_action(action):
			continue
		parts.append("%s  %s" % [
			ControlsPanel.keyboard_binding(action).to_upper(),
			ControlsPanel.label_for(action).to_upper(),
		])

	_controls_hint.text = "     ".join(parts)


func _on_controls_pressed() -> void:
	_main_panel.visible = false
	_controls_panel.visible = true
	# Rebuilt on open rather than trusted from _ready, so a binding changed
	# elsewhere in this session cannot leave a stale row on screen.
	_controls_panel.rebuild()
	_controls_panel.focus_first_control()


func _on_controls_closed() -> void:
	_controls_panel.visible = false
	_main_panel.visible = true
	_controls_button.grab_focus()


func _on_settings_pressed() -> void:
	_main_panel.visible = false
	_settings_panel.visible = true
	_settings_panel.focus_first_control()


func _on_settings_closed() -> void:
	_settings_panel.visible = false
	_main_panel.visible = true
	_play_button.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().quit()


## The STATS screen: what the player has actually done, across every run.
##
## Deliberately a record of the whole career rather than a trophy case of
## bests. A best is already shown against each mode on the way into a round,
## where it is a target; here the interesting numbers are the ones that
## accumulate, because those are the ones that say how the player plays rather
## than how well their single luckiest run went.
func _on_stats_pressed() -> void:
	_refresh_stats()
	_main_panel.visible = false
	_stats_panel.visible = true
	_stats_back_button.grab_focus()


func _close_stats_panel() -> void:
	_stats_panel.visible = false
	_main_panel.visible = true
	_stats_button.grab_focus()


func _refresh_stats() -> void:
	var career := Records.career()
	_stats_career.text = _describe_career(career)
	_stats_breakdown.text = _describe_breakdown()


## The career summary, in prose rather than a table.
##
## Accuracy is the one derived figure worth showing: it is the only number here
## the player can move deliberately, and on a map where most of a magazine goes
## into the dark it is the honest measure of whether the ammunition economy is
## being fought or wasted.
func _describe_career(career: Dictionary) -> String:
	var runs: int = career.runs_started

	if runs <= 0:
		return "No runs recorded yet. Finish one and it will show up here."

	var lines: Array[String] = []
	lines.append(
		"%s   ·   %d won   ·   %d lost"
		% [_plural(runs, "run"), career.runs_won, career.runs_lost]
	)
	lines.append(
		"%d kills   ·   %s   ·   %s survived"
		% [career.kills, _describe_accuracy(career), _describe_duration(career.duration)]
	)

	var deaths_by_kind: Dictionary = career.get("deaths_by_kind", {})
	if not deaths_by_kind.is_empty():
		lines.append(_describe_deadliest(deaths_by_kind))

	return "\n".join(lines)


## The zombie kind that has killed the player the most, across every run.
##
## Keys in deaths_by_kind round-trip through ConfigFile, which hands String
## keys back on some load paths and int keys on others depending on how the
## section was last written — int() normalizes either before it is used to
## look up both the count and the kind's display name.
func _describe_deadliest(deaths_by_kind: Dictionary) -> String:
	var best_kind := -1
	var best_count := -1

	for raw_key in deaths_by_kind:
		var kind := int(raw_key)
		var count: int = deaths_by_kind[raw_key]
		if count > best_count:
			best_kind = kind
			best_count = count

	var kind_name: String = ZombieTypes.definition(best_kind as ZombieTypes.Kind).name
	return "Most often killed by %s (%d)" % [kind_name, best_count]


## Shots hit against shots fired, or a flat statement when nothing was fired.
##
## Guarded rather than divided: a career that has started a run and quit out of
## it before shooting has a real run count and zero shots, and dividing by that
## would put "nan%" on the front page of the player's own statistics.
func _describe_accuracy(career: Dictionary) -> String:
	var fired: int = career.shots_fired

	if fired <= 0:
		return "no shots fired"

	return "%.0f%% accuracy" % (100.0 * float(career.shots_hit) / float(fired))


## One line per mode and difficulty the player has actually played.
##
## Combinations never played are left out entirely rather than listed as zeros.
## A grid of empty rows reads as a checklist of things the player has failed to
## do, which is the opposite of what a statistics screen is for.
func _describe_breakdown() -> String:
	var lines: Array[String] = []

	for mode: GameSettings.Mode in GameSettings.MODE_NAMES.keys():
		for difficulty: GameSettings.Difficulty in GameSettings.DIFFICULTY_NAMES.keys():
			var row := Records.totals(mode, difficulty)
			if row.runs_started <= 0:
				continue

			lines.append(
				"%-12s %-9s %s, %d won, %d kills   ·   best %s"
				% [
					GameSettings.MODE_NAMES[mode].to_upper(),
					GameSettings.DIFFICULTY_NAMES[difficulty].to_upper(),
					_plural(row.runs_started, "run"),
					row.runs_won,
					row.kills,
					Records.describe(mode, Records.best(mode, difficulty)),
				]
			)

	if lines.is_empty():
		return ""

	lines.insert(0, "BY MODE AND DIFFICULTY\n")
	return "\n".join(lines)


func _describe_duration(seconds: float) -> String:
	var whole := int(seconds)
	if whole < 3600:
		return "%dm" % (whole / 60)
	return "%dh %dm" % [whole / 3600, (whole % 3600) / 60]


## "1 run", "2 runs". Small, but this text sits on a screen whose whole job is
## to look considered, and "1 runs" undoes that in one glance.
func _plural(count: int, noun: String) -> String:
	if count == 1:
		return "1 %s" % noun
	return "%d %ss" % [count, noun]
