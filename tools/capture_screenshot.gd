extends SceneTree

## Dev tool: boots a scene, waits, and writes a frame to disk so rendering can
## be checked without playing by hand. Must run WITHOUT --headless; the headless
## renderer is a dummy and produces a blank image.
##
##   Godot --path . --script tools/capture_screenshot.gd --resolution 1280x720 \
##       -- --scene=res://src/ui/main_menu.tscn --out=res://menu.png --delay=1.0
##
## Defaults to the game scene with a delay long enough for zombies to arrive.
##
## --script replaces the main loop, which means Godot does NOT load autoloads
## or the configured main scene. Both are set up by hand below, otherwise the
## captured frame is an empty grey window.

const AUTOLOAD_SCRIPT := "res://src/core/game_settings.gd"
const AUTOLOAD_NAME := "Settings"

var _scene_path := "res://src/core/game.tscn"
var _output_path := "res://screenshot.png"
var _delay := 7.5
## Line up one of each zombie kind instead of aiming at the nearest one.
var pose_variety := false
## Camera pitch in degrees, positive looking up. Lets a capture check the
## ceiling, which is otherwise never in frame.
var _pitch := 0.0

var _root_node: Node
var _elapsed := 0.0
var _started := false


func _initialize() -> void:
	_parse_arguments()
	_install_autoload()

	var scene: PackedScene = load(_scene_path)
	if scene == null:
		printerr("FAIL: could not load %s" % _scene_path)
		quit(1)
		return

	_root_node = scene.instantiate()
	root.add_child(_root_node)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		return false

	_elapsed += delta

	# Turn the player so the shot frames the arena rather than a bare corner.
	# Face the nearest zombie, so the shot actually shows the thing under test
	# rather than whichever wall the player happened to spawn looking at.
	if _root_node is Game and _root_node.player != null:
		_root_node.spawner.minimum_spawn_distance = 6.0
		_face_nearest_zombie()

		if not is_zero_approx(_pitch):
			_root_node.player.head.rotation.x = deg_to_rad(_pitch)

	if _elapsed < _delay:
		return false

	var image := root.get_texture().get_image()
	if image.save_png(_output_path) != OK:
		printerr("FAIL: could not write %s" % _output_path)
		quit(1)
		return true

	print("CAPTURED %s (%dx%d) from %s" % [
		_output_path, image.get_width(), image.get_height(), _scene_path
	])
	quit(0)
	return true


func _face_nearest_zombie() -> void:
	var player: Node3D = _root_node.player
	var nearest: Node3D = null
	var nearest_distance := INF

	for child in _root_node.spawner.get_children():
		if not (child is Zombie) or child.is_queued_for_deletion():
			continue

		var distance: float = player.global_position.distance_to(child.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = child

	if nearest == null:
		return

	# Zombies wander into side chambers, so the nearest one is often behind a
	# wall. Place it in clear view instead — this is a screenshot tool, and a
	# deterministic frame is worth more than an authentic one.
	nearest.global_position = player.global_position + Vector3(0.0, 0.0, -4.5)
	player.rotation.y = 0.0


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			_scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
		elif argument == "--pose-variety":
			pose_variety = true
		elif argument.begins_with("--delay="):
			_delay = float(argument.trim_prefix("--delay="))
		elif argument.begins_with("--pitch="):
			_pitch = float(argument.trim_prefix("--pitch="))


func _install_autoload() -> void:
	var script: GDScript = load(AUTOLOAD_SCRIPT)
	var node: Node = script.new()
	node.name = AUTOLOAD_NAME
	root.add_child(node)


## Line up one of each zombie kind in front of the camera, so a screenshot can
## confirm the three read as different creatures rather than one recolour.
func _pose_variety() -> void:
	var player: Node3D = _root_node.player
	var zombies: Array[Zombie] = []

	for child in _root_node.spawner.get_children():
		if child is Zombie and not child.is_queued_for_deletion():
			zombies.append(child)

	var kinds := [
		ZombieTypes.Kind.SHAMBLER, ZombieTypes.Kind.RUNNER, ZombieTypes.Kind.BRUTE
	]

	for index in mini(kinds.size(), zombies.size()):
		var zombie := zombies[index]
		zombie.configure(kinds[index])
		zombie.global_position = player.global_position + Vector3(
			float(index - 1) * 2.6, 0.0, -7.0
		)
