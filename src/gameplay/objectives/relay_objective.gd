class_name RelayObjective
extends Node

## The relay chain: three beacons, then the run home.
##
## Implements design/gdd/objectives-and-exploration.md §3.2–§3.4.
##
## Owns the count, the extraction hold, and the one line of text that tells the
## player what they are doing. It does not own the HUD — it emits text and Game
## decides where text goes, the same rule the interactor's prompt follows.
##
## It also does not own the noise. Each relay emits noise_pulsed and Game wires
## that to _make_noise(), which is the single call that both broadcasts to the
## spawner and reports the cost to the HUD's noise ring.

## The objective line and the compass bearing changed. A bearing is a direction
## and nothing else — never a route, never a distance, never a minimap marker.
## The cave is a navigation problem and answering it would delete the cave.
signal objective_changed(text: String, bearing_target: Vector3, has_bearing: bool)
## The chain is done and the player made it home. Game ends the round.
signal completed()
## A relay finished arming. Game spawns the reward kit; the chain does not know
## what a medkit is.
signal relay_armed(relay: SignalRelay)

## Where each relay stands, and what the HUD calls it.
##
## The three furthest terminal chambers from the origin. The south WIDE_ROOM at
## (0,-8) is deliberately not one: it is only eight cells out and it sits on the
## route to the southern ring, so it is the chamber the player passes through
## anyway. Three relays that each require a dedicated trip is the point.
##
## The table lives here rather than in Arena's placement tables on purpose. The
## arena's cave layout is authored independently, and a chain that owns its own
## cells is one file to edit when a chamber moves, instead of a change landing
## in the middle of someone else's map.
##
## Offsets mirror Arena.CACHE_OFFSET's reasoning — clear of every point in
## SPAWN_SPREAD, and on the opposite side from the chamber's cache so the player
## is never made to choose between standing in a crate and standing in a relay.
const RELAY_PLACEMENTS := [
	{"cell": Vector2i(0, 12), "offset": Vector3(-2.8, 0.0, 0.0), "label": "DEEP NORTH"},
	{"cell": Vector2i(-11, 0), "offset": Vector3(0.0, 0.0, 2.8), "label": "WEST HALL"},
	{"cell": Vector2i(12, 0), "offset": Vector3(0.0, 0.0, 2.8), "label": "EAST HALL"},
]

@export_group("Chain")
## How many relays the chain needs. The session-length knob; two is the
## Recruit-difficulty cut.
@export var relay_count_required := 3
@export var relay_reward_kit := true

@export_group("Extraction")
## Where the player extracts: cell (0,0), their own spawn. Sending them home
## rather than to a fourth unexplored point is what makes the last leg a chase
## rather than a search.
@export var extraction_point := Vector3.ZERO
## Must comfortably contain the spawn without being trippable from a corridor
## mouth.
@export var extraction_radius := 4.0
## Non-zero so the win is taken, not stumbled into.
@export var extraction_hold_duration := 2.0

var relays: Array[SignalRelay] = []

var _player: Node3D
var _interactor: Interactor
var _enabled := false
var _active := false
var _extraction_elapsed := 0.0
var _finished := false
var _last_text := ""


## Stand the relays up in the cave and hand the chain the world it works in.
## Called once, from Game._ready().
##
## Placement happens here at runtime rather than from one of Arena's tables:
## the beacons are parented under the arena so they move with it, but the cave
## itself stays unaware that an objective exists. Built after the arena is
## ready, which is also after its navmesh bake — a relay is a prop and a
## trigger, and neither should contribute walkable surface or be carved out of
## it.
func bind(arena: Arena, player: Node3D, interactor: Interactor) -> void:
	_player = player
	_interactor = interactor
	relays.clear()

	for entry in RELAY_PLACEMENTS:
		var relay := SignalRelay.new()
		relay.name = "SignalRelay_%d_%d" % [entry.cell.x, entry.cell.y]
		relay.label = entry.label
		relay.position = arena._cell_to_world(entry.cell) + entry.offset
		arena.add_child(relay)
		relay.armed.connect(_on_relay_armed)
		relays.append(relay)


## Whether this mode uses the chain at all. Off in EXTRACTION, TIMED, ENDLESS,
## where the objective line is empty and nothing ticks.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled


## Whether the player currently has control. Mirrors exactly what Game already
## does to the weapon, the look and the interactor: off at round end, at pause,
## at level-up; on again when the round resumes.
##
## Without this a relay hold survives a death, which is the bug QA found on the
## interactor and the reason this method exists at all rather than the chain
## simply trusting Game to stop calling it.
func set_active(active: bool) -> void:
	if _active and not active:
		# Control is being taken away, so progress paid before that is
		# forfeited — the same forfeit letting go of the key produces.
		for relay in relays:
			relay.break_hold()
		_extraction_elapsed = 0.0

	_active = active


## Back to an untouched chain. Called from Game.start_round().
func reset() -> void:
	for relay in relays:
		relay.reset()

	_extraction_elapsed = 0.0
	_finished = false
	_last_text = ""
	_publish()


## How many relays are armed right now.
func armed_count() -> int:
	var count := 0
	for relay in relays:
		if relay.is_armed():
			count += 1
	return count


func is_chain_complete() -> bool:
	return armed_count() >= relay_count_required


## Fraction of the extraction hold paid, 0..1. Used by the tests and available
## to the HUD if a ring is ever wanted for it.
func extraction_progress() -> float:
	if extraction_hold_duration <= 0.0:
		return 1.0
	return clampf(_extraction_elapsed / extraction_hold_duration, 0.0, 1.0)


## The line the player reads, for the current state.
func objective_text() -> String:
	if not _enabled:
		return ""

	if _finished:
		return "EXTRACTING…"

	if is_chain_complete():
		if _extraction_elapsed > 0.0:
			return "EXTRACTING…"
		return "EXTRACT — RETURN TO THE ARENA"

	for relay in relays:
		if relay.state() == SignalRelay.State.ARMING:
			return "ARMING RELAY — %s" % relay.label

	return "SIGNAL RELAYS — %d OF %d ARMED" % [armed_count(), relay_count_required]


## Where the chevron points: the nearest dormant relay, or home once the chain
## is done. Null intent is reported as has_bearing == false rather than as a
## sentinel position, because a chevron pointing at the origin by accident is
## worse than no chevron.
func bearing_target() -> Vector3:
	if is_chain_complete():
		return extraction_point

	var best: Vector3 = extraction_point
	var best_distance := INF
	var found := false

	for relay in relays:
		if relay.is_armed():
			continue
		var distance: float = (
			relay.global_position.distance_to(_player.global_position)
			if _player != null else 0.0
		)
		if distance < best_distance:
			best_distance = distance
			best = relay.global_position
			found = true

	return best if found else extraction_point


func has_bearing() -> bool:
	return _enabled and not _finished


## One frame of the chain. Driven from Game._process() so the chain stops when
## the round does, without a second copy of the pause rules living here.
func tick(delta: float) -> void:
	if not _enabled or not _active or _finished:
		return

	var focus: Node = _interactor.focus() if _interactor != null else null

	for relay in relays:
		# The interactor's hold is the authority on whether the player is
		# actually paying: it already enforces reach, view angle and line of
		# sight, and it is already reset on every lifecycle boundary.
		if relay == focus and _interactor.hold_progress() > 0.0:
			relay.tick_hold(delta)
		else:
			relay.break_hold()

		relay.tick(delta)

	_tick_extraction(delta)
	_publish()


## Drive the chain's hold on a relay directly, bypassing the interactor.
##
## Exists for the headless tests, which run outside a physics frame and have no
## camera to aim. Everything after the hold — arming, pulses, the objective
## line — is the same code path the player drives.
func force_hold(relay: SignalRelay, delta: float) -> void:
	if not _enabled or not _active or _finished:
		return

	relay.tick_hold(delta)
	_publish()


## Advance time without anyone holding anything. Proves a relay never arms on a
## timer alone.
func tick_idle(delta: float) -> void:
	if not _enabled or not _active or _finished:
		return

	for relay in relays:
		relay.tick(delta)

	_tick_extraction(delta)
	_publish()


func _tick_extraction(delta: float) -> void:
	if not is_chain_complete() or _player == null:
		_extraction_elapsed = 0.0
		return

	var flat_player := Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	var flat_point := Vector3(extraction_point.x, 0.0, extraction_point.z)

	if flat_player.distance_to(flat_point) > extraction_radius:
		# Stepping out abandons the hold. A win you can leave halfway through
		# and come back to is not a run home, it is a checkpoint.
		_extraction_elapsed = 0.0
		return

	_extraction_elapsed += delta

	if _extraction_elapsed >= extraction_hold_duration:
		_finished = true
		_publish()
		completed.emit()


func _on_relay_armed(relay: SignalRelay) -> void:
	relay_armed.emit(relay)
	_publish()


## Emit only on a change. The objective line is read constantly and redrawn
## rarely; pushing the same string sixty times a second would make every
## listener pay for a state that did not move.
func _publish() -> void:
	var text := objective_text()
	if text == _last_text:
		return

	_last_text = text
	objective_changed.emit(text, bearing_target(), has_bearing())
