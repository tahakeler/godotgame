class_name WeaponTypes
extends RefCounted

## FEATURE 2b — The arsenal.
## Extends design/gdd/game-concept.md "Feature 2 — Ammunition and Reload" from
## one gun to three, each with its own reserve.
##
## One weapon makes ammunition a countdown. Three weapons with *separate*
## reserves make it a set of decisions: running the shotgun dry is not a pause
## to reload, it is a commitment to finish the fight on something else. That is
## only true because reserves do not pool — a shared pool would turn switching
## into a cosmetic choice about which barrel the same bullets leave from.
##
## The three are deliberately lopsided rather than sidegrades, the same way the
## zombie kinds are. A "slightly better pistol" is not a second weapon.
##
##   Pistol   — the floor. Accurate, cheap to fire, quiet, deep reserve. The
##              thing you always still have.
##   Shotgun  — the panic button. Eight pellets that delete anything inside
##              arm's reach and do nothing past it, four in the tube, and it is
##              the loudest noise in the cave. Firing it answers one problem by
##              inviting the next.
##   Rifle    — the answer to distance. Fast enough to matter, accurate cold,
##              and it climbs hard enough that holding the trigger is how you
##              miss. Sustained fire is the punishment, not the reward.
##
## The noise column is the reason this is a tactical system rather than a
## damage menu: zombies hunt by sound, so `noise_loudness` is what each weapon
## actually costs. The shotgun's 2.2 is not flavour — it is roughly two and a
## half times the pistol's hearing radius, which is a different room's worth of
## horde arriving.

enum Kind { PISTOL, SHOTGUN, RIFLE }

## The reserve the pistol carries at the normal difficulty's ammo budget.
##
## Difficulty sets a single `starting_reserve` figure on the weapon; every
## weapon's reserve is scaled against this so that picking Hard thins the whole
## arsenal proportionally instead of only the gun that happens to be in hand.
const BASELINE_RESERVE := 36

const DEFINITIONS := {
	Kind.PISTOL: {
		"name": "PISTOL",
		"model": "res://assets/models/weapons/blaster-a.glb",
		## Gunmetal with a faint warm cast. The kit ships this one lilac.
		"tint": Color(0.86, 0.84, 0.90),
		# Two pistol rounds kill a Shambler (50 hp), one kills a Runner (26).
		# That is the floor the rest of the arsenal is measured against.
		"damage": 26.0,
		"pellets": 1,
		## Cone half-angle in degrees applied to every pellet. Under a degree
		## reads as "where you pointed" — the pistol is never the reason a shot
		## missed, which is what makes it the fallback rather than a penalty.
		"spread_degrees": 0.6,
		"fire_cooldown": 0.28,
		"magazine_size": 10,
		"reserve": 36,
		"max_reserve": 72,
		"reload_duration": 1.5,
		"shot_range": 80.0,
		## Multiplier on every zombie's hearing range. Under one on purpose:
		## the pistol is the weapon you can use without answering for it.
		"noise_loudness": 0.85,
		"recoil_pitch_degrees": 1.2,
		## Extra recoil added per consecutive shot, as a fraction of the base
		## kick. Zero means the tenth shot sits where the first did.
		"recoil_climb": 0.0,
		"recoil_climb_max": 0.0,
		## Camera shake per shot. 0.2 is the established "a gun went off"
		## figure; the pistol sits just under it.
		"fire_trauma": 0.18,
		## Seconds to bring this weapon up. Switching has to cost something or
		## running a weapon dry is free.
		"swap_duration": 0.55,
	},
	Kind.SHOTGUN: {
		"name": "SHOTGUN",
		"model": "res://assets/models/weapons/blaster-k.glb",
		## Darker and browner — the heavy, older-looking one of the three.
		"tint": Color(0.82, 0.70, 0.56),
		# 13 x 8 = 104 on a point-blank hit: a Shambler and most of a second
		# one. Past the range cut-off it is 0, because the trace stops short.
		"damage": 13.0,
		"pellets": 8,
		## Wide enough that at ten metres most of the cone is cave wall. The
		## spread is the range limit you can *see*; shot_range is the one that
		## makes it absolute.
		"spread_degrees": 7.5,
		"fire_cooldown": 0.85,
		# Four shells and a slow reload is the whole character: you get four
		# answers, then you are holding a club for two and a half seconds.
		"magazine_size": 4,
		"reserve": 16,
		"max_reserve": 32,
		"reload_duration": 2.6,
		## Fourteen metres. Deliberately shorter than most sightlines in the
		## cave so that "useless at range" is a rule rather than a tendency.
		"shot_range": 14.0,
		## The loudest thing on the map, by a distance. Every shell is a
		## decision to trade the room you are in for the room next door.
		"noise_loudness": 2.2,
		"recoil_pitch_degrees": 4.5,
		"recoil_climb": 0.0,
		"recoil_climb_max": 0.0,
		# Well past the 0.2 gunshot mark and closing on the 0.6 of being hit.
		"fire_trauma": 0.45,
		# Slowest to bring up. A heavy gun should feel like a commitment before
		# it feels like a solution.
		"swap_duration": 0.85,
	},
	Kind.RIFLE: {
		"name": "RIFLE",
		"model": "res://assets/models/weapons/blaster-q.glb",
		## Cool steel, so the three read apart at a glance in a dark corridor.
		"tint": Color(0.72, 0.80, 0.92),
		# Lowest per-shot damage of the three, highest damage per second — but
		# only for the first few rounds, before the climb takes the accuracy.
		"damage": 17.0,
		"pellets": 1,
		"spread_degrees": 0.35,
		"fire_cooldown": 0.09,
		"magazine_size": 20,
		"reserve": 60,
		"max_reserve": 120,
		"reload_duration": 2.1,
		# Reaches further than anything else, which is the only thing it has
		# that the pistol does not.
		"shot_range": 110.0,
		# Between the two: loud enough that a long burst is a broadcast, quiet
		# enough that a two-round tap is not.
		"noise_loudness": 1.35,
		# Small kick per shot, but it stacks. By the eighth round of a held
		# burst the muzzle is 2.4x higher and the cone has opened with it, so
		# the gun that is best at range is worst at range if you abuse it.
		"recoil_pitch_degrees": 0.9,
		"recoil_climb": 0.2,
		"recoil_climb_max": 2.4,
		"fire_trauma": 0.14,
		"swap_duration": 0.7,
	},
}


## The stats for one weapon. Returns an empty dictionary for an unknown kind
## rather than failing, so a bad slot cannot take the round down with it.
static func definition(kind: Kind) -> Dictionary:
	return DEFINITIONS.get(kind, {})


## Every kind, in the order the number keys and the wheel walk through them.
##
## Built from the enum rather than written out, so a fourth weapon is one
## dictionary entry and not four places to remember.
static func order() -> Array:
	var kinds: Array = []
	for kind in DEFINITIONS:
		kinds.append(kind)
	return kinds


## The human-readable name, for the HUD.
static func display_name(kind: Kind) -> String:
	return definition(kind).get("name", "—")
