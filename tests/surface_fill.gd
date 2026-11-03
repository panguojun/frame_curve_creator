extends SceneTree

func _initialize() -> void:
	var builder = load("res://scripts/surface_fill.gd").new()
	var circle := PackedVector3Array()
	for i in range(24):
		var angle := TAU*float(i)/24.0
		circle.append(Vector3(cos(angle)*2.0,sin(angle)*2.0,0.0))
	circle.append(circle[0])
	var flat: Dictionary = builder.build(circle,1,15)
	assert(not flat.has("error"))
	assert(flat["boundary_count"] == 24)
	assert(flat["triangle_count"] > 24)
	assert(flat["euler"] == 1 and flat["boundary_edges"] >= 24)
	assert(absf(flat["projected_area"]-PI*4.0) < 0.2)
	for i in range(24):
		assert(flat["vertices"][i].is_equal_approx(circle[i]))
	var warped := PackedVector3Array([Vector3(-2,-2,-0.5),Vector3(2,-2,0.8),Vector3(2,2,-0.3),Vector3(-2,2,0.5),Vector3(-2,-2,-0.5)])
	var nonplanar: Dictionary = builder.build(warped,2,30)
	assert(not nonplanar.has("error"))
	assert(nonplanar["triangle_count"] > 20)
	assert(nonplanar["euler"] == 1)
	for i in range(4):
		assert(nonplanar["vertices"][i].is_equal_approx(warped[i]))
	var bowtie := PackedVector3Array([Vector3(-1,-1,0),Vector3(1,1,0),Vector3(-1,1,0),Vector3(1,-1,0)])
	assert(builder.build(bowtie).has("error"))
	print("Surface fill checks passed")
	quit()


