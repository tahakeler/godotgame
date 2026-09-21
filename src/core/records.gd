class_name Records
extends RefCounted

## Personal bests, stored per mode and difficulty.
##
## Endless in particular is pointless without one: a mode with no win condition
## and no recorded best gives the player nothing to compare a run against, so
## there is no reason to start a second one.
##
## What counts as "better" differs by mode, which is why each has its own
## comparison rather than a shared score. Extraction rewards leaving fast,
## Last Stand rewards killing within a fixed window, Endless rewards lasting.
##
## Plain static functions rather than an autoload, so this is reachable from
## headless `--script` runs where autoloads do not exist.

const PATH := "user://records.cfg"
const SECTION := "records"


## The best run recorded for this mode and difficulty, or an empty result.
static func best(mode: GameSettings.Mode, difficulty: GameSettings.Difficulty) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return _empty()

	# The default must be a real value: passing null reads as "no default" and
	# Godot reports a missing key as an error rather than returning it.
	var stored: Dictionary = config.get_value(SECTION, _key(mode, difficulty), {})
	return stored if stored.has("kills") else _empty()


## Record a finished run. Returns true when it beat the previous best.
static func submit(
	mode: GameSettings.Mode,
	difficulty: GameSettings.Difficulty,
	kills: int,
	duration: float,
	won: bool
) -> bool:
	var previous := best(mode, difficulty)
	var candidate := {
		"kills": kills,
		"duration": duration,
		"won": won,
	}

	if previous.has("kills") and not _is_better(mode, candidate, previous):
		return false

	var config := ConfigFile.new()
	# Losing the file is not worth failing a run over; it is rebuilt from the
	# next record either way.
	config.load(PATH)
	config.set_value(SECTION, _key(mode, difficulty), candidate)
	config.save(PATH)

	return true


## A human-readable summary of a best, for the menus.
static func describe(mode: GameSettings.Mode, record: Dictionary) -> String:
	if not record.has("kills"):
		return "No record yet"

	var duration := _format(record.duration)

	match mode:
		GameSettings.Mode.EXTRACTION:
			if not record.won:
				return "%d kills" % record.kills
			return "Extracted in %s  ·  %d kills" % [duration, record.kills]
		GameSettings.Mode.TIMED:
			return "%d kills" % record.kills
		GameSettings.Mode.RELAY:
			if not record.won:
				return "%d kills" % record.kills
			return "Signal complete in %s  �  %d kills" % [duration, record.kills]
		_:
			return "Survived %s  ·  %d kills" % [duration, record.kills]


## Extraction is a race, so a completed run always beats an incomplete one and
## faster beats slower. The other two are endurance, so more is better.
static func _is_better(
	mode: GameSettings.Mode, candidate: Dictionary, previous: Dictionary
) -> bool:
	match mode:
		GameSettings.Mode.EXTRACTION:
			if candidate.won != previous.won:
				return candidate.won
			if candidate.won:
				return candidate.duration < previous.duration
			return candidate.kills > previous.kills
		GameSettings.Mode.TIMED:
			return candidate.kills > previous.kills
		GameSettings.Mode.RELAY:
			# A relay run is a race, not an endurance test. The fallback below
			# rewards the longer duration, which for this mode would record the
			# slowest completion as the best one.
			if candidate.won != previous.won:
				return candidate.won
			if candidate.won:
				return candidate.duration < previous.duration
			return candidate.kills > previous.kills
		_:
			return candidate.duration > previous.duration


static func _key(mode: GameSettings.Mode, difficulty: GameSettings.Difficulty) -> String:
	return "%d_%d" % [int(mode), int(difficulty)]


static func _empty() -> Dictionary:
	return {}


static func _format(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
