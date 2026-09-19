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

@export_group("Feel")
@export var fire_trauma := 0.22
@export var hurt_trauma := 0.55

var state: RoundState = RoundState.PLAYING
var mode: GameSettings.Mode = GameSettings.Mode.EXTRACTION
var round_duration := 120.0
var time_remaining := 0.0
var elapsed_time := 0.0
var kills := 0

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var spawner: ZombieSpawner = $ZombieSpawner
@onready var weapon: Weapon = $Player/Head/Camera/Weapon
@onready var hud: HUD = $HUD
@onready var sounds: SoundBank = $SoundBank
@onready var effects: EffectSpawner = $EffectSpawner
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
	_wire_effects()
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


## Route gameplay signals to visual effects and camera feel, for the same reason
## audio is routed here: the weapon should not know what a hit looks like, only
## that it hit.
func _wire_effects() -> void:
	weapon.fired.connect(func(_from: Vector3, _to: Vector3) -> void:
		player.add_trauma(fire_trauma)
	)
	weapon.impacted.connect(func(position: Vector3, normal: Vector3, is_flesh: bool) -> void:
		effects.spawn_impact(position, normal, is_flesh)
	)
	weapon.target_hit.connect(func(_target: Node, _damage: float) -> void:
		hud.flash_hitmarker()
	)
	player.damage_taken.connect(func(_amount: float, _angle: float) -> void:
		player.add_trauma(hurt_trauma)
	)
	spawner.zombie_died.connect(func(death_position: Vector3) -> void:
		effects.spawn_death(death_position)
	)
	player.look_moved.connect(weapon.report_look)


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

	# Endless has no clock to run out, so its timer counts up as a score rather
	# than down as a deadline. Everything else is a countdown to a win.
	if mode == GameSettings.Mode.ENDLESS:
		elapsed_time += delta
		time_changed.emit(elapsed_time, 0.0)
		return

	time_remaining = maxf(0.0, time_remaining - delta)
	elapsed_time += delta
	time_changed.emit(time_remaining, round_duration)

	if time_remaining <= 0.0:
		_end_round(RoundState.WON)


## Restore every system to its opening state and begin a fresh round. This is
## the restart control — nothing is reloaded, so there is no scene transition
## and no chance of a stale node surviving into the new round.
func start_round() -> void:
	_apply_difficulty()

	_apply_mode()

	state = RoundState.PLAYING
	kills = 0
	elapsed_time = 0.0
	time_remaining = round_duration

	if _settings != null:
		_settings.apply_to_player(player)
	player.reset_to_spawn()
	player.set_look_enabled(true)
	weapon.reset_state()
	weapon.set_input_enabled(true)

	spawner.reset()
	spawner.begin(arena, player)

	kills_changed.emit(kills)
	time_changed.emit(
		elapsed_time if mode == GameSettings.Mode.ENDLESS else time_remaining,
		0.0 if mode == GameSettings.Mode.ENDLESS else round_duration
	)
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


## Configure the round for the chosen mode. Difficulty has already set the
## Extraction duration, so only the other two override it.
func _apply_mode() -> void:
	mode = _settings.mode if _settings != null else GameSettings.Mode.EXTRACTION
	round_duration = extraction_duration

	match mode:
		GameSettings.Mode.TIMED:
			round_duration = GameSettings.MODE_DURATIONS[GameSettings.Mode.TIMED]
		GameSettings.Mode.ENDLESS:
			round_duration = 0.0

	# Endless keeps escalating rather than settling at its floor, so the run
	# always ends eventually — a survival mode you cannot lose is a screensaver.
	spawner.endless = mode == GameSettings.Mode.ENDLESS


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

	# Only Extraction trades kills for clock. In Last Stand the timer is the
	# whole challenge, and in Endless there is no clock to shorten.
	if mode != GameSettings.Mode.EXTRACTION:
		return

	time_remaining = maxf(0.0, time_remaining - seconds_per_kill)
	time_changed.emit(time_remaining, round_duration)

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

	if result == RoundState.WON:
		round_won.emit(kills, elapsed_time)
	else:
		round_lost.emit(kills, elapsed_time)
