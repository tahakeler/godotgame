extends SceneTree

## Report checks for Feature 1 (ammunition and reload) and the health loss
## condition: normal and boundary cases, printed as expected vs actual inputs.
## Plays the real game scene.
##
##   Godot --headless --path . --script tools/check_ammo_health.gd
var _g: Node
var _t := 0.0
var _step := 0
var _before := 0.0
var _dry := 0
var _died := 0
func _initialize() -> void:
	var s: GDScript = load("res://src/core/game_settings.gd")
	var n: Node = s.new(); n.name = "Settings"; root.add_child(n)
	_g = (load("res://src/core/game.tscn") as PackedScene).instantiate()
	root.add_child(_g)
func _process(delta: float) -> bool:
	_t += delta
	if _g.upgrade_menu.is_open(): _g.upgrade_menu.close(); _g._on_resumed()
	var p: Player = _g.player
	var w: Weapon = _g.weapon
	match _step:
		0:
			if _t > 3.0:
				w.dry_fired.connect(func() -> void: _dry += 1)
				p.died.connect(func() -> void: _died += 1)
				# H1: a Shambler's contact lands once on a full-health player
				_g.spawner.clear_all()
				_before = p.health.current_health
				var z: Zombie = (load("res://src/gameplay/zombie/zombie.tscn") as PackedScene).instantiate()
				_g.spawner.add_child(z); z.configure(ZombieTypes.Kind.SHAMBLER); z.set_target(p); z.relentless = true
				z.global_position = p.global_position + (-p.global_transform.basis.z) * 1.2
				_step = 1
		1:
			if p.health.current_health < _before or _t > 12.0:
				print("H1 normal: Shambler (damage 12) reaches the player -> health %.0f -> %.0f after %.1f s" % [_before, p.health.current_health, _t - 3.0])
				_step = 2
		2:
			# H2 boundary: 5 health left, a 12-damage hit
			_g.spawner.clear_all()
			p.health.current_health = 5.0
			p.health._invulnerable_remaining = 0.0
			p.take_damage(12.0, p.global_position + Vector3(1, 0, 0), Vector3.ZERO)
			print("H2 boundary: 5 hp, 12 dmg -> health=%.0f is_dead=%s died_signals=%d round_state=%d (1=WON,2=LOST)" % [p.health.current_health, p.health.is_dead, _died, _g.state])
			p.take_damage(12.0, p.global_position, Vector3.ZERO)
			print("   second hit after death -> health=%.0f died_signals=%d" % [p.health.current_health, _died])
			_g.start_round(); _step = 3; _t = 100.0
		3:
			if _t > 101.0:
				print("   after restart -> health=%.0f state=%d kills=%d mag=%d res=%d" % [p.health.current_health, _g.state, _g.kills, w.magazine_ammo, w.reserve_ammo])
				var m0 := w.magazine_ammo; var r0 := w.reserve_ammo
				var ok := w.try_fire()
				print("A1 normal: fire -> ok=%s mag %d -> %d" % [ok, m0, w.magazine_ammo])
				_step = 4; _t = 200.0
		4:
			if _t > 200.5:
				var m1 := w.magazine_ammo; var r1 := w.reserve_ammo
				print("   reload -> started=%s" % w.try_reload())
				_before = float(m1 * 1000 + r1)
				_step = 5; _t = 300.0
		5:
			if not w.is_reloading() and _t > 300.2:
				print("   after reload: mag=%d res=%d (was mag=%d res=%d)" % [w.magazine_ammo, w.reserve_ammo, int(_before) / 1000, int(_before) % 1000])
				# A2 boundary: empty magazine, empty reserve
				w.magazine_ammo = 0; w.reserve_ammo = 0
				var d0 := _dry
				var fired := w.try_fire()
				var reloaded := w.try_reload()
				print("A2 boundary: mag=0 res=0 -> fire ok=%s mag=%d dry_fire_signals=+%d reload started=%s" % [fired, w.magazine_ammo, _dry - d0, reloaded])
				quit(); return true
	return false
