extends SceneTree

## Verifies cave acoustics: that a wall between the listener and a sound
## occludes it, that a clear line of sight does not, and that the SFX bus
## carries exactly one reverb no matter how many times buses are (re-)built.
##
## The whole feature rests on one claim — "a zombie on the other side of a
## wall sounds muffled, not silenced, not clean" — and the only way to prove
## the ray is doing that rather than nothing at all is to put a real wall in
## a real physics world and ask it.
##
##   Godot --headless --script tests/manual/verify_acoustics.gd

const WORLD_LAYER := 1

var _sounds: SoundBank
var _camera: Camera3D
var _point_a: Vector3
var _point_b: Vector3
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	DeterministicSettings.apply(root)

	# Floor: static geometry on the world layer, kept below the ray height
	# (y = 1) so it never itself occludes the horizontal test rays.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = WORLD_LAYER
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0, -0.5, 0)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 1, 20)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)

	# Camera stands in for the listener, same as SoundBank._listener_camera
	# uses get_viewport().get_camera_3d() in the real game.
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1, 0)
	root.add_child(_camera)
	_camera.current = true

	# A wall between the camera and point A only. Point B sits to the side
	# with nothing in the way.
	_point_a = Vector3(0, 1, 5)
	_point_b = Vector3(5, 1, 0)

	var wall_body := StaticBody3D.new()
	wall_body.collision_layer = WORLD_LAYER
	wall_body.collision_mask = 0
	wall_body.position = Vector3(0, 1, 2.5)
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(2, 2, 0.5)
	wall_shape.shape = wall_box
	wall_body.add_child(wall_shape)
	root.add_child(wall_body)

	_sounds = SoundBank.new()
	root.add_child(_sounds)


func _process(_delta: float) -> bool:
	# Give the physics server a couple of steps to register the colliders
	# before a ray is cast against them.
	_frames += 1
	if _frames < 5:
		return false

	test_a_wall_between_camera_and_point_occludes_it()
	test_a_clear_line_of_sight_is_not_occluded()
	test_ensure_buses_adds_exactly_one_reverb_to_the_sfx_bus()
	test_every_sound_event_loads_a_clip()

	_report()
	return true


func test_a_wall_between_camera_and_point_occludes_it() -> void:
	# Arrange: _point_a, set up in _initialize, has the wall between it and
	# the camera.

	# Act
	var occluded := _sounds.is_occluded(_camera.global_position, _point_a)

	# Assert
	if occluded:
		print("PASS: a wall between the listener and a sound occludes it")
	else:
		_failures.append(
			"point A sits behind a wall from the camera but is_occluded "
			+ "reported false"
		)


func test_a_clear_line_of_sight_is_not_occluded() -> void:
	# Arrange: _point_b, set up in _initialize, has nothing between it and
	# the camera.

	# Act
	var occluded := _sounds.is_occluded(_camera.global_position, _point_b)

	# Assert
	if not occluded:
		print("PASS: a clear line of sight is not occluded")
	else:
		_failures.append(
			"point B has a clear line of sight to the camera but "
			+ "is_occluded reported true"
		)


func test_ensure_buses_adds_exactly_one_reverb_to_the_sfx_bus() -> void:
	# Arrange / Act: called twice, deliberately, to prove idempotency — the
	# real game calls this on every scene boot and every settings apply.
	GameSettings.ensure_buses()
	GameSettings.ensure_buses()

	# Assert
	var sfx_index := AudioServer.get_bus_index(GameSettings.SFX_BUS)
	if sfx_index < 0:
		_failures.append("ensure_buses did not create the SFX bus")
		return

	var reverb_count := 0
	for i in AudioServer.get_bus_effect_count(sfx_index):
		if AudioServer.get_bus_effect(sfx_index, i) is AudioEffectReverb:
			reverb_count += 1

	if reverb_count == 1:
		print("PASS: the SFX bus carries exactly one reverb after two calls")
	else:
		_failures.append(
			"expected exactly one AudioEffectReverb on the SFX bus after "
			+ "calling ensure_buses twice, found %d" % reverb_count
		)


## A renamed or missing file does not crash: the event just goes silent, and
## nobody notices a phantom that never plays. Every event in every table must
## resolve to at least one stream.
func test_every_sound_event_loads_a_clip() -> void:
	var silent: Array[String] = []
	for table in [SoundBank.EVENTS, SoundBank.GENERATED_EVENTS, SoundBank.SOURCED_EVENTS]:
		for event in table:
			if _sounds._pick(event) == null:
				silent.append(event)

	if silent.is_empty():
		print("PASS: every sound event loads at least one clip")
	else:
		_failures.append("events with no loadable clip: %s" % ", ".join(silent))


func _report() -> void:
	if _sounds != null and is_instance_valid(_sounds):
		root.remove_child(_sounds)
		_sounds.free()
		_sounds = null

	if _failures.is_empty():
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
