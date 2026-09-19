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

## Interchangeable sculpts of the same chamber: identical footprint, identical
## openings, different rock. Measured, not assumed — see tools/measure_models.
const VARIANTS := {
	CENTRE_ROOM: ["room-large", "room-large-variation"],
	OUTER_ROOM: ["room-small", "room-small-variation"],
	WIDE_ROOM: ["room-wide", "room-wide-variation"],
}

## Chambers that are square, and so can be turned without changing what they
## connect to.
const SQUARE_ROOMS := [CENTRE_ROOM, OUTER_ROOM]

## Spawn scoring. Relative weights for a point directly behind the player
## versus directly ahead, how quickly preference falls off with distance past
## the minimum, and how hard a recently used chamber is damped.
const BEHIND_WEIGHT := 1.0
const AHEAD_WEIGHT := 0.12
const SPAWN_FALLOFF := 22.0
const REPEAT_DAMPING := 0.2
const RECENT_CHAMBER_MEMORY := 3

## Light every Nth corridor cell, and fade lights out beyond this range.
const CORRIDOR_LIGHT_SPACING := 3
const LIGHT_FADE_BEGIN := 34.0
const LIGHT_FADE_LENGTH := 12.0

## Where inside a chamber a zombie can appear, as offsets from its centre.
## Several points per chamber so arrivals are not all from one exact spot.
const SPAWN_SPREAD := [
	Vector2(0.0, 0.0),
	Vector2(3.0, 2.4),
	Vector2(-2.8, 2.6),
	Vector2(2.6, -2.8),
	Vector2(-2.4, -3.0),
]

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


## The cave network, as {model, cell, rotation}.
##
## Rooms are the nodes and corridors are the edges. Every bend happens inside a
## room, never between two corridors — an unrotated corridor runs along X and
## presents a solid end wall on its Z faces, so two corridors meeting at a
## right angle produce a dead end that looks like a passage. Rooms open on all
## four sides, which is what makes them safe to turn in.
##
## Fourteen chambers on four rings, with every outer chamber reachable by at
## least two routes. Deliberately irregular: arms differ in length, chambers
## differ in size, and no two loops are mirror images. A symmetric grid reads
## as a diagram; an uneven one reads as a place.
const LAYOUT := [
	# ---- Core -------------------------------------------------------------
	{"model": CENTRE_ROOM, "cell": Vector2i(0, 0), "rotation": 0},

	# ---- North spine ------------------------------------------------------
	{"model": CORRIDOR, "cell": Vector2i(0, 3), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(0, 4), "rotation": 90},
	{"model": OUTER_ROOM, "cell": Vector2i(0, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(0, 8), "rotation": 90},
	{"model": WIDE_ROOM, "cell": Vector2i(0, 11), "rotation": 90},

	# ---- East spine -------------------------------------------------------
	{"model": CORRIDOR, "cell": Vector2i(3, 0), "rotation": 0},
	{"model": WIDE_ROOM, "cell": Vector2i(6, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(9, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(10, 0), "rotation": 0},
	{"model": OUTER_ROOM, "cell": Vector2i(12, 0), "rotation": 0},

	# East chamber up to the north-east corner.
	{"model": CORRIDOR, "cell": Vector2i(12, 2), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(12, 3), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(12, 4), "rotation": 90},
	{"model": OUTER_ROOM, "cell": Vector2i(12, 6), "rotation": 0},

	# The long north hall, closing the biggest loop on the map.
	{"model": CORRIDOR, "cell": Vector2i(2, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(3, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(4, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(5, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(6, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(7, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(8, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(9, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(10, 6), "rotation": 0},

	# ---- West spine -------------------------------------------------------
	{"model": CORRIDOR, "cell": Vector2i(-3, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-4, 0), "rotation": 0},
	{"model": OUTER_ROOM, "cell": Vector2i(-6, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-8, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-9, 0), "rotation": 0},
	{"model": WIDE_ROOM, "cell": Vector2i(-12, 0), "rotation": 0},

	# North-west chamber, closing the upper-left loop.
	{"model": CORRIDOR, "cell": Vector2i(-6, 2), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(-6, 3), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(-6, 4), "rotation": 90},
	{"model": OUTER_ROOM, "cell": Vector2i(-6, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-2, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-3, 6), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-4, 6), "rotation": 0},

	# ---- South ring -------------------------------------------------------
	{"model": CORRIDOR, "cell": Vector2i(0, -3), "rotation": 90},
	{"model": OUTER_ROOM, "cell": Vector2i(0, -5), "rotation": 0},

	{"model": CORRIDOR, "cell": Vector2i(2, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(3, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(4, -5), "rotation": 0},
	{"model": OUTER_ROOM, "cell": Vector2i(6, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(6, -2), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(6, -3), "rotation": 90},

	{"model": CORRIDOR, "cell": Vector2i(-2, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-3, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-4, -5), "rotation": 0},
	{"model": OUTER_ROOM, "cell": Vector2i(-6, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-6, -2), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(-6, -3), "rotation": 90},

	# South-east chamber, hung off the south-east corner.
	{"model": CORRIDOR, "cell": Vector2i(9, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(10, -5), "rotation": 0},
	{"model": OUTER_ROOM, "cell": Vector2i(12, -5), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(12, -2), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(12, -3), "rotation": 90},

	# The deep south chamber, furthest point on the map from the centre.
	{"model": CORRIDOR, "cell": Vector2i(0, -7), "rotation": 90},
	{"model": CENTRE_ROOM, "cell": Vector2i(0, -10), "rotation": 0},

	# ---- Alcoves ----------------------------------------------------------
	# Short stubs that go nowhere, purely so the map has edges that are not all
	# routes — a network where every passage leads somewhere reads as a puzzle
	# rather than a cave.
	{"model": CORRIDOR, "cell": Vector2i(-15, 0), "rotation": 0},
	{"model": DEAD_END, "cell": Vector2i(-16, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(0, 14), "rotation": 90},
	{"model": DEAD_END, "cell": Vector2i(0, 15), "rotation": 270},
	{"model": CORRIDOR, "cell": Vector2i(15, 0), "rotation": 0},
	{"model": DEAD_END, "cell": Vector2i(16, 0), "rotation": 0},
]

## Chambers zombies arrive from.
##
## Every outer chamber on the map, so pressure can come from any bearing. Which
## of them is actually used for a given spawn is decided at runtime — see
## pick_spawn_point.
const SPAWN_CELLS := [
	Vector2i(0, 11), Vector2i(0, 6), Vector2i(12, 0), Vector2i(12, 6),
	Vector2i(-6, 0), Vector2i(-12, 0), Vector2i(-6, 6), Vector2i(0, -5),
	Vector2i(6, -5), Vector2i(-6, -5), Vector2i(12, -5), Vector2i(0, -10),
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
	# Moved clear of the raised decks below, which would otherwise have rock
	# growing up through the floorboards.
	{"position": Vector3(7.8, 0, -1.0), "rotation": 65, "scale": 0.55},
	{"position": Vector3(-7.4, 0, 0.8), "rotation": -40, "scale": 0.66},
	{"position": Vector3(-1.5, 0, 7.8), "rotation": 140, "scale": 0.5},
	{"position": Vector3(2.0, 0, -8.0), "rotation": -75, "scale": 0.58},
]

## Raised decks and the ramps up to them.
##
## Verticality does two things a flat arena cannot. It gives the player ground
## worth holding that costs something to reach and leave, and it splits the
## horde's approach into lanes instead of letting it arrive as one wall. The
## ramp is deliberately wide and open: a chokepoint you can hold indefinitely
## is exactly what the concept's anti-turtling rule rules out.
##
## `tiles` counts 4m kit blocks. `ramp_from` is the floor end of the ramp; the
## deck edge nearest it is worked out from the deck rectangle, so the two
## always meet however the deck is sized.
const DECK_HEIGHT := 3.0
const DECK_TILE := "template-floor-layer-raised"
const RAMP_WIDTH := 3.6
const RAMP_THICKNESS := 0.5
const RAMP_COLOUR := Color(0.36, 0.25, 0.17)
## How far the ramp's navmesh strip runs past the slab at each end.
const RAMP_NAV_OVERLAP := 0.9
## How far the flat landing reaches onto the deck, and out over the ramp.
const LANDING_INNER := 2.2
const LANDING_OUTER := 0.9
## How far each end of a ramp link sits back from the join, onto ground the
## baker definitely kept.
const LINK_SETBACK := 1.8

const PLATFORMS := [
	{
		"centre": Vector2(-4.5, 5.0),
		"tiles": Vector2i(2, 1),
		"ramp_from": Vector2(5.5, 5.0),
	},
	{
		"centre": Vector2(4.5, -5.0),
		"tiles": Vector2i(2, 1),
		"ramp_from": Vector2(-5.5, -5.0),
	},
	# In the long east hall, so the hall is not simply a corridor with a wide
	# middle.
	{
		"centre": Vector2(28.0, 0.0),
		"tiles": Vector2i(1, 2),
		"ramp_from": Vector2(19.0, 0.0),
	},
]

## Chambers holding a resupply cache, and where in the chamber it sits.
##
## Deliberately not in the central arena. Ammunition has to be somewhere the
## player must travel to, or it is just a slower version of starting with more
## — the point is that resupplying costs you the ground you were holding.
##
## Spread across four bearings so no single loop collects them all, and none of
## them is in a dead-end alcove: a cache you can only reach down a corridor
## with one exit is a trap rather than a decision.
const CACHE_CELLS := [
	Vector2i(0, 6),
	Vector2i(12, 0),
	Vector2i(-6, 0),
	Vector2i(6, -5),
	Vector2i(-6, -5),
	Vector2i(0, -10),
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

@export_group("Caches")
## The menu backdrop has no player to collect anything, so it skips them.
@export var caches_enabled := true

var spawn_points: Array[Vector3] = []
## Chamber index for each entry in spawn_points, parallel array.
var spawn_chambers: Array[int] = []
## Resupply points, for Game to connect to.
var ammo_caches: Array[AmmoCache] = []

var _rng := RandomNumberGenerator.new()
var _geometry_root: Node3D
## Chambers used for the last few spawns.
var _recent_chambers: Array[int] = []


func _ready() -> void:
	_rng.seed = generation_seed
	_apply_quality()

	_geometry_root = Node3D.new()
	_geometry_root.name = "Geometry"
	add_child(_geometry_root)

	_build_layout()
	_build_collision_shell()
	_build_platforms()
	_build_cover()
	_build_props()
	_build_spawn_points()

	if bake_navigation:
		_bake()

	# Added after baking on purpose: the ceiling is a large flat surface, and
	# the navmesh generator would happily carpet the top of it.
	if ceiling_enabled:
		_build_ceiling()

	_build_caches()

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
## Choose where the next zombie comes from.
##
## Uniform random across every chamber sounds fair and plays badly. It puts
## roughly as many zombies in front of the player as behind — so they appear
## out of nothing in plain view — and with no memory it will happily use the
## same doorway five times running, which reads as a spawn closet rather than a
## cave full of things.
##
## Candidates are scored instead of filtered: arrivals behind the player are
## strongly preferred, chambers used recently are damped, and distance is
## scored as a band rather than "further is safer" so a zombie spawned across
## the map does not spend a minute walking. Everything still has some weight,
## so pressure can come from any bearing.
func pick_spawn_point(away_from: Vector3, minimum_distance: float,
		facing := Vector3.ZERO) -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO

	var best_index := -1
	var best_score := -1.0
	var total := 0.0

	for index in spawn_points.size():
		var score := _score_spawn(index, away_from, minimum_distance, facing)
		if score <= 0.0:
			continue

		# Weighted reservoir sampling: one pass, no candidate array, and the
		# chance of holding any given point stays proportional to its score.
		total += score
		if _rng.randf() * total < score:
			best_index = index
			best_score = score

	if best_index < 0:
		best_index = _rng.randi_range(0, spawn_points.size() - 1)

	_remember_chamber(spawn_chambers[best_index])
	return spawn_points[best_index]


func _score_spawn(index: int, away_from: Vector3, minimum_distance: float,
		facing: Vector3) -> float:
	var point: Vector3 = spawn_points[index]
	var offset := point - away_from
	offset.y = 0.0

	var distance := offset.length()
	if distance < minimum_distance:
		return 0.0

	# Peaks at the near end of the band and tails off, so the fight stays where
	# the player is rather than trickling in from the far corners.
	var score: float = 1.0 / (1.0 + maxf(0.0, distance - minimum_distance) / SPAWN_FALLOFF)

	if facing != Vector3.ZERO and distance > 0.001:
		var ahead := facing.normalized().dot(offset / distance)
		# Smoothly favours behind over in front rather than switching at the
		# exact 90 degree line, which would make the preference obvious.
		score *= lerpf(BEHIND_WEIGHT, AHEAD_WEIGHT, inverse_lerp(-1.0, 1.0, ahead))

	if spawn_chambers[index] in _recent_chambers:
		score *= REPEAT_DAMPING

	return score


## Remember which chambers were used lately, so the next pick can avoid them.
func _remember_chamber(chamber: int) -> void:
	_recent_chambers.append(chamber)
	while _recent_chambers.size() > RECENT_CHAMBER_MEMORY:
		_recent_chambers.pop_front()


func _build_layout() -> void:
	for entry in LAYOUT:
		_place(entry.model, entry.cell, entry.rotation)


func _place(model: String, cell: Vector2i, rotation_degrees: float) -> void:
	var instance := _instantiate(CAVE_PATH % _mesh_for(model))
	if instance == null:
		return

	# Square chambers get a free quarter turn. The footprint is unchanged, but
	# the sculpted rock inside is not, and a dozen identical small rooms is the
	# single thing that makes a modular kit read as a modular kit.
	var placed_rotation := rotation_degrees
	if model in SQUARE_ROOMS:
		placed_rotation += 90.0 * float(_rng.randi_range(0, 3))

	instance.position = _cell_to_world(cell)
	instance.rotation.y = deg_to_rad(placed_rotation)
	instance.name = "%s_%d_%d" % [model, cell.x, cell.y]
	_geometry_root.add_child(instance)

	_add_nav_surface(cell, _footprint_for(model, rotation_degrees))
	_add_lighting(model, cell)


## Pick which mesh actually gets placed for a logical piece.
##
## The kit ships a second sculpt of each room with the same footprint and the
## same openings, so the two are interchangeable. Choosing between them costs
## nothing and stops the same cave wall appearing in six chambers.
func _mesh_for(model: String) -> String:
	var options: Array = VARIANTS.get(model, [])
	if options.is_empty():
		return model

	return options[_rng.randi_range(0, options.size() - 1)]


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
	# Corridors are lit every few cells rather than every cell. With the map at
	# its current size that is the difference between roughly ninety lights and
	# nearly three hundred, and a run of evenly spaced lamps reads better than
	# a continuous strip anyway — the dark stretches between them are what make
	# a corridor feel long.
	if model == CORRIDOR and posmod(cell.x + cell.y, CORRIDOR_LIGHT_SPACING) != 0:
		return

	var light := OmniLight3D.new()
	light.position = _cell_to_world(cell) + Vector3.UP * 3.3
	light.shadow_enabled = false

	# A light the player cannot see is still a light the renderer pays for.
	# The map is now far larger than anything visible at once, so lights fade
	# out well beyond the fog rather than accumulating across the whole cave.
	light.distance_fade_enabled = true
	light.distance_fade_begin = LIGHT_FADE_BEGIN
	light.distance_fade_length = LIGHT_FADE_LENGTH

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


## Place a resupply cache in each of the chambers that has one.
##
## Built after the navmesh bake: a cache is a trigger volume and a crate, and
## neither should contribute walkable surface or be carved out of it.
func _build_caches() -> void:
	ammo_caches.clear()

	if not caches_enabled:
		return

	for cell in CACHE_CELLS:
		var cache := AmmoCache.new()
		cache.name = "AmmoCache_%d_%d" % [cell.x, cell.y]
		# Offset from the chamber centre so the crate is not standing exactly
		# where zombies arrive.
		cache.position = _cell_to_world(cell) + Vector3(2.2, 0.0, -2.2)
		add_child(cache)
		ammo_caches.append(cache)


## Build every raised deck and its ramp.
##
## Runs before the navmesh bake, because the deck and ramp contribute walkable
## surfaces the bake has to see. A deck added afterwards is scenery the zombies
## cannot follow you onto, which would make climbing it a free win.
func _build_platforms() -> void:
	for entry in PLATFORMS:
		_build_platform(entry)


func _build_platform(entry: Dictionary) -> void:
	var centre: Vector2 = entry.centre
	var tiles: Vector2i = entry.tiles
	var deck_size := Vector2(float(tiles.x) * CELL, float(tiles.y) * CELL)

	_build_deck_blocks(centre, tiles)
	_add_deck_collision(centre, deck_size)
	_add_nav_quad(
		Vector3(centre.x, DECK_HEIGHT + NAV_HEIGHT, centre.y),
		deck_size,
		0.0,
		"NavDeck_%d_%d" % [int(centre.x), int(centre.y)]
	)

	_build_ramp(centre, deck_size, entry.ramp_from)


## The deck itself, tiled from the kit's raised floor block. The block is 4m
## square and exactly 3m tall, so its top face is the walking surface and no
## scaling is involved.
func _build_deck_blocks(centre: Vector2, tiles: Vector2i) -> void:
	for x in tiles.x:
		for z in tiles.y:
			var offset := Vector2(
				(float(x) - float(tiles.x - 1) * 0.5) * CELL,
				(float(z) - float(tiles.y - 1) * 0.5) * CELL
			)
			var block := _instantiate(CAVE_PATH % DECK_TILE)
			if block == null:
				return
			block.position = Vector3(centre.x + offset.x, 0.0, centre.y + offset.y)
			_geometry_root.add_child(block)


## One box for the whole deck rather than one per block. The blocks are only
## scenery — a stack of separate colliders meeting edge to edge gives a
## character something to catch on as it walks across the seams.
func _add_deck_collision(centre: Vector2, deck_size: Vector2) -> void:
	var body := StaticBody3D.new()
	body.name = "DeckBody_%d_%d" % [int(centre.x), int(centre.y)]
	_geometry_root.add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(deck_size.x, DECK_HEIGHT, deck_size.y)
	shape.shape = box
	shape.position = Vector3(centre.x, DECK_HEIGHT * 0.5, centre.y)
	body.add_child(shape)


## A ramp from the floor up to the nearest edge of the deck.
##
## Its slope is whatever the run works out to, which is around 25 degrees for
## the distances used here — well inside the navmesh baker's 45 degree limit,
## so zombies path up it exactly like any other floor. That matters more than
## it sounds: a deck they cannot reach is not a tactical position, it is a
## place to stand and win.
func _build_ramp(centre: Vector2, deck_size: Vector2, ramp_from: Vector2) -> void:
	var to_floor := ramp_from - centre
	var along_x: bool = absf(to_floor.x) > absf(to_floor.y)
	var direction: float = signf(to_floor.x if along_x else to_floor.y)

	# Start at the deck edge facing the floor end, not at the deck centre.
	var half_depth: float = (deck_size.x if along_x else deck_size.y) * 0.5
	var edge := centre
	if along_x:
		edge.x += half_depth * direction
	else:
		edge.y += half_depth * direction

	var run: float = (
		absf(ramp_from.x - edge.x) if along_x else absf(ramp_from.y - edge.y)
	)
	if run < 0.5:
		return

	var slope := atan2(DECK_HEIGHT, run)
	var length := sqrt(run * run + DECK_HEIGHT * DECK_HEIGHT)
	var midpoint := (edge + ramp_from) * 0.5
	var origin := Vector3(midpoint.x, DECK_HEIGHT * 0.5, midpoint.y)

	# Tilt about the axis across the ramp so it falls away from the deck.
	#
	# The sign matters and is easy to get backwards: with the wrong one the
	# ramp still looks like a ramp, but its high end is out on the floor and it
	# meets the deck at ground level. The deck then bakes as an island and
	# nothing can walk up. Rotating by `slope * direction` puts the low end on
	# whichever side the floor is.
	var basis := (
		Basis(Vector3.FORWARD, slope * direction) if along_x
		else Basis(Vector3.RIGHT, slope * direction)
	)

	var size := (
		Vector3(length, RAMP_THICKNESS, RAMP_WIDTH) if along_x
		else Vector3(RAMP_WIDTH, RAMP_THICKNESS, length)
	)

	var transform := Transform3D(basis, origin)
	_add_ramp_visual(transform, size, centre)
	_add_ramp_collision(transform, size, centre)

	# The walkable surface sits on top of the slab, not through its middle.
	var surface := transform
	surface.origin += transform.basis.y * (RAMP_THICKNESS * 0.5 + NAV_HEIGHT)

	# The navmesh strip runs past both ends of the slab it sits on.
	#
	# The baker erodes every walkable surface inward by the agent radius, so a
	# ramp that merely *touches* the deck at one end and the floor at the other
	# loses half a metre off each after erosion and bakes as an island. It
	# looks perfectly correct from above, and the deck becomes somewhere the
	# player can stand and never be followed. Overlapping the ends means the
	# surfaces are one region before erosion ever happens.
	var overlap := Vector2(
		size.x + RAMP_NAV_OVERLAP * 2.0, size.z
	) if along_x else Vector2(size.x, size.z + RAMP_NAV_OVERLAP * 2.0)

	_add_nav_surface_transformed(
		surface, overlap, "NavRamp_%d_%d" % [int(centre.x), int(centre.y)]
	)

	_add_landing(edge, along_x, direction, centre)
	_add_ramp_link(edge, ramp_from, along_x, direction, centre)


## Join the floor to the deck with an explicit navigation link.
##
## The ramp is solid geometry the player walks up, but the *baked* surfaces at
## its two ends refuse to merge into one region. The baker erodes every
## walkable area inward by the agent radius, and it also discards floor beneath
## anything with less than standing headroom above it — so the ramp carves a
## strip of unwalkable floor out from under itself and then fails to reach
## across it. Widening, lengthening and overlapping the strip all move the gap
## around without closing it.
##
## A link states the connection outright instead of hoping the geometry
## implies it, which is what links are for. Agents cross it in a straight line
## and the ramp is directly underneath, so they are visibly walking up it.
## Both ends are set back from the join onto ground that is definitely
## walkable, clear of the strip the baker discarded.
func _add_ramp_link(edge: Vector2, ramp_from: Vector2, along_x: bool,
		direction: float, centre: Vector2) -> void:
	var foot := ramp_from
	var head := edge

	if along_x:
		foot.x += LINK_SETBACK * direction
		head.x -= LINK_SETBACK * direction
	else:
		foot.y += LINK_SETBACK * direction
		head.y -= LINK_SETBACK * direction

	var link := NavigationLink3D.new()
	link.name = "RampLink_%d_%d" % [int(centre.x), int(centre.y)]
	link.start_position = Vector3(foot.x, NAV_HEIGHT, foot.y)
	link.end_position = Vector3(head.x, DECK_HEIGHT + NAV_HEIGHT, head.y)
	# Zombies have to be able to come back down as readily as they went up.
	link.bidirectional = true

	_geometry_root.add_child(link)


## A flat strip at deck height spanning the join between deck and ramp.
##
## Overlapping the ends of the sloped strip was not enough on its own: the
## slope and the deck are eroded inward by the agent radius from opposite
## sides and still ended up a fraction of a metre apart, which is all it takes
## to bake as two regions. This strip is exactly level with the deck, so the
## two merge into a single surface before erosion is applied, and it reaches
## far enough out over the top of the ramp to catch it as well.
func _add_landing(edge: Vector2, along_x: bool, direction: float,
		centre: Vector2) -> void:
	var position := edge
	var offset: float = (LANDING_OUTER - LANDING_INNER) * 0.5 * direction
	var depth := LANDING_INNER + LANDING_OUTER

	if along_x:
		position.x += offset
	else:
		position.y += offset

	var size := (
		Vector2(depth, RAMP_WIDTH) if along_x else Vector2(RAMP_WIDTH, depth)
	)

	_add_nav_quad(
		Vector3(position.x, DECK_HEIGHT + NAV_HEIGHT, position.y),
		size,
		0.0,
		"NavLanding_%d_%d" % [int(centre.x), int(centre.y)]
	)


func _add_ramp_visual(transform: Transform3D, size: Vector3, centre: Vector2) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.transform = transform
	mesh_instance.name = "Ramp_%d_%d" % [int(centre.x), int(centre.y)]

	var material := StandardMaterial3D.new()
	material.albedo_color = RAMP_COLOUR
	material.roughness = 0.9
	mesh_instance.material_override = material

	_geometry_root.add_child(mesh_instance)


func _add_ramp_collision(transform: Transform3D, size: Vector3, centre: Vector2) -> void:
	var body := StaticBody3D.new()
	body.name = "RampBody_%d_%d" % [int(centre.x), int(centre.y)]
	_geometry_root.add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = transform
	body.add_child(shape)


## A flat navmesh source at an arbitrary height and rotation.
func _add_nav_quad(position: Vector3, size: Vector2, rotation: float,
		node_name: String) -> void:
	var transform := Transform3D(Basis(Vector3.UP, rotation), position)
	_add_nav_surface_transformed(transform, size, node_name)


func _add_nav_surface_transformed(transform: Transform3D, size: Vector2,
		node_name: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mesh_instance.mesh = plane
	mesh_instance.transform = transform
	mesh_instance.visible = false
	mesh_instance.name = node_name

	_geometry_root.add_child(mesh_instance)
	mesh_instance.add_to_group(NAV_SOURCE_GROUP)


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
	spawn_chambers.clear()

	for chamber in SPAWN_CELLS.size():
		var origin := _cell_to_world(SPAWN_CELLS[chamber]) + Vector3.UP * 0.2

		for offset in SPAWN_SPREAD:
			spawn_points.append(origin + Vector3(offset.x, 0.0, offset.y))
			# Which chamber each point belongs to, so the picker can avoid
			# using the same one twice in a row.
			spawn_chambers.append(chamber)


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
