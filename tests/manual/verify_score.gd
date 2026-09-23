extends SceneTree

## Verifies the layered horror score: a cave bed picked per round, a tension
## layer that rides the smoothed threat from dread to danger, a dread swell
## that marks a long quiet breaking rather than every notice, and silence on
## death that begin_round() undoes.
##
## The feel of the fade is a playtest's job. What this defends is the
## contract: the tension layer is silent at zero threat and at
## tension_volume_db at full threat, the swell respects both its calm
## requirement and its cooldown, and a round restart always gets the score
## back to its resting volumes no matter what the last round did to it.
##
##   Godot --headless --script tests/manual/verify_score.gd

const TICK := 0.5

var _failures: Array[String] = []
var _ambience: Ambience


func _initialize() -> void:
	DeterministicSettings.apply(root)

	_ambience = Ambience.new()
	root.add_child(_ambience)


# Run on the first frame: the Ambience node added in _initialize is not
# inside the tree yet during _initialize itself, and building its layers
# (which needs the Music bus) has to wait until it is.
func _process(_delta: float) -> bool:
	test_zero_threat_is_silent_tension_and_bed_plays()
	test_full_threat_reaches_tension_volume()
	test_short_calm_does_not_play_the_swell()
	test_long_calm_plays_the_swell_once_per_cooldown()
	test_threat_after_fade_out_does_not_bring_the_music_back()
	test_fade_out_then_begin_round_restores_the_bed()

	_report()
	return true


func _settle_threat(target: float) -> void:
	# Enough steps to fully close the gap at the default smoothing rate (1.6
	# per second), with headroom, rather than assuming an exact step count.
	for i in 40:
		_ambience.set_threat(target, TICK)


func test_zero_threat_is_silent_tension_and_bed_plays() -> void:
	_settle_threat(0.0)

	_check(_ambience.tension_volume_db_now() <= -50.0,
		"tension layer is silent at threat 0 (%.1f dB)" % _ambience.tension_volume_db_now(),
		"tension layer at threat 0 was %.1f dB, expected <= -50 dB" % _ambience.tension_volume_db_now())
	_check(_ambience.explore_playing(),
		"the exploration bed is playing",
		"the exploration bed was not playing")


func test_full_threat_reaches_tension_volume() -> void:
	# 10 s at full threat, well past both the smoothing time constant and the
	# window the task asks the check to hold over.
	var steps := int(10.0 / TICK)
	for i in steps:
		_ambience.set_threat(1.0, TICK)

	var got := _ambience.tension_volume_db_now()
	var want: float = _ambience.tension_volume_db
	_check(absf(got - want) <= 1.0,
		"tension layer at threat 1.0 reached %.1f dB (target %.1f dB)" % [got, want],
		"tension layer at threat 1.0 was %.1f dB, wanted within 1 dB of %.1f dB" % [got, want])


func test_short_calm_does_not_play_the_swell() -> void:
	_settle_threat(0.0)
	var before := _ambience.swell_play_count()

	# 10 s of calm — short of the 40 s default requirement.
	var steps := int(10.0 / TICK)
	for i in steps:
		_ambience.set_threat(0.0, TICK)
	_ambience.on_first_notice()

	_check(_ambience.swell_play_count() == before,
		"a notice after only 10 s of calm plays no swell",
		"a notice after only 10 s of calm played the swell")


func test_long_calm_plays_the_swell_once_per_cooldown() -> void:
	# Continues accumulating calm from the previous test's 10 s rather than
	# resetting threat, since threat has stayed at 0 the whole time and the
	# calm timer is cumulative across that stretch.
	var before := _ambience.swell_play_count()

	# 35 more seconds brings total calm to 45 s, past the 40 s requirement.
	var steps := int(35.0 / TICK)
	for i in steps:
		_ambience.set_threat(0.0, TICK)
	_ambience.on_first_notice()

	_check(_ambience.swell_play_count() == before + 1,
		"a notice after 45 s of calm plays the swell once",
		"a notice after 45 s of calm played the swell %d time(s), expected 1" %
			(_ambience.swell_play_count() - before))

	# 5 s later, well inside the 90 s cooldown, a second notice must not
	# retrigger it even though calm is still building.
	var after_first := _ambience.swell_play_count()
	var cooldown_steps := int(5.0 / TICK)
	for i in cooldown_steps:
		_ambience.set_threat(0.0, TICK)
	_ambience.on_first_notice()

	_check(_ambience.swell_play_count() == after_first,
		"a second notice 5 s later, inside the cooldown, plays nothing more",
		"a second notice inside the cooldown played the swell again")


func test_fade_out_then_begin_round_restores_the_bed() -> void:
	_settle_threat(0.0)
	_ambience.fade_out()
	_ambience.begin_round()

	var got := _ambience.explore_volume_db_now()
	var want: float = _ambience.explore_volume_db
	_check(absf(got - want) <= 0.01,
		"begin_round() after fade_out() restores the bed to %.1f dB" % want,
		"bed volume after begin_round() was %.1f dB, expected %.1f dB" % [got, want])
	_check(_ambience.explore_playing(),
		"the exploration bed is playing again after begin_round()",
		"the exploration bed was not playing after begin_round()")


## Threat keeps being sampled after death. Re-applying the mix on each sample
## would drag the layers back up against the fade, so a death to a crowd would
## end with the tension layer at full volume over the results screen.
func test_threat_after_fade_out_does_not_bring_the_music_back() -> void:
	_ambience.begin_round()
	_settle_threat(0.0)
	_ambience.fade_out()
	_settle_threat(1.0)

	var got := _ambience.tension_volume_db_now()
	_check(got <= -50.0,
		"full threat after fade_out leaves the tension layer silent",
		"tension layer rose to %.1f dB after fade_out" % got)
	_ambience.begin_round()


func _check(ok: bool, pass_text: String, fail_text: String) -> void:
	if ok:
		print("PASS: %s" % pass_text)
	else:
		_failures.append(fail_text)


func _report() -> void:
	if _failures.is_empty():
		print("\nSCORE: all checks passed")
		quit(0)
		return
	for failure in _failures:
		print("FAIL: %s" % failure)
	quit(1)
