class_name CreditsPanel
extends Control

## In-game attribution for everything this project did not make itself.
##
## CC0 waives the requirement to credit, so none of this is legally owed. It is
## here because a published game that ships someone else's art without naming
## them is a worse game to have made, and because a credits screen that only
## exists in the repository is not a credits screen a player can read.
##
## The entries live in a table rather than in the scene so that adding a pack
## is one line and cannot leave the layout half-updated.

signal closed()

const ENGINE_LINE := "Built with Godot Engine 4.7 — MIT Licence"

## Every third-party pack, with what it is actually used for. "Used for" is
## specific on purpose: a list of names tells a reader nothing about what the
## work contributed.
const ASSET_PACKS := [
	{
		"name": "Modular Cave Kit",
		"licence": "CC0 1.0",
		"used": "The entire play space — chambers, corridors, raised decks and the rock used as cover",
	},
	{
		"name": "Blaster Kit",
		"licence": "CC0 1.0",
		"used": "The weapon viewmodel and the cases scattered across the floor",
	},
	{
		"name": "RPG Audio",
		"licence": "CC0 1.0",
		"used": "Reloads, impacts, footsteps, zombie groans and the round results",
	},
	{
		"name": "Animated Characters: Survivors",
		"licence": "CC0 1.0",
		"used": "The zombies — rigged mesh, skins, and the idle and run animations",
	},
	{
		"name": "Ancient Caverns and A Lurking Evil — by congusbongus (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "The low drone under exploration and the tense bed when something is near",
	},
	{
		"name": "Dark Cavern Ambient — by Paul Wortmann (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "The second exploration bed",
	},
	{
		"name": "Cave In — by StarNinjas (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "Rock falling somewhere you cannot see",
	},
	{
		"name": "Heartbeat Sounds — by bart (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "The heartbeat",
	},
	{
		"name": "Female High Pitched Scream SFX — by WuxiaScrub (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "A far-off call, dragged down in pitch past recognition",
	},
	{
		"name": "Wolf Monster Sound — by CaveboyTup (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "A howl from deep in the tunnels",
	},
	{
		"name": "Metal Impact Sounds — by BMacZero (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "Metal the labyrinth moves on its own",
	},
	{
		"name": "Footsteps — by GboxMikeFozzy (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "Footsteps behind you that are not yours",
	},
	{
		"name": "Dark Stinger 1 — by Kresiek The Furry (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "The swell when a long quiet finally breaks",
	},
	{
		"name": "Horror Breathing — by primbal (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "Breathing you should not be hearing",
	},
	{
		"name": "Water Drops — by ceoxblackj (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "Water dripping somewhere in the cave",
	},
	{
		"name": "Breaking Rock and Moving Boulder — by themightyglider (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "Rocks breaking and stones dropping in the dark",
	},
	{
		"name": "Horror Hit Soundpack 1 — by psychhead (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "The low hit when something finds you up close",
	},
	{
		"name": "Undead Moans — by antumdeluge (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "A moan from somewhere far away",
	},
	{
		"name": "Ghost/Monster Voice — by qubodup (OpenGameArt)",
		"licence": "CC0 1.0",
		"used": "Something calling that is not a person",
	},
]

## Things made for this project rather than brought in.
const ORIGINAL_WORK := [
	"All game code, scenes, UI and the arena layout",
	"The gunshot and the Brute's growl, synthesised by tools/generate_audio.gd",
	"All lighting, materials and environment setup",
]

@onready var _entries: VBoxContainer = %Entries
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: closed.emit())
	_build()


func focus_first_control() -> void:
	_back_button.grab_focus()


func _build() -> void:
	for child in _entries.get_children():
		child.queue_free()

	_add_heading("A S S E T S")
	_add_body(
		"Most art and audio is by Kenney (kenney.nl) under CC0 1.0. The listed "
		+ "sounds and music are CC0 works by the authors named."
	)

	for pack in ASSET_PACKS:
		_add_pack(pack)

	_add_spacer(18)
	_add_heading("M A D E   F O R   T H I S   P R O J E C T")
	for line in ORIGINAL_WORK:
		_add_body("·  %s" % line)

	_add_spacer(18)
	_add_heading("E N G I N E")
	_add_body(ENGINE_LINE)

	_add_spacer(18)
	_add_heading("A S S I S T A N C E")
	_add_body(
		"Parts of this project were written with Claude Code acting as an AI "
		+ "assistant. The specific features it authored are listed in "
		+ "docs/ai-contribution.md."
	)


func _add_pack(pack: Dictionary) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = "%s  ·  %s" % [pack.name, pack.licence]
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.957, 0.949, 0.933))
	row.add_child(title)

	var used := Label.new()
	used.text = pack.used
	used.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	used.add_theme_font_size_override("font_size", 14)
	used.add_theme_color_override("font_color", Color(0.514, 0.541, 0.588))
	row.add_child(used)

	_entries.add_child(row)
	_add_spacer(10)


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.878, 0.631, 0.235))
	_entries.add_child(label)
	_add_spacer(6)


func _add_body(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.792, 0.808, 0.839))
	_entries.add_child(label)
	_add_spacer(8)


func _add_spacer(height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	_entries.add_child(spacer)
