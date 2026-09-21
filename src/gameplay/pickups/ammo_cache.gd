class_name AmmoCache
extends Interactable

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
## Seconds of holding the interact key to empty a crate.
##
## Shorter than a medkit's: ammunition is what the game is about, and making
## the player pay two seconds for the resource they came for would turn every
## resupply into a chore rather than a gamble. Long enough that arriving with
## something already chasing you is a problem.
@export var resupply_hold_seconds := 1.2

const CRATE_MODEL := "res://assets/models/weapons/crate-medium.glb"
const CHARGED_COLOUR := Color(1.0, 0.76, 0.32)
const EMPTY_COLOUR := Color(0.32, 0.38, 0.5)

var _stock := 0
var _recharge_remaining := 0.0
var _player_inside := false
## Asked how many rounds the player can accept. Set by Game, which is the only
## thing that knows both the crate and the weapon.
var capacity_handler := Callable()

var _light: OmniLight3D
var _area: Area3D


func _ready() -> void:
	super()
	_stock = capacity
	interaction_hold_seconds = resupply_hold_seconds
	# Reached from further than a medkit on the floor, because the crate is
	# solid and the player is stopped by it before they are standing on it.
	interaction_reach_metres = 3.2
	interaction_focus_height = glow_height
	_build()
	_refresh_glow()


func _process(delta: float) -> void:
	if _stock < capacity:
		_recharge_remaining -= delta
		if _recharge_remaining <= 0.0:
			_stock = capacity
			_refresh_glow()


## Whether the player is standing in the trigger volume.
##
## The trigger no longer collects anything — that is the interaction system's
## job now, and a crate that emptied itself the moment you brushed past it was
## the reason the game had two different rules for using things. It is kept
## because "is the player at this cache" is still worth knowing cheaply, and
## because the recharge readout wants it.
func has_player_inside() -> bool:
	return _player_inside


## --- Interaction contract ---------------------------------------------------
##
## See src/gameplay/interaction/interactable.gd. Resupply is a hold rather than
## a press for the same reason it used to be a walk-over and should not have
## been: a cache is the place you least want to be standing still, and that
## tension is the whole reason caches were put out in the map.


func can_interact(_player: Node) -> bool:
	return has_stock() and room_to_take() > 0


func interaction_prompt(_player: Node) -> String:
	return "Resupply"


## How many rounds the player could actually accept right now.
##
## The crate still does not know what a magazine is — it asks how much will be
## taken and is told a number, which is the only thing it needs in order not to
## give away more than that.
##
## Without this a player at full reserve emptied a crate for nothing: the drain
## and the 55 second recharge ran unconditionally, and every piece of feedback
## — the resupply sound, the pickup chime, the world noise — was gated behind
## "did the reserve actually go up", so the crate went cold and silent and the
## player was given no way to tell that from a successful loot.
func room_to_take() -> int:
	if not capacity_handler.is_valid():
		return _stock

	return maxi(0, int(capacity_handler.call()))


func interact(player: Node) -> bool:
	if not has_stock():
		return false

	_collect()
	interacted.emit(player)
	return true


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
	# reset_to_spawn teleports the player rather than moving them, so body_exited
	# never fires for a cache they were standing in when the round ended. Left
	# set, this cache believes the player is inside it for the whole next round.
	_player_inside = false
	_refresh_glow()


## Hand over only what the player can carry, and keep the rest.
##
## A crate that empties itself into a full reserve is a resource destroyed by
## walking into it, which punishes the player for the one thing the caches
## exist to encourage.
func _collect() -> void:
	var taken: int = mini(_stock, room_to_take())
	if taken <= 0:
		return

	_stock -= taken
	if _stock <= 0:
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
