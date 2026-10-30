extends Control

class CoordFrame2D:
	var origin: Vector2
	var angle: float
	var radius: float
	var scale_t: float = 1.0
	var scale_n: float = 0.0
	var scale_w: float
	var tag: String
	var tangent_length: float = -1.0

	func _init(p_origin: Vector2, p_angle: float, p_radius: float = 24.0, p_weight: float = 1.0, p_tag: String = "") -> void:
		origin = p_origin
		angle = p_angle
		radius = p_radius
		scale_w = p_weight
		tag = p_tag

	func tangent() -> Vector2:
		return Vector2(cos(angle), sin(angle))

	func normal() -> Vector2:
		var t := tangent()
		return Vector2(-t.y, t.x)


const BG := Color(0.085, 0.098, 0.125)
const GRID_MAJOR := Color(0.25, 0.28, 0.34, 0.55)
const GRID_MINOR := Color(0.18, 0.20, 0.25, 0.45)
const HERMITE := Color(0.18, 0.54, 0.95)
const OFFSET := Color(0.18, 0.78, 0.45)
const POLY := Color(0.95, 0.28, 0.25)
const TANGENT := Color(0.20, 0.62, 1.0)
const NORMAL := Color(1.0, 0.61, 0.23)
const POINT := Color(0.28, 0.86, 0.52)
const SELECTED := Color(1.0, 0.95, 0.35)
const TANGENT_HANDLE_LEN := 92.0
const POINT_HIT_RADIUS := 20.0
const TANGENT_HIT_RADIUS := 18.0
const RADIUS_HIT_RADIUS := 18.0
const BLENDER_EXE := "C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe"
const BLENDER_IMPORT_SCRIPT := """
import bpy
import json
import sys
from pathlib import Path
from mathutils import Quaternion

args = sys.argv[sys.argv.index("--") + 1:]
data = json.loads(Path(args[0]).read_text(encoding="utf-8"))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
all_xy = []
created_objects = 0

for entry in data["curves"]:
    name = entry["name"]
    samples = entry["points"]
    if len(samples) < 2:
        continue
    if data["closed"] and samples[0] == samples[-1]:
        samples = samples[:-1]
    curve = bpy.data.curves.new(name, type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.0
    curve.extrude = 0.0
    curve.bevel_object = None
    curve.taper_object = None
    spline = curve.splines.new("POLY")
    spline.points.add(len(samples) - 1)
    for point, sample in zip(spline.points, samples):
        point.co = (sample["x"] * 0.01, -sample["y"] * 0.01, 0.0, 1.0)
        all_xy.append((point.co.x, point.co.y))
    spline.use_cyclic_u = data["closed"]
    obj = bpy.data.objects.new(name, curve)
    obj.display_type = "WIRE"
    bpy.context.collection.objects.link(obj)
    created_objects += 1
    mat = bpy.data.materials.new(name + " Color")
    mat.diffuse_color = (0.10, 0.72, 0.32, 1.0)
    curve.materials.append(mat)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

for area in (bpy.context.screen.areas if bpy.context.screen and not bpy.app.background else []):
    if area.type == "VIEW_3D":
        area.spaces.active.shading.color_type = "MATERIAL"
        view = area.spaces.active.region_3d
        view.view_perspective = "ORTHO"
        view.view_rotation = Quaternion((1.0, 0.0, 0.0, 0.0))
        if all_xy:
            min_x = min(p[0] for p in all_xy)
            max_x = max(p[0] for p in all_xy)
            min_y = min(p[1] for p in all_xy)
            max_y = max(p[1] for p in all_xy)
            view.view_location = ((min_x + max_x) * 0.5, (min_y + max_y) * 0.5, 0.0)
            view.view_distance = max(max_x - min_x, max_y - min_y, 1.0) * 1.6

assert created_objects >= 1
depsgraph = bpy.context.evaluated_depsgraph_get()
for obj in bpy.context.selected_objects:
    mesh = obj.evaluated_get(depsgraph).to_mesh()
    face_count = len(mesh.polygons)
    obj.evaluated_get(depsgraph).to_mesh_clear()
    assert face_count == 0, f"{obj.name} unexpectedly has {face_count} surface faces"
print(f"Frame polylines imported into Blender: {created_objects} curves, 0 surface faces")
"""

var frames: Array[CoordFrame2D] = []
var segment_durations: Array[float] = []
var closed := false
var view_offset := Vector2(640.0, 430.0)
var zoom := 1.0
var selected := -1
var drag_mode := ""
var normal_drag_gap := 0.0
var radius_drag_start_world := Vector2.ZERO
var radius_drag_start_value := 0.0
var insert_frame_mode := false
var show_polyline := true
var show_offsets := true
var samples_per_segment := 40
var last_message := ""
var toast_until_msec := 0
var export_dialog: FileDialog
var fit_dialog: ConfirmationDialog
var fit_source_option: OptionButton
var fit_model_option: OptionButton
var fit_info_label: Label
var fit_curves: Array = []
var fit_candidates: Array = []
var analytic_fitter: RefCounted


func _ready() -> void:
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_reset_sample()
	export_dialog = FileDialog.new()
	export_dialog.title = "Export curve"
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.use_native_dialog = true
	export_dialog.filters = PackedStringArray([
		"*.svg ; SVG curves (Blender)",
		"*.obj ; Wavefront OBJ edges (Blender)",
		"*.csv ; CSV samples",
		"*.json ; JSON curve data",
		"*.png ; PNG image"
	])
	export_dialog.file_selected.connect(_on_export_file_selected)
	add_child(export_dialog)
	analytic_fitter = load("res://scripts/analytic_fit.gd").new()
	fit_dialog = ConfirmationDialog.new()
	fit_dialog.title = "Fit Analytic Curve"
	fit_dialog.confirmed.connect(_apply_analytic_fit)
	var fit_content := VBoxContainer.new()
	fit_source_option = OptionButton.new()
	fit_source_option.item_selected.connect(_on_fit_source_selected)
	fit_content.add_child(fit_source_option)
	fit_model_option = OptionButton.new()
	fit_model_option.item_selected.connect(_on_fit_model_selected)
	fit_content.add_child(fit_model_option)
	fit_info_label = Label.new()
	fit_content.add_child(fit_info_label)
	fit_dialog.add_child(fit_content)
	add_child(fit_dialog)


func _reset_sample() -> void:
	frames = [
		CoordFrame2D.new(Vector2(-360.0, 120.0), deg_to_rad(-20.0), 30.0, 1.0, "start"),
		CoordFrame2D.new(Vector2(-150.0, -90.0), deg_to_rad(-65.0), 42.0, 0.9, "handle"),
		CoordFrame2D.new(Vector2(120.0, -20.0), deg_to_rad(35.0), 34.0, 1.1, "handle"),
		CoordFrame2D.new(Vector2(360.0, -150.0), deg_to_rad(-10.0), 26.0, 1.0, "end")
	]
	segment_durations = [1.0, 1.0, 1.0]
	closed = false
	selected = -1
	insert_frame_mode = false
	queue_redraw()


func _segment_count() -> int:
	return frames.size() if closed else maxi(frames.size() - 1, 0)


func _input(event: InputEvent) -> void:
	if (export_dialog != null and export_dialog.visible) or (fit_dialog != null and fit_dialog.visible):
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at(event.position, 1.1)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at(event.position, 1.0 / 1.1)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _handle_toolbar_click(event.position):
				drag_mode = ""
			elif insert_frame_mode or event.double_click:
				var curve_hit := _nearest_curve_parameter(event.position)
				if curve_hit.is_empty():
					if insert_frame_mode:
						_set_status("Click near a blue or green curve")
				else:
					_insert_frame_on_curve(curve_hit)
					insert_frame_mode = false
				drag_mode = ""
			else:
				var hit := _hit_test(event.position)
				selected = hit["index"]
				drag_mode = "radius" if event.alt_pressed and hit["mode"] == "normal_scale" else hit["mode"]
				if selected >= 0 and hit["mode"] == "normal_scale":
					var f := frames[selected]
					normal_drag_gap = maxf(22.0 / zoom - f.radius * f.scale_n, 0.0)
					radius_drag_start_world = screen_to_world(event.position)
					radius_drag_start_value = f.radius
		else:
			drag_mode = ""
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			var hit := _hit_test(event.position)
			if hit["index"] >= 0:
				selected = hit["index"]
				drag_mode = "rotate"
		else:
			drag_mode = ""
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		drag_mode = "pan" if event.pressed else ""
	queue_redraw()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var world := screen_to_world(event.position)
	if drag_mode == "point" and selected >= 0:
		frames[selected].origin = world
	elif drag_mode == "tangent" and selected >= 0:
		var d := world - frames[selected].origin
		if d.length() > 0.001:
			frames[selected].angle = d.angle()
			frames[selected].scale_t = clamp(d.length() / TANGENT_HANDLE_LEN, 0.05, 4.0)
	elif drag_mode == "rotate" and selected >= 0:
		var d := world - frames[selected].origin
		if d.length() > 0.001:
			frames[selected].angle = d.angle()
	elif drag_mode == "radius" and selected >= 0:
		var f := frames[selected]
		var change := (world - radius_drag_start_world).dot(f.normal())
		f.radius = clamp(radius_drag_start_value + change / maxf(f.scale_n, 1.0), 2.0, 160.0)
	elif drag_mode == "normal_scale" and selected >= 0:
		var f := frames[selected]
		var distance := (world - f.origin).dot(f.normal()) - normal_drag_gap
		f.scale_n = clamp(distance / maxf(f.radius, 0.001), 0.0, 4.0)
	elif drag_mode == "pan":
		view_offset += event.relative
	if drag_mode != "":
		queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_A:
		var p := screen_to_world(get_viewport().get_mouse_position())
		frames.append(CoordFrame2D.new(p, 0.0, 28.0, 1.0, "new"))
		segment_durations.append(1.0)
		selected = frames.size() - 1
	elif event.keycode == KEY_DELETE and selected >= 0 and frames.size() > 2:
		_delete_selected_frame()
	elif event.keycode == KEY_F:
		insert_frame_mode = not insert_frame_mode
		_set_status("Click blue or green curve to insert a frame" if insert_frame_mode else "Frame insertion cancelled")
	elif event.keycode == KEY_C:
		_toggle_closed()
	elif event.keycode == KEY_P:
		show_polyline = not show_polyline
	elif event.keycode == KEY_O:
		show_offsets = not show_offsets
	elif event.keycode == KEY_N and selected >= 0:
		frames[selected].scale_n = 1.0 if frames[selected].scale_n <= 0.0001 else 0.0
		_set_status("Normal scale n=%.2f" % frames[selected].scale_n)
	elif event.keycode == KEY_R:
		_reset_sample()
	elif event.keycode == KEY_X or event.keycode == KEY_I:
		_show_export_dialog()
	elif selected >= 0 and (event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS):
		frames[selected].scale_w = minf(frames[selected].scale_w + 0.1, 5.0)
	elif selected >= 0 and event.keycode == KEY_MINUS:
		frames[selected].scale_w = maxf(frames[selected].scale_w - 0.1, 0.1)
	elif selected >= 0 and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		_nudge_selected(event.keycode, 10.0 if event.shift_pressed else 2.0)
	elif selected >= 0 and event.keycode == KEY_Q:
		frames[selected].angle -= deg_to_rad(15.0 if event.shift_pressed else 3.0)
	elif selected >= 0 and event.keycode == KEY_E:
		frames[selected].angle += deg_to_rad(15.0 if event.shift_pressed else 3.0)
	queue_redraw()


func _toggle_closed() -> void:
	closed = not closed
	if closed:
		segment_durations.append(1.0)
	else:
		segment_durations.remove_at(segment_durations.size() - 1)
	_set_status("Curve closed" if closed else "Curve open")


func _delete_selected_frame() -> void:
	var index := selected
	if closed:
		var incoming := (index - 1 + frames.size()) % frames.size()
		segment_durations[incoming] += segment_durations[index]
		segment_durations.remove_at(index)
	elif index == 0:
		segment_durations.remove_at(0)
	elif index == frames.size() - 1:
		segment_durations.remove_at(segment_durations.size() - 1)
	else:
		segment_durations[index - 1] += segment_durations[index]
		segment_durations.remove_at(index)
	frames.remove_at(index)
	selected = mini(index, frames.size() - 1)


func _nudge_selected(keycode: Key, step: float) -> void:
	if keycode == KEY_LEFT:
		frames[selected].origin.x -= step
	elif keycode == KEY_RIGHT:
		frames[selected].origin.x += step
	elif keycode == KEY_UP:
		frames[selected].origin.y -= step
	elif keycode == KEY_DOWN:
		frames[selected].origin.y += step


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	_draw_grid()
	var centerline := _sample_hermite_curve()
	_draw_curve(centerline, HERMITE, 2.5)
	if show_offsets:
		if _has_offset_width():
			var offsets := _sample_offset_curves(centerline)
			_draw_curve(offsets["left"], OFFSET, 1.8)
			_draw_curve(offsets["right"], OFFSET, 1.8)
		else:
			_draw_curve(centerline, OFFSET, 3.0)
	if show_polyline:
		_draw_polyline_reference()
	_draw_frames()
	_draw_toolbar()
	_draw_status_toast()


func _draw_curve(points: Array[Vector2], color: Color, width: float) -> void:
	if points.size() >= 2:
		var screen_points := PackedVector2Array()
		for p in points:
			screen_points.append(world_to_screen(p))
		draw_polyline(screen_points, color, width, true)


func _draw_grid() -> void:
	var top_left := screen_to_world(Vector2.ZERO)
	var bottom_right := screen_to_world(size)
	var step := 50.0
	var x: float = floor(top_left.x / step) * step
	while x <= bottom_right.x:
		var color := GRID_MAJOR if abs(fmod(x, 200.0)) < 0.1 else GRID_MINOR
		draw_line(world_to_screen(Vector2(x, top_left.y)), world_to_screen(Vector2(x, bottom_right.y)), color, 1.0)
		x += step
	var y: float = floor(top_left.y / step) * step
	while y <= bottom_right.y:
		var color := GRID_MAJOR if abs(fmod(y, 200.0)) < 0.1 else GRID_MINOR
		draw_line(world_to_screen(Vector2(top_left.x, y)), world_to_screen(Vector2(bottom_right.x, y)), color, 1.0)
		y += step
	draw_line(world_to_screen(Vector2(top_left.x, 0.0)), world_to_screen(Vector2(bottom_right.x, 0.0)), Color(0.42, 0.44, 0.50), 1.4)
	draw_line(world_to_screen(Vector2(0.0, top_left.y)), world_to_screen(Vector2(0.0, bottom_right.y)), Color(0.42, 0.44, 0.50), 1.4)


func _draw_frames() -> void:
	for i in frames.size():
		var f := frames[i]
		var p := world_to_screen(f.origin)
		var t_end := world_to_screen(f.origin + f.tangent() * TANGENT_HANDLE_LEN * f.scale_t)
		var n_end := world_to_screen(f.origin + f.normal() * 58.0)
		var r_end := _normal_handle_screen(f)
		draw_line(p, t_end, TANGENT, 3.0, true)
		draw_line(p, n_end, NORMAL, 2.5, true)
		draw_arc(t_end, 10.0, 0.0, TAU, 48, TANGENT, 2.0)
		draw_circle(t_end, 7.0, TANGENT)
		draw_arc(r_end, 10.0, 0.0, TAU, 48, OFFSET, 2.0)
		draw_circle(r_end, 6.5, OFFSET)
		if f.scale_n > 0.001:
			draw_arc(p, f.radius * f.scale_n * zoom, 0.0, TAU, 72, Color(0.18, 0.78, 0.45, 0.22), 1.2)
		draw_circle(p, 11.0 if i == selected else 8.0, SELECTED if i == selected else POINT)
		draw_string(ThemeDB.fallback_font, p + Vector2(12, -12), "#%d  t=%.2f  n=%.2f  r=%.1f  w=%.2f" % [i, f.scale_t, f.scale_n, f.radius, f.scale_w], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.88, 0.90, 0.94))


func _normal_handle_screen(frame: CoordFrame2D) -> Vector2:
	var visible_distance := maxf(frame.radius * frame.scale_n * zoom, 22.0)
	return world_to_screen(frame.origin) + frame.normal() * visible_distance


func _draw_polyline_reference() -> void:
	var points: Array[Vector2] = []
	for f in frames:
		points.append(f.origin)
	if closed and not points.is_empty():
		points.append(points[0])
	_draw_curve(points, POLY, 1.8)


func _toolbar_buttons() -> Array:
	var x := size.x - 500.0
	return [
		{"rect": Rect2(Vector2(x, 16.0), Vector2(82.0, 30.0)), "label": "Frame", "action": "frame"},
		{"rect": Rect2(Vector2(x + 88.0, 16.0), Vector2(102.0, 30.0)), "label": "Closed" if closed else "Open", "action": "closed"},
		{"rect": Rect2(Vector2(x + 196.0, 16.0), Vector2(92.0, 30.0)), "label": "Fit", "action": "fit"},
		{"rect": Rect2(Vector2(x + 294.0, 16.0), Vector2(92.0, 30.0)), "label": "Export...", "action": "export"},
		{"rect": Rect2(Vector2(x + 392.0, 16.0), Vector2(92.0, 30.0)), "label": "Blender", "action": "blender"}
	]


func _draw_toolbar() -> void:
	for button in _toolbar_buttons():
		var rect: Rect2 = button["rect"]
		var active: bool = (button["action"] == "frame" and insert_frame_mode) or (button["action"] == "closed" and closed)
		draw_rect(rect, Color(0.12, 0.31, 0.43, 0.96) if active else Color(0.07, 0.08, 0.10, 0.92))
		draw_rect(rect, Color(0.42, 0.47, 0.56, 0.85), false, 1.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 22), button["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.94, 0.95, 0.97))


func _handle_toolbar_click(screen_pos: Vector2) -> bool:
	for button in _toolbar_buttons():
		if button["rect"].has_point(screen_pos):
			match button["action"]:
				"frame":
					insert_frame_mode = not insert_frame_mode
					_set_status("Click blue or green curve to insert a frame" if insert_frame_mode else "Frame insertion cancelled")
				"closed":
					_toggle_closed()
				"export":
					_show_export_dialog()
				"fit":
					_show_fit_dialog()
				"blender":
					_open_in_blender()
			return true
	return false


func _draw_status_toast() -> void:
	if last_message == "" or Time.get_ticks_msec() > toast_until_msec:
		return
	var text_size := ThemeDB.fallback_font.get_string_size(last_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var rect := Rect2(Vector2(size.x - text_size.x - 44.0, size.y - 52.0), Vector2(text_size.x + 28.0, 32.0))
	draw_rect(rect, Color(0.05, 0.06, 0.08, 0.88))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(14.0, 22.0), last_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.74, 0.95, 0.78))


func _set_status(message: String, duration_msec: int = 4500) -> void:
	last_message = message
	toast_until_msec = Time.get_ticks_msec() + duration_msec
	queue_redraw()


func _hit_test(screen_pos: Vector2) -> Dictionary:
	for i in range(frames.size() - 1, -1, -1):
		var f := frames[i]
		var p := world_to_screen(f.origin)
		var t_end := world_to_screen(f.origin + f.tangent() * TANGENT_HANDLE_LEN * f.scale_t)
		var r_end := _normal_handle_screen(f)
		if screen_pos.distance_to(p) <= 9.0:
			return {"index": i, "mode": "point"}
		if screen_pos.distance_to(t_end) <= TANGENT_HIT_RADIUS:
			return {"index": i, "mode": "tangent"}
		if screen_pos.distance_to(r_end) <= RADIUS_HIT_RADIUS and screen_pos.distance_to(p) > 9.0:
			return {"index": i, "mode": "normal_scale"}
		if screen_pos.distance_to(p) <= POINT_HIT_RADIUS:
			return {"index": i, "mode": "point"}
	return {"index": -1, "mode": ""}


func _sample_hermite_curve() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	if frames.size() < 2:
		return pts
	var lengths := _frame_tangent_lengths()
	for i in _segment_count():
		var a := frames[i]
		var b := frames[(i + 1) % frames.size()]
		var m0: Vector2 = a.tangent() * lengths[i] * a.scale_t * segment_durations[i]
		var m1: Vector2 = b.tangent() * lengths[(i + 1) % frames.size()] * b.scale_t * segment_durations[i]
		for j in samples_per_segment:
			pts.append(_hermite(a.origin, b.origin, m0, m1, float(j) / float(samples_per_segment)))
	pts.append(frames[0].origin if closed else frames[-1].origin)
	return pts


func _frame_tangent_lengths() -> Array[float]:
	var lengths: Array[float] = []
	for i in frames.size():
		if frames[i].tangent_length >= 0.0:
			lengths.append(frames[i].tangent_length)
		elif closed:
			var prev_len := frames[(i - 1 + frames.size()) % frames.size()].origin.distance_to(frames[i].origin)
			var next_len := frames[i].origin.distance_to(frames[(i + 1) % frames.size()].origin)
			lengths.append(maxf((prev_len + next_len) * 0.5, 1.0))
		elif i == 0:
			lengths.append(maxf(frames[0].origin.distance_to(frames[1].origin), 1.0))
		elif i == frames.size() - 1:
			lengths.append(maxf(frames[i - 1].origin.distance_to(frames[i].origin), 1.0))
		else:
			var prev_len := frames[i - 1].origin.distance_to(frames[i].origin)
			var next_len := frames[i].origin.distance_to(frames[i + 1].origin)
			lengths.append(maxf((prev_len + next_len) * 0.5, 1.0))
	return lengths


func _hermite(p0: Vector2, p1: Vector2, m0: Vector2, m1: Vector2, u: float) -> Vector2:
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * m0 + (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * m1


func _hermite_derivative(p0: Vector2, p1: Vector2, m0: Vector2, m1: Vector2, u: float) -> Vector2:
	var u2 := u * u
	return (6.0 * u2 - 6.0 * u) * p0 + (3.0 * u2 - 4.0 * u + 1.0) * m0 + (-6.0 * u2 + 6.0 * u) * p1 + (3.0 * u2 - 2.0 * u) * m1


func _nearest_curve_parameter(screen_pos: Vector2) -> Dictionary:
	var centerline := _sample_hermite_curve()
	if centerline.size() < 2:
		return {}
	var curve_sets: Array = [centerline]
	if show_offsets:
		var offsets := _sample_offset_curves(centerline)
		curve_sets.append(offsets["left"])
		curve_sets.append(offsets["right"])
	var best_distance := 18.0
	var best_index := -1
	var best_fraction := 0.0
	for curve in curve_sets:
		for k in curve.size() - 1:
			var a := world_to_screen(curve[k])
			var b := world_to_screen(curve[k + 1])
			var edge := b - a
			var fraction: float = clamp((screen_pos - a).dot(edge) / maxf(edge.length_squared(), 0.000001), 0.0, 1.0)
			var distance := screen_pos.distance_to(a + edge * fraction)
			if distance < best_distance:
				best_distance = distance
				best_index = k
				best_fraction = fraction
	if best_index < 0:
		return {}
	var sample_position: float = float(best_index) + best_fraction
	var segment := clampi(floori(sample_position / float(samples_per_segment)), 0, _segment_count() - 1)
	var u: float = (sample_position - float(segment * samples_per_segment)) / float(samples_per_segment)
	if u <= 0.01 or u >= 0.99:
		return {}
	return {"segment": segment, "u": u}


func _insert_frame_on_curve(hit: Dictionary) -> void:
	var segment: int = hit["segment"]
	var u: float = hit["u"]
	var lengths := _frame_tangent_lengths()
	for i in frames.size():
		frames[i].tangent_length = lengths[i]
	var a := frames[segment]
	var b := frames[(segment + 1) % frames.size()]
	var duration := segment_durations[segment]
	var m0: Vector2 = a.tangent() * lengths[segment] * a.scale_t * duration
	var m1: Vector2 = b.tangent() * lengths[(segment + 1) % frames.size()] * b.scale_t * duration
	var point := _hermite(a.origin, b.origin, m0, m1, u)
	var derivative := _hermite_derivative(a.origin, b.origin, m0, m1, u)
	if derivative.length() < 0.0001:
		_set_status("Choose a point away from the stationary point")
		return
	var frame := CoordFrame2D.new(point, derivative.angle(), lerpf(a.radius, b.radius, u), lerpf(a.scale_w, b.scale_w, u), "inserted")
	frame.tangent_length = derivative.length() / duration
	frame.scale_t = 1.0
	frame.scale_n = lerpf(a.radius * a.scale_n, b.radius * b.scale_n, u) / maxf(frame.radius, 0.001)
	frames.insert(segment + 1, frame)
	segment_durations[segment] = duration * u
	segment_durations.insert(segment + 1, duration * (1.0 - u))
	selected = segment + 1
	_set_status("Frame inserted; drag center, blue tangent or green normal scale")
	queue_redraw()


func _offset_width_at_sample(sample_index: int, _sample_count: int) -> float:
	var segment := mini(sample_index / samples_per_segment, _segment_count() - 1)
	var u: float = clampf(float(sample_index - segment * samples_per_segment) / float(samples_per_segment), 0.0, 1.0)
	return lerpf(frames[segment].radius * frames[segment].scale_n, frames[(segment + 1) % frames.size()].radius * frames[(segment + 1) % frames.size()].scale_n, u)


func _has_offset_width() -> bool:
	for f in frames:
		if f.radius * f.scale_n > 0.0001:
			return true
	return false


func _sample_offset_curves(centerline: Array[Vector2]) -> Dictionary:
	var left: Array[Vector2] = []
	var right: Array[Vector2] = []
	if centerline.size() < 3 or not _has_offset_width():
		return {"left": left, "right": right}
	for i in centerline.size():
		var prev: Vector2
		var next: Vector2
		if closed and (i == 0 or i == centerline.size() - 1):
			prev = centerline[centerline.size() - 2]
			next = centerline[1]
		else:
			prev = centerline[maxi(i - 1, 0)]
			next = centerline[mini(i + 1, centerline.size() - 1)]
		var tangent := (next - prev).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var width := _offset_width_at_sample(i, centerline.size())
		left.append(centerline[i] - normal * width)
		right.append(centerline[i] + normal * width)
	return {"left": left, "right": right}


func _production_curves() -> Array:
	var centerline := _sample_hermite_curve()
	if not _has_offset_width():
		return [{"name": "Profile Curve", "points": centerline}]
	var offsets := _sample_offset_curves(centerline)
	return [
		{"name": "Left Boundary", "points": offsets["left"]},
		{"name": "Right Boundary", "points": offsets["right"]}
	]


func _show_fit_dialog() -> void:
	fit_curves = _production_curves()
	fit_source_option.clear()
	for curve in fit_curves:
		fit_source_option.add_item(curve["name"])
	fit_source_option.select(0)
	_refresh_fit_candidates()
	fit_dialog.popup_centered(Vector2i(460, 220))


func _on_fit_source_selected(_index: int) -> void:
	_refresh_fit_candidates()


func _on_fit_model_selected(_index: int) -> void:
	if fit_candidates.is_empty():
		return
	var model: Dictionary = fit_candidates[fit_model_option.selected]
	var quality := "Approximate match" if model["relative_error"] > 0.05 else "Close match"
	fit_info_label.text = "%s: RMS %.2f units (%.1f%% of size).\nApply to reposition frames, then keep editing." % [quality, model["rms"], model["relative_error"] * 100.0]


func _refresh_fit_candidates() -> void:
	fit_model_option.clear()
	var points: Array[Vector2] = fit_curves[fit_source_option.selected]["points"]
	fit_candidates = analytic_fitter.candidates(points)
	for model in fit_candidates:
		fit_model_option.add_item("%s  |  RMS %.2f" % [model["label"], model["rms"]])
	fit_dialog.get_ok_button().disabled = fit_candidates.is_empty()
	if fit_candidates.is_empty():
		fit_info_label.text = "Not enough distinct points to fit an analytic curve."
	else:
		fit_model_option.select(0)
		_on_fit_model_selected(0)


func _apply_analytic_fit() -> void:
	if fit_candidates.is_empty():
		return
	var model: Dictionary = fit_candidates[fit_model_option.selected]
	var source_index := fit_source_option.selected
	var side := 0.0
	if fit_curves.size() == 2:
		side = -1.0 if source_index == 0 else 1.0
	var orientation_score := 0.0
	for f in frames:
		var source_point: Vector2 = f.origin + f.normal() * f.radius * f.scale_n * side
		var projection: Dictionary = analytic_fitter.project(model, source_point)
		orientation_score += f.tangent().dot(projection["tangent"])
	var direction := -1.0 if orientation_score < 0.0 else 1.0
	for f in frames:
		var width := f.radius * f.scale_n
		var source_point: Vector2 = f.origin + f.normal() * width * side
		var projection: Dictionary = analytic_fitter.project(model, source_point)
		var tangent: Vector2 = projection["tangent"] * direction
		var normal := Vector2(-tangent.y, tangent.x)
		f.origin = projection["point"] - normal * width * side
		f.angle = tangent.angle()
	for i in frames.size():
		var speeds: Array[float] = []
		if closed or i > 0:
			var previous := (i - 1 + frames.size()) % frames.size()
			speeds.append(frames[previous].origin.distance_to(frames[i].origin) / maxf(segment_durations[previous], 0.0001))
		if closed or i < frames.size() - 1:
			speeds.append(frames[i].origin.distance_to(frames[(i + 1) % frames.size()].origin) / maxf(segment_durations[i], 0.0001))
		var average := 0.0
		for speed in speeds:
			average += speed
		frames[i].tangent_length = maxf(average / float(speeds.size()), 1.0)
		frames[i].scale_t = 1.0
	_set_status("Fitted %s to %s (RMS %.2f)" % [fit_curves[source_index]["name"], model["label"], model["rms"]])
	queue_redraw()


func _show_export_dialog() -> void:
	var directory := _export_dir_absolute()
	DirAccess.make_dir_recursive_absolute(directory)
	export_dialog.current_dir = directory
	export_dialog.current_file = "frame_curve"
	export_dialog.popup_centered_ratio(0.7)


func _export_dir_absolute() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://exports")
	return OS.get_executable_path().get_base_dir().path_join("exports")


func _write_blender_import_script(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(BLENDER_IMPORT_SCRIPT)
	return true


func _open_in_blender() -> void:
	if not FileAccess.file_exists(BLENDER_EXE):
		_set_status("Blender not found at the configured Steam path")
		return
	var directory := _export_dir_absolute()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		_set_status("Cannot create exports folder for Blender")
		return
	var data_path := directory.path_join("frame_curve_blender_%d.json" % Time.get_ticks_msec())
	var script_path := directory.path_join("blender_import_polyline.py")
	var curves := _production_curves()
	if not _export_json(data_path, curves) or not _write_blender_import_script(script_path):
		_set_status("Cannot prepare curve data for Blender")
		return
	var pid := OS.create_process(BLENDER_EXE, PackedStringArray(["--factory-startup", "--python", script_path, "--", data_path]))
	_set_status("Opening curve in Blender" if pid > 0 else "Could not start Blender")


func _on_export_file_selected(path: String) -> void:
	var extension := path.get_extension().to_lower()
	if extension == "png":
		_render_final_png(path)
		return
	var curves := _production_curves()
	var ok := false
	match extension:
		"svg":
			ok = _export_svg(path, curves)
		"obj":
			ok = _export_obj(path, curves)
		"csv":
			ok = _export_csv(path, curves)
		"json":
			ok = _export_json(path, curves)
		_:
			_set_status("Choose SVG, OBJ, CSV, JSON or PNG")
			return
	_set_status("Exported " + path.get_file() if ok else "Export failed: " + path.get_file())


func _export_json(path: String, curves: Array) -> bool:
	var entries := []
	for entry in curves:
		entries.append({"name": entry["name"], "points": _points_to_dicts(entry["points"])})
	var data := {
		"format": "frame_curve_polyline",
		"version": 3,
		"closed": closed,
		"units": "editor_units",
		"samples_per_segment": samples_per_segment,
		"curves": entries
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func _points_to_dicts(points: Array[Vector2]) -> Array:
	var result := []
	for p in points:
		result.append({"x": p.x, "y": p.y})
	return result


func _export_csv(path: String, curves: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line("curve,point_index,x,y,closed")
	for entry in curves:
		var points: Array[Vector2] = entry["points"]
		for i in points.size():
			file.store_line("%s,%d,%.9f,%.9f,%s" % [entry["name"], i, points[i].x, points[i].y, str(closed).to_lower()])
	return true


func _export_svg(path: String, curves: Array) -> bool:
	if curves.is_empty():
		return false
	var point_sets: Array = []
	for entry in curves:
		point_sets.append(entry["points"])
	var bounds := _combined_bounds(point_sets)
	var margin := 32.0
	var width: float = maxf(bounds.size.x + margin * 2.0, 256.0)
	var height: float = maxf(bounds.size.y + margin * 2.0, 256.0)
	var offset := Vector2(margin - bounds.position.x, margin - bounds.position.y)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line('<svg xmlns="http://www.w3.org/2000/svg" width="%.3f" height="%.3f" viewBox="0 0 %.3f %.3f">' % [width, height, width, height])
	file.store_line('<g fill="none" stroke-linejoin="round" stroke-linecap="round">')
	for i in curves.size():
		var points: Array[Vector2] = curves[i]["points"]
		if points.size() > 1:
			file.store_line('<path id="profile_%d" d="%s" stroke="#2ec66d" stroke-width="2.0"/>' % [i, _svg_path(points, offset)])
	file.store_line("</g></svg>")
	return true


func _svg_path(points: Array[Vector2], offset: Vector2) -> String:
	var parts: Array[String] = []
	for i in points.size():
		var p: Vector2 = points[i] + offset
		parts.append("%s %.6f %.6f" % ["M" if i == 0 else "L", p.x, p.y])
	if closed:
		parts.append("Z")
	return " ".join(parts)


func _export_obj(path: String, curves: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line("# 2D Frame Curve Board; XY plane, editor units")
	file.store_line("# Y is flipped from the screen coordinate system")
	var next_index := 1
	for entry in curves:
		var points: Array[Vector2] = entry["points"]
		if points.size() < 2:
			continue
		file.store_line("o " + entry["name"].replace(" ", "_"))
		var unique_count := points.size() - 1 if closed else points.size()
		for i in unique_count:
			file.store_line("v %.9f %.9f 0.0" % [points[i].x, -points[i].y])
		var indices: Array[String] = []
		for i in unique_count:
			indices.append(str(next_index + i))
		if closed:
			indices.append(str(next_index))
		file.store_line("l " + " ".join(indices))
		next_index += unique_count
	return true


func _render_final_png(path: String) -> void:
	var render_size := Vector2i(maxi(int(size.x), 512), maxi(int(size.y), 512))
	var doubled_size := render_size * 2
	var render_data := _build_final_render_data(Vector2(doubled_size))
	var image := Image.create(doubled_size.x, doubled_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for points in render_data:
		_raster_polyline(image, points, OFFSET, 5)
	image.resize(render_size.x, render_size.y, Image.INTERPOLATE_LANCZOS)
	var save_err := image.save_png(path)
	_set_status("Exported " + path.get_file() if save_err == OK else "PNG export failed")


func _raster_polyline(image: Image, points: Array[Vector2], color: Color, width: int) -> void:
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
		for j in steps + 1:
			var p := a.lerp(b, float(j) / float(steps))
			_raster_dot(image, Vector2i(roundi(p.x), roundi(p.y)), width, color)


func _raster_dot(image: Image, center: Vector2i, width: int, color: Color) -> void:
	var radius := width / 2
	for y in range(maxi(center.y - radius, 0), mini(center.y + radius + 1, image.get_height())):
		for x in range(maxi(center.x - radius, 0), mini(center.x + radius + 1, image.get_width())):
			var dx := x - center.x
			var dy := y - center.y
			if dx * dx + dy * dy <= radius * radius:
				image.set_pixel(x, y, color)


func _build_final_render_data(target_size: Vector2) -> Array:
	var curves := _production_curves()
	var point_sets: Array = []
	for entry in curves:
		point_sets.append(entry["points"])
	var bounds := _combined_bounds(point_sets)
	var margin := 42.0
	var scale: float = minf((target_size.x - margin * 2.0) / maxf(bounds.size.x, 1.0), (target_size.y - margin * 2.0) / maxf(bounds.size.y, 1.0))
	var draw_size := bounds.size * scale
	var offset := Vector2((target_size.x - draw_size.x) * 0.5 - bounds.position.x * scale, (target_size.y - draw_size.y) * 0.5 - bounds.position.y * scale)
	var result: Array = []
	for entry in curves:
		result.append(_transform_points(entry["points"], scale, offset))
	return result


func _transform_points(points: Array[Vector2], scale: float, offset: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for p in points:
		result.append(p * scale + offset)
	return result


func _combined_bounds(point_sets: Array) -> Rect2:
	var first := true
	var min_p := Vector2.ZERO
	var max_p := Vector2.ZERO
	for points in point_sets:
		for p in points:
			if first:
				min_p = p
				max_p = p
				first = false
			else:
				min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
				max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	if first:
		return Rect2(Vector2.ZERO, Vector2(256.0, 256.0))
	return Rect2(min_p, max_p - min_p)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_pos)
	zoom = clamp(zoom * factor, 0.2, 5.0)
	var after := screen_to_world(screen_pos)
	view_offset += (after - before) * zoom
	queue_redraw()


func world_to_screen(p: Vector2) -> Vector2:
	return p * zoom + view_offset


func screen_to_world(p: Vector2) -> Vector2:
	return (p - view_offset) / zoom
