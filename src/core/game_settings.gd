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
	## Arm three signal relays at the deep ends of the cave, then run home.
	##
	## Appended rather than inserted on purpose: load_settings() reads the mode
	## back as a raw int from user://settings.cfg, so inserting an entry would
	## silently reassign the saved preference on every existing install.
	RELAY,
}

const MODE_NAMES := {
	Mode.EXTRACTION: "Extraction",
	Mode.TIMED: "Last Stand",
	Mode.ENDLESS: "Endless",
	Mode.RELAY: "Signal",
}

const MODE_BLURBS := {
	Mode.EXTRACTION: "Every kill drags the rescue clock closer. Fight your way out.",
	Mode.TIMED: "A fixed five minutes. Kills buy you nothing but breathing room.",
	Mode.ENDLESS: "They never stop coming. Survive as long as you can.",
	Mode.RELAY: "Three relays at the deep ends. Arming one is the loudest thing you can do.",
}

## Graphics presets. Measured with tools/benchmark.gd at 1920x1080 with 25
## zombies: SSAO costs ~2.3ms a frame and the arena's shadow ~1.4ms, together
## about a third of the frame budget. Both are worth offering as a choice
## rather than assuming every machine can pay for them.
enum Quality { LOW, MEDIUM, HIGH }

## Colour vision modes.
##
## The default palette leans on green-for-healthy and red-for-hurt, which is
## the single most common way a game becomes unreadable: red-green deficiency
## is the most prevalent form, and those two are exactly the pair it collapses.
## Each alternative keeps the same brightness ordering and swaps the hues for a
## pair that stays distinct — plus the HUD never relies on colour alone, since
## the bar length and the number carry the same information.
enum ColourMode { STANDARD, DEUTERANOPIA, PROTANOPIA, TRITANOPIA }

const COLOUR_MODE_NAMES := {
	ColourMode.STANDARD: "Standard",
	ColourMode.DEUTERANOPIA: "Deuteranopia",
	ColourMode.PROTANOPIA: "Protanopia",
	ColourMode.TRITANOPIA: "Tritanopia",
}

## "safe" is a healthy reading, "danger" is a critical one, "accent" carries
## progression. Blue/amber survives red-green deficiency; tritanopia loses
## blue/yellow instead, so it gets magenta and cyan.
const COLOUR_PALETTES := {
	ColourMode.STANDARD: {
		"safe": Color(0.42, 0.72, 0.45),
		"danger": Color(0.85, 0.24, 0.2),
		"accent": Color(0.878, 0.631, 0.235),
	},
	ColourMode.DEUTERANOPIA: {
		"safe": Color(0.35, 0.62, 0.92),
		"danger": Color(0.95, 0.72, 0.15),
		"accent": Color(0.92, 0.92, 0.95),
	},
	ColourMode.PROTANOPIA: {
		"safe": Color(0.3, 0.68, 0.9),
		"danger": Color(0.97, 0.78, 0.25),
		"accent": Color(0.88, 0.88, 0.94),
	},
	ColourMode.TRITANOPIA: {
		"safe": Color(0.25, 0.78, 0.76),
		"danger": Color(0.9, 0.26, 0.55),
		"accent": Color(0.95, 0.9, 0.92),
	},
}

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
	# No clock. elapsed_time counts up and is the score.
	Mode.RELAY: 0.0,
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
var invert_look_y := false
var master_volume := 0.8
## Music and effects ride separate buses under Master, created at runtime by
## ensure_buses(). Split because the ambience bed is the thing players most
## often want quieter without also going deaf to the footsteps behind them.
var music_volume := 0.8
var sfx_volume := 0.9
var fullscreen := true
## Windowed size, used only when `fullscreen` is off. Stored rather than derived
## so a player who picked a small window keeps it across restarts.
var window_size := Vector2i(1600, 900)
## Vertical field of view in degrees for the first-person camera. Wide FOV is a
## motion-sickness remedy as much as a preference, which is why it is offered
## rather than fixed.
var field_of_view := 78.0
var difficulty: Difficulty = Difficulty.SOLDIER
var mode: Mode = Mode.EXTRACTION
var quality: Quality = Quality.HIGH

var colour_mode: ColourMode = ColourMode.STANDARD
## Interface scale as a fraction. Drives the window's content scale, so every
## Control scales together rather than each screen needing its own handling.
var interface_scale := 1.0
## Camera shake as a fraction of its authored strength. Zero disables it
## entirely, which some players need and everyone else can ignore.
var shake_scale := 1.0
## Damps full-screen flashes for players who find them uncomfortable, and for
## anyone who should not be shown rapid flashing at all.
var reduce_flashing := false


## The colour set for the current mode.
func palette() -> Dictionary:
	return COLOUR_PALETTES[colour_mode]


## Look up one palette colour, with a fallback for callers running without the
## autoload (headless tests instance scenes directly).
static func colour(from: Node, key: String, fallback: Color) -> Color:
	var settings := instance(from)
	if settings == null:
		return fallback
	return settings.palette().get(key, fallback)


func get_colour_mode_name() -> String:
	return COLOUR_MODE_NAMES[colour_mode]


## Content scale applies to the whole window, so it has to be set on the window
## rather than on any one screen.
func apply_interface_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return

	tree.root.content_scale_factor = interface_scale


## The live autoload instance, or null when running without autoloads.
static func instance(from: Node) -> GameSettings:
	return from.get_node_or_null("/root/Settings") as GameSettings


func _ready() -> void:
	ensure_buses()
	load_settings()
	apply_audio()
	apply_window()
	apply_interface_scale()


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


## Names of the two buses created under Master. Playback code addresses them by
## name, so the mixer layout lives here rather than in a .tres nobody reads.
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"


## Create the Music and SFX buses if the project has no bus layout defining
## them. Built at runtime rather than shipped as a default_bus_layout.tres so
## that headless tools, which boot without the project's audio configuration,
## still find the buses the sliders claim to control.
static func ensure_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue

		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func apply_audio() -> void:
	ensure_buses()
	_apply_bus_volume("Master", master_volume)
	_apply_bus_volume(MUSIC_BUS, music_volume)
	_apply_bus_volume(SFX_BUS, sfx_volume)


## Silence is a real choice, so mute the bus rather than feeding it -inf dB:
## the conversion produces a number the mixer handles badly.
func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return

	if linear <= 0.001:
		AudioServer.set_bus_mute(bus, true)
		return

	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_volume_db(bus, linear_to_db(linear))




func apply_window() -> void:
	# Exclusive rather than plain fullscreen. On macOS the plain mode puts the
	# window in its own Space, where the cursor capture a first-person camera
	# depends on is unreliable — a trackpad could not turn the view at all.
	# Exclusive fullscreen keeps the window on the current Space and keeps
	# capture and focus behaving like every other platform.
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)

	if fullscreen:
		return

	# Resizing a fullscreen window does nothing visible and fights the mode on
	# the way back out, so the size is only ever pushed while windowed.
	DisplayServer.window_set_size(window_size)


## Push look preferences onto a player that just entered the scene.
func apply_to_player(player: Player) -> void:
	player.mouse_sensitivity = mouse_sensitivity
	player.shake_scale = shake_scale
	player.invert_look_y = invert_look_y
	player.set_base_fov(field_of_view)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION, "invert_look_y", invert_look_y)
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "music_volume", music_volume)
	config.set_value(SECTION, "sfx_volume", sfx_volume)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "window_size", window_size)
	config.set_value(SECTION, "field_of_view", field_of_view)
	config.set_value(SECTION, "difficulty", int(difficulty))
	config.set_value(SECTION, "mode", int(mode))
	config.set_value(SECTION, "quality", int(quality))
	config.set_value(SECTION, "colour_mode", int(colour_mode))
	config.set_value(SECTION, "interface_scale", interface_scale)
	config.set_value(SECTION, "shake_scale", shake_scale)
	config.set_value(SECTION, "reduce_flashing", reduce_flashing)
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
	music_volume = config.get_value(SECTION, "music_volume", music_volume)
	sfx_volume = config.get_value(SECTION, "sfx_volume", sfx_volume)
	fullscreen = config.get_value(SECTION, "fullscreen", fullscreen)
	window_size = config.get_value(SECTION, "window_size", window_size)
	field_of_view = config.get_value(SECTION, "field_of_view", field_of_view)
	difficulty = config.get_value(SECTION, "difficulty", difficulty) as Difficulty
	mode = config.get_value(SECTION, "mode", mode) as Mode
	quality = config.get_value(SECTION, "quality", quality) as Quality
	colour_mode = config.get_value(SECTION, "colour_mode", colour_mode) as ColourMode
	interface_scale = config.get_value(SECTION, "interface_scale", interface_scale)
	shake_scale = config.get_value(SECTION, "shake_scale", shake_scale)
	reduce_flashing = config.get_value(SECTION, "reduce_flashing", reduce_flashing)
