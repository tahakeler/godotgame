extends SceneTree

## Dev tool: boots the game, waits for zombies to arrive, and writes a frame to
## disk so rendering can be checked without playing by hand. Must run WITHOUT
## --headless; the headless renderer is a dummy and produces a blank image.
##
##   Godot --path . --script tools/capture_screenshot.gd --resolution 1280x720

const OUTPUT_PATH := "res://screenshot.png"
const CAPTURE_AFTER_SECONDS := 7.5

var _game: Game
var _elapsed := 0.0
var _started := false


func _initialize() -> void:
	var scene: PackedScene = load("res://src/core/game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		return false

	_elapsed += delta

	# Point the camera at the thick of the arena so the shot shows zombies,
	# cover, and lighting rather than an empty corner.
	if _game.player != null:
		_game.player.rotation.y = PI * 0.25

	if _elapsed < CAPTURE_AFTER_SECONDS:
		return false

	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)

	if error != OK:
		printerr("FAIL: could not write %s (error %d)" % [OUTPUT_PATH, error])
		quit(1)
		return true

	print("PASS: wrote %s (%dx%d), %d hostiles alive" % [
		OUTPUT_PATH, image.get_width(), image.get_height(),
		_game.spawner.get_alive_count()
	])
	quit(0)
	return true
