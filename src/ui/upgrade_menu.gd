class_name UpgradeMenu
extends CanvasLayer

## Level-up choice. Pauses the round and offers three upgrades.
##
## Pausing is deliberate. Picking an upgrade while a crowd closes on you is not
## a decision, it is a reflex — and the whole point of the choice is that the
## player weighs it.

signal chosen(upgrade_id: int)

@export var number_keys := [KEY_1, KEY_2, KEY_3]
@export var card_size := Vector2(262, 210)

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


## Build a card per choice.
##
## Laid out rather than crammed into a button's label: the number, name and
## effect need different weights and colours to be readable at a glance, and a
## level-up is meant to feel like a reward rather than a dialogue box. The
## button underneath stays invisible and does the input.
func _build_cards() -> void:
	for child in _cards.get_children():
		child.queue_free()

	for index in _choices.size():
		_cards.add_child(_build_card(_choices[index], index))


func _build_card(choice: Dictionary, index: int) -> Control:
	var card := Button.new()
	card.custom_minimum_size = card_size
	card.focus_mode = Control.FOCUS_ALL
	card.pressed.connect(_pick.bind(index))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Let clicks fall through to the button underneath.
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_label(
		"%d" % (index + 1), 30, Color(0.878, 0.631, 0.235, 0.85)
	))
	column.add_child(_rule())

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	column.add_child(spacer)

	column.add_child(_label(choice.name, 22, Color(0.957, 0.949, 0.933)))

	var detail := _label(choice.detail, 15, Color(0.6, 0.63, 0.7))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(detail)

	return card


func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(0.878, 0.631, 0.235, 0.45)
	rule.custom_minimum_size = Vector2(46, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


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
