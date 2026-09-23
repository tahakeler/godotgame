class_name Flashlight
extends SpotLight3D

## The player's torch.
##
## Parented to the camera so it points wherever the player looks — a torch that
## lagged behind the aim would be worse than none, because the thing you are
## trying to see is always the thing you are pointing at.
##
## Deliberately narrow and not very bright. The cave's per-chamber lighting is
## the atmosphere, and a wide floodlight would erase it: every chamber would
## read the same and the dark stretches that make a corridor feel long would
## stop existing. This is a tool for resolving what is in front of you, not for
## turning the lights on.
##
## No battery. The brief left it to judgement, and a drain timer here would
## tax the player for looking at things in a game already built on scarcity —
## ammunition is the resource this game is about, and a second meter competing
## with it would dilute that rather than deepen it. Turning the torch off has
## a real cost already: this game's enemies find you by sight and sound, and
## the light is the loudest thing you own that is not a gun.

signal toggled(is_on: bool)

@export_group("Beam")
## Tight enough to be a tool rather than a floodlight.
@export var cone_angle_degrees := 26.0
## How soft the edge of the cone is. A hard edge reads as a projected circle.
@export var cone_softness := 0.4
@export var beam_range := 24.0
@export var beam_energy := 2.4
## Above 1.0 the beam falls off faster than physically correct, which keeps the
## far end of a corridor dark instead of flatly lit.
@export var beam_attenuation := 1.6

@export_group("Cost")
## Shadows are off by default. A shadow-casting spotlight is one of the most
## expensive things a scene can have, and this project already sits close to
## its frame budget. Exposed so it can be turned on where there is headroom.
@export var cast_shadows := false

## How much easier a lit player is to see, as a multiplier on a zombie's sight
## range while the torch is on.
##
## This is the tradeoff the class comment above promises but the game does not
## yet actually charge. A torch is currently free: the beam is the only thing
## in the cave that announces your position at the speed of light, and nothing
## reads it. Exposing it here, with `visibility_scale()` below, puts the
## player's half of that bargain in place.
##
## The other half is one line in zombie.gd's `_can_see_target()` — see the
## note on `visibility_scale()`. It is not written here because that file
## belongs to the AI work in flight.
##
## 1.45 rather than something dramatic: the torch must remain worth carrying.
## At a 20m sight range this turns a zombie that notices you at 20m into one
## that notices you at 29m, which is roughly the difference between meeting it
## in the next chamber and meeting it in this one.
@export var lit_visibility_scale := 1.45

@export_group("Flicker")
## Darkest and brightest fraction of beam_energy a flicker step can land on.
## The low end is not 0 on principle — a torch that fully cuts out reads as a
## different mechanic (the light failing) than the one intended here (the
## light stuttering).
@export var flicker_min_scale := 0.05
@export var flicker_max_scale := 0.35
## Seconds between one stutter step and the next. Randomised per step so the
## pattern does not read as a metronome, which would make it identifiable —
## and identifiable is the one thing this effect must never become. See
## flicker_director.gd for why.
@export var flicker_step_min := 0.03
@export var flicker_step_max := 0.09

var is_on := false

## Seconds remaining in the current flicker; 0 when not flickering.
var _flicker_time_left := 0.0
var _flicker_step_timer := 0.0
var _flicker_dark := false
var _flicker_rng: RandomNumberGenerator


func _ready() -> void:
	spot_angle = cone_angle_degrees
	spot_angle_attenuation = cone_softness
	spot_range = beam_range
	spot_attenuation = beam_attenuation
	light_energy = beam_energy
	shadow_enabled = cast_shadows

	# Starts off so the player meets the cave as it was lit, and turning the
	# torch on is their first discovery rather than the default state.
	_apply()


## Flip the torch. Returns the new state.
func toggle() -> bool:
	is_on = not is_on
	_apply()
	toggled.emit(is_on)
	return is_on


func set_on(on: bool) -> void:
	if on == is_on:
		return

	is_on = on
	_apply()
	toggled.emit(is_on)


## How visible the torch is currently making its carrier. 1.0 when it is off.
##
## Read by anything that hunts by sight. The intended consumer is zombie.gd,
## which should scale its own `sight_range` by the target's visibility before
## the distance test in `_can_see_target()`:
##
##     var reach := sight_range
##     if _target != null and _target.has_method("visibility_scale"):
##         reach *= _target.visibility_scale()
##     if distance > reach:
##         return false
##
## Deliberately a pull, not a push: the light does not reach into the AI and
## edit anyone's stats, which would fight the tuning values in the inspector
## and leave a zombie permanently buffed if the player died mid-beam. The
## zombie asks, every time it looks, and the answer is always current.
func visibility_scale() -> float:
	return lit_visibility_scale if is_on else 1.0


## Stutter the beam for `duration` seconds, then restore it exactly.
##
## Called by flicker_director.gd, never on its own timer — this method knows
## only how to flicker, not when. Whether a given flicker means a hunter is
## close or means nothing at all lives entirely in the caller; this function
## must not leak that distinction; a `near` flicker and a `calm` flicker have
## to be indistinguishable from in here, or the paranoia the director is
## built for falls apart the first time a player learns to tell them apart.
##
## Does nothing if the torch is off — a flicker on a light that is not lit
## would be a state change nobody asked for and nothing sees.
##
## light_energy only; visibility_scale() reads is_on, not light_energy, so a
## flicker never touches how far a zombie can see the player. The torch looks
## like it is failing; the game does not treat it as failing.
func flicker(duration: float, rng: RandomNumberGenerator = null) -> void:
	if not is_on:
		return

	_flicker_rng = rng
	if _flicker_rng == null:
		_flicker_rng = RandomNumberGenerator.new()
		_flicker_rng.randomize()

	_flicker_time_left = duration
	_flicker_step_timer = 0.0
	_flicker_dark = false


func is_flickering() -> bool:
	return _flicker_time_left > 0.0


func _process(delta: float) -> void:
	if _flicker_time_left <= 0.0:
		return

	_flicker_time_left -= delta
	if _flicker_time_left <= 0.0:
		_end_flicker()
		return

	_flicker_step_timer -= delta
	if _flicker_step_timer > 0.0:
		return

	_flicker_dark = not _flicker_dark
	if _flicker_dark:
		var scale := _flicker_rng.randf_range(flicker_min_scale, flicker_max_scale)
		light_energy = scale * beam_energy
	else:
		light_energy = beam_energy

	_flicker_step_timer = _flicker_rng.randf_range(flicker_step_min, flicker_step_max)


func _end_flicker() -> void:
	_flicker_time_left = 0.0
	_flicker_step_timer = 0.0
	light_energy = beam_energy


func _apply() -> void:
	visible = is_on

	# Toggling off mid-flicker ends it outright rather than letting it play out
	# unseen — a flicker that finished after the torch was already dark would
	# restore light_energy on a light nobody can see change, and the next
	# toggle-on would inherit whatever stray value was left mid-stutter.
	if not is_on and _flicker_time_left > 0.0:
		_end_flicker()
