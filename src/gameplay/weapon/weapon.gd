class_name Weapon
extends Node3D

## FEATURE 2 — Ammunition and Reload.
## Implements design/gdd/game-concept.md "Feature 2 — Ammunition and Reload".
##
##   Trigger:      fire input, reload input, or a kill awarding reserve ammo
##   State change: magazine_ammo and reserve_ammo
##   Result:       ammo_changed drives the HUD counter; an empty magazine
##                 blocks firing and reports dry_fired instead
##
## All tuning values are exported so the ammo economy can be rebalanced from the
## inspector without touching this file — per the concept's "ammo tuning is the
## whole game" risk note.

signal ammo_changed(magazine: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished()
signal fired(from: Vector3, to: Vector3)
signal dry_fired()
signal target_hit(target: Node, damage_dealt: float)

@export_group("Ammunition")
@export var magazine_size := 8
@export var starting_reserve := 24
@export var max_reserve := 60

@export_group("Ballistics")
@export var damage := 25.0
@export var fire_cooldown := 0.18
@export var shot_range := 80.0

@export_group("Reload")
@export var reload_duration := 1.6

@export_group("Feel")
@export var recoil_pitch_degrees := 1.4
@export var recoil_recovery := 9.0
@export var tracer_lifetime := 0.04

var magazine_ammo := 0
var reserve_ammo := 0

var _is_reloading := false
var _cooldown_remaining := 0.0
var _reload_remaining := 0.0
var _recoil_offset := 0.0
var _input_enabled := true

@onready var _camera: Camera3D = _resolve_camera()
@onready var _muzzle: Node3D = $Muzzle
@onready var _muzzle_flash: OmniLight3D = $Muzzle/Flash


func _ready() -> void:
	magazine_ammo = magazine_size
	reserve_ammo = starting_reserve
	_muzzle_flash.visible = false
	ammo_changed.emit(magazine_ammo, reserve_ammo)


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	_tick_reload(delta)
	_tick_recoil(delta)

	if not _input_enabled:
		return

	# Semi-automatic: one bullet per click. The concept's first pillar is
	# "every bullet is a decision", which holding to spray would undermine.
	if Input.is_action_just_pressed("fire"):
		try_fire()
	elif Input.is_action_just_pressed("reload"):
		try_reload()


## Fire one round. Returns true only when a bullet actually left the weapon.
func try_fire() -> bool:
	if _is_reloading or _cooldown_remaining > 0.0:
		return false

	if magazine_ammo <= 0:
		# Boundary case: empty magazine blocks the shot entirely.
		dry_fired.emit()
		return false

	magazine_ammo -= 1
	_cooldown_remaining = fire_cooldown
	ammo_changed.emit(magazine_ammo, reserve_ammo)

	_apply_recoil()
	_show_muzzle_flash()
	_trace_shot()
	return true


## Begin a reload. Returns true only when a reload actually started.
func try_reload() -> bool:
	if _is_reloading:
		return false
	if magazine_ammo >= magazine_size:
		return false
	if reserve_ammo <= 0:
		return false

	_is_reloading = true
	_reload_remaining = reload_duration
	reload_started.emit(reload_duration)
	return true


## Award ammunition, clamped to the reserve ceiling. Returns the amount actually
## added, which is less than requested when the reserve is already full.
func add_reserve_ammo(amount: int) -> int:
	var before := reserve_ammo
	reserve_ammo = clampi(reserve_ammo + amount, 0, max_reserve)
	var added := reserve_ammo - before

	if added != 0:
		ammo_changed.emit(magazine_ammo, reserve_ammo)
	return added


func is_reloading() -> bool:
	return _is_reloading


## True when the weapon cannot fire and cannot be reloaded back into use.
func is_fully_dry() -> bool:
	return magazine_ammo <= 0 and reserve_ammo <= 0


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


## Restore the weapon to its opening state for a fresh round.
func reset_state() -> void:
	_is_reloading = false
	_reload_remaining = 0.0
	_cooldown_remaining = 0.0
	_recoil_offset = 0.0
	magazine_ammo = magazine_size
	reserve_ammo = starting_reserve
	ammo_changed.emit(magazine_ammo, reserve_ammo)


func _tick_reload(delta: float) -> void:
	if not _is_reloading:
		return

	_reload_remaining -= delta
	if _reload_remaining > 0.0:
		return

	var needed := magazine_size - magazine_ammo
	var transferred := mini(needed, reserve_ammo)

	magazine_ammo += transferred
	reserve_ammo -= transferred
	_is_reloading = false

	ammo_changed.emit(magazine_ammo, reserve_ammo)
	reload_finished.emit()


func _tick_recoil(delta: float) -> void:
	if is_zero_approx(_recoil_offset):
		return

	var previous := _recoil_offset
	_recoil_offset = move_toward(_recoil_offset, 0.0, recoil_recovery * delta)

	if _camera != null:
		_camera.rotation.x -= deg_to_rad(previous - _recoil_offset)


func _apply_recoil() -> void:
	_recoil_offset += recoil_pitch_degrees
	if _camera != null:
		_camera.rotation.x += deg_to_rad(recoil_pitch_degrees)


func _show_muzzle_flash() -> void:
	_muzzle_flash.visible = true
	var timer := get_tree().create_timer(0.05)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(_muzzle_flash):
			_muzzle_flash.visible = false
	)


func _trace_shot() -> void:
	if _camera == null:
		return

	var origin := _camera.global_position
	var direction := -_camera.global_basis.z
	var destination := origin + direction * shot_range

	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	# World geometry and zombies, never the player's own body.
	query.collision_mask = 1 | 4
	query.exclude = [_get_owner_rid()]

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if not result.is_empty():
		destination = result.position
		var collider: Node = result.get("collider")

		if collider != null and collider.has_method("take_damage"):
			collider.take_damage(damage, result.position, direction)
			target_hit.emit(collider, damage)

	fired.emit(_muzzle.global_position, destination)
	_spawn_tracer(_muzzle.global_position, destination)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var distance := from.distance_to(to)
	if distance < 0.1:
		return

	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.012
	cylinder.bottom_radius = 0.012
	cylinder.height = distance
	cylinder.radial_segments = 4
	mesh_instance.mesh = cylinder

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.45)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.78, 0.35)
	material.emission_energy_multiplier = 4.0
	mesh_instance.material_override = material

	get_tree().current_scene.add_child(mesh_instance)
	mesh_instance.global_position = from.lerp(to, 0.5)
	# CylinderMesh runs along local Y, so aim that axis down the shot.
	mesh_instance.look_at_from_position(
		mesh_instance.global_position, to, Vector3.UP
	)
	mesh_instance.rotate_object_local(Vector3.RIGHT, PI * 0.5)

	get_tree().create_timer(tracer_lifetime).timeout.connect(
		func() -> void:
			if is_instance_valid(mesh_instance):
				mesh_instance.queue_free()
	)


func _resolve_camera() -> Camera3D:
	var parent := get_parent()
	if parent is Camera3D:
		return parent
	return get_viewport().get_camera_3d()


func _get_owner_rid() -> RID:
	var body := get_parent()
	while body != null:
		if body is CollisionObject3D:
			return body.get_rid()
		body = body.get_parent()
	return RID()
