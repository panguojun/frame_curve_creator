extends SceneTree

func _initialize() -> void:
	var editor := (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(editor)
	_check.call_deferred(editor)

func _check(editor: Control) -> void:
	editor._select_only(0)
	editor._toggle_selected(2)
	editor.torsion_checkbox.button_pressed = true
	editor._refresh()
	assert(editor.selected_frames.size() == 2)
	assert(editor.tangent_node.mesh != null and editor.normal_node.mesh != null)
	for index in editor.selected_frames:
		var frame = editor.frames[index]
		var tangent_tip: Vector3 = frame.position + frame.tangent * editor.HANDLE_FACTOR
		var normal_tip: Vector3 = frame.position + editor._frame_normal(frame) * 0.8
		for view in [0, 1, 2, 3]:
			assert(editor._hit(editor._selection_projection(tangent_tip, view), view)["part"] == "tangent")
			assert(editor._hit(editor._selection_projection(normal_tip, view), view)["part"] == "normal")
	var frame = editor.frames[0]
	var tangent_screen: Vector2 = editor._project(frame.position + frame.tangent * editor.HANDLE_FACTOR, 0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = tangent_screen
	editor._mouse_button(press)
	assert(editor.drag_mode == "tangent")
	assert(editor.selected_frames.size() == 2 and editor.selected_frames.has(0) and editor.selected_frames.has(2))
	assert(editor.selected == 0)
	print("Multi-selection handle checks passed")
	quit()
