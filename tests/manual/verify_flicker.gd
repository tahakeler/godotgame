extends SceneTree

## Verifies the torch stutter: Flashlight.flicker() itself, and the
## FlickerDirector that decides when to call it.
##
## The property worth guarding is ambiguity, and ambiguity cannot be asserted
## directly — "the player cannot tell why" has no boolean. What can be
## asserted is the mechanism that ambiguity depends on: flicker() must not
## leak which trigger caused it (light_energy is the only thing that moves;
## visibility_scale() must not), and the director must actually fire from
## both triggers under the conditions design specified, not just one of them.
## A build where only the near trigger ever fired would still pass a
## "the torch flickers near a hunter" smoke test and would have quietly
## turned this into the exact instrument the design doc says it must never
## become.
##
##   Godot --headless --script tests/manual/verify_flicker.gd

const NEAR_TEST_SECONDS := 20.0
const FAR_TEST_SECONDS := 60.0
const STEP_DT := 0.1
const SEED := 1234567

var _failures: Array[String] = []

var _flashlight: Flashlight
var _off_flashlight: Flashlight
var _frames := 0


## A ZombieSpawner that answers nearest_hunter_distance() with a fixed value
## instead of walking a real population — the director only ever calls this
## one method on the spawner, so this is the entire surface it needs to fake.
class StubSpawner extends ZombieSpawner:
	var distance := INF

	func nearest_hunter_distance(_from: Vector3) -> float:
		return distance


func _initialize() -> void:
	DeterministicSettings.apply(root)

	_flashlight = Flashlight.new()
	root.add_child(_flashlight)
	_flashlight.set_on(true)

	_off_flashlight = Flashlight.new()
	root.add_child(_off_flashlight)
	# Stays off on purpose — this is the fixture for test (b).


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		# Nodes added in _initialize are not yet in the tree on that same
		# frame; give them one frame to settle before touching them.
		return false

	test_flicker_varies_energy_and_restores_it()
	test_flicker_does_nothing_while_off()
	test_flicker_leaves_visibility_scale_unchanged()
	test_director_flickers_near_a_hunter()
	test_director_never_flickers_far_and_calm()
	test_director_flickers_for_nothing_when_calm()

	_report()
	return true


func test_flicker_varies_energy_and_restores_it() -> void:
	# Arrange
	var beam := _flashlight.beam_energy
	var saw_dark := false
	var saw_full := false

	# Act: drive the flicker by hand rather than trusting the engine's own
	# frame timing, so the assertion below is exact rather than approximate.
	_flashlight.flicker(0.5, _seeded_rng())

	var elapsed := 0.0
	while elapsed < 0.6:
		_flashlight._process(STEP_DT)
		elapsed += STEP_DT
		if elapsed < 0.5:
			if not is_equal_approx(_flashlight.light_energy, beam):
				saw_dark = true
			else:
				saw_full = true

	# Assert
	if not saw_dark:
		_failures.append("flicker(0.5) never moved light_energy off beam_energy")
	elif not is_equal_approx(_flashlight.light_energy, beam):
		_failures.append(
			"light_energy did not restore exactly to beam_energy after the window (got %.4f, want %.4f)"
			% [_flashlight.light_energy, beam]
		)
	elif _flashlight.is_flickering():
		_failures.append("is_flickering() still true after the flicker window elapsed")
	else:
		print(
			"PASS: flicker(0.5) varied light_energy (dark=%s full=%s) and restored it exactly"
			% [saw_dark, saw_full]
		)


func test_flicker_does_nothing_while_off() -> void:
	# Arrange
	var beam := _off_flashlight.beam_energy
	var energy_before := _off_flashlight.light_energy

	# Act
	_off_flashlight.flicker(0.5, _seeded_rng())
	_off_flashlight._process(STEP_DT)

	# Assert
	if _off_flashlight.is_flickering():
		_failures.append("flicker() started on a torch that is off")
	elif not is_equal_approx(_off_flashlight.light_energy, energy_before):
		_failures.append("light_energy moved on a torch that is off")
	elif not is_equal_approx(energy_before, beam):
		_failures.append("an off torch did not carry its resting light_energy")
	else:
		print("PASS: flicker() does nothing while the torch is off")


func test_flicker_leaves_visibility_scale_unchanged() -> void:
	# Arrange
	var scale_before := _flashlight.visibility_scale()

	# Act
	_flashlight.flicker(0.3, _seeded_rng())
	_flashlight._process(STEP_DT)
	var scale_during := _flashlight.visibility_scale()

	# Drain the flicker so it does not bleed into later tests.
	while _flashlight.is_flickering():
		_flashlight._process(STEP_DT)

	# Assert
	if not is_equal_approx(scale_before, scale_during):
		_failures.append(
			"visibility_scale() changed during a flicker (%.4f -> %.4f) — a zombie's sight would notice"
			% [scale_before, scale_during]
		)
	else:
		print("PASS: visibility_scale() is unaffected by a flicker in progress")


func test_director_flickers_near_a_hunter() -> void:
	# Arrange
	var torch := Flashlight.new()
	root.add_child(torch)
	torch.set_on(true)

	var spawner := StubSpawner.new()
	spawner.distance = 5.0

	var player := Node3D.new()
	root.add_child(player)

	var director := FlickerDirector.new()
	root.add_child(director)
	director.set_rng(_seeded_rng())
	director.bind(torch, spawner, player)
	director.reset()

	# Act
	var triggered := false
	var elapsed := 0.0
	while elapsed < NEAR_TEST_SECONDS and not triggered:
		director.tick(STEP_DT, 0.0)
		elapsed += STEP_DT
		if torch.is_flickering():
			triggered = true

	# Assert
	if not triggered:
		_failures.append(
			"a hunter 5m away never triggered a flicker in %.0fs of ticks" % NEAR_TEST_SECONDS
		)
	else:
		print("PASS: the director flickers near a hunter (triggered at t=%.1fs)" % elapsed)

	director.queue_free()
	spawner.free()
	player.queue_free()
	torch.queue_free()


func test_director_never_flickers_far_and_calm() -> void:
	# Arrange
	var torch := Flashlight.new()
	root.add_child(torch)
	torch.set_on(true)

	var spawner := StubSpawner.new()
	spawner.distance = 50.0

	var player := Node3D.new()
	root.add_child(player)

	var director := FlickerDirector.new()
	root.add_child(director)
	director.set_rng(_seeded_rng())
	director.bind(torch, spawner, player)
	director.reset()

	# Act: threat sits at 0.5 — well above calm_threat_threshold, so neither
	# trigger should ever be eligible.
	var triggered := false
	var elapsed := 0.0
	while elapsed < FAR_TEST_SECONDS:
		director.tick(STEP_DT, 0.5)
		elapsed += STEP_DT
		if torch.is_flickering():
			triggered = true
			break

	# Assert
	if triggered:
		_failures.append(
			"a hunter 50m away with threat 0.5 triggered a flicker within %.0fs — it should never"
			% FAR_TEST_SECONDS
		)
	else:
		print("PASS: the director never flickers far away and calm-ineligible")

	director.queue_free()
	spawner.free()
	player.queue_free()
	torch.queue_free()


## The other half of the ambiguity: with nobody near and nothing hunting, the
## torch still stutters now and then. Without this a flicker would always mean
## a hunter, and the effect would become a detector.
func test_director_flickers_for_nothing_when_calm() -> void:
	var torch := Flashlight.new()
	root.add_child(torch)
	torch.set_on(true)
	var spawner := StubSpawner.new()
	spawner.distance = 50.0
	var player := Node3D.new()
	root.add_child(player)
	var director := FlickerDirector.new()
	root.add_child(director)
	director.set_rng(_seeded_rng())
	director.bind(torch, spawner, player)
	director.reset()

	var triggered := false
	var elapsed := 0.0
	while elapsed < 600.0 and not triggered:
		director.tick(STEP_DT, 0.0)
		elapsed += STEP_DT
		triggered = torch.is_flickering()

	if triggered:
		print("PASS: the torch flickers for nothing in calm (t=%.1fs)" % elapsed)
	else:
		_failures.append("no calm flicker in 600 s with nobody near")

	director.queue_free()
	spawner.free()
	player.queue_free()
	torch.queue_free()


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
