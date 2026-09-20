extends SceneTree

## Verifies that a zombie's collision capsule matches the body you can see.
##
## Regression test. The model was scaled by one number and the capsule by a
## different one, and they drifted a factor of two apart: zombies rendered
## about 3.5m tall with a 1.7m capsule, so the hitbox covered the legs while
## the player was aiming at the chest. Most shots that looked like clean hits
## passed straight through, which read as "shooting is broken".
##
## The measurement comes from the rig's bones. A skinned mesh reports its
## bind-pose bounds, which for this pack are a few centimetres across and would
## make this test pass no matter what.
##
##   Godot --headless --script tests/manual/verify_zombie_scale.gd

const ZOMBIE_SCENE := "res://src/gameplay/zombie/zombie.tscn"

## The topmost bone is the head joint, which sits a little below the crown of
## the mesh. A tenth is enough to catch a scale mistake without failing on the
## gap between a skull's top bone and the top of its head.
const TOLERANCE := 0.1

## Every kind, taken from the enum rather than listed by hand. A hand-written
## list silently stops covering the thing it exists to cover the moment someone
## adds a sixth archetype — which is exactly how the Stalker and the Screamer
## would have shipped untested.
var _kinds := ZombieTypes.Kind.values()

var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# @onready vars are not assigned until _ready() runs on the first frame.
	if not _started:
		_started = true
		return false

	for kind in _kinds:
		test_zombie_capsule_matches_its_declared_height(kind)
		test_zombie_rendered_body_matches_its_capsule(kind)

	_report()
	return true


func test_zombie_capsule_matches_its_declared_height(kind: ZombieTypes.Kind) -> void:
	# Arrange
	var definition := ZombieTypes.definition(kind)
	var zombie := _build(kind)

	# Act
	var capsule: float = zombie.get_node("CollisionShape3D").shape.height

	# Assert
	if not is_equal_approx(capsule, definition.height):
		_failures.append("%s capsule is %.2fm but its declared height is %.2fm" % [
			definition.name, capsule, definition.height
		])
	else:
		print("PASS: %s capsule matches its declared %.2fm" % [
			definition.name, definition.height
		])

	zombie.free()


func test_zombie_rendered_body_matches_its_capsule(kind: ZombieTypes.Kind) -> void:
	# Arrange
	var definition := ZombieTypes.definition(kind)
	var zombie := _build(kind)
	var capsule: float = zombie.get_node("CollisionShape3D").shape.height

	# Act
	var drawn := _rendered_height(zombie)

	# Assert
	if drawn <= 0.0:
		_failures.append("%s has no skeleton to measure" % definition.name)
	elif absf(drawn - capsule) > capsule * TOLERANCE:
		_failures.append(
			"%s is drawn %.2fm tall but its hitbox is %.2fm — you cannot shoot what you see"
			% [definition.name, drawn, capsule]
		)
	else:
		print("PASS: %s is drawn %.2fm against a %.2fm hitbox" % [
			definition.name, drawn, capsule
		])

	zombie.free()


func _build(kind: ZombieTypes.Kind) -> Node3D:
	var zombie: Node3D = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	root.add_child(zombie)
	zombie.configure(kind)
	zombie.global_position = Vector3.ZERO
	return zombie


## Height of the posed rig above the zombie's feet, in metres.
func _rendered_height(zombie: Node3D) -> float:
	var skeleton := _find_skeleton(zombie)
	if skeleton == null:
		return 0.0

	var top := 0.0
	for index in skeleton.get_bone_count():
		var bone := skeleton.global_transform * skeleton.get_bone_global_pose(index)
		top = maxf(top, bone.origin.y - zombie.global_position.y)

	return top


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node

	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found

	return null


func _report() -> void:
	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
