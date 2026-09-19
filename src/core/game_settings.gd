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
var invert_look_y := false
var master_volume := 0.8
var fullscreen := false
var difficulty: Difficulty = Difficulty.SOLDIER


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
	player.invert_look_y = invert_look_y


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION, "invert_look_y", invert_look_y)
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "difficulty", int(difficulty))
	config.save(CONFIG_PATH)

	changed.emit()


func load_settings() -> void:
	var config := ConfigFile.new()
	# Absent or corrupt config is normal on a first run — keep the defaults.
	if config.load(CONFIG_PATH) != OK:
		return

	mouse_sensitivity = config.get_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	invert_look_y = config.get_value(SECTION, "invert_look_y", invert_look_y)
	master_volume = config.get_value(SECTION, "master_volume", master_volume)
	fullscreen = config.get_value(SECTION, "fullscreen", fullscreen)
	difficulty = config.get_value(SECTION, "difficulty", difficulty) as Difficulty
