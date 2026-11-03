extends Control

class CurveFrame:
	var position: Vector3
	var tangent: Vector3
	func _init(p: Vector3, t: Vector3) -> void:
		position = p
		tangent = t

const BG := Color("161c27")
const PANEL := Color("202938")
const GRID := Color("374456")
const BLUE := Color("499cf5")
const GREEN := Color("4ed492")
const YELLOW := Color("ffe36a")
const HEADER_H := 42.0
const FOOTER_H := 30.0
const RAIL_W := 104.0
const PROP_W := 290.0
const HANDLE_FACTOR := 0.32
const SAMPLES := 36
const BLENDER_EXE := "C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe"
const BLENDER_IMPORT_SCRIPT := """
import bpy
import json
from pathlib import Path

source = Path(__PAYLOAD_PATH__)
receipt = Path(__RECEIPT_PATH__)
data = json.loads(source.read_text(encoding='utf-8'))
collection = bpy.data.collections.new('Frame Curve Board ' + source.stem)
bpy.context.scene.collection.children.link(collection)
created = 0
for entry in data['curves']:
    points = entry['points']
    closed = bool(entry.get('closed', data.get('closed')))
    if closed and len(points) > 1 and points[0] == points[-1]:
        points = points[:-1]
    if len(points) < 2:
        continue
    name = entry['name']
    curve = bpy.data.curves.new(name, type='CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 1
    curve.bevel_depth = 0.0
    curve.extrude = 0.0
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for control, point in zip(spline.points, points):
        control.co = (point[0], point[1], point[2], 1.0)
    spline.use_cyclic_u = closed
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.display_type = 'WIRE'
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    created += 1
faces = 0
surfaces = data.get('surfaces', [])
if not surfaces and data.get('surface', {}).get('vertices'):
    surfaces = [dict(data['surface'], name='active_surface')]
for surface in surfaces:
    if surface.get('vertices') and surface.get('indices'):
        vertices = surface['vertices']
        flat = surface['indices']
        triangles = [flat[i:i+3] for i in range(0, len(flat), 3)]
        name = surface.get('name', 'Frame Boundary Surface')
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(vertices, [], triangles)
        mesh.update()
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        faces += len(mesh.polygons)
receipt.write_text(f'{created} curves, {faces} faces', encoding='utf-8')
print(f'Frame Curve 3D imported: {created} editable Blender Curves, {faces} surface faces')
"""

var frames: Array[CurveFrame] = []
var other_curves: Array[Dictionary] = []
var closed := false
var surface_enabled := false
var surface_refine := 1
var surface_smooth := 20
var surface_data: Dictionary = {}
var last_surface_error := ""
var surface_builder: RefCounted
var selected := -1
var selected_frames: Array[int] = []
var undo_stack: Array[Dictionary] = []
var drag_positions: Dictionary = {}
var drag_start := Vector2.ZERO
var box_start := Vector2.ZERO
var box_end := Vector2.ZERO
var box_additive := false
var active_view := 0
var drag_mode := ""
var insert_mode := false
var view_pan: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var view_zoom: Array[float] = [70.0, 70.0, 70.0]
var orbit_yaw := 0.7
var orbit_pitch := -0.42
var orbit_distance := 13.0
var orbit_target := Vector3.ZERO
var preview: SubViewportContainer
var box_overlay: Control
var viewport_3d: SubViewport
var scene_root: Node3D
var camera: Camera3D
var geometry_root: Node3D
var curve_node: MeshInstance3D
var background_curve_node: MeshInstance3D
var surface_node: MeshInstance3D
var background_surface_nodes: Array[MeshInstance3D] = []
var tangent_node: MeshInstance3D
var marker_nodes: Array[MeshInstance3D] = []
var marker_mesh: SphereMesh
var marker_material: StandardMaterial3D
var selected_material: StandardMaterial3D
var save_dialog: FileDialog
var template_save_dialog: FileDialog
var load_dialog: FileDialog
var template_dialog: ConfirmationDialog
var template_replace_dialog: ConfirmationDialog
var template_shape: OptionButton
var template_plane: OptionButton
var template_a: SpinBox
var template_b: SpinBox
var template_sides: SpinBox
var template_a_label: Label
var template_b_label: Label
var template_sides_label: Label
var toast := ""
var toast_until := 0
var zen_mode := false
var old_window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var properties: Control
var property_title: Label
var property_fields: Array[SpinBox] = []
var updating_fields := false
var surface_info: Label
var surface_detail_field: SpinBox
var surface_smooth_field: SpinBox

func _copy_frames(source: Array) -> Array[CurveFrame]:
	var result: Array[CurveFrame] = []
	for frame in source:
		result.append(CurveFrame.new(frame.position, frame.tangent))
	return result

func _snapshot() -> Dictionary:
	var layers: Array[Dictionary] = []
	for layer in other_curves:
		layers.append({"frames":_copy_frames(layer["frames"]),"closed":layer["closed"],"surface":layer.get("surface",false)})
	return {"frames":_copy_frames(frames),"layers":layers,"closed":closed,"surface":surface_enabled,"refine":surface_refine,"smooth":surface_smooth,"selection":selected_frames.duplicate()}

func _record_undo() -> void:
	if frames.is_empty():
		return
	undo_stack.append(_snapshot())
	if undo_stack.size() > 50:
		undo_stack.pop_front()

func _undo() -> void:
	if undo_stack.is_empty():
		_message("Nothing to undo")
		return
	var state: Dictionary = undo_stack.pop_back()
	frames = _copy_frames(state["frames"])
	other_curves = state["layers"]
	closed = state["closed"]
	surface_enabled = state["surface"]
	surface_refine = state["refine"]
	surface_smooth = state["smooth"]
	selected_frames = state["selection"]
	selected = selected_frames.back() if not selected_frames.is_empty() else -1
	updating_fields = true
	surface_detail_field.value = surface_refine
	surface_smooth_field.value = surface_smooth
	updating_fields = false
	_refresh()
	_message("Undid last edit")

func _select_only(index: int) -> void:
	selected = index
	selected_frames.clear()
	if index >= 0:
		selected_frames.append(index)

func _toggle_selected(index: int) -> void:
	if selected_frames.has(index):
		selected_frames.erase(index)
	else:
		selected_frames.append(index)
	selected = selected_frames.back() if not selected_frames.is_empty() else -1

func _move_indices() -> Array[int]:
	var indices: Array[int] = selected_frames.duplicate()
	for index in selected_frames:
		for j in range(frames.size()):
			if not indices.has(j) and frames[j].position.is_equal_approx(frames[index].position):
				indices.append(j)
	return indices

func _ready() -> void:
	get_window().title = "3D Frame Curve Board | 0.4.2"
	get_window().grab_focus.call_deferred()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_make_preview()
	surface_builder = load("res://scripts/surface_fill.gd").new()
	_make_dialogs()
	_make_template_dialog()
	_make_properties()
	_reset_sample()

func _make_preview() -> void:
	preview = SubViewportContainer.new()
	preview.stretch = true
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview)
	box_overlay = Control.new()
	box_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box_overlay)
	box_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box_overlay.draw.connect(_draw_box_overlay)
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(640, 360)
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.own_world_3d = true
	preview.add_child(viewport_3d)
	scene_root = Node3D.new()
	viewport_3d.add_child(scene_root)
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.current = true
	scene_root.add_child(camera)
	geometry_root = Node3D.new()
	scene_root.add_child(geometry_root)
	_build_static_3d()
	_update_camera()
	resized.connect(_layout_preview)
	_layout_preview()

func _make_dialogs() -> void:
	save_dialog = FileDialog.new()
	save_dialog.title = "Export 3D curve"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.use_native_dialog = true
	save_dialog.filters = PackedStringArray(["*.json ; 3D curve and editable frames", "*.obj ; Wavefront 3D polylines"])
	save_dialog.file_selected.connect(_save_file)
	add_child(save_dialog)
	template_save_dialog = FileDialog.new()
	template_save_dialog.title = "Save current curve before replacing it"
	template_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	template_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	template_save_dialog.use_native_dialog = true
	template_save_dialog.filters = PackedStringArray(["*.json ; Editable 3D curve scene"])
	template_save_dialog.file_selected.connect(_save_then_apply_template)
	add_child(template_save_dialog)
	load_dialog = FileDialog.new()
	load_dialog.title = "Open 3D curve JSON"
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.use_native_dialog = true
	load_dialog.filters = PackedStringArray(["*.json ; 3D curve JSON"])
	load_dialog.file_selected.connect(_load_file)
	add_child(load_dialog)

func _make_template_dialog() -> void:
	template_dialog = ConfirmationDialog.new()
	template_dialog.title = "Create editable curve template"
	template_dialog.confirmed.connect(_request_template_replace)
	add_child(template_dialog)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	template_dialog.add_child(box)
	var note := Label.new()
	note.text = "Replace the current curve with a shape; edit its frames afterward."
	box.add_child(note)
	template_shape = OptionButton.new()
	for label in ["Circle", "Square", "Triangle", "Rectangle", "Regular polygon"]:
		template_shape.add_item(label)
	template_shape.item_selected.connect(_template_ui_update)
	box.add_child(template_shape)
	template_plane = OptionButton.new()
	for label in ["FRONT / XY", "TOP / XZ", "RIGHT / ZY"]:
		template_plane.add_item(label)
	box.add_child(template_plane)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	template_a_label = Label.new()
	grid.add_child(template_a_label)
	template_a = SpinBox.new()
	template_a.min_value = 0.1
	template_a.max_value = 100.0
	template_a.step = 0.1
	template_a.value = 3.0
	template_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(template_a)
	template_b_label = Label.new()
	grid.add_child(template_b_label)
	template_b = SpinBox.new()
	template_b.min_value = 0.1
	template_b.max_value = 100.0
	template_b.step = 0.1
	template_b.value = 3.0
	template_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(template_b)
	template_sides_label = Label.new()
	grid.add_child(template_sides_label)
	template_sides = SpinBox.new()
	template_sides.min_value = 3
	template_sides.max_value = 64
	template_sides.step = 1
	template_sides.value = 8
	template_sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(template_sides)
	_template_ui_update(0)
	template_replace_dialog = ConfirmationDialog.new()
	template_replace_dialog.title = "Replace current curve?"
	template_replace_dialog.dialog_text = "Save the current curve before replacing it with the selected template?"
	template_replace_dialog.ok_button_text = "Save..."
	template_replace_dialog.cancel_button_text = "Cancel"
	template_replace_dialog.add_button("Don't Save", true, "discard")
	template_replace_dialog.confirmed.connect(_choose_template_save)
	template_replace_dialog.custom_action.connect(_template_replace_action)
	add_child(template_replace_dialog)

func _request_template_replace() -> void:
	template_replace_dialog.popup_centered()

func _choose_template_save() -> void:
	template_save_dialog.popup_centered_ratio()

func _template_replace_action(action: StringName) -> void:
	if action == &"discard":
		template_replace_dialog.hide()
		_apply_template()

func _save_then_apply_template(path: String) -> void:
	var json_path := path if path.get_extension().to_lower() == "json" else path + ".json"
	if _save_file(json_path):
		_apply_template()

func _template_ui_update(index: int) -> void:
	match index:
		0:
			template_a_label.text = "Radius"
			template_b_label.visible = false
			template_b.visible = false
			template_sides_label.text = "Curve frames"
			template_sides.visible = true
			template_sides_label.visible = true
		1:
			template_a_label.text = "Side length"
			template_b_label.visible = false
			template_b.visible = false
			template_sides.visible = false
			template_sides_label.visible = false
		2, 3:
			template_a_label.text = "Width"
			template_b_label.text = "Height"
			template_b_label.visible = true
			template_b.visible = true
			template_sides.visible = false
			template_sides_label.visible = false
		4:
			template_a_label.text = "Radius"
			template_b_label.visible = false
			template_b.visible = false
			template_sides_label.text = "Sides"
			template_sides.visible = true
			template_sides_label.visible = true

func _template_point(p: Vector2, plane: int) -> Vector3:
	match plane:
		0: return Vector3(p.x,p.y,0)
		1: return Vector3(p.x,0,p.y)
		_: return Vector3(0,p.y,p.x)

func _apply_template() -> void:
	_record_undo()
	var shape := template_shape.selected
	var plane := template_plane.selected
	var a := template_a.value
	var b := template_b.value
	var sides := int(template_sides.value)
	var points: Array[Vector2] = []
	var tangents: Array[Vector2] = []
	if shape == 0:
		sides = maxi(4,sides)
		for i in range(sides):
			var theta := TAU*float(i)/sides
			points.append(Vector2(cos(theta),sin(theta))*a)
			tangents.append(Vector2(-sin(theta),cos(theta))*4.0*a*tan(PI/(2.0*sides)))
	elif shape == 1 or shape == 3:
		var hw := a*0.5
		var hh := a*0.5 if shape == 1 else b*0.5
		points = [Vector2(-hw,-hh),Vector2(hw,-hh),Vector2(hw,hh),Vector2(-hw,hh)]
	elif shape == 2:
		points = [Vector2(0,b*0.5),Vector2(-a*0.5,-b*0.5),Vector2(a*0.5,-b*0.5)]
	else:
		for i in range(sides):
			var theta := TAU*float(i)/sides+PI*0.5
			points.append(Vector2(cos(theta),sin(theta))*a)
	other_curves.clear()
	surface_data = {}
	last_surface_error = ""
	frames = []
	for i in range(points.size()):
		if shape == 0:
			frames.append(CurveFrame.new(_template_point(points[i],plane),_template_point(tangents[i],plane)))
		else:
			var incoming := points[i] - points[(i-1+points.size()) % points.size()]
			var outgoing := points[(i+1) % points.size()] - points[i]
			frames.append(CurveFrame.new(_template_point(points[i],plane),_template_point(incoming,plane)))
			frames.append(CurveFrame.new(_template_point(points[i],plane),_template_point(outgoing,plane)))
	closed = true
	surface_enabled = false
	selected = 0
	selected_frames = [0]
	insert_mode = false
	_refresh()
	_message("Editable %s template created" % template_shape.get_item_text(shape))

func _reset_sample() -> void:
	_record_undo()
	other_curves.clear()
	surface_enabled = false
	frames = [
		CurveFrame.new(Vector3(-2.8, -1.8, -0.4), Vector3(3.0, 0.0, 0.5)),
		CurveFrame.new(Vector3(2.8, -1.8, 0.5), Vector3(0.0, 2.5, 0.4)),
		CurveFrame.new(Vector3(2.8, 1.8, -0.3), Vector3(-3.0, 0.0, -0.4)),
		CurveFrame.new(Vector3(-2.8, 1.8, 0.4), Vector3(0.0, -2.5, -0.4))
	]
	closed = false
	selected = 1
	selected_frames = [1]
	insert_mode = false
	_refresh()

func _make_properties() -> void:
	properties = Control.new()
	properties.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(properties)
	property_title = Label.new()
	property_title.text = "SELECT A FRAME"
	property_title.position = Vector2(16, 20)
	property_title.add_theme_font_size_override("font_size", 17)
	properties.add_child(property_title)
	var headings := ["POSITION / XYZ", "TANGENT / XYZ"]
	var axes := ["X", "Y", "Z"]
	for group in range(2):
		var heading := Label.new()
		heading.text = headings[group]
		heading.position = Vector2(16, 76 + group*210)
		heading.add_theme_font_size_override("font_size", 13)
		properties.add_child(heading)
		for axis in range(3):
			var row := group*3 + axis
			var label := Label.new()
			label.text = axes[axis]
			label.position = Vector2(18, 111 + group*210 + axis*50)
			label.add_theme_font_size_override("font_size", 15)
			properties.add_child(label)
			var field := SpinBox.new()
			field.min_value = -10000.0
			field.max_value = 10000.0
			field.step = 0.01
			field.allow_greater = true
			field.allow_lesser = true
			field.position = Vector2(54, 104 + group*210 + axis*50)
			field.size = Vector2(PROP_W-72, 34)
			field.value_changed.connect(_on_property_changed.bind(row))
			properties.add_child(field)
			property_fields.append(field)
	var hint := Label.new()
	hint.text = "Drag empty space to box-select.\nAlt+drag boxes in PERSPECTIVE.\nShift adds to the selection."
	hint.position = Vector2(16, 506)
	properties.add_child(hint)
	surface_info = Label.new()
	surface_info.position = Vector2(16, 558)
	surface_info.text = "SURFACE  off"
	properties.add_child(surface_info)
	var detail_label := Label.new()
	detail_label.text = "Detail"
	detail_label.position = Vector2(16, 598)
	properties.add_child(detail_label)
	surface_detail_field = SpinBox.new()
	surface_detail_field.min_value = 0
	surface_detail_field.max_value = 2
	surface_detail_field.step = 1
	surface_detail_field.value = surface_refine
	surface_detail_field.position = Vector2(90, 590)
	surface_detail_field.size = Vector2(PROP_W-108,32)
	surface_detail_field.value_changed.connect(_on_surface_detail_changed)
	properties.add_child(surface_detail_field)
	var smooth_label := Label.new()
	smooth_label.text = "Smooth"
	smooth_label.position = Vector2(16, 641)
	properties.add_child(smooth_label)
	surface_smooth_field = SpinBox.new()
	surface_smooth_field.min_value = 0
	surface_smooth_field.max_value = 60
	surface_smooth_field.step = 1
	surface_smooth_field.value = surface_smooth
	surface_smooth_field.position = Vector2(90, 633)
	surface_smooth_field.size = Vector2(PROP_W-108,32)
	surface_smooth_field.value_changed.connect(_on_surface_smooth_changed)
	properties.add_child(surface_smooth_field)
	_layout_properties()

func _on_surface_detail_changed(value: float) -> void:
	if updating_fields or surface_refine == int(value):
		return
	_record_undo()
	surface_refine = int(value)
	_invalidate_background_surfaces()
	_refresh()

func _on_surface_smooth_changed(value: float) -> void:
	if updating_fields or surface_smooth == int(value):
		return
	_record_undo()
	surface_smooth = int(value)
	_invalidate_background_surfaces()
	_refresh()

func _invalidate_background_surfaces() -> void:
	for i in range(other_curves.size()):
		other_curves[i].erase("surface_mesh")
		other_curves[i].erase("surface_data")

func _layout_properties() -> void:
	if properties == null:
		return
	properties.visible = not zen_mode
	properties.position = Vector2(size.x-PROP_W, HEADER_H)
	properties.size = Vector2(PROP_W, maxf(100.0, size.y-HEADER_H))

func _sync_properties() -> void:
	if property_title == null:
		return
	updating_fields = true
	property_title.text = "%d FRAMES SELECTED" % selected_frames.size() if selected_frames.size() > 1 else ("FRAME %d" % (selected+1) if selected >= 0 else "SELECT A FRAME")
	for field in property_fields:
		field.editable = selected >= 0 and selected_frames.size() <= 1
	if selected >= 0 and selected_frames.size() <= 1:
		var f := frames[selected]
		var values := [f.position.x, f.position.y, f.position.z, f.tangent.x, f.tangent.y, f.tangent.z]
		for i in range(6):
			property_fields[i].value = values[i]
	if surface_info != null:
		if not surface_enabled:
			surface_info.text = "SURFACE  off"
		elif surface_data.has("error"):
			surface_info.text = "SURFACE  invalid boundary"
		else:
			surface_info.text = "SURFACE  %d triangles" % surface_data.get("triangle_count",0)
	updating_fields = false

func _on_property_changed(value: float, row: int) -> void:
	if updating_fields or selected < 0 or selected_frames.size() > 1:
		return
	var f := frames[selected]
	if not is_equal_approx((f.position if row < 3 else f.tangent)[row if row < 3 else row-3], value):
		_record_undo()
	if row < 3:
		var delta := value - f.position[row]
		for index in _move_indices():
			var p := frames[index].position
			p[row] += delta
			frames[index].position = p
	else:
		var t := f.tangent
		t[row-3] = value
		f.tangent = t
	_refresh()

func _layout_preview() -> void:
	if preview == null:
		return
	var r := _panel_rect(3)
	preview.position = r.position + Vector2(1, 26)
	preview.size = r.size - Vector2(2, 27)
	_layout_properties()
	queue_redraw()

func _panel_rect(index: int) -> Rect2:
	var left := 0.0 if zen_mode else RAIL_W
	var top := 0.0 if zen_mode else HEADER_H
	var work_w := size.x if zen_mode else size.x-RAIL_W-PROP_W
	var work_h := size.y if zen_mode else size.y-HEADER_H-FOOTER_H
	var w := maxf(100.0, work_w*0.5)
	var h := maxf(100.0, work_h*0.5)
	return Rect2(Vector2(left + (w if index%2 else 0.0), top + (h if index>=2 else 0.0)), Vector2(w,h))

func _view_at(p: Vector2) -> int:
	for i in range(4):
		if _panel_rect(i).has_point(p):
			return i
	return -1

func _axes(v: Vector3, index: int) -> Vector2:
	match index:
		0: return Vector2(v.x, v.y) # FRONT
		1: return Vector2(v.x, v.z) # TOP
		_: return Vector2(v.z, v.y) # RIGHT

func _project(v: Vector3, index: int) -> Vector2:
	var a := _axes(v, index)
	return _panel_rect(index).get_center() + view_pan[index] + Vector2(a.x, -a.y) * view_zoom[index]

func _unproject(p: Vector2, index: int, old: Vector3) -> Vector3:
	var a := (p - _panel_rect(index).get_center() - view_pan[index]) / view_zoom[index]
	match index:
		0: return Vector3(a.x, -a.y, old.z)
		1: return Vector3(a.x, old.y, -a.y)
		_: return Vector3(old.x, -a.y, a.x)

func _hermite(a: Vector3, b: Vector3, ta: Vector3, tb: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return (2.0*u3-3.0*u2+1.0)*a + (u3-2.0*u2+u)*ta + (-2.0*u3+3.0*u2)*b + (u3-u2)*tb

func _derivative(a: Vector3, b: Vector3, ta: Vector3, tb: Vector3, u: float) -> Vector3:
	var u2 := u*u
	return (6.0*u2-6.0*u)*a + (3.0*u2-4.0*u+1.0)*ta + (-6.0*u2+6.0*u)*b + (3.0*u2-2.0*u)*tb

func _sample_curves() -> Dictionary:
	return {"center":_sample_frame_curve(frames,closed)}

func _sample_frame_curve(frame_set: Array, is_closed: bool, steps: int = SAMPLES) -> PackedVector3Array:
	var center := PackedVector3Array()
	if frame_set.size() < 2:
		return center
	var count := frame_set.size() if is_closed else frame_set.size()-1
	for i in range(count):
		var a: CurveFrame = frame_set[i]
		var b: CurveFrame = frame_set[(i+1) % frame_set.size()]
		if a.position.is_equal_approx(b.position):
			continue
		for k in range(steps + 1):
			if not center.is_empty() and k == 0:
				continue
			var u := float(k) / steps
			var p := _hermite(a.position, b.position, a.tangent, b.tangent, u)
			center.append(p)
	return center

func _surface_boundary_points(frame_set: Array, is_closed: bool) -> PackedVector3Array:
	var steps := clampi(int(512.0/maxi(frame_set.size(),1)),8,24)
	return _sample_frame_curve(frame_set,is_closed,steps)

func _clamp_to_view(p: Vector2, index: int) -> Vector2:
	var r := _panel_rect(index)
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y + 26.0, r.end.y))

func _selection_projection(position: Vector3, index: int) -> Vector2:
	if index < 3:
		return _project(position, index)
	var viewport_size := Vector2(viewport_3d.size)
	return preview.position + camera.unproject_position(position) * (preview.size / viewport_size)

func _box_selection_indices(start: Vector2, finish: Vector2, index: int) -> Array[int]:
	var hits: Array[int] = []
	var box := Rect2(start, finish - start).abs().grow(0.5)
	for i in range(frames.size()):
		if index == 3 and camera.is_position_behind(frames[i].position):
			continue
		if box.has_point(_selection_projection(frames[i].position, index)):
			hits.append(i)
	return hits

func _finish_box_selection() -> void:
	if box_start.distance_to(box_end) < 4.0:
		if not box_additive:
			_select_only(-1)
	else:
		if not box_additive:
			_select_only(-1)
		for index in _box_selection_indices(box_start, box_end, active_view):
			if not selected_frames.has(index):
				selected_frames.append(index)
		selected = selected_frames.back() if not selected_frames.is_empty() else -1
	_sync_properties()
	queue_redraw()
	box_overlay.queue_redraw()

func _draw_box_overlay() -> void:
	if drag_mode != "box":
		return
	var box := Rect2(box_start, box_end - box_start).abs()
	box_overlay.draw_rect(box, Color(0.35, 0.65, 1.0, 0.18))
	box_overlay.draw_rect(box, Color(0.55, 0.78, 1.0), false, 1.5)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if not zen_mode:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, HEADER_H)), Color("111722"))
		draw_rect(Rect2(0, HEADER_H, RAIL_W, size.y-HEADER_H), Color("1b2432"))
		draw_rect(Rect2(size.x-PROP_W, HEADER_H, PROP_W, size.y-HEADER_H), Color("1b2432"))
		_draw_toolbar()
	var curves := _sample_curves()
	for i in range(4):
		var r := _panel_rect(i)
		draw_rect(r, PANEL if i != active_view else Color("253247"))
		draw_rect(r, Color("68788c"), false, 1.0)
		var title: String = ["FRONT  X / Y", "TOP  X / Z", "RIGHT  Z / Y", "PERSPECTIVE  drag to orbit / wheel to zoom"][i]
		draw_string(ThemeDB.fallback_font, r.position + Vector2(12, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		if i < 3:
			_draw_ortho(i, curves)
	if zen_mode:
		draw_rect(Rect2(12, 9, 222, 25), Color(0,0,0,0.55))
		draw_string(ThemeDB.fallback_font, Vector2(20, 27), "ZEN  ·  F11 / Esc to exit", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	else:
		_draw_footer()

func _draw_toolbar() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(15, 28), "3D FRAME CURVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(size.x-PROP_W+16, 28), "PROPERTIES", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b6c5d8"))
	var labels := ["ADD", "INSERT", "DELETE", "CLOSE", "TEMPLATE", "SURFACE", "BLENDER", "EXPORT", "OPEN", "RESET", "ZEN", "UNDO"]
	for j in range(labels.size()):
		var box := _tool_rect(j)
		draw_rect(box, Color("3b618a") if (j == 1 and insert_mode) or (j == 3 and closed) or (j == 5 and surface_enabled) else Color("2c394e"))
		draw_rect(box, Color("657891"), false, 1.0)
		draw_string(ThemeDB.fallback_font, box.position + Vector2(10, 25), labels[j], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

func _tool_rect(j: int) -> Rect2:
	return Rect2(9, HEADER_H + 12 + j*49, RAIL_W-18, 40)

func _toolbar_action(p: Vector2) -> bool:
	if zen_mode or p.x > RAIL_W or p.y < HEADER_H:
		return false
	for j in range(12):
		if _tool_rect(j).has_point(p):
			match j:
				0: _add_frame()
				1: insert_mode = not insert_mode
				2: _delete_frame()
				3:
					_record_undo()
					closed = not closed
				4: template_dialog.popup_centered()
				5: _toggle_surface()
				6: _open_in_blender()
				7: save_dialog.popup_centered_ratio()
				8: load_dialog.popup_centered_ratio()
				9: _reset_sample()
				10: _toggle_zen()
				11: _undo()
			if j in [1,3]:
				_refresh()
			else:
				queue_redraw()
			return true
	return true

func _draw_ortho(index: int, curves: Dictionary) -> void:
	var r := _panel_rect(index)
	var origin := _project(Vector3.ZERO, index)
	for k in range(-20, 21):
		var x := origin.x + k * view_zoom[index]
		var y := origin.y + k * view_zoom[index]
		if x >= r.position.x and x <= r.end.x:
			draw_line(Vector2(x, r.position.y+25), Vector2(x, r.end.y), GRID if k != 0 else Color("b66868"), 1.0)
		if y >= r.position.y+25 and y <= r.end.y:
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), GRID if k != 0 else Color("6eae74"), 1.0)
	for layer in other_curves:
		_draw_polyline(_sample_frame_curve(layer["frames"],layer["closed"]), index, Color("8998ad"), 1.6)
		for frame in layer["frames"]:
			var background_point := _project(frame.position,index)
			if r.grow(-6).has_point(background_point):
				draw_circle(background_point,4,Color("8998ad"))
	_draw_polyline(curves["center"], index, BLUE, 2.8)
	for j in range(frames.size()):
		var f := frames[j]
		var p := _project(f.position, index)
		var t := _project(f.position + f.tangent * HANDLE_FACTOR, index)
		if r.grow(-6).has_point(p):
			draw_line(p, t, BLUE, 1.5)
			draw_circle(t, 5, BLUE)
			draw_circle(p, 7 if selected_frames.has(j) else 5, YELLOW if selected_frames.has(j) else GREEN)
			draw_string(ThemeDB.fallback_font, p + Vector2(10, -7), str(j+1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

func _draw_polyline(points: PackedVector3Array, index: int, color: Color, width: float) -> void:
	var r := _panel_rect(index).grow(-2)
	for j in range(1, points.size()):
		var a := _project(points[j-1], index)
		var b := _project(points[j], index)
		if r.has_point(a) and r.has_point(b):
			draw_line(a, b, color, width, true)

func _draw_footer() -> void:
	var y := size.y - FOOTER_H
	draw_rect(Rect2(0, y, size.x, FOOTER_H), Color("111722"))
	var s := "Drag empty space to box-select · Alt+drag in perspective · Shift adds · Ctrl+Z undo"
	if selected_frames.size() == 1 and selected >= 0 and selected < frames.size():
		var f := frames[selected]
		s = "Frame %d  XYZ (%.2f, %.2f, %.2f)  tangent (%.2f, %.2f, %.2f)    |    %s" % [selected+1, f.position.x, f.position.y, f.position.z, f.tangent.x, f.tangent.y, f.tangent.z, s]
	if Time.get_ticks_msec() < toast_until:
		s = toast
	draw_string(ThemeDB.fallback_font, Vector2(12, y+23), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

func _input(event: InputEvent) -> void:
	if save_dialog.visible or template_save_dialog.visible or load_dialog.visible or template_dialog.visible or template_replace_dialog.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F11, KEY_ESCAPE]:
		if event.keycode == KEY_F11 or zen_mode:
			_toggle_zen()
		return
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and event.ctrl_pressed:
			_undo()
		elif get_viewport().gui_get_focus_owner() == null:
			_key(event)

func _mouse_button(e: InputEventMouseButton) -> void:
	var v := _view_at(e.position)
	if e.button_index == MOUSE_BUTTON_LEFT:
		if not e.pressed:
			if drag_mode == "box":
				box_end = _clamp_to_view(e.position, active_view)
				_finish_box_selection()
			drag_mode = ""
			drag_positions.clear()
			box_overlay.queue_redraw()
			return
		if _toolbar_action(e.position):
			return
		if v < 0:
			return
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()
		active_view = v
		if e.alt_pressed:
			_start_box_selection(e.position, v, e.shift_pressed)
		elif v == 3:
			drag_mode = "orbit"
		elif insert_mode or e.double_click:
			_insert_nearest(e.position, v)
			insert_mode = false
		else:
			var hit := _hit(e.position, v, e.shift_pressed)
			if hit["index"] < 0:
				var other_hit := _hit_other(e.position,v)
				if other_hit["layer"] >= 0:
					_activate_other(other_hit["layer"])
					hit = _hit(e.position,v, e.shift_pressed)
			if hit["index"] < 0:
				_start_box_selection(e.position, v, e.shift_pressed)
			elif e.shift_pressed and hit["part"] == "point":
				_toggle_selected(hit["index"])
				drag_mode = ""
			elif hit["index"] >= 0 and selected_frames.size() > 1 and selected_frames.has(hit["index"]) and hit["part"] == "point":
				selected = hit["index"]
				drag_mode = "point"
			else:
				_select_only(hit["index"])
				drag_mode = hit["part"]
			drag_start = e.position
			drag_positions.clear()
			if drag_mode == "point":
				for index in _move_indices():
					drag_positions[index] = frames[index].position
			if drag_mode != "box":
				_sync_properties()
	elif e.button_index == MOUSE_BUTTON_MIDDLE:
		if e.pressed and v >= 0 and v < 3:
			active_view = v
		drag_mode = "pan" if e.pressed and v < 3 and v >= 0 else ""
	elif e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var factor := 1.12 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.12
		if v == 3:
			orbit_distance = clampf(orbit_distance/factor, 2.0, 80.0)
			_update_camera()
		elif v >= 0:
			var old_world := _unproject(e.position, v, Vector3.ZERO)
			view_zoom[v] = clampf(view_zoom[v]*factor, 15.0, 300.0)
			var new_screen := _project(old_world, v)
			view_pan[v] += e.position-new_screen
	queue_redraw()

func _mouse_motion(e: InputEventMouseMotion) -> void:
	if drag_mode == "box":
		box_end = _clamp_to_view(e.position, active_view)
		box_overlay.queue_redraw()
	elif drag_mode == "orbit":
		orbit_yaw -= e.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch - e.relative.y*0.008, -1.45, 1.45)
		_update_camera()
	elif drag_mode == "pan" and active_view < 3:
		view_pan[active_view] += e.relative
	elif selected >= 0 and active_view < 3 and drag_mode != "":
		var f := frames[selected]
		match drag_mode:
			"point":
				if not drag_positions.is_empty():
					if not drag_positions.has("recorded"):
						_record_undo()
						drag_positions["recorded"] = true
					var delta := _unproject(e.position, active_view, Vector3.ZERO) - _unproject(drag_start, active_view, Vector3.ZERO)
					for index in drag_positions:
						if index is int:
							frames[index].position = drag_positions[index] + delta
			"tangent":
				if not drag_positions.has("recorded"):
					_record_undo()
					drag_positions["recorded"] = true
				f.tangent = (_unproject(e.position, active_view, f.position + f.tangent*HANDLE_FACTOR) - f.position) / HANDLE_FACTOR
		_refresh()
	if drag_mode != "":
		queue_redraw()

func _start_box_selection(p: Vector2, view: int, additive: bool) -> void:
	active_view = view
	box_start = _clamp_to_view(p, view)
	box_end = box_start
	box_additive = additive
	drag_mode = "box"
	box_overlay.queue_redraw()

func _hit(p: Vector2, v: int, prefer_unselected: bool = false) -> Dictionary:
	var best := 13.0
	var result := {"index": -1, "part": ""}
	for j in range(frames.size()):
		var f := frames[j]
		var handles := [f.position, f.position + f.tangent*HANDLE_FACTOR]
		for k in range(2):
			var d := p.distance_to(_project(handles[k], v))
			if d < best or (prefer_unselected and k == 0 and is_equal_approx(d,best) and not selected_frames.has(j)):
				best = d
				result = {"index": j, "part": ["point", "tangent"][k]}
	return result

func _hit_other(p: Vector2, v: int) -> Dictionary:
	var best := 13.0
	var result := {"layer":-1}
	for layer_index in range(other_curves.size()):
		for frame in other_curves[layer_index]["frames"]:
			var d := p.distance_to(_project(frame.position,v))
			if d < best:
				best = d
				result = {"layer":layer_index}
	return result

func _activate_other(index: int) -> void:
	_record_undo()
	var saved := {"frames":frames,"closed":closed,"surface":surface_enabled,"surface_data":surface_data,"surface_mesh":surface_node.mesh}
	var layer := other_curves[index]
	frames = layer["frames"]
	closed = layer["closed"]
	surface_enabled = bool(layer.get("surface",false))
	surface_data = layer.get("surface_data",{})
	other_curves[index] = saved
	_select_only(-1)
	_refresh()

func _insert_nearest(p: Vector2, v: int) -> void:
	var best := 14.0
	var best_segment := -1
	var best_u := 0.0
	var count := frames.size() if closed else frames.size()-1
	for i in range(count):
		var a := frames[i]
		var b := frames[(i+1)%frames.size()]
		if a.position.is_equal_approx(b.position):
			continue
		for k in range(1, SAMPLES):
			var u := float(k)/SAMPLES
			var d := _project(_hermite(a.position,b.position,a.tangent,b.tangent,u),v).distance_to(p)
			if d < best:
				best = d
				best_segment = i
				best_u = u
	if best_segment < 0:
		_message("Click near the blue curve to insert a frame")
		return
	var a := frames[best_segment]
	var b := frames[(best_segment+1)%frames.size()]
	var pos := _hermite(a.position,b.position,a.tangent,b.tangent,best_u)
	var tan := _derivative(a.position,b.position,a.tangent,b.tangent,best_u)
	_record_undo()
	selected = best_segment+1
	selected_frames = [selected]
	frames.insert(selected, CurveFrame.new(pos,tan))
	_refresh()

func _add_frame() -> void:
	_record_undo()
	var last: CurveFrame = frames.back()
	frames.append(CurveFrame.new(last.position + last.tangent.normalized()*2.0, last.tangent))
	selected = frames.size()-1
	selected_frames = [selected]
	_refresh()

func _delete_frame() -> void:
	if selected >= 0 and frames.size() > 2:
		_record_undo()
		var indices := selected_frames.duplicate()
		indices.sort()
		indices.reverse()
		for index in indices:
			if frames.size() > 2:
				frames.remove_at(index)
		selected = mini(selected, frames.size()-1)
		selected_frames = [selected]
		_refresh()

func _key(e: InputEventKey) -> void:
	if e.keycode == KEY_Z and e.ctrl_pressed:
		_undo()
		return
	match e.keycode:
		KEY_A: _add_frame()
		KEY_F: insert_mode = not insert_mode
		KEY_DELETE: _delete_frame()
		KEY_C:
			_record_undo()
			closed = not closed
		KEY_X: save_dialog.popup_centered_ratio()
		KEY_O: load_dialog.popup_centered_ratio()
		KEY_T: template_dialog.popup_centered()
		KEY_S: _toggle_surface()
		KEY_B: _open_in_blender()
		KEY_R: _reset_sample()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if selected >= 0 and active_view < 3:
				_record_undo()
				var delta := Vector2(-1 if e.keycode == KEY_LEFT else 1 if e.keycode == KEY_RIGHT else 0, -1 if e.keycode == KEY_UP else 1 if e.keycode == KEY_DOWN else 0) * (0.2 if e.shift_pressed else 0.02)
				for index in _move_indices():
					var f := frames[index]
					f.position = _unproject(_project(f.position,active_view)+Vector2(delta.x,-delta.y)*view_zoom[active_view],active_view,f.position)
	_refresh()

func _toggle_zen() -> void:
	zen_mode = not zen_mode
	if zen_mode:
		old_window_mode = DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(old_window_mode)
	_layout_preview()
	_layout_properties()
	queue_redraw()

func _toggle_surface() -> void:
	_record_undo()
	if surface_enabled:
		surface_enabled = false
		_refresh()
		_message("Surface hidden")
		return
	# A surface action always has a usable boundary, even when no frame is selected.
	if not closed:
		closed = true
	surface_enabled = true
	_refresh()
	if surface_data.has("error"):
		_message(str(surface_data["error"]))
		surface_enabled = false
		_refresh()
	else:
		_message("Surface generated: %d triangles" % surface_data.get("triangle_count",0))

func _refresh() -> void:
	if geometry_root != null:
		_update_dynamic_3d()
	_sync_properties()
	queue_redraw()

func _make_line(points: PackedVector3Array, color: Color, independent: bool = false) -> void:
	if points.size() < 2:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1,points.size()):
		if independent and i % 2 == 0:
			continue
		mesh.surface_add_vertex(points[i-1])
		mesh.surface_add_vertex(points[i])
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	node.material_override = mat
	geometry_root.add_child(node)

func _line_mesh(points: PackedVector3Array, independent: bool = false) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, points.size()):
		if independent and i % 2 == 0:
			continue
		mesh.surface_add_vertex(points[i-1])
		mesh.surface_add_vertex(points[i])
	mesh.surface_end()
	return mesh

func _line_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat

func _build_static_3d() -> void:
	for axis in range(3):
		var points := PackedVector3Array()
		for k in range(-10,11):
			var a := Vector3.ZERO
			var b := Vector3.ZERO
			if axis == 0:
				a = Vector3(k,0,-10); b = Vector3(k,0,10)
			elif axis == 1:
				a = Vector3(-10,0,k); b = Vector3(10,0,k)
			else:
				continue
			points.append(a); points.append(b)
		_make_line(points, Color("384350"), true)
	_make_line(PackedVector3Array([Vector3(-10,0,0),Vector3(10,0,0)]), Color("de6868"))
	_make_line(PackedVector3Array([Vector3(0,-5,0),Vector3(0,5,0)]), Color("79cb80"))
	_make_line(PackedVector3Array([Vector3(0,0,-10),Vector3(0,0,10)]), Color("7c9fe6"))
	background_curve_node = MeshInstance3D.new()
	background_curve_node.material_override = _line_material(Color("8998ad"))
	geometry_root.add_child(background_curve_node)
	surface_node = MeshInstance3D.new()
	var surface_mat := StandardMaterial3D.new()
	surface_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface_mat.albedo_color = Color(0.18,0.76,0.82,0.72)
	surface_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface_node.material_override = surface_mat
	geometry_root.add_child(surface_node)
	curve_node = MeshInstance3D.new()
	curve_node.material_override = _line_material(BLUE)
	geometry_root.add_child(curve_node)
	tangent_node = MeshInstance3D.new()
	tangent_node.material_override = _line_material(BLUE)
	geometry_root.add_child(tangent_node)
	marker_mesh = SphereMesh.new()
	marker_mesh.radius = 0.075
	marker_mesh.height = 0.15
	marker_material = _line_material(GREEN)
	selected_material = _line_material(YELLOW)

func _update_dynamic_3d() -> void:
	if surface_enabled:
		surface_data = surface_builder.build(_surface_boundary_points(frames,closed),surface_refine,surface_smooth) if closed else {"error":"Curve is open"}
	else:
		surface_data = {}
	var error_text := str(surface_data.get("error",""))
	if error_text != "" and error_text != last_surface_error:
		_message(error_text)
	last_surface_error = error_text
	surface_node.mesh = _surface_mesh(surface_data) if surface_data.has("vertices") else null
	while background_surface_nodes.size() < other_curves.size():
		var node := MeshInstance3D.new()
		node.material_override = surface_node.material_override
		geometry_root.add_child(node)
		background_surface_nodes.append(node)
	while background_surface_nodes.size() > other_curves.size():
		var node: MeshInstance3D = background_surface_nodes.pop_back()
		geometry_root.remove_child(node)
		node.queue_free()
	for layer_index in range(other_curves.size()):
		var layer := other_curves[layer_index]
		if layer.get("surface",false) and layer["closed"]:
			if not layer.has("surface_mesh") or layer["surface_mesh"] == null:
				var data: Dictionary = surface_builder.build(_surface_boundary_points(layer["frames"],layer["closed"]),surface_refine,surface_smooth)
				layer["surface_data"] = data
				layer["surface_mesh"] = _surface_mesh(data) if data.has("vertices") else null
				other_curves[layer_index] = layer
			background_surface_nodes[layer_index].mesh = layer["surface_mesh"]
		else:
			background_surface_nodes[layer_index].mesh = null
	var c := _sample_curves()
	var background_segments := PackedVector3Array()
	for layer in other_curves:
		var points := _sample_frame_curve(layer["frames"],layer["closed"])
		for i in range(1,points.size()):
			background_segments.append(points[i-1])
			background_segments.append(points[i])
	background_curve_node.mesh = _line_mesh(background_segments,true) if not background_segments.is_empty() else null
	curve_node.mesh = _line_mesh(c["center"])
	var tangent_points := PackedVector3Array()
	for f in frames:
		tangent_points.append(f.position)
		tangent_points.append(f.position+f.tangent*HANDLE_FACTOR)
	tangent_node.mesh = _line_mesh(tangent_points, true)
	while marker_nodes.size() < frames.size():
		var marker := MeshInstance3D.new()
		marker.mesh = marker_mesh
		geometry_root.add_child(marker)
		marker_nodes.append(marker)
	while marker_nodes.size() > frames.size():
		var marker: MeshInstance3D = marker_nodes.pop_back()
		geometry_root.remove_child(marker)
		marker.queue_free()
	for i in range(frames.size()):
		marker_nodes[i].position = frames[i].position
		marker_nodes[i].material_override = selected_material if selected_frames.has(i) else marker_material

func _surface_mesh(data: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _update_camera() -> void:
	var cp := cos(orbit_pitch)
	camera.position = orbit_target + Vector3(sin(orbit_yaw)*cp, sin(orbit_pitch), cos(orbit_yaw)*cp)*orbit_distance
	camera.look_at(orbit_target, Vector3.UP)

func _vec(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func _from_array(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func _write_blender_payload() -> Dictionary:
	var folder := OS.get_user_data_dir().path_join("blender_exports")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		_message("Could not create Blender export folder")
		return {}
	var stamp := str(Time.get_unix_time_from_system())
	var data_path := folder.path_join("frame_curve_"+stamp+".json")
	var script_path := folder.path_join("blender_import_curve_"+stamp+".py")
	var bridge_path := folder.path_join("blender_bridge.ps1")
	var receipt_path := folder.path_join("frame_curve_"+stamp+".imported")
	_save_file(data_path)
	if not FileAccess.file_exists(data_path):
		return {}
	var script := FileAccess.open(script_path,FileAccess.WRITE)
	if script == null:
		_message("Could not write Blender import script")
		return {}
	script.store_string(BLENDER_IMPORT_SCRIPT.replace("__PAYLOAD_PATH__",JSON.stringify(data_path)).replace("__RECEIPT_PATH__",JSON.stringify(receipt_path)))
	script.close()
	var bridge := FileAccess.open(bridge_path,FileAccess.WRITE)
	if bridge == null:
		_message("Could not write Blender bridge")
		return {}
	bridge.store_string(FileAccess.get_file_as_string("res://scripts/blender_bridge.ps1"))
	bridge.close()
	return {"data":data_path,"script":script_path,"bridge":bridge_path,"receipt":receipt_path}

func _open_in_blender() -> void:
	if not FileAccess.file_exists(BLENDER_EXE):
		_message("Blender was not found at " + BLENDER_EXE)
		return
	var paths := _write_blender_payload()
	if paths.is_empty():
		return
	var output := []
	var result := OS.execute("powershell.exe",["-NoProfile","-STA","-ExecutionPolicy","Bypass","-File",paths["bridge"],"-ImportScript",paths["script"],"-Receipt",paths["receipt"]],output,true)
	if result == 0:
		_message("Imported into the open Blender scene")
	elif result == 2:
		var pid := OS.create_process(BLENDER_EXE,["--python",paths["script"]])
		_message("Opening Blender with the current 3D curve" if pid > 0 else "Could not start Blender")
	else:
		_message("Blender import failed: " + (str(output[0]).strip_edges() if not output.is_empty() else "could not reach the open window"))

func _save_file(path: String) -> bool:
	var names := ["active_curve"]
	var sets := [_sample_frame_curve(frames,closed)]
	var closures := [closed]
	var export_surface: Dictionary = surface_builder.build(_surface_boundary_points(frames,closed),surface_refine,surface_smooth) if surface_enabled and closed else {}
	var surface_sets: Array[Dictionary] = []
	if export_surface.has("vertices"):
		surface_sets.append({"name":"active_surface","data":export_surface})
	for i in range(other_curves.size()):
		names.append("curve_%d" % (i+1))
		sets.append(_sample_frame_curve(other_curves[i]["frames"],other_curves[i]["closed"]))
		closures.append(other_curves[i]["closed"])
		if other_curves[i].get("surface",false) and other_curves[i]["closed"]:
			var layer_surface: Dictionary = surface_builder.build(_surface_boundary_points(other_curves[i]["frames"],other_curves[i]["closed"]),surface_refine,surface_smooth)
			if layer_surface.has("vertices"):
				surface_sets.append({"name":"surface_curve_%d" % (i+1),"data":layer_surface})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_message("Could not write " + path)
		return false
	if path.get_extension().to_lower() == "obj":
		file.store_line("# 3D Frame Curve Board; X Y Z; polyline geometry")
		var base := 1
		for j in range(sets.size()):
			file.store_line("o " + names[j])
			for p in sets[j]:
				file.store_line("v %.8f %.8f %.8f" % [p.x,p.y,p.z])
			var indices := PackedStringArray()
			for k in range(sets[j].size()):
				indices.append(str(base+k))
			file.store_line("l " + " ".join(indices))
			base += sets[j].size()
		for surface in surface_sets:
			file.store_line("o " + surface["name"])
			var data: Dictionary = surface["data"]
			for p in data["vertices"]:
				file.store_line("v %.8f %.8f %.8f" % [p.x,p.y,p.z])
			for k in range(0,data["indices"].size(),3):
				file.store_line("f %d %d %d" % [base+data["indices"][k],base+data["indices"][k+1],base+data["indices"][k+2]])
			base += data["vertices"].size()
	else:
		var frame_data := []
		for f in frames:
			frame_data.append({"position":_vec(f.position),"tangent":_vec(f.tangent)})
		var layer_data := []
		for layer in other_curves:
			var layer_frames := []
			for f in layer["frames"]:
				layer_frames.append({"position":_vec(f.position),"tangent":_vec(f.tangent)})
			layer_data.append({"closed":layer["closed"],"surface":layer.get("surface",false),"frames":layer_frames})
		var curve_data := []
		for j in range(sets.size()):
			var points := []
			for p in sets[j]: points.append(_vec(p))
			curve_data.append({"name":names[j],"closed":closures[j],"points":points})
		var surface_json := _surface_to_json(export_surface)
		var surfaces_json := []
		for surface in surface_sets:
			var entry: Dictionary = _surface_to_json(surface["data"])
			entry["name"] = surface["name"]
			surfaces_json.append(entry)
		file.store_string(JSON.stringify({"format":"frame_curve_3d_v1","closed":closed,"frames":frame_data,"layers":layer_data,"curves":curve_data,"surface_enabled":surface_enabled,"surface_refine":surface_refine,"surface_smooth":surface_smooth,"surface":surface_json,"surfaces":surfaces_json}, "  "))
	file.close()
	_message("Saved " + path)
	return true

func _surface_to_json(data: Dictionary) -> Dictionary:
	if not data.has("vertices"):
		return {}
	var vertices := []
	for p in data["vertices"]:
		vertices.append(_vec(p))
	return {"vertices":vertices,"indices":Array(data["indices"]),"triangle_count":data["triangle_count"],"boundary_count":data["boundary_count"]}

func _load_file(path: String) -> void:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		_message("Could not open " + path)
		return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("format","") != "frame_curve_3d_v1" or not data.get("frames",null) is Array:
		_message("Invalid 3D curve JSON")
		return
	var loaded := _parse_frames(data["frames"])
	if loaded.size() < 2:
		_message("At least two valid frames are required")
		return
	_record_undo()
	frames = loaded
	other_curves.clear()
	closed = bool(data.get("closed",false))
	surface_enabled = bool(data.get("surface_enabled",false))
	_select_only(-1)
	surface_refine = clampi(int(data.get("surface_refine",1)),0,2)
	surface_smooth = clampi(int(data.get("surface_smooth",20)),0,60)
	surface_detail_field.value = surface_refine
	surface_smooth_field.value = surface_smooth
	_refresh()
	_message("Opened " + path)

func _parse_frames(entries: Array) -> Array[CurveFrame]:
	var loaded: Array[CurveFrame] = []
	for entry in entries:
		if not entry is Dictionary or not entry.get("position",null) is Array or not entry.get("tangent",null) is Array:
			return []
		if entry["position"].size() != 3 or entry["tangent"].size() != 3:
			return []
		loaded.append(CurveFrame.new(_from_array(entry["position"]),_from_array(entry["tangent"])))
	return loaded

func _message(s: String) -> void:
	toast = s
	toast_until = Time.get_ticks_msec()+4500
	queue_redraw()
