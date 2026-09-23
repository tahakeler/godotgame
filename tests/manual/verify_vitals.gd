extends SceneTree

## Verifies the low-health vitals cue: VitalsAudio ramps the SFX bus's
## lowpass toward GameSettings.MUFFLE_MIN_CUTOFF as health drops below
## low_health_fraction, retriggers a heartbeat on the Master bus (never
## muffled itself), eases the muffle back out on healing, and reset() clears
## both immediately rather than on the next tick. Also checks that
## GameSettings.ensure_buses() stays idempotent for the new lowpass filter,
## the same contract _ensure_sfx_reverb already holds.
##
##   Godot --headless --script tests/manual/verify_vitals.gd

const TICK := 0.1
const LOW_HEALTH_SECONDS := 3.0

var _failures: Array[String] = []


func _initialize() -> void:
	DeterministicSettings.apply(root)


# Run on the first frame: nodes added in _initialize are not inside the tree
# yet, and VitalsAudio's _ready() (which builds its beat player) needs to be
# inside a live tree to be trusted.
func _process(_delta: float) -> bool:
	test_full_health_stays_clear_and_silent()
	test_low_health_muffles_and_beats()
	test_healing_clears_the_muffle()
	test_reset_restores_cutoff_at_once()
	test_ensure_buses_twice_leaves_one_lowpass()

	_report()
	return true


func _make_vitals() -> VitalsAudio:
	GameSettings.ensure_buses()
	GameSettings.set_sfx_muffle(0.0)
	var vitals := VitalsAudio.new()
	root.add_child(vitals)
	return vitals


func _cutoff_hz() -> float:
	var sfx_index := AudioServer.get_bus_index(GameSettings.SFX_BUS)
	if sfx_index < 0:
		return -1.0

	for i in AudioServer.get_bus_effect_count(sfx_index):
		var effect := AudioServer.get_bus_effect(sfx_index, i)
		if effect is AudioEffectLowPassFilter:
			return effect.cutoff_hz

	return -1.0


func _run(vitals: VitalsAudio, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		vitals.tick(TICK)
		elapsed += TICK


func test_full_health_stays_clear_and_silent() -> void:
	var vitals := _make_vitals()
	vitals.set_health(100.0, 100.0)
	_run(vitals, LOW_HEALTH_SECONDS)

	var cutoff := _cutoff_hz()
	_check(cutoff >= 19000.0,
		"full health keeps the SFX bus clear (cutoff %.0f Hz)" % cutoff,
		"full health left the SFX bus muffled at %.0f Hz" % cutoff)
	_check(vitals.beats_played == 0,
		"full health plays no heartbeat",
		"full health played %d heartbeat(s)" % vitals.beats_played)

	vitals.queue_free()


func test_low_health_muffles_and_beats() -> void:
	var vitals := _make_vitals()
	vitals.set_health(10.0, 100.0)
	_run(vitals, LOW_HEALTH_SECONDS)

	var cutoff := _cutoff_hz()
	_check(cutoff <= 1500.0,
		"10%% health muffles the SFX bus to %.0f Hz within 3 s" % cutoff,
		"10%% health only reached %.0f Hz after 3 s" % cutoff)
	_check(vitals.beats_played >= 2,
		"10%% health retriggers the heartbeat (%d beats in 3 s)" % vitals.beats_played,
		"10%% health only played %d heartbeat(s) in 3 s" % vitals.beats_played)

	vitals.queue_free()


func test_healing_clears_the_muffle() -> void:
	var vitals := _make_vitals()
	vitals.set_health(10.0, 100.0)
	_run(vitals, LOW_HEALTH_SECONDS)
	vitals.set_health(100.0, 100.0)
	_run(vitals, LOW_HEALTH_SECONDS)

	var cutoff := _cutoff_hz()
	_check(cutoff >= 19000.0,
		"healing back to full clears the muffle (cutoff %.0f Hz)" % cutoff,
		"healing back to full left the SFX bus at %.0f Hz" % cutoff)

	vitals.queue_free()


func test_reset_restores_cutoff_at_once() -> void:
	var vitals := _make_vitals()
	vitals.set_health(5.0, 100.0)
	_run(vitals, LOW_HEALTH_SECONDS)
	vitals.reset()

	var cutoff := _cutoff_hz()
	_check(cutoff >= 19000.0,
		"reset() restores the cutoff immediately (%.0f Hz)" % cutoff,
		"reset() left the cutoff at %.0f Hz" % cutoff)
	_check(vitals.beats_played == 0,
		"reset() clears the beat counter",
		"reset() left beats_played at %d" % vitals.beats_played)

	vitals.queue_free()


func test_ensure_buses_twice_leaves_one_lowpass() -> void:
	GameSettings.ensure_buses()
	GameSettings.ensure_buses()

	var sfx_index := AudioServer.get_bus_index(GameSettings.SFX_BUS)
	var count := 0
	for i in AudioServer.get_bus_effect_count(sfx_index):
		if AudioServer.get_bus_effect(sfx_index, i) is AudioEffectLowPassFilter:
			count += 1

	_check(count == 1,
		"ensure_buses() called twice leaves exactly one lowpass on SFX",
		"ensure_buses() called twice left %d lowpass filter(s) on SFX" % count)


func _check(ok: bool, pass_text: String, fail_text: String) -> void:
	if ok:
		print("PASS: %s" % pass_text)
	else:
		_failures.append(fail_text)


func _report() -> void:
	if _failures.is_empty():
		print("\nVITALS: all checks passed")
		quit(0)
		return
	for failure in _failures:
		print("FAIL: %s" % failure)
	quit(1)
