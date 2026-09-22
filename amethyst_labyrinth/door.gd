class_name DungeonDoor
extends AnimatableBody3D
@export var open_angle_degrees: float = -105.0
var opened := false
var animating := false
var closed_rotation := 0.0
func _ready() -> void:
	closed_rotation = rotation.y
	add_to_group("dungeon_doors")
func interact() -> void:
	if animating:
		return
	# Leave opened doors open so they cannot close into a player in the doorway.
	if opened:
		return
	opened = true
	animating = true
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self,"rotation:y",closed_rotation+deg_to_rad(open_angle_degrees),0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func(): animating = false)
