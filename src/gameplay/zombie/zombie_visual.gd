class_name ZombieVisual
extends Node3D

## Builds the zombie's animated body from the Kenney Animated Characters:
## Survivors pack (CC0) and drives its idle/run animations.
##
## The pack ships one rigged mesh plus separate animation files that share the
## same 58-bone skeleton. They are merged here at runtime: each animation is
## lifted out of its source scene and added to one library, so the zombie needs
## a single AnimationPlayer instead of one scene per clip.

const MODEL_PATH := "res://assets/models/characters/characterMedium.fbx"
const SKIN_PATHS := [
	"res://assets/models/characters/Skins/zombieA.png",
	"res://assets/models/characters/Skins/zombieC.png",
]

## animation name -> source scene and the clip's name inside it.
const ANIMATION_SOURCES := {
	"idle": {"scene": "res://assets/models/characters/idle.fbx", "clip": "Root|Idle"},
	"run": {"scene": "res://assets/models/characters/run.fbx", "clip": "Root|Run"},
}

## Height of the unscaled model from feet to the top of the head, in metres.
##
## Measured from the rig's bone poses rather than the mesh bounds — a skinned
## mesh reports its bind-pose AABB, which for this pack is a few centimetres
## across and tells you nothing. Everything else here is derived from this, so
## if the model is ever replaced this is the one number to re-measure.
const NATIVE_HEIGHT := 3.705

## Run animation plays above this horizontal speed.
@export var run_speed_threshold := 0.5
@export var hit_flash_duration := 0.09

@export_group("Locomotion")
## Ground speed the run animation was authored to travel at, for a model at
## NATIVE_HEIGHT. Playback is scaled against this so the feet keep up with the
## body instead of skating — the run cycle is otherwise played at a fixed rate
## no matter how fast the zombie is actually moving.
@export var run_reference_speed := 4.4
## Playback bounds, so a very fast or very slow zombie still animates legibly.
@export var min_animation_speed := 0.55
@export var max_animation_speed := 1.9

var _mesh: MeshInstance3D
var _animation_player: AnimationPlayer
var _skin_material: StandardMaterial3D
var _flash_material: StandardMaterial3D
var _current_animation := ""
var _model: Node3D
## Ratio the model is drawn at. Defaults to a plain Shambler's height so a
## zombie built without configure() is still the right size rather than the
## model's raw 3.7m.
var _kind_scale := 2.0 / NATIVE_HEIGHT
var _flash_remaining := 0.0


func _ready() -> void:
	_build_model()
	_build_materials()
	_load_animations()
	play_animation("idle")


func _process(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return

	_flash_remaining -= delta
	if _flash_remaining <= 0.0 and _mesh != null:
		_mesh.material_override = _skin_material


## Resize the body to a real height in metres, and tint it for its kind.
##
## Tint multiplies the skin rather than replacing it, so a Brute still reads as
## the same creature rather than a recoloured prop — the silhouette does the
## identifying and the colour only confirms it.
func apply_kind(target_height: float, tint: Color) -> void:
	_kind_scale = target_height / NATIVE_HEIGHT

	if _model != null:
		_model.scale = Vector3.ONE * _kind_scale

	if _skin_material != null:
		_skin_material.albedo_color = tint


## How much the model was shrunk to reach its height. The zombie uses it to
## keep the collision capsule the same size as what is actually drawn.
func get_body_scale() -> float:
	return _kind_scale


## Cut the body loose as a corpse that collapses and fades.
##
## The zombie node itself is freed immediately, so the spawner, the tests and
## the population count all keep treating death as instant. Only the body
## outlives it, reparented and inert — which avoids the alternative of keeping
## a dead zombie in the alive list and teaching every caller to skip it.
##
## Without this a zombie simply stops existing mid-stride, which is the single
## most obvious unfinished thing left in a fight.
func detach_as_corpse(collapse_time: float) -> Node3D:
	var world := get_parent().get_parent()
	if world == null or _model == null:
		return null

	var transform := global_transform

	get_parent().remove_child(self)
	world.add_child(self)
	global_transform = transform

	set_process(false)
	if _animation_player != null:
		_animation_player.pause()

	var tween := create_tween()
	tween.set_parallel(true)
	# Fall forward rather than straight down; a body that sinks through the
	# floor reads as a bug, one that topples reads as a kill.
	tween.tween_property(self, "rotation:x", -PI * 0.42, collapse_time * 0.55)
	tween.tween_property(self, "position:y", position.y - 0.45, collapse_time)
	tween.chain().tween_property(self, "scale", Vector3.ZERO, collapse_time * 0.3)
	tween.chain().tween_callback(queue_free)

	return self


## Switch animation based on how fast the zombie is actually moving, and play
## it at a rate that matches that speed.
##
## A shorter zombie covers less ground per stride, so the speed it needs to
## animate at is relative to its own size — scaling by the body scale is what
## keeps a Runner from looking like it is gliding and a Brute from looking like
## it is running on the spot.
func update_locomotion(horizontal_speed: float) -> void:
	var is_running := horizontal_speed > run_speed_threshold
	play_animation("run" if is_running else "idle")

	if _animation_player == null:
		return

	if not is_running:
		_animation_player.speed_scale = 1.0
		return

	var stride_speed: float = run_reference_speed * maxf(_kind_scale, 0.01)
	_animation_player.speed_scale = clampf(
		horizontal_speed / stride_speed, min_animation_speed, max_animation_speed
	)


func play_animation(name: String) -> void:
	if _animation_player == null or _current_animation == name:
		return
	if not _animation_player.has_animation(name):
		return

	_current_animation = name
	_animation_player.play(name)


## Briefly tint the body so a hit registers visually.
func flash() -> void:
	if _mesh == null:
		return

	_flash_remaining = hit_flash_duration
	_mesh.material_override = _flash_material


func _build_model() -> void:
	var scene: PackedScene = load(MODEL_PATH)
	if scene == null:
		push_error("ZombieVisual: could not load %s" % MODEL_PATH)
		return

	var model: Node3D = scene.instantiate()
	model.scale = Vector3.ONE * _kind_scale
	add_child(model)

	_model = model
	_mesh = _find_mesh(model)

	# The AnimationPlayer must sit beside "Root" inside the model, because the
	# imported tracks are addressed as "Root/Skeleton3D:<bone>" and resolve
	# relative to the player's parent.
	_animation_player = AnimationPlayer.new()
	model.add_child(_animation_player)


func _build_materials() -> void:
	if _mesh == null:
		return

	var skin_path: String = SKIN_PATHS[randi() % SKIN_PATHS.size()]
	var texture: Texture2D = load(skin_path)

	_skin_material = StandardMaterial3D.new()
	_skin_material.albedo_texture = texture
	_skin_material.roughness = 0.95
	# The pack's skins are flat colour atlases; filtering them softens the
	# intended low-poly look and bleeds neighbouring patches into each other.
	_skin_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color(1.0, 0.72, 0.68)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1.0, 0.3, 0.25)
	_flash_material.emission_energy_multiplier = 2.5

	_mesh.material_override = _skin_material


func _load_animations() -> void:
	if _animation_player == null:
		return

	var library := AnimationLibrary.new()

	for name in ANIMATION_SOURCES:
		var source: Dictionary = ANIMATION_SOURCES[name]
		var scene: PackedScene = load(source.scene)
		if scene == null:
			continue

		var instance: Node = scene.instantiate()
		var source_player: AnimationPlayer = instance.get_node_or_null("AnimationPlayer")

		if source_player != null and source_player.has_animation(source.clip):
			var animation: Animation = source_player.get_animation(source.clip).duplicate(true)
			animation.loop_mode = Animation.LOOP_LINEAR
			library.add_animation(name, animation)

		instance.free()

	_animation_player.add_animation_library("", library)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node

	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found

	return null
