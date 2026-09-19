extends Node3D

## Round root. Will own the extraction timer, win/loss resolution, and restart
## once those land on their own branches. For now it just holds the arena and
## the player together.

@onready var arena: Arena = $Arena
@onready var player: Player = $Player


func _ready() -> void:
	print("LAST MAGAZINE — round start (Godot %s)" % Engine.get_version_info().string)
