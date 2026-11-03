extends SceneTree
func _initialize() -> void:
 var b = load("res://scripts/surface_fill.gd").new()
 var cases = {}
 var circle = PackedVector3Array()
 for i in range(24):
  var t = TAU * float(i) / 24.0
  circle.append(Vector3(2*cos(t), 2*sin(t), 0))
 cases["circle"] = circle
 cases["concave"] = PackedVector3Array([Vector3(-3,-2,0),Vector3(3,-2,0),Vector3(3,-1,0),Vector3(0,-1,0),Vector3(0,2,0),Vector3(-3,2,0)])
 cases["warped"] = PackedVector3Array([Vector3(-2,-2,-0.5),Vector3(2,-2,0.8),Vector3(2,2,-0.3),Vector3(-2,2,0.5)])
 for name in cases:
  var result: Dictionary = b.build(cases[name], 1, 20)
  assert(not result.has("error"), str(result.get("error", "")))
  var v: PackedVector3Array = result.vertices
  var ids: PackedInt32Array = result.indices
  var lengths = PackedFloat32Array()
  var seen = {}
  var min_angle = 180.0
  for k in range(0, ids.size(), 3):
   var a = v[ids[k]]
   var bb = v[ids[k+1]]
   var c = v[ids[k+2]]
   min_angle = minf(min_angle, rad_to_deg((bb-a).angle_to(c-a)))
   min_angle = minf(min_angle, rad_to_deg((a-bb).angle_to(c-bb)))
   min_angle = minf(min_angle, rad_to_deg((a-c).angle_to(bb-c)))
   for pair in [[ids[k],ids[k+1]],[ids[k+1],ids[k+2]],[ids[k+2],ids[k]]]:
    var key = "%d:%d" % [mini(pair[0],pair[1]),maxi(pair[0],pair[1])]
    if not seen.has(key):
     seen[key] = true
     lengths.append(v[pair[0]].distance_to(v[pair[1]]))
  lengths.sort()
  var p10 = lengths[int((lengths.size()-1)*0.1)]
  var p90 = lengths[int((lengths.size()-1)*0.9)]
  print("QUALITY %s triangles=%d min_angle=%.2f p10=%.3f p90=%.3f ratio=%.2f" % [name,result.triangle_count,min_angle,p10,p90,p90/p10])
  assert(min_angle > 10.0)
  assert(p90/p10 < 5.0)
  assert(result.euler == 1)
 quit()


