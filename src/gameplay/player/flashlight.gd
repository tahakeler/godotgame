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


func _apply() -> void:
	visible = is_on
