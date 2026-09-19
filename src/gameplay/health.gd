class_name Health
extends Node

## Reusable health pool. Used by both the player and zombies so damage,
## death, and reset behave identically on both sides of the fight.
##
## Owners react through signals rather than polling, which keeps UI out of
## gameplay code — the HUD listens to `changed`, it is never referenced here.

signal changed(current: float, maximum: float)
signal damaged(amount: float, current: float, maximum: float)
signal died()

@export var max_health := 100.0
## Ignore further hits for this long after taking damage. Zero disables it.
@export var invulnerability_duration := 0.0

var current_health: float
var is_dead := false

var _invulnerable_remaining := 0.0


func _ready() -> void:
	current_health = max_health


func _process(delta: float) -> void:
	if _invulnerable_remaining > 0.0:
		_invulnerable_remaining = maxf(0.0, _invulnerable_remaining - delta)


## Apply damage. Returns the amount actually absorbed, which is zero when the
## owner is already dead or still inside their invulnerability window.
func take_damage(amount: float) -> float:
	if is_dead or amount <= 0.0 or _invulnerable_remaining > 0.0:
		return 0.0

	var before := current_health
	current_health = maxf(0.0, current_health - amount)
	var applied := before - current_health

	_invulnerable_remaining = invulnerability_duration

	damaged.emit(applied, current_health, max_health)
	changed.emit(current_health, max_health)

	if current_health <= 0.0:
		is_dead = true
		died.emit()

	return applied


func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0

	var before := current_health
	current_health = minf(max_health, current_health + amount)
	var applied := current_health - before

	if applied > 0.0:
		changed.emit(current_health, max_health)
	return applied


func get_fraction() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health


func is_invulnerable() -> bool:
	return _invulnerable_remaining > 0.0


## Restore to full for a fresh round.
func reset() -> void:
	is_dead = false
	current_health = max_health
	_invulnerable_remaining = 0.0
	changed.emit(current_health, max_health)
