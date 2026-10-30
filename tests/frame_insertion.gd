extends SceneTree


func _init() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.frames[1].scale_n = 0.0
	scene.frames[2].scale_n = 1.6
	var initial = scene._sample_hermite_curve()
	var p: Vector2 = initial[60]
	var hit: Dictionary = scene._nearest_curve_parameter(scene.world_to_screen(p))
	assert(hit["segment"] == 1)
	assert(abs(hit["u"] - 0.5) < 0.001)
	var original_frames: int = scene.frames.size()
	scene._insert_frame_on_curve(hit)
	assert(scene.frames.size() == original_frames + 1)
	assert(scene.selected == 2)
	assert(scene.frames[2].origin.distance_to(p) < 0.001)
	assert(abs(scene.frames[2].radius * scene.frames[2].scale_n - (scene.frames[1].radius * scene.frames[1].scale_n + scene.frames[3].radius * scene.frames[3].scale_n) * 0.5) < 0.001)
	assert(abs(scene.segment_durations[1] - 0.5) < 0.001)
	assert(abs(scene.segment_durations[2] - 0.5) < 0.001)
	var lengths: Array[float] = scene._frame_tangent_lengths()
	var left_frame = scene.frames[1]
	var mid_frame = scene.frames[2]
	var right_frame = scene.frames[3]
	var old_duration: float = scene.segment_durations[1] + scene.segment_durations[2]
	var old_m0: Vector2 = left_frame.tangent() * lengths[1] * left_frame.scale_t * old_duration
	var old_m1: Vector2 = right_frame.tangent() * lengths[3] * right_frame.scale_t * old_duration
	for k in 101:
		var u: float = float(k) / 100.0
		var original_point: Vector2 = scene._hermite(left_frame.origin, right_frame.origin, old_m0, old_m1, u)
		var subdivided_point: Vector2
		if u <= 0.5:
			var m0: Vector2 = left_frame.tangent() * lengths[1] * left_frame.scale_t * scene.segment_durations[1]
			var m1: Vector2 = mid_frame.tangent() * lengths[2] * mid_frame.scale_t * scene.segment_durations[1]
			subdivided_point = scene._hermite(left_frame.origin, mid_frame.origin, m0, m1, u * 2.0)
		else:
			var m0: Vector2 = mid_frame.tangent() * lengths[2] * mid_frame.scale_t * scene.segment_durations[2]
			var m1: Vector2 = right_frame.tangent() * lengths[3] * right_frame.scale_t * scene.segment_durations[2]
			subdivided_point = scene._hermite(mid_frame.origin, right_frame.origin, m0, m1, (u - 0.5) * 2.0)
		assert(original_point.distance_to(subdivided_point) < 0.001)
	var after = scene._sample_hermite_curve()
	assert(after.size() == initial.size() + scene.samples_per_segment)
	var offsets: Dictionary = scene._sample_offset_curves(after)
	var green_hit: Dictionary = scene._nearest_curve_parameter(scene.world_to_screen(offsets["left"][20]))
	assert(not green_hit.is_empty())
	assert(green_hit["segment"] == 0)
	print("Frame insertion checks passed")
	quit(0)
