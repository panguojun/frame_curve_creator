extends SceneTree

func _initialize() -> void:
	var builder = load("res://scripts/surface_fill.gd").new()
	var loop := PackedVector3Array()
	for i in range(48):
		var angle := TAU*float(i)/48.0
		loop.append(Vector3(2.0*cos(angle),2.0*sin(angle),0.0))
	var controls := [{"position":loop[0],"normal":Vector3(1.0,0.0,0.3).normalized()}, {"position":loop[24],"normal":Vector3(-1.0,0.0,0.3).normalized()}]
	var mesh: Dictionary = builder.build(loop,1,20,controls)
	assert(not mesh.has("error"))
	var vertices: PackedVector3Array = mesh["vertices"]
	var indices: PackedInt32Array = mesh["indices"]
	var owners := {}
	var max_angle := 0.0
	for k in range(0,indices.size(),3):
		var a: Vector3 = vertices[indices[k]]
		var b: Vector3 = vertices[indices[k+1]]
		var c: Vector3 = vertices[indices[k+2]]
		var face_normal := (b-a).cross(c-a).normalized()
		for j in range(3):
			var u := mini(indices[k+j],indices[k+(j+1)%3])
			var v := maxi(indices[k+j],indices[k+(j+1)%3])
			var key := "%d:%d" % [u,v]
			if owners.has(key):
				max_angle = maxf(max_angle,rad_to_deg(acos(clampf(face_normal.dot(owners[key]),-1.0,1.0))))
			else:
				owners[key] = face_normal
	print("MAX DIHEDRAL %.2f" % max_angle)
	assert(max_angle < 30.0)
	quit()
