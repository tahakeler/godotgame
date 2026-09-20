extends SceneTree

## Dev tool: photographs the arena from arbitrary vantage points.
##
## The in-game capture tool only ever shows the player's eye line, which is the
## worst angle for judging whether built geometry actually fits together — a
## ramp seen from its own foot is mostly foreshortening. This parks a free
## camera wherever you ask and looks at a point.
##
##   Godot --path . --script tools/survey.gd --resolution 1600x900 -- \
##       --from=0,26,26 --at=0,0,0 --out=res://survey.png

const ARENA_SCENE := "res://src/arena/arena.tscn"

var _from := Vector3(0.0, 26.0, 26.0)
var _at := Vector3.ZERO
var _out := "res://survey.png"
var _ceiling := false
var _frames := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--from="):
			_from = _parse(argument.trim_prefix("--from="))
		elif argument.begins_with("--at="):
			_at = _parse(argument.trim_prefix("--at="))
		elif argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument == "--ceiling":
			_ceiling = true

	var arena: Node3D = (load(ARENA_SCENE) as PackedScene).instantiate()
	# Nothing here needs to walk, and baking costs seconds per run.
	arena.bake_navigation = false
	# The roof is doing its job: from above, a surveyed arena is a black
	# rectangle. Lifted so the layout underneath can actually be photographed.
	arena.ceiling_enabled = _ceiling
	root.add_child(arena)

	# The cave lights point down into chambers and fade with distance, so from
	# a survey vantage the map is nearly black. A flat overhead light and a
	# lifted ambient make the geometry legible; this is a diagnostic, not a
	# beauty shot, and the real lighting is judged in-game.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, -38.0, 0.0)
	sun.light_energy = 1.35
	root.add_child(sun)

	var lift := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.03)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.56, 0.62)
	environment.ambient_light_energy = 1.1
	lift.environment = environment
	root.add_child(lift)

	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 60.0
	root.add_child(camera)
	camera.global_position = _from
	camera.look_at(_at, Vector3.UP)


func _process(_delta: float) -> bool:
	# Give the lights and the imported meshes a few frames to settle.
	_frames += 1
	if _frames < 40:
		return false

	var image := root.get_texture().get_image()
	if image.save_png(_out) != OK:
		printerr("FAIL: could not write %s" % _out)
		quit(1)
		return true

	print("SURVEYED %s from %v looking at %v" % [_out, _from, _at])
	quit(0)
	return true


func _parse(text: String) -> Vector3:
	var parts := text.split(",", false)
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
