class_name DungeonDoorHandle
extends Interactable

## Makes the imported map's doors usable by this game's interaction system.
##
## `amethyst_labyrinth/door.gd` ships with the map and speaks a different
## dialect: it has `interact()` with no arguments, and it never joins the
## interactable group, so Interactor's scan cannot see it and its
## `has_method("can_interact")` check would reject it anyway.
##
## The fix is a handle rather than an edit to `door.gd`. The map is the owner's
## source of truth and the next export of it would overwrite anything written
## into that file; a shim added at runtime survives a re-export untouched. It
## also keeps the prompt text, the reach and the hold time — all game concerns
## — out of a file whose job is to swing a door.
##
## One of these is parented to each door, so it inherits the leaf's transform
## and the prompt tracks the door as it opens.

## Where the prompt sits relative to the door's hinge.
##
## The hinge is at one edge of the leaf, not its middle, so a handle left at
## the origin would ask the player to look at the doorframe rather than at the
## door. Half a leaf width along local X puts it on the door itself.
const HANDLE_OFFSET := Vector3(0.9, 0.0, 0.0)

var _door: Node3D


## Attach a handle to a door from the imported map.
##
## Static factory for the same reason Medkit.spawn is one: placement is then a
## single line at the call site and nothing outside this file needs to know
## how the two halves are joined.
static func attach(door: Node3D) -> DungeonDoorHandle:
	var handle := DungeonDoorHandle.new()
	handle._door = door
	handle.name = "InteractionHandle"
	handle.position = HANDLE_OFFSET
	# Generous, because a door is approached head-on down a corridor and the
	# player should not have to walk into it to be offered the prompt.
	handle.interaction_reach_metres = 3.5
	handle.interaction_focus_height = 1.2
	# Instant. A door is not a decision the way a medkit is — the cost of
	# opening one is the noise and the sightline it gives away, not the time.
	handle.interaction_hold_seconds = 0.0
	door.add_child(handle)
	return handle


## Doors latch open on purpose (see door.gd), so a door that has been used has
## nothing left to offer and should stop claiming the prompt.
func can_interact(_player: Node) -> bool:
	return _door != null and not _door.opened


func interaction_prompt(_player: Node) -> String:
	return "Open"


func interact(_player: Node) -> bool:
	if _door == null or _door.opened:
		return false
	_door.interact()
	return true
