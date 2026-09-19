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
@onready var sounds: SoundBank = $SoundBank
@onready var pause_menu: PauseMenu = $PauseMenu

## Null when autoloads are unavailable (headless --script runs); the exported
## defaults above stand in for the difficulty profile in that case.
var _settings: GameSettings


func _ready() -> void:
	spawner.zombie_died.connect(_on_zombie_died)
	player.died.connect(_on_player_died)
	pause_menu.resumed.connect(_on_resumed)
	_settings = GameSettings.instance(self)

	_wire_audio()
	hud.bind(self, player, weapon, spawner)
	start_round()


## Route gameplay signals to sound events. Audio lives here rather than inside
## the systems, so none of them hold a reference to a player or a stream.
func _wire_audio() -> void:
	weapon.fired.connect(func(_from: Vector3, _to: Vector3) -> void:
		sounds.play("fire")
	)
	weapon.dry_fired.connect(func() -> void: sounds.play("dry_fire"))
	weapon.reload_started.connect(func(_duration: float) -> void:
		sounds.play("reload_start")
	)
	weapon.reload_finished.connect(func() -> void: sounds.play("reload_end"))
	weapon.target_hit.connect(func(target: Node, _damage: float) -> void:
		if target is Node3D:
			sounds.play_at("zombie_hit", target.global_position)
	)

	player.damage_taken.connect(func(_amount: float, _angle: float) -> void:
		sounds.play("player_hurt")
	)
	player.footstep_taken.connect(func() -> void: sounds.play("footstep"))

	spawner.zombie_groaned.connect(func(groan_position: Vector3) -> void:
		sounds.play_at("zombie_groan", groan_position)
	)

	round_won.connect(func(_kills: int, _time: float) -> void: sounds.play("round_won"))
	round_lost.connect(func(_kills: int, _time: float) -> void: sounds.play("round_lost"))


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()
		return

	if pause_menu.is_open():
		return

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
	_apply_difficulty()

	state = RoundState.PLAYING
	kills = 0
	time_remaining = extraction_duration

	if _settings != null:
		_settings.apply_to_player(player)
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


## Pull the chosen difficulty's numbers in before anything is reset, so a change
## made in the pause menu takes effect on the very next round.
func _apply_difficulty() -> void:
	if _settings == null:
		return

	var profile: Dictionary = _settings.get_profile()

	extraction_duration = profile.extraction_duration
	weapon.starting_reserve = profile.starting_reserve
	spawner.interval_scale = profile.spawn_interval_scale
	spawner.damage_scale = profile.damage_scale


func _toggle_pause() -> void:
	if pause_menu.is_open():
		pause_menu.close()
	else:
		pause_menu.open()
		weapon.set_input_enabled(false)
		player.set_look_enabled(false)


func _on_resumed() -> void:
	# The round may have ended while paused; do not hand control back if so.
	if state != RoundState.PLAYING:
		return

	weapon.set_input_enabled(true)
	player.set_look_enabled(true)


func _on_zombie_died(death_position: Vector3) -> void:
	if state != RoundState.PLAYING:
		return

	kills += 1
	kills_changed.emit(kills)
	sounds.play_at("zombie_death", death_position)
	sounds.play("ammo_gained")

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
