class_name LightFlicker
extends Node

## Wobbles a light's energy so lit rooms feel alive rather than painted.
##
## Two sine waves at unrelated frequencies rather than random noise: noise
## reads as a fault in the light, while a slow irregular breath reads as fire.
## Each light gets its own phase, otherwise the whole cave pulses in unison and
## the effect announces itself immediately.

@export var amplitude := 0.14
@export var slow_speed := 1.7
@export var fast_speed := 4.3

var _light: OmniLight3D
var _base_energy := 0.0
var _phase := 0.0


func setup(light: OmniLight3D, phase: float) -> void:
	_light = light
	_base_energy = light.light_energy
	_phase = phase


func _process(delta: float) -> void:
	if _light == null:
		return

	_phase += delta

	var wobble := (
		sin(_phase * slow_speed) * 0.65
		+ sin(_phase * fast_speed) * 0.35
	)
	_light.light_energy = _base_energy * (1.0 + wobble * amplitude)
