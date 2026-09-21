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
	"pause",
]

const REQUIRED_SCENES := [
	"res://src/core/game.tscn",
	"res://src/ui/main_menu.tscn",
	"res://src/ui/pause_menu.tscn",
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

	failures.append_array(_mangled_text_files())

	if failures.is_empty():
		print("PASS: %d input actions, %d scenes verified" % [
			REQUIRED_ACTIONS.size(), REQUIRED_SCENES.size()
		])
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


## Source files whose UTF-8 has been rewritten as latin-1.
##
## An in-place `perl -pi` re-encodes depending on locale unless it is given
## -CSD, and this codebase's comments are full of em-dashes. One agent's edit
## turned every "—" in arena.gd into "â€”" and it was only caught because the
## file happened to be read afterwards. Nothing else notices: GDScript parses
## fine, the game runs fine, and the damage sits in the comments until someone
## opens the file.
##
## The marker is the latin-1 reading of a UTF-8 lead byte, which is the common
## shape of every such mangling and does not occur in correct text here.
func _mangled_text_files() -> Array[String]:
	const MARKER := "â\u0080"
	var found: Array[String] = []

	for path in _source_files("res://src"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains(MARKER):
			found.append("mangled UTF-8 in %s — an edit re-encoded it" % path)

	return found


func _source_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return found

	directory.list_dir_begin()
	var entry := directory.get_next()

	while not entry.is_empty():
		var path := "%s/%s" % [root, entry]
		if directory.current_is_dir():
			found.append_array(_source_files(path))
		elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
			found.append(path)
		entry = directory.get_next()

	directory.list_dir_end()
	return found
