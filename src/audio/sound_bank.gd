class_name SoundBank
extends Node

## Central sound playback. Gameplay code never touches an AudioStreamPlayer —
## it emits signals, Game routes them here by event name, so audio stays out of
## the systems it reports on.
##
## Most clips are from the Kenney RPG Audio pack (CC0). Firing and the Brute
## growl are synthesised instead (tools/generate_audio.gd), because that pack
## has no firearm and no sound low enough to mark a Brute — and a shot is what
## the player hears most in this game.

const BASE := "res://assets/audio/%s.ogg"
const GENERATED := "res://assets/audio/generated/%s.wav"

## Events whose clips are synthesised rather than from the Kenney pack.
const GENERATED_EVENTS := {
	"fire": ["gunshot"],
	"fire_pistol": ["fire_pistol"],
	"fire_shotgun": ["fire_shotgun"],
	"fire_rifle": ["fire_rifle"],
	"screamer_inhale": ["screamer_inhale"],
	"screamer_alarm": ["screamer_alarm"],
	"brute_growl": ["brute_growl"],
	"decoy_land": ["decoy_land"],
	"zombie_alerted": ["zombie_alerted"],
}

## event name -> clip names. Multiple entries are chosen at random so repeated
## events do not sound mechanical.
const EVENTS := {
	"dry_fire": ["metalClick"],
	"reload_start": ["beltHandle1"],
	"reload_end": ["metalLatch"],
	"zombie_hit": ["knifeSlice"],
	# The emergency swing. Two events rather than one, because the only thing
	# the player needs to know in the moment they are swinging is whether it
	# landed — a hit and a whiff that sound alike make a last resort feel like
	# it is not responding.
	"melee_swing": ["cloth3"],
	"melee_hit": ["chop"],
	# Layered over melee_hit when the thing struck cannot be staggered. Dead and
	# heavy: the sound of a blow being absorbed rather than landing.
	"melee_unmoved": ["bookClose"],
	"zombie_death": ["cloth3"],
	"zombie_groan": ["creak1", "creak2", "creak3"],
	"player_hurt": ["cloth1"],
	"ammo_gained": ["handleCoins"],
	"footstep": ["footstep00", "footstep01", "footstep02", "footstep03", "footstep04"],
	# The same five clips as a walk. Stance is expressed entirely in the mix
	# below — louder and faster-pitched for a sprint, near-silent and dragged
	# for a crouch — because the difference the player needs to hear is how
	# much noise they are spending, not what their boots are made of.
	"footstep_sprint": [
		"footstep00", "footstep01", "footstep02", "footstep03", "footstep04"
	],
	"footstep_crouch": [
		"footstep00", "footstep01", "footstep02", "footstep03", "footstep04"
	],
	# Swapping weapons costs real time, and time the player cannot shoot in has
	# to be audible or the wait reads as input lag.
	"weapon_switch": ["beltHandle1", "metalLatch"],
	# Working a crate open. Distinct from the coin-rattle of ammunition landing
	# in the reserve, which plays immediately afterwards.
	"cache_resupply": ["chop"],
	# Two seconds of standing still, ending in cloth and a latch.
	"medkit_used": ["cloth1"],
	"round_won": ["doorOpen_1"],
	"round_lost": ["bookClose"],
}

## Per-event volume in dB and pitch range, so one pack of generic clips can
## carry very different weights.
## An optional "distance" key overrides max_3d_distance for that event alone.
## Most things should fade out at the same range so the mix stays honest about
## how far away the cave is; the exceptions are the sounds whose whole purpose
## is to reach you from further than you can see.
const MIX := {
	"fire": {"volume": -5.0, "pitch": Vector2(0.94, 1.06)},
	# The three weapons, mixed in the order their noise_loudness puts them, so
	# what the player hears matches what the zombies heard. Shotgun 2.2, rifle
	# 1.35, pistol 0.85 — and the rifle's true loudness is cumulative, eleven
	# shots a second, which is why it sits only just above the pistol per shot
	# and still dominates the moment it is held down.
	"fire_pistol": {"volume": -6.5, "pitch": Vector2(0.96, 1.05)},
	"fire_shotgun": {"volume": -2.0, "pitch": Vector2(0.97, 1.03)},
	"fire_rifle": {"volume": -6.0, "pitch": Vector2(0.97, 1.04)},
	# The loudest event in the game, and the only one allowed to out-reach the
	# 36m it recruits from — you must be able to hear it from outside the circle
	# it is drawing, or the warning arrives after the consequence. Its pitch
	# range is deliberately narrow: this is a siren, and a siren that changes
	# note between instances is harder to learn.
	# The warning, mixed to be heard from outside the room it is in. Quieter
	# than the scream it resolves into and reaching slightly less far, so the
	# pair reads as one event getting closer to happening rather than two.
	# Pitch is barely varied: this is the one sound the player must recognise
	# instantly every single time, and variation is the enemy of recognition.
	"screamer_inhale": {
		"volume": -7.0, "pitch": Vector2(0.99, 1.01), "distance": 40.0
	},
	"screamer_alarm": {
		"volume": -1.0, "pitch": Vector2(0.97, 1.04), "distance": 46.0
	},
	"brute_growl": {"volume": -4.0, "pitch": Vector2(0.9, 1.05)},
	"decoy_land": {"volume": -7.0, "pitch": Vector2(0.92, 1.12)},
	"zombie_alerted": {"volume": -3.0, "pitch": Vector2(0.9, 1.1)},
	"dry_fire": {"volume": -6.0, "pitch": Vector2(1.0, 1.08)},
	"reload_start": {"volume": -8.0, "pitch": Vector2(0.9, 1.0)},
	"reload_end": {"volume": -7.0, "pitch": Vector2(0.95, 1.05)},
	"zombie_hit": {"volume": -9.0, "pitch": Vector2(0.8, 0.95)},
	# A whiff is quiet and breathy; a connection is a wet, low thud. The gap
	# between the two mixes is doing the work the two clips cannot.
	"melee_swing": {"volume": -13.0, "pitch": Vector2(1.15, 1.3)},
	"melee_hit": {"volume": -6.0, "pitch": Vector2(0.75, 0.9)},
	"melee_unmoved": {"volume": -4.0, "pitch": Vector2(0.55, 0.65)},
	"zombie_death": {"volume": -6.0, "pitch": Vector2(0.65, 0.8)},
	"zombie_groan": {"volume": -12.0, "pitch": Vector2(0.55, 0.7)},
	"player_hurt": {"volume": -2.0, "pitch": Vector2(0.7, 0.85)},
	"ammo_gained": {"volume": -14.0, "pitch": Vector2(1.1, 1.25)},
	"footstep": {"volume": -18.0, "pitch": Vector2(0.9, 1.15)},
	# Six dB above a walk and pitched up: a sprint should sound like spending
	# something, because it is.
	"footstep_sprint": {"volume": -12.0, "pitch": Vector2(1.0, 1.25)},
	# Twelve below a walk and dragged down. Near the floor of audibility on
	# purpose — a crouch buys silence, and the player should hear that it did.
	"footstep_crouch": {"volume": -30.0, "pitch": Vector2(0.72, 0.86)},
	"weapon_switch": {"volume": -9.0, "pitch": Vector2(0.86, 0.96)},
	"cache_resupply": {"volume": -11.0, "pitch": Vector2(0.8, 0.92)},
	"medkit_used": {"volume": -7.0, "pitch": Vector2(0.9, 1.0)},
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

	# Every effect rides the SFX bus so the effects slider has something to
	# move. The buses are created here as well as by GameSettings, because a
	# tool that boots this scene without the autoload still has to produce
	# sound rather than errors about a missing bus.
	GameSettings.ensure_buses()

	for i in voice_count:
		var voice := AudioStreamPlayer.new()
		voice.bus = GameSettings.SFX_BUS
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
	player.bus = GameSettings.SFX_BUS
	add_child(player)

	var mix: Dictionary = MIX.get(event, {})
	player.stream = stream
	player.volume_db = mix.get("volume", -6.0)
	player.pitch_scale = _pitch_for(mix)
	player.max_distance = mix.get("distance", max_3d_distance)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


## Which fire event a weapon uses. Kept here rather than in Game so that the
## question "what does a shotgun sound like" has exactly one answer, and so a
## fourth weapon needs no change outside this file and the generator.
##
##   sounds.play(SoundBank.fire_event(weapon.kind))
static func fire_event(kind: WeaponTypes.Kind) -> String:
	match kind:
		WeaponTypes.Kind.SHOTGUN:
			return "fire_shotgun"
		WeaponTypes.Kind.RIFLE:
			return "fire_rifle"
		_:
			return "fire_pistol"


## Which footstep event a stance uses. The same idea Game already applies to
## footstep *noise* — a sprint gives away more than a crouch — carried into
## what the player hears, so the two never disagree.
##
##   sounds.play(SoundBank.footstep_event(player.stance()))
static func footstep_event(stance: int) -> String:
	match stance:
		Player.Stance.SPRINTING:
			return "footstep_sprint"
		Player.Stance.CROUCHING:
			return "footstep_crouch"
		_:
			return "footstep"


## What a zombie sounds like the instant it notices the player.
##
## Two kinds break the default. A Screamer gets its own alarm, because what it
## does next — recruiting everything within 36 metres — is the single most
## consequential thing any enemy does, and the player cannot answer a threat
## they were never told about. A Stalker gets *nothing*: silence while hunting
## is its entire design, and an alert cue would hand the player the one piece
## of information the archetype exists to withhold.
##
## An empty string is not an error; play_at ignores unknown events, which is
## exactly the behaviour a deliberately silent enemy wants.
##
##   sounds.play_at(SoundBank.notice_event(kind), at)
static func notice_event(kind: ZombieTypes.Kind) -> String:
	match kind:
		ZombieTypes.Kind.SCREAMER:
			return "screamer_alarm"
		ZombieTypes.Kind.STALKER:
			return ""
		_:
			return "zombie_alerted"


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
		_streams[event] = _load_all(EVENTS[event], BASE)

	for event in GENERATED_EVENTS:
		_streams[event] = _load_all(GENERATED_EVENTS[event], GENERATED)


func _load_all(names: Array, pattern: String) -> Array[AudioStream]:
	var loaded: Array[AudioStream] = []

	for clip_name in names:
		var stream: AudioStream = load(pattern % clip_name)
		if stream != null:
			loaded.append(stream)

	return loaded
