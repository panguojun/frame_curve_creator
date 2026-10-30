extends SceneTree


func _init() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	assert(FileAccess.file_exists(scene.BLENDER_EXE))
	assert(scene.segment_durations.size() == scene.frames.size() - 1)
	assert(scene._production_curves().size() == 1)
	for frame in scene.frames:
		assert(frame.scale_n == 0.0)
	scene.selected = 1
	assert(scene._hit_test(scene._normal_handle_screen(scene.frames[1]))["mode"] == "normal_scale")
	scene.drag_mode = "normal_scale"
	scene.normal_drag_gap = 22.0 / scene.zoom
	var spread_motion := InputEventMouseMotion.new()
	spread_motion.position = scene.world_to_screen(scene.frames[1].origin + scene.frames[1].normal() * (52.0 / scene.zoom))
	scene._handle_mouse_motion(spread_motion)
	assert(scene.frames[1].scale_n > 0.0)
	assert(scene._production_curves().size() == 2)
	var original: Array[Vector2] = scene._sample_hermite_curve()
	scene.frames[1].scale_t = 1.8
	var scaled: Array[Vector2] = scene._sample_hermite_curve()
	assert(original[50].distance_to(scaled[50]) > 0.1)
	scene._toggle_closed()
	assert(scene.closed and scene.segment_durations.size() == scene.frames.size())
	var loop: Array[Vector2] = scene._sample_hermite_curve()
	assert(loop[0].distance_to(loop[-1]) < 0.0001)
	var seam_hit: Dictionary = scene._nearest_curve_parameter(scene.world_to_screen(loop[loop.size() - 20]))
	assert(seam_hit["segment"] == scene.frames.size() - 1)
	scene._insert_frame_on_curve(seam_hit)
	assert(scene.frames.size() == 5)

	var folder := ProjectSettings.globalize_path("res://tests/output")
	DirAccess.make_dir_recursive_absolute(folder)
	var curves: Array = scene._production_curves()
	assert(curves.size() == 2)
	assert(curves[0]["name"] == "Left Boundary")
	assert(curves[1]["name"] == "Right Boundary")
	assert(curves[0]["points"][0].distance_to(curves[0]["points"][-1]) < 0.0001)
	scene.show_offsets = false
	assert(scene._production_curves().size() == 2) # visibility does not change exported geometry
	assert(scene._export_svg(folder.path_join("curve.svg"), curves))
	assert(scene._export_obj(folder.path_join("curve.obj"), curves))
	assert(scene._export_csv(folder.path_join("curve.csv"), curves))
	assert(scene._export_json(folder.path_join("curve.json"), curves))
	assert(scene._write_blender_import_script(folder.path_join("blender_import_polyline.py")))
	var svg := FileAccess.get_file_as_string(folder.path_join("curve.svg"))
	var obj := FileAccess.get_file_as_string(folder.path_join("curve.obj"))
	var csv := FileAccess.get_file_as_string(folder.path_join("curve.csv"))
	var json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("curve.json")))
	assert(svg.contains('<path id="profile_0"') and svg.contains('<path id="profile_1"'))
	assert(not svg.contains("centerline") and svg.contains(" Z"))
	assert(obj.contains("o Left_Boundary") and obj.contains("o Right_Boundary"))
	assert(not obj.contains("centerline"))
	assert(csv.contains("curve,point_index,x,y,closed") and not csv.contains("center_x"))
	assert(json["curves"].size() == 2 and not json.has("centerline"))
	scene._render_final_png(folder.path_join("curve.png"))
	assert(FileAccess.file_exists(folder.path_join("curve.png")))
	assert(FileAccess.get_file_as_bytes(folder.path_join("curve.png")).size() > 1000)

	scene._toggle_closed()
	assert(not scene.closed and scene.segment_durations.size() == scene.frames.size() - 1)
	for frame in scene.frames:
		frame.scale_n = 0.0
	var merged: Array = scene._production_curves()
	assert(merged.size() == 1 and merged[0]["name"] == "Profile Curve")
	scene.selected = 0
	assert(scene._hit_test(scene._normal_handle_screen(scene.frames[0]))["mode"] == "normal_scale")
	assert(scene._export_json(folder.path_join("merged.json"), merged))
	assert(scene._export_svg(folder.path_join("merged.svg"), merged))
	var merged_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("merged.json")))
	assert(merged_json["curves"].size() == 1 and not merged_json.has("centerline"))
	assert(not FileAccess.get_file_as_string(folder.path_join("merged.svg")).contains("profile_1"))
	var key := InputEventKey.new()
	key.keycode = KEY_N
	scene._handle_key(key)
	assert(scene.frames[0].scale_n == 1.0)
	print("Curve workflow checks passed")
	quit(0)
