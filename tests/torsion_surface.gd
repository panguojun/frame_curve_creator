extends SceneTree

func _initialize() -> void:
	var builder = load("res://scripts/surface_fill.gd").new()
	var loop := PackedVector3Array()
	for i in range(24):
		var angle := TAU * float(i) / 24.0
		loop.append(Vector3(2.0*cos(angle), 2.0*sin(angle), 0.0))
	loop.append(loop[0])
	var flat: Dictionary = builder.build(loop, 1, 15)
	var tilted: Dictionary = builder.build(loop, 1, 15, [{"position":loop[0], "normal":Vector3(0.5, 0.0, 0.8660254)}])
	assert(not flat.has("error") and not tilted.has("error"))
	assert(flat["vertices"].size() == tilted["vertices"].size())
	for i in range(24):
		assert(tilted["vertices"][i].is_equal_approx(loop[i]))
	var changed := false
	for i in range(24, tilted["vertices"].size()):
		if absf(tilted["vertices"][i].z - flat["vertices"][i].z) > 0.001:
			changed = true
			break
	assert(changed)
	print("Torsion surface checks passed")
	var scene := load("res://scenes/main_3d.tscn") as PackedScene
	var editor := scene.instantiate()
	root.add_child.call_deferred(editor)
	_check_editor.call_deferred(editor)

func _check_editor(editor: Control) -> void:
	assert(editor.tangent_checkbox.button_pressed and not editor.torsion_checkbox.button_pressed)
	var frame = editor.frames[0]
	var tangent_screen: Vector2 = editor._project(frame.position + frame.tangent * editor.HANDLE_FACTOR, 0)
	assert(editor._hit(tangent_screen, 0)["part"] != "tangent")
	editor._select_only(0)
	editor._refresh()
	assert(editor._hit(tangent_screen, 0)["part"] == "tangent")
	assert(editor.tangent_node.mesh != null and editor.normal_node.mesh == null)
	editor.torsion_checkbox.button_pressed = true
	assert(editor.normal_node.mesh != null)
	var original: Vector3 = editor.frames[0].normal
	editor._on_property_changed(0.5, 6)
	assert(not editor.frames[0].normal.is_equal_approx(original))
	editor._select_only(-1)
	editor._refresh()
	assert(editor.tangent_node.mesh == null and editor.normal_node.mesh == null)
	print("Torsion editor checks passed")
	quit()
