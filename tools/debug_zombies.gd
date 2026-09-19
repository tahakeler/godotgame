extends SceneTree

## Dev tool: dumps what each zombie's navigation agent is actually doing —
## where it is, where the agent wants it to go, and whether it is moving.
## Distinguishes "no path" from "has a path but cannot physically travel it".

const GAME_SCENE := "res://src/core/game.tscn"
const REPORT_AT := [2.0, 5.0, 9.0]

var _game: Game
var _elapsed := 0.0
var _configured := false
var _reported := 0


func _initialize() -> void:
	var scene: PackedScene = load(GAME_SCENE)
	_game = scene.instantiate()
	root.add_child(_game)


func _process(delta: float) -> bool:
	if _game == null or _game.spawner == null:
		return false

	if not _configured:
		_configured = true
		_game.spawner.grace_period = 0.0
		_game.spawner.initial_interval = 0.5

	_elapsed += delta

	if _reported < REPORT_AT.size() and _elapsed >= REPORT_AT[_reported]:
		_dump("t=%.1fs" % _elapsed)
		_reported += 1

	if _reported >= REPORT_AT.size():
		root.remove_child(_game)
		_game.free()
		_game = null
		quit(0)
		return true

	return false


func _dump(label: String) -> void:
	var player_position: Vector3 = _game.player.global_position
	print("--- %s  player=%v ---" % [label, player_position])

	for child in _game.spawner.get_children():
		if not (child is Zombie) or child.is_queued_for_deletion():
			continue

		var zombie: Zombie = child
		var agent: NavigationAgent3D = zombie.get_node("NavigationAgent3D")
		var next_position := agent.get_next_path_position()

		var blocker := "none"
		for index in zombie.get_slide_collision_count():
			var collision := zombie.get_slide_collision(index)
			var normal := collision.get_normal()
			# Near-horizontal normals mean a wall; report what it belongs to.
			if absf(normal.y) < 0.7:
				var collider := collision.get_collider()
				blocker = "%s n=(%.2f,%.2f,%.2f)" % [
					collider.name if collider != null else "?",
					normal.x, normal.y, normal.z
				]
				break

		print("  wall=%s blocker=%s" % [str(zombie.is_on_wall()), blocker])
		print("  pos=%.1f,%.1f,%.1f  next=%.1f,%.1f,%.1f  step=%.2f  vel=%.2f  dist=%.1f  reachable=%s  finished=%s  floor=%s" % [
			zombie.global_position.x, zombie.global_position.y, zombie.global_position.z,
			next_position.x, next_position.y, next_position.z,
			zombie.global_position.distance_to(next_position),
			Vector2(zombie.velocity.x, zombie.velocity.z).length(),
			zombie.global_position.distance_to(player_position),
			str(agent.is_target_reachable()),
			str(agent.is_navigation_finished()),
			str(zombie.is_on_floor()),
		])
