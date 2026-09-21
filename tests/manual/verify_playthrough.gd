extends SceneTree

## Walks the whole game the way a player does: main menu, into a round, win it,
## read the results, and back out to the menu.
##
## Every one of these steps is already covered on its own — verify_menus.gd
## opens and closes screens, verify_game_loop.gd wins and loses rounds — but
## nothing had ever crossed a scene boundary. That is where a game of this shape
## breaks: change_scene_to_file frees the old tree and builds a new one, and any
## system holding a reference across that line, or any autoload carrying state
## it should have dropped, survives every isolated test and fails the first time
## somebody actually plays twice in a row.
##
## The assertion that matters most is the last one: going back to the menu and
## starting again has to produce a genuinely fresh round, not the previous one
## with its clock reset.
##
##   Godot --headless --script tests/manual/verify_playthrough.gd

const MENU_SCENE := "res://src/ui/main_menu.tscn"
const GAME_SCENE := "res://src/core/game.tscn"

## change_scene_to_file is deferred, so the swap lands on a later frame.
const SETTLE_FRAMES := 3

enum Step {
	OPEN_MENU, ENTER_GAME, PLAY, WIN, READ_RESULTS, BACK_TO_MENU, PLAY_AGAIN, DONE
}

var _step: int = Step.OPEN_MENU
var _waited := 0
var _failures: Array[String] = []
var _first_round_kills := -1


func _initialize() -> void:
	# The menu is loaded as an ordinary scene rather than through the project's
	# main-scene setting, which --script does not apply.
	get_root().add_child(load(MENU_SCENE).instantiate())


func _process(_delta: float) -> bool:
	# Every step gives the tree a few frames, because a scene change is
	# deferred and a round needs its arena and navmesh built before it is real.
	_waited += 1
	if _waited < SETTLE_FRAMES:
		return false
	_waited = 0

	match _step:
		Step.OPEN_MENU:
			test_playthrough_the_menu_opens()
			DeterministicSettings.apply(get_root())

		Step.ENTER_GAME:
			change_scene_to_file(GAME_SCENE)

		Step.PLAY:
			test_playthrough_a_round_starts_from_the_menu()

		Step.WIN:
			_win_the_round()

		Step.READ_RESULTS:
			test_playthrough_winning_ends_the_round()

		Step.BACK_TO_MENU:
			change_scene_to_file(MENU_SCENE)

		Step.PLAY_AGAIN:
			test_playthrough_returning_to_the_menu_leaves_it_usable()
			change_scene_to_file(GAME_SCENE)

		Step.DONE:
			test_playthrough_a_second_round_is_genuinely_fresh()
			_report()
			return true

	_step += 1
	return false


func test_playthrough_the_menu_opens() -> void:
	# Arrange / Act
	var menu := _find(get_root(), "MainMenu")

	# Assert
	if menu == null:
		_failures.append("the main menu scene did not produce a MainMenu node")
	else:
		print("PASS: the main menu opens")


func test_playthrough_a_round_starts_from_the_menu() -> void:
	# Arrange / Act
	var game := _game()

	# Assert
	if game == null:
		_failures.append("entering the game from the menu produced no Game node")
		return

	game.start_round()

	if game.player == null or game.arena == null:
		_failures.append("the round started without a player or an arena")
	else:
		print("PASS: a round starts, with a player and a built arena")


## Win the way the extraction mode is won — by running the clock out.
func _win_the_round() -> void:
	var game := _game()
	if game == null:
		return

	_first_round_kills = game.kills
	game.time_remaining = 0.0


func test_playthrough_winning_ends_the_round() -> void:
	# Arrange / Act
	var game := _game()
	if game == null:
		_failures.append("the game vanished before the round could end")
		return

	# Assert
	if game.state == game.RoundState.PLAYING:
		_failures.append("the extraction clock reached zero and the round kept running")
	else:
		print("PASS: the round ends and a results state is reached")


func test_playthrough_returning_to_the_menu_leaves_it_usable() -> void:
	# Arrange / Act
	var menu := _find(get_root(), "MainMenu")
	var game := _game()

	# Assert
	if menu == null:
		_failures.append("leaving a finished round did not get back to the menu")
	elif game != null:
		_failures.append("the finished game survived the return to the menu")
	else:
		print("PASS: a finished round can be left, and the menu is there to leave to")


## The one that isolated tests cannot catch: a second round has to be a new
## round, not the old one with its counters reset.
func test_playthrough_a_second_round_is_genuinely_fresh() -> void:
	# Arrange / Act
	var game := _game()
	if game == null:
		_failures.append("a second round could not be started from the menu")
		return

	game.start_round()

	# Assert
	if game.state != game.RoundState.PLAYING:
		_failures.append("the second round did not reach a playing state")
	elif game.kills != 0:
		_failures.append(
			"the second round began with %d kills carried over from the first"
			% game.kills
		)
	elif game.spawner.get_alive_count() > 0:
		_failures.append(
			"the second round began with %d zombies left over"
			% game.spawner.get_alive_count()
		)
	else:
		print("PASS: a second round is fresh — no kills or zombies carried over")


## --- Helpers ----------------------------------------------------------------


func _game() -> Game:
	var found := _find(get_root(), "Game")
	return found as Game


func _find(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node

	for child in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found

	return null


func _report() -> void:
	if _failures.is_empty():
		print("playthrough: menu to round to results to menu and back in")
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
