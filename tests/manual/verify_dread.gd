extends SceneTree

## Verifies the dread director: phantoms wait for quiet, keep their distance
## from each other, stay silent under real danger and while the game is not
## being played, and a phantom follower never finishes walking up to a player
## who has turned to face it.
##
## The feel is the playtest's job. What this defends is the contract that
## makes the feel honest: a phantom never happens while it would compete with
## a real threat, and never while the player is looking straight at it.
##
##   Godot --headless --script tests/manual/verify_dread.gd

const TICK := 0.1
const SEED := 7

## Records play_at calls instead of making sound.
class RecordingBank extends SoundBank:
	var played: Array[String] = []

	func _ready() -> void:
		pass

	func play_at(event: String, _position: Vector3) -> void:
		played.append(event)


var _failures: Array[String] = []
var _listener: Node3D
var _camera: Camera3D


func _initialize() -> void:
	DeterministicSettings.apply(root)

	_listener = Node3D.new()
	root.add_child(_listener)
	_camera = Camera3D.new()
	_listener.add_child(_camera)


# Run on the first frame: nodes added in _initialize are not inside the tree
# yet, and the look check reads the camera's global transform.
func _process(_delta: float) -> bool:
	test_nothing_plays_before_the_first_calm()
	test_long_calm_plays_phantoms_spaced_by_the_gap()
	test_real_threat_keeps_it_silent()
	test_footsteps_stop_when_the_player_turns_to_face_them()
	test_inactive_plays_nothing()

	_report()
	return true


func _director() -> Array:
	var bank := RecordingBank.new()
	root.add_child(bank)
	var director := DreadDirector.new()
	root.add_child(director)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	director.set_rng(rng)
	director.bind(bank, _listener, _camera)
	director.reset()
	director.set_active(true)
	_camera.rotation = Vector3.ZERO
	return [director, bank]


func _run(director: DreadDirector, seconds: float, threat: float) -> Array[float]:
	# Polled rather than timestamped from a signal: a lambda captures locals by
	# value, so it would record the clock as it was when connected.
	var starts: Array[float] = []
	var elapsed := 0.0
	var seen := director.phantoms_played()
	while elapsed < seconds:
		director.tick(TICK, threat)
		elapsed += TICK
		if director.phantoms_played() > seen:
			seen = director.phantoms_played()
			starts.append(elapsed)
	return starts


func test_nothing_plays_before_the_first_calm() -> void:
	var pair := _director()
	var director: DreadDirector = pair[0]
	var starts := _run(director, director.calm_before_first - TICK, 0.0)
	_check(starts.is_empty(),
		"nothing plays in the first %.0f s of calm" % director.calm_before_first,
		"a phantom played %d time(s) before calm_before_first" % starts.size())


func test_long_calm_plays_phantoms_spaced_by_the_gap() -> void:
	var pair := _director()
	var director: DreadDirector = pair[0]
	var starts := _run(director, 400.0, 0.0)

	var min_spacing := INF
	for i in range(1, starts.size()):
		min_spacing = minf(min_spacing, starts[i] - starts[i - 1])

	_check(starts.size() >= 3,
		"400 s of calm plays %d phantoms" % starts.size(),
		"only %d phantoms in 400 s of calm" % starts.size())
	_check(min_spacing >= director.min_gap - TICK,
		"phantoms never closer than min_gap (closest %.1f s)" % min_spacing,
		"two phantoms %.1f s apart, under min_gap %.1f" % [min_spacing, director.min_gap])


func test_real_threat_keeps_it_silent() -> void:
	var pair := _director()
	var director: DreadDirector = pair[0]
	var starts := _run(director, 400.0, 0.5)
	_check(starts.is_empty(), "sustained real threat plays no phantoms",
		"%d phantoms played under threat 0.5" % starts.size())


func test_footsteps_stop_when_the_player_turns_to_face_them() -> void:
	var pair := _director()
	var director: DreadDirector = pair[0]
	var bank: RecordingBank = pair[1]

	# Unwatched: the sequence plays out in full.
	director._start_footsteps()
	var full_length: int = director._footsteps_remaining
	for i in 60:
		director.tick(TICK, 0.0)
	var unwatched := bank.played.count("phantom_step")

	# Watched: one step lands, then the player spins round to face it.
	bank.played.clear()
	director._start_footsteps()
	director.tick(TICK, 0.0)
	var to_point: Vector3 = director._footsteps_point - _camera.global_position
	_camera.rotation.y = atan2(-to_point.x, -to_point.z)
	for i in 60:
		director.tick(TICK, 0.0)
	var watched := bank.played.count("phantom_step")

	_check(unwatched == full_length,
		"unwatched footsteps play all %d steps" % full_length,
		"unwatched sequence played %d of %d steps" % [unwatched, full_length])
	_check(watched == 1 and not director._footsteps_active,
		"footsteps stop the moment the player faces them",
		"after turning to face them, %d step(s) played" % watched)


func test_inactive_plays_nothing() -> void:
	var pair := _director()
	var director: DreadDirector = pair[0]
	director.set_active(false)
	var starts := _run(director, 400.0, 0.0)
	_check(starts.is_empty(), "inactive director plays nothing",
		"%d phantoms played while inactive" % starts.size())


func _check(ok: bool, pass_text: String, fail_text: String) -> void:
	if ok:
		print("PASS: %s" % pass_text)
	else:
		_failures.append(fail_text)


func _report() -> void:
	if _failures.is_empty():
		print("\nDREAD: all checks passed")
		quit(0)
		return
	for failure in _failures:
		print("FAIL: %s" % failure)
	quit(1)
