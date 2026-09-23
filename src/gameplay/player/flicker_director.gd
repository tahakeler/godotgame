class_name FlickerDirector
extends Node

## Decides when the torch stutters, and never says why.
##
## Two triggers feed the same flicker() call on the same flashlight, and
## deliberately produce output nothing downstream can tell apart:
##
##   - near: a real hunter is close. The torch is genuinely reacting to
##     something, the way a game about scarcity and sight lines should let it.
##   - calm: nothing is wrong at all. The torch stutters anyway, on a slow
##     random roll that has nothing to do with the spawner.
##
## The point is that the player can never learn which one just happened. A
## flicker that only ever meant danger would become a second threat meter —
## strictly more useful than the torch's actual job of lighting the corridor,
## and the fastest way to turn paranoia into a reliable instrument. A flicker
## that only ever meant nothing would just be a tic, forgettable inside a
## minute. Held together, every stutter is a live question the game refuses
## to answer: something is close, or nothing is, and the only way to find out
## is to stop looking at the light and look at the room.
##
## Reads ZombieSpawner.nearest_hunter_distance() and Ambience's threat figure;
## never touches either. Writes only to Flashlight.flicker(), and only asks
## — it does not know or care whether the flashlight grants the request.

@export_group("Near")
## How close a hunting zombie has to be, in metres, before a flicker is
## eligible to read as "something is right there."
@export var near_distance := 9.0
## Chance per second of eligibility that a flicker actually starts. Rolled
## once per full second of eligibility, the same way DreadDirector rolls for
## a phantom — see _tick_near below.
@export var near_chance := 0.35
## Minimum seconds between the end of one near-triggered flicker and the next
## roll being eligible at all, regardless of how close the hunter stays.
@export var near_cooldown := 6.0
@export var near_duration_min := 0.35
@export var near_duration_max := 0.7

@export_group("Calm")
## Below this threat, the torch is allowed to stutter for no reason.
@export var calm_threat_threshold := 0.12
## Chance per second of eligibility. Deliberately much rarer than near_chance
## — a calm flicker is the seasoning, not the dish. Too frequent and the
## player correctly learns to ignore every flicker outright, which is the one
## outcome that defeats the whole system.
@export var calm_chance := 0.012
@export var calm_cooldown := 40.0
@export var calm_duration_min := 0.2
@export var calm_duration_max := 0.45

var _flashlight: Flashlight
var _spawner: ZombieSpawner
var _player: Node3D

var _rng := RandomNumberGenerator.new()

var _near_time_since_last := 0.0
var _near_roll_accum := 0.0

var _calm_time_since_last := 0.0
var _calm_roll_accum := 0.0


func _ready() -> void:
	_rng.randomize()


## Wire the director to the systems it reads and the torch it plays into.
## Called once by Game; nothing here is created in _ready because the
## flashlight and player belong to the Player scene and are not guaranteed to
## exist yet.
func bind(flashlight: Flashlight, spawner: ZombieSpawner, player: Node3D) -> void:
	_flashlight = flashlight
	_spawner = spawner
	_player = player


## Return every clock to its opening state for a fresh round. Both
## time-since-last clocks start at their cooldown value so eligibility is
## already satisfied at t=0 — only the trigger's own condition (distance or
## threat) should gate the very first flicker of a round.
func reset() -> void:
	_near_time_since_last = near_cooldown
	_near_roll_accum = 0.0
	_calm_time_since_last = calm_cooldown
	_calm_roll_accum = 0.0


## Swap in a seeded RNG for deterministic tests.
func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Advance both clocks and, if either is due, ask the flashlight to flicker.
## Called by Game every frame the round is PLAYING, fed the same smoothed
## threat figure the HUD and DreadDirector read.
func tick(delta: float, threat: float) -> void:
	if _flashlight == null or _spawner == null or _player == null:
		return

	_near_time_since_last += delta
	_calm_time_since_last += delta

	# Never stack a second roll on top of a flicker already playing, and never
	# ask an unlit torch to do anything — flicker() would refuse anyway, but
	# rolling for it would burn a roll the calm case is tuned to expect.
	if not _flashlight.is_on or _flashlight.is_flickering():
		return

	if _tick_near(delta):
		return
	_tick_calm(delta, threat)


## True proximity to a real hunter. Rolled once per whole second of
## eligibility, the same accumulator shape DreadDirector uses for its phantom
## roll — a probability that means what its @export says regardless of frame
## rate, rather than a per-frame chance that would fire more often at 144fps
## than at 60.
func _tick_near(delta: float) -> bool:
	if _near_time_since_last < near_cooldown:
		return false

	if _spawner.nearest_hunter_distance(_player.global_position) >= near_distance:
		return false

	_near_roll_accum += delta
	while _near_roll_accum >= 1.0:
		_near_roll_accum -= 1.0
		if _rng.randf() < near_chance:
			_trigger_near()
			return true

	return false


## No danger at all — the quiet the near trigger never sees.
func _tick_calm(delta: float, threat: float) -> void:
	if _calm_time_since_last < calm_cooldown:
		return

	if threat >= calm_threat_threshold:
		return

	_calm_roll_accum += delta
	while _calm_roll_accum >= 1.0:
		_calm_roll_accum -= 1.0
		if _rng.randf() < calm_chance:
			_trigger_calm()
			return


func _trigger_near() -> void:
	_flashlight.flicker(_rng.randf_range(near_duration_min, near_duration_max), _rng)
	_near_time_since_last = 0.0


func _trigger_calm() -> void:
	_flashlight.flicker(_rng.randf_range(calm_duration_min, calm_duration_max), _rng)
	_calm_time_since_last = 0.0
