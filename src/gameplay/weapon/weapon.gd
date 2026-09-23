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
## Reserve ammo landed on `kind`, `amount` rounds' worth, from a distribution
## pass. `distribute_reserve_ammo` routes rounds by need rather than by what
## is in the player's hands, which is correct for supply but means the
## destination is otherwise invisible: a crate can fill the holstered shotgun
## and the player has no way to know it happened. This signal exists so the
## HUD can say so.
signal reserve_gained(kind: WeaponTypes.Kind, amount: int)
## A decoy has left the hand. Game wires its landing to the noise system.
signal decoy_thrown(decoy: Decoy)
## Where a bullet landed, the surface normal, and whether it was a zombie.
signal impacted(position: Vector3, normal: Vector3, is_flesh: bool)
## A melee swing happened, and whether it connected with something living.
##
## Deliberately not `target_hit`. Game counts shots_hit from that signal and
## shots_fired from `fired`, and a melee hit that reported through it would
## push a round's accuracy above 100% without a bullet ever being spent.
## `staggered` is false when the swing landed on something that cannot be
## staggered — a Brute. That case has to be presentable as its own thing: a
## last resort that visibly does nothing against the enemy most likely to have
## cornered you reads as a broken game unless the game says otherwise. The
## weapon reports the distinction; Game decides what it sounds like.
signal melee_swung(hit: bool, staggered: bool, at: Vector3)

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

@export_group("Reload motion")
## How far the weapon drops (local -Y) at the low point of a reload, in
## metres.
@export var reload_dip_distance := 0.06
## How far the weapon rolls (around its own local Z) at the low point, in
## degrees. Combined with the dip, this is what makes "I cannot fire right
## now" readable at a glance rather than requiring a look at the HUD.
@export var reload_roll_degrees := 14.0
## Fraction of `reload_duration` spent dropping to the low point.
@export var reload_down_fraction := 0.22
## Fraction of `reload_duration` spent rising back to rest, timed to land
## exactly as the reload completes. Whatever is left between the two
## fractions is held at the low point — the magazine is actually being
## worked there, and there is nothing to animate through it.
@export var reload_up_fraction := 0.28

@export_group("Swap motion")
## How far the held weapon drops (local -Y) at the midpoint of a swap, in
## metres. The full swap dips to this and rises back out of it, so the pose
## the incoming weapon is revealed in is also the pose it has to climb out of.
@export var swap_drop_distance := 0.25
## How far the weapon rolls (around its own local Z) at the midpoint of a
## swap, in degrees. Same shorthand as the reload roll — a weapon dropped and
## canted away reads as "not ready" before the HUD or the cooldown has to say
## so.
@export var swap_roll_degrees := 28.0

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

@export_group("Melee")
## The floor under the whole ammo economy: something you can always do.
##
## `dry_resupply` prevents a *frozen* run — it trickles rounds into reserve, so
## the player still has to eat a reload before they can fire twice — but it does
## not prevent a *lost* one against a rising spawn rate. This does. It is
## available at all times rather than unlocked when dry, because a last resort
## that has to be granted is a mechanic the player has to be taught; one that is
## simply always there and simply always worse teaches itself.
##
## Sized so it never competes with a firearm. A Shambler has 50 health, so a
## pistol kills it in two rounds over 0.28s and this takes three swings over
## 2.2s — roughly a sixth of the damage per second. Whenever there are bullets,
## bullets are the right answer; that is the point.
@export var melee_damage := 18.0
## Reach in metres. Barely past a zombie's contact range, so a swing is a
## decision to let one get that close rather than a way to keep it away.
@export var melee_range := 2.0
## Deliberately long. A last resort should not become a rhythm — at just over a
## second a swing you commit to is a swing you cannot take back.
@export var melee_cooldown := 1.1
## Camera shake per swing. Above a gunshot's 0.2 because the swing is the whole
## body, and because a hit you cannot hear over a fight still has to land.
@export var melee_trauma := 0.28
## Shake for a hit that lands on something that cannot be staggered. Higher
## than a normal swing and near the 0.6 of being hit, because the swing went
## nowhere and the player needs to feel that rather than infer it.
@export var melee_unmoved_trauma := 0.42

@export_group("Melee motion")
## How far the weapon drives forward (local -Z) at full extension, in
## metres. Small on purpose — this is a first-person weapon a few
## centimetres from the camera, not a sword seen from outside.
@export var melee_motion_forward := 0.16
## Sideways drift (local X) at full extension, in metres. Positive is to
## the right, so the jab reads as a cross-body bash rather than a straight
## poke.
@export var melee_motion_side := 0.05
## Seconds to reach full extension. Fast on purpose — the strike has to
## read as an impact, not a drift.
@export var melee_out_time := 0.08
## Seconds to ease back to rest. Slower than the way out, so the recovery
## reads as the weapon settling rather than snapping back like elastic.
@export var melee_return_time := 0.25

@export_group("Decoy")
@export var throw_speed := 14.0
@export var throw_gravity := 18.0
## How much the throw is lobbed above the crosshair.
@export var throw_lift := 0.25
@export var throw_cooldown := 0.45
## Landing volume relative to a gunshot. Just under, so firing stays the
## loudest thing the player can do.
@export var decoy_loudness := 0.7

@export_group("Throw motion")
## How far the weapon dips (local -Y) at full extension of a throw, in
## metres.
@export var throw_motion_dip_distance := 0.05
## How far the weapon pushes forward (local -Z) at full extension of a throw,
## in metres.
@export var throw_motion_forward_distance := 0.08
## Seconds to reach full extension. Fast on purpose, same rationale as the
## fire kick's and the melee jab's out time — the flick has to read as a
## snap of the wrist, not a drift.
@export var throw_motion_out_time := 0.1
## Seconds to ease back to rest.
@export var throw_motion_return_time := 0.25

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

@export_group("Firing motion")
## Seconds for the viewmodel to snap to full kick after a shot. Fast on
## purpose — same rationale as the melee jab's out time — so it reads as an
## impact rather than a drift.
@export var fire_kick_out_time := 0.04
## Seconds to ease back from full kick to rest.
@export var fire_kick_return_time := 0.15
## Metres the weapon snaps back (local +Z, toward the camera) per degree of
## the equipped weapon's `recoil_pitch_degrees`. Riding on a stat every
## weapon already carries — rather than a second per-weapon table that would
## have to be kept in sync with it — is what makes the shotgun thump, the
## rifle chatter and the pistol snap without this file knowing which weapon
## is in hand.
@export var fire_kick_back_per_degree := 0.012
## Degrees the muzzle tips up (this node's own rotation.x) per degree of
## `recoil_pitch_degrees`. Shares the same reference stat as the position
## kick so the two always scale together.
@export var fire_muzzle_tip_per_degree := 0.55
## Light energy the muzzle flash jumps to on every shot. Mirrors the
## OmniLight3D's authored energy in the scene, kept here as well so both can
## be tuned from one place without opening the scene file.
@export var muzzle_flash_peak_energy := 6.0
## Seconds for the muzzle flash to decay from peak to off. A few tens of
## milliseconds reads as a flash; longer starts to look like the light was
## simply left on.
@export var muzzle_flash_decay_time := 0.035

@export_group("Hold motion")
## How far the weapon drops (local -Y) while a hold interaction — a medkit, an
## armed Signal relay — is in progress, in metres. Kept out of the way rather
## than left raised, since a raised gun during a two-second hold reads as
## "still ready", which during a hold is untrue — try_fire refuses while one
## is in progress. The pose is the visible half of that rule.
@export var hold_drop_distance := 0.18
## How far the weapon cants (around its own local Z) while a hold is in
## progress, in degrees. Same shorthand as the sprint carry's cant — a dropped,
## canted weapon reads as "not the point of this moment" at a glance.
@export var hold_cant_degrees := 15.0
## Seconds to ease into the lowered pose once a hold begins.
@export var hold_ease_in_time := 0.2
## Seconds to ease back to rest once the hold completes or is let go. Slower
## than the way down, so recovering reads as the weapon coming back up to meet
## the player rather than snapping into place.
@export var hold_ease_out_time := 0.25

@export_group("Sprint carry")
## How far the weapon drops (local -Y) at full sprint, in metres. A few
## centimetres — this is a carry pose, not a holster — so it reads as "held
## low and loose" without the model leaving the frame.
@export var sprint_carry_drop_distance := 0.04
## How far the weapon cants inward (around its own local Z) at full sprint,
## in degrees. The same silhouette shorthand games and film use for "running,
## not aiming" — legible at a glance, ahead of the HUD's speed or FOV change
## catching up.
@export var sprint_carry_roll_degrees := 10.0
## Seconds to ease fully into, or out of, the sprint pose. One value for both
## directions so starting and stopping a sprint read as the same motion
## played forward and back, rather than snapping in and drifting out.
@export var sprint_carry_ease_time := 0.2

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
var _melee_cooldown_remaining := 0.0
## Melee jab: a local-space offset composed into `position`, plus the timer
## and flag that drive it. Reset on every swing in `try_melee`, and zeroed on
## any weapon swap or round reset so a swing can never leave the model stuck
## mid-animation.
var _melee_offset := Vector3.ZERO
var _melee_anim_time := 0.0
var _melee_anim_active := false
## Reload dip and roll. Driven purely from `_is_reloading` and
## `_reload_remaining` rather than its own timer, so it can never drift out
## of sync with the reload it is illustrating.
var _reload_offset := Vector3.ZERO
var _reload_roll := 0.0
## Fire kick: a local-space offset plus a muzzle-tip rotation, both driven
## off one timer. `_fire_kick_peak` and `_fire_tip_peak` are computed once
## per shot in `_apply_fire_kick` and the timer is restarted rather than
## added to — see the comment there for why a rifle burst does not run away.
var _fire_offset := Vector3.ZERO
var _fire_tip := 0.0
var _fire_kick_peak := Vector3.ZERO
var _fire_tip_peak := 0.0
var _fire_anim_time := 0.0
var _fire_anim_active := false
## How far through the rise the kick was when it was last restarted, as a
## fraction of peak. Lets a restarted kick blend up from where it already was
## instead of popping back to zero — see `_apply_fire_kick`.
var _fire_start_weight := 0.0
## Sprint carry: a local-space offset plus a roll, same shape as the reload
## dip above. Unlike the reload, melee and fire motions — each a fixed-length
## animation triggered once and left to play out — sprinting is a stance that
## can start or stop on any frame, so there is no timer to drive this from.
## `_sprint_weight` is instead a plain 0..1 ramp, advanced every frame by
## `_tick_sprint_motion` at a constant rate toward whichever end the current
## stance points at; smoothstep is applied to it at the point of use (not
## stored) so the ramp itself stays linear while the pose still eases in and
## out rather than moving at constant speed.
var _sprint_weight := 0.0
var _sprint_offset := Vector3.ZERO
var _sprint_roll := 0.0
## Hold motion: same 0..1 ramp shape as `_sprint_weight` above, and for the
## same reason — a hold interaction can start or stop on any frame (the key
## can be let go, or the hold can complete, at any point), so there is no
## fixed-length animation to trigger this from either. Driven by
## `Interactor.hold_progress()` through `_owner_body()`, read with the same
## `has_method` indirection `_tick_sprint_motion` uses for `stance()` — this
## file has no hard dependency on the player or interactor classes.
var _hold_weight := 0.0
var _hold_offset := Vector3.ZERO
var _hold_roll := 0.0
## Swap dip and roll: the outgoing weapon drops out of view over the first
## half of a swap, the visible model hands over at the midpoint (see
## `_tick_swap`), and the incoming weapon rises back into place over the
## second half. Driven purely from `_swap_remaining` against the target's own
## `swap_duration`, the same way `_reload_offset` is driven from
## `_reload_remaining` — there is no separate timer here to drift out of sync
## with the swap it is illustrating.
var _swap_offset := Vector3.ZERO
var _swap_roll := 0.0
## True once the visible model has been handed over for the swap in progress.
## Reset whenever a new swap begins, so the handover in `_tick_swap` happens
## exactly once, at the midpoint, rather than on every frame past it.
var _swap_model_shown := false
## Throw flick: a local-space offset driven off one timer, the same shape as
## the fire kick (see `_apply_fire_kick`/`_tick_fire_motion`) but with a fixed
## peak rather than one scaled by a per-weapon stat — a decoy throw is the
## same flick no matter which weapon is in the other hand.
var _throw_offset := Vector3.ZERO
var _throw_anim_time := 0.0
var _throw_anim_active := false
## How far through the rise the flick was when it was last restarted, as a
## fraction of peak — same purpose as `_fire_start_weight`, see
## `_apply_throw_kick`.
var _throw_start_weight := 0.0
## Sum of the six offsets above. Kept as its own field only so the
## composition into `position` (in `_tick_viewmodel`) has one visible site
## instead of separate writers fighting over the same property.
var _action_offset := Vector3.ZERO

@onready var _camera: Camera3D = _resolve_camera()
@onready var _muzzle: Node3D = $Muzzle
@onready var _muzzle_flash: OmniLight3D = $Muzzle/Flash


func _ready() -> void:
	_rest_position = position
	_build_slots()
	_equip_now(starting_kind)
	_muzzle_flash.visible = false
	# Seeded at zero rather than left at the scene's authored peak, so the
	# first shot is the first time the light is ever seen lit — otherwise the
	# very first `visible = true` would flash at whatever energy the editor
	# saved the node with.
	_muzzle_flash.light_energy = 0.0
	ammo_changed.emit(magazine_ammo, reserve_ammo)


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	_tick_swap(delta)
	_tick_reload(delta)
	_tick_recoil(delta)
	_tick_recoil_climb(delta)
	_tick_melee_motion(delta)
	_tick_reload_motion()
	_tick_swap_motion()
	_tick_fire_motion(delta)
	_tick_throw_motion(delta)
	_tick_sprint_motion(delta)
	_tick_hold_motion(delta)
	_tick_muzzle_flash(delta)
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
	elif Input.is_action_just_pressed("melee"):
		try_melee()
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
	# A new weapon in hand starts from a clean pose. Without this, a swing, a
	# reload or a fire kick interrupted by an instant equip (round start,
	# `reset_state`) would hand the next weapon a leftover offset or roll it
	# never earned.
	_melee_anim_time = 0.0
	_melee_anim_active = false
	_melee_offset = Vector3.ZERO
	_reload_offset = Vector3.ZERO
	_reload_roll = 0.0
	_fire_anim_time = 0.0
	_fire_anim_active = false
	_fire_offset = Vector3.ZERO
	_fire_tip = 0.0
	_fire_start_weight = 0.0
	_sprint_weight = 0.0
	_sprint_offset = Vector3.ZERO
	_sprint_roll = 0.0
	_hold_weight = 0.0
	_hold_offset = Vector3.ZERO
	_hold_roll = 0.0
	_swap_offset = Vector3.ZERO
	_swap_roll = 0.0
	_swap_model_shown = false
	_throw_anim_time = 0.0
	_throw_anim_active = false
	_throw_offset = Vector3.ZERO
	_throw_start_weight = 0.0

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
	_reload_offset = Vector3.ZERO
	_reload_roll = 0.0
	# A swing does not survive a swap either — the weapon coming up is not
	# the one that was mid-jab. Same for a fire kick still playing out.
	_melee_anim_time = 0.0
	_melee_anim_active = false
	_melee_offset = Vector3.ZERO
	_fire_anim_time = 0.0
	_fire_anim_active = false
	_fire_offset = Vector3.ZERO
	_fire_tip = 0.0
	_fire_start_weight = 0.0
	_sprint_weight = 0.0
	_sprint_offset = Vector3.ZERO
	_sprint_roll = 0.0
	_hold_weight = 0.0
	_hold_offset = Vector3.ZERO
	_hold_roll = 0.0
	_throw_anim_time = 0.0
	_throw_anim_active = false
	_throw_offset = Vector3.ZERO
	_throw_start_weight = 0.0

	_swap_target = target
	_swap_remaining = maxf(_slots[target].stats.swap_duration, 0.0)
	# `_equip_now` already clears this at the end of every swap, but setting
	# it again here means a fresh swap's midpoint handover does not depend on
	# remembering that fact — it is armed at the same place `_swap_target`
	# and `_swap_remaining` are.
	_swap_model_shown = false
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

	# The visible model hands over at the midpoint, ahead of the stats and
	# ammo swap below in `_finish_swap`. The two are deliberately split: the
	# gameplay-relevant swap (what can be fired, what the magazine holds) still
	# only ever happens at the end, exactly as `_swap_remaining` reaching zero
	# already guaranteed, but the model the player sees can change earlier
	# because `_show_model` only touches what is displayed — it does not read
	# or write `kind`, ammo or any exported stat. That is what makes handing
	# the model over here, instead of in `_finish_swap`, safe to do at all.
	# Gated on `_swap_model_shown` so the handover fires exactly once per swap
	# rather than every frame past the midpoint.
	if not _swap_model_shown and _swap_elapsed_fraction() >= 0.5:
		_swap_model_shown = true
		var target_stats: Dictionary = _slots[_swap_target].stats
		_show_model(target_stats.get("model", ""), target_stats.get("tint", Color.WHITE) as Color)

	if _swap_remaining <= 0.0:
		_finish_swap()


func _finish_swap() -> void:
	_store_current_slot()
	_swap_remaining = 0.0
	_equip_now(_swap_target)


## Fraction of the current swap that has elapsed, timed against the target
## weapon's own `swap_duration` rather than whatever `swap_duration` currently
## reads — that exported field still belongs to the weapon being swapped
## away from until `_finish_swap` runs, so dividing by it here would drift
## the moment the two weapons disagree on how long a swap takes.
func _swap_elapsed_fraction() -> float:
	var total: float = _slots[_swap_target].stats.swap_duration
	return 1.0 - clampf(_swap_remaining / maxf(total, 0.001), 0.0, 1.0)


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
	# Hands busy with a hold — the same rule as try_fire.
	if _is_holding_interaction():
		return null

	reserve_ammo -= 1
	_throw_cooldown_remaining = throw_cooldown
	ammo_changed.emit(magazine_ammo, reserve_ammo)

	var decoy := Decoy.new()
	decoy.gravity = throw_gravity
	decoy.loudness = decoy_loudness

	_world_parent().add_child(decoy)
	decoy.launch(_throw_origin(), _throw_velocity())

	_apply_throw_motion()
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
	_melee_cooldown_remaining = maxf(0.0, _melee_cooldown_remaining - delta)


## Seconds until the next swing is available. Zero means ready.
func melee_cooldown_remaining() -> float:
	return _melee_cooldown_remaining


## Swing at whatever is directly in front of the player.
##
## Returns true when a swing was taken, hit or miss — the cooldown is spent
## either way, because a melee you can spam with no risk of whiffing is not a
## last resort, it is a free interrupt.
##
## Traces the same way a bullet does: one ray, world geometry and zombies, the
## player's own body excluded. Reusing that path rather than writing a second
## one is what keeps a swing agreeing with a shot about what counts as cover.
## The differences that matter are all in the numbers — two metres instead of
## eighty, one ray instead of eight, no spread, no noise.
##
## No noise is emitted on purpose. It is the only damage in the game that does
## not tell the cave where you are, which is the one advantage it has over the
## pistol and the reason it is worth reaching for before the last round rather
## than after it.
func try_melee() -> bool:
	if not _input_enabled or _melee_cooldown_remaining > 0.0:
		return false
	# Hands busy with a hold — the same rule as try_fire.
	if _is_holding_interaction():
		return false
	if _camera == null:
		return false

	_melee_cooldown_remaining = melee_cooldown

	# Restart the jab from the top on every swing, hit or miss — the visual
	# has to fire on the same terms as `melee_swung` does below, or a whiffed
	# swing would read as a dropped input rather than an attempt.
	_melee_anim_time = 0.0
	_melee_anim_active = true

	var origin := _camera.global_position
	var direction := -_camera.global_basis.z
	var destination := origin + direction * melee_range

	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	query.collision_mask = 1 | 4
	query.exclude = [_get_owner_rid()]

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		# A swing through empty air still reports, so the sound and the shake
		# fire. Feedback that only exists on a hit reads as a dropped input.
		melee_swung.emit(false, false, destination)
		return true

	var collider: Node = result.get("collider")
	var is_flesh := collider != null and collider.has_method("take_damage")

	# Read rather than assumed, and read through `get` so the weapon layer does
	# not take a hard dependency on the zombie class to answer it. A kind with
	# no stagger duration is one that will not flinch, and the player has to be
	# told that it did not flinch *because it cannot*, not because the swing
	# failed to register.
	var staggered := is_flesh and float(collider.get("stagger_duration")) > 0.0

	if is_flesh:
		# The stagger comes free with this call. A zombie flinches and drops a
		# wind-up whenever it is damaged, which is exactly the breathing room a
		# melee exists to buy — and a Brute's immunity to that flinch carries
		# over unchanged, so the one enemy you cannot shoot your way out of is
		# also the one you cannot club your way out of. No zombie-side change
		# was needed for any of it.
		collider.take_damage(melee_damage, result.position, direction)

	impacted.emit(result.position, result.get("normal", Vector3.UP), is_flesh)
	melee_swung.emit(is_flesh, staggered, result.position)
	return true


## Fire one round. Returns true only when a bullet actually left the weapon.
func try_fire() -> bool:
	# A weapon that is still coming up cannot be fired. This is the guarantee
	# that makes swap_duration a real cost rather than a cosmetic animation.
	if _swap_remaining > 0.0:
		return false
	if _is_reloading or _cooldown_remaining > 0.0:
		return false
	# Hands busy. A medkit is meant to cost "two seconds of standing still, so
	# it is still a decision", and arming a relay is meant to be exposed — but
	# nothing stopped the trigger during a hold, so both could be done while
	# fighting and neither was a decision at all. The weapon is visibly lowered
	# for the length of a hold (_tick_hold_motion); letting go of the interact
	# key brings it back up, which is the choice the design asks for.
	if _is_holding_interaction():
		return false

	if magazine_ammo <= 0:
		# Boundary case: empty magazine blocks the shot entirely.
		dry_fired.emit()
		return false

	magazine_ammo -= 1
	_cooldown_remaining = fire_cooldown
	ammo_changed.emit(magazine_ammo, reserve_ammo)

	_apply_recoil()
	_apply_fire_kick()
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
	var taken := 0
	# Tallied per kind and emitted once each after the loop, not once per
	# round: a kill can spray a dozen individual awards across two weapons in
	# the same frame, and a signal per round would ask the HUD to coalesce
	# what the source already knows in one pass.
	var gained_by_kind: Dictionary = {}

	# One round at a time, re-asking each time. Amounts here are small — a kill
	# is worth a handful — and handing them out individually is what stops a
	# single award overfilling one weapon past the point where another became
	# the needier one.
	for _index in maxi(amount, 0):
		var target := _neediest_kind()
		if target < 0:
			break
		_award_one(target)
		taken += 1
		gained_by_kind[target] = int(gained_by_kind.get(target, 0)) + 1

	for target_kind in gained_by_kind:
		reserve_gained.emit(target_kind, int(gained_by_kind[target_kind]))

	return taken


## The weapon most in need of the next round.
##
## Emptiest *relative to its own ceiling*, not in absolute rounds, with the
## weapon in hand breaking ties.
##
## The relative test is the load-bearing part. Ranked by absolute reserve the
## shotgun is always bottom — it starts at 16 against the rifle's 60 — so it
## would take the first sixteen rounds of every round's income and shells would
## be the *easiest* thing to come by. That is backwards: the shotgun is the
## expensive committal answer, and its small magazine and small ceiling are how
## it says so. By fill fraction all three start level at half full, so income
## follows what was actually spent.
##
## This is what keeps the fallback from starving. Rewarding the weapon in hand
## sounds natural and creates a trap: you do not hold the pistol, so it never
## refills, so you cannot fall back to it, so you never hold it. Rewarding the
## emptiest means switching to the pistol to save shells is also what refills
## the pistol. Nothing can self-fund either — a weapon at its ceiling stops
## drawing income entirely, which is how the shotgun's ceiling of 32 keeps
## shells scarce without anyone tuning a reward for it.
##
## Returns -1 when every weapon is full.
func _neediest_kind() -> int:
	var best := -1
	var best_fill := INF

	for slot_kind in _slots:
		var ceiling := reserve_ceiling_for(slot_kind)
		var reserve := reserve_for(slot_kind)
		if reserve >= ceiling:
			continue

		var fill := float(reserve) / maxf(float(ceiling), 1.0)
		# Strictly less, so an equal fill leaves the incumbent in place; the
		# held weapon is seeded first below to make that tie-break deliberate.
		if fill < best_fill:
			best_fill = fill
			best = slot_kind

	# Tie-break to the weapon in hand: if it is exactly as empty as the winner,
	# the rounds go where the player is actually shooting from.
	var held_ceiling := reserve_ceiling_for(kind)
	var held_reserve := reserve_for(kind)
	if held_reserve < held_ceiling:
		var held_fill := float(held_reserve) / maxf(float(held_ceiling), 1.0)
		if is_equal_approx(held_fill, best_fill):
			best = kind

	return best


## Reserve for any kind, reading the live field for the weapon in hand.
##
## Public because the held weapon's reserve lives in `reserve_ammo` and only
## reaches its slot on a swap, so anything reading `_slots` directly gets a
## stale figure for whatever is in the player's hands — the one place this is
## easy to get silently wrong.
func reserve_for(slot_kind: WeaponTypes.Kind) -> int:
	if slot_kind == kind:
		return reserve_ammo
	return int(_slots[slot_kind].reserve)


## Reserve ceiling for any kind, with the same caveat as reserve_for.
func reserve_ceiling_for(slot_kind: WeaponTypes.Kind) -> int:
	if slot_kind == kind:
		return max_reserve
	return int(_slots[slot_kind].stats.max_reserve)


func _award_one(slot_kind: WeaponTypes.Kind) -> void:
	if slot_kind == kind:
		reserve_ammo += 1
		ammo_changed.emit(magazine_ammo, reserve_ammo)
		return
	_slots[slot_kind].reserve = int(_slots[slot_kind].reserve) + 1


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
	_melee_cooldown_remaining = 0.0
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

	# Melee, reload, the swap dip, the fire kick, the throw flick, the sprint
	# carry and the hold motion each write a temporary offset elsewhere (see
	# `_tick_melee_motion`, `_tick_reload_motion`, `_tick_swap_motion`,
	# `_tick_fire_motion`, `_tick_throw_motion`, `_tick_sprint_motion` and
	# `_tick_hold_motion`); summed in here rather than in a second `position`
	# write, so this stays the only place the weapon's position is actually
	# set.
	_action_offset = (
		_melee_offset + _reload_offset + _swap_offset + _fire_offset
		+ _throw_offset + _sprint_offset + _hold_offset
	)
	position = _rest_position + _sway_offset + _action_offset
	# The weapon node's own rotation has two writers and no more: rotation.z
	# sums the reload roll, the swap roll, the sprint cant and the hold cant,
	# rotation.x is the fire kick's muzzle tip. Recoil still drives the
	# camera's pitch, never this.
	rotation.z = _reload_roll + _swap_roll + _sprint_roll + _hold_roll
	rotation.x = _fire_tip


## Drives the melee jab: a fast rise to full extension, then a slower ease
## back to rest. Triggered once per swing from `try_melee`, on a hit or a
## miss alike — a whiffed swing still has to look like an attempt.
func _tick_melee_motion(delta: float) -> void:
	if not _melee_anim_active:
		return

	_melee_anim_time += delta
	var total_duration := melee_out_time + melee_return_time

	if _melee_anim_time >= total_duration:
		_melee_anim_active = false
		_melee_offset = Vector3.ZERO
		return

	var weight := 0.0
	if _melee_anim_time < melee_out_time:
		# Quick rise to full extension — the "snap" of the strike.
		var out_t := _melee_anim_time / maxf(melee_out_time, 0.001)
		weight = sin(out_t * PI * 0.5)
	else:
		# Slower, eased fall back to rest — the recovery. Smoothstep leaves
		# and arrives gently rather than snapping into place at full speed,
		# which is what a raw cosine ease-out does here.
		var back_t := (_melee_anim_time - melee_out_time) / maxf(melee_return_time, 0.001)
		weight = 1.0 - smoothstep(0.0, 1.0, back_t)

	_melee_offset = Vector3(melee_motion_side, 0.0, -melee_motion_forward) * weight


## Dips and rolls the weapon through a reload: down over `reload_down_fraction`
## of the reload, held low through the middle, and back up over the final
## `reload_up_fraction` so it reaches rest exactly as the reload completes.
##
## Driven from `_reload_remaining` against `reload_duration` rather than its
## own timer, so the shape always lands correctly whether it is a 1.6s pistol
## reload or a much longer shotgun one — there is nothing here to fall out of
## sync with.
func _tick_reload_motion() -> void:
	if not _is_reloading:
		_reload_offset = Vector3.ZERO
		_reload_roll = 0.0
		return

	var elapsed_fraction := 1.0 - clampf(_reload_remaining / maxf(reload_duration, 0.001), 0.0, 1.0)
	var weight := 0.0

	if elapsed_fraction < reload_down_fraction:
		var down_t := elapsed_fraction / maxf(reload_down_fraction, 0.001)
		weight = smoothstep(0.0, 1.0, down_t)
	elif elapsed_fraction < 1.0 - reload_up_fraction:
		weight = 1.0
	else:
		var up_t := (elapsed_fraction - (1.0 - reload_up_fraction)) / maxf(reload_up_fraction, 0.001)
		weight = smoothstep(0.0, 1.0, 1.0 - up_t)

	_reload_offset = Vector3(0.0, -reload_dip_distance, 0.0) * weight
	_reload_roll = deg_to_rad(reload_roll_degrees) * weight


## Dips and rolls the weapon through a swap: the outgoing weapon drops out of
## view over the first half with an ease-in, and the incoming weapon — shown
## at the midpoint by `_tick_swap` — rises back into place over the second
## half with an ease-out. The result reads as one continuous "down, handover,
## up" swap rather than a countdown with a gun that pops in at the end.
##
## Driven from `_swap_remaining` against `_swap_elapsed_fraction` rather than
## its own timer, for the same reason `_tick_reload_motion` reads
## `_reload_remaining`: the countdown that actually gates firing already
## exists and has to stay authoritative, so this only ever samples it and
## never drives it.
func _tick_swap_motion() -> void:
	if _swap_remaining <= 0.0:
		_swap_offset = Vector3.ZERO
		_swap_roll = 0.0
		return

	var elapsed_fraction := _swap_elapsed_fraction()
	var weight := 0.0

	if elapsed_fraction < 0.5:
		# Ease-in: slow to start, accelerating toward the low point, so the
		# drop reads as a deliberate pull down and away rather than a snap.
		var down_t := elapsed_fraction / 0.5
		weight = down_t * down_t
	else:
		# Ease-out: fast off the low point, slowing into rest, so the rise
		# reads as the new weapon arriving rather than drifting to a stop.
		var up_t := (elapsed_fraction - 0.5) / 0.5
		weight = 1.0 - up_t * up_t

	_swap_offset = Vector3(0.0, -swap_drop_distance, 0.0) * weight
	_swap_roll = deg_to_rad(swap_roll_degrees) * weight


## Drives the fire kick: a fast snap to full extension, then a slower ease
## back to rest. Same shape as `_tick_melee_motion` — a sine rise for the
## snap, a smoothstep fall for the recovery — so the two read as the same
## family of motion on the same weapon. `_fire_kick_peak`/`_fire_tip_peak`
## already carry the per-weapon scale, computed once in `_apply_fire_kick`.
func _tick_fire_motion(delta: float) -> void:
	if not _fire_anim_active:
		return

	_fire_anim_time += delta
	var total_duration := fire_kick_out_time + fire_kick_return_time

	if _fire_anim_time >= total_duration:
		_fire_anim_active = false
		_fire_offset = Vector3.ZERO
		_fire_tip = 0.0
		return

	var weight := 0.0
	if _fire_anim_time < fire_kick_out_time:
		# Quick rise to full extension — the "snap" of the shot. Blends up
		# from `_fire_start_weight` rather than from zero, so a kick that was
		# restarted mid-recovery (see `_apply_fire_kick`) continues from
		# wherever it already was instead of popping back to rest for a
		# frame before rising again.
		var out_t := _fire_anim_time / maxf(fire_kick_out_time, 0.001)
		weight = lerpf(_fire_start_weight, 1.0, sin(out_t * PI * 0.5))
	else:
		# Slower, eased fall back to rest.
		var back_t := (_fire_anim_time - fire_kick_out_time) / maxf(fire_kick_return_time, 0.001)
		weight = 1.0 - smoothstep(0.0, 1.0, back_t)

	_fire_offset = _fire_kick_peak * weight
	_fire_tip = _fire_tip_peak * weight


## Drives the decoy throw flick: a fast snap to full extension, then a slower
## ease back to rest. Same shape as `_tick_fire_motion` — a sine rise for the
## snap, blending up from `_throw_start_weight` rather than zero so a
## retriggered throw does not pop, and a smoothstep fall for the recovery.
func _tick_throw_motion(delta: float) -> void:
	if not _throw_anim_active:
		return

	_throw_anim_time += delta
	var total_duration := throw_motion_out_time + throw_motion_return_time

	if _throw_anim_time >= total_duration:
		_throw_anim_active = false
		_throw_offset = Vector3.ZERO
		return

	var weight := 0.0
	if _throw_anim_time < throw_motion_out_time:
		var out_t := _throw_anim_time / maxf(throw_motion_out_time, 0.001)
		weight = lerpf(_throw_start_weight, 1.0, sin(out_t * PI * 0.5))
	else:
		var back_t := (_throw_anim_time - throw_motion_out_time) / maxf(throw_motion_return_time, 0.001)
		weight = 1.0 - smoothstep(0.0, 1.0, back_t)

	_throw_offset = Vector3(0.0, -throw_motion_dip_distance, -throw_motion_forward_distance) * weight


## Eases the weapon into, or out of, a sprint carry pose: dropped and canted
## while the owning body is sprinting, back to rest otherwise.
##
## Unlike the melee jab, reload dip and fire kick above — each a fixed-length
## animation fired once and left to play out — sprinting is a stance that can
## start or stop on any given frame, so there is no shot or swing to time an
## animation from. This instead advances `_sprint_weight`, a plain 0..1 ramp,
## toward whichever end the current stance points at, at a constant rate set
## by `sprint_carry_ease_time`; smoothstep is applied on top at the point of
## use so the pose still eases in and out rather than moving at a constant
## speed, without the ramp itself needing a start time to ease relative to.
##
## Reads the stance through `has_method` rather than typing the body as
## `Player`, so this file never has to hard-depend on the player script —
## the same indirection `_owner_body` already keeps by returning a plain
## `CharacterBody3D`.
func _tick_sprint_motion(delta: float) -> void:
	var body := _owner_body()
	# `body.stance()` is a dynamic call — CharacterBody3D itself does not
	# declare it — so its result comes back untyped. `has_method` guards the
	# call rather than a hard `is Player` check, which is the dependency this
	# file is avoiding; the explicit `bool` below is only there because an
	# untyped operand keeps the whole `and` chain untyped for `:=` to infer.
	var sprinting: bool = (
		body != null
		and body.has_method("stance")
		and body.stance() == Player.Stance.SPRINTING
	)

	var rate := 1.0 / maxf(sprint_carry_ease_time, 0.001)
	_sprint_weight = move_toward(_sprint_weight, 1.0 if sprinting else 0.0, rate * delta)
	var weight := smoothstep(0.0, 1.0, _sprint_weight)

	_sprint_offset = Vector3(0.0, -sprint_carry_drop_distance, 0.0) * weight
	_sprint_roll = deg_to_rad(sprint_carry_roll_degrees) * weight


## Eases the weapon down and canted while the player is mid-hold — a medkit, an
## armed Signal relay — and back up once the hold completes or is let go.
##
## Design intent: a hold interaction should read as the player's attention
## leaving the weapon, the same way the sprint carry reads as their attention
## leaving aim. Implements that reading for the same reason `_tick_sprint_motion`
## exists — a raised gun during a two-second stand-still otherwise looks like
## nothing is happening.
##
## Same ramp shape as `_tick_sprint_motion`: a hold, like a sprint, can begin
## or end on any given frame — the player can release the key, or the hold can
## finish, at any point — so there is no fixed-length animation to trigger this
## from. `_hold_weight` is instead a plain 0..1 ramp advanced at a constant
## rate toward whichever end `Interactor.hold_progress()` points at, with
## smoothstep applied on top at the point of use so the pose still eases rather
## than moving at constant speed. Unlike the sprint carry, the two directions
## use different rates — `hold_ease_in_time` down, `hold_ease_out_time` up —
## because the design calls for lowering and raising to read as different
## costs, not one motion played forward and back.
##
## Reads the interactor through `get`/`has_method` rather than typing the body
## as `Player`, for the same reason `_tick_sprint_motion` reads `stance()` that
## way: this file must not take a hard dependency on the player or interactor
## classes to answer a question about a stance.
func _tick_hold_motion(delta: float) -> void:
	var holding := _is_holding_interaction()

	var ease_time := hold_ease_in_time if holding else hold_ease_out_time
	var rate := 1.0 / maxf(ease_time, 0.001)
	_hold_weight = move_toward(_hold_weight, 1.0 if holding else 0.0, rate * delta)
	var weight := smoothstep(0.0, 1.0, _hold_weight)

	_hold_offset = Vector3(0.0, -hold_drop_distance, 0.0) * weight
	_hold_roll = deg_to_rad(hold_cant_degrees) * weight


## Whether the owner is part-way through a hold interaction — a medkit, a
## Signal relay. Read through get/has_method so this file keeps no hard
## dependency on the player or interactor classes.
func _is_holding_interaction() -> bool:
	var body := _owner_body()
	if body == null:
		return false
	var interactor: Variant = body.get("interactor")
	return (
		interactor != null
		and interactor.has_method("hold_progress")
		and float(interactor.hold_progress()) > 0.0
	)


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


## Trigger the viewmodel kick for one shot.
##
## Restarts the timer and recomputes the peak rather than adding to whatever
## offset is already in flight, so the offset is always bounded by one
## weapon's peak no matter how fast the trigger is pulled. Restarting the
## timer alone would make `_tick_fire_motion` start its next rise from
## `sin(0) == 0`, snapping the offset back to rest for a frame before it
## rises again — a visible pop on every round of a burst. `_fire_start_weight`
## captures how far through the previous kick's rise the weapon already was,
## as a fraction of the peak that is about to be replaced, so the new rise
## blends up from there instead. A weapon whose `fire_cooldown` is shorter
## than `fire_kick_out_time + fire_kick_return_time` — the rifle, at a 0.09s
## cooldown against a ~0.19s kick — hits this on every round of a burst, not
## just as an edge case.
func _apply_fire_kick() -> void:
	_fire_start_weight = 0.0
	if _fire_anim_active:
		_fire_start_weight = clampf(
			_fire_offset.z / maxf(_fire_kick_peak.z, 0.0001), 0.0, 1.0
		)

	_fire_anim_time = 0.0
	_fire_anim_active = true
	_fire_kick_peak = Vector3(0.0, 0.0, fire_kick_back_per_degree * recoil_pitch_degrees)
	_fire_tip_peak = deg_to_rad(fire_muzzle_tip_per_degree * recoil_pitch_degrees)


## Trigger the viewmodel flick for one decoy throw.
##
## Same shape as `_apply_fire_kick`: restarts the timer rather than adding to
## whatever offset is already in flight, so the offset is always bounded by
## one flick's peak no matter how fast the throw is retriggered, and captures
## `_throw_start_weight` from the offset already in flight so a restarted
## flick blends up from there instead of popping back to rest for a frame.
## Y is read rather than Z because dip can never be tuned to zero the way the
## fire kick's Z sometimes is on a weapon with no recoil — it is always a safe
## denominator.
func _apply_throw_motion() -> void:
	_throw_start_weight = 0.0
	if _throw_anim_active:
		_throw_start_weight = clampf(
			_throw_offset.y / minf(-throw_motion_dip_distance, -0.0001), 0.0, 1.0
		)

	_throw_anim_time = 0.0
	_throw_anim_active = true


## The cone every pellet is jittered inside, widened by accumulated climb.
##
## Tying spread to the same climb as the kick is what makes sustained rifle
## fire actually punishing: the muzzle walking up is something the player can
## fight, the cone opening is not.
func current_spread_degrees() -> float:
	return spread_degrees * (1.0 + _recoil_climb_amount)


## Jump the muzzle light to its peak. `_tick_muzzle_flash` owns bringing it
## back down every frame — see that function for why a pulse replaces the old
## visible on/off switch.
func _show_muzzle_flash() -> void:
	_muzzle_flash.light_energy = muzzle_flash_peak_energy
	_muzzle_flash.visible = true


## Decay the muzzle light from its peak back to off.
##
## A binary `visible = true` then a timer flipping it back off reads as a
## light switch, not a flash — real muzzle flashes are a spike that fades,
## not a step function. Doing the fade here, once per frame, is also cheaper
## than the old approach's per-shot `SceneTreeTimer` and closure.
func _tick_muzzle_flash(delta: float) -> void:
	if not _muzzle_flash.visible:
		return

	var decay_rate := muzzle_flash_peak_energy / maxf(muzzle_flash_decay_time, 0.001)
	_muzzle_flash.light_energy = move_toward(_muzzle_flash.light_energy, 0.0, decay_rate * delta)

	if is_zero_approx(_muzzle_flash.light_energy):
		_muzzle_flash.visible = false


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

	# `current_scene` is null when the game is driven by a --script tool rather
	# than run normally, and a tracer is spawned on every pellet — so under a
	# headless probe this produced one engine error per pellet and drowned the
	# output it was there to read. _world_parent already answers this question
	# correctly for the decoy; the tracer should have been asking it too.
	_world_parent().add_child(mesh_instance)
	mesh_instance.global_position = from.lerp(to, 0.5)
	# CylinderMesh runs along local Y, so aim that axis down the shot.
	#
	# The up vector is chosen off the shot direction for the same reason the
	# impact spray picks one: a shot fired straight down at the floor is
	# colinear with Vector3.UP, which leaves look_at unable to resolve roll. A
	# tracer is a cylinder and has no meaningful roll, so any resolving axis is
	# as good as another.
	var along := (to - mesh_instance.global_position).normalized()
	var tracer_up := Vector3.UP
	if absf(along.dot(Vector3.UP)) > 0.99:
		tracer_up = Vector3.FORWARD

	mesh_instance.look_at_from_position(
		mesh_instance.global_position, to, tracer_up
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
