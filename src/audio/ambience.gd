class_name Ambience
extends Node

## The sound of the cave, and the sound of the cave coming for you.
##
## Two looping layers. The bed is always there and does not change — a space
## with no ambient sound reads as unfinished no matter how it looks, because
## silence is something rooms do not do. The pulse fades in with danger.
##
## The pulse carries no information the HUD does not already have. It exists so
## that the moment several things start hunting you is *felt* a beat before it
## is read, which is the difference between a game that tells you you are in
## trouble and one where you notice.
##
## Threat is smoothed on the way in. The raw figure moves the instant a zombie
## loses or regains sight of you, and a mix that jumped with it would pump
## audibly on every flicker — the listener hears the seams of the system rather
## than the tension it is modelling.

const AMBIENCE_STREAM := "res://assets/audio/generated/cave_ambience.wav"
const PULSE_STREAM := "res://assets/audio/generated/tension_pulse.wav"

## Bed volume in dB. Well under everything else: it should be noticed only when
## it stops.
@export var bed_volume_db := -22.0
## Pulse volume at full threat.
@export var pulse_volume_db := -12.0
## Below this threat the pulse is silent rather than merely quiet, so a single
## distant hunter does not start a heartbeat.
@export var pulse_threshold := 0.18
## How fast the mix chases the real threat level, per second.
@export var smoothing := 1.6

var _threat := 0.0
var _bed: AudioStreamPlayer
var _pulse: AudioStreamPlayer


func _ready() -> void:
	_bed = _build_layer(AMBIENCE_STREAM, bed_volume_db)
	_pulse = _build_layer(PULSE_STREAM, linear_to_db(0.0001))


## Feed the current danger in. Called every frame by Game.
func set_threat(target: float, delta: float) -> void:
	_threat = move_toward(_threat, clampf(target, 0.0, 1.0), smoothing * delta)
	_apply()


## The smoothed figure, which is what the mix and the vignette both read.
func threat() -> float:
	return _threat


func _apply() -> void:
	if _pulse == null:
		return

	if _threat <= pulse_threshold:
		_pulse.volume_db = linear_to_db(0.0001)
		return

	# Rescaled above the threshold so the pulse comes in from nothing rather
	# than snapping to an audible level the moment it crosses.
	var strength := inverse_lerp(pulse_threshold, 1.0, _threat)
	_pulse.volume_db = linear_to_db(maxf(strength, 0.0001)) + pulse_volume_db


func _build_layer(path: String, volume_db: float) -> AudioStreamPlayer:
	var stream: AudioStream = load(path)
	if stream == null:
		push_error("Ambience: could not load %s" % path)
		return null

	# Looping is set here rather than baked into the file. save_to_wav does not
	# write loop metadata, so a stream loaded straight off disk plays once and
	# stops — which would look exactly like the ambience system doing nothing.
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = 0

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.autoplay = false
	add_child(player)
	player.play()

	return player
