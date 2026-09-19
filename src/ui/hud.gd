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

## A spent round stays visible rather than disappearing, so the magazine's
## capacity reads as a fixed shape and the gap tells you what you have left.
const PIP_LOADED := Color(0.929, 0.933, 0.949, 0.95)
const PIP_SPENT := Color(0.929, 0.933, 0.949, 0.16)

## Peak opacity of the full-screen damage wash, normally and when the player
## has asked for reduced flashing.
const FULL_FLASH_ALPHA := 0.32
const REDUCED_FLASH_ALPHA := 0.1

const MAIN_MENU_SCENE := "res://src/ui/main_menu.tscn"

## How long the noise ring stays on screen as it expands and fades.
const NOISE_RING_DURATION := 0.55

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
@onready var _magazine_pips: HBoxContainer = %MagazinePips
@onready var _stats_row: HBoxContainer = %StatsRow
@onready var _play_again_button: Button = %PlayAgainButton
@onready var _menu_button: Button = %MenuButton
@onready var _crosshair: Control = $Crosshair
@onready var _top_bar: Control = $TopBar
@onready var _objective_block: Control = $ObjectiveBlock
@onready var _vitals_block: Control = $VitalsBlock
@onready var _ammo_block: Control = $AmmoBlock
@onready var _noise_ring: Control = %NoiseRing

var _damage_markers: Array[Dictionary] = []
var _flash_remaining := 0.0
var _hitmarker_remaining := 0.0
var _hurt_pulse := 0.0
## The last sound the player made: how loud, and how many heard it.
var _noise_remaining := 0.0
var _noise_loudness := 0.0
var _noise_heard := 0


func _ready() -> void:
	_overlay.visible = false
	_record_label.visible = false
	_hitmarker.modulate.a = 0.0
	_damage_flash.color.a = 0.0
	_damage_indicator.draw.connect(_draw_damage_markers)
	_noise_ring.draw.connect(_draw_noise_ring)

	# The results buttons must keep working after the round ends. Nothing pauses
	# the tree here, but the HUD outliving a round is the point of them.
	_play_again_button.pressed.connect(_on_play_again_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)


func _process(delta: float) -> void:
	_tick_damage_markers(delta)
	_tick_flash(delta)
	_tick_hitmarker(delta)
	_tick_hurt_vignette(delta)
	_tick_noise_ring(delta)


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


## Hide the live readouts while the results are up.
##
## A crosshair sitting in the middle of the results, and a kill counter still
## reading out next to the figure that summarises it, both say the round is
## still running when it is not. The results screen should be the only thing
## asking for attention.
func _set_round_readouts_visible(shown: bool) -> void:
	for node in [_crosshair, _top_bar, _objective_block, _vitals_block, _ammo_block]:
		if node != null:
			node.visible = shown


func _on_round_started() -> void:
	_overlay.visible = false
	_set_round_readouts_visible(true)
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

	# Colour comes from the active palette rather than being hard-coded, so the
	# colour-vision setting reaches the one readout where red-green is the
	# difference between fine and nearly dead. The bar length and the number say
	# the same thing, so colour is never carrying it alone.
	var fraction := current / maxf(maximum, 1.0)
	_health_bar.modulate = (
		GameSettings.colour(self, "danger", Color(0.85, 0.24, 0.2))
		if fraction <= LOW_HEALTH_FRACTION
		else GameSettings.colour(self, "safe", Color(0.42, 0.72, 0.45))
	)


func _on_ammo_changed(magazine: int, reserve: int) -> void:
	_magazine_label.text = str(magazine)
	_reserve_label.text = str(reserve)
	_update_magazine_pips(magazine)

	if magazine == 0:
		_magazine_label.modulate = Color(0.9, 0.25, 0.2)
	elif magazine <= LOW_AMMO_ROUNDS:
		_magazine_label.modulate = Color(1.0, 0.72, 0.25)
	else:
		_magazine_label.modulate = Color(0.95, 0.95, 0.95)


## Draw the magazine as a row of rounds rather than only a number.
##
## A count has to be read; a row of pips is taken in at a glance, which is the
## difference between knowing you are nearly dry and noticing it afterwards.
## The number stays for the exact figure — the pips are for peripheral vision.
func _update_magazine_pips(magazine: int) -> void:
	if _weapon == null:
		return

	var capacity: int = maxi(_weapon.magazine_size, 1)

	# Rebuild only when the capacity itself changes, which an upgrade can do.
	# Rebuilding every shot would churn a dozen nodes several times a second.
	if _magazine_pips.get_child_count() != capacity:
		for child in _magazine_pips.get_children():
			child.queue_free()
		for index in capacity:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(9.0, 10.0)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_magazine_pips.add_child(pip)

	for index in _magazine_pips.get_child_count():
		var pip: ColorRect = _magazine_pips.get_child(index)
		var loaded := index < magazine
		pip.color = PIP_LOADED if loaded else PIP_SPENT

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
		GameSettings.colour(self, "safe", Color(0.45, 0.85, 0.5)),
		kills,
		time_taken
	)


func _on_round_lost(kills: int, time_survived: float, is_record: bool) -> void:
	_show_record_banner(is_record)
	_show_overlay(
		"YOU DIED",
		GameSettings.colour(self, "danger", Color(0.88, 0.26, 0.22)),
		kills,
		time_survived
	)


## Build the stats row for a finished round.
##
## A round ends with a number of things the player wants to know and one line
## of text can only carry two of them. Each figure gets its own column with a
## quiet caption underneath, so the result can be read at a glance and compared
## against the last run without parsing a sentence.
func _build_results(kills: int, duration: float) -> void:
	for child in _stats_row.get_children():
		child.queue_free()

	_add_stat(str(kills), "KILLS")
	_add_stat(_format_duration(duration), "TIME")

	if _game != null and _game.progression != null:
		_add_stat("%d" % _game.progression.level, "LEVEL")

	# Accuracy is only meaningful once a shot has been taken. Showing 0% to
	# someone who never fired reads as a judgement rather than a statistic.
	if _game != null and _game.shots_fired > 0:
		var accuracy := float(_game.shots_hit) / float(_game.shots_fired)
		_add_stat("%d%%" % roundi(accuracy * 100.0), "ACCURACY")


func _add_stat(value: String, caption: String) -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)

	var figure := Label.new()
	figure.text = value
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	figure.add_theme_font_size_override("font_size", 40)
	figure.add_theme_color_override("font_color", Color(0.957, 0.949, 0.933))
	column.add_child(figure)

	var label := Label.new()
	label.text = caption
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.463, 0.494, 0.553))
	column.add_child(label)

	_stats_row.add_child(column)


func _on_play_again_pressed() -> void:
	if _game != null:
		_game.start_round()


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## A run that beat the previous best should say so on the results screen. In
## Endless especially it is the only feedback the mode can give.
func _show_record_banner(is_record: bool) -> void:
	_record_label.visible = is_record


func _show_overlay(title: String, color: Color, kills: int, duration: float) -> void:
	_overlay_title.text = title
	_overlay_title.modulate = color
	_build_results(kills, duration)
	_overlay_detail.text = "Enter to play again  ·  Esc for the menu"
	_overlay.visible = true
	_set_round_readouts_visible(false)

	# The round is over and the cursor has to be usable again, or the buttons
	# below are decorative.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_play_again_button.grab_focus()


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


## Show the player what a sound just cost them.
##
## Without this the awareness system is invisible and therefore arbitrary: a
## crowd arrives and the player has no way to connect it to the shot they fired
## ten seconds ago, so it reads as the game cheating rather than as a rule they
## can work with. A ring sized to the loudness, turning amber when something
## actually heard it, teaches the whole system in about three shots.
func report_noise(loudness: float, heard_by: int) -> void:
	_noise_remaining = NOISE_RING_DURATION
	_noise_loudness = loudness
	_noise_heard = heard_by
	_noise_ring.queue_redraw()


func _tick_noise_ring(delta: float) -> void:
	if _noise_remaining <= 0.0:
		return

	_noise_remaining = maxf(0.0, _noise_remaining - delta)
	_noise_ring.queue_redraw()


func _draw_noise_ring() -> void:
	if _noise_remaining <= 0.0:
		return

	# Expands and fades over its life, so the eye reads it as a sound going out
	# rather than as a static indicator switching on.
	var progress := 1.0 - (_noise_remaining / NOISE_RING_DURATION)
	var radius: float = lerpf(10.0, 26.0 + 46.0 * _noise_loudness, progress)

	var colour: Color = (
		GameSettings.colour(self, "danger", Color(0.95, 0.72, 0.25))
		if _noise_heard > 0
		else Color(0.886, 0.914, 0.965)
	)
	colour.a = (1.0 - progress) * (0.25 + 0.45 * _noise_loudness)

	_noise_ring.draw_arc(
		_noise_ring.size * 0.5, radius, 0.0, TAU, 48, colour, 1.5, true
	)


func _tick_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return

	_flash_remaining = maxf(0.0, _flash_remaining - delta)

	# Damped rather than removed when the player has asked for less flashing.
	# Taking damage still has to register — the flash is how a hit from behind
	# is noticed at all — so it becomes a dim wash instead of vanishing.
	var settings := GameSettings.instance(self)
	var peak: float = (
		REDUCED_FLASH_ALPHA if settings != null and settings.reduce_flashing
		else FULL_FLASH_ALPHA
	)
	_damage_flash.color.a = (_flash_remaining / 0.35) * peak


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
