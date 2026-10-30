extends RefCounted

# Fits geometric primitives to sampled 2D points in editor coordinates.
# Each candidate stores an orthogonal-distance RMS in the same units.


func candidates(source_points: Array[Vector2]) -> Array:
	var points := _decimate(source_points)
	if points.size() < 3:
		return []
	var center := Vector2.ZERO
	var min_p := points[0]
	var max_p := points[0]
	for p in points:
		center += p
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	center /= float(points.size())
	var extent: float = maxf(max_p.distance_to(min_p), 1.0)
	var result: Array = []
	var line := _fit_line(points, center)
	if not line.is_empty():
		result.append(line)
	var circle := _fit_circle(points, center, extent)
	if not circle.is_empty():
		result.append(circle)
	var ellipse := _fit_ellipse(points, center, extent)
	if not ellipse.is_empty():
		result.append(ellipse)
	for model in result:
		var sum_sq := 0.0
		for p in points:
			var projection: Dictionary = project(model, p)
			sum_sq += p.distance_squared_to(projection["point"])
		model["rms"] = sqrt(sum_sq / float(points.size()))
		model["relative_error"] = model["rms"] / extent
		var penalty := 0.0
		if model["type"] == "circle":
			penalty = 0.0015 * extent
		elif model["type"] == "ellipse":
			penalty = 0.004 * extent
		model["score"] = model["rms"] + penalty
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])
	return result


func project(model: Dictionary, point: Vector2) -> Dictionary:
	match model["type"]:
		"line":
			var direction: Vector2 = model["direction"]
			var foot: Vector2 = model["center"] + direction * (point - model["center"]).dot(direction)
			return {"point": foot, "tangent": direction}
		"circle":
			var radial: Vector2 = point - model["center"]
			if radial.length_squared() < 0.000001:
				radial = Vector2.RIGHT
			radial = radial.normalized()
			return {"point": model["center"] + radial * model["radius"], "tangent": Vector2(-radial.y, radial.x)}
		"ellipse":
			return _project_ellipse(model, point)
	return {"point": point, "tangent": Vector2.RIGHT}


func _decimate(source_points: Array[Vector2]) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var count := source_points.size()
	if count > 1 and source_points[0].distance_to(source_points[-1]) < 0.0001:
		count -= 1
	var stride := maxi(1, ceili(float(count) / 180.0))
	for i in range(0, count, stride):
		points.append(source_points[i])
	return points


func _fit_line(points: Array[Vector2], center: Vector2) -> Dictionary:
	var xx := 0.0
	var xy := 0.0
	var yy := 0.0
	for p in points:
		var d := p - center
		xx += d.x * d.x
		xy += d.x * d.y
		yy += d.y * d.y
	if xx + yy < 0.000001:
		return {}
	var angle := 0.5 * atan2(2.0 * xy, xx - yy)
	var direction := Vector2(cos(angle), sin(angle))
	return {"type": "line", "label": "Line", "center": center, "direction": direction}


func _fit_circle(points: Array[Vector2], center: Vector2, extent: float) -> Dictionary:
	var rows: Array = []
	var values: Array[float] = []
	for p in points:
		var q := (p - center) / extent
		rows.append([2.0 * q.x, 2.0 * q.y, 1.0])
		values.append(q.length_squared())
	var solution := _least_squares(rows, values, 3)
	if solution.size() != 3:
		return {}
	var radius_sq: float = solution[0] * solution[0] + solution[1] * solution[1] + solution[2]
	if radius_sq <= 0.0:
		return {}
	var radius := sqrt(radius_sq) * extent
	if radius > extent * 100.0:
		return {}
	return {"type": "circle", "label": "Circle", "center": center + Vector2(solution[0], solution[1]) * extent, "radius": radius}


func _fit_ellipse(points: Array[Vector2], center: Vector2, extent: float) -> Dictionary:
	var rows: Array = []
	var values: Array[float] = []
	for p in points:
		var q := (p - center) / extent
		rows.append([q.x * q.x, q.x * q.y, q.y * q.y, q.x, q.y])
		values.append(1.0)
	var solution := _least_squares(rows, values, 5)
	if solution.size() != 5:
		return {}
	var a: float = solution[0]
	var b: float = solution[1]
	var c: float = solution[2]
	var d: float = solution[3]
	var e: float = solution[4]
	var determinant: float = 4.0 * a * c - b * b
	if determinant <= 0.000001:
		return {}
	var center_n := Vector2((b * e - 2.0 * c * d) / determinant, (b * d - 2.0 * a * e) / determinant)
	var value_at_center: float = a * center_n.x * center_n.x + b * center_n.x * center_n.y + c * center_n.y * center_n.y + d * center_n.x + e * center_n.y
	var rhs: float = 1.0 - value_at_center
	var delta := sqrt((a - c) * (a - c) + b * b)
	var lambda_hi := 0.5 * (a + c + delta)
	var lambda_lo := 0.5 * (a + c - delta)
	if absf(lambda_hi) < 0.000001 or absf(lambda_lo) < 0.000001:
		return {}
	var hi_sq := rhs / lambda_hi
	var lo_sq := rhs / lambda_lo
	if hi_sq <= 0.0 or lo_sq <= 0.0:
		return {}
	var r_hi := sqrt(hi_sq) * extent
	var r_lo := sqrt(lo_sq) * extent
	var major: float = maxf(r_hi, r_lo)
	var minor: float = minf(r_hi, r_lo)
	if minor < extent * 0.015 or major > extent * 100.0 or major / minor > 30.0:
		return {}
	var theta := 0.5 * atan2(b, a - c)
	var axis_hi := Vector2(cos(theta), sin(theta))
	var axis_lo := Vector2(-sin(theta), cos(theta))
	var axis_a := axis_hi if r_hi >= r_lo else axis_lo
	var axis_b := axis_lo if r_hi >= r_lo else axis_hi
	return {"type": "ellipse", "label": "Ellipse", "center": center + center_n * extent, "axis_a": axis_a, "axis_b": axis_b, "radius_a": major, "radius_b": minor}


func _project_ellipse(model: Dictionary, point: Vector2) -> Dictionary:
	var axis_a: Vector2 = model["axis_a"]
	var axis_b: Vector2 = model["axis_b"]
	var ra: float = model["radius_a"]
	var rb: float = model["radius_b"]
	var d: Vector2 = point - model["center"]
	var local := Vector2(d.dot(axis_a), d.dot(axis_b))
	var angle := atan2(local.y / rb, local.x / ra)
	for i in 20:
		var q := Vector2(ra * cos(angle), rb * sin(angle))
		var dq := Vector2(-ra * sin(angle), rb * cos(angle))
		var ddq := -q
		var numerator := (q - local).dot(dq)
		var denominator := dq.dot(dq) + (q - local).dot(ddq)
		if absf(denominator) < 0.000001:
			break
		var step: float = clampf(numerator / denominator, -0.5, 0.5)
		angle -= step
		if absf(step) < 0.000001:
			break
	var result: Vector2 = model["center"] + axis_a * (ra * cos(angle)) + axis_b * (rb * sin(angle))
	var tangent := (axis_a * (-ra * sin(angle)) + axis_b * (rb * cos(angle))).normalized()
	return {"point": result, "tangent": tangent}


func _least_squares(rows: Array, values: Array[float], columns: int) -> PackedFloat64Array:
	var matrix: Array = []
	for i in columns:
		var row: Array[float] = []
		for j in columns + 1:
			row.append(0.0)
		matrix.append(row)
	for k in rows.size():
		for i in columns:
			var xi: float = rows[k][i]
			matrix[i][columns] += xi * values[k]
			for j in columns:
				matrix[i][j] += xi * float(rows[k][j])
	for i in columns:
		matrix[i][i] += 0.000000001
	for column in columns:
		var pivot := column
		for row in range(column + 1, columns):
			if absf(matrix[row][column]) > absf(matrix[pivot][column]):
				pivot = row
		if absf(matrix[pivot][column]) < 0.0000000001:
			return PackedFloat64Array()
		var saved = matrix[pivot]
		matrix[pivot] = matrix[column]
		matrix[column] = saved
		var divisor: float = matrix[column][column]
		for j in range(column, columns + 1):
			matrix[column][j] /= divisor
		for row in columns:
			if row == column:
				continue
			var factor: float = matrix[row][column]
			for j in range(column, columns + 1):
				matrix[row][j] -= factor * matrix[column][j]
	var answer := PackedFloat64Array()
	for i in columns:
		answer.append(matrix[i][columns])
	return answer
