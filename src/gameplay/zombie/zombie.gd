class_name Zombie
extends CharacterBody3D

## Pursues the player across the baked navmesh and attacks on contact.
##
## Zombies collide with world geometry only, never with each other or the
## player. Letting bodies push each other turns a crowd into a physics pile-up
## and lets zombies shove the player through the arena, which reads as a bug
## rather than a threat.

signal died(zombie: Zombie, death_position: Vector3)
signal hit_player(damage: float, from_position: Vector3)
signal groaned(groan_position: Vector3)
## Raised by a zombie that is actively hunting, carrying what it believes. The
## spawner passes it to anything close enough to hear, which is what turns one
## noticed gunshot into a chamber emptying toward you.
signal raised_alarm(zombie: Zombie, believed_position: Vector3)
## The instant this zombie starts hunting. The most important event in a round,
## and it used to happen silently.
signal noticed_player(at: Vector3, kind: ZombieTypes.Kind)
## The instant a zombie commits to a lunge, before it can possibly land. A
## straight cooldown-gated hit at range had nothing to hang a tell off; this is
## the hook a telegraph animation or sound cue would attach to.
signal attack_telegraphed(zombie: Zombie, at: Vector3)
## A Screamer has noticed the player and drawn breath. Fires alarm_windup
## seconds before the alarm itself, and is the only warning the player gets
## that the room is about to fill up. The hook a dedicated inhale sound
## attaches to.
signal alarm_winding_up(zombie: Zombie, at: Vector3)

## What a zombie knows about the player right now.
enum Awareness {
	## No idea. Wandering.
	UNAWARE,
	## Believes the player is somewhere, from a sound, an alert, or from having
	## lost sight of them. The belief is frequently wrong by the time it gets
	## there, which is the point.
	INVESTIGATING,
	## Can see the player. Tracks them live.
	HUNTING,
	## Arrived at the believed position, found nothing, and is now working the
	## area around it.
	##
	## This used to live inside INVESTIGATING as a countdown, and the result
	## was a zombie that walked to a spot and then stood on it vibrating for
	## four seconds. Searching that does not move does not look like searching;
	## it looks like a state machine waiting for a timer. Splitting it out gives
	## it its own goals, its own tell, and its own exit.
	SEARCHING,
	## Deliberately withdrawing. Only kinds that break off when watched ever
	## enter this — for everything else it is unreachable, and that is fine:
	## a state no zombie can enter costs nothing, and a Stalker's whole
	## character is that it has one.
	RETREATING,
}

@export_group("Movement")
@export var move_speed := 3.2
@export var turn_speed := 9.0
## Metres per second squared the horizontal velocity is allowed to change by.
## Velocity used to be assigned outright every physics frame, which made every
## zombie feel like a cursor sliding along the path rather than a body with
## momentum. Set per kind by configure() — a Brute's low value is what makes it
## feel heavy to get moving and slow to turn away from once committed.
@export var acceleration := 7.0
## How often the navigation target is refreshed. Every frame is wasteful and
## produces no visible improvement at this speed.
@export var repath_interval := 0.15
## Steepest surface a zombie will walk up rather than treat as a wall.
@export var floor_climb_angle_degrees := 80.0

@export_group("Individuality")
## Fractional per-zombie jitter applied to move_speed, so two Shamblers spawned
## a second apart are not visibly running in lockstep. Drawn once from this
## zombie's own RNG (see _rng below), not the shared global one.
@export_range(0.0, 0.4) var speed_variation := 0.12
## Same idea, applied to turn_speed.
@export_range(0.0, 0.4) var turn_variation := 0.18
## Chance, rolled once per repath tick while not actively hunting, that this
## zombie pauses instead of immediately continuing. A crowd that never
## hesitates reads as one mind operating several bodies; this puts a little
## uncertainty back into individuals without touching the belief system that
## actually drives where they are trying to go.
@export_range(0.0, 0.5) var hesitation_chance := 0.08
@export var hesitation_duration := Vector2(0.15, 0.4)

@export_group("Separation")
## Extra gap beyond the two capsules' own radii at which zombies start
## pushing apart. Small on purpose — this stops bodies overlapping in a
## crowd, it is not a formation-keeping force, and a generous radius would
## read as an invisible fence around every zombie.
@export var separation_margin := 0.6
## Push strength as a fraction of move_speed. Kept below 1 so separation can
## nudge a zombie sideways but can never be the reason it fails to close on
## the player.
@export_range(0.0, 1.0) var separation_strength := 0.5

@export_group("Combat")
@export var contact_damage := 12.0
@export var attack_range := 1.9
@export var attack_cooldown := 1.1
## Seconds a zombie holds still (but keeps turning to face the target) before
## a lunge fires. Long enough to read and step out of, short enough that
## standing still is not a safe answer to it. Set per kind by configure().
@export var attack_windup := 0.35
## How long the lunge itself lasts once it fires. The zombie is committed to
## the direction it was facing when the windup ended for this whole window —
## it cannot re-aim mid-lunge, which is what makes stepping aside work.
@export var attack_commit_duration := 0.25
## Forward speed during the lunge itself, independent of move_speed. Set per
## kind by configure() — a Brute is slow to start but closes fast once it
## commits, which punishes standing at the edge of its reach.
@export var lunge_speed := 5.5

@export_group("Hearing")
## How far this zombie can hear a noise of loudness 1.0, measured along the
## navmesh rather than through rock.
##
## Set per kind by configure(): a Brute hears furthest, which means the thing
## you least want to attract is the thing a shot is most likely to bring.
@export var hearing_range := 26.0
## How long it keeps walking toward a belief before giving up on it.
@export var investigate_duration := 9.0
## How long it casts about after arriving and finding nothing.
@export var search_duration := 4.0
## How far from the arrival point it searches.
@export var search_radius := 5.0
## Longest a zombie will walk toward one search waypoint before picking
## another. A search leg that ran to completion every time would send a zombie
## on a long straight march away from the only place the player might plausibly
## be; cutting it short keeps it circling the believed position.
@export var search_leg_duration := 1.4
## How far past the believed position the first search leg carries.
##
## Walking *through* the spot rather than stopping on it is most of what makes
## a search read as a search. A body that arrives, halts, and pivots on the
## spot looks like a machine consulting a timer.
@export var search_overshoot := 3.0

@export_group("Sight")
## How far it can see. Generous, because a zombie that cannot see across a
## chamber makes the whole cave feel empty.
@export var sight_range := 20.0
## Total field of view. Behind it counts as unseen, so getting round one works.
@export var sight_cone_degrees := 140.0
## Seconds between line-of-sight checks. A raycast per zombie per frame is real
## cost for information that cannot change meaningfully at walking pace.
@export var sight_interval := 0.2
## How long it keeps hunting after losing sight.
##
## Not instant on purpose. A zombie that forgot you the moment you stepped
## behind a rock would be trivial to shake and would read as stupid rather
## than as something you outmanoeuvred.
@export var lose_sight_duration := 3.5
## How many seconds ahead of the player's last observed motion a zombie aims
## once the line breaks.
##
## Losing sight used to freeze the belief on the exact spot the player was
## standing, which meant the reliable way to shake anything was to keep
## walking in a straight line: it would arrive behind you every time. A zombie
## that just lost you now keeps leading you for a moment, so the seconds right
## after you break line of sight are the *most* dangerous ones rather than the
## safest. Guessing wrong is fine and frequently happens — that is what makes
## cutting back the other way work.
@export var sight_lead_time := 1.1

@export_group("Archetype")
## Seconds of flinch when shot. Zero means this kind cannot be interrupted at
## all — see the Brute. Set per kind by configure().
@export var stagger_duration := 0.22
## Loudness beneath this kind's notice, regardless of range.
@export var noise_floor := 0.0
## Seconds of uncontrolled run-on after a lunge ends, during which the zombie
## cannot steer, stop, or attack. Set per kind by configure(); only the Runner
## has it.
@export var overrun_duration := 0.0
## Pull toward nearby zombies of the same kind, as a fraction of move_speed.
@export_range(0.0, 1.0) var cohesion_strength := 0.0
## How far apart two zombies can be and still travel together.
@export var cohesion_radius := 9.0
## Metres behind the player this kind approaches from. Zero walks straight in.
@export var flank_distance := 0.0
## Whether being looked at makes this kind withdraw and try again elsewhere.
@export var breaks_off_when_watched := false
## Range at which a flanking kind abandons the flank and drives at the player.
##
## Without this the flank point is not a waypoint, it is a terminus: a Stalker
## walked to a spot flank_distance behind the player and stood on it. Measured
## on a stationary player, it settled exactly 5.5m out and held there for the
## rest of the encounter, never once attacking — 47% of samples stationary,
## which reads as an enemy that cannot make up its mind rather than one that is
## stalking you.
##
## A Stalker that has got behind you has already won its game. The right move
## then is to strike, not to keep circling, so past this range flanking stops
## having an opinion and it closes like anything else.
##
## Must be larger than flank_distance or it can never trigger — the body would
## park on the flank point before ever getting close enough to commit. The gap
## between the two is the length of the final run-in: at 7m a Stalker covers
## the last stretch in about a second and a half.
@export var flank_commit_distance := 7.0
## Half-angle, in degrees, within which the player counts as looking at this
## zombie. Deliberately narrower than a monitor's field of view: a Stalker that
## broke off whenever it was anywhere on screen could never close at all.
@export var watched_cone_degrees := 55.0
## Beyond this it does not care whether it is being looked at — a distant shape
## in the dark has not been spotted just because you faced its direction.
@export var watched_range := 16.0
@export var break_off_duration := 2.6
## How far it withdraws to. Far enough to leave the player's light, not so far
## that it disengages from the fight entirely.
@export var break_off_distance := 9.0
## Seconds between deliberate alarms while hunting. Zero means this kind only
## alerts others when it happens to groan.
@export var alarm_interval := 0.0
## Seconds a Screamer spends drawing breath before its first alarm of a hunt.
##
## 1.6s is costed from what the player has to actually do in it: register the
## cue (~0.7s), turn and pick the Screamer out of the crowd (~0.5s), and land
## the two pistol rounds its 34 health takes (~0.4s). Anything shorter and the
## window is decorative; much longer and a Screamer you decide to ignore stops
## punishing you for it, which is the other half of the decision.
##
## It is also exactly one alarm_interval, so the inhale costs a Screamer one
## scream's worth of time — the telegraph is paid for out of its own output
## rather than bolted on beside it.
@export var alarm_windup := 1.6
## How far this zombie's shout reaches. Set by the spawner from its own alert
## radius and the kind's multiplier, so one tuning knob still governs the crowd
## and a Screamer is expressed as a multiple of it rather than a second number
## that can drift out of step. Zero means this kind never tells anyone.
@export var alarm_radius := 14.0
## Whether hunting means running toward other zombies rather than at the
## player.
@export var flees_to_allies := false
## Multiplier on the awareness tell's brightness.
@export var glow_scale := 1.0

@export_group("Feel")
@export var groan_interval := Vector2(3.5, 9.0)
@export var corpse_collapse_time := 0.9

## What a zombie is doing about the player it is in range of.
enum AttackState {
	## Not attacking. Free to move normally.
	READY,
	## Holding still and turning to face the target. Readable, and the window
	## in which backing off avoids the hit entirely.
	WINDING_UP,
	## Committed to the direction faced when the windup ended. Cannot re-aim.
	LUNGING,
	## Still travelling in the lunge direction after the lunge itself is over,
	## unable to steer or attack. Only kinds with overrun_duration reach this.
	##
	## This is the Runner's cost of admission. Something that fast needs a way
	## to be wrong, and "it cannot stop" is a far more readable weakness than
	## a number on a sheet: you sidestep, it goes past, and for four tenths of
	## a second its back is to you.
	OVERRUNNING,
}

var _target: Node3D
var _attack_remaining := 0.0
var _attack_state: AttackState = AttackState.READY
var _attack_state_remaining := 0.0
var _attack_landed := false
var _lunge_direction := Vector3.ZERO
var _repath_remaining := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _groan_remaining := 0.0

## This zombie's own random stream, seeded independently of the shared global
## one. Everything individual — speed, turn rate, gait phase, hesitation — is
## drawn from this, so a crowd's jitter can never disturb something unrelated
## that happens to call randf() the same frame (the spawner's kind roll, for
## one).
var _rng := RandomNumberGenerator.new()
## Multiplier on move_speed, drawn once in _ready(). See speed_variation.
var _speed_scale := 1.0
## Multiplier on turn_speed, drawn once in _ready(). See turn_variation.
var _turn_scale := 1.0
var _hesitate_remaining := 0.0
## Capsule radius, cached by configure() so separation does not need to reach
## into a sibling's collider every tick to read its shape.
var _body_radius := 0.4
## Recomputed on the repath cadence, not every physics frame — see
## _compute_separation(). Applied every frame regardless, since adding a
## cached vector costs nothing.
var _separation_push := Vector3.ZERO

## What this zombie currently believes about the player.
##
## Replacing live omniscience with a belief is the whole point of this system.
## While it was reading the player's real position every frame, noise could
## only ever distract — it could not inform, because there was nothing left to
## learn. A belief can be stale, wrong, or planted, and all three are things
## the player can now work with.
var awareness: Awareness = Awareness.UNAWARE
var last_known_position := Vector3.ZERO

var _investigate_remaining := 0.0
var _search_remaining := 0.0
var _sight_remaining := 0.0
var _lost_sight_remaining := 0.0

## Where the current search is centred: the place the player was last believed
## to be, kept separate from last_known_position because the search moves the
## goal around while the reason for searching stays put.
var _search_origin := Vector3.ZERO
var _search_leg_remaining := 0.0
## Which way the last search leg went, so the next one is picked somewhere
## else. Sweeping a fresh random direction every leg lets a zombie re-check the
## same patch of floor three times in a row, which looks worse than not
## searching at all.
var _search_heading := 0.0

## The player's velocity as last observed, in metres per second, estimated
## from two consecutive sightings. Drives the lead applied to the belief when
## the line breaks — see sight_lead_time.
var _seen_velocity := Vector3.ZERO
var _previous_seen_position := Vector3.ZERO
var _has_previous_sighting := false

## Where a zombie that has broken off is withdrawing to, and how long it stays
## withdrawn. Only kinds with breaks_off_when_watched use either.
var _retreat_position := Vector3.ZERO
## The direction the current withdrawal is going, fixed for its duration. Kept
## so that a Stalker the player keeps looking at extends one retreat instead of
## starting a new one every sight tick — see _begin_break_off().
var _retreat_heading := Vector3.ZERO
var _retreat_remaining := 0.0
var _alarm_remaining := 0.0
## True while a Screamer is drawing breath but has not yet let it out. The
## window in which killing it prevents the pull entirely.
var _inhaling := false
## Nearest living neighbour, refreshed by the neighbour scan on the repath
## cadence. Free, since that scan already visits every sibling — and it is what
## a Screamer runs toward instead of at the player.
var _nearest_ally_position := Vector3.INF
## Seconds of stagger left. Separate from _hesitate_remaining so being shot
## cannot be confused with idle hesitation, and so a stagger-immune kind's
## timer is provably always zero.
var _stagger_remaining := 0.0

## Whether this zombie has been taken out of the fight because the round is
## over. Read by the spawner and by the tests; set only through
## stop_fighting() and resume_fighting().
##
## This is a separate flag rather than just switching physics processing off,
## because the things that have to stop are not all driven from the physics
## frame. A stopped zombie still has live signal connections, and anything that
## reaches it by another route — a hit resolving, a noise broadcast, an alarm
## from a zombie that was stopped a frame later — must find a body that has
## already left the fight.
var is_stopped := false

## Set by configure(); read by the spawner when this zombie dies.
var kind: ZombieTypes.Kind = ZombieTypes.Kind.SHAMBLER
var experience_value := 1
var ammo_value := 3

## Capsule radius as a fraction of the body's height. A human figure is roughly
## four and a half times as tall as it is wide through the shoulders.
const BODY_RADIUS_RATIO := 0.22
## Height the exported attack_range below was tuned against.
const REFERENCE_HEIGHT := 2.0
## Close enough to a sound to count as having reached it.
const ARRIVAL_DISTANCE := 2.0

## What a zombie glows when it has heard something, and when it has seen you.
const INVESTIGATING_GLOW := Color(1.0, 0.62, 0.2)
const HUNTING_GLOW := Color(1.0, 0.2, 0.12)
## Casting about, having found nothing. Cooler and weaker than the amber of a
## zombie walking purposefully toward a belief, because they are genuinely
## different situations to walk into: one is heading somewhere, the other has
## given up on heading anywhere and is sweeping the room you are standing in.
const SEARCHING_GLOW := Color(0.72, 0.78, 0.35)
## Withdrawing. Cold, and the faintest tell in the game — a Stalker that has
## just broken off is supposed to be most of the way to invisible, and the
## information the player gets is "it was there a moment ago".
const RETREATING_GLOW := Color(0.35, 0.55, 1.0)

## Deliberately faint. Emission adds on top of the skin, so anything stronger
## floods the whole body and flattens a zombie into a glowing silhouette —
## losing the character entirely and costing more atmosphere than the clarity
## is worth. These read at corridor distance against an unlit wall and are
## barely noticeable up close, which is the right way round: up close you can
## already see what it is doing.
const INVESTIGATING_GLOW_ENERGY := 0.09
const HUNTING_GLOW_ENERGY := 0.32
const SEARCHING_GLOW_ENERGY := 0.06
const RETREATING_GLOW_ENERGY := 0.04
## What a Screamer turns while drawing breath. A cold white against its own
## sickly yellow, so the change reads as a change rather than as the same
## shape getting brighter — the player has to be able to tell "there is a
## Screamer" from "the Screamer is about to go off" at a glance.
const INHALE_GLOW := Color(0.85, 0.95, 1.0)
## Brightest thing the game ever puts on a body, before glow_scale multiplies
## it again. This is the one moment the design actively wants the player to
## look away from whatever else is happening.
const INHALE_GLOW_ENERGY := 0.55

var base_attack_range := 1.9
## The unmodified sight memory the per-kind multiplier is applied to. Mirrors
## base_attack_range: the exported value is what a kind's scale multiplies,
## and keeping the baseline separate makes configure() idempotent.
var base_lose_sight_duration := 3.5

@onready var health: Health = $Health
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: ZombieVisual = $Visual
@onready var _collider: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = attack_range * 0.7

	_groan_remaining = randf_range(groan_interval.x, groan_interval.y)

	# The cave floor meets doorways in steep rocky lips. At the default 45° a
	# zombie treats those as walls and stops dead; a steep limit lets it walk up
	# them while still being blocked by the near-vertical walls themselves.
	floor_max_angle = deg_to_rad(floor_climb_angle_degrees)

	_rng.randomize()
	_speed_scale = 1.0 + _rng.randf_range(-speed_variation, speed_variation)
	_turn_scale = 1.0 + _rng.randf_range(-turn_variation, turn_variation)
	_visual.set_gait_offset(_rng.randf())


func _physics_process(delta: float) -> void:
	_attack_remaining = maxf(0.0, _attack_remaining - delta)
	_stagger_remaining = maxf(0.0, _stagger_remaining - delta)
	_tick_groan(delta)
	_visual.update_locomotion(Vector2(velocity.x, velocity.z).length())

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if _target == null or health.is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_tick_senses(delta)
	_tick_awareness(delta)
	_tick_repath(delta)

	# An attack in progress owns velocity outright — winding up holds the body
	# still and lunging commits it to a straight line, neither of which the
	# normal path-following steering should be allowed to override.
	if not _tick_attack(delta):
		_move_toward_target(delta)

	move_and_slide()


## Apply a kind's stats and look. Called by the spawner before the zombie
## enters the fight, so health is set before _ready reads max_health.
func configure(zombie_kind: ZombieTypes.Kind) -> void:
	kind = zombie_kind
	var definition := ZombieTypes.definition(kind)

	move_speed = definition.speed
	contact_damage = definition.damage
	experience_value = definition.experience
	ammo_value = definition.ammo
	hearing_range = definition.hearing
	acceleration = definition.acceleration
	turn_speed = definition.turn_speed
	attack_windup = definition.attack_windup
	lunge_speed = definition.lunge_speed

	# The behaviour block. Everything below changes what this zombie *does*
	# rather than how well it does it, which is the difference between five
	# enemies and one enemy with five health bars.
	attack_commit_duration = definition.attack_commit
	stagger_duration = definition.stagger_duration
	noise_floor = definition.noise_floor
	overrun_duration = definition.overrun_duration
	cohesion_strength = definition.cohesion_strength
	flank_distance = definition.flank_distance
	breaks_off_when_watched = definition.breaks_off_when_watched
	alarm_interval = definition.alarm_interval
	alarm_windup = definition.alarm_windup
	flees_to_allies = definition.flees_to_allies
	glow_scale = definition.glow_scale
	groan_interval = definition.groan_interval
	# Scaled from the untouched baseline rather than from the current value, so
	# configuring a zombie twice cannot compound the multiplier.
	lose_sight_duration = base_lose_sight_duration * definition.sight_memory_scale

	# alarm_radius is not set here: it is a multiple of the spawner's crowd
	# alert radius, which this zombie has no business knowing about. The
	# spawner applies the kind's multiplier itself right after configure().

	_groan_remaining = randf_range(groan_interval.x, groan_interval.y)

	health.max_health = definition.health
	health.current_health = definition.health

	var height: float = definition.height
	_visual.apply_kind(height, definition.tint)

	# The capsule is built from the same height the model was scaled to, so
	# what you shoot at is what you hit. These used to come from separate
	# numbers and ended up a factor of two apart: the hitbox sat around the
	# zombie's legs while the player was aiming at its chest, and most shots
	# that looked like hits passed straight through.
	_collider.shape = _collider.shape.duplicate()
	_collider.shape.height = height
	_collider.shape.radius = height * BODY_RADIUS_RATIO
	_collider.position.y = height * 0.5
	_body_radius = _collider.shape.radius

	# A Brute is wider as well as taller, and reach has to grow with the body
	# or it cannot land a blow its arms clearly reach.
	attack_range = base_attack_range * (height / REFERENCE_HEIGHT)


## Take this zombie out of the fight, and leave it standing where it is.
##
## Called when the round ends. Stopping the spawner used to stop only the
## spawning: every zombie already in the cave carried on pathing, biting and
## groaning behind the results overlay, so a player reading their score was
## still taking damage flashes, hurt audio and contact pings from a fight that
## was over — at the CPU cost of a full horde still running navigation on a
## screen nobody was playing.
##
## Frozen rather than despawned, and frozen rather than merely defanged. A
## results screen with the horde still milling about in the background reads as
## the game continuing without you; a horde that vanishes the instant you die
## reads as a bug. Standing still is the only one of the three that looks
## deliberate — and it is also the cheapest, since the physics frame is where
## essentially all of a zombie's cost lives.
##
## Deliberately not a state on the awareness machine. Awareness is what a
## zombie believes about the player, and "the round is over" is not something
## it believes — mixing the two would mean every branch of the state machine
## growing a case for a situation that is not about the player at all.
func stop_fighting() -> void:
	if is_stopped:
		return

	is_stopped = true

	# Left mid-stride otherwise: the visual reads the horizontal speed to pick
	# its animation, so a frozen zombie with velocity still on it would stand
	# in place playing a run cycle.
	velocity = Vector3.ZERO
	_visual.update_locomotion(0.0)

	set_physics_process(false)


## Put a stopped zombie back to work.
##
## The inverse matters as much as the stop. Restarting has to be able to hand
## the fight back to anything that survived, and a freeze with no way out would
## turn one ended round into a permanently disarmed horde.
func resume_fighting() -> void:
	if not is_stopped:
		return

	is_stopped = false
	set_physics_process(true)


## Assign the node this zombie hunts, and give it a reason to be here.
##
## A newly spawned zombie starts out already believing the player is where they
## were at that moment. That is both the fiction — it is arriving because it
## heard the fight — and the safeguard that keeps the horde relentless: without
## it, spawns would wander off into empty chambers and the pressure the whole
## game is built on would quietly drain away.
func set_target(target: Node3D) -> void:
	_target = target
	if target == null:
		return

	_believe(target.global_position)

	if is_inside_tree():
		_agent.target_position = last_known_position


## Damage entry point used by the weapon's raycast.
func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO,
		_direction: Vector3 = Vector3.ZERO) -> float:
	return health.take_damage(amount)


## React to a noise somewhere in the cave.
##
## A sound reveals a *place*, never a person. The zombie goes to look, which is
## what makes firing cost the shooter their position rather than only a bullet.
##
## Two deliberate deafnesses. A zombie that can already see the player ignores
## noise entirely — something with eyes on you does not wander off because a
## gun went off nearby, and letting it would make firing an escape rather than
## a cost. And a sound beyond this zombie's hearing does nothing at all, which
## is what makes distance a defence worth having.
##
## Returns true only when the noise actually told this zombie something.
func hear_noise(noise_position: Vector3, loudness: float) -> bool:
	if health.is_dead or is_stopped or awareness == Awareness.HUNTING:
		return false

	# Beneath notice. A Brute's floor sits above a thrown decoy and below a
	# gunshot on purpose: the trick that peels every other kind off does not
	# work on the one you most want to peel off, so a Brute in the room turns
	# the decoy from an answer into a delaying tactic for everything *else*.
	if loudness < noise_floor:
		return false

	if not _can_hear(noise_position, loudness):
		return false

	_believe(noise_position)
	return true


## Whether a sound at this position and loudness reaches this zombie.
##
## Measured along the navmesh rather than straight through rock. In a cave of
## chambers joined by corridors that is the difference between a system the
## player can learn and one that feels arbitrary: a wall should muffle, a
## corridor should carry, and a shot two rooms away should not be as loud as
## one in the open.
##
## Path distance is never shorter than straight-line distance, so the cheap
## check below is a perfect conservative filter — anything it rejects would
## have been rejected by the expensive one too. Only sounds that could plausibly
## reach pay for a path query.
func _can_hear(noise_position: Vector3, loudness: float) -> bool:
	var reach := hearing_range * loudness
	if global_position.distance_to(noise_position) > reach:
		return false

	var map: RID = get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(
		map, global_position, noise_position, true
	)

	# No route at all means no way for the sound to travel either.
	if path.size() < 2:
		return false

	var travelled := 0.0
	for index in range(1, path.size()):
		travelled += path[index - 1].distance_to(path[index])
		if travelled > reach:
			return false

	return true


## Change state, and make the change visible and audible.
##
## Every zombie has had a mental model since the awareness system landed, and
## none of it reached the player. A system you cannot read is indistinguishable
## from one that is cheating: a crowd converges and you have no way to know
## whether you were seen, heard, or told. The tells are not decoration — they
## are what turns the model into something you can play against.
func _set_awareness(next: Awareness) -> void:
	if next == awareness:
		return

	var previous := awareness
	awareness = next
	_apply_awareness_tell()

	# The moment something starts hunting you is the single most important
	# thing that happens in a round, and it used to happen in silence.
	if next == Awareness.HUNTING and previous != Awareness.HUNTING:
		noticed_player.emit(global_position, kind)
		# Notice, then inhale, then scream. A Screamer that loses the player and
		# finds them again pays the full wind-up a second time, so breaking its
		# line of sight is a real answer and not merely a delay.
		_begin_inhale()

	if previous == Awareness.HUNTING and next != Awareness.HUNTING:
		_inhaling = false


## Colour a zombie by what it knows.
##
## Emission rather than albedo, so it reads in a dark corridor at distance —
## which is exactly where you need to know whether the shape ahead has noticed
## you. Kept dim on purpose: this is a tell, not a healthbar, and a cave full
## of glowing outlines would cost more atmosphere than it buys clarity.
func _apply_awareness_tell() -> void:
	if _visual == null:
		return

	match awareness:
		Awareness.HUNTING:
			_visual.apply_glow(HUNTING_GLOW, HUNTING_GLOW_ENERGY * glow_scale)
		Awareness.INVESTIGATING:
			_visual.apply_glow(
				INVESTIGATING_GLOW, INVESTIGATING_GLOW_ENERGY * glow_scale
			)
		Awareness.SEARCHING:
			_visual.apply_glow(SEARCHING_GLOW, SEARCHING_GLOW_ENERGY * glow_scale)
		Awareness.RETREATING:
			_visual.apply_glow(RETREATING_GLOW, RETREATING_GLOW_ENERGY * glow_scale)
		_:
			_visual.apply_glow(Color.BLACK, 0.0)


## Adopt a belief about where the player is, and go and look.
func _believe(where: Vector3) -> void:
	last_known_position = where
	_investigate_remaining = investigate_duration
	_search_remaining = 0.0
	_set_awareness(Awareness.INVESTIGATING)


## States in which new information is refused because the zombie is already
## acting on better information, or is deliberately busy.
##
## Hunting is the original case: something with eyes on you does not wander off
## because a gun went off nearby. Retreating is the same idea from the other
## end — a Stalker that has just broken off knows perfectly well where you are,
## and letting a stray noise pull it straight back into your view would undo
## the one behaviour that makes it a Stalker.
func _is_committed() -> bool:
	return awareness == Awareness.HUNTING or awareness == Awareness.RETREATING


## Told by another zombie. Alerts spread through a crowd, which is what turns
## one noticed gunshot into a chamber emptying toward you rather than a single
## zombie taking an interest.
func receive_alert(where: Vector3) -> void:
	if health.is_dead or is_stopped or _is_committed():
		return

	_believe(where)


## True while this zombie is acting on a belief, whether it is still walking to
## it or already sweeping the area around it.
##
## Searching is a separate state internally because it needs its own goals and
## its own tell, but to everything outside this class it is the same answer:
## this zombie thinks you are somewhere and is doing something about it.
func is_investigating() -> bool:
	return awareness == Awareness.INVESTIGATING or awareness == Awareness.SEARCHING


func is_hunting() -> bool:
	return awareness == Awareness.HUNTING


## Working the area around a belief that turned out to be empty.
func is_searching() -> bool:
	return awareness == Awareness.SEARCHING


## Deliberately withdrawing after being looked at. Stalkers only.
func is_retreating() -> bool:
	return awareness == Awareness.RETREATING


## The point this zombie wants to reach in order to attack a player standing at
## player_position and facing player_facing.
##
## Public and pure so the flanking behaviour can be asserted rather than
## eyeballed: a Stalker's answer must sit outside the player's view far more
## often than a Shambler's, and "far more often" is only meaningful if
## something measures it.
##
## Everything except a Stalker answers "where the player is", which is the
## correct answer for a creature with no plan.
func preferred_approach_point(player_position: Vector3, player_facing: Vector3) -> Vector3:
	if flank_distance <= 0.0:
		return player_position

	# Close enough to stop manoeuvring and attack. Flanking is how it gets
	# there, not where it is going — see flank_commit_distance.
	if global_position.distance_to(player_position) <= flank_commit_distance:
		return player_position

	var facing := Vector3(player_facing.x, 0.0, player_facing.z)
	if facing.length_squared() < 0.0001:
		return player_position

	# Directly behind them, measured against where they are looking rather
	# than where they are moving. A player who backpedals while shooting is
	# still watching the way they face, and it is the watching that matters.
	return player_position - facing.normalized() * flank_distance


## Where this zombie is currently trying to get to.
##
## Hunting tracks the player live; everything else walks to a belief, which may
## be wrong and usually is by the time it arrives.
func _move_goal() -> Vector3:
	if awareness == Awareness.RETREATING:
		return _retreat_position

	if awareness != Awareness.HUNTING or _target == null:
		return last_known_position

	# A Screamer hunting the player does not go near the player. It runs to
	# whatever else is alive and shouts from behind it, which is what turns
	# "shoot the Screamer" from an aiming problem into a positioning one.
	if flees_to_allies:
		if _nearest_ally_position.is_finite():
			return _nearest_ally_position

		# Nothing to hide behind. Back away from the player instead — still
		# not toward them, because a Screamer that charges when alone is just
		# a bad Shambler.
		var away := global_position - _target.global_position
		away.y = 0.0
		if away.length_squared() < 0.0001:
			return last_known_position
		return global_position + away.normalized() * break_off_distance

	return preferred_approach_point(
		_target.global_position, -_target.global_transform.basis.z
	)


## Look for the player, and remember having seen them.
##
## Sight is checked on a slow cadence rather than every frame. A raycast per
## zombie per frame is real cost for information that cannot meaningfully
## change in a tenth of a second at walking pace.
func _tick_senses(delta: float) -> void:
	_sight_remaining -= delta
	if _sight_remaining > 0.0:
		return

	_sight_remaining = sight_interval

	if _can_see_target():
		_observe_target()

		# Being seen is not the same as being caught, for one kind. A Stalker
		# that finds itself in the player's view gives up the approach and
		# goes round again rather than trading its advantage for a few metres.
		if breaks_off_when_watched and _is_being_watched():
			_begin_break_off()
			return

		_set_awareness(Awareness.HUNTING)
		_lost_sight_remaining = lose_sight_duration
		return

	_has_previous_sighting = false

	# Sight is not lost the instant the line breaks, and what the zombie holds
	# on to is not a spot on the floor. It keeps leading the player along the
	# motion it last saw, so the fade from certainty to a guess happens over
	# seconds and at a position that is still roughly right at first.
	#
	# Freezing the belief on the exact spot instead made walking in a straight
	# line the reliable way to shake anything: it would arrive behind you every
	# time. Leading makes the moment just after you break line of sight the
	# most dangerous one rather than the safest, and makes cutting back the
	# other way the thing that actually works.
	if awareness == Awareness.HUNTING:
		_lost_sight_remaining -= sight_interval
		last_known_position += _seen_velocity * sight_interval

		if _lost_sight_remaining <= 0.0:
			var elapsed := lose_sight_duration
			_believe(last_known_position + _seen_velocity * sight_lead_time)
			# Whatever is left of the memory is spent walking to the guess, so
			# a long-memoried Brute keeps at it and a Runner gives up early.
			_investigate_remaining = minf(investigate_duration, elapsed * 2.0)
			_seen_velocity = Vector3.ZERO


## Record where the player is, and how fast they were going when seen.
##
## Two consecutive sightings are enough for a usable velocity, and sightings
## come in on the slow sight cadence rather than every frame, so this costs one
## subtraction per zombie every sight_interval.
func _observe_target() -> void:
	var seen_at := _target.global_position

	if _has_previous_sighting:
		var motion := (seen_at - _previous_seen_position) / maxf(sight_interval, 0.001)
		motion.y = 0.0
		# Smoothed, or a single frame of strafing throws the prediction across
		# the room and the zombie lurches after a direction the player never
		# committed to.
		_seen_velocity = _seen_velocity.lerp(motion, 0.5)
	else:
		_seen_velocity = Vector3.ZERO

	_previous_seen_position = seen_at
	_has_previous_sighting = true
	last_known_position = seen_at


## Whether the player is looking more or less straight at this zombie.
##
## Deliberately a narrower cone than the player's actual field of view, and
## range-limited: a shape at the far end of an unlit corridor has not been
## spotted merely because the player happened to face its direction, and a
## Stalker that broke off whenever it was anywhere on screen could never
## complete an approach at all.
func _is_being_watched() -> bool:
	if _target == null:
		return false

	var to_self := global_position - _target.global_position
	to_self.y = 0.0
	var distance := to_self.length()

	if distance > watched_range or distance < 0.01:
		return false

	var facing := -_target.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return false

	return facing.normalized().dot(to_self / distance) > cos(
		deg_to_rad(watched_cone_degrees * 0.5)
	)


## Break contact and reposition, keeping what it knows.
##
## The withdrawal point is off to one side rather than straight backward: a
## Stalker that reversed in a line would simply be walking away, and would
## come back along the route the player is already watching.
## Continuing to back off under a steady gaze is intended. Picking a new
## direction to back off in, five times a second, is not: break-off is reached
## from the sight tick, which runs every sight_interval for as long as the
## player keeps looking. The outward component of the withdrawal was stable and
## the sideways one was re-rolled each time, so a watched Stalker crabbed from
## side to side and never actually left.
##
## Already retreating means extend, not restart: same heading, re-projected
## from wherever the body has got to, and the clock pushed back out to full.
func _begin_break_off() -> void:
	if awareness == Awareness.RETREATING:
		_retreat_remaining = break_off_duration
		_retreat_position = global_position + _retreat_heading * break_off_distance
		return

	_retreat_remaining = break_off_duration

	var away := global_position - _target.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.FORWARD

	# Sideways component is drawn from this zombie's own stream, so two
	# Stalkers backing off from the same spot do not peel the same way.
	var sideways := away.normalized().cross(Vector3.UP) * _rng.randf_range(-1.0, 1.0)

	# Drawn once and kept for the whole withdrawal. The randomness is there so
	# two Stalkers backing off from the same spot do not peel the same way, not
	# so that one Stalker peels a different way every tick.
	_retreat_heading = (away.normalized() + sideways).normalized()
	_retreat_position = global_position + _retreat_heading * break_off_distance

	_set_awareness(Awareness.RETREATING)


## The direction this zombie's body is actually pointing.
##
## Godot's standard: an imported character model, look_at(), the sight cone and
## the lunge all treat -Z as the front of a body, and all four already agreed.
##
## The steering did not. _move_toward_target() set the yaw with
## `atan2(velocity.x, velocity.z)`, which puts *+Z* along the direction of
## travel, so every zombie in the game was turned exactly 180 degrees from
## where it was going — walking backwards, with its 140-degree vision cone
## pointing at the ground it had already crossed. Measured with a probe on a
## Shambler closing on a stationary player, the dot product between facing and
## the direction to the player sat at -1.00 for the whole approach.
##
## That one sign was quietly holding down most of this class, because HUNTING
## is only ever entered by *seeing* the player. Zombies arrived, attacked and
## killed while still INVESTIGATING, which meant the hunting tell never lit,
## the spawner's threat meter (which counts hunters only) read near-zero during
## a mauling, a Screamer could not raise an alarm because alarms require
## HUNTING, and a Stalker could not break off because break-off is reached from
## a successful sight check. Each of those looked like a separate design
## problem and none of them was.
##
## This accessor exists so there is one place that answers the question, rather
## than four call sites each spelling out a sign that is easy to get wrong.
func facing() -> Vector3:
	return -global_transform.basis.z


func _can_see_target() -> bool:
	if _target == null:
		return false

	var to_target := _target.global_position - global_position
	var distance := to_target.length()

	# A lit player is visible further off. This asks the target how visible it
	# is rather than having the torch reach in and edit sight_range: pull, not
	# push, so the light cannot fight inspector tuning, cannot stack across
	# several zombies, and cannot leave one permanently buffed because the
	# player happened to die mid-beam.
	#
	# It is also what finally makes the torch a decision. Until now seeing in a
	# pitch-black cave was free, so the only reason to ever switch it off was
	# that you had forgotten it was on.
	var reach := sight_range
	if _target.has_method("visibility_scale"):
		reach *= _target.visibility_scale()

	if distance > reach:
		return false

	# Behind counts as unseen, so breaking line of sight by getting behind one
	# actually works.
	var facing := facing()
	if distance > 0.01 and facing.dot(to_target / distance) < cos(deg_to_rad(sight_cone_degrees * 0.5)):
		return false

	# Eye height on both ends, or the ray leaves from the floor and clips the
	# lip of every doorway.
	var eye_height: float = _collider.shape.height * 0.85
	var from := global_position + Vector3.UP * eye_height
	var to := _target.global_position + Vector3.UP * 1.5

	var query := PhysicsRayQueryParameters3D.create(from, to)
	# World geometry only: other zombies must not block the view, or a crowd
	# would blind itself.
	query.collision_mask = 1
	query.exclude = [get_rid()]

	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Run down the belief: walk to it, search around it, then give up on it.
func _tick_awareness(delta: float) -> void:
	_tick_alarm(delta)

	match awareness:
		Awareness.SEARCHING:
			_tick_search(delta)

		Awareness.RETREATING:
			_retreat_remaining -= delta
			if _retreat_remaining <= 0.0:
				# It never stopped knowing where you were; it only stopped
				# walking at you. Coming back out of a break-off as a fresh
				# belief is what makes a Stalker circle rather than flee.
				_believe(last_known_position)

		Awareness.INVESTIGATING:
			_investigate_remaining -= delta

			# Arrived, and nothing here. Work the area before losing interest
			# — a zombie that snaps from "hunting" to "idle" on the spot reads
			# as a switch being flipped.
			if global_position.distance_to(last_known_position) <= ARRIVAL_DISTANCE:
				_begin_search()
			elif _investigate_remaining <= 0.0:
				_begin_search()


## Keep shouting while hunting, for the kinds that shout on purpose.
##
## Everything else raises the alarm incidentally, when a groan happens to land
## while it can see the player. A Screamer is the only thing in the cave that
## treats spreading the word as its job, which is why it is the only thing that
## does it on a clock.
func _tick_alarm(delta: float) -> void:
	if alarm_interval <= 0.0 or awareness != Awareness.HUNTING:
		return

	_alarm_remaining -= delta
	if _alarm_remaining > 0.0:
		return

	_inhaling = false
	_alarm_remaining = alarm_interval
	_scream()


## Draw breath. The window in which killing a Screamer actually prevents
## something.
##
## Without this the alarm was instantaneous on noticing, and measurement showed
## what that meant: one Screamer recruited 8 of 8 sleepers in a single tick at
## 4.1 seconds. The design promise is "kill it first and fast", but there was no
## interval in which being fast helped — the player cannot pick one shape out of
## a crowd at 17m in an unlit cave before a scream that costs nothing to make
## has already landed.
##
## A wider or narrower alarm radius cannot create that interval; only time can.
## Measured directly: dropping alarm_radius_scale from 2.6 to 1.8 changed the
## recruit count not at all, because the horde is clustered well inside either
## radius.
##
## Modelled on the attack wind-up rather than invented, so it reads the way
## every other telegraph in this project reads: a thing visibly commits, and
## for a moment it is committed and you are not.
func _begin_inhale() -> void:
	if alarm_interval <= 0.0:
		return

	_inhaling = true
	_alarm_remaining = alarm_windup

	# Two channels, because the player will meet this down a corridor in the
	# dark while already shooting at something else.
	#
	# The glow is the Screamer's own tell at its own brightness — it is already
	# the most luminous thing in the cave by a factor of two and a half, and
	# this is a distinct colour on top of that, so "the yellow one just changed"
	# reads at range.
	if _visual != null:
		_visual.apply_glow(INHALE_GLOW, INHALE_GLOW_ENERGY * glow_scale)

	# Sound does the heavier lifting: light needs line of sight and a corridor
	# denies it. groaned is emitted deliberately rather than only the new
	# signal, because the spawner already relays groans to the audio system and
	# that gives an immediate positional cue with no change outside this class.
	# alarm_winding_up is the hook for a dedicated inhale sound to replace it.
	alarm_winding_up.emit(self, global_position)
	groaned.emit(global_position)


## Let it out, and go back to looking like an ordinary hunter.
func _scream() -> void:
	_apply_awareness_tell()

	if alarm_radius > 0.0:
		raised_alarm.emit(self, last_known_position)


## Work the ground around a belief that turned out to be empty.
##
## Searching used to be a four-second countdown spent standing on one spot with
## a single random destination picked at the start, which is not what searching
## looks like from the outside — it looks like a body waiting for a timer. This
## keeps the zombie moving through and around the place it thought you were,
## re-picking a leg whenever it arrives or whenever a leg has run long enough,
## and only gives up when the whole search budget is spent.
##
## The total budget is unchanged, so a belief still decays in search_duration
## seconds however many legs it fits into that time.
func _tick_search(delta: float) -> void:
	_search_remaining -= delta
	if _search_remaining <= 0.0:
		_set_awareness(Awareness.UNAWARE)
		return

	_search_leg_remaining -= delta
	var arrived := global_position.distance_to(last_known_position) <= ARRIVAL_DISTANCE

	if _search_leg_remaining <= 0.0 or arrived:
		_pick_search_leg()


func _begin_search() -> void:
	_search_origin = last_known_position
	_search_remaining = search_duration
	_search_heading = _rng.randf() * TAU

	_set_awareness(Awareness.SEARCHING)

	# The first leg carries straight through the believed position rather than
	# stopping on it. Walking through a place is how a body checks it; halting
	# on the exact coordinate is how a cursor arrives.
	var approach := _search_origin - global_position
	approach.y = 0.0
	if approach.length_squared() < 0.0001:
		_pick_search_leg()
		return

	last_known_position = _search_origin + approach.normalized() * search_overshoot
	_search_leg_remaining = search_leg_duration


## Pick somewhere else near the believed position to go and look.
##
## Directions are stepped around a ring rather than drawn fresh each time.
## Re-rolling would happily send a zombie back over the same patch of floor
## three legs running, which looks worse than not searching at all.
func _pick_search_leg() -> void:
	_search_heading += _rng.randf_range(TAU * 0.25, TAU * 0.55)
	var radius := search_radius * _rng.randf_range(0.45, 1.0)

	last_known_position = _search_origin + Vector3(
		cos(_search_heading) * radius, 0.0, sin(_search_heading) * radius
	)
	_search_leg_remaining = search_leg_duration


## Refresh the nav target and the things that only need to change this often:
## the separation push and whether this zombie hesitates for a beat.
##
## Both are recomputed on the existing repath cadence rather than every
## physics frame. Crowding cannot change meaningfully in under 150ms at
## walking pace, so amortising an O(neighbours) scan this way — instead of
## running it 60 times a second per zombie — is most of the cost of separation
## for none of the responsiveness lost.
func _tick_repath(delta: float) -> void:
	_repath_remaining -= delta
	if _repath_remaining > 0.0:
		return

	_repath_remaining = repath_interval
	_agent.target_position = _move_goal()
	_separation_push = _compute_separation()

	# A hunting zombie never hesitates — something with eyes on you does not
	# pause to think about it. Reserved for the states where a beat of
	# stillness reads as noticing or reconsidering rather than a hitch in
	# something that is supposed to be relentless.
	if awareness != Awareness.HUNTING and _rng.randf() < hesitation_chance:
		_hesitate_remaining = _rng.randf_range(hesitation_duration.x, hesitation_duration.y)


func _move_toward_target(delta: float) -> void:
	# Reeling from a hit. Held still rather than merely slowed, because the
	# point of a stagger is that it is unambiguous: you shot it, it stopped.
	if _stagger_remaining > 0.0:
		_accelerate_toward(Vector3.ZERO, delta)
		return

	if _hesitate_remaining > 0.0:
		_hesitate_remaining -= delta
		_accelerate_toward(Vector3.ZERO, delta)
		return

	var next_position := _agent.get_next_path_position()
	var to_next := next_position - global_position
	to_next.y = 0.0

	var goal_velocity := Vector3.ZERO
	if to_next.length() >= 0.05:
		goal_velocity = to_next.normalized() * (move_speed * _speed_scale)

	# Separation is added to the goal rather than resolved separately, so a
	# zombie that has arrived but is still overlapping a neighbour keeps
	# getting nudged apart instead of the push being dropped the instant
	# get_next_path_position() reports "close enough".
	var desired_velocity := goal_velocity + _separation_push

	if desired_velocity.length_squared() < 0.0001:
		_accelerate_toward(Vector3.ZERO, delta)
		return

	_accelerate_toward(desired_velocity, delta)

	# Face travel direction. Interpolated so zombies do not snap around when
	# the path bends around a crate.
	# Negated on both axes so that -Z, not +Z, ends up along the direction of
	# travel. Without the signs a zombie walks backwards: the model faces the
	# way it came and the sight cone looks at ground already crossed.
	var desired_yaw := atan2(-desired_velocity.x, -desired_velocity.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, turn_speed * _turn_scale * delta)


## Move the horizontal velocity toward a desired velocity at this zombie's
## acceleration, rather than snapping straight to it.
##
## This one function is the entire "weight" of a zombie's movement: a Brute's
## low acceleration is what makes it feel heavy to get moving, and the same
## call handles slowing to a stop, so a Brute is exactly as sluggish about
## stopping as it is about starting.
func _accelerate_toward(desired_velocity: Vector3, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(desired_velocity, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## How hard, and in which direction, this zombie should push away from bodies
## it is overlapping.
##
## Zombies deliberately do not collide with each other (see the class comment)
## so this is the only thing standing between a crowd and a single stack of
## bodies occupying one point in space. It is a steering nudge, not a physics
## response — nothing here can push a zombie backward off its goal, only
## sideways off another zombie, which is what keeps this from being able to
## stall a pursuit.
## It also answers two other questions that need the same loop and would
## otherwise each cost their own O(neighbours) scan: where the nearest living
## zombie is (a Screamer runs toward it) and where the local group of this
## zombie's own kind is heading (a Shambler drifts toward it). Folding all
## three into one pass over the siblings is the only reason two new behaviours
## cost nothing.
## Whether running to this spot would take a fleeing zombie toward the player.
##
## Distance alone is not enough. A zombie five metres away can still be five
## metres away *past* the player, and a Screamer that ran to it would close
## with the thing it is running from. The rule is simply that the refuge may
## not be nearer the player than the Screamer already is — which makes the
## behaviour true by construction rather than true in the common case.
func _is_refuge(where: Vector3) -> bool:
	if _target == null:
		return true

	var player_position := _target.global_position
	return where.distance_to(player_position) >= global_position.distance_to(player_position)


func _compute_separation() -> Vector3:
	var push := Vector3.ZERO
	_nearest_ally_position = Vector3.INF
	var nearest_distance := INF
	var cohesion_sum := Vector3.ZERO
	var cohesion_count := 0

	var parent := get_parent()
	if parent == null:
		return push

	for sibling in parent.get_children():
		if sibling == self:
			continue

		var other := sibling as Zombie
		if other == null or not is_instance_valid(other) or other.health.is_dead:
			continue

		var offset := global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		var combined_radius: float = _body_radius + other._body_radius + separation_margin

		# Only a kind that actually runs to other zombies pays for this, and
		# only within the range at which a neighbour is a neighbour. The search
		# was previously unbounded, which had two bad consequences: any zombie
		# anywhere in the cave counted as cover, so the "nothing to hide
		# behind" fallback below only ran when the Screamer was the last thing
		# alive in the arena; and if the only other zombie was on the far side
		# of the player, the destination was on the far side of the player. The
		# one kind designed never to approach you would charge through you to
		# get there.
		#
		# cohesion_radius is reused rather than a new constant invented: it is
		# already this class's answer to "how far apart can two zombies be and
		# still be together", and hiding behind something is the same question.
		if (
			flees_to_allies
			and distance < nearest_distance
			and distance <= cohesion_radius
			and _is_refuge(other.global_position)
		):
			nearest_distance = distance
			_nearest_ally_position = other.global_position

		# Group up with your own kind, but only at a range where separation is
		# not already shoving you apart. Overlapping the two forces would leave
		# every zombie permanently fighting itself, and the result reads as
		# jitter rather than as a crowd.
		if (
			cohesion_strength > 0.0
			and other.kind == kind
			and distance > combined_radius
			and distance < cohesion_radius
		):
			cohesion_sum += other.global_position
			cohesion_count += 1

		if distance >= combined_radius or distance < 0.001:
			continue

		# Push harder the more two bodies overlap, so a graze is a nudge and a
		# dead-on stack is a shove.
		var overlap := (combined_radius - distance) / combined_radius
		push += (offset / distance) * overlap

	if push.length_squared() > 1.0:
		push = push.normalized()

	var steering := push * move_speed * separation_strength

	# Shamblers arrive in loose clumps rather than as a spread of individuals
	# who happen to share a destination. It is the plainest kind in the game
	# and the one the player sees most, so what makes it distinctive has to be
	# something visible at a distance — and a drift of three or four bodies
	# moving together is legible from across a chamber in a way that any stat
	# on the sheet is not.
	if cohesion_count > 0:
		var centre: Vector3 = cohesion_sum / float(cohesion_count)
		var toward := centre - global_position
		toward.y = 0.0
		if toward.length_squared() > 0.0001:
			steering += toward.normalized() * move_speed * cohesion_strength

	return steering


## Wind up, commit, and land — or whiff — a bite.
##
## Returns true while an attack owns velocity, so _physics_process knows to
## skip the normal path-following steering for this frame.
##
## A straight cooldown-gated hit at range was an invisible damage tick: there
## was nothing to see or react to before it landed. Splitting it into a
## wind-up the zombie holds through, then a short lunge it cannot steer out
## of, turns the same damage into something the player can read coming and
## step away from — at the cost of the zombie being unable to correct if they
## do.
func _tick_attack(delta: float) -> bool:
	match _attack_state:
		AttackState.WINDING_UP:
			_hold_still_and_track(delta)
			_attack_state_remaining -= delta
			if _attack_state_remaining <= 0.0:
				_begin_lunge()
			return true

		AttackState.LUNGING:
			velocity.x = _lunge_direction.x * lunge_speed
			velocity.z = _lunge_direction.z * lunge_speed
			_try_land_hit()
			_attack_state_remaining -= delta
			if _attack_state_remaining <= 0.0:
				_attack_remaining = attack_cooldown
				if overrun_duration > 0.0:
					_attack_state = AttackState.OVERRUNNING
					_attack_state_remaining = overrun_duration
				else:
					_attack_state = AttackState.READY
			return true

		AttackState.OVERRUNNING:
			# Same direction, same commitment, no attack left in it. A Runner
			# that misses is briefly a projectile: it cannot steer, cannot
			# stop, and cannot bite. That window is the whole counterplay
			# against the fastest thing in the cave.
			velocity.x = _lunge_direction.x * lunge_speed
			velocity.z = _lunge_direction.z * lunge_speed
			_attack_state_remaining -= delta
			if _attack_state_remaining <= 0.0:
				_attack_state = AttackState.READY
			return true

		_:
			if _attack_remaining > 0.0:
				return false

			# A staggered zombie is not allowed to start a new wind-up, or
			# being shot would only ever reset the animation rather than
			# actually buy the player anything.
			if _stagger_remaining > 0.0:
				return false

			var distance := global_position.distance_to(_target.global_position)
			if distance > attack_range:
				return false

			_begin_windup()
			return true


func _begin_windup() -> void:
	_attack_state = AttackState.WINDING_UP
	_attack_state_remaining = attack_windup
	_attack_landed = false
	attack_telegraphed.emit(self, global_position)


func _begin_lunge() -> void:
	_attack_state = AttackState.LUNGING
	_attack_state_remaining = attack_commit_duration
	# Locked in at the moment the lunge starts. Committing to the direction
	# faced right now, rather than continuing to track the target, is what
	# makes stepping aside during the lunge actually work.
	_lunge_direction = facing()


func _hold_still_and_track(delta: float) -> void:
	_accelerate_toward(Vector3.ZERO, delta)

	if _target == null:
		return

	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= 0.01:
		return

	# Same sign convention as _move_toward_target: -Z is the front of a body.
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, turn_speed * _turn_scale * delta)


func _try_land_hit() -> void:
	# Guarded here as well as by the frozen physics frame. This is the one
	# place a zombie reaches out and touches the player, and it is worth being
	# unable to do so by more than one route: a hit that lands after the round
	# has ended is damage the player can neither see coming nor answer.
	if _attack_landed or _target == null or is_stopped:
		return

	if global_position.distance_to(_target.global_position) > attack_range:
		return

	_attack_landed = true
	hit_player.emit(contact_damage, global_position)

	if _target.has_method("take_damage"):
		_target.take_damage(contact_damage, global_position, Vector3.ZERO)


func _tick_groan(delta: float) -> void:
	if is_stopped:
		return

	_groan_remaining -= delta
	if _groan_remaining > 0.0:
		return

	_groan_remaining = randf_range(groan_interval.x, groan_interval.y)
	groaned.emit(global_position)

	# A zombie that has eyes on the player does not groan quietly to itself.
	# This is the third channel information travels down, after sight and
	# sound, and it is the one that makes a crowd behave like a crowd.
	# A Stalker's alarm_radius is zero, so it never does this. It is the only
	# thing in the cave that keeps what it knows to itself, and a chamber with
	# one in it is a chamber that sounds empty.
	if awareness == Awareness.HUNTING and alarm_radius > 0.0:
		raised_alarm.emit(self, last_known_position)


## Being shot tells a zombie a great deal, even if it never saw who did it.
func _on_damaged(_amount: float, _current: float, _maximum: float) -> void:
	_visual.flash()

	_stagger()

	if awareness != Awareness.HUNTING and _target != null:
		_believe(_target.global_position)


## Flinch, and drop whatever attack was being wound up.
##
## This is what makes shooting a zombie that is already on top of you worth
## doing even when the shot will not kill it: the hit buys the attack back.
## A Brute's zero-length stagger removes that answer entirely — you cannot
## shoot your way out of a Brute's wind-up, you have to move — and a kind that
## cannot be interrupted is a far more legible difference than any number on
## the stat sheet.
##
## A lunge already in flight is never interrupted, for anyone. Once a zombie
## has committed to a direction it is committed, which is the contract that
## makes stepping aside work.
func _stagger() -> void:
	if stagger_duration <= 0.0 or _attack_state == AttackState.LUNGING:
		return

	_stagger_remaining = stagger_duration

	# A hit knocks the breath out of it. The archetype table has claimed since
	# the Screamer landed that "any hit at all buys a pause in the screaming
	# even when it does not kill" — until the inhale existed there was nothing
	# for that to be true of. Now a single round that fails to kill still costs
	# the Screamer its whole wind-up and starts it again, which is what makes
	# shooting the weakest thing in the room worth a magazine.
	if _inhaling:
		_begin_inhale()

	if _attack_state == AttackState.WINDING_UP:
		_attack_state = AttackState.READY
		_attack_remaining = attack_cooldown


func _on_died() -> void:
	died.emit(self, global_position)

	# Hand the body off before the node goes, so the kill leaves something
	# behind without keeping a dead zombie in the alive list.
	_visual.detach_as_corpse(corpse_collapse_time)

	# Stop participating in the fight immediately; the node is freed by the
	# spawner after the death signal is handled.
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	queue_free()
