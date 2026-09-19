class_name Decoy
extends Node3D

## A round thrown to be heard rather than fired.
##
## The awareness system gave zombies beliefs about where the player is. This is
## the only verb that lets the player *write* one. Without it information only
## ever leaks outward — you can be quiet or loud, but you cannot aim it — which
## makes the whole system a penalty rather than something to play with.
##
## It costs a round of reserve ammunition, which is the point. The game has two
## scarce resources, bullets and the horde's attention, and this is the trade
## between them: spend the thing you cannot spare to buy position. A round can
## leave through the barrel or through your hand, and those do completely
## different jobs.
##
## The throw itself is silent. Only the landing is loud, so a decoy can be
## thrown from cover without giving the cover away — which is the entire
## reason to have one.

signal landed(at: Vector3, loudness: float)

## Simulated by hand rather than with a RigidBody3D. A rigid body would need a
## collision layer that interacts with the world but not the player or the
## zombies, a physics material tuned so it neither skids nor sticks, and a
## sleep threshold — all to model something that is in the air for under a
## second. A parabola plus one ray is exact, cheap, and lands precisely where
## the trajectory preview said it would, which matters more than realism: the
## player aimed at that spot.
@export var gravity := 18.0
## How loud the landing is, relative to a gunshot. Deliberately just under —
## firing remains the loudest thing you can do.
@export var loudness := 0.85
## How long the round stays visible on the ground afterwards.
@export var linger := 2.5

var _velocity := Vector3.ZERO
var _flying := true
var _mesh: MeshInstance3D


func _ready() -> void:
	_build()


func _physics_process(delta: float) -> void:
	if not _flying:
		return

	_velocity.y -= gravity * delta
	var step := _velocity * delta

	# One ray per frame along the step just taken, so a fast throw cannot pass
	# through a wall between frames.
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + step
	)
	# World geometry only. A decoy that bounced off a zombie would be a way to
	# hit them with ammunition, which is what the gun is for.
	query.collision_mask = 1

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		global_position += step
		rotate_x(delta * 9.0)
		return

	global_position = hit.position
	_land()


## Begin a throw from a position with an initial velocity.
func launch(from: Vector3, velocity: Vector3) -> void:
	global_position = from
	_velocity = velocity
	_flying = true


func _land() -> void:
	_flying = false
	landed.emit(global_position, loudness)

	var tween := create_tween()
	tween.tween_interval(linger)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(queue_free)


func _build() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.035
	cylinder.bottom_radius = 0.045
	cylinder.height = 0.13
	cylinder.radial_segments = 6

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.82, 0.62, 0.25)
	material.metallic = 0.9
	material.roughness = 0.35

	_mesh = MeshInstance3D.new()
	_mesh.mesh = cylinder
	_mesh.material_override = material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
