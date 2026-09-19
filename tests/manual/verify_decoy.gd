extends SceneTree

## Verifies the decoy: what it costs, where it lands, and that the landing is
## the thing zombies react to.
##
## The decoy is the only verb the player has for *writing* a belief rather than
## leaking one. If the throw stopped costing a round it would become free and
## the trade the mechanic exists for would vanish; if the preview stopped
## matching the flight, the player would be spending ammunition on a lie. Both
## would still look like a working throw.
##
##   Godot --headless --script tests/manual/verify_decoy.gd

const ARENA_SCENE := "res://src/arena/arena.tscn"
const WEAPON_SCENE := "res://src/gameplay/weapon/weapon.tscn"
const ZOMBIE_SCENE := "res://src/gameplay/zombie/zombie.tscn"

var _arena: Arena
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	# Hearing is a navmesh query, and the server syncs on a physics step.
	_frames += 1
	if _frames < 30:
		return false

	test_a_throw_costs_a_reserve_round()
	test_a_throw_never_touches_the_magazine()
	test_throwing_is_refused_with_an_empty_reserve()
	test_a_landing_diverts_a_zombie_to_the_landing_point()
	test_a_landing_is_quieter_than_a_gunshot()

	_report()
	return true


func test_a_throw_costs_a_reserve_round() -> void:
	# Arrange
	var weapon := _weapon()
	weapon.reserve_ammo = 10

	# Act
	var decoy: Decoy = weapon.try_throw_decoy()

	# Assert
	if decoy == null:
		_failures.append("a throw with ammunition available produced no decoy")
	elif weapon.reserve_ammo != 9:
		_failures.append(
			"a throw should have cost one reserve round, reserve went 10 -> %d"
			% weapon.reserve_ammo
		)
	else:
		print("PASS: a throw spends one round of reserve")

	if decoy != null:
		decoy.free()
	weapon.free()


func test_a_throw_never_touches_the_magazine() -> void:
	# Arrange: the magazine is what stands between the player and the thing in
	# front of them. A decoy eating it would make every throw a panic.
	var weapon := _weapon()
	weapon.reserve_ammo = 10
	weapon.magazine_ammo = 5

	# Act
	var decoy: Decoy = weapon.try_throw_decoy()

	# Assert
	if weapon.magazine_ammo != 5:
		_failures.append(
			"a throw took from the magazine (5 -> %d)" % weapon.magazine_ammo
		)
	else:
		print("PASS: a throw leaves the magazine alone")

	if decoy != null:
		decoy.free()
	weapon.free()


func test_throwing_is_refused_with_an_empty_reserve() -> void:
	# Arrange
	var weapon := _weapon()
	weapon.reserve_ammo = 0

	# Act
	var decoy: Decoy = weapon.try_throw_decoy()

	# Assert
	if decoy != null:
		_failures.append("a decoy was thrown with nothing left to throw")
		decoy.free()
	else:
		print("PASS: an empty reserve has nothing to throw")

	weapon.free()


## The whole mechanic in one assertion: a sound the player caused somewhere
## they are not, pulling a zombie to that place instead of to them.
func test_a_landing_diverts_a_zombie_to_the_landing_point() -> void:
	# Arrange: a zombie at the arena centre, a player far to the south, and a
	# landing 20m up the north corridor.
	var landing := Vector3(0.0, 0.1, 20.0)
	var player := _marker(Vector3(0.0, 0.1, -400.0))
	var zombie: Zombie = (load(ZOMBIE_SCENE) as PackedScene).instantiate()
	root.add_child(zombie)
	zombie.configure(ZombieTypes.Kind.SHAMBLER)
	zombie.global_position = Vector3(0.0, 0.1, 0.0)
	zombie.set_target(player)

	# Act: exactly what a landing does.
	var heard: bool = zombie.hear_noise(landing, 0.85)

	# Assert
	if not heard:
		_failures.append("a decoy landing 20m away was not heard")
	elif not zombie.last_known_position.is_equal_approx(landing):
		_failures.append(
			"a zombie heard the decoy but went somewhere else — it believed %v"
			% zombie.last_known_position
		)
	else:
		print("PASS: a landing pulls a zombie to the landing point, not the player")

	zombie.free()
	player.free()


func test_a_landing_is_quieter_than_a_gunshot() -> void:
	# Arrange: firing must stay the loudest thing the player can do, or the
	# safest way to move a crowd would be to shoot at nothing.
	var weapon := _weapon()

	# Act / Assert
	if weapon.decoy_loudness >= weapon.noise_loudness:
		_failures.append(
			"a decoy (%.2f) is at least as loud as a gunshot (%.2f)"
			% [weapon.decoy_loudness, weapon.noise_loudness]
		)
	else:
		print("PASS: a decoy carries less far than a shot (%.2f vs %.2f)" % [
			weapon.decoy_loudness, weapon.noise_loudness
		])

	weapon.free()


func _weapon() -> Weapon:
	var weapon: Weapon = (load(WEAPON_SCENE) as PackedScene).instantiate()
	root.add_child(weapon)
	return weapon


func _marker(at: Vector3) -> Node3D:
	var marker := Node3D.new()
	root.add_child(marker)
	marker.global_position = at
	return marker


func _report() -> void:
	if _arena != null and is_instance_valid(_arena):
		root.remove_child(_arena)
		_arena.free()
		_arena = null

	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
