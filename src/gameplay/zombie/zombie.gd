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

## Deliberately faint. Emission adds on top of the skin, so anything stronger
## floods the whole body and flattens a zombie into a glowing silhouette —
## losing the character entirely and costing more atmosphere than the clarity
## is worth. These read at corridor distance against an unlit wall and are
## barely noticeable up close, which is the right way round: up close you can
## already see what it is doing.
const INVESTIGATING_GLOW_ENERGY := 0.09
const HUNTING_GLOW_ENERGY := 0.32

var base_attack_range := 1.9

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
	if health.is_dead or awareness == Awareness.HUNTING:
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
			_visual.apply_glow(HUNTING_GLOW, HUNTING_GLOW_ENERGY)
		Awareness.INVESTIGATING:
			_visual.apply_glow(INVESTIGATING_GLOW, INVESTIGATING_GLOW_ENERGY)
		_:
			_visual.apply_glow(Color.BLACK, 0.0)


## Adopt a belief about where the player is, and go and look.
func _believe(where: Vector3) -> void:
	last_known_position = where
	_investigate_remaining = investigate_duration
	_search_remaining = 0.0
	_set_awareness(Awareness.INVESTIGATING)


## Told by another zombie. Alerts spread through a crowd, which is what turns
## one noticed gunshot into a chamber emptying toward you rather than a single
## zombie taking an interest.
func receive_alert(where: Vector3) -> void:
	if health.is_dead or awareness == Awareness.HUNTING:
		return

	_believe(where)


func is_investigating() -> bool:
	return awareness == Awareness.INVESTIGATING


func is_hunting() -> bool:
	return awareness == Awareness.HUNTING


## Where this zombie is currently trying to get to.
##
## Hunting tracks the player live; everything else walks to a belief, which may
## be wrong and usually is by the time it arrives.
func _move_goal() -> Vector3:
	if awareness == Awareness.HUNTING and _target != null:
		return _target.global_position

	return last_known_position


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
		_set_awareness(Awareness.HUNTING)
		last_known_position = _target.global_position
		_lost_sight_remaining = lose_sight_duration
		return

	# Sight is not lost the instant the line breaks. A zombie that forgot you
	# the moment you stepped behind a rock would be trivial to shake off, and
	# would read as stupid rather than as something you outmanoeuvred.
	if awareness == Awareness.HUNTING:
		_lost_sight_remaining -= sight_interval
		if _lost_sight_remaining <= 0.0:
			_believe(last_known_position)


func _can_see_target() -> bool:
	if _target == null:
		return false

	var to_target := _target.global_position - global_position
	var distance := to_target.length()

	if distance > sight_range:
		return false

	# Behind counts as unseen, so breaking line of sight by getting behind one
	# actually works.
	var facing := -global_transform.basis.z
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
	if awareness != Awareness.INVESTIGATING:
		return

	if _search_remaining > 0.0:
		_search_remaining -= delta
		if _search_remaining <= 0.0:
			_set_awareness(Awareness.UNAWARE)
		return

	_investigate_remaining -= delta

	# Arrived, and nothing here. Cast about nearby before losing interest — a
	# zombie that snaps from "hunting" to "idle" on the spot reads as a switch
	# being flipped.
	if global_position.distance_to(last_known_position) <= ARRIVAL_DISTANCE:
		_begin_search()
		return

	if _investigate_remaining <= 0.0:
		_begin_search()


func _begin_search() -> void:
	_search_remaining = search_duration
	last_known_position = global_position + Vector3(
		randf_range(-search_radius, search_radius),
		0.0,
		randf_range(-search_radius, search_radius)
	)


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
	var desired_yaw := atan2(desired_velocity.x, desired_velocity.z)
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
func _compute_separation() -> Vector3:
	var push := Vector3.ZERO
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

		if distance >= combined_radius or distance < 0.001:
			continue

		# Push harder the more two bodies overlap, so a graze is a nudge and a
		# dead-on stack is a shove.
		var overlap := (combined_radius - distance) / combined_radius
		push += (offset / distance) * overlap

	if push.length_squared() > 1.0:
		push = push.normalized()

	return push * move_speed * separation_strength


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
				_attack_state = AttackState.READY
				_attack_remaining = attack_cooldown
			return true

		_:
			if _attack_remaining > 0.0:
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
	_lunge_direction = -global_transform.basis.z


func _hold_still_and_track(delta: float) -> void:
	_accelerate_toward(Vector3.ZERO, delta)

	if _target == null:
		return

	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= 0.01:
		return

	var desired_yaw := atan2(to_target.x, to_target.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, turn_speed * _turn_scale * delta)


func _try_land_hit() -> void:
	if _attack_landed or _target == null:
		return

	if global_position.distance_to(_target.global_position) > attack_range:
		return

	_attack_landed = true
	hit_player.emit(contact_damage, global_position)

	if _target.has_method("take_damage"):
		_target.take_damage(contact_damage, global_position, Vector3.ZERO)


func _tick_groan(delta: float) -> void:
	_groan_remaining -= delta
	if _groan_remaining > 0.0:
		return

	_groan_remaining = randf_range(groan_interval.x, groan_interval.y)
	groaned.emit(global_position)

	# A zombie that has eyes on the player does not groan quietly to itself.
	# This is the third channel information travels down, after sight and
	# sound, and it is the one that makes a crowd behave like a crowd.
	if awareness == Awareness.HUNTING:
		raised_alarm.emit(self, last_known_position)


## Being shot tells a zombie a great deal, even if it never saw who did it.
func _on_damaged(_amount: float, _current: float, _maximum: float) -> void:
	_visual.flash()

	if awareness != Awareness.HUNTING and _target != null:
		_believe(_target.global_position)


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
