extends SceneTree

func _initialize() -> void:
	var scene := load("res://scenes/main_3d.tscn") as PackedScene
	assert(scene != null)
	var editor := scene.instantiate()
	root.add_child.call_deferred(editor)
	_check.call_deferred(editor)

func _check(editor: Control) -> void:
	assert(editor.frames.size() == 4)
	assert(editor._panel_rect(0).position.x == editor.RAIL_W)
	assert(editor.properties.position.x == editor.size.x - editor.PROP_W)
	assert(editor.tangent_checkbox.position.x < editor.RAIL_W and editor.torsion_checkbox.position.x < editor.RAIL_W)
	assert(editor.properties != null and editor.property_fields.size() == 3)
	var f = editor.frames[1]
	var initial: Vector3 = f.position
	var front: Vector2 = editor._project(f.position, 0)
	f.position = editor._unproject(front + Vector2(35, -21), 0, f.position)
	assert(is_equal_approx(f.position.z, initial.z))
	assert(f.position.x > initial.x and f.position.y > initial.y)
	var top: Vector2 = editor._project(f.position, 1)
	var prior_y: float = f.position.y
	f.position = editor._unproject(top + Vector2(0, -20), 1, f.position)
	assert(is_equal_approx(f.position.y, prior_y) and f.position.z > initial.z)
	var right: Vector2 = editor._project(f.position, 2)
	var prior_x: float = f.position.x
	f.position = editor._unproject(right + Vector2(15, 0), 2, f.position)
	assert(is_equal_approx(f.position.x, prior_x))
	editor.selected = 1
	editor._on_property_changed(4.25, 0)
	assert(is_equal_approx(editor.frames[1].position.x, 4.25))
	editor.zen_mode = true
	assert(editor._panel_rect(0).position.x == 0.0)
	editor.zen_mode = false
	var open_curves: Dictionary = editor._sample_curves()
	assert(open_curves["center"].size() == 3 * 36 + 1)
	editor.closed = true
	var curves: Dictionary = editor._sample_curves()
	assert(curves["center"].size() == 4 * 36 + 1)
	assert(curves["center"][0].is_equal_approx(curves["center"][-1]))
	var json_path := "user://curve_3d_check.json"
	var obj_path := "user://curve_3d_check.obj"
	editor._save_file(json_path)
	editor._save_file(obj_path)
	assert(FileAccess.file_exists(json_path))
	assert(FileAccess.file_exists(obj_path))
	var obj = FileAccess.get_file_as_string(obj_path)
	assert(obj.contains("o active_curve") and obj.contains("l "))
	assert(not obj.contains("offset_plus"))
	var before: Vector3 = f.position
	editor._reset_sample()
	editor._load_file(json_path)
	assert(editor.closed and editor.frames[1].position.is_equal_approx(before))
	assert(editor.frames.size() == 4)
	var stable_curve_node = editor.curve_node
	var stable_grid_count: int = editor.geometry_root.get_child_count()
	editor.template_shape.select(0)
	editor.template_a.value = 2.5
	editor.template_sides.value = 8
	editor._request_template_replace()
	assert(editor.template_replace_dialog.visible and editor.frames.size() == 4)
	editor.template_replace_dialog.hide()
	assert(editor.frames.size() == 4)
	editor._template_replace_action(&"discard")
	assert(editor.frames.size() == 8 and editor.closed and editor.other_curves.is_empty())
	assert(is_equal_approx(editor.frames[0].position.length(), 2.5))
	assert(editor.frames[0].tangent.length() > 0.1)
	assert(editor.curve_node == stable_curve_node)
	assert(editor.geometry_root.get_child_count() >= stable_grid_count)
	editor.template_shape.select(1)
	editor.template_a.value = 4.0
	editor._save_then_apply_template("user://missing_template_directory/template.json")
	assert(editor.frames.size() == 8)
	var template_save_path := "user://template_replace_check.json"
	editor._save_then_apply_template(template_save_path)
	assert(FileAccess.file_exists(template_save_path))
	var saved_template = JSON.parse_string(FileAccess.get_file_as_string(template_save_path))
	assert(saved_template["frames"].size() == 8 and saved_template["layers"].is_empty())
	assert(editor.frames.size() == 8 and editor.frames[0].position.is_equal_approx(Vector3(-2,-2,0)))
	assert(editor.frames[0].position.is_equal_approx(editor.frames[1].position))
	assert(editor.frames[0].tangent.length() > 0.1 and editor.frames[1].tangent.length() > 0.1)
	assert(not editor.frames[0].tangent.is_equal_approx(editor.frames[1].tangent))
	assert(editor._sample_curves()["center"].size() == 4 * 36 + 1)
	# The FRONT view must include both coincident frames even when one is deeper.
	editor.frames[1].position.z += 2.0
	var corner_screen: Vector2 = editor._project(editor.frames[0].position, 0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = corner_screen - Vector2(15, 15)
	editor._mouse_button(press)
	assert(editor.drag_mode == "box")
	var move_box := InputEventMouseMotion.new()
	move_box.position = corner_screen + Vector2(15, 15)
	editor._mouse_motion(move_box)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = move_box.position
	editor._mouse_button(release)
	assert(editor.selected_frames.has(0) and editor.selected_frames.has(1))
	assert(editor.selected_frames.size() == 2)
	editor.frames[1].position.z -= 2.0
	var second_corner: Vector3 = editor.frames[1].position
	editor.frames[1].position = editor.camera.global_position.lerp(editor.frames[0].position, 0.8)
	var perspective_point: Vector2 = editor._selection_projection(editor.frames[0].position, 3)
	var perspective_hits: Array[int] = editor._box_selection_indices(perspective_point - Vector2(5, 5), perspective_point + Vector2(5, 5), 3)
	assert(perspective_hits.has(0) and perspective_hits.has(1))
	editor.frames[1].position = second_corner
	var next_corner_screen: Vector2 = editor._project(editor.frames[2].position, 0)
	editor._start_box_selection(next_corner_screen - Vector2(12, 12), 0, true)
	editor.box_end = next_corner_screen + Vector2(12, 12)
	editor._finish_box_selection()
	assert(editor.selected_frames.has(0) and editor.selected_frames.has(1))
	assert(editor.selected_frames.has(2) and editor.selected_frames.has(3))
	editor.drag_mode = ""
	editor._select_only(0)
	var corner: Vector3 = editor.frames[0].position
	editor._on_property_changed(corner.x + 0.5, 0)
	assert(editor.frames[1].position.is_equal_approx(editor.frames[0].position))
	editor._undo()
	assert(editor.frames[0].position.is_equal_approx(corner))
	editor._select_only(0)
	editor._toggle_selected(2)
	assert(editor.selected_frames.size() == 2)
	assert(editor._move_indices().size() == 4)
	editor._sync_properties()
	assert(not editor.property_fields[0].editable)
	editor.active_view = 0
	editor.drag_mode = "point"
	editor.drag_start = editor._project(editor.frames[0].position, 0)
	editor.drag_positions.clear()
	for index in editor._move_indices():
		editor.drag_positions[index] = editor.frames[index].position
	var motion := InputEventMouseMotion.new()
	motion.position = editor.drag_start + Vector2(20, 0)
	editor._mouse_motion(motion)
	assert(editor.frames[0].position.is_equal_approx(editor.frames[1].position))
	assert(editor.frames[2].position.is_equal_approx(editor.frames[3].position))
	assert(editor.frames[0].position.x > corner.x)
	editor._undo()
	assert(editor.frames[0].position.is_equal_approx(corner))
	editor.drag_mode = ""
	editor._select_only(0)
	editor.template_shape.select(2)
	editor.template_a.value = 6.0
	editor.template_b.value = 3.0
	editor._apply_template()
	assert(editor.frames.size() == 6)
	editor.template_shape.select(3)
	editor._apply_template()
	assert(editor.frames.size() == 8 and is_equal_approx(editor.frames[0].position.x, -3.0))
	editor.template_shape.select(4)
	editor.template_a.value = 3.0
	editor.template_sides.value = 7
	editor.template_plane.select(1)
	editor._apply_template()
	assert(editor.frames.size() == 14 and is_equal_approx(editor.frames[0].position.y, 0.0))
	assert(editor.other_curves.is_empty())
	editor._toggle_surface()
	assert(editor.surface_enabled and editor.surface_data.has("vertices"))
	assert(editor.surface_data["triangle_count"] > 0)
	var stable_surface_node = editor.surface_node
	editor._refresh()
	assert(editor.surface_node == stable_surface_node)
	var surface_obj_path := "user://surface_3d_check.obj"
	editor._save_file(surface_obj_path)
	var surface_obj = FileAccess.get_file_as_string(surface_obj_path)
	assert(surface_obj.contains("o active_surface") and surface_obj.contains("f "))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(surface_obj_path))
	editor.template_shape.select(0)
	editor.template_plane.select(0)
	editor.template_a.value = 1.5
	editor.template_sides.value = 8
	editor._apply_template()
	assert(editor.other_curves.is_empty())
	assert(editor.background_surface_nodes.is_empty())
	editor._toggle_surface()
	assert(editor.surface_data.has("vertices"))
	var blender_paths: Dictionary = editor._write_blender_payload()
	assert(FileAccess.file_exists(blender_paths["data"]))
	assert(FileAccess.file_exists(blender_paths["script"]))
	assert(FileAccess.file_exists(blender_paths["bridge"]))
	assert(not FileAccess.get_file_as_string(blender_paths["script"]).contains("bpy.ops.object.delete"))
	var payload = JSON.parse_string(FileAccess.get_file_as_string(blender_paths["data"]))
	assert(payload["curves"].size() == 1 and payload["layers"].size() == 0)
	assert(payload["surface"]["triangle_count"] > 0)
	assert(payload["surfaces"].size() == 1)
	print("Blender payload: " + blender_paths["data"])
	print("Blender script: " + blender_paths["script"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(template_save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(json_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(obj_path))
	print("3D curve workflow checks passed")
	quit()





