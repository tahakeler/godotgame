class_name UpgradeMenu
extends CanvasLayer

## Level-up choice. Pauses the round and offers three upgrades.
##
## Pausing is deliberate. Picking an upgrade while a crowd closes on you is not
## a decision, it is a reflex — and the whole point of the choice is that the
## player weighs it.

signal chosen(upgrade_id: int)

@export var number_keys := [KEY_1, KEY_2, KEY_3]

@onready var _root: Control = %Root
@onready var _cards: HBoxContainer = %Cards
@onready var _level_label: Label = %LevelLabel

var _open := false
var _choices: Array[Dictionary] = []


func _ready() -> void:
	# Must keep processing while the tree is paused, or it cannot take the
	# input that closes it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return

	var index: int = number_keys.find(event.keycode)
	if index >= 0 and index < _choices.size():
		_pick(index)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func open(level: int, choices: Array[Dictionary]) -> void:
	_choices = choices
	_open = true
	_root.visible = true

	_level_label.text = "LEVEL %d" % level
	_build_cards()

	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if _cards.get_child_count() > 0:
		(_cards.get_child(0) as Button).grab_focus()


func _build_cards() -> void:
	for child in _cards.get_children():
		child.queue_free()

	for index in _choices.size():
		var choice := _choices[index]
		var card := Button.new()
		card.custom_minimum_size = Vector2(260, 190)
		card.focus_mode = Control.FOCUS_ALL
		card.text = "%d\n\n%s\n\n%s" % [index + 1, choice.name, choice.detail]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(_pick.bind(index))
		_cards.add_child(card)


## Dismiss without choosing. Used when a round restarts underneath the screen —
## leaving it up would strand the player behind a modal with the tree paused.
func close() -> void:
	if not _open:
		return

	_open = false
	_root.visible = false
	get_tree().paused = false


func _pick(index: int) -> void:
	if not _open or index < 0 or index >= _choices.size():
		return

	var upgrade_id: int = _choices[index].id
	close()
	chosen.emit(upgrade_id)
