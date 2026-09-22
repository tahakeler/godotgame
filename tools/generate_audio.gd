extends SceneTree

## Synthesises the sounds the Kenney RPG Audio pack cannot provide.
##
## That pack has no firearm — it is an RPG pack — so firing had been using a
## percussive clip pitched down, which reads as "something happened" rather
## than as a gun. A shot is the sound the player hears most in this game, and
## it was the weakest thing in the mix.
##
## Generating them keeps everything original: no licence to track, and the
## envelope can be tuned to the weapon rather than the weapon tuned to a clip.
##
##   Godot --headless --script tools/generate_audio.gd

const OUTPUT_DIR := "res://assets/audio/generated"
const SAMPLE_RATE := 44100


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_DIR)
	)

	_write("gunshot", _build_gunshot())
	_write("fire_pistol", _build_fire_pistol())
	_write("fire_shotgun", _build_fire_shotgun())
	_write("fire_rifle", _build_fire_rifle())
	_write("melee_swing", _build_melee_swing())
	_write("screamer_inhale", _build_screamer_inhale())
	_write("screamer_alarm", _build_screamer_alarm())
	_write("brute_growl", _build_brute_growl())
	_write("decoy_land", _build_decoy_land())
	_write("zombie_alerted", _build_zombie_alerted())
	_write("cave_ambience", _build_cave_ambience())
	_write("tension_pulse", _build_tension_pulse())

	quit(0)


## A shot is three things stacked: a bright crack, a body thump that gives it
## weight, and a short noisy tail that reads as the cave answering back.
func _build_gunshot() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var duration := 0.32
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var previous := 0.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE

		# Crack: white noise under a very fast decay.
		var noise := rng.randf_range(-1.0, 1.0)
		# One-pole lowpass. Raw white noise is hissy and reads as static;
		# rolling the top off leaves something with a barrel behind it.
		previous = lerpf(previous, noise, 0.55)
		var crack: float = previous * exp(-t * 46.0)

		# Body: a low sine that drops in pitch, which is what makes it read as
		# a gun rather than a snare.
		var pitch := lerpf(190.0, 70.0, minf(t / 0.09, 1.0))
		var body: float = sin(TAU * pitch * t) * exp(-t * 26.0)

		# Tail: quieter, slower noise so the sound does not simply stop.
		var tail: float = previous * exp(-t * 9.0) * 0.22

		samples[index] = clampf(crack * 0.85 + body * 0.75 + tail, -1.0, 1.0)

	return samples


## The cave itself: a slow low drone under a breath of filtered air.
##
## Built from tones whose frequencies are exact multiples of 1/duration, so
## every partial completes a whole number of cycles and the loop point lands
## on the same phase it started at. A drone that clicks once every eight
## seconds is worse than no drone at all — the ear finds the seam immediately
## and then cannot stop hearing it.
func _build_cave_ambience() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3030

	var duration := 8.0
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var previous := 0.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE

		# 384, 572 and 778 whole cycles across eight seconds.
		var drone: float = (
			sin(TAU * 48.0 * t) * 0.5
			+ sin(TAU * 71.5 * t) * 0.3
			+ sin(TAU * 97.25 * t) * 0.2
		)

		# A very slow swell, also an exact multiple, so the room seems to
		# breathe rather than hum.
		var swell: float = 0.75 + 0.25 * sin(TAU * 0.125 * t)

		# Heavily rolled-off noise for air movement. Kept low enough that the
		# seam where it wraps is inaudible under the drone.
		var noise := rng.randf_range(-1.0, 1.0)
		previous = lerpf(previous, noise, 0.02)

		samples[index] = clampf(drone * swell * 0.34 + previous * 0.5, -1.0, 1.0)

	return samples


## The layer that fades in when the cave is coming for you.
##
## A slow two-beat pulse, deliberately close to a heart at exertion. It carries
## no information the HUD does not already have — it exists so that the moment
## several things start hunting you is felt before it is read.
func _build_tension_pulse() -> PackedFloat32Array:
	var duration := 4.0
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	# Four beats across four seconds, so the loop closes on a whole number.
	var beats := 4.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE
		var phase: float = fmod(t * beats, 1.0)

		# Two thumps per beat, the second softer, like a heart.
		var strike: float = exp(-phase * 26.0) + exp(-maxf(0.0, phase - 0.22) * 30.0) * 0.55
		var tone: float = sin(TAU * 41.0 * t)

		samples[index] = clampf(tone * strike * 0.5, -1.0, 1.0)

	return samples


## The rasp a zombie makes the instant it notices you.
##
## Deliberately unlike anything else in the mix: rising rather than falling,
## and harsh rather than wet. It has to be recognisable through a firefight,
## because it is the one sound that means something changed about you rather
## than about them.
func _build_zombie_alerted() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150

	var duration := 0.55
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var previous := 0.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE
		var envelope: float = minf(t / 0.04, 1.0) * exp(-t * 4.2)

		# Rising pitch is the tell. Everything else the zombies do falls away;
		# this climbs, which reads as alarm rather than as idling.
		var pitch := lerpf(120.0, 260.0, minf(t / 0.35, 1.0))
		var tone: float = sin(TAU * pitch * t)

		# Squared up into a rasp. A clean sine reads as a machine.
		tone = signf(tone) * pow(absf(tone), 0.45)

		var noise := rng.randf_range(-1.0, 1.0)
		previous = lerpf(previous, noise, 0.25)

		samples[index] = clampf((tone * 0.55 + previous * 0.45) * envelope, -1.0, 1.0)

	return samples


## A thrown round hitting rock: a short metallic ring with almost no body.
##
## It has to be identifiable as "that was me, over there" from across a
## chamber, and distinct from a gunshot — the whole mechanic depends on the
## player telling the two apart by ear.
func _build_decoy_land() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1717

	var duration := 0.45
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	for index in frames:
		var t := float(index) / SAMPLE_RATE

		# A brief scrape of noise for the impact itself.
		var tick: float = rng.randf_range(-1.0, 1.0) * exp(-t * 180.0)

		# Two inharmonic partials ringing on. Inharmonic is what makes it read
		# as metal rather than as a musical note.
		var ring: float = (
			sin(TAU * 2350.0 * t) * 0.6
			+ sin(TAU * 3720.0 * t) * 0.4
		) * exp(-t * 11.0)

		samples[index] = clampf(tick * 0.7 + ring * 0.5, -1.0, 1.0)

	return samples


## A Brute needs to be audible before it is visible), and lower than the crowd.
func _build_brute_growl() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909

	var duration := 1.1
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var previous := 0.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE
		var envelope: float = minf(t / 0.12, 1.0) * exp(-t * 2.4)

		# Two detuned low tones beating against each other, which gives the
		# growl a wobble no single tone has.
		var tone: float = (
			sin(TAU * 58.0 * t) * 0.6
			+ sin(TAU * 71.0 * t) * 0.4
		)

		var noise := rng.randf_range(-1.0, 1.0)
		previous = lerpf(previous, noise, 0.08)

		samples[index] = clampf((tone + previous * 0.5) * envelope * 0.7, -1.0, 1.0)

	return samples


## The pistol: 26 damage, ten rounds, the quietest thing you can fire.
##
## Short and bright, with almost no tail. It has to read as *cheap* — the shot
## you can afford to take — so it is the only one of the three that is over
## before the cave has a chance to answer.
func _build_fire_pistol() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611

	var duration := 0.24
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var previous := 0.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE

		# Less lowpass than the shotgun gets: the pistol lives in the top of
		# the mix, which is where a crack has to sit to stay legible under a
		# rifle firing beside it.
		var noise := rng.randf_range(-1.0, 1.0)
		previous = lerpf(previous, noise, 0.72)
		var crack: float = previous * exp(-t * 62.0)

		# A quick fall rather than a drop. A pistol has a body, but a small one.
		var pitch := lerpf(240.0, 105.0, minf(t / 0.05, 1.0))
		var body: float = sin(TAU * pitch * t) * exp(-t * 38.0)

		samples[index] = clampf(crack * 0.82 + body * 0.6, -1.0, 1.0)

	return samples


## The shotgun: eight pellets, four shells, noise 2.2 — the loudest thing on
## the map by a factor of two and a half.
##
## This is the sound that tells the player they have just called the cave down
## on themselves, so it has to cost something to hear. Everything about it is
## long: a slow pitch drop into sub-bass, and a tail that keeps going for most
## of a second so the room is still ringing while the next zombie turns round.
func _build_fire_shotgun() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8822

	var duration := 0.9
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var previous := 0.0
	var rumble_previous := 0.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE

		var noise := rng.randf_range(-1.0, 1.0)

		# Two lowpasses at very different corners. The fast one is the blast,
		# the slow one is the room — separating them is what stops a long tail
		# from turning into hiss.
		previous = lerpf(previous, noise, 0.40)
		rumble_previous = lerpf(rumble_previous, noise, 0.035)

		var blast: float = previous * exp(-t * 20.0)

		# Down to 42 Hz, below anything else in the game. A Brute growls at 58;
		# the shotgun goes under even that, which is what makes it feel like the
		# floor moved rather than like a loud noise happened.
		var pitch := lerpf(150.0, 42.0, minf(t / 0.16, 1.0))
		var body: float = sin(TAU * pitch * t) * exp(-t * 9.0)

		# The tail decays at a third of the blast's rate. Long enough that the
		# player cannot fire again inside it and pretend nothing happened.
		var tail: float = rumble_previous * exp(-t * 3.2) * 0.75

		samples[index] = clampf(blast * 0.7 + body * 0.85 + tail, -1.0, 1.0)

	return samples


## The rifle: 17 damage every 0.09 seconds.
##
## The constraint here is repetition, not impact. Eleven of these land per
## second, so anything with a tail stacks into mud and the player stops being
## able to hear the cave over their own weapon. It is therefore the shortest of
## the three by a wide margin: all attack, a hard cut, no room tone at all.
func _build_fire_rifle() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1735

	# Shorter than the 0.09s fire interval doubled, so consecutive shots overlap
	# only briefly and each one still reads as a separate event.
	var duration := 0.15
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var previous := 0.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE

		var noise := rng.randf_range(-1.0, 1.0)
		previous = lerpf(previous, noise, 0.62)
		var snap: float = previous * exp(-t * 95.0)

		# A higher, faster body than the pistol. Higher survives being stacked;
		# low frequencies are what smear when shots overlap.
		var pitch := lerpf(330.0, 165.0, minf(t / 0.03, 1.0))
		var body: float = sin(TAU * pitch * t) * exp(-t * 55.0)

		# A hard fade over the last 12ms. Truncating a decaying sample clicks,
		# and a click repeated eleven times a second is a buzz.
		var fade: float = minf((duration - t) / 0.012, 1.0)

		samples[index] = clampf((snap * 0.9 + body * 0.55) * fade, -1.0, 1.0)

	return samples


## The Screamer's alarm — the most important sound in the game.
##
## A Screamer is harmless in a fight and recruits every zombie within 36 metres
## when it notices you. Without a cue, the player never learns that the death
## thirty seconds later was caused by something they could have shot. The
## mechanic is entirely carried by this sound, so it is built to violate every
## rule the rest of the mix follows:
##
##   - it is long (2.1s) where everything else is under a second, so it cannot
##     be missed inside a firefight;
##   - it *rises and holds* where zombie sounds fall and fade, which is what
##     makes it read as an alarm rather than as a creature;
##   - it is built on a high fundamental with a hard-saturated harmonic stack,
##     because high and harsh is what survives distance and a shotgun tail.
##
## The pitch sweeps up, wobbles on a siren vibrato, then lands on a held note.
## The held part is deliberate: it gives the player a full second in which the
## correct play — turn, find it, kill it — is still available.
## A melee swing that hits nothing. 140ms of air going past.
##
## Synthesised because the borrowed clip was actively harmful, not merely
## bland: `melee_swing` and `zombie_death` were both `cloth3`, separated only by
## pitch. "You swung and hit nothing" and "a zombie just died" are opposite
## pieces of information arriving at the one moment the player is panicking, and
## a whiff that can be mistaken for a kill is worse than no whiff sound at all.
##
## Purely noise, with no tonal content anywhere. Everything else in the melee's
## vocabulary has a pitch — `melee_hit` cracks, `melee_unmoved` thuds — so the
## absence of one is itself the signal: nothing was struck, because nothing
## resonated.
##
## The character is entirely in the downward sweep. A band of noise falling from
## 1900 Hz to 320 Hz over 140ms is the sound of a source passing the listener,
## and that is exactly the report: it went by, it did not land.
func _build_melee_swing() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var duration := 0.14
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var low := 0.0
	var band := 0.0

	for index in frames:
		var progress := float(index) / float(frames)

		# A bell, not a hit. Air builds as the arm accelerates and falls away
		# behind it; an instant attack would read as a contact, which is the one
		# thing this sound must never be confused with.
		var envelope: float = sin(PI * pow(progress, 0.75))

		# Fast at first and slowing, the way something passing you does.
		var centre: float = lerpf(1900.0, 320.0, pow(progress, 0.6))
		var f: float = 2.0 * sin(PI * centre / SAMPLE_RATE)
		# Low resonance throughout: this is a body of air, not a throat. Any
		# more and it starts to sing, which would give it the pitch it must not
		# have.
		var q := 0.9

		var noise := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high: float = noise - low - q * band
		band += f * high

		samples[index] = clampf(band * 1.1 * envelope, -1.0, 1.0)

	return samples


## The breath a Screamer takes before it screams. 1.6s, to match the wind-up.
##
## This is the most important warning in the game and it has to win three
## fights at once.
##
## Against the ambient groan. The groan is a short wooden creak that starts at
## its loudest and dies away. This does the opposite in every dimension: it has
## no attack at all, swells continuously for a second and a half, and rises in
## pitch throughout. Nothing else in the bank crescendos, and a rising,
## swelling sound is the one gesture the ear refuses to file as background —
## it is the shape of something approaching, which is exactly the report.
##
## Against distance and corners. Sound is the only sense that goes round a
## corner in this game — the flashlight needs line of sight and this must not.
## The energy is deliberately low and narrow-band rather than bright: high
## frequencies are the first thing forty metres of cave takes away, so a hiss
## would vanish and this does not.
##
## Against a firefight. A gunshot is a broadband transient, over in a moment.
## This is sustained, narrow and slow, which puts it in a different perceptual
## stream — the ear tracks it as a separate voice rather than masking it under
## the shooting, in the same way a held note survives applause.
##
## It ends on 300 Hz because that is the pitch `screamer_alarm` begins at, so
## the inhale does not stop and a scream start: the breath focuses, arrives at
## the note, and the scream continues the same gesture. Two clips, one event.
func _build_screamer_inhale() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6661

	# Matches Zombie's 1.6s alarm wind-up. If that timing changes this should
	# follow it, or the breath will finish before or after the lungs do.
	var duration := 1.6
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	# State-variable filter state. A resonant band-pass is what turns white
	# noise into breath rather than static — the resonance gives the air a
	# throat to pass through.
	var low := 0.0
	var band := 0.0
	var tone_phase := 0.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE
		var progress := t / duration

		# No attack whatsoever, and an accelerating swell. An onset is what
		# makes a sound an event; the absence of one is what makes this feel
		# like something that was already happening when you noticed it.
		var envelope: float = pow(progress, 1.7)
		# Except at the very end, where it must not click into the scream.
		envelope *= minf(1.0, (1.0 - progress) / 0.04 + 0.85)

		# 170 Hz up to the 300 Hz the scream starts on. Curved rather than
		# linear so most of the travel happens late, which reads as the breath
		# running out of room.
		var centre: float = lerpf(170.0, 300.0, pow(progress, 1.5))

		var f: float = 2.0 * sin(PI * centre / SAMPLE_RATE)
		# Resonance tightens as the breath focuses: wide and airy at the start,
		# nearly a pitch by the end.
		var q: float = lerpf(0.55, 0.13, progress)

		var noise := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high: float = noise - low - q * band
		band += f * high

		# The tone the breath resolves into, absent until the final third. This
		# is the hinge between the two clips — by the time the scream starts,
		# its pitch is already sounding.
		var focus: float = clampf((progress - 0.62) / 0.38, 0.0, 1.0)
		tone_phase = fmod(tone_phase + TAU * centre / SAMPLE_RATE, TAU)
		var tone: float = sin(tone_phase) * focus * 0.3

		samples[index] = clampf((band * 1.6 + tone) * envelope, -1.0, 1.0)

	return samples


func _build_screamer_alarm() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6660

	var duration := 2.1
	var frames := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var previous := 0.0
	var phase := 0.0
	var sub_phase := 0.0

	for index in frames:
		var t := float(index) / SAMPLE_RATE

		# Fast in, long hold, decay only over the final third. The shape of a
		# siren, not of an impact.
		var envelope: float = minf(t / 0.06, 1.0) * minf(1.0, exp(-maxf(0.0, t - 1.35) * 2.6))

		# Up to 880 Hz over the first 0.45s and then held. Integrating the
		# instantaneous frequency rather than writing sin(TAU * f * t) matters
		# here: with a sweeping f the latter smears the phase and the sweep
		# arrives at the wrong pitch.
		var sweep: float = lerpf(300.0, 880.0, minf(t / 0.45, 1.0))
		# A 5.5 Hz wobble. A steady tone reads as an electronic alert; the
		# waver is what keeps it attached to a throat.
		var frequency: float = sweep * (1.0 + 0.055 * sin(TAU * 5.5 * t))

		phase = fmod(phase + TAU * frequency / SAMPLE_RATE, TAU)
		sub_phase = fmod(sub_phase + TAU * frequency * 0.5 / SAMPLE_RATE, TAU)

		# Saturated hard. pow(|x|, 0.3) is close to a square wave, which is a
		# stack of odd harmonics — that stack is what still gets through when
		# the sound has been attenuated by forty metres of distance.
		var cry: float = sin(phase)
		cry = signf(cry) * pow(absf(cry), 0.3)

		# An octave below, kept quiet. It carries no information; it is there so
		# the scream has a body and does not sound like a whistle.
		var sub: float = sin(sub_phase) * 0.35

		# A rasp of breath over the top.
		var noise := rng.randf_range(-1.0, 1.0)
		previous = lerpf(previous, noise, 0.35)

		samples[index] = clampf(
			(cry * 0.62 + sub * 0.28 + previous * 0.22) * envelope, -1.0, 1.0
		)

	return samples


func _write(name: String, samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)

	for index in samples.size():
		var value := int(clampf(samples[index], -1.0, 1.0) * 32767.0)
		data.encode_s16(index * 2, value)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data

	var path := "%s/%s.wav" % [OUTPUT_DIR, name]
	var error := stream.save_to_wav(path)

	if error != OK:
		printerr("FAIL: could not write %s (error %d)" % [path, error])
		return

	print("wrote %s  (%.2fs, %d frames)" % [
		path, float(samples.size()) / SAMPLE_RATE, samples.size()
	])
