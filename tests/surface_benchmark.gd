extends SceneTree
func _initialize() -> void:
 var b = load("res://scripts/surface_fill.gd").new()
 for n in [96, 256, 512]:
  var loop = PackedVector3Array()
  for i in range(n):
   var t = TAU * float(i) / n
   loop.append(Vector3(2*cos(t), 2*sin(t), 0))
  var start = Time.get_ticks_msec()
  var result: Dictionary = b.build(loop, 1, 20)
  print("BENCH %d vertices=%d triangles=%d ms=%d error=%s" % [n, result.get("vertices", PackedVector3Array()).size(),result.get("triangle_count",0),Time.get_ticks_msec()-start,result.get("error","")])
 quit()
