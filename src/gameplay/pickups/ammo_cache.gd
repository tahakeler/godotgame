class_name AmmoCache
extends Node3D

## A fixed resupply point that refills slowly after it is emptied.
##
## The map was previously scenery: fourteen chambers with no reason to prefer
## any of them, so an entire round could be played in one room. Caches give the
## space a geography — you learn where ammunition lives and plan routes through
## it, and leaving a defensible spot to reach one is a decision rather than a
## wander.
##
## They pair with the noise system deliberately. Fighting next to a cache is
## loud, and loud draws the crowd to exactly the place you need to come back
## to, so the skilled play is to pull the horde away first and loop back.
##
## Recharging rather than being consumed once is what stops the map becoming a
## checklist: a cleared cache is a reason to return later, not a dead prop.

signal collected(rounds: int)

@export var capacity := 8
## Seconds from empty back to full.
@export var recharge_seconds := 55.0
## Height of the light above the crate.
@export var glow_height := 1.4

const CRATE_MODEL := "res://assets/models/weapons/crate-medium.glb"
const CHARGED_COLOUR := Color(1.0, 0.76, 0.32)
const EMPTY_COLOUR := Color(0.32, 0.38, 0.5)

var _stock := 0
var _recharge_remaining := 0.0
var _player_inside := false

var _light: OmniLight3D
var _area: Area3D


func _ready() -> void:
	_stock = capacity
	_build()
	_refresh_glow()


func _process(delta: float) -> void:
	if _stock < capacity:
		_recharge_remaining -= delta
		if _recharge_remaining <= 0.0:
			_stock = capacity
			_refresh_glow()

	# Checked per frame rather than only on entry, so a player standing on a
	# cache when it refills is served without having to step off and back on.
	# Camping is not the risk it sounds like: the recharge is long enough that
	# waiting it out in the open is its own punishment.
	if _player_inside and _stock > 0:
		_collect()


## True when there is anything to take. Used by tests and by the HUD prompt.
func has_stock() -> bool:
	return _stock > 0


func stock() -> int:
	return _stock


## Refill immediately. Used by round restart, so a new round never begins with
## the caches the last one drained.
func reset() -> void:
	_stock = capacity
	_recharge_remaining = 0.0
	_refresh_glow()


func _collect() -> void:
	var taken := _stock
	_stock = 0
	_recharge_remaining = recharge_seconds
	_refresh_glow()
	collected.emit(taken)


## The light is the whole readout: amber means there is something here, cold
## blue means come back later. It has to be legible from across a chamber,
## because the decision to cross the room is made from across the room.
func _refresh_glow() -> void:
	if _light == null:
		return

	_light.light_color = CHARGED_COLOUR if has_stock() else EMPTY_COLOUR
	_light.light_energy = 2.6 if has_stock() else 0.7


func _build() -> void:
	var scene: PackedScene = load(CRATE_MODEL)
	if scene != null:
		var crate: Node3D = scene.instantiate()
		add_child(crate)
		# The crate is solid; the trigger below is not. Its cylinder reaches
		# 1.6m, comfortably past the 0.6m half-length of the crate, so standing
		# against a cache still counts as standing in it.
		MeshCollision.fit(crate)

	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, glow_height, 0.0)
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	add_child(_light)

	_area = Area3D.new()
	# Layer 2 is the player. Zombies must not trip a cache, and world geometry
	# must not either.
	_area.collision_layer = 0
	_area.collision_mask = 2
	add_child(_area)

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.6
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position = Vector3(0.0, 1.5, 0.0)
	_area.add_child(shape)

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_inside = true


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_inside = false
