class_name Interactor
extends Node

## The player's half of the interaction contract: find what they are looking
## at, say what pressing the key will do, and run the hold.
##
## Lives on the player rather than on the objects, so there is exactly one
## place that decides what "in range and in view" means. When that rule lived
## inside each pickup — as it did for AmmoCache, which collected on touch —
## every new object got to invent its own, and the player had no consistent
## thing to learn.
##
## Presentation is a signal, never a call. This node has no idea a HUD exists;
## Game wires `prompt_changed` to it, which is what keeps the interaction
## system testable without a screen.

## Full prompt text, or "" when nothing is focused. The HUD clears on empty.
signal prompt_changed(text: String)
## The focused object changed. Carries null when focus is lost.
signal focus_changed(target: Node)
## A held interaction completed and the object accepted it.
signal interaction_completed(target: Node)
## A hold was started and let go before it finished. Emitted so audio can
## acknowledge the abort rather than the prompt silently resetting.
signal interaction_cancelled(target: Node)

## The action bound to E and to the pad. Named here so the string exists once.
const ACTION := "interact"

@export_group("Detection")
## Fallback reach for objects that do not declare their own.
@export var default_reach_metres := 3.0
## How far off the centre of the screen an object may sit and still count as
## looked at. Generous on purpose: a tight cone turns using a crate at your
## feet into an aiming exercise, and nothing here competes for the same key.
@export var view_angle_degrees := 60.0
## Whether the object must be in line of sight. Exported because the raycast is
## the one part of this that cannot run outside a physics frame.
@export var require_line_of_sight := true
## Physics layer the sight ray tests against. Layer 1 is world geometry: only
## rock should hide a prompt, not a zombie standing in front of the crate.
@export_flags_3d_physics var sight_mask := 1

@export_group("Prompt")
## Shown for instant interactions.
@export var press_format := "Press E — %s"
## Shown for held ones before the hold begins.
@export var hold_format := "Hold E — %s"
## Shown during a hold. Second slot is whole percent.
@export var progress_format := "Hold E — %s  %d%%"

var _player: Node3D
var _camera: Camera3D
var _focus: Node = null
var _hold_elapsed := 0.0
var _was_held := false
var _last_prompt := ""
## Mirrors Weapon._input_enabled. The round state machine already takes the
## weapon and the look away at a death, a win, a pause and a level-up; before
## this existed it did not take the interact key, so a results screen was a
## place where crates could still be emptied and world noise still emitted.
var _input_enabled := true


func _ready() -> void:
	_player = get_parent() as Node3D
	if _player != null and "camera" in _player:
		_camera = _player.camera as Camera3D


func _process(delta: float) -> void:
	tick(delta, Input.is_action_pressed(ACTION))


## The whole system, with the input already read.
##
## Split from _process so a test can drive it: Input cannot be synthesised
## meaningfully under `--headless --script`, and a system only reachable
## through a key press is a system that never gets asserted on.
func tick(delta: float, interact_held: bool) -> void:
	if not _input_enabled:
		# Drop any hold in progress rather than freezing it: control is being
		# taken away, and progress paid before that has to be forfeited the
		# same as letting go of the key does.
		if _focus != null or _hold_elapsed > 0.0 or _was_held:
			reset()
		return

	var target := _find_focus()

	if target != _focus:
		_cancel_hold()
		_focus = target
		focus_changed.emit(target)

	if target == null:
		# Pressing the key with nothing in front of you is not an error and not
		# an event. It is the most common thing a player will do with it.
		_was_held = interact_held
		_hold_elapsed = 0.0
		_publish("")
		return

	var hold_time: float = maxf(0.0, target.interaction_hold_time(_player))

	if not interact_held:
		if _was_held and _hold_elapsed > 0.0:
			interaction_cancelled.emit(target)
		# Releasing early forfeits the progress outright. Resuming from where
		# you let go would let a hold be paid in instalments, and the whole
		# point of it is that it must be paid in one uninterrupted stretch.
		_hold_elapsed = 0.0
		_was_held = false
		_publish(_prompt_for(target, hold_time, 0.0))
		return

	if hold_time <= 0.0:
		# Instant: fires on the press edge only, so holding the key down does
		# not machine-gun a door open and shut.
		if not _was_held:
			_complete(target)
		_was_held = true
		_publish(_prompt_for(target, hold_time, 0.0))
		return

	_hold_elapsed += delta
	_was_held = true

	if _hold_elapsed >= hold_time:
		_hold_elapsed = 0.0
		_complete(target)
		return

	_publish(_prompt_for(target, hold_time, _hold_elapsed / hold_time))


## What is currently focused, or null.
func focus() -> Node:
	return _focus


## Fraction of the current hold completed, 0..1.
func hold_progress() -> float:
	if _focus == null or not is_instance_valid(_focus):
		return 0.0
	var hold_time: float = _focus.interaction_hold_time(_player)
	if hold_time <= 0.0:
		return 0.0
	return clampf(_hold_elapsed / hold_time, 0.0, 1.0)


## Whether the interact key is listened to at all. Game turns this off
## alongside the weapon whenever it takes control: round over, pause, level-up.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


## Drop any focus and any progress. Used on round restart and when a menu
## opens, so a hold cannot survive across a pause.
func reset() -> void:
	_cancel_hold()
	_focus = null
	_was_held = false
	_publish("")


func _complete(target: Node) -> void:
	if target.interact(_player):
		interaction_completed.emit(target)
	_hold_elapsed = 0.0


func _cancel_hold() -> void:
	if _focus != null and is_instance_valid(_focus) and _hold_elapsed > 0.0:
		interaction_cancelled.emit(_focus)
	_hold_elapsed = 0.0


func _prompt_for(target: Node, hold_time: float, progress: float) -> String:
	var label: String = target.interaction_prompt(_player)

	if hold_time <= 0.0:
		return press_format % label
	if progress > 0.0:
		return progress_format % [label, int(progress * 100.0)]
	return hold_format % label


func _publish(text: String) -> void:
	if text == _last_prompt:
		return
	_last_prompt = text
	prompt_changed.emit(text)


## Nearest usable object that is both within its own reach and inside the view
## cone. Nearest rather than most-centred: two objects close enough to compete
## are close enough that the player means the one they are standing on.
func _find_focus() -> Node:
	if _player == null or not is_instance_valid(_player):
		return null

	var best: Node = null
	var best_distance := INF
	var eye := _eye_position()
	var facing := _facing()
	var cos_limit := cos(deg_to_rad(view_angle_degrees * 0.5))

	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		if not _is_interactable(node):
			continue
		if not node.can_interact(_player):
			continue

		var point: Vector3 = (
			node.interaction_point() if node.has_method("interaction_point")
			else (node as Node3D).global_position
		)
		var reach: float = (
			node.interaction_reach() if node.has_method("interaction_reach")
			else default_reach_metres
		)

		var distance := (point - _player.global_position).length()
		if distance > reach or distance >= best_distance:
			continue

		var to_point := point - eye
		var length := to_point.length()
		if length > 0.01 and facing.dot(to_point / length) < cos_limit:
			continue

		if not _has_line_of_sight(eye, point):
			continue

		best = node
		best_distance = distance

	return best


## Duck-typed check. Anything answering the four contract methods is usable,
## whether or not it extends Interactable — see interactable.gd for why the
## contract is shaped this way.
func _is_interactable(node: Node) -> bool:
	return (
		node is Node3D
		and is_instance_valid(node)
		and node.has_method("can_interact")
		and node.has_method("interaction_prompt")
		and node.has_method("interaction_hold_time")
		and node.has_method("interact")
	)


## Rock between you and a crate should hide the prompt, or players learn to
## read prompts through walls to find the supplies.
##
## Skipped outside a physics frame rather than run there: querying the space
## state while the engine is not stepping physics is an error in Godot 4, and
## the only callers outside a physics frame are the headless tests, where every
## object is placed in open space anyway.
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if not require_line_of_sight or not Engine.is_in_physics_frame():
		return true

	var world := _player.get_world_3d()
	if world == null:
		return true

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = sight_mask
	return world.direct_space_state.intersect_ray(query).is_empty()


func _eye_position() -> Vector3:
	if _camera != null and is_instance_valid(_camera):
		return _camera.global_position
	return _player.global_position + Vector3.UP * 1.6


func _facing() -> Vector3:
	if _camera != null and is_instance_valid(_camera):
		return -_camera.global_transform.basis.z
	return -_player.global_transform.basis.z
