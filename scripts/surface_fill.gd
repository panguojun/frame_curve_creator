extends RefCounted

# A boundary-constrained harmonic height field over a planar projection.
# It preserves the sampled 3D loop and never pretends to be an exact NURBS patch.

func build(raw: PackedVector3Array, refine: int = 1, smooth: int = 20) -> Dictionary:
	var boundary := PackedVector3Array()
	for p in raw:
		if boundary.is_empty() or boundary[-1].distance_to(p) > 0.00001:
			boundary.append(p)
	if boundary.size() > 2 and boundary[0].distance_to(boundary[-1]) < 0.00001:
		boundary.remove_at(boundary.size()-1)
	if boundary.size() < 3:
		return {"error":"A closed curve needs at least three distinct boundary points"}
	var normal := Vector3.ZERO
	for i in range(boundary.size()):
		var a := boundary[i]
		var b := boundary[(i+1)%boundary.size()]
		normal += a.cross(b)
	if normal.length() < 0.000001:
		return {"error":"Boundary has no stable projection plane"}
	normal = normal.normalized()
	var origin := boundary[0]
	var axis_u := Vector3.ZERO
	for i in range(1,boundary.size()):
		var edge := boundary[i]-origin
		edge -= normal*edge.dot(normal)
		if edge.length() > 0.00001:
			axis_u = edge.normalized()
			break
	if axis_u == Vector3.ZERO:
		return {"error":"Boundary projection is degenerate"}
	var axis_v := normal.cross(axis_u)
	var uv := PackedVector2Array()
	var heights := PackedFloat32Array()
	for p in boundary:
		var d := p-origin
		uv.append(Vector2(d.dot(axis_u),d.dot(axis_v)))
		heights.append(d.dot(normal))
	var area := _signed_area(uv)
	if absf(area) < 0.000001:
		return {"error":"Projected boundary area is too small"}
	if area < 0.0:
		boundary.reverse()
		uv.reverse()
		heights.reverse()
		area = -area
	if _self_intersects(uv):
		return {"error":"Boundary crosses itself in the surface projection"}
	var triangles := Geometry2D.triangulate_polygon(uv)
	if triangles.is_empty():
		return {"error":"Boundary triangulation failed"}
	var fixed := PackedByteArray()
	fixed.resize(uv.size())
	fixed.fill(1)
	var boundary_edges := {}
	for i in range(uv.size()):
		boundary_edges[_edge_key(i,(i+1)%uv.size())] = true
	if refine > 0:
		var target := sqrt(area/float(boundary.size())) * 1.25 / pow(1.45, float(clampi(refine,1,3)-1))
		triangles = _refine_by_length(uv, heights, fixed, triangles, boundary_edges, target)
	triangles = _improve_triangles(uv, heights, triangles)
	_relax_interior(uv, triangles, fixed)
	triangles = _improve_triangles(uv, heights, triangles)
	var neighbors: Array[Dictionary] = []
	for _i in range(uv.size()):
		neighbors.append({})
	for k in range(0,triangles.size(),3):
		for e in range(3):
			var a := triangles[k+e]
			var b := triangles[k+(e+1)%3]
			neighbors[a][b] = true
			neighbors[b][a] = true
	for _iteration in range(clampi(smooth,0,100)):
		var next_heights := heights.duplicate()
		for i in range(heights.size()):
			if fixed[i] != 0 or neighbors[i].is_empty():
				continue
			var total := 0.0
			for neighbor in neighbors[i]:
				total += heights[neighbor]
			next_heights[i] = total/neighbors[i].size()
		heights = next_heights
	var vertices := PackedVector3Array()
	for i in range(uv.size()):
		vertices.append(origin + axis_u*uv[i].x + axis_v*uv[i].y + normal*heights[i])
	var mesh_area := 0.0
	var edge_counts := {}
	var used_vertices := {}
	for k in range(0,triangles.size(),3):
		var ia := triangles[k]
		var ib := triangles[k+1]
		var ic := triangles[k+2]
		var a := uv[ia]
		var b := uv[ib]
		var c := uv[ic]
		var signed := (b-a).cross(c-a)*0.5
		if signed <= 0.0000000001:
			return {"error":"Triangulation contains a degenerate triangle"}
		if (vertices[ib]-vertices[ia]).cross(vertices[ic]-vertices[ia]).length() < 0.00000001:
			return {"error":"Surface contains a degenerate 3D triangle"}
		mesh_area += signed
		for id in [ia,ib,ic]:
			used_vertices[id] = true
		for pair in [[ia,ib],[ib,ic],[ic,ia]]:
			var key := _edge_key(pair[0],pair[1])
			edge_counts[key] = int(edge_counts.get(key,0))+1
			if edge_counts[key] > 2:
				return {"error":"Surface has a nonmanifold edge"}
	if absf(mesh_area-area) > maxf(0.00001,area*0.0001):
		return {"error":"Triangle area does not match the boundary"}
	var boundary_degree := {}
	var boundary_edge_count := 0
	for key in edge_counts:
		if edge_counts[key] == 1:
			boundary_edge_count += 1
			var parts: PackedStringArray = str(key).split(":")
			var x := int(parts[0])
			var y := int(parts[1])
			boundary_degree[x] = int(boundary_degree.get(x,0))+1
			boundary_degree[y] = int(boundary_degree.get(y,0))+1
	for degree in boundary_degree.values():
		if degree != 2:
			return {"error":"Surface boundary is not a closed manifold loop"}
	var triangle_count := triangles.size()/3
	var euler := used_vertices.size()-edge_counts.size()+triangle_count
	if euler != 1 or boundary_edge_count < 3:
		return {"error":"Surface topology is not a disk"}
	return {"vertices":vertices,"indices":triangles,"boundary_count":boundary.size(),"boundary_edges":boundary_edge_count,"triangle_count":triangle_count,"projected_area":area,"euler":euler}

func _midpoint(a: int, b: int, uv: PackedVector2Array, heights: PackedFloat32Array, fixed: PackedByteArray, boundary_edges: Dictionary, midpoint_map: Dictionary) -> int:
	var key := _edge_key(a,b)
	if midpoint_map.has(key):
		return midpoint_map[key]
	var index := uv.size()
	uv.append((uv[a]+uv[b])*0.5)
	heights.append((heights[a]+heights[b])*0.5)
	fixed.append(1 if boundary_edges.has(key) else 0)
	midpoint_map[key] = index
	return index

# Local frame coordinates provide the 2D orientation test. Only interior edges
# are exchanged; the sampled spatial boundary is never altered.
func _refine_by_length(uv: PackedVector2Array, heights: PackedFloat32Array, fixed: PackedByteArray, triangles: PackedInt32Array, boundary_edges: Dictionary, target: float) -> PackedInt32Array:
	for _pass in range(6):
		if triangles.size() > 45000:
			break
		var split := {}
		for k in range(0, triangles.size(), 3):
			for j in range(3):
				var a := triangles[k+j]
				var b := triangles[k+(j+1)%3]
				var spatial_length := sqrt(uv[a].distance_squared_to(uv[b]) + pow(heights[a]-heights[b],2))
				if spatial_length > target*1.35:
					split[_edge_key(a,b)] = true
		if split.is_empty():
			break
		var mids := {}
		var next := PackedInt32Array()
		for k in range(0, triangles.size(), 3):
			var a := triangles[k]
			var b := triangles[k+1]
			var c := triangles[k+2]
			var ring := PackedInt32Array([a])
			if split.has(_edge_key(a,b)):
				ring.append(_midpoint(a,b,uv,heights,fixed,boundary_edges,mids))
			ring.append(b)
			if split.has(_edge_key(b,c)):
				ring.append(_midpoint(b,c,uv,heights,fixed,boundary_edges,mids))
			ring.append(c)
			if split.has(_edge_key(c,a)):
				ring.append(_midpoint(c,a,uv,heights,fixed,boundary_edges,mids))
			if ring.size() == 3:
				next.append_array(PackedInt32Array([a,b,c]))
				continue
			var center := uv.size()
			uv.append((uv[a]+uv[b]+uv[c])/3.0)
			heights.append((heights[a]+heights[b]+heights[c])/3.0)
			fixed.append(0)
			for j in range(ring.size()):
				next.append_array(PackedInt32Array([center,ring[j],ring[(j+1)%ring.size()]]))
		triangles = next
		var new_boundary := {}
		for key in boundary_edges:
			if mids.has(key):
				var parts := str(key).split(":")
				var a := int(parts[0])
				var b := int(parts[1])
				var mid: int = mids[key]
				new_boundary[_edge_key(a,mid)] = true
				new_boundary[_edge_key(mid,b)] = true
			else:
				new_boundary[key] = true
		boundary_edges = new_boundary
		triangles = _improve_triangles(uv, heights, triangles)
		_relax_interior(uv, triangles, fixed)
	return triangles

func _improve_triangles(uv: PackedVector2Array, heights: PackedFloat32Array, indices: PackedInt32Array) -> PackedInt32Array:
	var tris: Array[PackedInt32Array] = []
	for k in range(0, indices.size(), 3):
		tris.append(PackedInt32Array([indices[k], indices[k+1], indices[k+2]]))
	for _pass in range(6):
		var owners := {}
		for i in range(tris.size()):
			var t := tris[i]
			for j in range(3):
				var key := _edge_key(t[j], t[(j+1)%3])
				if not owners.has(key):
					owners[key] = []
				owners[key].append(i)
		var changed := false
		var touched := {}
		for key in owners:
			var pair: Array = owners[key]
			if pair.size() != 2 or touched.has(pair[0]) or touched.has(pair[1]):
				continue
			var first: PackedInt32Array = tris[pair[0]]
			var second: PackedInt32Array = tris[pair[1]]
			var parts := str(key).split(":")
			var a := int(parts[0])
			var b := int(parts[1])
			var c := -1
			var d := -1
			for id in first:
				if id != a and id != b:
					c = id
			for id in second:
				if id != a and id != b:
					d = id
			if c < 0 or d < 0 or c == d:
				continue
			if (uv[b]-uv[a]).cross(uv[c]-uv[a]) < 0.0:
				var tmp := a
				a = b
				b = tmp
			if (uv[d]-uv[c]).cross(uv[b]-uv[c]) <= 0.0000000001 or (uv[c]-uv[d]).cross(uv[a]-uv[d]) <= 0.0000000001:
				continue
			var old_quality := minf(_spatial_quality(uv,heights,first[0],first[1],first[2]), _spatial_quality(uv,heights,second[0],second[1],second[2]))
			var new_quality := minf(_spatial_quality(uv,heights,c,d,b), _spatial_quality(uv,heights,d,c,a))
			if new_quality <= old_quality + 0.0001:
				continue
			tris[pair[0]] = PackedInt32Array([c,d,b])
			tris[pair[1]] = PackedInt32Array([d,c,a])
			touched[pair[0]] = true
			touched[pair[1]] = true
			changed = true
		if not changed:
			break
	var out := PackedInt32Array()
	for tri in tris:
		out.append_array(tri)
	return out

func _relax_interior(uv: PackedVector2Array, triangles: PackedInt32Array, fixed: PackedByteArray) -> void:
	var adjacent: Array[Dictionary] = []
	var incident: Array[Array] = []
	for _i in range(uv.size()):
		adjacent.append({})
		incident.append([])
	for k in range(0, triangles.size(), 3):
		var a := triangles[k]
		var b := triangles[k+1]
		var c := triangles[k+2]
		for id in [a,b,c]:
			incident[id].append(k)
		adjacent[a][b] = true
		adjacent[a][c] = true
		adjacent[b][a] = true
		adjacent[b][c] = true
		adjacent[c][a] = true
		adjacent[c][b] = true
	for _pass in range(4):
		for i in range(uv.size()):
			if fixed[i] != 0 or adjacent[i].is_empty():
				continue
			var center := Vector2.ZERO
			for neighbor in adjacent[i]:
				center += uv[neighbor]
			center /= float(adjacent[i].size())
			var prior := uv[i]
			var candidate := prior.lerp(center, 0.55)
			var before := 1.0
			var after := 1.0
			for k in incident[i]:
				var a := triangles[k]
				var b := triangles[k+1]
				var c := triangles[k+2]
				before = minf(before, _triangle_quality(uv[a],uv[b],uv[c]))
				var pa: Vector2 = candidate if a == i else uv[a]
				var pb: Vector2 = candidate if b == i else uv[b]
				var pc: Vector2 = candidate if c == i else uv[c]
				if (pb-pa).cross(pc-pa) <= 0.0000000001:
					after = -1.0
					break
				after = minf(after, _triangle_quality(pa,pb,pc))
			if after > before + 0.00001:
				uv[i] = candidate

func _triangle_quality(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := a.distance_squared_to(b)
	var bc := b.distance_squared_to(c)
	var ca := c.distance_squared_to(a)
	var denominator := ab+bc+ca
	if denominator <= 0.000000000001:
		return 0.0
	return 2.0*sqrt(3.0)*absf((b-a).cross(c-a))/denominator

func _spatial_quality(uv: PackedVector2Array, heights: PackedFloat32Array, ia: int, ib: int, ic: int) -> float:
	var a := Vector3(uv[ia].x,uv[ia].y,heights[ia])
	var b := Vector3(uv[ib].x,uv[ib].y,heights[ib])
	var c := Vector3(uv[ic].x,uv[ic].y,heights[ic])
	var denominator := a.distance_squared_to(b)+b.distance_squared_to(c)+c.distance_squared_to(a)
	if denominator <= 0.000000000001:
		return 0.0
	return 2.0*sqrt(3.0)*(b-a).cross(c-a).length()/denominator

func _edge_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a,b),maxi(a,b)]

func _signed_area(uv: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(uv.size()):
		var a := uv[i]
		var b := uv[(i+1)%uv.size()]
		total += a.cross(b)
	return total*0.5

func _self_intersects(uv: PackedVector2Array) -> bool:
	for i in range(uv.size()):
		var a := uv[i]
		var b := uv[(i+1)%uv.size()]
		for j in range(i+2,uv.size()):
			if i == 0 and j == uv.size()-1:
				continue
			var c := uv[j]
			var d := uv[(j+1)%uv.size()]
			if Geometry2D.segment_intersects_segment(a,b,c,d) != null:
				return true
	return false

