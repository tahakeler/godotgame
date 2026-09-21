class_name SignalRelay
extends Interactable

## One signal relay: a beacon the player must reach, hold, and then survive.
##
## Implements design/gdd/objectives-and-exploration.md §3.2.
##
## A relay knows nothing about Game, the HUD or the spawner. It reports what it
## did — it armed, it made a noise — and something above it decides what that
## costs. Same rule the caches and medkits already follow, and the reason a
## crate never has to learn what a magazine is.
##
## The point of the object is that arming it is the loudest act in the game,
## performed at a dead end with one exit. Everything here exists to make that
## true: an uninterrupted hold, a pulse train during it, and a residual
## broadcast afterwards that the player has no way to switch off.

## The relay finished its hold. Whoever owns the chain listens here.
signal armed(relay: SignalRelay)
## A noise pulse left the beacon. Routed to Game._make_noise() by the owner —
## never straight to the spawner, or the relay would be loud without the noise
## ring ever telling the player it was.
signal noise_pulsed(at: Vector3, loudness: float)

## DORMANT -> ARMING -> ARMED is the only legal path. There is no way back from
## ARMED short of a round restart, which is the whole "cannot un-ring the bell"
## pressure the design is built on.
enum State { DORMANT, ARMING, ARMED }

@export_group("Relay")
## Seconds of unbroken hold to arm. Longer than the medkit's 2.0s so it reads
## as the biggest commitment in the game.
@export var relay_hold_duration := 3.0
## Loudness of each pulse while the hold is running. Twice the cache's 0.45 and
## near a gunshot — this is the number that sets the cost of the objective.
@export var relay_arming_loudness := 0.9
## Loudness of each pulse after arming. Above a footstep, below a crate.
@export var relay_residual_loudness := 0.35
## Seconds the residual broadcast runs. Zero is a valid tuning floor and simply
## removes the irreversibility; it is the Recruit-difficulty variant.
@export var relay_residual_duration := 20.0
## Seconds between pulses. Also the cost knob: halving it doubles the total.
@export var relay_pulse_interval := 0.5

## What the HUD calls this relay. Presentational only — relay order is free.
var label := "RELAY"

var _state: State = State.DORMANT
var _hold_elapsed := 0.0
var _residual_remaining := 0.0
var _pulse_remaining := 0.0

const BEACON_HEIGHT := 1.5
const DORMANT_COLOUR := Color(0.38, 0.52, 0.72)
const ARMED_COLOUR := Color(0.95, 0.35, 0.28)

var _light: OmniLight3D


func _ready() -> void:
	super()
	interaction_hold_seconds = relay_hold_duration
	# Reached from about as far as a crate: the beacon is a solid prop and the
	# player is stopped by it before they are standing on it.
	interaction_reach_metres = 3.2
	interaction_focus_height = BEACON_HEIGHT
	_build()
	_refresh_glow()


## --- Interaction contract ---------------------------------------------------
##
## See src/gameplay/interaction/interactable.gd.


func can_interact(_player: Node) -> bool:
	return _state != State.ARMED


func interaction_prompt(_player: Node) -> String:
	return "Arm relay"


func interaction_hold_time(_player: Node) -> float:
	return relay_hold_duration


## Called by Interactor once its own unbroken hold completes.
##
## The relay also arms itself from tick_hold() crossing the same threshold, and
## both paths are deliberate: the Interactor owns the prompt and the progress
## ring the player actually reads, while tick_hold() owns the pulse train and
## makes the relay drivable in a headless test with no player in front of it.
## They are keyed to the same duration and the same frame delta, so they cross
## together in game. _arm() is idempotent precisely so it does not matter which
## of the two gets there first.
func interact(player: Node) -> bool:
	if _state == State.ARMED:
		return false

	_arm()
	interacted.emit(player)
	return true


## --- Chain contract ---------------------------------------------------------


func state() -> State:
	return _state


func is_armed() -> bool:
	return _state == State.ARMED


## Fraction of the arming hold paid so far, 0..1.
func hold_progress() -> float:
	if relay_hold_duration <= 0.0:
		return 1.0
	return clampf(_hold_elapsed / relay_hold_duration, 0.0, 1.0)


## Advance an in-progress hold by one frame, pulsing as it goes.
##
## Called every frame the player is actually holding interact on this relay.
func tick_hold(delta: float) -> void:
	if _state == State.ARMED:
		return

	_state = State.ARMING
	_hold_elapsed += delta

	_pulse_remaining -= delta
	if _pulse_remaining <= 0.0:
		_pulse(relay_arming_loudness)
		_pulse_remaining = relay_pulse_interval

	if _hold_elapsed >= relay_hold_duration:
		_arm()


## Abandon an in-progress hold. No progress is banked, ever.
##
## Partial credit would turn the relay into something you chip at between
## waves, and the design is that it is one unbroken window of vulnerability.
func break_hold() -> void:
	if _state != State.ARMING:
		return

	_state = State.DORMANT
	_hold_elapsed = 0.0
	_pulse_remaining = 0.0
	_refresh_glow()


## Advance the residual broadcast. Called every frame regardless of the player.
func tick(delta: float) -> void:
	if _residual_remaining <= 0.0:
		return

	_residual_remaining -= delta
	_pulse_remaining -= delta

	if _pulse_remaining <= 0.0:
		_pulse(relay_residual_loudness)
		_pulse_remaining = relay_pulse_interval


## True while the beacon is still broadcasting after having been armed.
func is_broadcasting() -> bool:
	return _residual_remaining > 0.0


## Back to untouched. Called from Game.start_round() alongside cache.reset().
##
## This is the exact class of bug QA found twice — interact state surviving a
## lifecycle boundary. An armed relay must not survive a restart, and a hold at
## 2.9s of 3.0 must not complete on the first frame of the next round.
func reset() -> void:
	_state = State.DORMANT
	_hold_elapsed = 0.0
	_residual_remaining = 0.0
	_pulse_remaining = 0.0
	_refresh_glow()


func _arm() -> void:
	if _state == State.ARMED:
		return

	_state = State.ARMED
	_hold_elapsed = relay_hold_duration
	_residual_remaining = relay_residual_duration
	_pulse_remaining = relay_pulse_interval
	_refresh_glow()
	armed.emit(self)


func _pulse(loudness: float) -> void:
	if loudness <= 0.0:
		return

	# From the relay, not from the player. The crowd converges on the beacon,
	# so the play is to arm it and then not be standing next to it — the same
	# muzzle-not-player rule the gunshot noise already follows.
	noise_pulsed.emit(global_position, loudness)


## Cold blue means dormant, red means broadcasting. Legible from across a
## chamber, because "have I done this one" is asked from the doorway.
func _refresh_glow() -> void:
	if _light == null:
		return

	_light.light_color = ARMED_COLOUR if _state == State.ARMED else DORMANT_COLOUR
	_light.light_energy = 3.2 if _state == State.ARMED else 1.6


func _build() -> void:
	var mast := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.22
	mesh.height = BEACON_HEIGHT
	mast.mesh = mesh
	mast.position = Vector3(0.0, BEACON_HEIGHT * 0.5, 0.0)
	add_child(mast)
	# Solid, like the crate. A prop the player and the crowd can both walk
	# straight through is scenery, and the beacon is meant to be a thing you
	# stand at — tools/audit_collision.gd enforces exactly this.
	MeshCollision.fit(mast)

	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, BEACON_HEIGHT, 0.0)
	_light.omni_range = 8.0
	_light.shadow_enabled = false
	add_child(_light)
