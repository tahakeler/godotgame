class_name Interactable
extends Node3D

## Base class for anything the player can use by pressing the interact key.
##
## CONTRACT — read this before adding a new usable object.
##
## The contract is duck-typed, and this class is a convenience rather than a
## requirement. Interactor only ever asks `has_method()` for:
##
##   can_interact(player) -> bool           may it be used right now
##   interaction_prompt(player) -> String   what the prompt says it will do
##   interaction_hold_time(player) -> float seconds of hold, 0 for instant
##   interact(player) -> bool               do it; true if something happened
##
## and optionally `interaction_point() -> Vector3` and `interaction_reach()
## -> float`, falling back to the node's own origin and the interactor's
## default reach when they are absent.
##
## Duck typing rather than a mandatory base class, because the objects that
## need the contract already exist and already have parents they cannot give
## up: AmmoCache is a Node3D that builds its own trigger Area, and a future
## door will want to be a StaticBody3D. Forcing everything through one
## inheritance chain would mean rewriting working objects. A contract that can
## be adopted without changing what you already are is one that will actually
## be adopted.
##
## What this class buys you if you do extend it: group registration, the
## reach/hold exports, and sane defaults for every method above.

## Emitted after a successful use. Systems that need to react (audio, noise,
## score) listen here rather than being called from inside the object, so a
## crate never has to learn what a magazine is.
signal interacted(player: Node)

## Every interactable joins this group on ready. Interactor scans the group
## rather than the physics world: the set is tiny (tens of nodes, not
## thousands) and a group scan works outside a physics frame, which a shape
## query does not — and the headless tests run outside one.
const GROUP := "interactable"

@export_group("Interaction")
## How far away the player may stand and still use this. Per-object rather than
## global, because a waist-high crate and a wall lever are reached from
## different distances and pretending otherwise makes one of them feel wrong.
@export var interaction_reach_metres := 3.0
## Seconds the key must be held. Zero means instant.
##
## Hold is not friction for its own sake: it is what turns a pickup into a
## decision, because in this game standing still is the most expensive thing
## you can do.
@export var interaction_hold_seconds := 0.0
## Where the prompt aims. Lifted off the floor so looking at an object at your
## feet still counts as looking at it.
@export var interaction_focus_height := 1.0


func _ready() -> void:
	add_to_group(GROUP)


## Whether this can be used right now. False hides the prompt entirely — the
## player should never be told to press a key that will do nothing.
func can_interact(_player: Node) -> bool:
	return true


## What the prompt says. Name the outcome ("Resupply"), not the object.
func interaction_prompt(_player: Node) -> String:
	return "Use"


func interaction_hold_time(_player: Node) -> float:
	return interaction_hold_seconds


## Perform the interaction. Return true only when something actually happened,
## so the interactor can stay silent on a no-op.
func interact(player: Node) -> bool:
	interacted.emit(player)
	return true


func interaction_point() -> Vector3:
	return global_position + Vector3.UP * interaction_focus_height


func interaction_reach() -> float:
	return interaction_reach_metres
