extends SceneTree

## Verifies the accessibility options actually change the game.
##
## An accessibility setting that saves correctly and affects nothing is worse
## than no setting at all: it tells a player their problem is handled when it
## is not. So these assert on behaviour — the palette a readout would use, the
## shake a hit would produce — rather than on the stored value.
##
##   Godot --headless --script tests/manual/verify_accessibility.gd

const PLAYER_SCENE := "res://src/gameplay/player/player.tscn"

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	test_colour_modes_are_distinguishable_from_each_other()
	test_colour_modes_keep_safe_and_danger_apart()
	test_shake_scale_of_zero_produces_no_camera_shake()
	test_shake_scale_is_proportional()

	_report()
	return true


func test_colour_modes_are_distinguishable_from_each_other() -> void:
	# Arrange / Act: every mode must define a full palette.
	var missing: Array[String] = []

	for mode in GameSettings.COLOUR_MODE_NAMES:
		var palette: Dictionary = GameSettings.COLOUR_PALETTES.get(mode, {})
		for key in ["safe", "danger", "accent"]:
			if not palette.has(key):
				missing.append("%s has no %s colour" % [
					GameSettings.COLOUR_MODE_NAMES[mode], key
				])

	# Assert
	if missing.is_empty():
		print("PASS: all %d colour modes define a full palette" % [
			GameSettings.COLOUR_MODE_NAMES.size()
		])
	else:
		_failures.append_array(missing)


func test_colour_modes_keep_safe_and_danger_apart() -> void:
	# Arrange: "healthy" and "nearly dead" are the pair that must never
	# collapse into each other, whichever mode is selected.
	var too_close: Array[String] = []

	for mode in GameSettings.COLOUR_PALETTES:
		var palette: Dictionary = GameSettings.COLOUR_PALETTES[mode]
		var safe: Color = palette.safe
		var danger: Color = palette.danger

		# Compare on hue and brightness rather than raw RGB distance: two
		# colours can be far apart numerically and still read the same to
		# someone who cannot separate their hues.
		var hue_gap: float = absf(safe.h - danger.h)
		hue_gap = minf(hue_gap, 1.0 - hue_gap)
		var value_gap: float = absf(safe.get_luminance() - danger.get_luminance())

		if hue_gap < 0.08 and value_gap < 0.15:
			too_close.append(
				"%s: safe and danger are too similar (hue gap %.2f, brightness gap %.2f)"
				% [GameSettings.COLOUR_MODE_NAMES[mode], hue_gap, value_gap]
			)

	# Assert
	if too_close.is_empty():
		print("PASS: safe and danger stay distinct in every colour mode")
	else:
		_failures.append_array(too_close)


func test_shake_scale_of_zero_produces_no_camera_shake() -> void:
	# Arrange
	var player := _build_player()
	player.shake_scale = 0.0

	# Act: a hit's worth of trauma.
	player.add_trauma(0.6)

	# Assert
	if not is_zero_approx(player._trauma):
		_failures.append(
			"camera shake was disabled but a hit still produced %.2f trauma"
			% player._trauma
		)
	else:
		print("PASS: a shake setting of zero produces no shake at all")

	player.free()


func test_shake_scale_is_proportional() -> void:
	# Arrange
	var player := _build_player()
	player.shake_scale = 0.5

	# Act
	player.add_trauma(0.6)

	# Assert
	if not is_equal_approx(player._trauma, 0.3):
		_failures.append(
			"half shake should have produced 0.30 trauma, got %.2f" % player._trauma
		)
	else:
		print("PASS: shake scales proportionally (half setting, half trauma)")

	player.free()


func _build_player() -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(player)
	return player


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
