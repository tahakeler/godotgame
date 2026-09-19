class_name Arena
extends NavigationRegion3D

## The play space, assembled from Kenney Modular Cave Kit pieces (CC0).
##
## The kit is built on a 4-unit grid: every piece is centred on its own origin,
## rooms are 12x12 or 20x20, and corridors are 4x4.
##
## Every piece opening was measured with tools/probe_openings.gd rather than
## read off a render: rooms open on all four sides, an unrotated corridor runs
## along X, and corridor-end caps a stub. Guessing any of that previously cost
## real time, so the layout below is built against measured fact.
##
## Layout: an irregular network of seven chambers around a central arena, with
## two uneven loops and a pair of dead-end alcoves.
##
## Neither collision nor navigation comes from the cave meshes. Collision is a
## box shell built from the walkable cells (see _build_collision_shell) and
## navigation is baked from flat footprints (see _add_nav_surface). Both exist
## because the sculpted rock is the wrong shape to derive either from.

const CAVE_PATH := "res://assets/models/cave/%s.glb"
const PROP_PATH := "res://assets/models/weapons/%s.glb"

## Grid unit of the cave kit. Every placement below is a multiple of this.
const CELL := 4.0

const CENTRE_ROOM := "room-large"
const OUTER_ROOM := "room-small"
const WIDE_ROOM := "room-wide"
const CORRIDOR := "corridor"
const DEAD_END := "corridor-end"

## Walkable footprint per piece, before rotation. Measured with
## tools/probe_openings.gd rather than guessed — every room in this kit opens
## on all four sides, while an unrotated corridor runs along X.
const FOOTPRINTS := {
	CENTRE_ROOM: Vector2(17.0, 17.0),
	OUTER_ROOM: Vector2(9.0, 9.0),
	WIDE_ROOM: Vector2(17.0, 9.0),
	CORRIDOR: Vector2(8.0, 2.6),
	DEAD_END: Vector2(5.0, 2.6),
}

## The cave network, as {model, cell, rotation}. Deliberately irregular: arms
## differ in length, chambers differ in size, and the two loops are not mirror
## images. A symmetric grid reads as a diagram; an uneven one reads as a place.
const LAYOUT := [
	# Central arena.
	{"model": CENTRE_ROOM, "cell": Vector2i(0, 0), "rotation": 0},

	# North run to a small chamber.
	{"model": CORRIDOR, "cell": Vector2i(0, 3), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(0, 4), "rotation": 90},
	{"model": OUTER_ROOM, "cell": Vector2i(0, 6), "rotation": 0},

	# Short east run into the long hall.
	{"model": CORRIDOR, "cell": Vector2i(3, 0), "rotation": 0},
	{"model": WIDE_ROOM, "cell": Vector2i(6, 0), "rotation": 0},

	# Long west run.
	{"model": CORRIDOR, "cell": Vector2i(-3, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-4, 0), "rotation": 0},
	{"model": OUTER_ROOM, "cell": Vector2i(-6, 0), "rotation": 0},

	# Short south run.
	{"model": CORRIDOR, "cell": Vector2i(0, -3), "rotation": 90},
	{"model": OUTER_ROOM, "cell": Vector2i(0, -5), "rotation": 0},

	# North-west chamber, closing the upper loop.
	{"model": OUTER_ROOM, "cell": Vector2i(-6, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-2, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-3, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-4, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-6, 2), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(-6, 3), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(-6, 4), "rotation": 90},

	# South-east chamber, closing the lower loop.
	{"model": OUTER_ROOM, "cell": Vector2i(6, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(6, -2), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(6, -3), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(2, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(3, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(4, -5), "rotation": 0},

	# Alcoves. Short stubs that go nowhere, purely so the map has edges that
	# are not all routes — a network where every passage leads somewhere reads
	# as a puzzle rather than a cave.
	{"model": CORRIDOR, "cell": Vector2i(-8, 0), "rotation": 0},
	{"model": DEAD_END, "cell": Vector2i(-9, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(0, 8), "rotation": 90},
	{"model": DEAD_END, "cell": Vector2i(0, 9), "rotation": 270},
]

## Chambers zombies arrive from.
const SPAWN_CELLS := [
	Vector2i(0, 6), Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, -5),
	Vector2i(-6, 6), Vector2i(6, -5),
]

## Half-extent of each piece in grid cells. Every piece spans an odd number of
## cells, so it sits centred on its own cell.
const CELL_EXTENTS := {
	CENTRE_ROOM: Vector2i(2, 2),
	OUTER_ROOM: Vector2i(1, 1),
	WIDE_ROOM: Vector2i(2, 1),
	CORRIDOR: Vector2i(0, 0),
	DEAD_END: Vector2i(0, 0),
}

## Collision shell dimensions.
const WALL_HEIGHT := 5.0
const WALL_THICKNESS := 0.8
const FLOOR_THICKNESS := 2.0

## Nodes in this group are the *only* geometry the navmesh is baked from.
const NAV_SOURCE_GROUP := "navmesh_source"

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

@export_group("Atmosphere")
## Set from the graphics preset before the arena builds itself.
@export var quality: GameSettings.Quality = GameSettings.Quality.HIGH
@export var dust_enabled := true
@export var dust_amount := 160

@export_group("Ceiling")
## A roof closes the cave in. Without it the player sees over the walls into
## empty space, which reads as an unfinished level rather than a cave.
@export var ceiling_enabled := true
## Sits clear of the 5m walls. It used to be below them, so the wall tops cut
## through the roof and the cave leaked into empty space along every edge.
@export var ceiling_height := 5.6
@export var ceiling_thickness := 0.6
@export var ceiling_colour := Color(0.3, 0.2, 0.19)
@export var stalactite_count := 90

var spawn_points: Array[Vector3] = []

var _rng := RandomNumberGenerator.new()
var _geometry_root: Node3D


func _ready() -> void:
	_rng.seed = generation_seed
	_apply_quality()

	_geometry_root = Node3D.new()
	_geometry_root.name = "Geometry"
	add_child(_geometry_root)

	_build_layout()
	_build_collision_shell()
	_build_cover()
	_build_props()
	_build_spawn_points()

	if bake_navigation:
		_bake()

	# Added after baking on purpose: the ceiling is a large flat surface, and
	# the navmesh generator would happily carpet the top of it.
	if ceiling_enabled:
		_build_ceiling()

	if dust_enabled and quality >= GameSettings.Quality.MEDIUM:
		_build_dust()


## Turn the post-processing that the benchmark showed to be expensive on or off.
## The geometry and lighting layout stay identical across presets — only the
## effects that cost frames change, so Performance looks flatter but never
## different enough to play differently.
func _apply_quality() -> void:
	var settings := GameSettings.instance(self)
	if settings != null:
		quality = settings.quality

	var world_environment: WorldEnvironment = get_node_or_null("WorldEnvironment")
	if world_environment == null or world_environment.environment == null:
		return

	var environment: Environment = world_environment.environment
	environment.ssao_enabled = quality >= GameSettings.Quality.HIGH
	environment.glow_enabled = quality >= GameSettings.Quality.MEDIUM

	if quality == GameSettings.Quality.LOW:
		# Fog is cheap, but without SSAO or glow the scene needs a little more
		# of it to keep depth readable.
		environment.fog_density = 0.03


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
		_place(entry.model, entry.cell, entry.rotation)


func _place(model: String, cell: Vector2i, rotation_degrees: float) -> void:
	var instance := _instantiate(CAVE_PATH % model)
	if instance == null:
		return

	instance.position = _cell_to_world(cell)
	instance.rotation.y = deg_to_rad(rotation_degrees)
	instance.name = "%s_%d_%d" % [model, cell.x, cell.y]
	_geometry_root.add_child(instance)

	_add_nav_surface(cell, _footprint_for(model, rotation_degrees))
	_add_lighting(model, cell)


## Walkable footprint for a piece, turned to match its placement. Quarter turns
## swap the axes; half turns leave them alone.
func _footprint_for(model: String, rotation_degrees: float) -> Vector2:
	var footprint: Vector2 = FOOTPRINTS.get(model, Vector2(4.0, 2.6))
	var quarter_turned := is_equal_approx(fposmod(rotation_degrees, 180.0), 90.0)

	return Vector2(footprint.y, footprint.x) if quarter_turned else footprint


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
			light.light_energy = 5.6
			light.omni_range = 20.0
			# Only the arena casts shadows; the cost is worth it where the
			# player actually fights, and invisible everywhere else.
			light.shadow_enabled = quality >= GameSettings.Quality.MEDIUM
			light.position.y = 4.0
		OUTER_ROOM:
			light.light_color = Color(1.0, 0.7, 0.42)
			light.light_energy = 3.6
			light.omni_range = 13.0
		WIDE_ROOM:
			light.light_color = Color(1.0, 0.66, 0.36)
			light.light_energy = 4.0
			light.omni_range = 16.0
		_:
			light.light_color = Color(0.42, 0.62, 1.0)
			light.light_energy = 1.5
			light.omni_range = 7.0
			light.position.y = 3.0

	_geometry_root.add_child(light)
	_add_lamp_glow(light)

	var flicker := LightFlicker.new()
	light.add_child(flicker)
	# Random phase, or the whole cave pulses in unison and announces itself.
	flicker.setup(light, _rng.randf_range(0.0, TAU))


## Dust hanging in the air of the central arena.
##
## Cheap, and it does a lot: motes drifting through the light give the space
## depth and make the beams read as volume rather than as a flat gradient on
## the floor. Confined to the arena, where the player spends their time.
func _build_dust() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = dust_amount
	particles.lifetime = 9.0
	particles.preprocess = 9.0
	particles.visibility_aabb = AABB(Vector3(-11, 0, -11), Vector3(22, 6, 22))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(10.0, 2.4, 10.0)
	process.direction = Vector3(0.2, 1.0, 0.1)
	process.spread = 80.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.22
	process.gravity = Vector3(0.0, -0.04, 0.0)
	process.scale_min = 0.4
	process.scale_max = 1.0
	particles.process_material = process

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, 0.035)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.86, 0.68, 0.32)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = material
	particles.draw_pass_1 = mesh

	particles.position = Vector3(0.0, 2.0, 0.0)
	particles.name = "Dust"
	particles.emitting = true
	add_child(particles)


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
		_add_cover_collider(instance, entry.scale)


func _build_props() -> void:
	for entry in PROPS:
		var instance := _instantiate(PROP_PATH % entry.model)
		if instance == null:
			continue

		instance.position = entry.position
		instance.rotation.y = deg_to_rad(entry.rotation)
		_geometry_root.add_child(instance)


func _build_ceiling() -> void:
	# Reaches past the furthest chamber so no edge is ever visible from inside.
	var extent := 160.0

	# A box rather than a plane. A plane's normals point one way, and a flipped
	# plane lit from underneath renders as a black void that reads as open sky
	# — which is exactly what the roof used to look like. A box has correct
	# outward normals on every face, so its underside is lit like any other
	# surface and there is nothing to get backwards.
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(extent, ceiling_thickness, extent)
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(
		0.0, ceiling_height + ceiling_thickness * 0.5, 0.0
	)

	var material := StandardMaterial3D.new()
	material.albedo_color = ceiling_colour
	material.roughness = 1.0
	mesh_instance.material_override = material
	mesh_instance.name = "Ceiling"
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mesh_instance)
	_build_stalactites()


## Rock hanging from the roof.
##
## A flat ceiling reads as a lid on a box however well it is lit. Breaking the
## silhouette is what makes the space read as a cave, and it costs a handful of
## cones. They are kept above head height and away from the centre of chambers
## so they never obstruct a shot.
func _build_stalactites() -> void:
	if stalactite_count <= 0:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = ceiling_colour.darkened(0.15)
	material.roughness = 1.0

	var root := Node3D.new()
	root.name = "Stalactites"
	add_child(root)

	var reach := get_play_radius()

	for index in stalactite_count:
		var cone := CylinderMesh.new()
		cone.top_radius = _rng.randf_range(0.22, 0.6)
		cone.bottom_radius = 0.0
		cone.height = _rng.randf_range(0.8, 2.3)
		cone.radial_segments = 6
		cone.rings = 1

		var instance := MeshInstance3D.new()
		instance.mesh = cone
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.position = Vector3(
			_rng.randf_range(-reach, reach),
			ceiling_height - cone.height * 0.5,
			_rng.randf_range(-reach, reach)
		)
		root.add_child(instance)


## Zombies enter from the outer chambers, so pressure arrives from every
## bearing and never from inside the room the player is standing in.
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


## Build collision as a box shell around the walkable cells, rather than from
## the cave meshes.
##
## Colliding against the render geometry was costing ~0.6ms of physics per
## zombie: concave trimesh built from sculpted rock is the most expensive shape
## a capsule can sweep against, and thirty zombies put physics over the entire
## frame budget. Shipping games keep collision separate from what is drawn, and
## boxes are roughly an order of magnitude cheaper to query.
##
## A wall goes on any cell edge whose neighbour is not walkable, which places
## openings exactly where two pieces meet without needing to know anything
## about doorways.
func _build_collision_shell() -> void:
	var occupied := _occupied_cells()

	var shell := StaticBody3D.new()
	shell.name = "CollisionShell"
	add_child(shell)

	_add_floor_collider(shell, occupied)

	const NEIGHBOURS := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	for cell in occupied:
		for offset in NEIGHBOURS:
			if occupied.has(cell + offset):
				continue
			_add_wall_collider(shell, cell, offset)


## Every grid cell any piece covers.
func _occupied_cells() -> Dictionary:
	var occupied: Dictionary = {}

	for entry in LAYOUT:
		var extent: Vector2i = CELL_EXTENTS.get(entry.model, Vector2i.ZERO)

		# A quarter turn swaps the footprint's axes.
		if is_equal_approx(fposmod(float(entry.rotation), 180.0), 90.0):
			extent = Vector2i(extent.y, extent.x)

		for x in range(entry.cell.x - extent.x, entry.cell.x + extent.x + 1):
			for y in range(entry.cell.y - extent.y, entry.cell.y + extent.y + 1):
				occupied[Vector2i(x, y)] = true

	return occupied


func _add_wall_collider(shell: StaticBody3D, cell: Vector2i, offset: Vector2i) -> void:
	var along_x := offset.x != 0

	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (
		Vector3(WALL_THICKNESS, WALL_HEIGHT, CELL) if along_x
		else Vector3(CELL, WALL_HEIGHT, WALL_THICKNESS)
	)
	collider.shape = box
	collider.position = _cell_to_world(cell) + Vector3(
		float(offset.x) * CELL * 0.5,
		WALL_HEIGHT * 0.5,
		float(offset.y) * CELL * 0.5
	)

	shell.add_child(collider)


## One slab under everything. The walls contain the player, so the floor does
## not need to follow the walkable shape.
func _add_floor_collider(shell: StaticBody3D, occupied: Dictionary) -> void:
	var minimum := Vector2i(9999, 9999)
	var maximum := Vector2i(-9999, -9999)

	for cell in occupied:
		minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
		maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))

	var span := Vector3(
		float(maximum.x - minimum.x + 2) * CELL,
		FLOOR_THICKNESS,
		float(maximum.y - minimum.y + 2) * CELL
	)
	var centre := (_cell_to_world(minimum) + _cell_to_world(maximum)) * 0.5

	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = span
	collider.shape = box
	collider.position = centre - Vector3(0.0, FLOOR_THICKNESS * 0.5, 0.0)

	shell.add_child(collider)


## Cover rocks get a cylinder rather than their mesh, for the same reason the
## walls get boxes: the shape only has to stop a capsule, not match the art.
func _add_cover_collider(instance: Node3D, scale_factor: float) -> void:
	var body := StaticBody3D.new()

	var collider := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.15 * scale_factor
	cylinder.height = 4.4 * scale_factor
	collider.shape = cylinder
	collider.position = Vector3(0.0, cylinder.height * 0.5, 0.0)

	body.add_child(collider)
	instance.add_child(body)


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
