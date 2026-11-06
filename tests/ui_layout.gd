extends SceneTree

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var editor := (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(editor)
	_check.call_deferred(editor)

func _check(editor: Control) -> void:
	for _i in range(6):
		await process_frame
	editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	editor.size = Vector2(1280, 720)
	editor._layout_preview()
	for _i in range(3):
		await process_frame
	assert(editor.property_fields.size() == 3)
	assert(editor._tool_rect(11).end.y < editor.size.y - editor.FOOTER_H)
	assert(editor._panel_rect(1).end.x <= editor.properties.position.x)
	assert(editor.property_scroll.size.y <= editor.properties.size.y)
	assert(editor.surface_info.text.contains("Off"))
	if DisplayServer.get_name() != "headless":
		get_root().get_texture().get_image().save_png("res://build/ui_preview.png")
	editor.size = Vector2(1100, 650)
	editor._layout_preview()
	await process_frame
	assert(editor._tool_rect(11).end.y < editor.size.y - editor.FOOTER_H)
	assert(editor._panel_rect(1).end.x <= editor.properties.position.x)
	print("UI layout checks passed")
	quit()
