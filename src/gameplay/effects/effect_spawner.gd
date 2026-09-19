class_name EffectSpawner
extends Node3D

## One-shot visual effects: bullet impacts, blood, and death bursts.
##
## Gameplay never builds particles. It reports what happened and Game routes it
## here, the same way it routes sound — so the weapon does not know what a hit
## looks like, only that it hit.
##
## Particle materials are built once and shared. Each burst allocates a node,
## which is fine at the rate a semi-automatic weapon can fire, but the process
## materials would be wasteful to rebuild per shot.

## Bursts free themselves after this multiple of their lifetime.
const CLEANUP_MARGIN := 1.4

@export_group("Impact")
@export var rock_colour := Color(0.85, 0.66, 0.5)
@export var blood_colour := Color(0.62, 0.08, 0.09)
@export var impact_particles := 14
@export var impact_lifetime := 0.45

@export_group("Death")
@export var death_particles := 36
@export var death_lifetime := 0.8

var _rock_material: ParticleProcessMaterial
var _blood_material: ParticleProcessMaterial
var _death_material: ParticleProcessMaterial
var _rock_mesh: Mesh
var _blood_mesh: Mesh


func _ready() -> void:
	_rock_material = _make_process_material(3.2, 0.06)
	_blood_material = _make_process_material(2.4, 0.05)
	_death_material = _make_process_material(4.0, 0.09)

	_rock_mesh = _make_mesh(0.045, rock_colour, 1.0)
	_blood_mesh = _make_mesh(0.055, blood_colour, 2.2)


## A bullet struck something. `is_flesh` picks blood over rock chips.
func spawn_impact(position: Vector3, normal: Vector3, is_flesh: bool) -> void:
	var burst := GPUParticles3D.new()
	burst.amount = impact_particles
	burst.lifetime = impact_lifetime
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.process_material = _blood_material if is_flesh else _rock_material
	burst.draw_pass_1 = _blood_mesh if is_flesh else _rock_mesh

	add_child(burst)
	burst.global_position = position

	# Spray back along the surface normal rather than in a ball, so a hit reads
	# as coming off the surface it landed on.
	if not normal.is_zero_approx():
		burst.look_at(position + normal, Vector3.UP)

	burst.emitting = true
	_free_after(burst, impact_lifetime)


## A zombie died. Bigger, slower, and always blood.
func spawn_death(position: Vector3) -> void:
	var burst := GPUParticles3D.new()
	burst.amount = death_particles
	burst.lifetime = death_lifetime
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.process_material = _death_material
	burst.draw_pass_1 = _blood_mesh

	add_child(burst)
	burst.global_position = position + Vector3.UP * 0.9
	burst.emitting = true
	_free_after(burst, death_lifetime)


func _make_process_material(speed: float, gravity_scale: float) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0.0, 0.0, 1.0)
	material.spread = 55.0
	material.initial_velocity_min = speed * 0.4
	material.initial_velocity_max = speed
	material.gravity = Vector3(0.0, -9.8 * gravity_scale * 10.0, 0.0)
	material.scale_min = 0.5
	material.scale_max = 1.3
	material.damping_min = 1.0
	material.damping_max = 3.0
	return material


func _make_mesh(size: float, colour: Color, emission_energy: float) -> Mesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = emission_energy
	# Face the camera so flat quads never present edge-on and vanish.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = false
	mesh.material = material

	return mesh


func _free_after(node: Node, lifetime: float) -> void:
	get_tree().create_timer(lifetime * CLEANUP_MARGIN).timeout.connect(
		func() -> void:
			if is_instance_valid(node):
				node.queue_free()
	)
