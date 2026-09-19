extends Node3D

## Root scene. Owns nothing yet — arena, player, and game loop are added on
## their own branches. Exists so the project has a runnable main scene.

func _ready() -> void:
	print("LAST MAGAZINE — boot OK (Godot %s)" % Engine.get_version_info().string)
