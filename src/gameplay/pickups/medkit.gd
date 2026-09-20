class_name Medkit
extends Interactable

## A one-use field dressing lying in the cave.
##
## Health only ever went down before this existed, which made a long round a
## slow slide with no plays left in it. The medkit gives the player something
## to spend a risk on.
##
## It is deliberately a HOLD, not a touch pickup. This game is about noise and
## position: zombies hunt by sound and sight, and the moments that matter are
## the ones where you decide whether you can afford to stop. A medkit you walk
## over heals you for free while you run away, and the only question it asks is
## whether you noticed it. A medkit that costs two seconds of standing still
## asks the question the game is actually about — is this corridor clear
## enough, right now, to stop moving in it. Releasing early costs nothing but
## the time, so the answer can be revised halfway through.
##
## Refused at full health rather than wasted. A consumable the player can
## delete by mistake teaches them to avoid it.

## Emitted when it is actually used, with the health restored. Game wires the
## sound and the noise; the kit itself knows nothing about either.
signal used(healed: float)

## The kit reads as a supply item at a glance because it is the same crate
## silhouette as a cache, in a different colour. Recognising "supplies" from
## across a chamber matters more here than the two objects being distinct
## shapes, and the light tells them apart: caches glow amber, kits green.
@export var model_path := "res://assets/models/weapons/crate-small.glb"
## Health restored, out of the player's 100. Under half a bar on purpose: a kit
## should change how long you can last, not undo the fight you just had.
@export var heal_amount := 40.0
## Seconds of standing still it costs. Long enough to be a decision, short
## enough to take in a doorway you have just checked.
@export var hold_seconds := 2.0
## Green, and dimmer than a cache's amber. A kit is a smaller promise.
@export var glow_colour := Color(0.36, 1.0, 0.52)
@export var glow_height := 0.9
@export var glow_range := 5.0
@export var glow_energy := 1.8

var _consumed := false

var _light: OmniLight3D


func _ready() -> void:
	super()
	interaction_hold_seconds = hold_seconds
	_build()


## Spawn a kit under `parent` at a world position.
##
## A static factory rather than a scene path the level has to know: placement
## is then one line wherever the layout eventually lives, and nothing outside
## this file has to learn how a kit is assembled.
static func spawn(parent: Node, at: Vector3) -> Medkit:
	var kit := Medkit.new()
	parent.add_child(kit)
	kit.global_position = at
	return kit


## Already taken.
func is_consumed() -> bool:
	return _consumed


func can_interact(player: Node) -> bool:
	if _consumed:
		return false

	var pool := _health_of(player)
	# Refused at full. See the class comment: a wasted consumable is a lesson
	# in never picking one up.
	return pool != null and not pool.is_dead and pool.get_fraction() < 1.0


func interaction_prompt(_player: Node) -> String:
	return "Bandage"


func interact(player: Node) -> bool:
	if not can_interact(player):
		return false

	var pool := _health_of(player)
	var healed := pool.heal(heal_amount)
	if healed <= 0.0:
		return false

	_consumed = true
	remove_from_group(Interactable.GROUP)
	used.emit(healed)
	interacted.emit(player)
	_dissolve()
	return true


## The player's Health component, however it is exposed. Read through a
## property rather than a hard node path, so this works on anything carrying a
## health pool — a future ally NPC would be healed by exactly this code.
func _health_of(player: Node) -> Health:
	if player == null or not is_instance_valid(player):
		return null
	if not ("health" in player):
		return null
	return player.health as Health


func _dissolve() -> void:
	if _light != null and is_instance_valid(_light):
		_light.visible = false
	visible = false
	# Freed at the end of the frame rather than immediately, because interact()
	# is called from inside the interactor's own tick, which still holds a
	# reference to this node when it returns.
	queue_free()


func _build() -> void:
	if ResourceLoader.exists(model_path):
		var scene: PackedScene = load(model_path)
		if scene != null:
			var model: Node3D = scene.instantiate()
			add_child(model)
			_tint(model)
			# Solid, like the caches. A supply item you can walk through reads
			# as a hologram, and the player needs to be stopped by it to know
			# they have arrived.
			MeshCollision.fit(model)

	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, glow_height, 0.0)
	_light.light_color = glow_colour
	_light.light_energy = glow_energy
	_light.omni_range = glow_range
	_light.shadow_enabled = false
	add_child(_light)


## Tinted in code rather than authored into the model, so the kit and the cache
## can share one crate mesh and still be told apart at distance.
func _tint(node: Node) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = glow_colour.lerp(Color(0.9, 0.95, 0.95), 0.45)
		material.emission_enabled = true
		material.emission = glow_colour
		material.emission_energy_multiplier = 0.35
		(node as MeshInstance3D).material_override = material

	for child in node.get_children():
		_tint(child)
