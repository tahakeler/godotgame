class_name Arena
extends NavigationRegion3D

## The play space, assembled from Kenney Modular Cave Kit pieces (CC0).
##
## The kit is built on a 4-unit grid: every piece is centred on its own origin,
## rooms are 12x12 or 20x20, corridors are 4x4, and each room wall carries a
## one-cell door opening at its midpoint. The layout table below places pieces
## on that grid — a central arena with four side chambers, so the horde can
## arrive from any bearing instead of funnelling down a single route.
##
## Collision and navigation are both generated from the imported meshes; the
## kit ships neither.

const CAVE_PATH := "res://assets/models/cave/%s.glb"
const PROP_PATH := "res://assets/models/weapons/%s.glb"

## Grid unit of the cave kit. Every placement below is a multiple of this.
const CELL := 4.0

## model, grid position in cells, y-rotation in degrees.
const LAYOUT := [
	{"model": "room-large", "cell": Vector2i(0, 0), "rotation": 0},

	{"model": "corridor", "cell": Vector2i(0, -3), "rotation": 0},
	{"model": "room-small", "cell": Vector2i(0, -5), "rotation": 0},

	{"model": "corridor", "cell": Vector2i(0, 3), "rotation": 0},
	{"model": "room-small", "cell": Vector2i(0, 5), "rotation": 0},

	{"model": "corridor", "cell": Vector2i(3, 0), "rotation": 90},
	{"model": "room-small", "cell": Vector2i(5, 0), "rotation": 90},

	{"model": "corridor", "cell": Vector2i(-3, 0), "rotation": 90},
	{"model": "room-small", "cell": Vector2i(-5, 0), "rotation": 90},
]

## Rock formations used as cover in the central room, from the cave kit. Scaled
## below full wall height so they break sightlines without turning the arena
## into a maze — the concept's anti-pillar rules out anything that makes
## turtling viable.
const COVER := [
	{"position": Vector3(-6.0, 0, -4.5), "rotation": 18, "scale": 0.62},
	{"position": Vector3(6.5, 0, 4.0), "rotation": -110, "scale": 0.7},
	{"position": Vector3(5.5, 0, -6.5), "rotation": 65, "scale": 0.55},
	{"position": Vector3(-6.5, 0, 6.0), "rotation": -40, "scale": 0.66},
	{"position": Vector3(-1.5, 0, 7.8), "rotation": 140, "scale": 0.5},
	{"position": Vector3(2.0, 0, -8.0), "rotation": -75, "scale": 0.58},
]

## Flat weapon cases from the Kenney Blaster Kit (CC0), used as floor dressing.
## They are 0.23m tall, so they are set dressing rather than cover.
const PROPS := [
	{"model": "crate-wide", "position": Vector3(3.2, 0, 2.4), "rotation": 24},
	{"model": "crate-medium", "position": Vector3(-3.6, 0, 1.6), "rotation": -52},
	{"model": "crate-small", "position": Vector3(1.2, 0, -3.4), "rotation": 88},
]

## Where zombies enter. Side chambers and corridor mouths, so pressure arrives
## from several bearings at once.
const SPAWN_CELLS := [
	Vector2i(0, -5), Vector2i(0, 5), Vector2i(5, 0), Vector2i(-5, 0),
	Vector2i(0, -3), Vector2i(0, 3), Vector2i(3, 0), Vector2i(-3, 0),
]

@export var generation_seed := 20260919
## The main menu uses this scene purely as a backdrop and has nothing to
## navigate, so it can skip the bake.
@export var bake_navigation := true

var spawn_points: Array[Vector3] = []

var _rng := RandomNumberGenerator.new()
var _geometry_root: Node3D


func _ready() -> void:
	_rng.seed = generation_seed

	_geometry_root = Node3D.new()
	_geometry_root.name = "Geometry"
	add_child(_geometry_root)

	_build_layout()
	_build_cover()
	_build_props()
	_build_spawn_points()
	if bake_navigation:
		_bake()


## Half-extent of the central room.
func get_play_radius() -> float:
	return 10.0


## A spawn position biased away from the player, so zombies never appear on
## top of them.
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


func _build_layout() -> void:
	for entry in LAYOUT:
		var instance := _instantiate(CAVE_PATH % entry.model)
		if instance == null:
			continue

		instance.position = _cell_to_world(entry.cell)
		instance.rotation.y = deg_to_rad(entry.rotation)
		instance.name = "%s_%d_%d" % [entry.model, entry.cell.x, entry.cell.y]
		_geometry_root.add_child(instance)
		_add_collision(instance)


func _build_cover() -> void:
	for entry in COVER:
		var instance := _instantiate(CAVE_PATH % "template-detail")
		if instance == null:
			continue

		instance.position = entry.position
		instance.rotation.y = deg_to_rad(entry.rotation)
		instance.scale = Vector3.ONE * entry.scale
		instance.name = "Cover"
		_geometry_root.add_child(instance)
		_add_collision(instance)


func _build_props() -> void:
	for entry in PROPS:
		var instance := _instantiate(PROP_PATH % entry.model)
		if instance == null:
			continue

		instance.position = entry.position
		instance.rotation.y = deg_to_rad(entry.rotation)
		_geometry_root.add_child(instance)
		_add_collision(instance)


func _build_spawn_points() -> void:
	spawn_points.clear()
	for cell in SPAWN_CELLS:
		spawn_points.append(_cell_to_world(cell) + Vector3.UP * 0.2)


func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * CELL, 0.0, float(cell.y) * CELL)


func _instantiate(path: String) -> Node3D:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("Arena: could not load %s" % path)
		return null
	return scene.instantiate()


## The kit ships no collision shapes, so build static trimesh bodies from the
## imported meshes. Trimesh is correct here because every piece is static level
## geometry that never moves.
func _add_collision(node: Node) -> void:
	for mesh_instance in _find_mesh_instances(node):
		mesh_instance.create_trimesh_collision()


func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []

	if node is MeshInstance3D and node.mesh != null:
		found.append(node)

	for child in node.get_children():
		found.append_array(_find_mesh_instances(child))

	return found


func _bake() -> void:
	var nav_mesh := NavigationMesh.new()
	# Agent dimensions must be exact multiples of cell_size, or the baker rounds
	# them to voxel units and the mesh stops matching these values.
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_max_climb = 0.5
	# Must match the navigation map cell size (project default 0.25), otherwise
	# the mesh rasterises against a different grid than the one agents query.
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	# Parse meshes rather than colliders: create_trimesh_collision() attaches
	# its bodies deferred, so they are not reliably in the tree at bake time.
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	navigation_mesh = nav_mesh

	# Synchronous — zombies query the mesh on their first frame.
	bake_navigation_mesh(false)
