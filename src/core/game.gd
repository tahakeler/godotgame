class_name Game
extends Node3D

## Round root and game loop. Owns the extraction timer, win/loss resolution,
## and restart.
##
## The loop's central inversion: kills subtract from the extraction clock, so
## killing is how you leave sooner. Combined with ammunition that only comes
## from kills, neither hiding nor spraying is a viable strategy.

signal round_started()
signal round_won(kills: int, time_taken: float, is_record: bool)
signal round_lost(kills: int, time_survived: float, is_record: bool)
signal time_changed(remaining: float, total: float)
signal kills_changed(kills: int)

enum RoundState { PLAYING, WON, LOST }

const MAIN_MENU_SCENE := "res://src/ui/main_menu.tscn"

## How far each action carries, as a fraction of a gunshot. Footsteps are
## quiet but constant, which is what makes moving fast a real tell.
const RELOAD_LOUDNESS := 0.3
const FOOTSTEP_LOUDNESS := 0.22
const CACHE_LOUDNESS := 0.45

## How often danger is recomputed. Ten times a second is far finer than the
## mix it drives can respond to.
const THREAT_SAMPLE_INTERVAL := 0.1

@export_group("Extraction")
## Baseline round length before any kills are counted.
@export var extraction_duration := 120.0
## Seconds removed from the clock per kill.
@export var seconds_per_kill := 2.0

@export_group("Rewards")
## Added on top of whatever the kind itself is worth.
@export var ammo_bonus_per_kill := 0

@export_group("Feel")
@export var fire_trauma := 0.22
@export var hurt_trauma := 0.55

var state: RoundState = RoundState.PLAYING
var mode: GameSettings.Mode = GameSettings.Mode.EXTRACTION
var round_duration := 120.0
var time_remaining := 0.0
var elapsed_time := 0.0
var kills := 0
## Shots that left the barrel, and shots that reached a zombie. Reset with the
## round, so accuracy on the results screen is for that run only.
var shots_fired := 0
var shots_hit := 0
var _threat_remaining := 0.0
var _threat_elapsed := 0.0

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var spawner: ZombieSpawner = $ZombieSpawner
@onready var weapon: Weapon = $Player/Head/Camera/Weapon
@onready var hud: HUD = $HUD
@onready var sounds: SoundBank = $SoundBank
@onready var ambience: Ambience = $Ambience
@onready var effects: EffectSpawner = $EffectSpawner
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var progression: Progression = $Progression
@onready var upgrade_menu: UpgradeMenu = $UpgradeMenu

## Null when autoloads are unavailable (headless --script runs); the exported
## defaults above stand in for the difficulty profile in that case.
var _settings: GameSettings
## Player and weapon values as they were before any upgrade touched them.
var _baselines: Dictionary = {}


func _ready() -> void:
	spawner.zombie_died.connect(_on_zombie_died)
	player.died.connect(_on_player_died)
	pause_menu.resumed.connect(_on_resumed)
	progression.levelled_up.connect(_on_levelled_up)
	upgrade_menu.chosen.connect(_apply_upgrade)
	_settings = GameSettings.instance(self)

	# Look preferences are otherwise only read when a round starts, so a player
	# adjusting sensitivity from the pause menu would change nothing until they
	# restarted — and the whole reason to open that slider mid-round is that the
	# current setting feels wrong right now.
	if _settings != null:
		_settings.changed.connect(func() -> void: _settings.apply_to_player(player))

	_capture_baselines()
	_wire_audio()
	_wire_statistics()
	_wire_noise()
	_wire_caches()
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
	weapon.scrounged.connect(func(_amount: int) -> void: sounds.play("ammo_gained"))
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

	# The one sound that means something changed about you rather than about
	# them. Played where the zombie is, so it carries a direction.
	spawner.zombie_noticed_player.connect(
		func(at: Vector3, _kind: ZombieTypes.Kind) -> void:
			sounds.play_at("zombie_alerted", at)
	)

	# A Brute announces itself with something lower than the crowd, so it can be
	# heard coming before the corridor gives it away.
	spawner.zombie_groaned.connect(
		func(groan_position: Vector3, kind: ZombieTypes.Kind) -> void:
			var event := (
				"brute_growl" if kind == ZombieTypes.Kind.BRUTE else "zombie_groan"
			)
			sounds.play_at(event, groan_position)
	)

	round_won.connect(
		func(_kills: int, _time: float, _record: bool) -> void: sounds.play("round_won")
	)
	round_lost.connect(
		func(_kills: int, _time: float, _record: bool) -> void: sounds.play("round_lost")
	)


## Caches hand their rounds to the weapon through Game, for the same reason
## audio and effects route through here: a crate in the arena should not know
## what a magazine is.
func _wire_caches() -> void:
	for cache in arena.ammo_caches:
		cache.collected.connect(func(rounds: int) -> void:
			var added := weapon.add_reserve_ammo(rounds)
			if added > 0:
				sounds.play("ammo_gained")
				# Rummaging through a crate is not silent, and a cache is
				# exactly the place you least want a crowd arriving at.
				_make_noise(cache.global_position, CACHE_LOUDNESS)
		)


## A gunshot is heard by anything nearby, and what it draws is a crowd to the
## place the shot came from — not to the player.
##
## This is what makes the game's first pillar literally true. Ammunition
## scarcity alone means a bullet costs a bullet; with noise it also costs your
## position, and moving after shooting becomes a real play rather than a habit.
## The noise is emitted from the muzzle rather than from the player so that a
## shot fired from cover gives away the cover, which is the intended lesson.
func _wire_noise() -> void:
	weapon.fired.connect(func(from: Vector3, _to: Vector3) -> void:
		_make_noise(from, weapon.noise_loudness)
	)

	# A vocabulary rather than one event. Once quiet actions exist, how you
	# move becomes a choice: crossing a chamber at a walk and emptying a
	# magazine in it are different amounts of information given away, and the
	# player can spend that deliberately.
	weapon.reload_started.connect(func(_duration: float) -> void:
		_make_noise(player.global_position, RELOAD_LOUDNESS)
	)
	player.footstep_taken.connect(func() -> void:
		_make_noise(player.global_position, FOOTSTEP_LOUDNESS)
	)

	# The throw is silent; only the landing speaks. That is the whole reason a
	# decoy is worth a round — it moves the horde without moving you, and
	# without telling them where you threw it from.
	weapon.decoy_thrown.connect(func(decoy: Decoy) -> void:
		decoy.landed.connect(func(at: Vector3, loudness: float) -> void:
			sounds.play_at("decoy_land", at)
			_make_noise(at, loudness)
		)
	)


## Danger drives the audio mix and the weight of the frame.
##
## Sampled several times a second rather than every frame. The figure walks
## every living zombie, and the mix it feeds is smoothed over more than a
## second anyway — so a tenth of a second of staleness is not something anyone
## can hear, while the per-frame walk is cost paid for nothing.
##
## The accumulated time is handed to the smoothing rather than the frame delta,
## so the ramp runs at the same rate regardless of how often this is sampled.
func _tick_threat(delta: float) -> void:
	_threat_remaining -= delta
	_threat_elapsed += delta

	if _threat_remaining > 0.0:
		return

	ambience.set_threat(
		spawner.threat_level(player.global_position), _threat_elapsed
	)
	hud.set_threat(ambience.threat())

	_threat_remaining = THREAT_SAMPLE_INTERVAL
	_threat_elapsed = 0.0


## Emit a sound into the world and tell the HUD what it cost.
func _make_noise(at: Vector3, loudness: float) -> void:
	if loudness <= 0.0:
		return

	var heard := spawner.broadcast_noise(at, loudness)
	hud.report_noise(loudness, heard, at)


## Count what the results screen reports.
##
## Kept on the round rather than on the weapon, because accuracy describes a
## run and the weapon outlives runs. A shot that leaves the barrel is one
## attempt and a shot that reaches a zombie is one hit, so missing costs the
## bullet and the percentage but nothing more.
func _wire_statistics() -> void:
	weapon.fired.connect(func(_from: Vector3, _to: Vector3) -> void:
		shots_fired += 1
	)
	weapon.target_hit.connect(func(_target: Node, _damage: float) -> void:
		shots_hit += 1
	)


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
	spawner.zombie_died.connect(
		func(death_position: Vector3, _experience: int, _ammo: int) -> void:
			effects.spawn_death(death_position)
	)
	player.look_moved.connect(weapon.report_look)


## Opening the pause menu is taken as an input event rather than polled in
## _process, because this node stops processing the instant the tree pauses.
## Polling meant the control that opened the menu could not close it again —
## the only way out was clicking Resume, with a mouse. Closing is handled by
## PauseMenu itself, which is the node still awake at that point.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return

	if state == RoundState.PLAYING:
		_toggle_pause()
	else:
		# There is nothing to pause once the round is over, so the same control
		# leaves for the menu — which is what the results screen offers.
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)

	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if pause_menu.is_open() or upgrade_menu.is_open():
		return

	if Input.is_action_just_pressed("restart"):
		start_round()
		return

	_tick_threat(delta)

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

	_restore_baselines()
	upgrade_menu.close()

	state = RoundState.PLAYING
	kills = 0
	shots_fired = 0
	shots_hit = 0
	elapsed_time = 0.0
	time_remaining = round_duration

	if _settings != null:
		_settings.apply_to_player(player)
	player.reset_to_spawn()
	player.set_look_enabled(true)
	weapon.reset_state()
	weapon.set_input_enabled(true)

	progression.reset()

	# A new round must not begin with the caches the last one drained.
	for cache in arena.ammo_caches:
		cache.reset()

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


## Upgrades mutate the player and weapon directly, so a restart has to put those
## values back. Without this the next round silently inherits every upgrade from
## the last, and the difficulty curve quietly stops meaning anything.
func _capture_baselines() -> void:
	_baselines = {
		"magazine_size": weapon.magazine_size,
		"damage": weapon.damage,
		"reload_duration": weapon.reload_duration,
		"max_reserve": weapon.max_reserve,
		"move_speed": player.move_speed,
		"max_health": player.health.max_health,
		"ammo_bonus_per_kill": ammo_bonus_per_kill,
		"noise_loudness": weapon.noise_loudness,
		"decoy_loudness": weapon.decoy_loudness,
	}


func _restore_baselines() -> void:
	if _baselines.is_empty():
		return

	weapon.magazine_size = _baselines.magazine_size
	weapon.damage = _baselines.damage
	weapon.reload_duration = _baselines.reload_duration
	weapon.max_reserve = _baselines.max_reserve
	player.move_speed = _baselines.move_speed
	player.health.max_health = _baselines.max_health
	ammo_bonus_per_kill = _baselines.ammo_bonus_per_kill
	weapon.noise_loudness = _baselines.noise_loudness
	weapon.decoy_loudness = _baselines.decoy_loudness


## Apply a chosen upgrade. Progression decides what was offered and picked;
## the effects live here, because only Game knows about the player and weapon.
func _apply_upgrade(upgrade_id: int) -> void:
	match upgrade_id:
		Progression.Upgrade.MAGAZINE:
			weapon.magazine_size += 3
			weapon.magazine_ammo += 3
			weapon.ammo_changed.emit(weapon.magazine_ammo, weapon.reserve_ammo)
		Progression.Upgrade.VITALITY:
			player.health.max_health += 25.0
			player.health.heal(25.0)
		Progression.Upgrade.HOLLOW_POINTS:
			weapon.damage += 8.0
		Progression.Upgrade.FAST_HANDS:
			weapon.reload_duration *= 0.8
		Progression.Upgrade.ADRENALINE:
			player.move_speed *= 1.12
		Progression.Upgrade.SCAVENGER:
			ammo_bonus_per_kill += 2
		Progression.Upgrade.BANDOLIER:
			weapon.max_reserve += 15
			weapon.add_reserve_ammo(15)
		Progression.Upgrade.SUBSONIC:
			# Buys back some of what firing costs you in position, which is
			# the only upgrade here that trades against the noise system
			# rather than against a number on the weapon.
			weapon.noise_loudness = maxf(0.25, weapon.noise_loudness - 0.35)
		Progression.Upgrade.BAIT:
			# Deepens the verb without removing its price. A decoy that cost
			# nothing would stop being a trade, and the trade is the mechanic.
			weapon.decoy_loudness = minf(2.0, weapon.decoy_loudness + 0.4)

	# Handing control back is the same job as leaving the pause menu.
	_on_resumed()


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


func _on_zombie_died(death_position: Vector3, experience: int, ammo: int) -> void:
	if state != RoundState.PLAYING:
		return

	kills += 1
	kills_changed.emit(kills)
	progression.add_kill_experience(experience)
	sounds.play_at("zombie_death", death_position)
	sounds.play("ammo_gained")

	# Kills are the only source of ammunition, and the only way to shorten the
	# round. Both rewards come from the same action by design.
	weapon.add_reserve_ammo(ammo + ammo_bonus_per_kill)

	# Only Extraction trades kills for clock. In Last Stand the timer is the
	# whole challenge, and in Endless there is no clock to shorten.
	if mode != GameSettings.Mode.EXTRACTION:
		return

	time_remaining = maxf(0.0, time_remaining - seconds_per_kill)
	time_changed.emit(time_remaining, round_duration)

	if time_remaining <= 0.0:
		_end_round(RoundState.WON)


## A level-up interrupts the round, so control is taken the same way the pause
## menu takes it.
func _on_levelled_up(level: int, choices: Array[Dictionary]) -> void:
	if state != RoundState.PLAYING:
		return

	weapon.set_input_enabled(false)
	player.set_look_enabled(false)
	upgrade_menu.open(level, choices)


func _on_player_died() -> void:
	if state == RoundState.PLAYING:
		_end_round(RoundState.LOST)


func _end_round(result: RoundState) -> void:
	state = result

	spawner.stop()
	weapon.set_input_enabled(false)
	player.set_look_enabled(false)

	var difficulty: GameSettings.Difficulty = (
		_settings.difficulty if _settings != null else GameSettings.Difficulty.SOLDIER
	)
	var is_record := Records.submit(
		mode, difficulty, kills, elapsed_time, result == RoundState.WON
	)

	if result == RoundState.WON:
		round_won.emit(kills, elapsed_time, is_record)
	else:
		round_lost.emit(kills, elapsed_time, is_record)
