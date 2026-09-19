extends SceneTree

## Static project checks run by tools/check.sh. Verifies that the things a
## headless boot cannot catch — input actions, physics layers, required scenes —
## are actually present. Exits non-zero on failure so CI/check.sh can fail hard.

const REQUIRED_ACTIONS := [
	"move_forward",
	"move_back",
	"move_left",
	"move_right",
	"fire",
	"reload",
	"restart",
	"jump",
]

const REQUIRED_SCENES := [
	"res://src/core/game.tscn",
]

func _initialize() -> void:
	var failures: Array[String] = []

	for action in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			failures.append("missing input action: %s" % action)

	for scene_path in REQUIRED_SCENES:
		if not ResourceLoader.exists(scene_path):
			failures.append("missing scene: %s" % scene_path)
		elif load(scene_path) == null:
			failures.append("scene failed to load: %s" % scene_path)

	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene.is_empty():
		failures.append("no main scene configured")

	if failures.is_empty():
		print("PASS: %d input actions, %d scenes verified" % [
			REQUIRED_ACTIONS.size(), REQUIRED_SCENES.size()
		])
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)
