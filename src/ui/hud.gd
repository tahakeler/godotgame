class_name HUD
extends CanvasLayer

## Round interface: extraction clock, health, ammunition, kills, and the
## end-of-round overlay.
##
## The HUD only listens. Gameplay code never reaches into it — every value
## arrives through a signal, so the systems below can be tested without a
## viewport.

const LOW_HEALTH_FRACTION := 0.35
const LOW_AMMO_ROUNDS := 2

@export var damage_marker_lifetime := 1.1
@export var hitmarker_duration := 0.22

var _game: Game
var _player: Player
var _weapon: Weapon

@onready var _extraction_label: Label = %ExtractionLabel
@onready var _kills_label: Label = %KillsLabel
@onready var _zombies_label: Label = %ZombiesLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _magazine_label: Label = %MagazineLabel
@onready var _reserve_label: Label = %ReserveLabel
@onready var _weapon_status_label: Label = %WeaponStatusLabel
@onready var _damage_indicator: Control = %DamageIndicator
@onready var _damage_flash: ColorRect = %DamageFlash
@onready var _overlay: Control = %Overlay
@onready var _overlay_title: Label = %OverlayTitle
@onready var _overlay_detail: Label = %OverlayDetail
@onready var _record_label: Label = %RecordLabel
@onready var _hitmarker: Control = %Hitmarker
@onready var _level_label: Label = %LevelLabel
@onready var _experience_bar: ProgressBar = %ExperienceBar
@onready var _hurt_vignette: TextureRect = %HurtVignette

var _damage_markers: Array[Dictionary] = []
var _flash_remaining := 0.0
var _hitmarker_remaining := 0.0
var _hurt_pulse := 0.0


func _ready() -> void:
	_overlay.visible = false
	_record_label.visible = false
	_hitmarker.modulate.a = 0.0
	_damage_flash.color.a = 0.0
	_damage_indicator.draw.connect(_draw_damage_markers)


func _process(delta: float) -> void:
	_tick_damage_markers(delta)
	_tick_flash(delta)
	_tick_hitmarker(delta)
	_tick_hurt_vignette(delta)


## Connect to a round. Called by Game once every system exists.
func bind(game: Game, player: Player, weapon: Weapon, spawner: ZombieSpawner) -> void:
	_game = game
	_player = player
	_weapon = weapon

	game.time_changed.connect(_on_time_changed)
	game.kills_changed.connect(_on_kills_changed)
	game.round_won.connect(_on_round_won)
	game.round_lost.connect(_on_round_lost)
	game.round_started.connect(_on_round_started)
	game.progression.experience_changed.connect(_on_experience_changed)

	player.health.changed.connect(_on_health_changed)
	player.damage_taken.connect(_on_damage_taken)

	weapon.ammo_changed.connect(_on_ammo_changed)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_weapon_status_cleared)
	weapon.dry_fired.connect(_on_dry_fired)

	spawner.population_changed.connect(_on_population_changed)

	_on_health_changed(player.health.current_health, player.health.max_health)
	_on_ammo_changed(weapon.magazine_ammo, weapon.reserve_ammo)


func _on_round_started() -> void:
	_overlay.visible = false
	_damage_markers.clear()
	_flash_remaining = 0.0
	_damage_flash.color.a = 0.0
	_weapon_status_label.text = ""
	_damage_indicator.queue_redraw()


## Endless has no deadline, so its clock counts up and never turns amber —
## there is nothing imminent to warn about.
func _on_time_changed(value: float, total: float) -> void:
	var counts_up := is_zero_approx(total)
	_extraction_label.text = "%s  %s" % [
		_timer_caption(), _format_duration(value)
	]

	if counts_up:
		_extraction_label.modulate = Color(0.85, 0.9, 1.0)
		return

	# Turns amber inside the last 15 seconds so the finish is visibly imminent.
	_extraction_label.modulate = (
		Color(1.0, 0.78, 0.3) if value <= 15.0 else Color(0.85, 0.9, 1.0)
	)


func _timer_caption() -> String:
	if _game == null:
		return "EXTRACTION"

	match _game.mode:
		GameSettings.Mode.TIMED:
			return "HOLD OUT"
		GameSettings.Mode.ENDLESS:
			return "SURVIVED"
		_:
			return "EXTRACTION"


func _on_experience_changed(current: int, needed: int, level: int) -> void:
	_level_label.text = "LV %d" % level
	_experience_bar.max_value = maxf(float(needed), 1.0)
	_experience_bar.value = current


func _on_kills_changed(kills: int) -> void:
	_kills_label.text = "KILLS  %d" % kills


func _on_population_changed(alive: int) -> void:
	_zombies_label.text = "HOSTILES  %d" % alive


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "%d" % roundi(current)

	var fraction := current / maxf(maximum, 1.0)
	var bar_color := (
		Color(0.85, 0.24, 0.2) if fraction <= LOW_HEALTH_FRACTION
		else Color(0.42, 0.72, 0.45)
	)
	_health_bar.modulate = bar_color


func _on_ammo_changed(magazine: int, reserve: int) -> void:
	_magazine_label.text = str(magazine)
	_reserve_label.text = "/ %d" % reserve

	if magazine == 0:
		_magazine_label.modulate = Color(0.9, 0.25, 0.2)
	elif magazine <= LOW_AMMO_ROUNDS:
		_magazine_label.modulate = Color(1.0, 0.72, 0.25)
	else:
		_magazine_label.modulate = Color(0.95, 0.95, 0.95)

	# Clear a stale "MAGAZINE EMPTY" once rounds are actually available again.
	if magazine > 0 and _weapon_status_label.text == "MAGAZINE EMPTY":
		_weapon_status_label.text = ""


func _on_reload_started(_duration: float) -> void:
	_weapon_status_label.text = "RELOADING"
	_weapon_status_label.modulate = Color(1.0, 0.82, 0.35)


func _on_weapon_status_cleared() -> void:
	_weapon_status_label.text = ""


func _on_dry_fired() -> void:
	if _weapon == null:
		return

	# Tell the player *why* nothing happened — and whether reloading would help.
	if _weapon.is_fully_dry():
		_weapon_status_label.text = "NO AMMUNITION"
	else:
		_weapon_status_label.text = "MAGAZINE EMPTY"
	_weapon_status_label.modulate = Color(0.92, 0.28, 0.22)


func _on_damage_taken(_amount: float, direction_angle: float) -> void:
	_damage_markers.append({
		"angle": direction_angle,
		"remaining": damage_marker_lifetime,
	})
	_flash_remaining = 0.35
	_damage_indicator.queue_redraw()


func _on_round_won(kills: int, time_taken: float, is_record: bool) -> void:
	_show_record_banner(is_record)
	_show_overlay(
		"SURVIVED" if _game != null and _game.mode == GameSettings.Mode.TIMED else "EXTRACTED",
		Color(0.45, 0.85, 0.5),
		"%d kills  ·  extracted in %s\n\nPress ENTER to play again" % [
			kills, _format_duration(time_taken)
		]
	)


func _on_round_lost(kills: int, time_survived: float, is_record: bool) -> void:
	_show_record_banner(is_record)
	_show_overlay(
		"YOU DIED",
		Color(0.88, 0.26, 0.22),
		"%d kills  ·  survived %s\n\nPress ENTER to try again" % [
			kills, _format_duration(time_survived)
		]
	)


## A run that beat the previous best should say so on the results screen. In
## Endless especially it is the only feedback the mode can give.
func _show_record_banner(is_record: bool) -> void:
	_record_label.visible = is_record


func _show_overlay(title: String, color: Color, detail: String) -> void:
	_overlay_title.text = title
	_overlay_title.modulate = color
	_overlay_detail.text = detail
	_overlay.visible = true


func _tick_damage_markers(delta: float) -> void:
	if _damage_markers.is_empty():
		return

	for marker in _damage_markers:
		marker.remaining -= delta

	_damage_markers = _damage_markers.filter(
		func(marker: Dictionary) -> bool: return marker.remaining > 0.0
	)
	_damage_indicator.queue_redraw()


## Confirm a hit landed. Without it the player is guessing whether a shot
## connected, which in a game about counting bullets is the difference between
## a considered decision and a superstition.
func flash_hitmarker() -> void:
	_hitmarker_remaining = hitmarker_duration
	_hitmarker.modulate.a = 1.0


func _tick_hitmarker(delta: float) -> void:
	if _hitmarker_remaining <= 0.0:
		return

	_hitmarker_remaining = maxf(0.0, _hitmarker_remaining - delta)
	_hitmarker.modulate.a = _hitmarker_remaining / hitmarker_duration


## Pulse a red vignette while health is low.
##
## A number in the corner is something the player has to remember to read. A
## pulse at the edge of vision is something they feel, which is what you want
## when the information is "you are about to die".
func _tick_hurt_vignette(delta: float) -> void:
	if _player == null:
		return

	var fraction := _player.health.get_fraction()
	if fraction > LOW_HEALTH_FRACTION or _player.health.is_dead:
		_hurt_vignette.modulate.a = move_toward(_hurt_vignette.modulate.a, 0.0, delta * 2.0)
		return

	_hurt_pulse += delta * lerpf(6.5, 2.6, fraction / LOW_HEALTH_FRACTION)
	var severity := 1.0 - fraction / LOW_HEALTH_FRACTION
	_hurt_vignette.modulate.a = (0.45 + sin(_hurt_pulse) * 0.25) * severity


func _tick_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return

	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	_damage_flash.color.a = (_flash_remaining / 0.35) * 0.32


## Arc markers around the crosshair pointing at whatever just hit the player.
## This is the concept's mitigation for first-person flanking being invisible.
func _draw_damage_markers() -> void:
	var center := _damage_indicator.size * 0.5
	var radius := 110.0

	for marker in _damage_markers:
		var alpha: float = clampf(marker.remaining / damage_marker_lifetime, 0.0, 1.0)
		var color := Color(0.95, 0.2, 0.15, alpha)

		# Screen space puts 0 radians up, so rotate the bearing a quarter turn.
		var facing: float = marker.angle - PI * 0.5
		var points := PackedVector2Array()
		var segments := 12
		var spread := deg_to_rad(34.0)

		for i in segments + 1:
			var t := float(i) / float(segments)
			var angle: float = facing - spread * 0.5 + spread * t
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)

		_damage_indicator.draw_polyline(points, color, 5.0, true)


func _format_duration(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
