class_name MeshCollision
extends RefCounted

## Gives a placed object collision that matches what it draws.
##
## Implements Phase 3's rule that "collision should approximately match visible
## geometry" without solving anything with a giant invisible box.
##
## Two decisions are worth stating, because both look arbitrary and neither is.
##
## Boxes rather than the meshes themselves, for the same reason the cave's walls
## are boxes: a shape only has to stop a capsule, and a concave trimesh built
## from sculpted art is the most expensive thing a capsule can sweep against —
## measured here at roughly 0.6ms of physics per zombie, which put thirty
## zombies over the entire frame budget.
##
## One box per mesh rather than one box around the whole object. For a crate the
## two are all but identical, but the difference is the whole point for anything
## with a hole in it: a door frame boxed as a single object is a wall across the
## doorway, which is the giant invisible box the rule exists to prevent.
##
## Objects that are drawn but out of reach — an overhead lintel, a stalactite —
## are better left alone than given collision nobody can touch.


## Fit collision to an object's meshes and return the body carrying it, or null
## if the object draws nothing.
##
## The object must already be inside the tree: the fit is computed from each
## mesh's transform relative to the object, which is only knowable once both
## have a place in it.
static func fit(instance: Node3D) -> StaticBody3D:
	var meshes := _meshes_of(instance)
	if meshes.is_empty():
		return null

	var body := StaticBody3D.new()
	body.name = "Collision"
	var to_local := instance.global_transform.affine_inverse()

	for mesh_instance in meshes:
		var bounds: AABB = (
			(to_local * mesh_instance.global_transform) * mesh_instance.get_aabb()
		)
		if bounds.get_longest_axis_size() <= 0.0:
			continue

		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = bounds.size
		collider.shape = box
		collider.position = bounds.get_center()
		body.add_child(collider)

	if body.get_child_count() == 0:
		body.free()
		return null

	instance.add_child(body)
	return body


static func _meshes_of(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []

	if node is MeshInstance3D and node.mesh != null:
		found.append(node)

	for child in node.get_children():
		found.append_array(_meshes_of(child))

	return found
