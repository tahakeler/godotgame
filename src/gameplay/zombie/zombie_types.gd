class_name ZombieTypes
extends RefCounted

## The three things that can come at you, and when they start showing up.
##
## One enemy type makes a horde a texture rather than a threat: there is never
## a reason to shoot one thing before another. These exist to force target
## priority — a Runner has to be dealt with *now*, a Brute has to be dealt with
## *carefully*, and ignoring either is a different kind of mistake.
##
## Stats are deliberately lopsided rather than sidegrades. A Runner that was
## merely "a bit faster" would read as the same enemy with a different skin.

enum Kind { SHAMBLER, RUNNER, BRUTE }

const DEFINITIONS := {
	Kind.SHAMBLER: {
		"name": "Shambler",
		"health": 50.0,
		"speed": 3.2,
		"damage": 12.0,
		## Rendered height in metres, measured from the floor. This is a real
		## world measurement rather than a multiplier because it drives two
		## things that must agree — the model and the collision capsule. They
		## were previously set from separate numbers and drifted a factor of
		## two apart, which put the hitbox around a zombie's legs while the
		## player was aiming at its chest.
		##
		## Two metres is deliberately a head taller than the 1.8m player.
		"height": 2.0,
		"tint": Color(1.0, 1.0, 1.0),
		"experience": 1,
		"ammo": 3,
		## How far this kind hears a gunshot, in metres. A Brute hears furthest,
		## so the thing you least want to attract is the thing a shot is most
		## likely to bring — which is what makes firing a decision rather than
		## a reflex.
		"hearing": 26.0,
		## Seconds into the round before this kind can appear.
		"unlock": 0.0,
		## Relative spawn frequency once unlocked.
		"weight": 10.0,
		# Baseline weight: not twitchy, not sluggish. Runner and Brute are
		# deliberately lopsided away from this in opposite directions, which
		# is what makes the three kinds move recognisably differently at a
		# glance rather than only differing in a health bar.
		"acceleration": 6.0,
		"turn_speed": 5.5,
		"attack_windup": 0.4,
		"lunge_speed": 4.6,
	},
	Kind.RUNNER: {
		"name": "Runner",
		# Dies to a single upgraded shot, but closes the distance fast enough
		# that ignoring one is how a comfortable round stops being comfortable.
		"health": 26.0,
		"speed": 5.8,
		"damage": 8.0,
		"height": 1.85,
		"tint": Color(0.78, 1.0, 0.82),
		"experience": 2,
		"ammo": 3,
		"hearing": 32.0,
		"unlock": 25.0,
		"weight": 6.0,
		# Twitchy: spins up to full speed and changes facing almost at once,
		# and its lunge is a quick jab rather than a committed charge.
		"acceleration": 18.0,
		"turn_speed": 12.0,
		"attack_windup": 0.16,
		"lunge_speed": 8.0,
	},
	Kind.BRUTE: {
		"name": "Brute",
		# Three magazines of baseline damage. The point is that you cannot
		# afford to kill it with the gun alone — you have to use the space.
		"health": 165.0,
		"speed": 2.0,
		"damage": 28.0,
		"height": 2.6,
		"tint": Color(0.95, 0.62, 0.58),
		"experience": 5,
		"ammo": 8,
		"hearing": 42.0,
		"unlock": 70.0,
		"weight": 2.5,
		# Heavy: slow to get moving and slow to turn away from, which is what
		# makes circling one actually work as a tactic. Its telegraph is long
		# enough to see coming, but the lunge itself closes ground fast, so
		# standing at the edge of its reach while it winds up is not safe.
		"acceleration": 3.2,
		"turn_speed": 2.0,
		"attack_windup": 0.65,
		"lunge_speed": 6.5,
	},
}


## Pick a kind for a spawn this far into the round.
##
## Weights are fixed rather than drifting toward the rarer kinds over time: the
## escalation already comes from spawn rate and population, and stacking a
## third curve on top makes late rounds spike unpredictably.
static func pick(elapsed: float, rng: RandomNumberGenerator) -> Kind:
	var available: Array[Kind] = []
	var total := 0.0

	for kind in DEFINITIONS:
		if elapsed >= DEFINITIONS[kind].unlock:
			available.append(kind)
			total += DEFINITIONS[kind].weight

	if available.is_empty():
		return Kind.SHAMBLER

	var roll := rng.randf() * total

	for kind in available:
		roll -= DEFINITIONS[kind].weight
		if roll <= 0.0:
			return kind

	return available[available.size() - 1]


static func definition(kind: Kind) -> Dictionary:
	return DEFINITIONS[kind]
