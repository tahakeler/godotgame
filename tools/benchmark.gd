extends SceneTree

## Measures frame time under a full horde, and reports where the time goes.
##
## Must run WITHOUT --headless: the headless renderer draws nothing, so it
## reports a frame rate the game will never actually see. Everything this
## project has measured so far was logic; this is the first thing that asks
## whether the game is playable on the machine it runs on.
##
##   Godot --path . --script tools/benchmark.gd --resolution 1920x1080 -- --zombies=30

const GAME_SCENE := "res://src/core/game.tscn"

## Frames to run before sampling, so shader compilation and the first navmesh
## queries do not land in the measurement.
const WARMUP_FRAMES := 90

var _zombie_target := 30
var _sample_frames := 400

var _game: Game
var _frames := 0
var _samples: Array[float] = []
var _configured := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--zombies="):
			_zombie_target = int(argument.trim_prefix("--zombies="))
		elif argument.begins_with("--frames="):
			_sample_frames = int(argument.trim_prefix("--frames="))

	# Vsync pins every frame to 16.67ms and hides all headroom, making a
	# struggling build look identical to a comfortable one.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(delta: float) -> bool:
	if _game == null or _game.spawner == null:
		return false

	if not _configured:
		_configured = true
		# Drive the population straight to the target rather than waiting out
		# the ramp; the question is how it performs at full load.
		_game.spawner.grace_period = 0.0
		_game.spawner.initial_interval = 0.02
		_game.spawner.minimum_interval = 0.02
		_game.spawner.max_alive = _zombie_target
		_game.spawner.minimum_spawn_distance = 0.0

	_frames += 1

	if _frames < WARMUP_FRAMES:
		return false

	_samples.append(delta)

	if _samples.size() < _sample_frames:
		return false

	_report()
	return true


func _report() -> void:
	_samples.sort()

	var total := 0.0
	for sample in _samples:
		total += sample

	var mean := total / float(_samples.size())
	var p95: float = _samples[int(float(_samples.size()) * 0.95)]
	var worst: float = _samples[_samples.size() - 1]

	var alive := 0
	for child in _game.spawner.get_children():
		if child is Zombie and not child.is_queued_for_deletion():
			alive += 1

	print("")
	print("LAST MAGAZINE — performance")
	print("=".repeat(62))
	print("zombies alive      %d" % alive)
	print("frames sampled     %d" % _samples.size())
	print("mean               %.2f ms  (%.0f fps)" % [mean * 1000.0, 1.0 / mean])
	print("95th percentile    %.2f ms  (%.0f fps)" % [p95 * 1000.0, 1.0 / p95])
	print("worst frame        %.2f ms  (%.0f fps)" % [worst * 1000.0, 1.0 / worst])
	print("draw calls         %d" % Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
	))
	print("primitives         %d" % Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
	))
	print("objects in frame   %d" % Performance.get_monitor(
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
	))
	print("video memory       %.1f MB" % (
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	))
	print("physics time       %.2f ms" % (
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	))
	print("=".repeat(62))

	root.remove_child(_game)
	_game.free()
	_game = null
	quit(0)
