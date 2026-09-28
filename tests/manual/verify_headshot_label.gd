extends SceneTree

## Regression: the HEADSHOT callout must only appear for a moment after a
## headshot. It used to be switched on with the rest of the HUD at round start
## and stayed stuck on the crosshair for the whole round.
##
##   Godot --headless --path . --script tests/manual/verify_headshot_label.gd

var _g: Node
var _t := 0.0
var _step := 0
var _failures: Array[String] = []


func _initialize() -> void:
	DeterministicSettings.apply(root)
	_g = (load("res://src/core/game.tscn") as PackedScene).instantiate()
	root.add_child(_g)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		_failures.append(what)


func _process(delta: float) -> bool:
	_t += delta
	var label: Label = _g.hud._headshot_label
	match _step:
		0:
			if _t > 2.0:
				_check(not label.visible, "HEADSHOT is hidden when a round starts")
				_g.hud.show_headshot()
				_step = 1
		1:
			_check(label.visible, "HEADSHOT shows right after a headshot")
			_step = 2
			_t = 10.0
		2:
			if _t > 11.2:
				_check(not label.visible, "HEADSHOT fades out about a second later")
				_g.hud.show_headshot()
				_g.start_round()
				_step = 3
				_t = 20.0
		3:
			if _t > 20.5:
				_check(not label.visible, "HEADSHOT is hidden again after a restart")
				for failure in _failures:
					print("FAIL: ", failure)
				quit(0 if _failures.is_empty() else 1)
				return true
	return false
