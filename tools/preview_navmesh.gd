extends SceneTree

## Dev tool: renders the baked navigation mesh as flat geometry from above, so
## disconnected islands are visible. Polygon count tells you a bake happened;
## only looking at the shape tells you whether zombies can actually get
## anywhere. Must run WITHOUT --headless.
##
##   Godot --path . --script tools/preview_navmesh.gd --resolution 1100x1100

const ARENA_SCENE := "res://src/arena/arena.tscn"

var _arena: Arena
var _frames := 0
var _output_path := "res://navmesh.png"
var _size := 72.0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--size="):
			_size = float(argument.trim_prefix("--size="))

	var scene: PackedScene = load(ARENA_SCENE)
	_arena = scene.instantiate()
	# The cave geometry would hide the navmesh; only the mesh itself matters.
	_arena.ceiling_enabled = false
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	if _frames == 3:
		_hide_cave_geometry()
		_draw_navmesh()
		_build_camera()
		return false

	if _frames < 8:
		return false

	root.get_texture().get_image().save_png(_output_path)
	print("CAPTURED %s (%d polygons)" % [
		_output_path, _arena.navigation_mesh.get_polygon_count()
	])
	quit(0)
	return true


func _hide_cave_geometry() -> void:
	var geometry: Node = _arena.get_node_or_null("Geometry")
	if geometry != null:
		geometry.visible = false


## Build one flat surface per navmesh polygon, lifted clear of the floor.
func _draw_navmesh() -> void:
	var nav_mesh: NavigationMesh = _arena.navigation_mesh
	var vertices := nav_mesh.get_vertices()

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for index in nav_mesh.get_polygon_count():
		var polygon := nav_mesh.get_polygon(index)

		# Fan-triangulate; navmesh polygons are convex.
		for corner in range(1, polygon.size() - 1):
			surface.add_vertex(vertices[polygon[0]])
			surface.add_vertex(vertices[polygon[corner]])
			surface.add_vertex(vertices[polygon[corner + 1]])

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.25, 0.9, 0.55)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface.commit()
	mesh_instance.material_override = material
	root.add_child(mesh_instance)


func _build_camera() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.04, 0.06)

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _size
	camera.position = Vector3(0.0, 40.0, 0.01)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true
	root.add_child(camera)
