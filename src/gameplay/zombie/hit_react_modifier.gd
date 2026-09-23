class_name HitReactModifier
extends SkeletonModifier3D

## A physical flinch layered on top of whatever clip is playing.
##
## The pack's Hit clip is one authored reaction, always to the front, and it
## takes the body over. A shot from the side or from behind, or one landing on
## a zombie mid-run, needs to read as the torso being knocked the way the round
## was travelling, without the legs stopping. This bends the spine and head
## along the shot on a damped spring, after the animation has posed the
## skeleton, so it composes with walk, run, attack and the Hit clip alike.
##
## Runs as a SkeletonModifier3D so the engine applies it after the
## AnimationPlayer every frame; writing bone poses from _process would be
## overwritten by the next animation update.

## Bones bent, and how much of the lean each takes. The spine carries the
## body, the neck adds the whip that sells an impact.
const BONE_NAMES := ["spine02", "neck01"]
const BONE_SHARES := [0.55, 0.45]

## Stiffness and damping of the spring, per second. Tuned for a snap that
## settles in about a third of a second with one small overshoot.
@export var stiffness := 160.0
@export var damping := 14.0
## Largest lean the spring may reach, in radians.
@export var max_angle := 0.6
## Angular speed an impulse of strength 1 adds, radians per second.
@export var impulse_speed := 12.0

var _offset := Vector3.ZERO
var _velocity := Vector3.ZERO
var _bone_ids := PackedInt32Array()
var _last_ticks := 0


## Knock the torso along `direction` (world space, the way the round was
## travelling). `strength` 0..1 scales the kick; a Brute passes less.
func react(direction: Vector3, strength: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or direction.length_squared() < 0.0001:
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return
	# Rotating about up x travel tips the top of the body along the travel.
	# Worked out in world space and then taken into the skeleton's own frame:
	# imported rigs are not necessarily Y-up inside the skeleton.
	var world_axis := Vector3.UP.cross(flat.normalized())
	var axis := (skeleton.global_basis.inverse() * world_axis).normalized()
	_velocity += axis * impulse_speed * clampf(strength, 0.0, 1.0)


## Current lean, radians. Exposed for tests.
func lean() -> float:
	return _offset.length()


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	var now := Time.get_ticks_usec()
	var delta := clampf((now - _last_ticks) / 1_000_000.0, 0.0, 0.05) if _last_ticks > 0 else 0.0
	_last_ticks = now
	_step(delta)

	if _offset.length_squared() < 0.000001:
		return

	if _bone_ids.is_empty():
		for bone in BONE_NAMES:
			_bone_ids.append(skeleton.find_bone(bone))

	for i in _bone_ids.size():
		var id := _bone_ids[i]
		if id < 0:
			continue
		var angle: float = _offset.length() * BONE_SHARES[i]
		# The lean is expressed in skeleton space; a bone's local rotation is
		# relative to its parent, so the axis is carried into the parent's frame.
		var parent := skeleton.get_bone_parent(id)
		var axis := _offset.normalized()
		if parent >= 0:
			axis = (skeleton.get_bone_global_pose(parent).basis.inverse() * axis).normalized()
		var local := skeleton.get_bone_pose_rotation(id)
		skeleton.set_bone_pose_rotation(id, Quaternion(axis, angle) * local)


## Advance the spring. Separate from the pose write so tests can drive it
## without a rendering frame.
func _step(delta: float) -> void:
	if delta <= 0.0:
		return
	var accel := -_offset * stiffness - _velocity * damping
	_velocity += accel * delta
	_offset += _velocity * delta
	if _offset.length() > max_angle:
		_offset = _offset.normalized() * max_angle
		_velocity *= 0.5
	if _offset.length() < 0.0005 and _velocity.length() < 0.005:
		_offset = Vector3.ZERO
		_velocity = Vector3.ZERO
