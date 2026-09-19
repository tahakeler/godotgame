class_name Progression
extends Node

## Kills earn experience; experience earns levels; levels offer an upgrade.
##
## This exists to give a run a shape. Without it every minute of a round plays
## the same as the last, and the only thing that changes is how many zombies
## are on screen. With it the player is steadily answering a question — what do
## I need next — which is what makes a long run worth staying in.
##
## Progression holds no references to the player or the weapon. It decides what
## was offered and chosen; Game applies the effect.

signal experience_changed(current: int, needed: int, level: int)
signal levelled_up(level: int, choices: Array[Dictionary])

## Upgrade identifiers, kept as an enum so Game's apply step is exhaustive
## rather than string-matched.
enum Upgrade {
	MAGAZINE,
	VITALITY,
	HOLLOW_POINTS,
	FAST_HANDS,
	ADRENALINE,
	SCAVENGER,
	BANDOLIER,
}

const UPGRADES := {
	Upgrade.MAGAZINE: {
		"name": "Extended Magazine",
		"detail": "+3 rounds per magazine",
	},
	Upgrade.VITALITY: {
		"name": "Field Dressing",
		"detail": "+25 max health, and heal that much now",
	},
	Upgrade.HOLLOW_POINTS: {
		"name": "Hollow Points",
		"detail": "+8 damage per shot",
	},
	Upgrade.FAST_HANDS: {
		"name": "Fast Hands",
		"detail": "Reload 20% faster",
	},
	Upgrade.ADRENALINE: {
		"name": "Adrenaline",
		"detail": "+12% movement speed",
	},
	Upgrade.SCAVENGER: {
		"name": "Scavenger",
		"detail": "+2 reserve rounds per kill",
	},
	Upgrade.BANDOLIER: {
		"name": "Bandolier",
		"detail": "+15 reserve capacity, and fill it now",
	},
}

@export var experience_per_kill := 1
## Kills needed for the first level. Deliberately small — the first upgrade
## should arrive while the player is still learning the weapon.
@export var base_requirement := 4
## Added to the requirement each level, so the curve stretches without
## ever becoming a wall.
@export var requirement_growth := 3
@export var choices_per_level := 3

var level := 1
var experience := 0
var requirement := 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	reset()


## Award experience for a kill. The amount travels with the kind that died,
## so a Brute moves the bar further than a Shambler.
func add_kill_experience(amount: int = experience_per_kill) -> void:
	experience += maxi(amount, 1)

	if experience < requirement:
		experience_changed.emit(experience, requirement, level)
		return

	experience -= requirement
	level += 1
	requirement = _requirement_for(level)

	experience_changed.emit(experience, requirement, level)
	levelled_up.emit(level, roll_choices())


## Pick distinct upgrades to offer. Offering the same one twice wastes a slot
## and reads as a bug.
func roll_choices() -> Array[Dictionary]:
	var pool: Array[int] = []
	for id in UPGRADES:
		pool.append(id)

	var chosen: Array[Dictionary] = []
	var wanted := mini(choices_per_level, pool.size())

	for i in wanted:
		var index := _rng.randi_range(0, pool.size() - 1)
		var id: int = pool[index]
		pool.remove_at(index)

		chosen.append({
			"id": id,
			"name": UPGRADES[id].name,
			"detail": UPGRADES[id].detail,
		})

	return chosen


func reset() -> void:
	level = 1
	experience = 0
	requirement = _requirement_for(level)
	experience_changed.emit(experience, requirement, level)


func _requirement_for(for_level: int) -> int:
	return base_requirement + (for_level - 1) * requirement_growth
