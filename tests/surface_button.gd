extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/main_3d.tscn") as PackedScene
	var editor = scene.instantiate()
	root.add_child.call_deferred(editor)
	_check.call_deferred(editor)
func _check(editor: Control) -> void:
	editor.selected = -1
	assert(not editor.closed and not editor.surface_enabled)
	var button_center: Vector2 = editor._tool_rect(5).get_center()
	assert(editor._toolbar_action(button_center))
	assert(editor.closed and editor.surface_enabled)
	assert(editor.surface_data.has("vertices"))
	assert(editor.surface_node.mesh != null)
	assert(editor.surface_data["triangle_count"] > 0)
	assert(editor.surface_data["projected_area"] > 10.0)
	assert(editor.toast.contains("Surface generated"))
	editor._toolbar_action(button_center)
	assert(not editor.surface_enabled and editor.surface_node.mesh == null)
	print("Surface button checks passed")
	quit()

