extends Node3D

## Round root. Wires the arena, player, and spawner together. The extraction
## timer, win/loss resolution, and restart land on the game-loop branch.

@export var ammo_per_kill := 3

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var spawner: ZombieSpawner = $ZombieSpawner
@onready var weapon: Weapon = $Player/Head/Camera/Weapon

var kills := 0


func _ready() -> void:
	spawner.zombie_died.connect(_on_zombie_died)
	spawner.begin(arena, player)


## Kills are the only source of ammunition — the concept's central tension is
## that you cannot restock without spending what you have.
func _on_zombie_died(_death_position: Vector3) -> void:
	kills += 1
	weapon.add_reserve_ammo(ammo_per_kill)
