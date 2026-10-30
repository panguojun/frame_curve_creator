extends SceneTree


func _init() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in scene.frames.size():
		scene.frames[i].origin = Vector2(float(i) * 100.0, [3.0, -4.0, 5.0, -2.0][i])
		scene.frames[i].angle = 0.0
		scene.frames[i].scale_n = 0.0
	scene._show_fit_dialog()
	await process_frame
	assert(scene.fit_dialog.visible)
	assert(scene.fit_source_option.size.x > 100.0)
	assert(scene.fit_model_option.size.x > 100.0)
	assert(scene.fit_info_label.size.y > 0.0)
	assert(scene.fit_source_option.get_global_rect().end.y <= scene.fit_dialog.size.y)
	assert(scene.fit_model_option.get_global_rect().end.y <= scene.fit_dialog.size.y)
	assert(scene.fit_curves.size() == 1)
	assert(scene.fit_candidates[0]["type"] == "line")
	var model: Dictionary = scene.fit_candidates[0]
	scene._apply_analytic_fit()
	for frame in scene.frames:
		assert(frame.origin.distance_to(scene.analytic_fitter.project(model, frame.origin)["point"]) < 0.001)
		assert(frame.scale_t == 1.0)
	var before: Array[Vector2] = scene._sample_hermite_curve()
	scene.frames[1].origin.y += 20.0
	var after: Array[Vector2] = scene._sample_hermite_curve()
	assert(before[40].distance_to(after[40]) > 1.0)
	scene.fit_dialog.hide()
	scene._reset_sample()
	for i in scene.frames.size():
		scene.frames[i].origin = Vector2(float(i) * 100.0, [3.0, -4.0, 5.0, -2.0][i])
		scene.frames[i].angle = 0.0
		scene.frames[i].scale_n = 1.0
		scene.frames[i].radius = 12.0
	scene._show_fit_dialog()
	assert(scene.fit_curves.size() == 2)
	scene.fit_source_option.select(1)
	scene._on_fit_source_selected(1)
	assert(scene.fit_candidates[0]["type"] == "line")
	var right_model: Dictionary = scene.fit_candidates[0]
	scene._apply_analytic_fit()
	for frame in scene.frames:
		var boundary: Vector2 = frame.origin + frame.normal() * frame.radius * frame.scale_n
		assert(boundary.distance_to(scene.analytic_fitter.project(right_model, boundary)["point"]) < 0.001)
	scene.fit_dialog.hide()
	print("Analytic editor fit checks passed")
	quit(0)
