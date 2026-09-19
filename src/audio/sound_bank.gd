class_name SoundBank
extends Node

## Central sound playback. Gameplay code never touches an AudioStreamPlayer —
## it emits signals, Game routes them here by event name, so audio stays out of
## the systems it reports on.
##
## All clips are from the Kenney RPG Audio pack (CC0). That pack has no firearm
## sound, so "fire" uses a percussive clip pitched down; it reads as a shot in
## context but is the one event without a purpose-made source.

const BASE := "res://assets/audio/%s.ogg"

## event name -> clip names. Multiple entries are chosen at random so repeated
## events do not sound mechanical.
const EVENTS := {
	"fire": ["chop"],
	"dry_fire": ["metalClick"],
	"reload_start": ["beltHandle1"],
	"reload_end": ["metalLatch"],
	"zombie_hit": ["knifeSlice"],
	"zombie_death": ["cloth3"],
	"zombie_groan": ["creak1", "creak2", "creak3"],
	"player_hurt": ["cloth1"],
	"ammo_gained": ["handleCoins"],
	"footstep": ["footstep00", "footstep01", "footstep02", "footstep03", "footstep04"],
	"round_won": ["doorOpen_1"],
	"round_lost": ["bookClose"],
}

## Per-event volume in dB and pitch range, so one pack of generic clips can
## carry very different weights.
const MIX := {
	"fire": {"volume": -4.0, "pitch": Vector2(0.62, 0.72)},
	"dry_fire": {"volume": -6.0, "pitch": Vector2(1.0, 1.08)},
	"reload_start": {"volume": -8.0, "pitch": Vector2(0.9, 1.0)},
	"reload_end": {"volume": -7.0, "pitch": Vector2(0.95, 1.05)},
	"zombie_hit": {"volume": -9.0, "pitch": Vector2(0.8, 0.95)},
	"zombie_death": {"volume": -6.0, "pitch": Vector2(0.65, 0.8)},
	"zombie_groan": {"volume": -12.0, "pitch": Vector2(0.55, 0.7)},
	"player_hurt": {"volume": -2.0, "pitch": Vector2(0.7, 0.85)},
	"ammo_gained": {"volume": -14.0, "pitch": Vector2(1.1, 1.25)},
	"footstep": {"volume": -18.0, "pitch": Vector2(0.9, 1.15)},
	"round_won": {"volume": -3.0, "pitch": Vector2(0.9, 1.0)},
	"round_lost": {"volume": -3.0, "pitch": Vector2(0.7, 0.8)},
}

## Non-positional voices, reused round-robin. Sized for the loudest moment —
## a full magazine emptied into a crowd — so shots never cut each other off.
@export var voice_count := 12
@export var max_3d_distance := 28.0

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_preload_streams()

	for i in voice_count:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)


## Release every stream reference on the way out. Voices and one-shot 3D
## players hold their streams until playback ends, so a scene torn down
## mid-sound leaves those OGGs referenced and the engine reports them as
## resources still in use at exit.
func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null

	_voices.clear()
	_streams.clear()


## Play an event without a position — the player's own weapon and UI.
func play(event: String) -> void:
	var stream := _pick(event)
	if stream == null:
		return

	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()

	var mix: Dictionary = MIX.get(event, {})
	voice.stream = stream
	voice.volume_db = mix.get("volume", -6.0)
	voice.pitch_scale = _pitch_for(mix)
	voice.play()


## Play an event at a world position, so the player can hear where it happened.
func play_at(event: String, position: Vector3) -> void:
	var stream := _pick(event)
	if stream == null:
		return

	var player := AudioStreamPlayer3D.new()
	add_child(player)

	var mix: Dictionary = MIX.get(event, {})
	player.stream = stream
	player.volume_db = mix.get("volume", -6.0)
	player.pitch_scale = _pitch_for(mix)
	player.max_distance = max_3d_distance
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


func _pitch_for(mix: Dictionary) -> float:
	var range_value: Vector2 = mix.get("pitch", Vector2(1.0, 1.0))
	return _rng.randf_range(range_value.x, range_value.y)


func _pick(event: String) -> AudioStream:
	var clips: Array = _streams.get(event, [])
	if clips.is_empty():
		return null
	return clips[_rng.randi_range(0, clips.size() - 1)]


func _preload_streams() -> void:
	for event in EVENTS:
		var loaded: Array[AudioStream] = []

		for clip_name in EVENTS[event]:
			var stream: AudioStream = load(BASE % clip_name)
			if stream != null:
				loaded.append(stream)

		_streams[event] = loaded
