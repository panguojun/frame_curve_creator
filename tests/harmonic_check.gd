extends SceneTree

func _initialize() -> void:
	var builder = load("res://scripts/surface_fill.gd").new()

	# Case 1: planar circle at z=0. All boundary heights are 0.
	# The harmonic solution must be h=0 everywhere -> interior z must be 0.
	var circle := PackedVector3Array()
	for i in range(32):
		var angle := TAU * float(i) / 32.0
		circle.append(Vector3(2.0*cos(angle), 2.0*sin(angle), 0.0))
	circle.append(circle[0])
	var r: Dictionary = builder.build(circle, 2, 40)
	assert(not r.has("error"), "planar circle failed: " + str(r.get("error","")))
	var max_z := 0.0
	for v in r["vertices"]:
		max_z = maxf(max_z, absf(v.z))
	print("Planar circle: max interior |z| = %.6f" % max_z)
	assert(max_z < 0.001, "Planar circle interior z not zero: " + str(max_z))

	# Case 2: tilted planar square. Boundary heights are not zero but the
	# surface must stay exactly planar (no warping). Interior vertices must
	# lie on the same plane as the boundary.
	var sq := PackedVector3Array([
		Vector3(-2,-2,0.5),
		Vector3(2,-2,0.5),
		Vector3(2,2,0.5),
		Vector3(-2,2,0.5),
		Vector3(-2,-2,0.5),
	])
	var r2: Dictionary = builder.build(sq, 1, 40)
	assert(not r2.has("error"), "tilted square failed: " + str(r2.get("error","")))
	var max_dev := 0.0
	for v in r2["vertices"]:
		max_dev = maxf(max_dev, absf(v.z - 0.5))
	print("Tilted square: max |z - 0.5| = %.6f" % max_dev)
	assert(max_dev < 0.001, "Tilted square interior not planar: " + str(max_dev))

	# Case 3: boundary vertex preservation — every sampled boundary point must
	# appear exactly at its original 3D position (no drift).
	var wave := PackedVector3Array()
	for i in range(24):
		var angle := TAU * float(i) / 24.0
		wave.append(Vector3(2.0*cos(angle), 2.0*sin(angle), 0.3*sin(3.0*angle)))
	wave.append(wave[0])
	var r3: Dictionary = builder.build(wave, 1, 30)
	assert(not r3.has("error"), "wave circle failed: " + str(r3.get("error","")))
	# First 24 vertices are boundary; check them against original samples.
	var max_drift := 0.0
	for i in range(24):
		max_drift = maxf(max_drift, r3["vertices"][i].distance_to(wave[i]))
	print("Wave circle: max boundary drift = %.6f" % max_drift)
	assert(max_drift < 0.0001, "Boundary drift too large: " + str(max_drift))

	# Case 4: Euler characteristic must be exactly 1 for all valid loops.
	assert(r["euler"] == 1, "Euler != 1 for circle")
	assert(r2["euler"] == 1, "Euler != 1 for square")
	assert(r3["euler"] == 1, "Euler != 1 for wave")

	print("Harmonic correctness checks passed")
	quit()
