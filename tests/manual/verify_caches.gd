extends SceneTree

## Verifies the resupply caches: what they give, that they run dry, and that
## they come back.
##
## The recharge is the part worth guarding. A cache that never refills turns
## the map into a checklist you clear once; a cache that refills instantly
## removes the reason to ever leave it. Either failure still looks like a
## working crate.
##
##   Godot --headless --script tests/manual/verify_caches.gd

const ARENA_SCENE := "res://src/arena/arena.tscn"

var _arena: Arena
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	_arena.bake_navigation = false
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	test_arena_places_a_cache_in_every_declared_chamber()
	test_a_cache_builds_a_crate_and_a_light()
	test_caches_are_outside_the_central_arena()
	test_a_cache_gives_its_stock_once_then_runs_dry()
	test_a_drained_cache_refills_after_its_recharge()
	test_reset_refills_a_drained_cache()

	_report()
	return true


func test_arena_places_a_cache_in_every_declared_chamber() -> void:
	# Arrange / Act
	var placed := _arena.ammo_caches.size()

	# Assert
	if placed != Arena.CACHE_CELLS.size():
		_failures.append("declared %d caches but placed %d" % [
			Arena.CACHE_CELLS.size(), placed
		])
	else:
		print("PASS: all %d caches placed" % placed)


## The crate and the light are both built in code from a hard-coded path, and
## a wrong path fails silently — you get an invisible cache that still works,
## which is the worst of both. The light doubles as the readout for whether
## there is anything to collect, so an absent one is not cosmetic.
func test_a_cache_builds_a_crate_and_a_light() -> void:
	# Arrange
	var cache: AmmoCache = _arena.ammo_caches[0]

	# Act
	var has_mesh := _find_mesh(cache) != null
	var has_light := _find_light(cache) != null

	# Assert
	if not has_mesh:
		_failures.append("a cache rendered no crate — the model path is wrong")
	elif not has_light:
		_failures.append("a cache has no light, so its stock cannot be read")
	else:
		print("PASS: a cache builds both its crate and its light")


func test_caches_are_outside_the_central_arena() -> void:
	# Arrange: the central room spans roughly 17m across its centre. A cache
	# inside it would be reachable without ever leaving the ground the player
	# is already holding, which defeats the point of having them.
	var too_close: Array[String] = []

	for cache in _arena.ammo_caches:
		var flat := Vector2(cache.position.x, cache.position.z)
		if flat.length() < 12.0:
			too_close.append("a cache sits %.1fm from the centre" % flat.length())

	# Assert
	if too_close.is_empty():
		print("PASS: every cache is outside the central arena")
	else:
		_failures.append_array(too_close)


func test_a_cache_gives_its_stock_once_then_runs_dry() -> void:
	# Arrange
	var cache: AmmoCache = _arena.ammo_caches[0]
	cache.reset()
	var received := [0]
	cache.collected.connect(func(rounds: int) -> void: received[0] += rounds)

	# Act: two collections back to back.
	cache._collect()
	var stock_after_first: int = cache.stock()
	cache._collect()

	# Assert
	if received[0] != cache.capacity:
		_failures.append(
			"a cache handed out %d rounds across two collections, expected %d"
			% [received[0], cache.capacity]
		)
	elif stock_after_first != 0:
		_failures.append("a collected cache still held %d rounds" % stock_after_first)
	else:
		print("PASS: a cache gives %d rounds once, then is empty" % cache.capacity)


func test_a_drained_cache_refills_after_its_recharge() -> void:
	# Arrange
	var cache: AmmoCache = _arena.ammo_caches[1]
	cache.reset()
	cache._collect()

	# Act: not yet, then past the recharge.
	cache._process(cache.recharge_seconds * 0.5)
	var midway := cache.has_stock()
	cache._process(cache.recharge_seconds)

	# Assert
	if midway:
		_failures.append("a cache refilled halfway through its recharge")
	elif not cache.has_stock():
		_failures.append("a cache never refilled — the map becomes a checklist")
	else:
		print("PASS: a drained cache refills only after its full recharge")


func test_reset_refills_a_drained_cache() -> void:
	# Arrange: restart must not hand the next round the caches this one drained.
	var cache: AmmoCache = _arena.ammo_caches[2]
	cache._collect()

	# Act
	cache.reset()

	# Assert
	if cache.stock() != cache.capacity:
		_failures.append(
			"restart left a cache holding %d of %d rounds"
			% [cache.stock(), cache.capacity]
		)
	else:
		print("PASS: restart refills every cache")


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node

	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found

	return null


func _find_light(node: Node) -> OmniLight3D:
	if node is OmniLight3D:
		return node

	for child in node.get_children():
		var found := _find_light(child)
		if found != null:
			return found

	return null


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
