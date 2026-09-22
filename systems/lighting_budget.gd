extends Node3D
var tick := 0.0
var lamps: Array[OmniLight3D] = []
func _ready():
 for n in get_parent().find_children("*", "OmniLight3D", true, false): lamps.append(n)
func _process(delta):
 tick += delta
 if tick < 0.35:return
 tick=0.0
 var camera=get_viewport().get_camera_3d()
 if camera == null:return
 lamps.sort_custom(func(a,b):return a.global_position.distance_squared_to(camera.global_position)<b.global_position.distance_squared_to(camera.global_position))
 for i in lamps.size():
  var d=lamps[i].global_position.distance_to(camera.global_position)
  lamps[i].visible=i<8 and d<23.0
  lamps[i].shadow_enabled=lamps[i].visible
