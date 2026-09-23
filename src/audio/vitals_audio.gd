class_name VitalsAudio
extends Node

## The world goes muffled, and the player's own heartbeat takes over.
##
## A classic AAA low-health cue. Below a health fraction, the SFX bus loses
## its top end — routed through GameSettings.set_sfx_muffle(), the same
## bus/filter pair Ambience and every gunshot already play through — while a
## heartbeat, deliberately NOT muffled, gets louder and faster the closer
## death gets. Health is the only input: nothing here reads damage sources,
## zombie state, or combat directly, so the cue works for any way the player
## ends up hurt without this file knowing what hit them.
##
## Game wires `player.health.changed` straight into `set_health()`, calls
## `tick()` every frame alongside its other per-frame systems, and calls
## `reset()` on round start and on player death — so the main menu and the
## results screen are never left muffled or thumping.

## The heartbeat one-shot. ~1.8 s; retriggered on its own schedule rather than
## looped, so a health change mid-beat is heard on the very next trigger.
const HEARTBEAT_STREAM := "res://assets/audio/sourced/oneshots/heartbeat_slow_01.wav"

## Health fraction below which the cue engages at all.
@export var low_health_fraction := 0.35
## How fast the muffle chases its target, in muffle-units (0..1) per second.
@export var muffle_rate := 1.5
## Seconds between heartbeats right at the threshold (barely triggered).
@export var beat_interval_high := 1.6
## Seconds between heartbeats at 0 health (as fast as the cue gets).
@export var beat_interval_low := 0.75
## Heartbeat volume right at the threshold.
@export var beat_volume_low_db := -18.0
## Heartbeat volume at 0 health.
@export var beat_volume_high_db := -6.0

var _fraction := 1.0
var _muffle := 0.0
## The last value actually pushed to GameSettings, so small per-frame ramp
## steps don't each fire an AudioServer call — only the accumulated change
## crossing the 0.01 mark does.
var _reported_muffle := 0.0
var _beat_timer := 0.0
var _beat_player: AudioStreamPlayer

## Exposed for tests: counts every heartbeat retrigger since the last reset().
var beats_played := 0


func _ready() -> void:
	var stream: AudioStream = load(HEARTBEAT_STREAM)
	if stream == null:
		push_warning("VitalsAudio: could not load %s" % HEARTBEAT_STREAM)

	_beat_player = AudioStreamPlayer.new()
	# Deliberately the Master bus, not SFX: the same low-health state that
	# muffles the SFX bus must not muffle the sound telling the player they
	# are low on health, or the cue would duck the one thing it exists to
	# deliver clearly.
	_beat_player.bus = "Master"
	_beat_player.stream = stream
	add_child(_beat_player)


## Fed from player.health.changed. Stores the fraction only — the audio
## response happens on the next tick(), so a burst of damage within one frame
## does not fire multiple retriggers.
func set_health(current: float, maximum: float) -> void:
	_fraction = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)


## Called every frame by Game. Ramps the world muffle and, while badly hurt,
## retriggers the heartbeat on its own escalating schedule.
func tick(delta: float) -> void:
	var below := _fraction < low_health_fraction
	var severity := 0.0
	if below:
		severity = clampf(inverse_lerp(low_health_fraction, 0.0, _fraction), 0.0, 1.0)

	_muffle = move_toward(_muffle, severity, muffle_rate * delta)
	if absf(_muffle - _reported_muffle) > 0.01:
		_reported_muffle = _muffle
		GameSettings.set_sfx_muffle(_muffle)

	if not below:
		# Above the threshold, the beat schedule is not merely paused — it is
		# cleared, so a second dip below the threshold always opens with an
		# immediate beat rather than the tail end of a stale countdown.
		_beat_timer = 0.0
		return

	_beat_timer -= delta
	if _beat_timer > 0.0:
		return

	_trigger_beat(severity)
	_beat_timer = lerp(beat_interval_high, beat_interval_low, severity)


func _trigger_beat(severity: float) -> void:
	beats_played += 1
	if _beat_player.stream == null:
		return

	_beat_player.volume_db = lerp(beat_volume_low_db, beat_volume_high_db, severity)
	_beat_player.play()


## Round start and player death both call this: clears the muffle and the
## beat immediately (not next tick), so neither carries into the main menu or
## the results screen.
func reset() -> void:
	_fraction = 1.0
	_muffle = 0.0
	_reported_muffle = 0.0
	_beat_timer = 0.0
	beats_played = 0
	GameSettings.set_sfx_muffle(0.0)
	if _beat_player != null:
		_beat_player.stop()
