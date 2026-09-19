class_name Arena
extends NavigationRegion3D

## Builds the play space procedurally: floor, perimeter walls, cover obstacles,
## and the spawn ring zombies enter from. Geometry is generated rather than
## hand-placed so the layout can be re-tuned by changing exported values, and so
## the navigation mesh is always baked against the geometry that actually exists.

@export_group("Dimensions")
@export var arena_size := 44.0
@export var wall_height := 6.0
@export var wall_thickness := 1.0

@export_group("Obstacles")
@export var obstacle_count := 14
@export var obstacle_min_size := Vector3(1.6, 1.2, 1.6)
@export var obstacle_max_size := Vector3(4.5, 3.4, 4.5)
## Obstacles are kept out of this radius so the player never spawns inside cover.
@export var center_clearance := 6.0

@export_group("Spawning")
@export var spawn_point_count := 10
## How far inside the walls zombies appear.
@export var spawn_inset := 3.5

@export_group("Generation")
## Fixed so the arena is identical every run — players learn one layout.
@export var generation_seed := 20260919

var spawn_points: Array[Vector3] = []

var _obstacle_bounds: Array[AABB] = []
var _rng := RandomNumberGenerator.new()

@onready var _floor_material := _make_material(Color(0.13, 0.13, 0.16), 0.9)
@onready var _wall_material := _make_material(Color(0.09, 0.09, 0.12), 0.85)
@onready var _obstacle_material := _make_material(Color(0.22, 0.20, 0.17), 0.75)


func _ready() -> void:
	_rng.seed = generation_seed
	_build_floor()
	_build_walls()
	_build_obstacles()
	_build_spawn_points()
	_bake()


## Half-extent of the playable floor, minus wall thickness.
func get_play_radius() -> float:
	return arena_size * 0.5 - wall_thickness


## A random spawn position, biased away from the player so zombies do not
## materialise on top of them.
func pick_spawn_point(away_from: Vector3, minimum_distance: float) -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO

	var candidates: Array[Vector3] = spawn_points.filter(
		func(point: Vector3) -> bool:
			return point.distance_to(away_from) >= minimum_distance
	)
	if candidates.is_empty():
		candidates = spawn_points

	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(arena_size, arena_size)
	mesh.mesh = plane
	mesh.material_override = _floor_material
	body.add_child(mesh)

	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(arena_size, wall_thickness, arena_size)
	collider.shape = box
	collider.position = Vector3(0.0, -wall_thickness * 0.5, 0.0)
	body.add_child(collider)

	add_child(body)


func _build_walls() -> void:
	var half := arena_size * 0.5
	var offsets := [
		Vector3(0.0, wall_height * 0.5, -half),
		Vector3(0.0, wall_height * 0.5, half),
		Vector3(-half, wall_height * 0.5, 0.0),
		Vector3(half, wall_height * 0.5, 0.0),
	]
	var sizes := [
		Vector3(arena_size + wall_thickness, wall_height, wall_thickness),
		Vector3(arena_size + wall_thickness, wall_height, wall_thickness),
		Vector3(wall_thickness, wall_height, arena_size + wall_thickness),
		Vector3(wall_thickness, wall_height, arena_size + wall_thickness),
	]

	for i in offsets.size():
		_add_box("Wall%d" % i, offsets[i], sizes[i], _wall_material)


func _build_obstacles() -> void:
	var placement_limit := get_play_radius() - 2.0
	var attempts := 0

	while _obstacle_bounds.size() < obstacle_count and attempts < obstacle_count * 40:
		attempts += 1

		var size := Vector3(
			_rng.randf_range(obstacle_min_size.x, obstacle_max_size.x),
			_rng.randf_range(obstacle_min_size.y, obstacle_max_size.y),
			_rng.randf_range(obstacle_min_size.z, obstacle_max_size.z)
		)
		var position := Vector3(
			_rng.randf_range(-placement_limit, placement_limit),
			size.y * 0.5,
			_rng.randf_range(-placement_limit, placement_limit)
		)

		if Vector2(position.x, position.z).length() < center_clearance:
			continue

		# Padding keeps a walkable gap between obstacles so the navmesh stays
		# connected and zombies cannot wedge themselves in a crevice.
		var candidate := AABB(position - size * 0.5, size).grow(1.5)
		var overlaps := _obstacle_bounds.any(
			func(existing: AABB) -> bool: return existing.intersects(candidate)
		)
		if overlaps:
			continue

		_obstacle_bounds.append(candidate)
		_add_box("Obstacle%d" % _obstacle_bounds.size(), position, size, _obstacle_material)


func _build_spawn_points() -> void:
	spawn_points.clear()
	var radius := get_play_radius() - spawn_inset

	for i in spawn_point_count:
		var angle := TAU * float(i) / float(spawn_point_count)
		var candidate := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

		# Nudge inward until the point is clear of cover, so zombies never spawn
		# inside a crate.
		var pullback := 0.0
		while pullback < radius * 0.6 and _is_blocked(candidate):
			pullback += 1.0
			candidate = Vector3(
				cos(angle) * (radius - pullback), 0.0, sin(angle) * (radius - pullback)
			)

		if not _is_blocked(candidate):
			spawn_points.append(candidate)


func _is_blocked(point: Vector3) -> bool:
	var probe := AABB(point - Vector3(0.5, 0.0, 0.5), Vector3(1.0, 2.0, 1.0))
	return _obstacle_bounds.any(func(bounds: AABB) -> bool: return bounds.intersects(probe))


func _add_box(node_name: String, position: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = material
	body.add_child(mesh)

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)

	add_child(body)


func _bake() -> void:
	var nav_mesh := NavigationMesh.new()
	# Agent dimensions are exact multiples of cell_size, otherwise the baker
	# rounds them to voxel units and the mesh no longer matches these values.
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_max_climb = 0.5
	# Must match the navigation map cell size (project default 0.25), otherwise
	# the mesh rasterises against a different grid than the one agents query.
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	navigation_mesh = nav_mesh

	# Synchronous bake — zombies query the mesh on the first frame, so it has to
	# exist before _ready() returns.
	bake_navigation_mesh(false)


func _make_material(albedo: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = 0.05
	return material
