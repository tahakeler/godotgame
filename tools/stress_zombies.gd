extends SceneTree

## Puts a zombie on every spawn point at once and watches whether each one
## actually gets to the player.
##
## `tests/manual/verify_zombies.gd` already asks whether zombies pursue, but it
## samples whichever handful the director happened to spawn. That passes even
## when one wing of the map is unreachable, because the director never picked a
## point there. This covers every spawn point deliberately, which is the check
## worth having after the layout changes: a navmesh that bakes but does not
## connect leaves zombies milling in their chamber forever and reports no error
## anywhere.
##
## It doubles as a load test. Every spawn point at once is far more zombies
## than a round ever holds, so the frame time printed at the end is a worst
## case rather than a typical one.
##
##   Godot --headless --script tools/stress_zombies.gd -- --seconds=25

const GAME_SCENE := "res://src/core/game.tscn"

## How close counts as having arrived. Zombies stop at attack range, so this is
## a little more than that.
const ARRIVAL_DISTANCE := 3.5

## A zombie that closes less than this over the whole run never really tried.
const REQUIRED_APPROACH := 5.0

## Movement below this over the stuck window means it is wedged on something.
const STUCK_WINDOW := 6.0
const STUCK_MOVEMENT := 1.0

var _game: Game
var _seconds := 25.0
var _elapsed := 0.0
var _started := false
var _tracked: Array[Dictionary] = []
var _frame_times: Array[float] = []
var _problems: Array[String] = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			_seconds = float(argument.split("=")[1])

	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		DeterministicSettings.apply(root)
		_game.start_round()
		_populate()
		return false

	_elapsed += delta
	_frame_times.append(delta)
	_sample()

	if _elapsed < _seconds:
		return false

	_report()
	return true


## One zombie of a known kind on each spawn point, with the director switched
## off so it cannot add more and muddy the count.
func _populate() -> void:
	var spawner := _game.spawner
	spawner.stop()
	spawner.clear_all()

	var player := _game.player
	var kinds: Array = ZombieTypes.Kind.values()

	for index in _game.arena.spawn_points.size():
		var point: Vector3 = _game.arena.spawn_points[index]

		var zombie: Zombie = spawner.zombie_scene.instantiate()
		spawner.add_child(zombie)

		# Configure before positioning: the kind resizes the capsule, and a
		# Brute placed first spends its first frame half inside the floor.
		var kind: int = kinds[index % kinds.size()]
		zombie.configure(kind)
		zombie.global_position = point + Vector3.UP * 0.1
		zombie.set_target(player)

		# Woken deliberately. An unaware zombie is supposed to stand around, so
		# leaving them asleep would measure the wrong thing entirely.
		zombie.hear_noise(player.global_position, 4.0)

		_tracked.append({
			"zombie": zombie,
			"index": index,
			"spawn": point,
			"kind": kind,
			"start": point.distance_to(player.global_position),
			"closest": point.distance_to(player.global_position),
			"last_move_at": 0.0,
			"last_position": point,
			"stuck_for": 0.0,
		})

	print("tracking %d zombies, one per spawn point, for %.0fs" % [
		_tracked.size(), _seconds
	])


func _sample() -> void:
	var player := _game.player

	for entry in _tracked:
		var zombie: Zombie = entry.zombie
		if not is_instance_valid(zombie) or zombie.health.is_dead:
			continue

		var at := zombie.global_position
		var distance := at.distance_to(player.global_position)
		entry.closest = minf(entry.closest, distance)

		if at.distance_to(entry.last_position) > STUCK_MOVEMENT:
			entry.last_position = at
			entry.stuck_for = 0.0
		else:
			entry.stuck_for = _elapsed - entry.last_move_at

		if at.distance_to(entry.last_position) > STUCK_MOVEMENT:
			entry.last_move_at = _elapsed


func _report() -> void:
	var arrived := 0
	var approached := 0
	var stuck: Array[String] = []
	var never_moved: Array[String] = []

	for entry in _tracked:
		var closed: float = entry.start - entry.closest
		var label := "spawn %d (%s) at (%.0f, %.0f)" % [
			entry.index, _kind_name(entry.kind), entry.spawn.x, entry.spawn.z
		]

		if entry.closest <= ARRIVAL_DISTANCE:
			arrived += 1
			approached += 1
		elif closed >= REQUIRED_APPROACH:
			approached += 1
		elif closed < 1.0:
			never_moved.append("%s closed %.1fm of %.0fm" % [label, closed, entry.start])
		else:
			stuck.append(
				"%s only closed %.1fm of %.0fm" % [label, closed, entry.start]
			)

	print("")
	print("--- pursuit over %.0fs ---" % _elapsed)
	print("  reached the player:   %d / %d" % [arrived, _tracked.size()])
	print("  closed meaningfully:  %d / %d" % [approached, _tracked.size()])

	if not never_moved.is_empty():
		print("")
		print("  never got going:")
		for note in never_moved:
			print("    %s" % note)
		_problems.append(
			"%d zombies never left their spawn — those chambers are cut off from "
			% never_moved.size() + "the navmesh"
		)

	if not stuck.is_empty():
		print("")
		print("  made partial progress then stopped:")
		for note in stuck:
			print("    %s" % note)

	_report_frame_time()

	print("")
	if _problems.is_empty():
		print("stress: every spawn point can reach the player")
		quit(0)
		return

	for problem in _problems:
		printerr("FAIL: %s" % problem)
	quit(1)


## Worst-case frame time, since this holds far more zombies than a round does.
func _report_frame_time() -> void:
	if _frame_times.is_empty():
		return

	var total := 0.0
	var worst := 0.0
	for time in _frame_times:
		total += time
		worst = maxf(worst, time)

	var mean := total / float(_frame_times.size())
	print("")
	print("--- frame time with %d zombies alive ---" % _tracked.size())
	print("  mean %.2fms, worst %.2fms (budget 16.60ms)" % [mean * 1000.0, worst * 1000.0])


func _kind_name(kind: int) -> String:
	var names: Array = ZombieTypes.Kind.keys()
	return str(names[kind]) if kind < names.size() else "?"
