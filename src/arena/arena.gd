class_name Arena
extends NavigationRegion3D

## The play space, assembled from Kenney Modular Cave Kit pieces (CC0).
##
## The kit is built on a 4-unit grid: every piece is centred on its own origin,
## rooms are 12x12 or 20x20, and corridors are 4x4.
##
## The constraint that shapes everything here: the kit's rooms open on two
## opposite walls only. The indentations on the other two walls look like
## doorways from above but are solid rock, so a room can never be a junction.
## Branching is done with corridor-intersection, which is genuinely open on all
## four sides, and rooms always sit inline along a run.
##
## Layout: a 20x20 arena at the centre, a spine running north and south to a
## crossroads, and east/west arms off each crossroads threading two chambers
## each — eleven rooms in all, with ten chambers zombies spawn from.
##
## Collision is generated from the imported meshes. Navigation is not: see
## _add_nav_surface for why the cave's own floors cannot be used.

const CAVE_PATH := "res://assets/models/cave/%s.glb"
const PROP_PATH := "res://assets/models/weapons/%s.glb"

## Grid unit of the cave kit. Every placement below is a multiple of this.
const CELL := 4.0

const CENTRE_ROOM := "room-large"
const OUTER_ROOM := "room-small"
const CORRIDOR := "corridor"
const HUB := "corridor-intersection"

## Cell of the crossroads on each spine, where the side arms branch off.
const HUB_CELL := 5
## Cell of the chamber that caps each spine.
const SPINE_END_CELL := 9
## Cells of the two chambers along each side arm.
const ARM_ROOM_CELLS := [4, 9]

## Nodes in this group are the *only* geometry the navmesh is baked from.
const NAV_SOURCE_GROUP := "navmesh_source"

## Walkable footprints, kept strictly inside the walls of the piece they sit in.
const NAV_CENTRE_SIZE := 17.0
const NAV_ROOM_SIZE := 9.0
const NAV_CORRIDOR_WIDTH := 2.6
const NAV_HUB_SIZE := 3.0
## Corridor strips run long so they overlap their neighbours and the rooms.
const NAV_CORRIDOR_LENGTH := 8.0
## Slightly above the sculpted floor, which varies by a few centimetres.
const NAV_HEIGHT := 0.05

## Rock formations used as cover in the central room. Scaled below full wall
## height so they break sightlines without turning the arena into a maze — the
## concept's anti-pillars rule out anything that makes turtling viable.
const COVER := [
	{"position": Vector3(-6.0, 0, -4.5), "rotation": 18, "scale": 0.62},
	{"position": Vector3(6.5, 0, 4.0), "rotation": -110, "scale": 0.7},
	{"position": Vector3(5.5, 0, -6.5), "rotation": 65, "scale": 0.55},
	{"position": Vector3(-6.5, 0, 6.0), "rotation": -40, "scale": 0.66},
	{"position": Vector3(-1.5, 0, 7.8), "rotation": 140, "scale": 0.5},
	{"position": Vector3(2.0, 0, -8.0), "rotation": -75, "scale": 0.58},
]

## Flat weapon cases from the Kenney Blaster Kit (CC0), as floor dressing.
## They are 0.23m tall, so they are scenery rather than cover.
const PROPS := [
	{"model": "crate-wide", "position": Vector3(3.2, 0, 2.4), "rotation": 24},
	{"model": "crate-medium", "position": Vector3(-3.6, 0, 1.6), "rotation": -52},
	{"model": "crate-small", "position": Vector3(1.2, 0, -3.4), "rotation": 88},
]

@export var generation_seed := 20260919
## The main menu uses this scene purely as a backdrop and has nothing to
## navigate, so it can skip the bake.
@export var bake_navigation := true

@export_group("Ceiling")
## A roof closes the cave in. Without it the player sees over the walls into
## empty space, which reads as an unfinished level rather than a cave.
@export var ceiling_enabled := true
@export var ceiling_height := 4.15

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

	# Added after baking on purpose: the ceiling is a large flat surface, and
	# the navmesh generator would happily carpet the top of it.
	if ceiling_enabled:
		_build_ceiling()


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


## The kit's rooms open on two opposite walls only — the indentations on the
## other two are decorative, and a corridor placed against one is a corridor
## into solid rock. So rooms always sit inline in a run, and every branch is a
## corridor-intersection, which is genuinely open on all four sides.
func _build_layout() -> void:
	_place(CENTRE_ROOM, Vector2i(0, 0), 0)

	# Two spines north and south of the arena, since room-large opens that way.
	for direction: int in [-1, 1]:
		_build_spine(direction)
		_build_arms(direction)


## Arena -> corridors -> crossroads -> corridors -> end chamber.
func _build_spine(direction: int) -> void:
	for distance in [3, 4]:
		_place(CORRIDOR, Vector2i(0, distance * direction), 90)

	_place(HUB, Vector2i(0, HUB_CELL * direction), 0)

	for distance in [6, 7]:
		_place(CORRIDOR, Vector2i(0, distance * direction), 90)

	_place(OUTER_ROOM, Vector2i(0, SPINE_END_CELL * direction), 0)


## East and west arms leaving each crossroads, each threading two chambers.
## Rooms are rotated a quarter turn so their openings face along the arm.
func _build_arms(direction: int) -> void:
	var row: int = HUB_CELL * direction

	for side: int in [-1, 1]:
		for distance in [1, 2, 6, 7]:
			_place(CORRIDOR, Vector2i(distance * side, row), 0)

		for room_distance in ARM_ROOM_CELLS:
			_place(OUTER_ROOM, Vector2i(room_distance * side, row), 90)


func _place(model: String, cell: Vector2i, rotation_degrees: float) -> void:
	var instance := _instantiate(CAVE_PATH % model)
	if instance == null:
		return

	instance.position = _cell_to_world(cell)
	instance.rotation.y = deg_to_rad(rotation_degrees)
	instance.name = "%s_%d_%d" % [model, cell.x, cell.y]
	_geometry_root.add_child(instance)
	_add_collision(instance)

	var footprint := Vector2(NAV_CORRIDOR_WIDTH, NAV_CORRIDOR_LENGTH)

	if model == CENTRE_ROOM:
		footprint = Vector2(NAV_CENTRE_SIZE, NAV_CENTRE_SIZE)
	elif model == OUTER_ROOM:
		footprint = Vector2(NAV_ROOM_SIZE, NAV_ROOM_SIZE)
	elif model == HUB:
		footprint = Vector2(NAV_HUB_SIZE, NAV_HUB_SIZE)
	elif is_zero_approx(rotation_degrees):
		# An unrotated corridor runs along X; rotating it a quarter turn runs it
		# along Z. The piece reads the opposite way round from what its footprint
		# suggests, which is what blocked every route until it was checked.
		footprint = Vector2(NAV_CORRIDOR_LENGTH, NAV_CORRIDOR_WIDTH)

	_add_nav_surface(cell, footprint)
	_add_lighting(model, cell)


## Light every piece as it is placed, so lighting scales with the layout
## instead of being hand-placed for one that no longer exists.
##
## Rooms are lit warm and corridors cold. The contrast is the point: a single
## colour temperature across a whole level reads flat no matter how bright it
## is, whereas warm pools separated by cold runs give the eye depth and make
## each chamber feel like somewhere rather than more of the same.
func _add_lighting(model: String, cell: Vector2i) -> void:
	var light := OmniLight3D.new()
	light.position = _cell_to_world(cell) + Vector3.UP * 3.3
	light.shadow_enabled = false

	match model:
		CENTRE_ROOM:
			light.light_color = Color(1.0, 0.79, 0.52)
			light.light_energy = 7.0
			light.omni_range = 22.0
			# Only the arena casts shadows; the cost is worth it where the
			# player actually fights, and invisible everywhere else.
			light.shadow_enabled = true
			light.position.y = 4.0
		OUTER_ROOM:
			light.light_color = Color(1.0, 0.7, 0.42)
			light.light_energy = 5.0
			light.omni_range = 15.0
		HUB:
			light.light_color = Color(0.45, 0.68, 1.0)
			light.light_energy = 3.5
			light.omni_range = 11.0
		_:
			light.light_color = Color(0.42, 0.62, 1.0)
			light.light_energy = 2.0
			light.omni_range = 8.0
			light.position.y = 3.0

	_geometry_root.add_child(light)
	_add_lamp_glow(light)


## A small emissive block at each light, so the glow has a visible source
## rather than appearing to come from nowhere.
func _add_lamp_glow(light: OmniLight3D) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.12, 0.35)
	mesh_instance.mesh = box
	mesh_instance.position = light.position + Vector3.UP * 0.35

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = light.light_color
	material.emission_enabled = true
	material.emission = light.light_color
	material.emission_energy_multiplier = 4.0
	mesh_instance.material_override = material

	_geometry_root.add_child(mesh_instance)


## Flat walkable footprint for one piece, used as navmesh source geometry.
##
## The navmesh is baked from these rather than from the cave itself. The kit's
## floors are sculpted rock, and recast slices them into disconnected strips:
## rooms bake solid, corridors bake as rungs, and no path exists between them,
## so zombies never leave the chamber they spawn in. Nothing reports an error.
##
## Describing the walkable space directly makes the result predictable, and the
## overlap between neighbouring footprints guarantees the graph is connected.
## Each footprint stays well inside its piece's walls, because with explicit
## source geometry the walls no longer carve the mesh themselves.
func _add_nav_surface(cell: Vector2i, footprint: Vector2) -> void:
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = footprint
	mesh_instance.mesh = plane
	mesh_instance.position = _cell_to_world(cell) + Vector3.UP * NAV_HEIGHT
	mesh_instance.visible = false
	mesh_instance.name = "NavSurface_%d_%d" % [cell.x, cell.y]

	_geometry_root.add_child(mesh_instance)
	mesh_instance.add_to_group(NAV_SOURCE_GROUP)


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


func _build_ceiling() -> void:
	# Reaches past the furthest chamber so no edge is ever visible from inside.
	var extent := (float(SPINE_END_CELL) * CELL + 16.0) * 2.0

	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	# Flipped to face down into the cave.
	plane.orientation = PlaneMesh.FACE_Y
	mesh_instance.mesh = plane
	mesh_instance.position = Vector3(0.0, ceiling_height, 0.0)
	mesh_instance.rotation_degrees = Vector3(180.0, 0.0, 0.0)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.28, 0.25)
	material.roughness = 1.0
	# Double-sided so the roof cannot vanish if the plane ends up facing up.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	mesh_instance.name = "Ceiling"

	add_child(mesh_instance)


## Zombies enter from the outer chambers, so pressure arrives from every
## bearing and never from inside the room the player is standing in.
func _build_spawn_points() -> void:
	spawn_points.clear()

	for direction: int in [-1, 1]:
		var row: int = HUB_CELL * direction
		spawn_points.append(_cell_to_world(Vector2i(0, SPINE_END_CELL * direction)) + Vector3.UP * 0.2)

		for side: int in [-1, 1]:
			for room_distance in ARM_ROOM_CELLS:
				spawn_points.append(
					_cell_to_world(Vector2i(room_distance * side, row)) + Vector3.UP * 0.2
				)


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
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	# Only the flat footprints above, never the cave geometry.
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nav_mesh.geometry_source_group_name = NAV_SOURCE_GROUP
	navigation_mesh = nav_mesh

	# Synchronous — zombies query the mesh on their first frame.
	bake_navigation_mesh(false)
