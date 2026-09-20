class_name DeterministicSettings
extends RefCounted

## Pins the Settings autoload to known values for the duration of a test.
##
## Godot 4.7 DOES load autoloads under `--script`, contrary to the comment this
## project carried for a long time. That means every headless test silently
## inherited whatever the player last chose in the menus — difficulty, mode and
## graphics preset all persist to user://settings.cfg and are read back on
## load.
##
## The consequence was a gate that passed or failed depending on the machine it
## ran on. Setting the mode to Last Stand in the menu and then running the
## suite made verify_game_loop fail, because a Last Stand round is 300 seconds
## and kills do not shorten it, while the test was written for Extraction.
## Nothing reported the real cause; the test simply said the clock was wrong.
##
## `.claude/rules/test-standards.md` requires that tests not depend on external
## state, and the filesystem is external state.
##
## Call this BEFORE instantiating anything that reads settings — Game applies
## the mode in its _ready, which runs the moment it is added to the tree.

## The values every test assumes unless it says otherwise. Extraction because
## it is the mode the loop tests are written against; Soldier because its
## profile is the baseline the exported defaults were tuned to.
const TEST_MODE := GameSettings.Mode.EXTRACTION
const TEST_DIFFICULTY := GameSettings.Difficulty.SOLDIER


## Pin the live settings, and report whether there were any to pin.
##
## `from` is any node already inside the tree; the autoload is looked up
## through it the same way the game does.
static func apply(from: Node) -> bool:
	# Looked up as a direct child of root rather than by absolute path.
	# get_node("/root/...") is refused while the tree is not yet running, which
	# is exactly when a test needs to pin settings — before anything reads them.
	var settings: GameSettings = null
	var tree := Engine.get_main_loop() as SceneTree

	if tree != null and tree.root != null:
		settings = tree.root.get_node_or_null("Settings") as GameSettings

	if settings == null and from != null and from.is_inside_tree():
		settings = GameSettings.instance(from)

	if settings == null:
		return false

	settings.mode = TEST_MODE
	settings.difficulty = TEST_DIFFICULTY
	return true
