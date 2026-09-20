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

var is_on := false


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


func _apply() -> void:
	visible = is_on
