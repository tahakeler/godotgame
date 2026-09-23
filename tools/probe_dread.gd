extends SceneTree

## Plays a real Signal-mode round with a stand-in that kills anything within
## 8 m and is held at 30% health after two minutes, then reports how often
## the dread systems actually fire in play: phantoms by kind, torch flickers,
## heartbeats, the deepest muffle, and how the round's threat is distributed.
## Unit tests prove each system obeys its rules; this is the only check that
## the rules ever let it happen in a real round.
##
##   Godot --headless --path . --script tools/probe_dread.gd
const SECONDS := 240.0
var _game: Node
var _t := 0.0
var _phantoms := {}
var _flickers := 0
var _was_flicker := false
var _hist := [0, 0, 0, 0, 0]
var _min_cutoff := 20000.0
var _kill_timer := 0.0
var _kills := 0
func _initialize() -> void:
	DeterministicSettings.apply(root)
	var s = root.get_node_or_null("Settings")
	if s != null: s.mode = GameSettings.Mode.RELAY
	print("settings node: ", s != null)
	_game = (load("res://src/core/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
func _process(delta: float) -> bool:
	if _t == 0.0:
		_game.dread.phantom_played.connect(func(k: int, _a: Vector3) -> void:
			_phantoms[k] = _phantoms.get(k, 0) + 1)
		_game.player.flashlight.set_on(true)
	_t += delta
	if _game.upgrade_menu.is_open():
		_game.upgrade_menu.close()
		_game._on_resumed()
	var h: Health = _game.player.health
	if _t > 120.0 and h.current_health > h.max_health * 0.3:
		h.take_damage(h.current_health - h.max_health * 0.3)
	if h.current_health < h.max_health * 0.3:
		h.heal(h.max_health * 0.3 - h.current_health)
	_kill_timer -= delta
	if _kill_timer <= 0.0:
		_kill_timer = 1.0
		for z in _game.spawner._alive.duplicate():
			if is_instance_valid(z) and z.global_position.distance_to(_game.player.global_position) < 8.0:
				z.take_damage(9999.0); _kills += 1
	var f: bool = _game.player.flashlight.is_flickering()
	if f and not _was_flicker: _flickers += 1
	_was_flicker = f
	var th: float = _game.ambience.threat()
	_hist[mini(int(th / 0.12), 4)] += 1
	var i := AudioServer.get_bus_index("SFX")
	for e in AudioServer.get_bus_effect_count(i):
		var fx := AudioServer.get_bus_effect(i, e)
		if fx is AudioEffectLowPassFilter: _min_cutoff = minf(_min_cutoff, fx.cutoff_hz)
	if _t >= SECONDS:
		var tot := 0
		for v in _hist: tot += v
		var pct := []
		for v in _hist: pct.append("%d%%" % roundi(100.0 * v / tot))
		print("PROBE state=%d phantoms=%s flickers=%d beats=%d min_cutoff=%.0f kills=%d threat_hist[<.12,<.24,<.36,<.48,rest]=%s" % [_game.state, _phantoms, _flickers, _game.vitals.beats_played, _min_cutoff, _kills, pct])
		quit(); return true
	return false
