class_name ZombieTypes
extends RefCounted

## The five things that can come at you, and when they start showing up.
##
## One enemy type makes a horde a texture rather than a threat: there is never
## a reason to shoot one thing before another. These exist to force target
## priority — a Runner has to be dealt with *now*, a Brute has to be dealt with
## *carefully*, a Screamer has to be dealt with *first*, and a Stalker has to
## be dealt with before you find out it is there.
##
## Stats are deliberately lopsided rather than sidegrades. A Runner that was
## merely "a bit faster" would read as the same enemy with a different skin.
##
## That principle applies twice over to the behaviour keys on each kind below.
## Numbers alone were never enough: five kinds that all walk the shortest path
## at you and bite when they arrive are one enemy with five health bars, no
## matter how far apart the health bars are. Every kind here owns at least one
## structural rule that none of the others has, and the player is meant to be
## able to name it after two encounters — "that one charges past you", "that
## one won't flinch", "that one comes from behind", "that one shouts".

enum Kind { SHAMBLER, RUNNER, BRUTE, STALKER, SCREAMER }

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
		## Nothing. The commonest kill in the game funds nothing, which is the only
		## way the average round-per-kill lands below what a kill costs to make —
		## measured at 1.2-1.3 rounds spent, and Shamblers are 40-70% of kills, so
		## no reward of 1 or more anywhere else can drag the mean under water.
		##
		## The horde does not fund you. The map does.
		"ammo": 0,
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
		# is what makes the kinds move recognisably differently at a glance
		# rather than only differing in a health bar.
		"acceleration": 6.0,
		"turn_speed": 5.5,
		"attack_windup": 0.4,
		"lunge_speed": 4.6,
		## How long the lunge itself lasts. Longer reads as more committed and
		## is easier to sidestep; shorter is a jab you have less time to read.
		"attack_commit": 0.25,
		## Seconds of flinch when shot, during which the zombie stops dead and
		## any wind-up in progress is cancelled. This is the whole reason
		## shooting a closing zombie is worth doing even when the shot will not
		## kill it: it buys the attack back. A kind with 0.0 cannot be
		## interrupted at all.
		"stagger_duration": 0.22,
		## Loudness beneath this kind's notice. 0.0 means it reacts to anything
		## it can hear at all.
		"noise_floor": 0.0,
		## Multiplier on how long it keeps hunting after losing sight.
		"sight_memory_scale": 1.0,
		## Seconds of uncontrolled run-on after a lunge ends. Non-zero means
		## the kind physically cannot stop at the end of a charge.
		"overrun_duration": 0.0,
		## Pull toward nearby zombies of the same kind, as a fraction of
		## move_speed. The only thing here that makes a crowd a crowd rather
		## than a set of individuals who happen to share a destination.
		"cohesion_strength": 0.28,
		## Metres behind the player this kind tries to approach from. 0.0 walks
		## straight at them.
		"flank_distance": 0.0,
		## Whether being looked at makes this kind withdraw and come back from
		## somewhere else.
		"breaks_off_when_watched": false,
		## Multiplier on the spawner's alert radius when this kind shouts.
		## 0.0 means it never tells anyone anything.
		"alarm_radius_scale": 1.0,
		## Seconds between deliberate alarms while hunting. 0.0 means this kind
		## only alerts others incidentally, when it happens to groan.
		"alarm_interval": 0.0,
		"alarm_windup": 0.0,
		## Whether hunting means running toward other zombies rather than at
		## the player.
		"flees_to_allies": false,
		## Multiplier on the awareness tell's brightness.
		"glow_scale": 1.0,
		"groan_interval": Vector2(3.5, 9.0),
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
		"ammo": 1,
		"hearing": 32.0,
		"unlock": 25.0,
		"weight": 6.0,
		# Twitchy: spins up to full speed and changes facing almost at once,
		# and its lunge is a quick jab rather than a committed charge.
		"acceleration": 18.0,
		"turn_speed": 12.0,
		"attack_windup": 0.16,
		"lunge_speed": 8.0,
		"attack_commit": 0.18,
		"stagger_duration": 0.30,
		"noise_floor": 0.0,
		# Its structural weakness, and the answer to it. A Runner that misses
		# sails on past at lunge speed and cannot steer, then has to wheel
		# round — and it forgets you faster than anything else in the cave, so
		# the window it hands you by overshooting is genuinely a window. It
		# catches you or it loses you; it is very bad at the middle.
		"sight_memory_scale": 0.45,
		"overrun_duration": 0.40,
		"cohesion_strength": 0.0,
		"flank_distance": 0.0,
		"breaks_off_when_watched": false,
		"alarm_radius_scale": 1.0,
		"alarm_interval": 0.0,
		"alarm_windup": 0.0,
		"flees_to_allies": false,
		"glow_scale": 1.0,
		"groan_interval": Vector2(2.5, 6.0),
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
		"ammo": 4,
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
		# Unshakeable, in three separate senses, and each one removes a tool
		# that works on everything else. Bullets do not interrupt its wind-up,
		# so the panic answer of shooting the thing that is about to hit you
		# does nothing and you have to move instead. A thrown decoy is beneath
		# its notice, so the trick that peels every other kind off does not
		# peel this one. And it remembers you nearly twice as long, so breaking
		# line of sight buys far less than it looks like it should.
		"attack_commit": 0.50,
		"stagger_duration": 0.0,
		"noise_floor": 0.9,
		"sight_memory_scale": 1.8,
		"overrun_duration": 0.0,
		"cohesion_strength": 0.0,
		"flank_distance": 0.0,
		"breaks_off_when_watched": false,
		"alarm_radius_scale": 1.0,
		"alarm_interval": 0.0,
		"alarm_windup": 0.0,
		"flees_to_allies": false,
		"glow_scale": 1.0,
		"groan_interval": Vector2(4.0, 8.0),
	},
	Kind.STALKER: {
		"name": "Stalker",
		# The only kind whose threat is not in its numbers. It dies to a
		# glancing hit and it is not especially fast; what it costs you is the
		# assumption that the room in front of you is the room you are in.
		"health": 18.0,
		"speed": 4.4,
		"damage": 16.0,
		"height": 1.95,
		# Near-black slate. It is meant to be genuinely hard to pick out
		# against unlit rock — that is the entire enemy.
		"tint": Color(0.34, 0.37, 0.44),
		"experience": 3,
		"ammo": 1,
		"hearing": 30.0,
		"unlock": 45.0,
		"weight": 4.0,
		"acceleration": 10.0,
		"turn_speed": 9.0,
		"attack_windup": 0.28,
		"lunge_speed": 7.0,
		"attack_commit": 0.22,
		"stagger_duration": 0.25,
		"noise_floor": 0.0,
		# Paths to a point behind you rather than to you, withdraws into the
		# dark the moment you look straight at it, and never shouts — so a
		# Stalker in the room is a room that sounds empty. The counterplay is
		# your own head: keep turning, and it can never finish an approach.
		"sight_memory_scale": 1.3,
		"overrun_duration": 0.0,
		"cohesion_strength": 0.0,
		"flank_distance": 5.5,
		"breaks_off_when_watched": true,
		"alarm_radius_scale": 0.0,
		"alarm_interval": 0.0,
		"alarm_windup": 0.0,
		"flees_to_allies": false,
		# Dimmer even than the baseline tell: the one enemy allowed to be hard
		# to see, because seeing it at all is most of the win against it.
		"glow_scale": 0.75,
		"groan_interval": Vector2(9.0, 16.0),
	},
	Kind.SCREAMER: {
		"name": "Screamer",
		# Harmless on its own and barely worth fighting. Its damage is a third
		# of a Shambler's and it is slower than one. Everything dangerous about
		# it happens to the rest of the cave, which is exactly why it has to be
		# the first thing you shoot and why that is a real decision: you spend
		# rounds on the enemy that cannot hurt you while the ones that can are
		# still walking in.
		"health": 34.0,
		"speed": 2.6,
		"damage": 4.0,
		"height": 1.7,
		"tint": Color(1.0, 0.92, 0.45),
		# Priced as the kill it is. Dropping one fast should feel rewarded
		# rather than like a magazine spent on a weakling.
		"experience": 4,
		"ammo": 2,
		"hearing": 34.0,
		"unlock": 35.0,
		"weight": 3.0,
		"acceleration": 8.0,
		"turn_speed": 7.0,
		"attack_windup": 0.5,
		"lunge_speed": 3.6,
		"attack_commit": 0.2,
		# Soft in the head as well as the body: it flinches longer than
		# anything else, so any hit at all buys a pause in the screaming even
		# when it does not kill.
		"stagger_duration": 0.40,
		"noise_floor": 0.0,
		"sight_memory_scale": 1.0,
		"overrun_duration": 0.0,
		"cohesion_strength": 0.0,
		"flank_distance": 0.0,
		"breaks_off_when_watched": false,
		# The payload. It shouts nearly three times as far as anything else and
		# does it on a timer rather than by luck, so one Screamer that sees you
		# empties a large part of the map in your direction.
		"alarm_radius_scale": 2.6,
		"alarm_interval": 1.6,
		## Notice, inhale, scream. The window in which killing it prevents the
		## pull rather than merely stopping the next one — see Zombie.alarm_windup
		## for how the 1.6s is costed.
		"alarm_windup": 1.6,
		# And it will not come to you. It runs to the nearest zombie it can
		# find and screams from behind it, so shooting it is a positioning
		# problem rather than only an aiming problem.
		"flees_to_allies": true,
		# Brightest tell in the game, on purpose. The whole design depends on
		# the player picking it out of a crowd instantly.
		"glow_scale": 2.4,
		"groan_interval": Vector2(2.0, 4.5),
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
