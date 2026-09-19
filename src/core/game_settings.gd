class_name GameSettings
extends Node

## Player preferences, persisted to disk and shared across scenes.
##
## Registered as the `Settings` autoload. Holds preferences only — never round
## state — so it does not violate the project's no-singletons-for-game-state
## rule. Difficulty is stored here as a choice; the numbers it implies are read
## by Game when a round starts.
##
## Callers reach the live instance through `GameSettings.instance(node)` rather
## than the `Settings` autoload identifier. Autoloads do not exist when Godot
## runs with `--script`, and a direct reference fails to *compile*, taking every
## dependent script down with it — which is how the headless test suite broke.
## The class_name keeps constants resolvable in that mode; the lookup returns
## null and callers fall back to their exported defaults.

signal changed()

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "gameplay"

enum Difficulty { RECRUIT, SOLDIER, VETERAN }

## How a round is won, or whether it can be.
enum Mode {
	## Kills shorten the extraction clock. Reaching zero wins.
	EXTRACTION,
	## A fixed clock that kills do not affect. Outlast it to win.
	TIMED,
	## No clock and no win. Zombies keep coming until they finish you.
	ENDLESS,
}

const MODE_NAMES := {
	Mode.EXTRACTION: "Extraction",
	Mode.TIMED: "Last Stand",
	Mode.ENDLESS: "Endless",
}

const MODE_BLURBS := {
	Mode.EXTRACTION: "Every kill drags the rescue clock closer. Fight your way out.",
	Mode.TIMED: "A fixed five minutes. Kills buy you nothing but breathing room.",
	Mode.ENDLESS: "They never stop coming. Survive as long as you can.",
}

## Graphics presets. Measured with tools/benchmark.gd at 1920x1080 with 25
## zombies: SSAO costs ~2.3ms a frame and the arena's shadow ~1.4ms, together
## about a third of the frame budget. Both are worth offering as a choice
## rather than assuming every machine can pay for them.
enum Quality { LOW, MEDIUM, HIGH }

const QUALITY_NAMES := {
	Quality.LOW: "Performance",
	Quality.MEDIUM: "Balanced",
	Quality.HIGH: "Quality",
}

## Round length per mode, in seconds. Endless counts up and ignores this.
const MODE_DURATIONS := {
	Mode.EXTRACTION: 0.0,
	Mode.TIMED: 300.0,
	Mode.ENDLESS: 0.0,
}

const DIFFICULTY_NAMES := {
	Difficulty.RECRUIT: "Recruit",
	Difficulty.SOLDIER: "Soldier",
	Difficulty.VETERAN: "Veteran",
}

## Tuning applied per difficulty. spawn_interval_scale below 1.0 means zombies
## arrive faster; extraction_duration is the baseline round length in seconds.
const DIFFICULTY_PROFILES := {
	Difficulty.RECRUIT: {
		"spawn_interval_scale": 1.4,
		"damage_scale": 0.65,
		"extraction_duration": 100.0,
		"starting_reserve": 32,
	},
	Difficulty.SOLDIER: {
		"spawn_interval_scale": 1.0,
		"damage_scale": 1.0,
		"extraction_duration": 120.0,
		"starting_reserve": 24,
	},
	Difficulty.VETERAN: {
		"spawn_interval_scale": 0.68,
		"damage_scale": 1.4,
		"extraction_duration": 145.0,
		"starting_reserve": 16,
	},
}

var mouse_sensitivity := 0.0022
## Stick turn rate in radians per second at full deflection. Kept separate from
## the mouse figure because the two are not the same unit: one is radians per
## pixel moved, the other radians per second held.
var gamepad_sensitivity := 2.7
var invert_look_y := false
var master_volume := 0.8
var fullscreen := true
var difficulty: Difficulty = Difficulty.SOLDIER
var mode: Mode = Mode.EXTRACTION
var quality: Quality = Quality.HIGH


## The live autoload instance, or null when running without autoloads.
static func instance(from: Node) -> GameSettings:
	return from.get_node_or_null("/root/Settings") as GameSettings


func _ready() -> void:
	load_settings()
	apply_audio()
	apply_window()


func get_profile() -> Dictionary:
	return DIFFICULTY_PROFILES[difficulty]


func get_difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func get_quality_name() -> String:
	return QUALITY_NAMES[quality]


func get_mode_blurb() -> String:
	return MODE_BLURBS[mode]


func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return

	# Silence is a real choice, so mute the bus rather than feeding it -inf dB.
	if master_volume <= 0.001:
		AudioServer.set_bus_mute(bus, true)
	else:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume))


func apply_window() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)


## Push look preferences onto a player that just entered the scene.
func apply_to_player(player: Player) -> void:
	player.mouse_sensitivity = mouse_sensitivity
	player.gamepad_sensitivity = gamepad_sensitivity
	player.invert_look_y = invert_look_y


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION, "gamepad_sensitivity", gamepad_sensitivity)
	config.set_value(SECTION, "invert_look_y", invert_look_y)
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "difficulty", int(difficulty))
	config.set_value(SECTION, "mode", int(mode))
	config.set_value(SECTION, "quality", int(quality))
	config.save(CONFIG_PATH)

	changed.emit()


func load_settings() -> void:
	var config := ConfigFile.new()
	# Absent or corrupt config is normal on a first run — keep the defaults.
	if config.load(CONFIG_PATH) != OK:
		return

	mouse_sensitivity = config.get_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	gamepad_sensitivity = config.get_value(SECTION, "gamepad_sensitivity", gamepad_sensitivity)
	invert_look_y = config.get_value(SECTION, "invert_look_y", invert_look_y)
	master_volume = config.get_value(SECTION, "master_volume", master_volume)
	fullscreen = config.get_value(SECTION, "fullscreen", fullscreen)
	difficulty = config.get_value(SECTION, "difficulty", difficulty) as Difficulty
	mode = config.get_value(SECTION, "mode", mode) as Mode
	quality = config.get_value(SECTION, "quality", quality) as Quality
