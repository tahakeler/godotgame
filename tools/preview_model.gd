extends SceneTree

## Dev tool: renders one or more models from above so modular pieces can be
## inspected — specifically where their wall openings sit, which the bounding
## box does not tell you. Must run WITHOUT --headless.
##
##   Godot --path . --script tools/preview_model.gd --resolution 1100x1100 \
##       -- --models=res://assets/models/cave/room-large.glb --out=res://preview.png

var _model_paths: Array[String] = []
var _output_path := "res://preview.png"
var _height := 34.0
var _angle := -90.0
var _size := 0.0
var _spacing := 26.0
var _frames := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--models="):
			for path in argument.trim_prefix("--models=").split(",", false):
				_model_paths.append(path)
		elif argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--height="):
			_height = float(argument.trim_prefix("--height="))
		elif argument.begins_with("--angle="):
			_angle = float(argument.trim_prefix("--angle="))
		elif argument.begins_with("--size="):
			_size = float(argument.trim_prefix("--size="))
		elif argument.begins_with("--spacing="):
			_spacing = float(argument.trim_prefix("--spacing="))

	_build_lighting()

	# Lay the pieces out in a row so several can be compared in one image.
	var offset := 0.0
	for path in _model_paths:
		var scene: PackedScene = load(path)
		if scene == null:
			printerr("FAIL: could not load %s" % path)
			continue

		var instance: Node3D = scene.instantiate()
		root.add_child(instance)
		instance.position = Vector3(offset, 0.0, 0.0)
		offset += _spacing

	_build_camera(offset)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false

	var image := root.get_texture().get_image()
	image.save_png(_output_path)
	print("CAPTURED %s" % _output_path)
	quit(0)
	return true


func _build_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.1, 0.11, 0.15)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.82, 0.9)
	environment.ambient_light_energy = 1.4

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-62.0, -38.0, 0.0)
	light.light_energy = 1.4
	root.add_child(light)


func _build_camera(span: float) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _size if _size > 0.0 else maxf(span, 26.0)
	camera.position = Vector3(maxf(span - _spacing, 0.0) * 0.5, _height, 0.01)
	camera.rotation_degrees = Vector3(_angle, 0.0, 0.0)
	if not is_equal_approx(_angle, -90.0):
		camera.position.z = _height * 0.9
	camera.current = true
	root.add_child(camera)
