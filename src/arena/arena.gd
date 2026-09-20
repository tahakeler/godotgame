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
const CORNER_ROOM := "room-corner"
const CORRIDOR := "corridor"
## A true four-way crossroads. Corridors can branch anywhere now, instead of
## every junction having to be a room.
const CROSS := "corridor-intersection"
const DEAD_END := "corridor-end"

## Interchangeable sculpts of the same chamber: identical footprint, identical
## openings, different rock. Measured, not assumed — see tools/measure_models.
const VARIANTS := {
	CENTRE_ROOM: ["room-large", "room-large-variation"],
	OUTER_ROOM: ["room-small", "room-small-variation"],
	WIDE_ROOM: ["room-wide", "room-wide-variation"],
}

## Chambers that are square *and* open on every side, so a free quarter turn
## changes the rock without changing what they connect to.
##
## A corner room is square but emphatically not in this list: its rotation is
## what decides which two sides are open.
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

## Walkable footprint per piece, before rotation.
##
## Every one of these was measured with tools/probe_openings.gd rather than
## read off a render. The kit's rooms have decorative indentations that look
## like doorways from above and are solid rock, an unrotated corridor runs
## along X, and `corridor-corner` reads as walled on all four sides at head
## height — which is why it is not used here despite being exactly the piece
## the layout would seem to want.
##
## Corridor footprints deliberately run longer than the 4m piece so they lap
## into their neighbours and the navmesh bakes as one surface. Room footprints
## sit inside their piece, so they never poke walkable ground into rock.
const FOOTPRINTS := {
	CENTRE_ROOM: Vector2(17.0, 17.0),
	OUTER_ROOM: Vector2(9.0, 9.0),
	CORNER_ROOM: Vector2(9.0, 9.0),
	WIDE_ROOM: Vector2(17.0, 9.0),
	CORRIDOR: Vector2(8.0, 2.6),
	CROSS: Vector2(8.0, 2.6),
	DEAD_END: Vector2(5.0, 2.6),
}

## A second footprint for pieces that are walkable along both axes.
##
## Only the four-way crossroads needs one, and only because it is the single
## piece whose walkable area is a plus rather than a rectangle. Giving a T
## junction the same treatment would lay navmesh through its closed side and
## send zombies walking into rock, so T junctions are not used.
const EXTRA_FOOTPRINTS := {
	CROSS: Vector2(2.6, 8.0),
}


## The cave network, as {model, cell, rotation}.
##
## Corridors branch at crossroads and chambers are not all rectangles, so the
## map reads as a place that was dug rather than a diagram that was drawn.
## The central network has two loops; terminal branches require backtracking.
##
## Rotations for `room-corner` come from the probe: unrotated it opens -X and
## -Z, and each quarter turn moves both. 0 is -X/-Z, 90 is -X/+Z, 180 is
## +X/+Z, 270 is +X/-Z.
const LAYOUT := [
	# ---- The arena ---------------------------------------------------------
	{"model": CENTRE_ROOM, "cell": Vector2i(0, 0), "rotation": 0},

	# ---- North crossroads --------------------------------------------------
	{"model": CORRIDOR, "cell": Vector2i(0, 3), "rotation": 90},
	{"model": CROSS, "cell": Vector2i(0, 4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(0, 5), "rotation": 90},
	{"model": OUTER_ROOM, "cell": Vector2i(0, 7), "rotation": 0},

	# West off the crossroads, into a corner chamber that turns south.
	{"model": CORRIDOR, "cell": Vector2i(-1, 4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-2, 4), "rotation": 0},
	{"model": CORNER_ROOM, "cell": Vector2i(-4, 4), "rotation": 270},
	{"model": CORRIDOR, "cell": Vector2i(-4, 2), "rotation": 90},

	# East off the crossroads, mirrored but not symmetrical.
	# One cell further out than its western twin, and reached by a longer run.
	{"model": CORRIDOR, "cell": Vector2i(1, 4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(2, 4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(3, 4), "rotation": 0},
	{"model": CORNER_ROOM, "cell": Vector2i(5, 4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(5, 2), "rotation": 90},

	# The deep north chamber, furthest point on the map.
	{"model": CORRIDOR, "cell": Vector2i(0, 9), "rotation": 90},
	{"model": CENTRE_ROOM, "cell": Vector2i(0, 12), "rotation": 0},

	# ---- Flanking chambers -------------------------------------------------
	{"model": CORRIDOR, "cell": Vector2i(-3, 0), "rotation": 0},
	{"model": OUTER_ROOM, "cell": Vector2i(-5, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(3, 0), "rotation": 0},
	{"model": OUTER_ROOM, "cell": Vector2i(5, 0), "rotation": 0},

	# ---- South crossroads --------------------------------------------------
	{"model": CORRIDOR, "cell": Vector2i(0, -3), "rotation": 90},
	{"model": CROSS, "cell": Vector2i(0, -4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(0, -5), "rotation": 90},
	{"model": WIDE_ROOM, "cell": Vector2i(0, -8), "rotation": 90},

	# West off the south crossroads, turning north to close the loop.
	{"model": CORRIDOR, "cell": Vector2i(-1, -4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-2, -4), "rotation": 0},
	{"model": CORNER_ROOM, "cell": Vector2i(-4, -4), "rotation": 180},
	{"model": CORRIDOR, "cell": Vector2i(-4, -2), "rotation": 90},

	# East off the south crossroads.
	# A plain chamber rather than a fourth corner room, so the south-east does
	# not mirror the north-east.
	{"model": CORRIDOR, "cell": Vector2i(1, -4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(2, -4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(3, -4), "rotation": 0},
	{"model": OUTER_ROOM, "cell": Vector2i(5, -4), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(5, -2), "rotation": 90},

	# ---- The long halls ----------------------------------------------------
	# Deliberately uneven: the east run is one cell longer than the west, so
	# the two sides of the map never feel like reflections of each other.
	{"model": CORRIDOR, "cell": Vector2i(7, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(8, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(9, 0), "rotation": 0},
	{"model": WIDE_ROOM, "cell": Vector2i(12, 0), "rotation": 0},

	{"model": CORRIDOR, "cell": Vector2i(-7, 0), "rotation": 0},
	{"model": CORRIDOR, "cell": Vector2i(-8, 0), "rotation": 0},
	{"model": WIDE_ROOM, "cell": Vector2i(-11, 0), "rotation": 0},

	# ---- Alcoves -----------------------------------------------------------
	# Stubs that go nowhere, so not every passage is a route. A network where
	# everything leads somewhere reads as a puzzle rather than a cave.
	{"model": CORRIDOR, "cell": Vector2i(0, -11), "rotation": 90},
	{"model": DEAD_END, "cell": Vector2i(0, -12), "rotation": 90},
	{"model": CORRIDOR, "cell": Vector2i(15, 0), "rotation": 0},
	{"model": DEAD_END, "cell": Vector2i(16, 0), "rotation": 0},
]

## Chambers zombies arrive from.
##
## Every outer chamber, so pressure can come from any bearing. Which one is
## used for a given spawn is decided at runtime — see pick_spawn_point.
const SPAWN_CELLS := [
	Vector2i(0, 7), Vector2i(0, 12), Vector2i(-5, 0), Vector2i(5, 0),
	Vector2i(0, -8), Vector2i(-4, 4), Vector2i(5, 4), Vector2i(-4, -4),
	Vector2i(5, -4), Vector2i(12, 0), Vector2i(-11, 0),
]


## Half-extent of each piece in grid cells. Every piece spans an odd number of
## cells, so it sits centred on its own cell.
const CELL_EXTENTS := {
	CENTRE_ROOM: Vector2i(2, 2),
	OUTER_ROOM: Vector2i(1, 1),
	CORNER_ROOM: Vector2i(1, 1),
	WIDE_ROOM: Vector2i(2, 1),
	CORRIDOR: Vector2i(0, 0),
	CROSS: Vector2i(0, 0),
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
	# Moved clear of the south-east ramp, which it was standing 0.4m inside.
	{"position": Vector3(-7.3, 0, -4.8), "rotation": 18, "scale": 0.62},
	# Pulled south off the north ramp's landing, which it stood 0.3m inside.
	# Invisible until all six of these were given distinct names — five of them
	# had been skipped by the placement audit entirely.
	{"position": Vector3(7.2, 0, 2.0), "rotation": -110, "scale": 0.7},
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
## Weathered timber for the kit's raised platforms and their matching stairs.
const TIMBER_COLOUR := Color(0.29, 0.235, 0.17)
const TREAD_DEPTH := 0.34
const TREAD_THICKNESS := 0.12
const STRINGER_THICKNESS := 0.22

## The kit's doorway lintel. It hangs from 3.25m, clear of head height.
const DOORWAY_BEAM := "gate-overhang"

## Things that are drawn here but whose collision comes from somewhere else —
## the cave's box shell, a deck body, a ramp body — or that are out of reach
## and need none at all.
##
## Declared rather than inferred so that tools/audit_collision.gd can hold
## everything else to the rule that it must carry its own collider. The
## polarity matters: marking what is exempt means the next prop somebody adds
## is audited by default, where marking what is solid would let it slip through
## unnoticed.
const SHELL_BACKED := "collision_provided_elsewhere"

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
	# There were three of these. The third sat in an outer chamber and kept
	# landing on that chamber's spawn points and its supply crate — the outer
	# rooms are 9m across and a deck plus its ramp is most of that. Two decks in
	# the arena, where fights actually concentrate, is the better trade.
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
## Where the crate sits inside its chamber.
##
## Checked against SPAWN_SPREAD by tools/audit_placement.gd: it has to clear
## every spawn point in the chamber, and still fit inside a 9m walkable room.
const CACHE_OFFSET := Vector3(2.8, 0.0, 0.0)

const CACHE_CELLS := [
	Vector2i(0, 7),
	Vector2i(-5, 0),
	Vector2i(5, 0),
	Vector2i(0, -8),
	Vector2i(-4, -4),
	Vector2i(12, 0),
]

## Flat weapon cases from the Kenney Blaster Kit (CC0), as floor dressing.
## They are 0.23m tall, so they are scenery rather than cover.
const PROPS := [
	# Pulled back from the north ramp, whose footprint it was touching.
	{"model": "crate-wide", "position": Vector3(3.2, 0, 1.2), "rotation": 24},
	{"model": "crate-medium", "position": Vector3(-3.6, 0, 1.6), "rotation": -52},
	# Was sitting inside the south deck and its ramp at once. Now that props
	# are solid this would have been a crate embedded in a staircase that you
	# could also stand on.
	{"model": "crate-small", "position": Vector3(-2.0, 0, -1.5), "rotation": 88},
]

## Retain the atlas detail in neutral stone; world-space mottling spans seams.
const STONE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D stone_atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform bool textured = true;
uniform vec4 stone_color : source_color = vec4(0.48, 0.47, 0.435, 1.0);
uniform float variation = 1.0;
uniform vec3 grain_scale = vec3(14.0);
uniform vec3 mottle_scale = vec3(0.7, 1.5, 0.7);
uniform float strata_strength = 0.025;
varying vec3 world_position;
float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float stone_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
		mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
		mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float atlas = 0.55;
	if (textured) {
		atlas = dot(texture(stone_atlas, UV).rgb, vec3(0.2126, 0.7152, 0.0722));
	}
	float broad = stone_noise(world_position * mottle_scale);
	float grain = stone_noise(world_position * grain_scale);
	float strata = sin(world_position.y * 10.0 + broad * 7.0) * strata_strength;
	ALBEDO = stone_color.rgb * (0.64 + atlas * 0.7) *
		(0.79 + broad * 0.27 + grain * 0.12 + strata) * variation;
	ROUGHNESS = 0.92 + grain * 0.08;
	SPECULAR = 0.18;
}
"""

@export var generation_seed := 20260919
## The main menu uses this scene purely as a backdrop and has nothing to
## navigate, so it can skip the bake.
@export var bake_navigation := true

@export_group("Atmosphere")
## Set from the graphics preset before the arena builds itself.
@export var quality: GameSettings.Quality = GameSettings.Quality.HIGH
@export var dust_enabled := true
@export var dust_amount := 45

@export_group("Ceiling")
## A roof closes the cave in. Without it the player sees over the walls into
## empty space, which reads as an unfinished level rather than a cave.
@export var ceiling_enabled := true
## Minimum roof baseline. Irregular facets rise above it and blend into walls.
@export var ceiling_height := 5.6
@export var ceiling_colour := Color(0.32, 0.31, 0.285)


@export_group("Dressing")
## Overhead beams where corridors meet chambers.
@export var doorways_enabled := true

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
var _stone_shader: Shader
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

	# Roof dressing is added after baking so overhead rock cannot become
	# a disconnected walkable surface.
	if ceiling_enabled:
		_build_ceiling()

	_build_caches()
	_build_doorways()

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
		environment.fog_density = 0.018


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
	instance.add_to_group(SHELL_BACKED)
	_geometry_root.add_child(instance)

	_add_nav_surface(cell, _footprint_for(model, rotation_degrees))

	# A crossroads is walkable along both axes, so it contributes two strips.
	if EXTRA_FOOTPRINTS.has(model):
		_add_nav_surface(cell, _turned(EXTRA_FOOTPRINTS[model], rotation_degrees))

	# Stone stays neutral; fixtures carry subtle temperature differences.
	var profile := _lighting_profile_for(model, cell)
	_tint_rock(instance, profile.color)
	_add_lighting(model, cell, profile)


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
	return _turned(footprint, rotation_degrees)


## Swap a footprint's axes when a piece is stood a quarter turn round.
func _turned(footprint: Vector2, rotation_degrees: float) -> Vector2:
	var quarter_turned := is_equal_approx(fposmod(rotation_degrees, 180.0), 90.0)
	return Vector2(footprint.y, footprint.x) if quarter_turned else footprint


## Fallback lighting per piece type, keyed by model. Used for every layout
## cell that CHAMBER_IDENTITY does not name explicitly below — which is
## every plain corridor cell, and the safety net for any piece type this
## table has not been taught a chamber identity for.
##
## `height` is the lamp's absolute world Y (cells are all at Y=0, so this is
## the whole offset): rooms hang their lamp a little higher than the low
## corridor ceiling, which is as much a silhouette cue as a light source.
const _DEFAULT_LIGHTING := {
	CENTRE_ROOM: {"color": Color(1.0, 0.90, 0.76), "energy": 3.5, "range": 17.0, "height": 4.6},
	OUTER_ROOM: {"color": Color(1.0, 0.91, 0.79), "energy": 2.6, "range": 12.0, "height": 4.2},
	WIDE_ROOM: {"color": Color(1.0, 0.91, 0.79), "energy": 2.8, "range": 15.0, "height": 4.4},
	CORNER_ROOM: {"color": Color(0.86, 0.91, 1.0), "energy": 2.5, "range": 10.0, "height": 4.1},
	CROSS: {"color": Color(0.93, 0.95, 1.0), "energy": 1.8, "range": 8.0, "height": 3.8},
	DEAD_END: {"color": Color(1.0, 0.89, 0.74), "energy": 0.9, "range": 5.5, "height": 3.8},
	CORRIDOR: {"color": Color(0.80, 0.87, 1.0), "energy": 1.1, "range": 6.0, "height": 3.8},
}

## Subtle temperature shifts rather than a separate hue per room.
const CHAMBER_IDENTITY := {
	Vector2i(0, 12): {"color": Color(0.84, 0.90, 1.0), "energy": 2.9},
	Vector2i(0, 7): {"color": Color(0.90, 0.94, 1.0)},
	Vector2i(-5, 0): {"color": Color(1.0, 0.92, 0.80)},
	Vector2i(5, 0): {"color": Color(0.87, 0.92, 1.0)},
	Vector2i(0, -8): {"color": Color(1.0, 0.87, 0.72), "energy": 2.7},
	Vector2i(12, 0): {"color": Color(0.91, 0.94, 1.0)},
	Vector2i(-11, 0): {"color": Color(0.84, 0.90, 1.0), "energy": 2.5},
}

## Combine a piece's model default with any chamber-specific override for its
## cell. Every layout cell resolves to a full profile even when it is not
## named in CHAMBER_IDENTITY, so adding a new placement never leaves a light
## with missing fields.
func _lighting_profile_for(model: String, cell: Vector2i) -> Dictionary:
	var profile: Dictionary = (
		_DEFAULT_LIGHTING.get(model, _DEFAULT_LIGHTING[CORRIDOR]) as Dictionary
	).duplicate()
	if CHAMBER_IDENTITY.has(cell):
		profile.merge(CHAMBER_IDENTITY[cell], true)
	return profile


## Restrained work lights leave dark intervals between chambers.
func _add_lighting(model: String, cell: Vector2i, profile: Dictionary) -> void:
	# Corridors are lit every few cells rather than every cell. With the map at
	# its current size that is the difference between roughly ninety lights and
	# nearly three hundred, and a run of evenly spaced lamps reads better than
	# a continuous strip anyway — the dark stretches between them are what make
	# a corridor feel long.
	if model == CORRIDOR and posmod(cell.x + cell.y, CORRIDOR_LIGHT_SPACING) != 0:
		return

	var light := OmniLight3D.new()
	light.position = _cell_to_world(cell) + Vector3.UP * float(profile.height)
	light.light_color = profile.color
	light.light_energy = profile.energy
	light.omni_range = profile.range
	light.shadow_enabled = false

	# Only the arena itself casts shadows — tied to the cell rather than the
	# model, so the deep north chamber (the same room-large piece) does not
	# quietly double that cost. The cost is worth it where the player actually
	# fights, and invisible everywhere else.
	if cell == Vector2i(0, 0):
		light.shadow_enabled = quality >= GameSettings.Quality.MEDIUM

	# A light the player cannot see is still a light the renderer pays for.
	# The map is now far larger than anything visible at once, so lights fade
	# out well beyond the fog rather than accumulating across the whole cave.
	light.distance_fade_enabled = true
	light.distance_fade_begin = LIGHT_FADE_BEGIN
	light.distance_fade_length = LIGHT_FADE_LENGTH

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


## Suspended work lights have a dark housing and cable anchored into the roof.
func _add_lamp_glow(light: OmniLight3D) -> void:
	var fixture := Node3D.new()
	fixture.name = "WorkLight"
	fixture.add_to_group(SHELL_BACKED)
	_geometry_root.add_child(fixture)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.065, 0.072, 0.075)
	metal.roughness = 0.8
	metal.metallic = 0.65
	var anchor: Vector3 = light.position + Vector3.UP * 0.22
	var housing: MeshInstance3D = _add_detail_box(fixture, Vector3(0.6, 0.12, 0.28), anchor, metal)
	# A small housing next to a point source otherwise casts an enormous square
	# across the roof. The room geometry still casts the central light's shadows.
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cable_height: float = ceiling_height + 2.8 - anchor.y
	_add_detail_box(fixture, Vector3(0.025, cable_height, 0.025),
		anchor + Vector3.UP * (cable_height * 0.5), metal)
	var diffuser := StandardMaterial3D.new()
	diffuser.albedo_color = light.light_color
	diffuser.emission_enabled = true
	diffuser.emission = light.light_color
	diffuser.emission_energy_multiplier = 1.8
	_add_detail_box(fixture, Vector3(0.45, 0.035, 0.19),
		anchor - Vector3.UP * 0.072, diffuser)
	for mesh_instance: MeshInstance3D in _find_mesh_instances(fixture):
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _stone_material(texture: Texture2D, tint: Color, variation: float = 1.0) -> ShaderMaterial:
	if _stone_shader == null:
		_stone_shader = Shader.new()
		_stone_shader.code = STONE_SHADER
	var material := ShaderMaterial.new()
	material.shader = _stone_shader
	material.set_shader_parameter("textured", texture != null)
	if texture != null:
		material.set_shader_parameter("stone_atlas", texture)
	material.set_shader_parameter("stone_color", tint)
	material.set_shader_parameter("variation", variation)
	return material


func _timber_material() -> ShaderMaterial:
	var material: ShaderMaterial = _stone_material(null, TIMBER_COLOUR)
	material.set_shader_parameter("grain_scale", Vector3(0.6, 18.0, 18.0))
	material.set_shader_parameter("mottle_scale", Vector3(0.3, 3.0, 3.0))
	material.set_shader_parameter("strata_strength", 0.0)
	return material


func _tint_rock(instance: Node3D, _identity_colour: Color) -> void:
	var variation: float = 1.0 + _rng.randf_range(-0.04, 0.04)
	for mesh_instance in _find_mesh_instances(instance):
		for surface in mesh_instance.mesh.get_surface_count():
			var material: Material = mesh_instance.get_active_material(surface)
			if material is StandardMaterial3D:
				mesh_instance.set_surface_override_material(surface, _stone_material(
					material.albedo_texture, Color(0.48, 0.47, 0.435), variation))


func _add_detail_box(parent: Node3D, size: Vector3, at: Vector3,
		material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance


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
	for index in COVER.size():
		var entry: Dictionary = COVER[index]
		var instance := _instantiate(CAVE_PATH % "template-detail")
		if instance == null:
			continue

		instance.position = entry.position
		instance.rotation.y = deg_to_rad(entry.rotation)
		instance.scale = Vector3.ONE * entry.scale
		# Numbered, because add_child renames a duplicate name to something
		# generated — and the tools that look for these in the live tree find
		# them by name. Naming all six "Cover" meant five of them vanished from
		# tools/audit_placement.gd without the audit noticing it had stopped
		# checking them.
		instance.name = "Cover_%d" % index
		_geometry_root.add_child(instance)
		_add_cover_collider(instance, entry.scale)
		_tint_rock(instance, Color.WHITE)


func _build_props() -> void:
	for index in PROPS.size():
		var entry: Dictionary = PROPS[index]
		var instance := _instantiate(PROP_PATH % entry.model)
		if instance == null:
			continue

		instance.position = entry.position
		instance.rotation.y = deg_to_rad(entry.rotation)
		# Named so tools/audit_placement.gd can find it in the live tree rather
		# than re-deriving where it ought to be from the table, and numbered so
		# that all three survive being added — see _build_cover.
		instance.name = "Prop_%d" % index
		_geometry_root.add_child(instance)

		# These are shin-high footlockers, so collision turns each one into a
		# step rather than a wall — the player's step assist clears 0.45m and
		# these are 0.35m. Without it they were scenery you walked through.
		MeshCollision.fit(instance)


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
		# Offset from the chamber centre, clear of every point in SPAWN_SPREAD.
		# The first version sat 0.7m from one of them, so zombies arrived
		# standing inside the supply crate in all six chambers.
		cache.position = _cell_to_world(cell) + CACHE_OFFSET
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
		# Work lights keep enemy silhouettes readable on the raised routes.
		var light := OmniLight3D.new()
		light.name = "PlatformWorkLight"
		light.position = Vector3(entry.centre.x, 5.3, entry.centre.y)
		light.light_color = Color(0.90, 0.94, 1.0)
		light.light_energy = 1.4
		light.omni_range = 8.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = LIGHT_FADE_BEGIN
		light.distance_fade_length = LIGHT_FADE_LENGTH
		_geometry_root.add_child(light)
		_add_lamp_glow(light)


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
			for mesh_instance: MeshInstance3D in _find_mesh_instances(block):
				mesh_instance.material_override = _timber_material()
			block.add_to_group(SHELL_BACKED)
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


## Horizontal timber treads on narrow stringers; existing ramp collision and
## navigation links remain the authoritative traversal surface.
func _add_ramp_visual(transform: Transform3D, size: Vector3, centre: Vector2) -> void:
	var root := Node3D.new()
	root.name = "Ramp_%d_%d" % [int(centre.x), int(centre.y)]
	root.add_to_group(SHELL_BACKED)
	_geometry_root.add_child(root)
	var timber: ShaderMaterial = _timber_material()
	var along_x: bool = size.x > size.z
	var slope_length: float = maxf(size.x, size.z)
	var axis := Vector3.RIGHT if along_x else Vector3.BACK
	var across := Vector3.BACK if along_x else Vector3.RIGHT
	var start: Vector3 = transform * (-axis * slope_length * 0.5)
	var finish: Vector3 = transform * (axis * slope_length * 0.5)
	var horizontal_run: float = Vector2(finish.x - start.x, finish.z - start.z).length()
	var count: int = ceili(horizontal_run / TREAD_DEPTH)
	var depth: float = horizontal_run / float(count)
	for index in count:
		var fraction: float = (float(index) + 0.5) / float(count)
		var at: Vector3 = start.lerp(finish, fraction)
		at.y += transform.basis.y.y * RAMP_THICKNESS * 0.5 - TREAD_THICKNESS * 0.5
		var tread_size := Vector3(depth + 0.018, TREAD_THICKNESS, RAMP_WIDTH)
		if not along_x:
			tread_size = Vector3(RAMP_WIDTH, TREAD_THICKNESS, depth + 0.018)
		_add_detail_box(root, tread_size, at, timber)
	for side in [-1.0, 1.0]:
		var beam_size := Vector3(slope_length, STRINGER_THICKNESS, 0.16)
		if not along_x:
			beam_size = Vector3(0.16, STRINGER_THICKNESS, slope_length)
		var beam: MeshInstance3D = _add_detail_box(root, beam_size,
			transform.origin + across * side * (RAMP_WIDTH * 0.5 - 0.18), timber)
		beam.basis = transform.basis


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


## Continuous irregular roof. Shared world-space samples prevent module seams.
## Its lowest point clears a standing player on the 3m decks.
func _build_ceiling() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = generation_seed + 81
	noise.frequency = 0.12
	noise.fractal_octaves = 3
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var occupied: Dictionary = _occupied_cells()
	for cell: Vector2i in occupied:
		var origin: Vector3 = _cell_to_world(cell) - Vector3(CELL * 0.5, 0, CELL * 0.5)
		for x in 2:
			for z in 2:
				var corner: Vector3 = origin + Vector3(x * 2.0, 0, z * 2.0)
				var a: Vector3 = _roof_point(corner, noise)
				var b: Vector3 = _roof_point(corner + Vector3(2, 0, 0), noise)
				var c: Vector3 = _roof_point(corner + Vector3(2, 0, 2), noise)
				var d: Vector3 = _roof_point(corner + Vector3(0, 0, 2), noise)
				_add_rock_triangle(surface, a, b, c)
				_add_rock_triangle(surface, a, c, d)
		# Rock aprons join the roof into the walls above player headroom.
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if occupied.has(cell + direction):
				continue
			var normal := Vector3(direction.x, 0, direction.y)
			var tangent := Vector3(-direction.y, 0, direction.x)
			var edge: Vector3 = _cell_to_world(cell) + normal * CELL * 0.5
			for segment in 2:
				var a: Vector3 = _roof_point(edge + tangent * (float(segment) * 2.0 - 2.0), noise)
				var b: Vector3 = _roof_point(edge + tangent * float(segment) * 2.0, noise)
				var c := Vector3(b.x, 2.6, b.z)
				var d := Vector3(a.x, 2.6, a.z)
				var mid_a := Vector3(a.x, 4.8 + noise.get_noise_2d(a.x, a.z) * 0.5, a.z)
				var mid_b := Vector3(b.x, 4.8 + noise.get_noise_2d(b.x, b.z) * 0.5, b.z)
				# A shallow rock shoulder joins the upper wall into the vault.
				# It remains behind the existing collision shell's inner face.
				mid_a -= normal * 0.18
				mid_b -= normal * 0.18
				_add_rock_triangle(surface, a, b, mid_b)
				_add_rock_triangle(surface, a, mid_b, mid_a)
				_add_rock_triangle(surface, mid_a, mid_b, c)
				_add_rock_triangle(surface, mid_a, c, d)
	var roof := MeshInstance3D.new()
	roof.name = "Ceiling"
	roof.mesh = surface.commit()
	roof.material_override = _stone_material(null, ceiling_colour)
	roof.add_to_group(SHELL_BACKED)
	add_child(roof)


func _roof_point(point: Vector3, noise: FastNoiseLite) -> Vector3:
	var height: float = ceiling_height + 0.5 + (noise.get_noise_2d(point.x, point.z) + 1.0) * 1.15
	var x: float = point.x + noise.get_noise_2d(point.x + 117.0, point.z) * 0.65
	var z: float = point.z + noise.get_noise_2d(point.x, point.z - 83.0) * 0.65
	return Vector3(x, height, z)


func _add_rock_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	var points: Array[Vector3] = [a, b, c]
	if normal.y > 0.0:
		normal = -normal
		points = [a, c, b]
	for point: Vector3 in points:
		surface.set_normal(normal)
		surface.add_vertex(point)


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


## Frame every corridor mouth with an overhead beam.
##
## The cave read as tunnels bored through rock with nothing to say who bored
## them. A lintel where a corridor meets a chamber does two jobs at once: it
## makes the place look worked rather than natural, and it gives the eye a
## frame that marks a threshold — which matters in a game where knowing which
## opening something is about to come through is the whole problem.
##
## Derived from the layout rather than hand-placed. A hand-placed list would
## drift the moment the network changed, and this network has already been
## rebuilt once.
func _build_doorways() -> void:
	if not doorways_enabled:
		return

	var rooms := _room_cells()
	var placed := {}

	for entry in LAYOUT:
		if CELL_EXTENTS.get(entry.model, Vector2i.ZERO) != Vector2i.ZERO:
			continue

		for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var neighbour: Vector2i = entry.cell + direction
			if not rooms.has(neighbour):
				continue

			# Key on the pair so a corridor between two chambers does not get
			# two beams stacked in the same doorway.
			var key := "%s|%s" % [entry.cell, neighbour]
			if placed.has(key):
				continue
			placed[key] = true

			_add_doorway(entry.cell, direction)


## Cells belonging to a piece large enough to be a chamber.
func _room_cells() -> Dictionary:
	var cells := {}

	for entry in LAYOUT:
		var extent: Vector2i = CELL_EXTENTS.get(entry.model, Vector2i.ZERO)
		if extent == Vector2i.ZERO:
			continue

		if is_equal_approx(fposmod(float(entry.rotation), 180.0), 90.0):
			extent = Vector2i(extent.y, extent.x)

		for x in range(entry.cell.x - extent.x, entry.cell.x + extent.x + 1):
			for y in range(entry.cell.y - extent.y, entry.cell.y + extent.y + 1):
				cells[Vector2i(x, y)] = true

	return cells


func _add_doorway(cell: Vector2i, direction: Vector2i) -> void:
	var beam := _instantiate(CAVE_PATH % DOORWAY_BEAM)
	if beam == null:
		return

	# Sits on the boundary between the two cells rather than in either of them,
	# so it frames the gap instead of hanging over one side of it.
	var edge := Vector3(
		float(direction.x) * CELL * 0.5, 0.0, float(direction.y) * CELL * 0.5
	)
	beam.position = _cell_to_world(cell) + edge

	# The beam spans X unrotated, so a doorway facing along Z needs a quarter
	# turn to lie across the opening rather than along it.
	if direction.x != 0:
		beam.rotation.y = deg_to_rad(90.0)

	for mesh_instance: MeshInstance3D in _find_mesh_instances(beam):
		mesh_instance.material_override = _timber_material()
	beam.name = "Doorway"
	beam.add_to_group(SHELL_BACKED)
	_geometry_root.add_child(beam)
