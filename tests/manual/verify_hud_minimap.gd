extends SceneTree

## Verifies the minimap, the marker rule, and the three-weapon ammo readout.
##
## Every failure guarded here is silent on a screenshot. A map that starts
## fully revealed looks exactly like a map that reveals correctly, once the
## player has walked around. A marker rule that never expires looks like a
## marker rule until the round turns into a wallhack. An ammo readout reading
## a shared pool looks right until the moment the decision depends on it.
##
##   Godot --headless --script tests/manual/verify_hud_minimap.gd

const GAME_SCENE := "res://src/core/game.tscn"

var _game: Game
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		# Autoloads exist only after _initialize returns, so the settings are
		# pinned on the first processed frame rather than in setup.
		DeterministicSettings.apply(root)
		return false

	_game.start_round()

	test_map_does_not_start_revealed()
	test_map_reveals_as_the_player_moves()
	test_marker_rule_only_covers_hunters_and_close_contacts()
	test_noise_marker_expires()
	test_ammo_follows_the_weapon_and_its_own_reserve()
	test_hud_writes_nothing_back_to_the_game()

	_report()
	return true


func test_map_does_not_start_revealed() -> void:
	# Arrange / Act: a fresh round, with one visibility sample taken.
	var hud := _game.hud
	hud.sample_visibility()

	# Assert: the cave has to be learnt. Knowing everything from the first
	# frame removes the only reason to explore carefully.
	var revealed := hud.revealed_cell_count()
	var total := hud.map_cell_count()

	if total <= 0:
		_failures.append("the minimap has no cell grid to draw")
	elif revealed <= 0:
		_failures.append("the minimap revealed nothing at all at the start")
	elif revealed >= total:
		_failures.append(
			"the minimap started fully revealed (%d of %d cells)" % [revealed, total]
		)
	else:
		print("PASS: the map starts partly revealed (%d of %d cells)" % [revealed, total])


func test_map_reveals_as_the_player_moves() -> void:
	# Arrange
	var hud := _game.hud
	var before := hud.revealed_cell_count()

	# Act: walk the player into the ring, well clear of the chamber, and let
	# the map sample from there.
	_game.player.global_position = Vector3(Arena.CELL * 6.0, 0.4, 0.0)
	hud.sample_visibility()

	# Assert
	var after := hud.revealed_cell_count()
	if after <= before:
		_failures.append(
			"the map revealed nothing after the player moved (%d cells both times)" % after
		)
	else:
		print("PASS: moving reveals more of the map (%d -> %d cells)" % [before, after])


func test_marker_rule_only_covers_hunters_and_close_contacts() -> void:
	# Arrange
	var hud := _game.hud

	# Act / Assert: the rule is the feature, so it is asserted directly rather
	# than through whichever zombies the spawner happened to make.
	if not hud.contact_rule(Zombie.Awareness.HUNTING, 40.0):
		_failures.append("a hunting zombie was not shown on the map")
	elif hud.contact_rule(Zombie.Awareness.UNAWARE, 40.0):
		_failures.append("an unaware zombie across the map was shown — that is a wallhack")
	elif hud.contact_rule(Zombie.Awareness.INVESTIGATING, 40.0):
		_failures.append("an investigating zombie across the map was shown")
	elif not hud.contact_rule(Zombie.Awareness.UNAWARE, 2.0):
		_failures.append("a zombie at arm's length was not shown")
	else:
		print("PASS: markers cover hunters and close contacts, and nothing else")


func test_noise_marker_expires() -> void:
	# Arrange: a zombie gives its position away.
	var hud := _game.hud
	var before: int = hud.visible_contacts().size()
	_game.spawner.zombie_groaned.emit(
		Vector3(Arena.CELL * 3.0, 0.0, 0.0), ZombieTypes.Kind.SHAMBLER
	)

	# Act
	var during: int = hud.visible_contacts().size()
	hud._tick_map(hud.contact_ping_lifetime + 0.5)
	var after: int = hud.visible_contacts().size()

	# Assert: a noise is a mark that fades, not a tracker that stays.
	if during <= before:
		_failures.append("a groan left no mark on the map")
	elif after != before:
		_failures.append("the noise mark outlived its lifetime (%d marks left)" % after)
	else:
		print("PASS: a noise marks the map and then expires")


func test_ammo_follows_the_weapon_and_its_own_reserve() -> void:
	# Arrange
	var hud := _game.hud
	var weapon: Weapon = _game.weapon

	weapon.equip(WeaponTypes.Kind.PISTOL)
	# A weapon is not in hand until it has been raised, and the HUD deliberately
	# keeps reporting the old gun until it is. Outside a processed frame the swap
	# has to be stepped by hand.
	weapon.call("_tick_swap", 5.0)
	var pistol_reserve := weapon.reserve_ammo
	var pistol_caption: String = hud._ammo_caption.text

	# Act
	weapon.equip(WeaponTypes.Kind.SHOTGUN)
	weapon.call("_tick_swap", 5.0)
	var shotgun_reserve := weapon.reserve_ammo

	# Assert: the caption names the gun in hand, and the reserve is that gun's
	# own. A shared pool would report the same figure for both.
	var caption: String = hud._ammo_caption.text
	if not caption.begins_with("S H O T G U N"):
		_failures.append("the ammo caption did not follow the switch: '%s'" % caption)
	elif caption == pistol_caption:
		_failures.append("the ammo caption did not change when the weapon did")
	elif shotgun_reserve == pistol_reserve:
		_failures.append(
			"both weapons reported the same reserve (%d) — the pool looks shared"
			% shotgun_reserve
		)
	elif hud._reserve_label.text != str(shotgun_reserve):
		_failures.append(
			"the reserve readout said '%s' while the shotgun holds %d"
			% [hud._reserve_label.text, shotgun_reserve]
		)
	elif hud._magazine_label.text != str(weapon.magazine_ammo):
		_failures.append("the magazine readout did not follow the switch")
	else:
		print("PASS: the ammo readout follows the weapon and its own reserve")


func test_hud_writes_nothing_back_to_the_game() -> void:
	# Arrange: everything the HUD touches while it draws.
	var hud := _game.hud
	var health := _game.player.health.current_health
	var position := _game.player.global_position
	var magazine := _game.weapon.magazine_ammo
	var reserve := _game.weapon.reserve_ammo
	var alive := _game.spawner.get_alive_count()

	# Act: the whole read path, twice, including the contact sweep.
	hud.sample_visibility()
	hud.visible_contacts()
	hud._tick_map(0.25)
	hud.visible_contacts()

	# Assert: the HUD is a view. A view that can change the round is a bug with
	# a very long tail, and this is the only test that would catch it.
	if not is_equal_approx(_game.player.health.current_health, health):
		_failures.append("the HUD changed the player's health")
	elif not _game.player.global_position.is_equal_approx(position):
		_failures.append("the HUD moved the player")
	elif _game.weapon.magazine_ammo != magazine or _game.weapon.reserve_ammo != reserve:
		_failures.append("the HUD changed the weapon's ammunition")
	elif _game.spawner.get_alive_count() != alive:
		_failures.append("the HUD changed the population")
	else:
		print("PASS: the HUD wrote nothing back to the game")


func _report() -> void:
	if _failures.is_empty():
		print("HUD minimap verification passed")
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
