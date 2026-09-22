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

## Lifetime tallies, one accumulated row per mode and difficulty, plus a
## career-wide section that is not split by mode or difficulty at all. Kept
## as a second ConfigFile section rather than a second file so a corrupt or
## missing save wipes both at once instead of leaving them out of sync.
const TOTALS_SECTION := "totals"
const CAREER_SECTION := "career"
const CAREER_KEY := "career"


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


## Accumulate one finished run into the lifetime totals for this mode and
## difficulty. Independent of `submit()` above: a run always adds to the
## totals even when it does not beat the recorded best.
static func tally_run(
	mode: GameSettings.Mode,
	difficulty: GameSettings.Difficulty,
	kills: int,
	shots_fired: int,
	shots_hit: int,
	duration: float,
	won: bool
) -> void:
	var row := totals(mode, difficulty)
	row.runs_started += 1
	row.runs_won += 1 if won else 0
	row.runs_lost += 0 if won else 1
	row.kills += kills
	row.shots_fired += shots_fired
	row.shots_hit += shots_hit
	row.duration += duration

	var config := ConfigFile.new()
	# As with submit(), a missing or unreadable file is rebuilt rather than
	# failed over; the run that just finished is not worth losing.
	config.load(PATH)
	config.set_value(TOTALS_SECTION, _key(mode, difficulty), row)
	config.save(PATH)


## The accumulated lifetime row for this mode and difficulty, or all zeros
## when nothing has been tallied yet.
static func totals(mode: GameSettings.Mode, difficulty: GameSettings.Difficulty) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return _empty_totals()

	# As with best() above: the default passed to get_value() must be a real
	# dictionary, not null, or a missing key reads back as an error instead
	# of quietly returning the default.
	var stored: Dictionary = config.get_value(TOTALS_SECTION, _key(mode, difficulty), {})
	return stored if stored.has("runs_started") else _empty_totals()


## Every mode and difficulty summed into one row, plus the career-wide
## deaths-by-kind map. This is what the STATS tab shows; nothing here is
## split by mode or difficulty.
static func career() -> Dictionary:
	var summed := _empty_totals()

	var config := ConfigFile.new()
	# Guarded on the section as well as the load. Every save written before
	# totals existed has a "records" section and no "totals" one, and
	# get_section_keys reports a missing section as an engine error rather
	# than returning nothing — which the verification gate treats as a failed
	# step, on what is simply a player who has played this game before.
	if config.load(PATH) == OK and config.has_section(TOTALS_SECTION):
		for row_key: String in config.get_section_keys(TOTALS_SECTION):
			var row: Dictionary = config.get_value(TOTALS_SECTION, row_key, {})
			if not row.has("runs_started"):
				continue
			summed.runs_started += row.runs_started
			summed.runs_won += row.runs_won
			summed.runs_lost += row.runs_lost
			summed.kills += row.kills
			summed.shots_fired += row.shots_fired
			summed.shots_hit += row.shots_hit
			summed.duration += row.duration

	summed["deaths_by_kind"] = _deaths_by_kind()
	return summed


## Record one death credited to this zombie kind. Career-wide, not split by
## mode or difficulty, so the menu can answer "what usually kills me?" across
## every run rather than per mode.
static func tally_death(kind: ZombieTypes.Kind) -> void:
	var deaths := _deaths_by_kind()
	deaths[int(kind)] = deaths.get(int(kind), 0) + 1

	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(CAREER_SECTION, CAREER_KEY, deaths)
	config.save(PATH)


## Wipes the lifetime tallies only. The best-run section is untouched, so
## resetting the STATS tab never costs the player a personal best.
static func reset_totals() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	# erase_section() raises an error for a section that is not there, so a
	# fresh save with nothing tallied yet must not call it unconditionally.
	if config.has_section(TOTALS_SECTION):
		config.erase_section(TOTALS_SECTION)
	if config.has_section(CAREER_SECTION):
		config.erase_section(CAREER_SECTION)
	config.save(PATH)


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
			return "Signal complete in %s  ·  %d kills" % [duration, record.kills]
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


static func _empty_totals() -> Dictionary:
	return {
		"runs_started": 0,
		"runs_won": 0,
		"runs_lost": 0,
		"kills": 0,
		"shots_fired": 0,
		"shots_hit": 0,
		"duration": 0.0,
	}


## The career-wide deaths-by-kind map, keyed by `int(ZombieTypes.Kind)`, or
## empty when nothing has been tallied yet.
static func _deaths_by_kind() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return {}
	# Same null-default trap as best() and totals(): {} must be passed
	# explicitly so an absent key returns it instead of raising an error.
	return config.get_value(CAREER_SECTION, CAREER_KEY, {})


static func _format(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
