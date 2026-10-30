extends SceneTree


func _init() -> void:
	var fitter = load("res://scripts/analytic_fit.gd").new()
	var line: Array[Vector2] = []
	var circle: Array[Vector2] = []
	var ellipse: Array[Vector2] = []
	var rotation := deg_to_rad(28.0)
	var axis_a := Vector2(cos(rotation), sin(rotation))
	var axis_b := Vector2(-sin(rotation), cos(rotation))
	for i in 80:
		var t := float(i) / 79.0
		line.append(Vector2(-100.0 + t * 200.0, 3.0 + (-100.0 + t * 200.0) * 0.6))
		var angle := TAU * float(i) / 80.0
		circle.append(Vector2(30.0, -40.0) + Vector2(cos(angle), sin(angle)) * 80.0)
		ellipse.append(Vector2(-20.0, 15.0) + axis_a * (120.0 * cos(angle)) + axis_b * (50.0 * sin(angle)))
	assert(fitter.candidates(line)[0]["type"] == "line")
	var circle_fit: Dictionary = fitter.candidates(circle)[0]
	assert(circle_fit["type"] == "circle")
	assert(circle_fit["rms"] < 0.01)
	var ellipse_fit: Dictionary = fitter.candidates(ellipse)[0]
	assert(ellipse_fit["type"] == "ellipse")
	assert(ellipse_fit["rms"] < 0.1)
	print("Analytic fit checks passed")
	quit(0)
