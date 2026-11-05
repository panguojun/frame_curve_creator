extends SceneTree

func _initialize() -> void:
	var builder = load("res://scripts/surface_fill.gd").new()
	for count in [8, 12, 20, 32, 48]:
		for variant in range(3):
			var loop := PackedVector3Array()
			for i in range(count):
				var angle := TAU * float(i) / float(count)
				var radius := 2.0 + 0.32 * sin(angle*float(3+variant)) + 0.17 * cos(angle*7.0)
				loop.append(Vector3(radius*cos(angle), radius*sin(angle), 0.18*sin(angle*float(2+variant))))
			for detail in [0, 1, 2]:
				var mesh: Dictionary = builder.build(loop, detail, 20)
				assert(not mesh.has("error"), "%d/%d/%d: %s" % [count, variant, detail, mesh.get("error", "")])
				assert(mesh["euler"] == 1)
				for i in range(count):
					assert(mesh["vertices"][i].is_equal_approx(loop[i]))
	print("Mesh stress checks passed")
	quit()
