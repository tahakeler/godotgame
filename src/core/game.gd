class_name Game
extends Node3D

## Round root and game loop. Owns the extraction timer, win/loss resolution,
## and restart.
##
## The loop's central inversion: kills subtract from the extraction clock, so
## killing is how you leave sooner. Combined with ammunition that only comes
## from kills, neither hiding nor spraying is a viable strategy.

signal round_started()
signal round_won(kills: int, time_taken: float)
signal round_lost(kills: int, time_survived: float)
signal time_changed(remaining: float, total: float)
signal kills_changed(kills: int)

enum RoundState { PLAYING, WON, LOST }

@export_group("Extraction")
## Baseline round length before any kills are counted.
@export var extraction_duration := 120.0
## Seconds removed from the clock per kill.
@export var seconds_per_kill := 2.0

@export_group("Rewards")
@export var ammo_per_kill := 3

var state: RoundState = RoundState.PLAYING
var time_remaining := 0.0
var kills := 0

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var spawner: ZombieSpawner = $ZombieSpawner
@onready var weapon: Weapon = $Player/Head/Camera/Weapon
@onready var hud: HUD = $HUD


func _ready() -> void:
	spawner.zombie_died.connect(_on_zombie_died)
	player.died.connect(_on_player_died)

	hud.bind(self, player, weapon, spawner)
	start_round()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		start_round()
		return

	if state != RoundState.PLAYING:
		return

	time_remaining = maxf(0.0, time_remaining - delta)
	time_changed.emit(time_remaining, extraction_duration)

	if time_remaining <= 0.0:
		_end_round(RoundState.WON)


## Restore every system to its opening state and begin a fresh round. This is
## the restart control — nothing is reloaded, so there is no scene transition
## and no chance of a stale node surviving into the new round.
func start_round() -> void:
	state = RoundState.PLAYING
	kills = 0
	time_remaining = extraction_duration

	player.reset_to_spawn()
	player.set_look_enabled(true)
	weapon.reset_state()
	weapon.set_input_enabled(true)

	spawner.reset()
	spawner.begin(arena, player)

	kills_changed.emit(kills)
	time_changed.emit(time_remaining, extraction_duration)
	round_started.emit()


func is_round_over() -> bool:
	return state != RoundState.PLAYING


func _on_zombie_died(_death_position: Vector3) -> void:
	if state != RoundState.PLAYING:
		return

	kills += 1
	kills_changed.emit(kills)

	# Kills are the only source of ammunition, and the only way to shorten the
	# round. Both rewards come from the same action by design.
	weapon.add_reserve_ammo(ammo_per_kill)
	time_remaining = maxf(0.0, time_remaining - seconds_per_kill)
	time_changed.emit(time_remaining, extraction_duration)

	if time_remaining <= 0.0:
		_end_round(RoundState.WON)


func _on_player_died() -> void:
	if state == RoundState.PLAYING:
		_end_round(RoundState.LOST)


func _end_round(result: RoundState) -> void:
	state = result

	spawner.stop()
	weapon.set_input_enabled(false)
	player.set_look_enabled(false)

	var elapsed := extraction_duration - time_remaining

	if result == RoundState.WON:
		round_won.emit(kills, elapsed)
	else:
		round_lost.emit(kills, elapsed)
