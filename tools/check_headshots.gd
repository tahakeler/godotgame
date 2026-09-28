extends SceneTree

## Report checks for Feature 2 (headshots, built through the godot-ai MCP):
## a real pistol shot at a Brute's head (normal) and 8 cm under the head zone
## (boundary), plus the zone edge at +/-1 cm. Needs a window (not --headless)
## only for the HUD callout; the numbers print either way.
##
##   Godot --path . --script tools/check_headshots.gd
var _g: Node
var _t := 0.0
var _step := 0
var _z: Zombie
func _initialize() -> void:
	var s: GDScript = load("res://src/core/game_settings.gd")
	var n: Node = s.new(); n.name = "Settings"; root.add_child(n)
	root.size = Vector2i(1600, 900)
	_g = (load("res://src/core/game.tscn") as PackedScene).instantiate()
	root.add_child(_g)
func _aim(y: float) -> void:
	var p: Player = _g.player
	var cam: Camera3D = _g.weapon.get_parent()
	var target := _z.global_position + Vector3(0, y, 0)
	var to := target - cam.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	p.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
func _spawn() -> void:
	_g.spawner.clear_all()
	_z = (load("res://src/gameplay/zombie/zombie.tscn") as PackedScene).instantiate()
	_g.spawner.add_child(_z); _z.configure(ZombieTypes.Kind.BRUTE)
	_z.set_physics_process(false)
	var p: Player = _g.player
	_z.global_position = p.global_position + Vector3(0, 0, -5)
func _process(delta: float) -> bool:
	_t += delta
	if _g.upgrade_menu.is_open(): _g.upgrade_menu.close(); _g._on_resumed()
	_g.player.health.heal(100)
	var w: Weapon = _g.weapon
	match _step:
		0:
			if _t > 3.0:
				w.spread_degrees = 0.0
				_spawn(); _step = 1
		1:
			var h: float = _z._collider.shape.height
			print("brute height=%.2f head zone starts at %.3f m (top %.0f%%)" % [h, h * (1.0 - _z.head_fraction), _z.head_fraction * 100])
			_aim(h * 0.94)
			_step = 2
		2:
			var before: float = _z.health.current_health
			var hs: int = _g.headshots
			w._cooldown_remaining = 0.0
			w.try_fire()
			print("NORMAL head shot: health %.0f -> %.0f (dmg %.0f) headshots %d -> %d callout_visible=%s" % [before, _z.health.current_health, before - _z.health.current_health, hs, _g.headshots, _g.hud._headshot_label.visible])
			_step = 3; _t = 10.0
		3:
			if _t > 10.4:
				
				_z.health.current_health = _z.health.max_health
				var h2: float = _z._collider.shape.height
				_aim(h2 * (1.0 - _z.head_fraction) - 0.08)
				_step = 4
		4:
			if _t > 11.3:
				var before2: float = _z.health.current_health
				var hs2: int = _g.headshots
				_g.weapon._cooldown_remaining = 0.0
				_g.weapon.try_fire()
				print("BOUNDARY 8 cm below head zone: health %.0f -> %.0f (dmg %.0f) headshots %d -> %d" % [before2, _z.health.current_health, before2 - _z.health.current_health, hs2, _g.headshots])
				var h3: float = _z._collider.shape.height
				var edge: float = _z.global_position.y + h3 * (1.0 - _z.head_fraction)
				print("EDGE is_head_hit(edge-1cm)=%s is_head_hit(edge+1cm)=%s" % [_z.is_head_hit(Vector3(0, edge - 0.01, 0)), _z.is_head_hit(Vector3(0, edge + 0.01, 0))])
				_g._end_round(2)
				_step = 5; _t = 20.0
		5:
			if _t > 21.0:
				
				quit(); return true
	return false
