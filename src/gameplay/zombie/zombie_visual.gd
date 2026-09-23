class_name ZombieVisual
extends Node3D

## The zombie's animated body: one of the three bodies from the owner's zombie
## pack (normal, heavy, runner; MakeHuman CC0 sources), driven by the
## zombie's real movement and fight.
##
## All three bodies share one 163-bone MakeHuman skeleton with identical bone
## names, so any clip can drive any body once its track paths are pointed at
## that body's rig. That is what lets every body borrow the runner's Run: the
## pack's walks are authored at 0.5-0.9 m/s, and the game's hunters close at
## 2-6 m/s. Played at game speed a walk cycle has to run nearly four times
## over and reads as frantic; the run, borrowed and slowed, reads as a body
## committing to the chase.
##
## Clips per body are built once and shared by every instance of that body,
## so a crowd of twenty costs three libraries, not twenty.
##
## The zombie never touches the model. It reports what happened (moved at
## this speed, wound up an attack, got staggered, noticed you, died) and this
## decides what that looks like.

## body name -> glb, rig node name, and the model's height in metres (mesh
## bounds, feet to crown, measured on import). The rig name is what the
## animation tracks are addressed through ("<Rig>/Skeleton3D:<bone>").
const BODIES := {
	"normal": {
		"scene": "res://assets/models/zombies/normal.glb",
		"rig": "Normal_Rig",
		"height": 1.75,
		# m/s the pack's Walk clip travels at playback 1.0, at native height.
		"walk_speed": 0.855,
		# How far the walk may be sped up before handing over to the run.
		"max_walk_rate": 1.8,
	},
	"heavy": {
		"scene": "res://assets/models/zombies/heavy.glb",
		"rig": "Heavy_Rig",
		"height": 1.825,
		"walk_speed": 0.532,
		# The heavy's wide lumbering walk carries further before it breaks
		# into a run: a Brute that jogs loses the weight the body was built for.
		"max_walk_rate": 2.9,
	},
	"runner": {
		"scene": "res://assets/models/zombies/runner.glb",
		"rig": "Runner_Rig",
		"height": 1.68,
		"walk_speed": 0.855,
		"max_walk_rate": 1.6,
	},
}

## The runner owns the only Run clip; every body borrows it from here.
const RUN_SOURCE_BODY := "runner"
## m/s the Run clip travels at playback 1.0, at the runner's native height.
const RUN_SPEED := 2.86
const LOOPED_CLIPS := ["Idle", "Walk", "Run"]
## Hidden: a mouthful of geometry (16k vertices, 22% of the body) that sits
## behind closed lips at every distance the game is played at.
const HIDDEN_MESH_SUFFIXES := ["teeth_base"]
## The eyes carry the awareness tell. A face in an unlit corridor is not
## readable, two points of light at head height are.
const EYE_MESH_SUFFIX := "high-poly"
## Where in the Attack clips the blow connects (the pack authors every attack
## with its strike at 48% of the clip).
const STRIKE_FRACTION := 0.48

## Below this ground speed the body idles.
@export var idle_speed := 0.25
@export var hit_flash_duration := 0.09

@export_group("Locomotion")
## Playback bounds, so a very fast or very slow zombie still animates legibly.
@export var min_animation_speed := 0.5
@export var max_animation_speed := 1.9
## Crossfade between locomotion clips, seconds.
@export var locomotion_blend := 0.22

@export_group("Reactions")
## How long past the stagger the hit reaction holds before movement resumes.
@export var hit_tail := 0.25
## Standing still at least this slowly, a zombie that notices you rears up.
## Faster than this and the alert would slide it along the floor.
@export var alert_max_speed := 0.6
## Seconds of the strike clip allowed after the blow before it blends out.
@export var attack_recovery := 0.35

@export_group("Corpse")
## Seconds the finished death pose lies there before it sinks away.
@export var corpse_hold := 3.0
@export var corpse_sink_depth := 0.6
@export var corpse_sink_time := 1.4

@export_group("Glow")
## Multiplies the awareness tell's energy on the eyes, which are small; the
## energies the zombie sends were tuned for a whole glowing body.
@export var eye_glow_scale := 6.0

@export_group("Performance")
## Beyond this distance the body is not drawn at all. The fog has swallowed
## it long before, and a crowd past it is the largest single render cost.
@export var draw_distance := 42.0

## body name -> shared AnimationLibrary, built on first use.
static var _libraries = null

var _body := ""
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _eye_meshes: Array[MeshInstance3D] = []
var _animation_player: AnimationPlayer
var _current_animation := ""
var _kind_scale := 1.0
var _body_height := 1.75
var _target_height := 2.0
var _tint := Color.WHITE
var _walk_speed := 0.855
var _max_walk_rate := 1.8
var _last_speed := 0.0
var _gait_offset := 0.0
var _flash_remaining := 0.0
## A one-shot (attack, hit, alert, death) owns the body until it runs out;
## locomotion only records speed meanwhile.
var _one_shot := ""
var _one_shot_remaining := 0.0
var _attack_index := 0
var _is_corpse := false

var _glow_colour := Color.BLACK
var _glow_energy := 0.0
## Per-instance eye material carrying the awareness tell.
var _eye_material: StandardMaterial3D
## Physical flinch on the skeleton, layered over whatever clip is playing.
var _hit_react: HitReactModifier
static var _flash_material: StandardMaterial3D
## Live bodies sharing the static caches. When the last one leaves the tree the
## caches are dropped, so shared materials and clips do not outlive the scene
## (and are not reported as leaks at exit).
static var _live_bodies := 0


func _enter_tree() -> void:
	_live_bodies += 1


func _exit_tree() -> void:
	_live_bodies -= 1
	if _live_bodies <= 0:
		_live_bodies = 0
		# Null rather than cleared: an empty Dictionary still holds pooled
		# memory, and scripts outlive the tree at exit.
		_libraries = null
		_tinted = null
		_flash_material = null


func _ready() -> void:
	# A zombie is configured straight after it is added; build the default
	# body only if nothing asked for a specific one by the end of the frame.
	_ensure_body.call_deferred()


func _process(delta: float) -> void:
	if _flash_remaining > 0.0:
		_flash_remaining -= delta
		if _flash_remaining <= 0.0:
			_set_overlay(null)

	if _one_shot_remaining > 0.0:
		_one_shot_remaining -= delta
		if _one_shot_remaining <= 0.0 and not _is_corpse:
			_one_shot = ""
			_current_animation = ""
			update_locomotion(_last_speed)


## Choose the body and size it for a kind, and tint it.
##
## Tint multiplies the textures rather than replacing them, so a Stalker is a
## darker version of a body you already know rather than a recoloured prop.
func apply_kind(target_height: float, tint: Color, body := "normal") -> void:
	_target_height = target_height
	_tint = tint

	if not BODIES.has(body):
		body = "normal"
	if body != _body:
		_build_body(body)

	_apply_scale()
	_apply_tint()


## How much the model was scaled to reach its height. The zombie uses it to
## keep the collision capsule the same size as what is actually drawn.
func get_body_scale() -> float:
	return _kind_scale


## Which of the pack's bodies this zombie wears.
func body_name() -> String:
	return _body


## Set this instance's gait phase, as a fraction (0-1) into the loop, so a
## crowd that starts moving on the same frame does not step in unison.
func set_gait_offset(fraction: float) -> void:
	_gait_offset = clampf(fraction, 0.0, 1.0)


## Light the eyes, to show what this zombie knows. The zombie decides the
## colour; this only paints it. Survives hit flashes, which use the overlay.
func apply_glow(colour: Color, energy: float) -> void:
	_glow_colour = colour
	_glow_energy = energy
	_apply_glow()


## The awareness tell as currently painted. Public so tests can check the
## state survives a flash without reaching into materials.
func glow_energy() -> float:
	return _glow_energy


func glow_colour() -> Color:
	return _glow_colour


## Switch between idle, walk and run for how fast the zombie is actually
## moving, and play the clip at the rate that keeps the feet under the body.
func update_locomotion(horizontal_speed: float) -> void:
	_last_speed = horizontal_speed
	if _animation_player == null or _one_shot != "" or _is_corpse:
		return

	if horizontal_speed < idle_speed:
		_play_loop("Idle", 1.0)
		return

	var walk_stride := _walk_speed * _kind_scale
	var walk_rate := horizontal_speed / maxf(walk_stride, 0.01)
	if walk_rate <= _max_walk_rate or not _animation_player.has_animation("Run"):
		_play_loop("Walk", clampf(walk_rate, min_animation_speed, _max_walk_rate))
		return

	var run_stride := RUN_SPEED * (_kind_scale * _body_height / BODIES[RUN_SOURCE_BODY].height)
	_play_loop("Run", clampf(
		horizontal_speed / maxf(run_stride, 0.01), min_animation_speed, max_animation_speed
	))


## The wind-up has started; strike in `windup` seconds. The clip is timed so
## its blow lands as the lunge fires, which is when the hit can connect.
## Returns how long the attack owns the body.
func play_attack(windup: float) -> float:
	var clip := "Attack" if _attack_index % 2 == 0 else "Attack2"
	_attack_index += 1
	if not _has(clip):
		clip = "Attack"
	if not _has(clip):
		return 0.0

	var length := _animation_player.get_animation(clip).length
	var rate := clampf((STRIKE_FRACTION * length) / maxf(windup + 0.08, 0.05), 0.8, 3.0)
	var hold := windup + attack_recovery
	return _play_one_shot(clip, rate, hold, 0.12)


## Flinch for a stagger of `stagger` seconds. Cancels a wind-up, which is
## what the stagger does to the attack too.
func play_hit(stagger: float) -> void:
	if not _has("Hit") or _one_shot == "Death":
		return
	var length := _animation_player.get_animation("Hit").length
	var hold := stagger + hit_tail
	_play_one_shot("Hit", clampf(length / maxf(hold, 0.2), 1.0, 2.6), hold, 0.08)


## Rear up on noticing the player, if standing still enough not to slide.
## `duration` <= 0 plays the clip once through (a Screamer's inhale passes
## its own wind-up so the rear lasts exactly as long as the breath).
func play_alert(duration := 0.0) -> void:
	if not _has("Alert") or _one_shot != "":
		return
	if duration <= 0.0 and _last_speed > alert_max_speed:
		return
	var length := _animation_player.get_animation("Alert").length
	var hold := duration if duration > 0.0 else length / 1.2
	_play_one_shot("Alert", clampf(length / maxf(hold, 0.2), 0.6, 2.0), hold, 0.15)


## Knock the torso the way the round was travelling. `strength` 0..1.
func react_to_hit(direction: Vector3, strength: float) -> void:
	if _hit_react != null and not _is_corpse:
		_hit_react.react(direction, strength)


## Briefly overlay a hot colour so a hit registers visually.
func flash() -> void:
	if _meshes.is_empty():
		return
	_flash_remaining = hit_flash_duration
	_set_overlay(_get_flash_material())


## Cut the body loose as a corpse that plays its death, lies still, then sinks.
##
## The zombie node itself is freed immediately, so the spawner, the tests and
## the population count all keep treating death as instant. Only the body
## outlives it, reparented and inert.
func detach_as_corpse(collapse_time: float) -> Node3D:
	var world := get_parent().get_parent() if get_parent() != null else null
	if world == null or _model == null:
		return null

	var transform := global_transform
	get_parent().remove_child(self)
	world.add_child(self)
	global_transform = transform

	_is_corpse = true
	_flash_remaining = 0.0
	_set_overlay(null)
	apply_glow(Color.BLACK, 0.0)

	var fall_time := collapse_time
	if _has("Death"):
		var length := _animation_player.get_animation("Death").length
		_one_shot = "Death"
		_animation_player.speed_scale = 1.15
		_animation_player.play("Death", 0.1)
		_current_animation = "Death"
		fall_time = length / 1.15
	else:
		var topple := create_tween()
		topple.tween_property(self, "rotation:x", -PI * 0.42, collapse_time * 0.55)

	var tween := create_tween()
	tween.tween_interval(fall_time + corpse_hold)
	# Stop animating the settled pose before the sink: a still body costs
	# nothing to pose, a playing one costs a skeleton update a frame.
	tween.tween_callback(func() -> void:
		if _animation_player != null:
			_animation_player.pause()
	)
	tween.tween_property(self, "position:y", position.y - corpse_sink_depth, corpse_sink_time)
	tween.tween_callback(queue_free)
	return self


func play_animation(clip: String) -> void:
	_play_loop(clip, 1.0)


func _play_loop(clip: String, rate: float) -> void:
	if _animation_player == null:
		return
	_animation_player.speed_scale = rate
	if _current_animation == clip:
		return
	if not _has(clip):
		return

	var restarting := _current_animation == ""
	_current_animation = clip
	_animation_player.play(clip, locomotion_blend)
	# Phase offset only when a loop starts from nothing, so a crowd released
	# together does not step in unison; a blend between loops keeps its phase.
	if restarting or clip == "Idle":
		var length := _animation_player.current_animation_length
		if length > 0.0:
			_animation_player.seek(_gait_offset * length, true)


func _play_one_shot(clip: String, rate: float, hold: float, blend: float) -> float:
	if _animation_player == null or _is_corpse:
		return 0.0
	_one_shot = clip
	_one_shot_remaining = hold
	_current_animation = clip
	_animation_player.speed_scale = rate
	_animation_player.play(clip, blend)
	_animation_player.seek(0.0, true)
	return hold


func _has(clip: String) -> bool:
	return _animation_player != null and _animation_player.has_animation(clip)


func _ensure_body() -> void:
	if _body == "":
		apply_kind(_target_height, _tint, "normal")


func _build_body(body: String) -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	_meshes.clear()
	_eye_meshes.clear()
	_animation_player = null
	_current_animation = ""

	var spec: Dictionary = BODIES[body]
	var scene: PackedScene = load(spec.scene)
	if scene == null:
		push_error("ZombieVisual: could not load %s" % spec.scene)
		return

	_body = body
	_body_height = spec.height
	_walk_speed = spec.walk_speed
	_max_walk_rate = spec.max_walk_rate

	_model = scene.instantiate()
	# The pack's characters face +Z; every body in this game faces -Z.
	_model.rotation.y = PI
	add_child(_model)

	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var hidden := false
		for suffix in HIDDEN_MESH_SUFFIXES:
			if String(mesh.name).ends_with(suffix):
				hidden = true
		if hidden:
			mesh.visible = false
			continue
		# Shadows off: twenty skinned bodies drawn twice more per shadowed
		# light cost more than any shadow they add in corridors this dark.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_end = draw_distance
		mesh.visibility_range_end_margin = 4.0
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_meshes.append(mesh)
		if String(mesh.name).ends_with(EYE_MESH_SUFFIX):
			_eye_meshes.append(mesh)

	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_hit_react = null
	if skeleton != null:
		_hit_react = HitReactModifier.new()
		skeleton.add_child(_hit_react)

	_animation_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player != null:
		var library := _library_for(body)
		for existing in _animation_player.get_animation_library_list():
			_animation_player.remove_animation_library(existing)
		_animation_player.add_animation_library("", library)

	_eye_material = null
	_apply_tint()
	_apply_glow()
	update_locomotion(_last_speed)


func _apply_scale() -> void:
	_kind_scale = _target_height / maxf(_body_height, 0.01)
	if _model != null:
		_model.scale = Vector3.ONE * _kind_scale


## Materials are shared per (body, tint) so twenty zombies of a kind draw with
## the same handful of materials and batch together.
static var _tinted = null

func _apply_tint() -> void:
	for mesh in _meshes:
		if mesh in _eye_meshes:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i) as BaseMaterial3D
			if source == null:
				continue
			if _tint.is_equal_approx(Color.WHITE):
				mesh.set_surface_override_material(i, null)
				continue
			if _tinted == null:
				_tinted = {}
			var key := "%s|%s|%s" % [_body, source.get_instance_id(), _tint.to_html()]
			if not _tinted.has(key):
				var tinted := source.duplicate() as BaseMaterial3D
				tinted.albedo_color = source.albedo_color * _tint
				_tinted[key] = tinted
			mesh.set_surface_override_material(i, _tinted[key])


func _apply_glow() -> void:
	if _eye_meshes.is_empty():
		return
	if _eye_material == null:
		var source := _eye_meshes[0].mesh.surface_get_material(0) as StandardMaterial3D
		_eye_material = source.duplicate() if source != null else StandardMaterial3D.new()
		for eye in _eye_meshes:
			eye.set_surface_override_material(0, _eye_material)

	_eye_material.emission_enabled = _glow_energy > 0.0
	_eye_material.emission = _glow_colour
	_eye_material.emission_energy_multiplier = _glow_energy * eye_glow_scale


func _set_overlay(material: Material) -> void:
	for mesh in _meshes:
		if mesh in _eye_meshes:
			continue
		mesh.material_overlay = material


static func _get_flash_material() -> StandardMaterial3D:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.albedo_color = Color(1.0, 0.35, 0.28, 0.55)
	return _flash_material


## One library per body: that body's own clips, plus the runner's Run with its
## tracks re-addressed to this body's rig. Loops are set here because the
## import leaves every clip as play-once.
static func _library_for(body: String) -> AnimationLibrary:
	if _libraries == null:
		_libraries = {}
	if _libraries.has(body):
		return _libraries[body]

	var library := AnimationLibrary.new()
	var own := _source_player(body)
	if own != null:
		for clip in own.get_animation_list():
			var animation := own.get_animation(clip).duplicate(true) as Animation
			animation.loop_mode = (
				Animation.LOOP_LINEAR if clip in LOOPED_CLIPS else Animation.LOOP_NONE
			)
			library.add_animation(clip, animation)
		own.get_parent().free()

	if not library.has_animation("Run") and body != RUN_SOURCE_BODY:
		var source := _source_player(RUN_SOURCE_BODY)
		if source != null and source.has_animation("Run"):
			var run := source.get_animation("Run").duplicate(true) as Animation
			var from: String = BODIES[RUN_SOURCE_BODY].rig + "/"
			var to: String = BODIES[body].rig + "/"
			for track in run.get_track_count():
				var path := str(run.track_get_path(track))
				if path.begins_with(from):
					run.track_set_path(track, NodePath(to + path.substr(from.length())))
			run.loop_mode = Animation.LOOP_LINEAR
			library.add_animation("Run", run)
		if source != null:
			source.get_parent().free()

	_libraries[body] = library
	return library


static func _source_player(body: String) -> AnimationPlayer:
	var scene: PackedScene = load(BODIES[body].scene)
	if scene == null:
		return null
	var instance := scene.instantiate()
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		instance.free()
	return player
