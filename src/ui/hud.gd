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

## How heavy the frame sits when nothing is hunting, and when the room is as
## dangerous as it gets.
const BASE_VIGNETTE_ALPHA := 1.0
const THREAT_VIGNETTE_ALPHA := 1.7

## Crosshair spread, in pixels from the centre. Rest is how tight it sits when
## the player is still; the rest is what movement and firing add.
const CROSSHAIR_REST := 0.0
const CROSSHAIR_MOVE_SPREAD := 9.0
const CROSSHAIR_FIRE_KICK := 5.0
const CROSSHAIR_MAX_KICK := 14.0
const CROSSHAIR_RECOVERY := 22.0
const CROSSHAIR_SMOOTHING := 14.0

## A kill marker is bigger and lasts longer than a hit marker, because the two
## are different pieces of news.
const KILL_MARKER_SCALE := 1.45
const KILL_MARKER_DURATION_SCALE := 2.2

## The pale bar trailing the health bar: how long it waits before draining, how
## fast it drains, and what colour the wound is.
const HEALTH_DELTA_HOLD := 0.35
const HEALTH_DELTA_DRAIN := 55.0
const HEALTH_DELTA_COLOUR := Color(1.0, 0.82, 0.55, 0.5)

## Compass bearings in degrees, and how much of the horizon the strip shows.
const COMPASS_POINTS := {"N": 0.0, "E": 90.0, "S": 180.0, "W": -90.0}
const COMPASS_VISIBLE_ARC := 160.0

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
## The caption under the ammo counts. Doubles as the weapon name once there is
## more than one weapon — with three separate reserves, a bare "12 / 34" does
## not say which gun's 34 it is, and that is the number the player is deciding
## on. Reusing the caption keeps this to one line rather than a new HUD element;
## the full readout is a later pass.
@onready var _ammo_caption: Label = $AmmoBlock/AmmoCaption
@onready var _stats_row: HBoxContainer = %StatsRow
@onready var _play_again_button: Button = %PlayAgainButton
@onready var _menu_button: Button = %MenuButton
@onready var _crosshair: Control = $Crosshair
@onready var _top_bar: Control = $TopBar
@onready var _objective_block: Control = $ObjectiveBlock
@onready var _objective_label: Label = %ObjectiveLabel
@onready var _vitals_block: Control = $VitalsBlock
@onready var _ammo_block: Control = $AmmoBlock
@onready var _noise_ring: Control = %NoiseRing
@onready var _throw_arc: Control = %ThrowArc
@onready var _vignette: TextureRect = $Vignette
@onready var _torch_label: Label = %TorchLabel
@onready var _compass: Control = %Compass
@onready var _prompt_label: Label = %PromptLabel
@onready var _health_delta: Control = %HealthDelta
@onready var _crosshair_up: ColorRect = $Crosshair/Up
@onready var _crosshair_down: ColorRect = $Crosshair/Down
@onready var _crosshair_left: ColorRect = $Crosshair/Left
@onready var _crosshair_right: ColorRect = $Crosshair/Right

var _damage_markers: Array[Dictionary] = []
## Where the objective chevron points, in world space, and whether to draw it.
var _objective_bearing := Vector3.ZERO
var _objective_has_bearing := false
var _flash_remaining := 0.0
var _hitmarker_remaining := 0.0
var _hurt_pulse := 0.0
## The last sound the player made: how loud, and how many heard it.
var _noise_remaining := 0.0
var _noise_loudness := 0.0
var _noise_heard := 0
## Where the sound came from in the world, or INF when it has no place.
var _noise_world := Vector3.INF

## How far the reticle is currently opened, and how much of that came from
## recoil rather than from movement.
var _crosshair_spread := 0.0
var _crosshair_kick := 0.0
## The pale health bar trailing behind the real one.
var _health_delta_value := 0.0
var _health_delta_hold := 0.0


func _ready() -> void:
	_overlay.visible = false
	_record_label.visible = false
	_hitmarker.modulate.a = 0.0
	_damage_flash.color.a = 0.0
	_damage_indicator.draw.connect(_draw_damage_markers)
	_noise_ring.draw.connect(_draw_noise_ring)
	_throw_arc.draw.connect(_draw_throw_arc)
	_compass.draw.connect(_draw_compass)
	_health_delta.draw.connect(_draw_health_delta)
	_ready_minimap()
	_ready_melee()

	# The arms are moved relative to where the scene put them, so the authored
	# gap between the reticle and its centre survives the spread maths.
	for arm in [_crosshair_up, _crosshair_down, _crosshair_left, _crosshair_right]:
		arm.set_meta("rest_position", arm.position)

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
	_tick_crosshair(delta)
	_tick_health_delta(delta)
	_tick_map(delta)
	_tick_melee(delta)

	# The bearing changes every time the player turns, which is constantly.
	_compass.queue_redraw()

	# The arc follows the camera, so it has to be redrawn every frame it is up
	# rather than only when something changes.
	if _weapon != null and _weapon.is_aiming_throw():
		_throw_arc.queue_redraw()
	elif _throw_arc.visible:
		_throw_arc.queue_redraw()


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

	player.flashlight.toggled.connect(_on_flashlight_toggled)
	player.health.changed.connect(_on_health_changed)
	player.damage_taken.connect(_on_damage_taken)

	weapon.ammo_changed.connect(_on_ammo_changed)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_weapon_status_cleared)
	weapon.dry_fired.connect(_on_dry_fired)
	weapon.fired.connect(_on_weapon_fired)
	weapon.weapon_switched.connect(_on_weapon_switched)
	_on_weapon_switched(weapon.kind, weapon.display_name)

	spawner.population_changed.connect(_on_population_changed)
	spawner.zombie_died.connect(_on_zombie_killed)

	# The map needs the cave and the crowd, both read-only.
	_bind_minimap(game, spawner)
	_bind_melee(weapon)

	# Seeded from the real value, or the pale bar drains from zero on the first
	# frame and reads as damage the player never took.
	_health_delta_value = player.health.current_health
	_on_flashlight_toggled(player.flashlight.is_on)
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

	# A new round is a new cave to learn: nothing carries over.
	_revealed.clear()
	_discovered_caches.clear()
	_contact_pings.clear()


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


## The torch state has to be readable without looking away from the cave, so
## it sits with the other status captions rather than anywhere new. Amber when
## lit follows the rule the rest of the HUD uses: amber means a resource is
## being spent, and light is the loudest thing the player owns that is not a
## gun.
func _on_flashlight_toggled(is_on: bool) -> void:
	# The caption names what is happening and never says by how much. A
	# percentage invites arithmetic; the bargain should be felt in what the
	# cave does to you, with the HUD only putting a word to it. The word is
	# still chosen from the torch's own figure, so retuning the cost in one
	# place cannot leave this line claiming a price that no longer exists.
	_torch_label.text = _lit_caption() if is_on else "T O R C H   O F F"
	_torch_label.modulate = (
		GameSettings.colour(self, "accent", Color(0.878, 0.631, 0.235))
		if is_on else Color(1.0, 1.0, 1.0)
	)


func _lit_caption() -> String:
	var word := _exposure_word()
	if word.is_empty():
		return "T O R C H   O N"
	return "T O R C H   O N   ·   %s" % word


## How conspicuous the torch currently makes the player, in words.
##
## Bands rather than a figure: "seen further" is something a player can act on,
## "+45%" is something they can only do sums with. Read off the same
## lit_visibility_scale the zombies use to decide how far away a lit target
## registers, so the wording moves when the balance does — down to nothing at
## all if the cost is ever tuned away.
func _exposure_word() -> String:
	var scale := 1.45
	if _player != null and _player.flashlight != null:
		scale = _player.flashlight.lit_visibility_scale

	if scale <= 1.02:
		return ""
	if scale <= 1.25:
		return "S E E N   S O O N E R"
	if scale <= 1.6:
		return "S E E N   F U R T H E R"
	return "S E E N   F R O M   A N Y W H E R E"


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current

	# A hit leaves the pale bar behind at the old value; healing pulls it up
	# immediately, because there is no wound to show.
	if current < _health_delta_value:
		_health_delta_hold = HEALTH_DELTA_HOLD
	else:
		_health_delta_value = current
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


## Name the weapon whose magazine and reserve the counts belong to.
func _on_weapon_switched(_kind: WeaponTypes.Kind, display_name: String) -> void:
	_build_weapon_chips()

	# Flash the caption so the change is seen rather than discovered later.
	_switch_flash = 1.0
	_apply_switch_flash()

	if _ammo_caption == null:
		return
	# Letter-spaced to match the caption it replaces.
	var spaced := ""
	for index in display_name.length():
		if index > 0:
			spaced += " "
		spaced += display_name[index]

	_ammo_caption.text = "%s   ·   M A G   ·   R E S" % spaced


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
	# Reset from any kill marker still fading, so a hit never inherits its
	# colour or its size.
	_hitmarker.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_hitmarker.scale = Vector2.ONE


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
## The ring is drawn where the sound actually came from, not at the crosshair.
##
## For a gunshot those are the same place and it reads as "you gave yourself
## away". For a thrown decoy they are emphatically not, and the ring appearing
## over *there* while the crowd turns toward it is what teaches the entire
## mechanic in a single throw. Anchoring it to the crosshair would say the
## opposite of what happened.
func report_noise(loudness: float, heard_by: int, at := Vector3.INF) -> void:
	_noise_remaining = NOISE_RING_DURATION
	_noise_loudness = loudness
	_noise_heard = heard_by
	_noise_world = at
	_noise_ring.queue_redraw()


## Where on screen a world position falls, or the centre when it cannot be
## shown — behind the camera, off screen, or with no camera to ask.
func _noise_screen_position() -> Vector2:
	var centre := _noise_ring.size * 0.5

	if _player == null or _noise_world == Vector3.INF:
		return centre

	var camera := _player.camera
	if camera == null or camera.is_position_behind(_noise_world):
		return centre

	return camera.unproject_position(_noise_world)


## Draw where a thrown round would land.
##
## Projected from the same parabola the decoy actually flies, so the arc is a
## promise the throw keeps. A preview computed any other way would be worse
## than none: the player aims at the dot, and if the round lands somewhere else
## they have spent ammunition on a lie.
func _draw_throw_arc() -> void:
	if _weapon == null or _player == null or not _weapon.is_aiming_throw():
		return

	var camera := _player.camera
	if camera == null:
		return

	var arc := _weapon.predict_throw()
	if arc.size() < 2:
		return

	var colour := GameSettings.colour(self, "accent", Color(0.878, 0.631, 0.235))

	for index in arc.size():
		if camera.is_position_behind(arc[index]):
			continue

		var screen := camera.unproject_position(arc[index])
		var along := float(index) / float(arc.size() - 1)

		# Dots rather than a line, thinning along the flight. A solid line
		# reads as a laser sight — something the weapon projects — when this is
		# the player's own estimate of a throw.
		colour.a = 0.75 - 0.35 * along
		_throw_arc.draw_circle(screen, lerpf(3.0, 1.5, along), colour)

	# The landing point is the only part that matters, so it gets a mark of
	# its own rather than being the last dot of a fading trail.
	var landing := arc[arc.size() - 1]
	if not camera.is_position_behind(landing):
		colour.a = 0.9
		_throw_arc.draw_arc(
			camera.unproject_position(landing), 9.0, 0.0, TAU, 20, colour, 1.5, true
		)


## Tighten the edges of the screen as danger closes in.
##
## The same smoothed figure that drives the audio, so the picture and the mix
## move together rather than each doing its own thing. It is deliberately the
## base vignette being pushed rather than a new overlay: the frame simply gets
## heavier, which the eye reads as pressure without ever looking like a HUD
## element switching on.
##
## Separate from the hurt vignette, which is about the state of your body. This
## one is about the state of the room.
func set_threat(threat: float) -> void:
	if _vignette == null:
		return

	_vignette.modulate.a = lerpf(
		BASE_VIGNETTE_ALPHA, THREAT_VIGNETTE_ALPHA, clampf(threat, 0.0, 1.0)
	)


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
		_noise_screen_position(), radius, 0.0, TAU, 48, colour, 1.5, true
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


# --- Interactive layer -------------------------------------------------------
#
# Everything below exists so the HUD answers back. The readouts above report
# state; these react to what the player is doing, which is most of the
# difference between an interface that informs and one that feels connected to
# the game.


## Open the crosshair to match how accurate the player actually is.
##
## A fixed reticle lies: it promises the same precision standing still and
## sprinting. Opening it while moving and kicking it on every shot turns the
## crosshair into a readout of the one thing it was always pretending to show,
## and it costs no screen space to say it.
func _tick_crosshair(delta: float) -> void:
	if _player == null:
		return

	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var from_movement: float = minf(speed / maxf(_player.move_speed, 0.01), 1.0)

	var target: float = CROSSHAIR_REST + CROSSHAIR_MOVE_SPREAD * from_movement + _crosshair_kick
	_crosshair_kick = maxf(0.0, _crosshair_kick - CROSSHAIR_RECOVERY * delta)

	# Chased rather than snapped. A reticle that tracked speed exactly would
	# jitter with every footfall and read as a bug.
	_crosshair_spread = lerpf(
		_crosshair_spread, target, clampf(CROSSHAIR_SMOOTHING * delta, 0.0, 1.0)
	)

	_place_crosshair_arm(_crosshair_up, Vector2(0.0, -_crosshair_spread))
	_place_crosshair_arm(_crosshair_down, Vector2(0.0, _crosshair_spread))
	_place_crosshair_arm(_crosshair_left, Vector2(-_crosshair_spread, 0.0))
	_place_crosshair_arm(_crosshair_right, Vector2(_crosshair_spread, 0.0))


func _place_crosshair_arm(arm: Control, offset: Vector2) -> void:
	if arm != null:
		arm.position = arm.get_meta("rest_position", Vector2.ZERO) + offset


## Kick the reticle open. Called on every shot.
func _on_weapon_fired(_from: Vector3, _to: Vector3) -> void:
	_crosshair_kick = minf(_crosshair_kick + CROSSHAIR_FIRE_KICK, CROSSHAIR_MAX_KICK)


## A kill gets its own confirmation, distinct from a hit.
##
## Landing a shot and finishing something are different pieces of news, and a
## game about ammunition needs the second one to be unmistakable — it is the
## moment the bullet is confirmed to have been worth spending.
func _on_zombie_killed(_at: Vector3, _experience: int, _ammo: int) -> void:
	_hitmarker_remaining = hitmarker_duration * KILL_MARKER_DURATION_SCALE
	_hitmarker.modulate = GameSettings.colour(
		self, "danger", Color(0.95, 0.3, 0.24)
	)
	_hitmarker.modulate.a = 1.0
	_hitmarker.scale = Vector2.ONE * KILL_MARKER_SCALE


## Drain the pale bar down to the real one, so a hit leaves a visible wound.
##
## The health bar alone is a number that changes between glances. The lagging
## bar shows how much was just taken and from where, which is the difference
## between noticing damage and reconstructing it afterwards.
func _tick_health_delta(delta: float) -> void:
	if _health_delta_value <= _health_bar.value:
		_health_delta_value = _health_bar.value
		_health_delta.queue_redraw()
		return

	_health_delta_hold = maxf(0.0, _health_delta_hold - delta)
	if _health_delta_hold > 0.0:
		return

	_health_delta_value = move_toward(
		_health_delta_value, _health_bar.value, HEALTH_DELTA_DRAIN * delta
	)
	_health_delta.queue_redraw()


func _draw_health_delta() -> void:
	var maximum: float = maxf(_health_bar.max_value, 1.0)
	var current: float = _health_bar.value / maximum
	var ghost: float = _health_delta_value / maximum

	if ghost - current < 0.001:
		return

	var size := _health_delta.size
	_health_delta.draw_rect(
		Rect2(size.x * current, 0.0, size.x * (ghost - current), size.y),
		HEALTH_DELTA_COLOUR
	)


## The single line telling the player what they are doing and where.
##
## One line, upper case, always present while the round runs. The bearing feeds
## the compass and nothing else: it is a direction, never a route and never a
## distance. A marker painted on the minimap would answer the navigation problem
## outright, and the navigation problem is the cave.
func set_objective(text: String, bearing_target: Vector3, has_bearing: bool) -> void:
	_objective_bearing = bearing_target
	_objective_has_bearing = has_bearing

	if _objective_label == null:
		return

	_objective_label.text = text
	# An empty line is a blank row pushing the rest of the block down, so the
	# label leaves rather than sits there.
	_objective_label.visible = not text.is_empty()


## A compass strip, so the cave can be navigated by memory.
##
## The map is a loop of chambers that look increasingly alike by design, and
## "which way is the north hall" is a question the player asks constantly. A
## bearing answers it without a minimap drawing the whole map for them, which
## would take the tension out of being lost.
func _draw_compass() -> void:
	if _player == null:
		return

	var facing := -_player.global_transform.basis.z
	var bearing := atan2(facing.x, -facing.z)
	var width := _compass.size.x
	var centre := width * 0.5

	for point in COMPASS_POINTS:
		var offset := angle_difference(bearing, deg_to_rad(COMPASS_POINTS[point]))

		# Only the arc actually in front of the player is drawn; the rest would
		# be a ring of labels pointing at the back of their head.
		if absf(offset) > deg_to_rad(COMPASS_VISIBLE_ARC * 0.5):
			continue

		var x: float = centre + offset / deg_to_rad(COMPASS_VISIBLE_ARC * 0.5) * centre
		var fade: float = 1.0 - absf(offset) / deg_to_rad(COMPASS_VISIBLE_ARC * 0.5)

		var colour := Color(0.886, 0.914, 0.965, 0.25 + 0.45 * fade)
		_compass.draw_string(
			ThemeDB.fallback_font, Vector2(x - 6.0, 14.0), point,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colour
		)

	# The centre tick is what the labels are read against.
	_compass.draw_rect(
		Rect2(centre - 1.0, 18.0, 2.0, 6.0),
		GameSettings.colour(self, "accent", Color(0.878, 0.631, 0.235))
	)

	_draw_objective_chevron(bearing, centre)


## A single chevron on the compass, at the bearing of the current objective.
##
## It rides the same strip as the cardinal letters, so it answers "which way"
## in the place the player already looks for that answer, and it says nothing
## about how far or by what route.
func _draw_objective_chevron(bearing: float, centre: float) -> void:
	if not _objective_has_bearing or _player == null:
		return

	var to_target := _objective_bearing - _player.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return

	var target_bearing := atan2(to_target.x, -to_target.z)
	var offset := angle_difference(bearing, target_bearing)
	var half_arc := deg_to_rad(COMPASS_VISIBLE_ARC * 0.5)

	# Clamped to the edge of the strip rather than hidden when the objective is
	# behind the player. A chevron that disappears reads as "arrived", and the
	# one thing it must never do is stop telling the truth.
	var clamped := clampf(offset, -half_arc, half_arc)
	var x: float = centre + clamped / half_arc * centre
	var colour := GameSettings.colour(self, "accent", Color(0.878, 0.631, 0.235))

	_compass.draw_colored_polygon(
		PackedVector2Array([
			Vector2(x, 0.0), Vector2(x - 5.0, -7.0), Vector2(x + 5.0, -7.0)
		]),
		colour
	)


## Show a contextual prompt, or clear it when given nothing.
##
## Bottom centre and close to the crosshair on purpose: a prompt the player has
## to look away from the world to read is a prompt they will miss.
func show_prompt(text: String) -> void:
	_prompt_label.text = text


# --- Minimap -----------------------------------------------------------------
#
# Drawn from the arena's own cell grid rather than from a second camera: the
# layout is already a dictionary of Vector2i, so a map costs a dictionary
# lookup per cell instead of a render pass, and it can never disagree with the
# geometry the player is standing in.
#
# ORIENTATION — heading-up. The map rotates so that forward is up. The compass
# strip already answers "which way is north"; the question the map has to
# answer is "is that opening on my left the one I came in by", and a north-up
# map makes the player do that rotation in their head while something is
# chasing them. North stays findable: a tick rides the rim.
#
# REVEAL — nothing is given away at the start. A cell is remembered once the
# player has either been next to it (minimap_touch_cells — feeling your way
# along a wall in the dark) or looked at it down an unbroken line of open cells
# inside minimap_sight_arc_degrees. Sight reaches further with the torch lit,
# which is the bargain the torch makes everywhere else: you see more of the
# cave and the cave sees more of you.
#
# CONTACTS — see contact_rule(). Never a wallhack.

## How often the reveal sweep runs. Cheap, but not free, and the map does not
## change meaningfully between frames at walking pace.
const MAP_SAMPLE_INTERVAL := 0.2

## Steps per cell when walking a sight line. Finer than this only finds corners
## the player could not shoot through anyway.
const MAP_LINE_STEP := 0.34

@export_group("Minimap")
## How many cells fit across the dial. Smaller is a closer, more legible map.
@export var minimap_visible_cells := 13.0
## Cells around the player revealed without needing line of sight — what you
## would know by touch.
@export var minimap_touch_cells := 1.6
## How far an unlit player sees, in cells, and what the torch adds.
@export var minimap_sight_cells := 4.0
@export var minimap_torch_bonus_cells := 3.0
## The cone the player is considered to be looking down.
@export var minimap_sight_arc_degrees := 110.0

@export_group("Contacts")
## Anything nearer than this is on the map whatever it is doing: at this range
## the player can hear it, and a marker only confirms what the mix already said.
@export var contact_radius := 8.0
## How long a noise a zombie made stays on the map as a stale mark.
@export var contact_ping_lifetime := 3.5

var _arena: Arena
var _spawner: ZombieSpawner
## The arena's cell grid, fetched once. Read-only here.
var _occupied: Dictionary = {}
## Vector2i -> true for every cell the player has earned.
var _revealed: Dictionary = {}
## Index into arena.ammo_caches -> true, once its cell has been revealed.
var _discovered_caches: Dictionary = {}
## Stale marks: { "position": Vector3, "remaining": float }.
var _contact_pings: Array[Dictionary] = []
var _map_sample_cooldown := 0.0
## Fades the weapon caption back to normal after a switch, so the change is seen.
var _switch_flash := 0.0

@onready var _minimap: Control = %MiniMap
@onready var _weapon_row: HBoxContainer = %WeaponRow


## Wire the map up. Called from _ready(), after the scene exists.
func _ready_minimap() -> void:
	_minimap.draw.connect(_draw_minimap)


## Take the arena and the spawner from the round being bound.
##
## Both are read, never written: the map is a view of the cave, and a view that
## could move a zombie would be a bug with a very long tail.
func _bind_minimap(game: Game, spawner: ZombieSpawner) -> void:
	_arena = game.arena
	_spawner = spawner
	_revealed.clear()
	_discovered_caches.clear()
	_contact_pings.clear()

	if _arena != null and _arena.has_method("_occupied_cells"):
		_occupied = _arena.call("_occupied_cells")

	# A groan, or a zombie noticing you, is the moment it gave its position
	# away. That is the only reason the map is allowed to know where it was.
	spawner.zombie_groaned.connect(_on_contact_noise)
	spawner.zombie_noticed_player.connect(_on_contact_noise)

	_build_weapon_chips()


func _on_contact_noise(at: Vector3, _kind: ZombieTypes.Kind) -> void:
	_contact_pings.append({"position": at, "remaining": contact_ping_lifetime})


func _tick_map(delta: float) -> void:
	if not _contact_pings.is_empty():
		for ping in _contact_pings:
			ping.remaining -= delta
		_contact_pings = _contact_pings.filter(
			func(ping: Dictionary) -> bool: return ping.remaining > 0.0
		)

	_map_sample_cooldown -= delta
	if _map_sample_cooldown <= 0.0:
		_map_sample_cooldown = MAP_SAMPLE_INTERVAL
		sample_visibility()

	if _switch_flash > 0.0:
		_switch_flash = maxf(0.0, _switch_flash - delta)
		_apply_switch_flash()

	_minimap.queue_redraw()


## Remember whatever the player can currently touch or see.
##
## Public because it is the whole reveal rule, and a test that cannot step it
## deterministically cannot prove the map does not start fully drawn.
func sample_visibility() -> void:
	if _player == null or _occupied.is_empty():
		return

	var here := _player.global_position
	var centre := _world_to_cell(here)
	var facing := -_player.global_transform.basis.z
	var heading := Vector2(facing.x, facing.z)
	if heading.length_squared() < 0.0001:
		heading = Vector2(0.0, -1.0)
	heading = heading.normalized()

	var sight := minimap_sight_cells
	if _player.flashlight != null and _player.flashlight.is_on:
		sight += minimap_torch_bonus_cells

	var cone := cos(deg_to_rad(minimap_sight_arc_degrees * 0.5))
	var reach := int(ceil(maxf(sight, minimap_touch_cells)))

	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var cell := centre + Vector2i(dx, dy)
			if _revealed.has(cell) or not _occupied.has(cell):
				continue

			var offset := Vector2(float(dx), float(dy))
			var distance := offset.length()
			if distance <= minimap_touch_cells:
				_revealed[cell] = true
				continue

			if distance > sight:
				continue
			if heading.dot(offset / maxf(distance, 0.001)) < cone:
				continue
			if _map_line_is_open(centre, cell):
				_revealed[cell] = true

	_discover_caches()


## True when every cell between two cells is open floor.
##
## Walls in this arena are the absence of a cell, so an unbroken line of
## occupied cells is exactly a line of sight.
func _map_line_is_open(from: Vector2i, to: Vector2i) -> bool:
	var start := Vector2(from)
	var end := Vector2(to)
	var steps := int(ceil(start.distance_to(end) / MAP_LINE_STEP))

	for index in range(1, steps):
		var point := start.lerp(end, float(index) / float(steps))
		if not _occupied.has(Vector2i(roundi(point.x), roundi(point.y))):
			return false

	return true


## A cache is on the map once the player has revealed the ground it stands on.
func _discover_caches() -> void:
	if _arena == null:
		return

	for index in _arena.ammo_caches.size():
		if _discovered_caches.has(index):
			continue
		var cache: AmmoCache = _arena.ammo_caches[index]
		if cache != null and _revealed.has(_world_to_cell(cache.global_position)):
			_discovered_caches[index] = true


func _world_to_cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / Arena.CELL), roundi(point.z / Arena.CELL))


## How many cells the player has earned so far. For tests, and nothing else.
func revealed_cell_count() -> int:
	return _revealed.size()


## How many cells the cave has in total.
func map_cell_count() -> int:
	return _occupied.size()


## THE MARKER RULE. A zombie is on the map only when it has already given
## itself away:
##
##   * it is HUNTING — it can see the player and is tracking them live. The
##     information is symmetric: it knows where you are, so you know where it
##     is. That is what makes the marker a warning rather than an advantage.
##   * it has been alerted — INVESTIGATING, SEARCHING or RETREATING — and is
##     inside contact_radius. It is already looking for the player and close
##     enough to hear, so the marker confirms a direction they half know.
##
## A zombie that has noticed nothing is never drawn, however close it comes:
## that was a proximity radar, and it let a patient player track a crowd that
## had no idea they were there.
##
## Everything else is invisible. A Stalker circling two rooms away, or a
## Shambler that has noticed nothing, stays off the map, because the moment the
## map shows those the game stops being about not knowing.
##
## Separately, a zombie that made a noise leaves a stale mark for
## contact_ping_lifetime seconds — where it *was*, not where it is.
func contact_rule(awareness: int, distance: float) -> bool:
	# UNAWARE is never drawn, at any range. Allowing it inside contact_radius
	# turned the dial into a proximity radar: a patient player could stand
	# still and watch wanderers flicker across the ring, which is a map of
	# where things are rather than a warning that something is coming.
	if awareness == Zombie.Awareness.UNAWARE:
		return false

	return awareness == Zombie.Awareness.HUNTING or distance <= contact_radius


## Everything the map is currently allowed to show.
## Entries: { "position": Vector3, "live": bool, "age": float }.
func visible_contacts() -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []

	if _player != null and _spawner != null:
		for child in _spawner.get_children():
			var zombie := child as Zombie
			if zombie == null or zombie.health.is_dead:
				continue
			var distance := zombie.global_position.distance_to(_player.global_position)
			if contact_rule(zombie.awareness, distance):
				contacts.append({
					"position": zombie.global_position, "live": true, "age": 0.0,
				})

	for ping in _contact_pings:
		contacts.append({
			"position": ping.position,
			"live": false,
			"age": 1.0 - ping.remaining / maxf(contact_ping_lifetime, 0.001),
		})

	return contacts


func _draw_minimap() -> void:
	var extent: float = minf(_minimap.size.x, _minimap.size.y)
	var centre := _minimap.size * 0.5
	var radius := extent * 0.5 - 2.0

	# The dial is drawn even with no round behind it, so the corner never looks
	# like a piece of interface that failed to load.
	_minimap.draw_circle(centre, radius, Color(0.03, 0.035, 0.05, 0.62))
	_minimap.draw_arc(centre, radius, 0.0, TAU, 64, Color(0.55, 0.6, 0.7, 0.35), 1.0, true)

	if _player == null or _occupied.is_empty():
		return

	var pixels_per_cell := extent / maxf(minimap_visible_cells, 1.0)
	var here := _player.global_position
	var player_cell := Vector2(here.x / Arena.CELL, here.z / Arena.CELL)

	var facing := -_player.global_transform.basis.z
	var forward := Vector2(facing.x, facing.z)
	if forward.length_squared() < 0.0001:
		forward = Vector2(0.0, -1.0)
	forward = forward.normalized()
	# Screen right, in world-XZ terms. With forward up this puts east on the
	# right when the player faces north.
	var right := Vector2(-forward.y, forward.x)

	var floor_colour := Color(0.62, 0.68, 0.78, 0.3)
	for cell in _revealed:
		var offset := Vector2(cell) - player_cell
		var screen := centre + Vector2(offset.dot(right), -offset.dot(forward)) * pixels_per_cell
		if screen.distance_to(centre) > radius - pixels_per_cell * 0.62:
			continue
		_draw_map_cell(screen, right, forward, pixels_per_cell, floor_colour)

	_draw_map_caches(centre, radius, pixels_per_cell, player_cell, right, forward)
	_draw_map_contacts(centre, radius, pixels_per_cell, player_cell, right, forward)
	_draw_map_north(centre, radius, right, forward)
	_draw_map_exposure(centre, pixels_per_cell)
	_draw_map_player(centre)


## The torch, drawn as the pool of light it actually is.
##
## This is the cost of the light said without saying it: while the torch is on
## the dial carries a soft amber bloom around the player, sized by the same
## lit_visibility_scale the zombies read when they decide how far off a lit
## target registers. Turning the torch off collapses it to nothing, and that
## collapse — not a percentage — is what teaches the player that the dark is
## worth something.
func _draw_map_exposure(centre: Vector2, pixels_per_cell: float) -> void:
	if _player == null or _player.flashlight == null or not _player.flashlight.is_on:
		return

	var colour := GameSettings.colour(self, "accent", Color(0.878, 0.631, 0.235))
	var reach := minimap_sight_cells * _player.flashlight.lit_visibility_scale

	# Three stacked discs rather than one hard edge: light does not stop, and a
	# crisp circle would read as a range the player could step just outside of.
	for step in 3:
		var fraction := 1.0 - float(step) / 3.0
		colour.a = 0.05
		_minimap.draw_circle(centre, reach * fraction * pixels_per_cell, colour)


## One floor tile, turned with the map so the grid reads as a room rather than
## as a scatter of dots.
func _draw_map_cell(screen: Vector2, right: Vector2, forward: Vector2,
		pixels_per_cell: float, colour: Color) -> void:
	var half := pixels_per_cell * 0.46
	var across := Vector2(right.dot(right), -right.dot(forward)) * half
	var along := Vector2(forward.dot(right), -forward.dot(forward)) * half
	_minimap.draw_colored_polygon(PackedVector2Array([
		screen - across - along, screen + across - along,
		screen + across + along, screen - across + along,
	]), colour)


## Where a world point falls on the dial, pinned to the rim when it is off the
## edge. Returns the point and whether it had to be pinned — a pinned marker is
## a bearing, not a position, and is drawn dimmer to say so.
func _map_project(world: Vector3, centre: Vector2, radius: float,
		pixels_per_cell: float, player_cell: Vector2,
		right: Vector2, forward: Vector2) -> Dictionary:
	var offset := Vector2(world.x / Arena.CELL, world.z / Arena.CELL) - player_cell
	var screen := Vector2(offset.dot(right), -offset.dot(forward)) * pixels_per_cell
	var limit := radius - 7.0

	if screen.length() > limit:
		return {"point": centre + screen.normalized() * limit, "pinned": true}

	return {"point": centre + screen, "pinned": false}


func _draw_map_caches(centre: Vector2, radius: float, pixels_per_cell: float,
		player_cell: Vector2, right: Vector2, forward: Vector2) -> void:
	if _arena == null:
		return

	var colour := GameSettings.colour(self, "accent", Color(0.878, 0.631, 0.235))

	for index in _discovered_caches:
		if index >= _arena.ammo_caches.size():
			continue
		var cache: AmmoCache = _arena.ammo_caches[index]
		if cache == null:
			continue

		var projected := _map_project(
			cache.global_position, centre, radius, pixels_per_cell,
			player_cell, right, forward
		)
		var point: Vector2 = projected.point
		colour.a = 0.45 if projected.pinned else 0.9

		# A diamond, filled while it has rounds and hollow once it is spent.
		# Shape rather than colour, so an empty cache reads without relying on
		# hue — the same rule the rest of the HUD follows.
		var diamond := PackedVector2Array([
			point + Vector2(0.0, -5.0), point + Vector2(5.0, 0.0),
			point + Vector2(0.0, 5.0), point + Vector2(-5.0, 0.0),
		])
		if cache.has_stock():
			_minimap.draw_colored_polygon(diamond, colour)
		else:
			var outline := diamond.duplicate()
			outline.append(diamond[0])
			_minimap.draw_polyline(outline, colour, 1.5, true)


func _draw_map_contacts(centre: Vector2, radius: float, pixels_per_cell: float,
		player_cell: Vector2, right: Vector2, forward: Vector2) -> void:
	var danger := GameSettings.colour(self, "danger", Color(0.9, 0.28, 0.24))

	for contact in visible_contacts():
		var projected := _map_project(
			contact.position, centre, radius, pixels_per_cell,
			player_cell, right, forward
		)
		var point: Vector2 = projected.point
		var colour := danger

		if contact.live:
			# A solid wedge: something is there now.
			colour.a = 0.5 if projected.pinned else 0.95
			_minimap.draw_colored_polygon(PackedVector2Array([
				point + Vector2(0.0, -5.5), point + Vector2(4.8, 3.5),
				point + Vector2(-4.8, 3.5),
			]), colour)
		else:
			# A widening, fading ring: something was heard here, and the older
			# the mark the less it is worth acting on.
			var age: float = contact.age
			colour.a = (1.0 - age) * 0.7
			_minimap.draw_arc(
				point, lerpf(3.0, 9.0, age), 0.0, TAU, 20, colour, 1.2, true
			)


## North on the rim, so heading-up never means lost.
func _draw_map_north(centre: Vector2, radius: float, right: Vector2,
		forward: Vector2) -> void:
	var north := Vector2(0.0, -1.0)
	var direction := Vector2(north.dot(right), -north.dot(forward))
	var point := centre + direction * (radius - 9.0)
	_minimap.draw_string(
		ThemeDB.fallback_font, point + Vector2(-4.0, 4.0), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.886, 0.914, 0.965, 0.55)
	)


## The player sits at the centre pointing up, because the map turns and they
## do not. Amber while the torch is lit, matching the torch caption.
func _draw_map_player(centre: Vector2) -> void:
	var colour := Color(0.95, 0.96, 0.98, 0.95)
	if _player != null and _player.flashlight != null and _player.flashlight.is_on:
		colour = GameSettings.colour(self, "accent", Color(0.878, 0.631, 0.235))

	_minimap.draw_colored_polygon(PackedVector2Array([
		centre + Vector2(0.0, -6.0), centre + Vector2(4.5, 5.0),
		centre, centre + Vector2(-4.5, 5.0),
	]), colour)


# --- Arsenal -----------------------------------------------------------------


## One chip per weapon, with the slot key that selects it.
##
## Three separate reserves mean the counts above are only meaningful next to
## the name of the gun they belong to, and the row also answers "what else do I
## have" — which, with the shotgun dry, is the only question that matters. The
## active chip is marked by a caret and by brightness, never by colour alone.
func _build_weapon_chips() -> void:
	if _weapon_row == null:
		return

	var kinds: Array = WeaponTypes.order()
	if _weapon_row.get_child_count() != kinds.size():
		for child in _weapon_row.get_children():
			child.queue_free()
		for index in kinds.size():
			var chip := Label.new()
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_theme_font_size_override("font_size", 11)
			chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
			chip.add_theme_constant_override("outline_size", 2)
			_weapon_row.add_child(chip)

	for index in mini(_weapon_row.get_child_count(), kinds.size()):
		var chip: Label = _weapon_row.get_child(index)
		var kind: WeaponTypes.Kind = kinds[index]
		var active := _weapon != null and _weapon.kind == kind
		chip.text = "%s%d %s" % [
			"▸" if active else " ", index + 1, WeaponTypes.display_name(kind)
		]
		chip.modulate = (
			Color(0.96, 0.96, 0.97, 1.0) if active else Color(0.55, 0.58, 0.64, 0.6)
		)


## Fade the weapon caption back from the accent colour after a switch.
##
## Switching is the one moment the ammo counts change meaning rather than
## value, and a number that silently becomes a different number is the easiest
## way to fire four rounds you thought you had. The flash is short and moves
## nothing, so it reads as confirmation rather than as an alert.
func _apply_switch_flash() -> void:
	if _ammo_caption == null:
		return

	var accent := GameSettings.colour(self, "accent", Color(0.878, 0.631, 0.235))
	_ammo_caption.modulate = Color(1.0, 1.0, 1.0).lerp(accent, _switch_flash)


# --- Emergency melee ---------------------------------------------------------
#
# The melee is a last resort, not a weapon slot, so it is absent from the HUD
# until the player is in the situation it exists for: a magazine with nothing
# in it. A permanent readout would advertise it as an option alongside the
# guns, which is exactly what it is not — it does two thirds of a pistol round
# for four times the wait, and its only real advantage is that it makes no
# sound at all. So the hint says the two things that change a decision: which
# button, and that swinging costs no noise.

## How long a melee confirmation stays up. Shorter than a gunshot's, because
## the swing has already told the player something happened.
const MELEE_MARKER_DURATION := 0.3

## How long "it did not flinch" stays on the status line.
const MELEE_STATUS_DURATION := 0.9

## A hit that landed and moved nothing. Deliberately not the kill red:
## "connected" and "connected and it mattered" have to look different, or a
## Brute's immunity to the stagger reads as the game dropping the hit.
const MELEE_UNMOVED_COLOUR := Color(0.62, 0.66, 0.74, 1.0)

const MELEE_UNMOVED_TEXT := "DID NOT FLINCH"

var _melee_status_remaining := 0.0

@onready var _melee_hint: Label = %MeleeHint


func _ready_melee() -> void:
	_melee_hint.visible = false


func _bind_melee(weapon: Weapon) -> void:
	weapon.melee_swung.connect(_on_melee_swung)


## Surface the melee only while the magazine is empty, and fade it while the
## swing is still coming back.
func _tick_melee(delta: float) -> void:
	if _melee_status_remaining > 0.0:
		_melee_status_remaining = maxf(0.0, _melee_status_remaining - delta)
		if _melee_status_remaining <= 0.0 and _weapon_status_label.text == MELEE_UNMOVED_TEXT:
			_weapon_status_label.text = ""

	if _weapon == null or _melee_hint == null:
		return

	# Empty magazine, not empty reserve: the moment worth naming is the one
	# where the trigger has just stopped working, whether or not a reload is
	# available. Reloading in front of something is the decision this is for.
	var dry := _weapon.magazine_ammo <= 0
	_melee_hint.visible = dry
	if not dry:
		return

	if _melee_hint.text.is_empty():
		_melee_hint.text = "%s   M E L E E   ·   S I L E N T" % _melee_key_name()

	# Dimmed while the swing is still recovering, so a cooldown reads as "not
	# yet" rather than as a button that did nothing.
	var cooldown: float = maxf(_weapon.melee_cooldown, 0.001)
	var ready_fraction: float = 1.0 - clampf(
		_weapon.melee_cooldown_remaining() / cooldown, 0.0, 1.0
	)
	_melee_hint.modulate.a = lerpf(0.28, 0.85, ready_fraction)


## The control actually bound to the melee action, read from the InputMap.
##
## A prompt naming a key that does nothing is worse than no prompt, and the
## controls screen already lets the player rebind this one.
func _melee_key_name() -> String:
	if not InputMap.has_action("melee"):
		return "MELEE"

	for event in InputMap.action_get_events("melee"):
		if event is InputEventKey:
			return (event as InputEventKey).as_text_physical_keycode().to_upper()

	return "MELEE"


## Confirm a swing, and say which of the three things happened.
##
## A miss gets nothing: the swing itself is the feedback, and a marker for
## "there was nothing there" would be noise in the one moment the player is
## already panicking. A hit that staggered gets the ordinary confirmation. A
## hit that did not gets its own colour and a word, because "that connected and
## went nowhere" is a fact the player has to act on — by moving, which is the
## Brute's whole rule.
func _on_melee_swung(hit: bool, staggered: bool, _at: Vector3) -> void:
	if not hit:
		return

	_hitmarker_remaining = MELEE_MARKER_DURATION
	_hitmarker.scale = Vector2.ONE

	if staggered:
		_hitmarker.modulate = Color(1.0, 1.0, 1.0, 1.0)
		return

	_hitmarker.modulate = MELEE_UNMOVED_COLOUR
	_weapon_status_label.text = MELEE_UNMOVED_TEXT
	_weapon_status_label.modulate = MELEE_UNMOVED_COLOUR
	_melee_status_remaining = MELEE_STATUS_DURATION
