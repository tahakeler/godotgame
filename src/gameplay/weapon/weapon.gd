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
##
## Since the arsenal landed, this node is the *holder* rather than the gun. The
## exported ballistics below describe whichever weapon is currently in hand;
## the numbers themselves come from `WeaponTypes.DEFINITIONS`, and each kind's
## magazine, reserve and (upgraded) stats live in its own slot so that putting
## the shotgun away does not quietly pour its shells into the rifle.

signal ammo_changed(magazine: int, reserve: int)
## A different weapon has finished coming up. Carries the kind and its name so
## the HUD never has to reach into WeaponTypes itself.
signal weapon_switched(kind: WeaponTypes.Kind, display_name: String)
## A swap has begun. The weapon cannot fire for `duration` seconds.
signal switch_started(duration: float)
signal reload_started(duration: float)
signal reload_finished()
signal fired(from: Vector3, to: Vector3)
signal dry_fired()
signal target_hit(target: Node, damage_dealt: float)
## Rounds scraped together after running completely dry.
signal scrounged(amount: int)
## A decoy has left the hand. Game wires its landing to the noise system.
signal decoy_thrown(decoy: Decoy)
## Where a bullet landed, the surface normal, and whether it was a zombie.
signal impacted(position: Vector3, normal: Vector3, is_flesh: bool)

@export_group("Arsenal")
## What the player starts a round holding.
@export var starting_kind: WeaponTypes.Kind = WeaponTypes.Kind.PISTOL
## Seconds to bring the current weapon up. Set from the equipped definition.
##
## A swap has to cost real time. An instant one makes running a weapon dry a
## non-event — you would simply be holding a different gun a frame later — and
## the whole point of separate reserves is that emptying one is a mistake you
## have to live through.
@export var swap_duration := 0.55
## The equipped weapon's name, for the HUD.
@export var display_name := "PISTOL"

@export_group("Ammunition")
@export var magazine_size := 8
## The *pistol's* reserve at this difficulty. Every weapon's starting reserve is
## scaled against WeaponTypes.BASELINE_RESERVE by this figure, so a difficulty
## change thins the whole arsenal rather than only whatever is in hand.
@export var starting_reserve := 36
@export var max_reserve := 72

@export_group("Ballistics")
@export var damage := 25.0
## Projectiles per trigger pull. Above one makes the weapon a shotgun: each
## pellet traces and damages separately, so a spread that only half-connects
## deals half the damage.
@export var pellets := 1
## Cone half-angle in degrees that each pellet is jittered within.
@export var spread_degrees := 0.6
@export var fire_cooldown := 0.18
@export var shot_range := 80.0
## How loud a shot is, as a multiplier on each zombie's hearing range. Lower
## values are quieter; an upgrade can buy the player some of it back.
@export var noise_loudness := 1.0

@export_group("Reload")
@export var reload_duration := 1.6
## Reload on its own the moment the magazine runs dry.
##
## The manual reload key still exists and is still the right habit — topping up
## a half-empty magazine between fights is a decision worth making. This only
## covers the case where there is no decision left to make: an empty magazine
## with rounds in reserve has exactly one sensible next action, and making the
## player press a key to confirm it is friction, not tension.
@export var auto_reload := true

@export_group("Last resort")
## Seconds between scrounged rounds once the player is completely out.
##
## Without this the ammo economy has a dead end: reserve ammo comes from kills,
## kills need ammo, and a player who spends their last round has no way back
## into the game and has to watch a round they cannot influence. A slow trickle
## keeps the scarcity — it is far too slow to fight from — while making sure
## there is always a way out.
@export var dry_resupply_interval := 7.0
@export var dry_resupply_amount := 2

@export_group("Decoy")
@export var throw_speed := 14.0
@export var throw_gravity := 18.0
## How much the throw is lobbed above the crosshair.
@export var throw_lift := 0.25
@export var throw_cooldown := 0.45
## Landing volume relative to a gunshot. Just under, so firing stays the
## loudest thing the player can do.
@export var decoy_loudness := 0.7

@export_group("Feel")
@export var recoil_pitch_degrees := 1.4
@export var recoil_recovery := 9.0
## Extra kick and spread added per consecutive shot, as a fraction of the base.
##
## This is what separates a rifle from a fast pistol. Without it, a high rate of
## fire is strictly better than a low one and there is no reason to ever tap.
@export var recoil_climb := 0.0
## Ceiling on the accumulated climb, so sustained fire gets worse and then stops
## getting worse — an unbounded climb reads as a bug rather than a cost.
@export var recoil_climb_max := 0.0
## Seconds of not firing after which the climb has fully bled off.
@export var recoil_climb_recovery := 1.6
## Camera shake per shot, handed to Player.add_trauma by Game. 0.2 is a
## gunshot, 0.6 is being hit.
@export var fire_trauma := 0.2
@export var tracer_lifetime := 0.04

@export_group("Viewmodel")
@export var sway_amount := 0.0011
@export var sway_limit := 0.05
@export var sway_smoothing := 9.0
@export var sway_recentre := 12.0
@export var bob_frequency := 9.0
@export var bob_amount := 0.012

var magazine_ammo := 0
var reserve_ammo := 0
## Which of the three is in hand.
var kind: WeaponTypes.Kind = WeaponTypes.Kind.PISTOL

## kind -> { "magazine": int, "reserve": int, "stats": Dictionary }.
##
## The stats block is a *copy* of the definition rather than the definition
## itself, because upgrades mutate the weapon in hand and those changes have to
## follow that weapon rather than leaking onto whatever is picked up next.
var _slots := {}
## Counts down while a weapon is being raised. Firing is blocked throughout.
var _swap_remaining := 0.0
## What we are swapping *to*; the stats only change when the swap completes.
var _swap_target: WeaponTypes.Kind = WeaponTypes.Kind.PISTOL
var _recoil_climb_amount := 0.0
## Holds the climb at its current value for a beat after each shot, so a burst
## accumulates instead of decaying between rounds.
var _climb_hold_remaining := 0.0

var _is_reloading := false
var _cooldown_remaining := 0.0
var _reload_remaining := 0.0
var _recoil_offset := 0.0
var _input_enabled := true
var _was_mouse_captured := false
## Briefly blocks firing after the cursor is re-captured, so the click that
## brings the window back into focus does not also spend a round.
var _focus_lock_remaining := 0.0
var _look_delta := Vector2.ZERO
var _sway_offset := Vector3.ZERO
var _bob_time := 0.0
var _rest_position := Vector3.ZERO
## Counts down only while the weapon is completely dry.
var _dry_remaining := 0.0
var _throw_cooldown_remaining := 0.0

@onready var _camera: Camera3D = _resolve_camera()
@onready var _muzzle: Node3D = $Muzzle
@onready var _muzzle_flash: OmniLight3D = $Muzzle/Flash


func _ready() -> void:
	_rest_position = position
	_build_slots()
	_equip_now(starting_kind)
	_muzzle_flash.visible = false
	ammo_changed.emit(magazine_ammo, reserve_ammo)


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	_tick_swap(delta)
	_tick_reload(delta)
	_tick_recoil(delta)
	_tick_recoil_climb(delta)
	_tick_viewmodel(delta)

	if not _input_enabled:
		return

	_read_switch_input()
	_tick_focus_lock(delta)
	_tick_throw_cooldown(delta)
	_tick_dry_resupply(delta)

	if auto_reload and magazine_ammo <= 0 and not _is_reloading:
		try_reload()

	# Semi-automatic: one bullet per click. The concept's first pillar is
	# "every bullet is a decision", which holding to spray would undermine.
	# Hold to aim, release to throw. A preview the player cannot study before
	# committing is not a decision, and the whole value of a decoy is choosing
	# where it goes.
	if Input.is_action_just_released("throw_decoy"):
		try_throw_decoy()
	elif Input.is_action_just_pressed("fire") and _focus_lock_remaining <= 0.0:
		try_fire()
	elif Input.is_action_just_pressed("reload"):
		try_reload()


## Give every kind its own magazine, reserve and mutable stat block.
##
## Reserves are scaled against the difficulty's ammo budget rather than taken
## flat from the definitions, so Hard thins all three weapons instead of only
## the one the difficulty setting happens to name.
func _build_slots() -> void:
	var scale := float(starting_reserve) / float(WeaponTypes.BASELINE_RESERVE)
	_slots.clear()

	for slot_kind in WeaponTypes.order():
		var definition: Dictionary = WeaponTypes.definition(slot_kind).duplicate(true)
		_slots[slot_kind] = {
			"magazine": int(definition.magazine_size),
			"reserve": maxi(1, roundi(float(definition.reserve) * scale)),
			"stats": definition,
		}


## Copy the equipped weapon's live stats back into its slot.
##
## Upgrades mutate this node's exported fields directly (Game owns that logic),
## so the only way an upgraded magazine or a subsonic barrel survives a swap is
## to read the fields back out before they are overwritten.
func _store_current_slot() -> void:
	var slot: Dictionary = _slots.get(kind, {})
	if slot.is_empty():
		return

	slot.magazine = magazine_ammo
	slot.reserve = reserve_ammo
	var stats: Dictionary = slot.stats
	stats.damage = damage
	stats.pellets = pellets
	stats.spread_degrees = spread_degrees
	stats.fire_cooldown = fire_cooldown
	stats.magazine_size = magazine_size
	stats.max_reserve = max_reserve
	stats.reload_duration = reload_duration
	stats.shot_range = shot_range
	stats.noise_loudness = noise_loudness
	stats.recoil_pitch_degrees = recoil_pitch_degrees
	stats.recoil_climb = recoil_climb
	stats.recoil_climb_max = recoil_climb_max
	stats.fire_trauma = fire_trauma
	stats.swap_duration = swap_duration


## Put a weapon in hand immediately, with no raise time.
##
## Only used where there is no swap to animate: the first frame of a round, and
## a reset. Player-driven switching always goes through `equip`.
func _equip_now(target: WeaponTypes.Kind) -> void:
	if not _slots.has(target):
		return

	kind = target
	_swap_target = target
	_swap_remaining = 0.0
	_recoil_climb_amount = 0.0

	var slot: Dictionary = _slots[target]
	var stats: Dictionary = slot.stats

	display_name = stats.name
	damage = stats.damage
	pellets = stats.pellets
	spread_degrees = stats.spread_degrees
	fire_cooldown = stats.fire_cooldown
	magazine_size = stats.magazine_size
	max_reserve = stats.max_reserve
	reload_duration = stats.reload_duration
	shot_range = stats.shot_range
	noise_loudness = stats.noise_loudness
	recoil_pitch_degrees = stats.recoil_pitch_degrees
	recoil_climb = stats.recoil_climb
	recoil_climb_max = stats.recoil_climb_max
	fire_trauma = stats.fire_trauma
	swap_duration = stats.swap_duration

	magazine_ammo = slot.magazine
	reserve_ammo = slot.reserve

	_show_model(stats.get("model", ""), stats.get("tint", Color.WHITE) as Color)
	ammo_changed.emit(magazine_ammo, reserve_ammo)
	weapon_switched.emit(kind, display_name)


## Begin switching to another weapon. Returns true only when a swap started.
##
## Deliberately refuses a swap that is already under way rather than queueing
## it: letting the player re-trigger the raise would let them spam the number
## keys to stay permanently un-fireable, and more importantly it would let a
## panicked double-press cancel the swap they actually wanted.
func equip(target: WeaponTypes.Kind) -> bool:
	if not _slots.has(target):
		return false
	if _swap_remaining > 0.0:
		return false
	if target == kind:
		return false

	# A reload does not survive a swap. The rounds were never in the magazine,
	# and letting a reload finish on a weapon in the other hand is the kind of
	# free value that makes switching the answer to everything.
	_is_reloading = false
	_reload_remaining = 0.0

	_swap_target = target
	_swap_remaining = maxf(_slots[target].stats.swap_duration, 0.0)
	switch_started.emit(_swap_remaining)

	if is_zero_approx(_swap_remaining):
		_finish_swap()
	return true


## Switch to the next weapon in the arsenal, wrapping around.
func switch_next() -> bool:
	return equip(_neighbour(1))


## Switch to the previous weapon in the arsenal, wrapping around.
func switch_previous() -> bool:
	return equip(_neighbour(-1))


func _neighbour(step: int) -> WeaponTypes.Kind:
	var kinds: Array = WeaponTypes.order()
	var index: int = kinds.find(kind)
	if index < 0:
		return kind
	return kinds[posmod(index + step, kinds.size())]


## True while a weapon is being raised and nothing can be fired.
func is_switching() -> bool:
	return _swap_remaining > 0.0


func _tick_swap(delta: float) -> void:
	if _swap_remaining <= 0.0:
		return

	_swap_remaining = maxf(0.0, _swap_remaining - delta)
	if _swap_remaining <= 0.0:
		_finish_swap()


func _finish_swap() -> void:
	_store_current_slot()
	_swap_remaining = 0.0
	_equip_now(_swap_target)


func _read_switch_input() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		equip(WeaponTypes.Kind.PISTOL)
	elif Input.is_action_just_pressed("weapon_2"):
		equip(WeaponTypes.Kind.SHOTGUN)
	elif Input.is_action_just_pressed("weapon_3"):
		equip(WeaponTypes.Kind.RIFLE)
	elif Input.is_action_just_pressed("weapon_next"):
		switch_next()
	elif Input.is_action_just_pressed("weapon_previous"):
		switch_previous()


## Show the equipped weapon's model and hide the others.
##
## Models are instanced once on first use and then kept, because a swap is a
## thing the player does several times a fight and loading a .glb mid-fight is
## a hitch in exactly the moment they can least afford one.
func _show_model(path: String, tint: Color) -> void:
	var holder := get_node_or_null("Models")
	if holder == null:
		return

	for child in holder.get_children():
		child.visible = child.name == _model_node_name(path)

	if path.is_empty() or holder.has_node(_model_node_name(path)):
		return

	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return

	var instance: Node3D = scene.instantiate()
	instance.name = _model_node_name(path)
	instance.scale = Vector3.ONE * 0.5
	_tint_model(instance, tint)
	holder.add_child(instance)


## Recolour a weapon model into the cave's palette.
##
## The blaster kit ships in bright primaries — the pistol is lilac and white —
## which against brown rock under a neutral grade reads as a prop from a
## different game held up in front of this one. It is the most out-of-place
## thing on screen.
##
## All of that colour lives in the texture, not in albedo_color, which is plain
## white on every surface. Multiplying albedo therefore only darkens the purple
## rather than removing it — the first attempt at this produced a dark purple
## pistol. So the shader desaturates what it samples first and then applies a
## cast, which keeps the texture's light and dark detail while discarding its
## hue.
const VIEWMODEL_SHADER := """
shader_type spatial;
uniform sampler2D source : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 cast_colour : source_color = vec4(1.0);
uniform float desaturation : hint_range(0.0, 1.0) = 0.85;
void fragment() {
	vec3 sampled = texture(source, UV).rgb;
	float luma = dot(sampled, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = mix(sampled, vec3(luma), desaturation) * cast_colour.rgb;
	METALLIC = 0.4;
	ROUGHNESS = 0.45;
	SPECULAR = 0.55;
}
"""


func _tint_model(instance: Node3D, tint: Color) -> void:
	if tint == Color.WHITE:
		return

	var shader := Shader.new()
	shader.code = VIEWMODEL_SHADER

	for mesh_instance in _mesh_instances(instance):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue

		for surface in mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface)

			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("cast_colour", tint)

			# Carry the kit's own texture across. Without it the gun is a
			# single flat colour and loses the shading that separates the
			# barrel, the grip and the magazine at viewmodel scale.
			if source is StandardMaterial3D:
				material.set_shader_parameter(
					"source", (source as StandardMaterial3D).albedo_texture
				)

			mesh_instance.set_surface_override_material(surface, material)


func _mesh_instances
(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		found.append(node)

	for child in node.get_children():
		found.append_array(_mesh_instances(child))

	return found


func _model_node_name(path: String) -> String:
	return path.get_file().get_basename()


## Bleed the accumulated recoil climb back off once the player stops firing.
##
## The hold is what makes tapping a real technique. Without it the climb would
## decay between the rounds of a burst and a held trigger would settle at some
## harmless equilibrium instead of walking the muzzle off the target.
func _tick_recoil_climb(delta: float) -> void:
	_climb_hold_remaining = maxf(0.0, _climb_hold_remaining - delta)

	if _recoil_climb_amount <= 0.0 or recoil_climb_max <= 0.0:
		return
	if _climb_hold_remaining > 0.0:
		return

	var rate := recoil_climb_max / maxf(recoil_climb_recovery, 0.01)
	_recoil_climb_amount = maxf(0.0, _recoil_climb_amount - rate * delta)


## The player re-captures the cursor by clicking, and that same click would
## otherwise reach the weapon and spend a round. In a game built on ammunition
## scarcity, losing a bullet to alt-tabbing back in is a real cost, so firing is
## suppressed briefly after the cursor is captured.
func _tick_focus_lock(delta: float) -> void:
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

	if captured and not _was_mouse_captured:
		_focus_lock_remaining = 0.25

	_was_mouse_captured = captured
	_focus_lock_remaining = maxf(0.0, _focus_lock_remaining - delta)


## Scrape together a couple of rounds when the player has nothing left at all.
##
## The timer only runs while completely dry and resets the moment anything is
## picked up, so it can never top a player up during a fight they are winning.
func _tick_dry_resupply(delta: float) -> void:
	# The floor asks the arsenal, not the hand. is_fully_dry() answers "the
	# thing I am holding is empty", which is the HUD's question. Using it here
	# meant an empty pistol refilled itself for free while a loaded shotgun sat
	# in the other slot: hold the dry gun, wait, and the run never runs out.
	if not is_arsenal_dry():
		_dry_remaining = dry_resupply_interval
		return

	_dry_remaining -= delta
	if _dry_remaining > 0.0:
		return

	_dry_remaining = dry_resupply_interval
	var added := add_reserve_ammo(dry_resupply_amount)
	if added > 0:
		scrounged.emit(added)


## Throw a round to be heard instead of fired.
##
## Costs one from reserve rather than from the magazine: the magazine is what
## stands between you and the thing in front of you, and making a decoy eat it
## would turn every throw into a panic. Reserve is the resource you are
## deciding how to spend, which is where this decision belongs.
##
## Returns the decoy so the caller can wire up its landing, or null when there
## was nothing to throw.
func try_throw_decoy() -> Decoy:
	if reserve_ammo <= 0 or _throw_cooldown_remaining > 0.0:
		return null

	reserve_ammo -= 1
	_throw_cooldown_remaining = throw_cooldown
	ammo_changed.emit(magazine_ammo, reserve_ammo)

	var decoy := Decoy.new()
	decoy.gravity = throw_gravity
	decoy.loudness = decoy_loudness

	_world_parent().add_child(decoy)
	decoy.launch(_throw_origin(), _throw_velocity())

	decoy_thrown.emit(decoy)
	return decoy


## Where a thrown decoy is parented.
##
## Never the weapon itself — a decoy attached to the weapon would fly along
## with the camera instead of being thrown. The running scene is the natural
## home, but it is null when a weapon is built directly rather than as part of
## a round, so fall back to whatever this weapon hangs from.
func _world_parent() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		return scene

	var parent := get_parent()
	return parent if parent != null else self


## Where the arc will land, for the trajectory preview.
##
## Steps the same parabola the decoy flies and stops at the first thing it
## hits, so what the preview draws is what the throw does. A preview computed
## any other way is a promise the throw does not keep, and the player aimed at
## that spot.
func predict_throw(points: int = 24, step := 0.06) -> PackedVector3Array:
	var arc := PackedVector3Array()
	if _camera == null:
		return arc

	var position := _throw_origin()
	var velocity := _throw_velocity()
	arc.append(position)

	var space := get_world_3d().direct_space_state

	for index in points:
		velocity.y -= throw_gravity * step
		var next := position + velocity * step

		var query := PhysicsRayQueryParameters3D.create(position, next)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)

		if not hit.is_empty():
			arc.append(hit.position)
			break

		position = next
		arc.append(position)

	return arc


func _throw_origin() -> Vector3:
	if _camera == null:
		return global_position
	# From slightly below the eye, so the arc is visible rather than starting
	# behind the crosshair.
	return _camera.global_position + _camera.global_basis.y * -0.15


func _throw_velocity() -> Vector3:
	if _camera == null:
		return Vector3.FORWARD * throw_speed
	# Lobbed a little above where you are looking, because a flat throw at a
	# far wall lands short of where the crosshair implies.
	var direction := (-_camera.global_basis.z + _camera.global_basis.y * throw_lift).normalized()
	return direction * throw_speed


## True while the player is holding the throw and has something to throw.
func is_aiming_throw() -> bool:
	return (
		_input_enabled
		and reserve_ammo > 0
		and Input.is_action_pressed("throw_decoy")
	)


func _tick_throw_cooldown(delta: float) -> void:
	_throw_cooldown_remaining = maxf(0.0, _throw_cooldown_remaining - delta)


## Fire one round. Returns true only when a bullet actually left the weapon.
func try_fire() -> bool:
	# A weapon that is still coming up cannot be fired. This is the guarantee
	# that makes swap_duration a real cost rather than a cosmetic animation.
	if _swap_remaining > 0.0:
		return false
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
	if _swap_remaining > 0.0:
		return false
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
## How many more rounds the player could carry, across every weapon.
##
## Asked by an ammo cache before it drains itself, so a crate is never spent on
## a player who cannot carry what is in it.
##
## Across every weapon rather than only the one in hand. Counting just the
## equipped gun meant a crate went silent and prompt-less while the pistol was
## full and the shotgun was empty — visibly stocked, amber light on, and no way
## to interact with it. That reads as broken rather than as a rule.
func reserve_capacity() -> int:
	var room := maxi(0, max_reserve - reserve_ammo)

	for slot_kind in _slots:
		if slot_kind == kind:
			continue

		var slot: Dictionary = _slots[slot_kind]
		room += maxi(0, int(slot.stats.max_reserve) - int(slot.reserve))

	return room


## Take rounds into the equipped weapon first, then spill into the others.
##
## The gun in your hands is the one you are about to need, so it fills first.
## What will not fit goes to the rest, which is a supply crate behaving like a
## supply crate instead of like a magazine for whichever weapon happened to be
## raised at the moment you reached it.
##
## This also settles the swap case: a resupply finished during a raise used to
## land entirely on the gun being holstered. Spilling means the rounds are
## still the player's either way.
func distribute_reserve_ammo(amount: int) -> int:
	var taken := add_reserve_ammo(amount)
	var spare := amount - taken

	for slot_kind in _slots:
		if spare <= 0:
			break
		if slot_kind == kind:
			continue

		var slot: Dictionary = _slots[slot_kind]
		var ceiling := int(slot.stats.max_reserve)
		var before := int(slot.reserve)
		var after: int = clampi(before + spare, 0, ceiling)

		slot.reserve = after
		spare -= after - before
		taken += after - before

	return taken


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


## True when nothing in the whole arsenal can be fired, in hand or holstered.
##
## The slot dictionary is only written back on a swap, so the weapon currently
## equipped is asked through its live fields and the rest through their slots.
## Reading the slot for the equipped kind would answer with whatever it held at
## the last swap, which is the state the player has spent the round changing.
func is_arsenal_dry() -> bool:
	if not is_fully_dry():
		return false

	for slot_kind in _slots:
		if slot_kind == kind:
			continue
		var slot: Dictionary = _slots[slot_kind]
		if int(slot.magazine) > 0 or int(slot.reserve) > 0:
			return false

	return true


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


## Restore the weapon to its opening state for a fresh round.
## Rebuilds every slot from WeaponTypes rather than only refilling the weapon in
## hand. This is also what undoes last round's upgrades: they were written into
## the slots' stat blocks, and the slots are thrown away here.
func reset_state() -> void:
	_is_reloading = false
	_reload_remaining = 0.0
	_cooldown_remaining = 0.0
	_recoil_offset = 0.0
	_recoil_climb_amount = 0.0
	_climb_hold_remaining = 0.0
	_build_slots()
	_equip_now(starting_kind)
	_dry_remaining = dry_resupply_interval


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


## Sway and bob the viewmodel.
##
## A weapon welded rigidly to the camera reads as a decal on the screen. Making
## it lag behind the look and rise with the stride is what sells it as an object
## being carried. Both are applied as an offset from the rest pose, so recoil
## and shake stay independent of it.
func _tick_viewmodel(delta: float) -> void:
	var target_sway := Vector3(
		clampf(-_look_delta.x * sway_amount, -sway_limit, sway_limit),
		clampf(-_look_delta.y * sway_amount, -sway_limit, sway_limit),
		0.0
	)
	_look_delta = _look_delta.lerp(Vector2.ZERO, clampf(sway_recentre * delta, 0.0, 1.0))

	var speed := 0.0
	var body := _owner_body()
	if body != null and body.is_on_floor():
		speed = Vector2(body.velocity.x, body.velocity.z).length()

	if speed > 0.6:
		_bob_time += delta * bob_frequency * clampf(speed / 6.5, 0.4, 1.6)
	else:
		# Settle the bob rather than freezing it mid-stride.
		_bob_time = lerpf(_bob_time, 0.0, clampf(6.0 * delta, 0.0, 1.0))

	var bob_strength: float = clampf(speed / 6.5, 0.0, 1.0) * bob_amount
	var bob := Vector3(
		sin(_bob_time) * bob_strength,
		-absf(cos(_bob_time)) * bob_strength * 0.8,
		0.0
	)

	_sway_offset = _sway_offset.lerp(
		target_sway + bob, clampf(sway_smoothing * delta, 0.0, 1.0)
	)
	position = _rest_position + _sway_offset


## Record look movement so the viewmodel can lag behind it.
func report_look(relative: Vector2) -> void:
	_look_delta += relative


func _owner_body() -> CharacterBody3D:
	var node := get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


func _tick_recoil(delta: float) -> void:
	if is_zero_approx(_recoil_offset):
		return

	var previous := _recoil_offset
	_recoil_offset = move_toward(_recoil_offset, 0.0, recoil_recovery * delta)

	if _camera != null:
		_camera.rotation.x -= deg_to_rad(previous - _recoil_offset)


func _apply_recoil() -> void:
	var kick := recoil_pitch_degrees * (1.0 + _recoil_climb_amount)
	_recoil_offset += kick
	if _camera != null:
		_camera.rotation.x += deg_to_rad(kick)

	# Hold long enough to cover the gap to the next round of a held burst, with
	# margin. Derived from the weapon's own fire rate so the rifle and the
	# pistol do not need separate hold figures.
	_climb_hold_remaining = fire_cooldown * 1.8 + 0.05
	_recoil_climb_amount = minf(
		recoil_climb_max, _recoil_climb_amount + recoil_climb
	)


## The cone every pellet is jittered inside, widened by accumulated climb.
##
## Tying spread to the same climb as the kick is what makes sustained rifle
## fire actually punishing: the muzzle walking up is something the player can
## fight, the cone opening is not.
func current_spread_degrees() -> float:
	return spread_degrees * (1.0 + _recoil_climb_amount)


func _show_muzzle_flash() -> void:
	_muzzle_flash.visible = true
	var timer := get_tree().create_timer(0.05)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(_muzzle_flash):
			_muzzle_flash.visible = false
	)


## Trace every pellet of one trigger pull.
##
## `fired` and `target_hit` are emitted at most once each, for the trigger pull
## rather than per pellet. Game counts shots fired and shots hit from those two
## signals and makes noise from the first — a shotgun that emitted eight of
## each would report 800% accuracy and call the horde eight times for one
## shell. `impacted` stays per pellet, because that one is decals, and eight
## holes in the wall is exactly what a shotgun should leave.
func _trace_shot() -> void:
	if _camera == null:
		return

	var origin := _camera.global_position
	var forward := -_camera.global_basis.z
	var spread := deg_to_rad(current_spread_degrees())
	var shot_destination := origin + forward * shot_range

	var space := get_world_3d().direct_space_state
	var owner_rid := _get_owner_rid()
	var struck: Node = null
	var damage_dealt := 0.0

	for index in maxi(pellets, 1):
		var direction := _spread_direction(forward, spread)
		var destination := origin + direction * shot_range

		var query := PhysicsRayQueryParameters3D.create(origin, destination)
		# World geometry and zombies, never the player's own body.
		query.collision_mask = 1 | 4
		query.exclude = [owner_rid]

		var result := space.intersect_ray(query)

		if not result.is_empty():
			destination = result.position
			var collider: Node = result.get("collider")
			var is_flesh := collider != null and collider.has_method("take_damage")

			if is_flesh:
				collider.take_damage(damage, result.position, direction)
				if struck == null:
					struck = collider
				damage_dealt += damage

			impacted.emit(
				result.position, result.get("normal", Vector3.UP), is_flesh
			)

		if index == 0:
			shot_destination = destination
		_spawn_tracer(_muzzle.global_position, destination)

	if struck != null:
		target_hit.emit(struck, damage_dealt)

	fired.emit(_muzzle.global_position, shot_destination)


## Jitter a direction inside a cone of `spread` radians around `forward`.
##
## The radius is square-rooted so pellets land evenly across the disc rather
## than bunching in the middle, which is what stops a shotgun reading as a
## slightly fuzzy rifle at range.
func _spread_direction(forward: Vector3, spread: float) -> Vector3:
	if spread <= 0.0 or _camera == null:
		return forward

	var angle := randf_range(0.0, TAU)
	var radius := sqrt(randf()) * tan(spread)
	var offset := (
		_camera.global_basis.x * cos(angle) * radius
		+ _camera.global_basis.y * sin(angle) * radius
	)
	return (forward + offset).normalized()


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
