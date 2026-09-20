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
	_write("brute_growl", _build_brute_growl())
	_write("decoy_land", _build_decoy_land())
	_write("zombie_alerted", _build_zombie_alerted())

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
