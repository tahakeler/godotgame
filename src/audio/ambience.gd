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
##
## On top of that sound design sits a score: a cave bed picked fresh each
## round, a tension layer that rides the same smoothed threat from dread to
## danger without ever switching tracks, and a dread swell that marks the
## moment a long quiet breaks rather than every notice. Design doc:
## design/gdd/dread-audio.md.

const AMBIENCE_STREAM := "res://assets/audio/generated/cave_ambience.wav"
const PULSE_STREAM := "res://assets/audio/generated/tension_pulse.wav"

## Two cave beds — one is picked at random for the round. Two rather than one
## so a long session does not learn the score by heart.
const EXPLORE_BEDS := [
	"res://assets/audio/sourced/music/ancient_caverns_drone_loop.ogg",
	"res://assets/audio/sourced/music/dark_cavern_ambient_loop.ogg",
]
const TENSION_STREAM := "res://assets/audio/sourced/music/lurking_evil_tense_loop.ogg"
const SWELL_STREAM := "res://assets/audio/sourced/stingers/dark_stinger_01.ogg"

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

## Exploration score volume in dB — the cave bed picked fresh each round.
@export var explore_volume_db := -16.0
## Below this threat the tension layer is silent, the same shape as the pulse.
@export var tension_threshold := 0.25
## Tension layer volume at full threat.
@export var tension_volume_db := -10.0
## How far the exploration bed ducks under full threat. It ducks rather than
## stops, so the mix moves from dread to danger instead of swapping tracks.
@export var explore_duck_db := -8.0

## Dread swell volume in dB.
@export var swell_volume_db := -12.0
## Smoothed threat must stay under swell_calm_threshold this long before a
## swell may play — it marks a long quiet breaking, not a notice on its own.
@export var swell_calm_required := 40.0
## Minimum seconds between swells, regardless of how calm it has been.
@export var swell_cooldown := 90.0
## Threat below this counts as "calm" for the swell's quiet requirement.
@export var swell_calm_threshold := 0.12

## Volume every layer is tweened to on fade_out().
@export var fade_silence_db := -60.0

var _threat := 0.0
var _bed: AudioStreamPlayer
var _pulse: AudioStreamPlayer
var _score: AudioStreamPlayer
var _tension: AudioStreamPlayer
var _swell: AudioStreamPlayer

var _calm_time := 0.0
var _swell_cooldown_remaining := 0.0
var _swell_play_count := 0
var _fade_tween: Tween
## Set by fade_out, cleared by begin_round. While set, _apply leaves every
## volume alone: threat is still sampled after death, and re-applying the mix
## each sample would drag the layers back up against the fade.
var _silenced := false


func _ready() -> void:
	_bed = _build_layer(AMBIENCE_STREAM, bed_volume_db)
	_pulse = _build_layer(PULSE_STREAM, linear_to_db(0.0001))
	_score = _build_music_layer(_random_explore_bed(), explore_volume_db, true, true)
	_tension = _build_music_layer(TENSION_STREAM, linear_to_db(0.0001), true, true)
	# The swell is a one-shot: built here so the stream is loaded and warned
	# about once, but never auto-played — only on_first_notice() starts it.
	_swell = _build_music_layer(SWELL_STREAM, linear_to_db(0.0001), false, false)


## Feed the current danger in. Called every frame by Game.
func set_threat(target: float, delta: float) -> void:
	_threat = move_toward(_threat, clampf(target, 0.0, 1.0), smoothing * delta)

	if _threat < swell_calm_threshold:
		_calm_time += delta
	else:
		_calm_time = 0.0
	_swell_cooldown_remaining = maxf(0.0, _swell_cooldown_remaining - delta)

	_apply()


## The smoothed figure, which is what the mix and the vignette both read.
func threat() -> float:
	return _threat


## Called by Game at the start of every round. Rerolls which of the two
## exploration beds plays and puts every layer back at its resting volume —
## the counterpart to fade_out(), which is silence's only exit.
func begin_round() -> void:
	_kill_fade_tween()
	_silenced = false
	_threat = 0.0
	_calm_time = 0.0
	_swell_cooldown_remaining = 0.0

	if _bed != null:
		_bed.volume_db = bed_volume_db
		if not _bed.playing:
			_bed.play()

	if _pulse != null and not _pulse.playing:
		_pulse.play()

	if _score == null:
		_score = _build_music_layer(_random_explore_bed(), explore_volume_db, true, true)
	else:
		var stream: AudioStream = load(_random_explore_bed())
		if stream == null:
			push_warning("Ambience: could not reload an exploration bed")
		else:
			if stream is AudioStreamOggVorbis:
				stream.loop = true
			_score.stream = stream
		_score.play()

	if _tension != null and not _tension.playing:
		_tension.play()

	_apply()


## Called by Game the moment a zombie's zombie_noticed_player fires. Plays the
## dread swell once, but only if it marks a long quiet breaking rather than
## routine business — a swell on every notice would just be another sting.
func on_first_notice() -> void:
	if _swell == null:
		return
	if _swell_cooldown_remaining > 0.0:
		return
	if _calm_time < swell_calm_required:
		return

	_swell.volume_db = swell_volume_db
	_swell.play(0.0)
	_swell_cooldown_remaining = swell_cooldown
	_swell_play_count += 1


## Called by Game on player death. Tweens every layer to silence rather than
## cutting it — a hard cut in a headphone-heavy horror game reads as an audio
## bug, not as the mix agreeing that the player is dead. begin_round() is what
## brings the volumes back.
func fade_out(seconds := 2.5) -> void:
	_kill_fade_tween()
	_silenced = true
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	for layer in [_bed, _pulse, _score, _tension, _swell]:
		if layer != null:
			_fade_tween.tween_property(layer, "volume_db", fade_silence_db, seconds)


func _kill_fade_tween() -> void:
	# A fade left running across a round restart would keep dragging the
	# freshly restored volumes back down on its next tick.
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _apply() -> void:
	if _silenced:
		return

	if _pulse != null:
		if _threat <= pulse_threshold:
			_pulse.volume_db = linear_to_db(0.0001)
		else:
			# Rescaled above the threshold so the pulse comes in from nothing
			# rather than snapping to an audible level the moment it crosses.
			var strength := inverse_lerp(pulse_threshold, 1.0, _threat)
			_pulse.volume_db = linear_to_db(maxf(strength, 0.0001)) + pulse_volume_db

	if _tension != null:
		if _threat <= tension_threshold:
			_tension.volume_db = linear_to_db(0.0001)
		else:
			# Same shape as the pulse: silent below the threshold, rescaled
			# above it so tension arrives from nothing rather than a snap.
			var strength := inverse_lerp(tension_threshold, 1.0, _threat)
			_tension.volume_db = linear_to_db(maxf(strength, 0.0001)) + tension_volume_db

	if _score != null:
		# A duck rather than a mute, so the mix moves from dread to danger
		# instead of swapping tracks under the player.
		_score.volume_db = explore_volume_db + explore_duck_db * _threat


func _random_explore_bed() -> String:
	return EXPLORE_BEDS[randi() % EXPLORE_BEDS.size()]


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

	# The bed and the pulse are this game's score — there is no other music —
	# so they answer to the music slider rather than the effects one.
	GameSettings.ensure_buses()

	var player := AudioStreamPlayer.new()
	player.bus = GameSettings.MUSIC_BUS
	player.stream = stream
	player.volume_db = volume_db
	player.autoplay = false
	add_child(player)
	player.play()

	return player


## Same shape as _build_layer(), for the sourced OGG score layers. A missing
## file is a push_warning and a skipped layer, never a crash — the game should
## still be playable with no score, the way it is with no bed if a WAV goes
## missing.
func _build_music_layer(
	path: String, volume_db: float, loop: bool, autoplay: bool
) -> AudioStreamPlayer:
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("Ambience: could not load %s — skipping layer" % path)
		return null

	if loop and stream is AudioStreamOggVorbis:
		stream.loop = true

	GameSettings.ensure_buses()

	var player := AudioStreamPlayer.new()
	player.bus = GameSettings.MUSIC_BUS
	player.stream = stream
	player.volume_db = volume_db
	player.autoplay = false
	add_child(player)
	if autoplay:
		player.play()

	return player


## Read-only accessors below exist for tests: the mix has no HUD equivalent to
## assert against, so these let the score's shape be checked without reaching
## into private state.

func tension_volume_db_now() -> float:
	return _tension.volume_db if _tension != null else linear_to_db(0.0001)


func explore_volume_db_now() -> float:
	return _score.volume_db if _score != null else linear_to_db(0.0001)


func explore_playing() -> bool:
	return _score != null and _score.playing


func swell_play_count() -> int:
	return _swell_play_count
