class_name DreadDirector
extends Node

## The sound of something that was never there.
##
## Every other system in this game reports something real: a footstep the
## player actually took, a zombie that actually noticed, a shot that actually
## fired. This one does not. DreadDirector plays fake, positional sounds of
## presence — a step behind you, a call in the distance, the cave settling,
## a breath too close — that never touch the spawner, never alert a zombie,
## and never appear on the HUD. They exist only in the player's ears.
##
## The trigger for a phantom is the *absence* of danger, not its presence.
## Real threat already has the pulse in Ambience and the zombies themselves
## to carry tension; a phantom that fired on top of a real chase would just
## be noise competing with noise. Phantoms are reserved for the quiet, and
## get louder the longer the quiet holds — the longer nothing has happened,
## the more the cave has to say about it.
##
## The one rule every phantom kind obeys: it is allowed to almost convince the
## player and it is never allowed to finish the job while they are looking
## straight at it. FOOTSTEPS_BEHIND cancels itself the instant the camera
## turns toward the point it was walking from, so a player who spins around
## to confront the sound finds nothing — because there correctly was nothing,
## and the game does not get to cheat that by finishing the step anyway.

signal phantom_played(kind: int, at: Vector3)

enum Kind { FOOTSTEPS_BEHIND, DISTANT_CALL, CAVE_SETTLE, CLOSE_BREATH }

## Below this threat the calm clock counts up. Real danger does not need
## fake danger, so nothing phantom starts while threat sits at or above it.
@export var calm_threshold := 0.12
## At or above this threat the calm clock resets to zero outright — a spike
## in danger erases the quiet that was building, rather than merely pausing it.
@export var interrupt_threshold := 0.45
## Minimum real time between the end of one phantom and the start of the next,
## regardless of how calm the cave has been.
@export var min_gap := 28.0
## Minimum unbroken calm before the very first phantom of a round is allowed.
@export var calm_before_first := 15.0
## Chance per second of a phantom starting, the moment min_gap and
## calm_before_first are both satisfied.
@export var base_chance := 0.02
## Chance per second once the calm has run for calm_before_first + calm_ramp
## seconds. The longer it is quiet, the more the cave talks.
@export var max_chance := 0.07
## Seconds of additional calm, past calm_before_first, to ramp from
## base_chance to max_chance.
@export var calm_ramp := 90.0

## FOOTSTEPS_BEHIND: where the sequence starts, in metres behind the listener.
@export var behind_distance_min := 7.0
@export var behind_distance_max := 12.0
## Jitter either side of the listener's exact flat-behind direction, degrees.
@export var behind_jitter_deg := 35.0
## How many steps a footsteps-behind sequence plays, before it is cut short.
@export var step_count_min := 3
@export var step_count_max := 6
## Seconds between one phantom step and the next.
@export var step_interval_min := 0.42
@export var step_interval_max := 0.55
## Metres the phantom point closes toward the listener with each step — it is
## meant to read as closing in.
@export var step_close_distance := 0.6
## If the camera's flat forward comes within this many degrees of the
## direction to the phantom point, the sequence stops before the next step
## plays. The player turned around; there is nothing there.
@export var look_cut_angle := 70.0

## DISTANT_CALL: metres away, any direction.
@export var distant_distance_min := 22.0
@export var distant_distance_max := 35.0

## CAVE_SETTLE: metres away, any direction.
@export var settle_distance_min := 8.0
@export var settle_distance_max := 18.0

## CLOSE_BREATH: metres behind the listener. Only offered once _calm exceeds
## breath_calm_threshold, and never more than once per round — a phantom this
## intimate stops being unsettling the moment it is familiar.
@export var breath_distance_min := 1.5
@export var breath_distance_max := 2.5
@export var breath_calm_threshold := 60.0

## Relative weights for picking a phantom kind once one is due to start.
@export var weight_footsteps := 3.0
@export var weight_distant := 2.0
@export var weight_settle := 3.0
@export var weight_breath := 1.0

var _sounds: SoundBank
var _listener: Node3D
var _camera: Camera3D

var _active := true
var _rng := RandomNumberGenerator.new()

var _calm := 0.0
var _time_since_last := 0.0
var _roll_accum := 0.0
var _breath_played := false
var _phantoms_played := 0

var _footsteps_active := false
var _footsteps_point := Vector3.ZERO
var _footsteps_remaining := 0
var _footsteps_timer := 0.0


func _ready() -> void:
	_rng.randomize()


## Wire the director to the systems it reads and plays into. Called once by
## Game; nothing here is created in _ready because the listener and camera
## belong to the Player scene and are not guaranteed to exist yet.
func bind(sounds: SoundBank, listener: Node3D, camera: Camera3D) -> void:
	_sounds = sounds
	_listener = listener
	_camera = camera


## Enable or disable phantoms outright. Game calls this everywhere the weapon
## and look are disabled — pause, level-up, extraction — and the reverse when
## they are re-enabled, so a phantom never plays while the player cannot even
## turn to look for it. A sequence in progress is cancelled, not paused.
func set_active(active: bool) -> void:
	_active = active
	if not active:
		_footsteps_active = false


## Return every clock to its opening state for a fresh round. _time_since_last
## starts at min_gap so the gap requirement is already satisfied at t=0 — only
## calm_before_first should gate the first phantom of a round.
func reset() -> void:
	_calm = 0.0
	_time_since_last = min_gap
	_roll_accum = 0.0
	_breath_played = false
	_phantoms_played = 0
	_footsteps_active = false
	_footsteps_remaining = 0
	_footsteps_timer = 0.0


## Swap in a seeded RNG for deterministic tests.
func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


func phantoms_played() -> int:
	return _phantoms_played


## Advance every clock and, if due, start or continue a phantom. Called by
## Game every frame the round is PLAYING, fed the same smoothed threat figure
## the HUD and Ambience read.
func tick(delta: float, threat: float) -> void:
	if not _active or _sounds == null or _listener == null:
		return

	_update_calm(delta, threat)
	_time_since_last += delta

	if _footsteps_active:
		_advance_footsteps(delta)
		return

	if threat >= calm_threshold:
		return
	if _time_since_last < min_gap:
		return
	if _calm < calm_before_first:
		return

	_roll_for_phantom(delta)


func _update_calm(delta: float, threat: float) -> void:
	if threat >= interrupt_threshold:
		_calm = 0.0
	elif threat < calm_threshold:
		_calm += delta
	# Between the two thresholds the clock simply holds — not calm enough to
	# grow the quiet, not dangerous enough to erase it.


func _roll_for_phantom(delta: float) -> void:
	_roll_accum += delta
	while _roll_accum >= 1.0:
		_roll_accum -= 1.0
		var chance := lerpf(
			base_chance,
			max_chance,
			clampf((_calm - calm_before_first) / calm_ramp, 0.0, 1.0)
		)
		if _rng.randf() < chance:
			_trigger_phantom()
			return


func _trigger_phantom() -> void:
	match _pick_kind():
		Kind.FOOTSTEPS_BEHIND:
			_start_footsteps()
		Kind.DISTANT_CALL:
			_play_distant()
		Kind.CAVE_SETTLE:
			_play_settle()
		Kind.CLOSE_BREATH:
			_play_breath()


func _pick_kind() -> int:
	var options: Array[int] = [Kind.FOOTSTEPS_BEHIND, Kind.DISTANT_CALL, Kind.CAVE_SETTLE]
	var weights: Array[float] = [weight_footsteps, weight_distant, weight_settle]

	if _calm > breath_calm_threshold and not _breath_played:
		options.append(Kind.CLOSE_BREATH)
		weights.append(weight_breath)

	var total := 0.0
	for w in weights:
		total += w

	var roll := _rng.randf() * total
	var cursor := 0.0
	for i in options.size():
		cursor += weights[i]
		if roll < cursor:
			return options[i]

	return options[options.size() - 1]


## Start a footsteps-behind sequence. Exposed (rather than fully private) so
## tests can force one without waiting on the scheduler's roll.
func _start_footsteps() -> void:
	var behind_dir := -_flat_forward(_listener)
	var jitter := deg_to_rad(_rng.randf_range(-behind_jitter_deg, behind_jitter_deg))
	var dir := behind_dir.rotated(Vector3.UP, jitter)
	var dist := _rng.randf_range(behind_distance_min, behind_distance_max)

	_footsteps_point = _walkable(_listener.global_position + dir * dist)
	_footsteps_remaining = _rng.randi_range(step_count_min, step_count_max)
	_footsteps_timer = 0.0
	_footsteps_active = true

	_finish_phantom(Kind.FOOTSTEPS_BEHIND, _footsteps_point)


func _advance_footsteps(delta: float) -> void:
	_footsteps_timer -= delta
	if _footsteps_timer > 0.0:
		return

	# The paranoia trick: if the camera has turned toward the point, there is
	# nothing there to keep walking, so the sequence ends before this step.
	if _is_looking_at(_footsteps_point):
		_footsteps_active = false
		return

	_sounds.play_at("phantom_step", _footsteps_point)
	_footsteps_remaining -= 1

	if _footsteps_remaining <= 0:
		_footsteps_active = false
		return

	_footsteps_point = _footsteps_point.move_toward(_listener.global_position, step_close_distance)
	_footsteps_timer = _rng.randf_range(step_interval_min, step_interval_max)


func _play_distant() -> void:
	var dist := _rng.randf_range(distant_distance_min, distant_distance_max)
	var pos := _listener.global_position + _random_flat_direction() * dist
	_sounds.play_at("phantom_distant", pos)
	_finish_phantom(Kind.DISTANT_CALL, pos)


func _play_settle() -> void:
	var dist := _rng.randf_range(settle_distance_min, settle_distance_max)
	var pos := _listener.global_position + _random_flat_direction() * dist
	_sounds.play_at("phantom_settle", pos)
	_finish_phantom(Kind.CAVE_SETTLE, pos)


func _play_breath() -> void:
	_breath_played = true
	var dist := _rng.randf_range(breath_distance_min, breath_distance_max)
	var pos := _walkable(_listener.global_position - _flat_forward(_listener) * dist)
	_sounds.play_at("phantom_breath", pos)
	_finish_phantom(Kind.CLOSE_BREATH, pos)


func _finish_phantom(kind: int, at: Vector3) -> void:
	_phantoms_played += 1
	_time_since_last = 0.0
	phantom_played.emit(kind, at)


func _flat_forward(node: Node3D) -> Vector3:
	var forward := -node.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


## The nearest point a body could actually stand on. A step heard from inside
## solid rock is a step nobody could have taken, and the labyrinth puts rock
## behind the player more often than not. Falls back to the raw point when
## there is no navigation map yet (tests, the first frames of a round).
func _walkable(point: Vector3) -> Vector3:
	if not _listener.is_inside_tree():
		return point
	var map := _listener.get_world_3d().navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return point
	return NavigationServer3D.map_get_closest_point(map, point)


func _random_flat_direction() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	return Vector3(cos(angle), 0.0, sin(angle))


func _is_looking_at(point: Vector3) -> bool:
	if _camera == null:
		return false

	var forward := _flat_forward(_camera)
	var to_point := point - _camera.global_position
	to_point.y = 0.0
	if to_point.length() < 0.0001:
		return false

	var angle := rad_to_deg(forward.angle_to(to_point.normalized()))
	return angle <= look_cut_angle
