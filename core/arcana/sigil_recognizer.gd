class_name SigilRecognizer
extends RefCounted
## Analytical stroke recogniser for chalk sigils (no templates, no QTEs).
## Measures geometric properties of a freehand stroke on the bench plane:
##   closure     how well the stroke returns to its start
##   circularity 1 - relative spread of distance from the centroid
##   vertices    sharp turning-angle peaks on the resampled path
##   regularity  1 - relative spread of the side lengths
## The vertex count (or a circle) picks the field type; power is the product
## of closure, regularity and drawn size, so sloppy sigils make weak fields.

enum Kind { NONE, CIRCLE, TRIANGLE, SQUARE, PENTAGON, HEXAGON, OCTAGON }

const KIND_NAMES: PackedStringArray = ["—", "Circle of Warding", "Triangle of Ignis", "Square of Glacies", "Pentagram of Ascension", "Hexagram of Vortices", "Octagram of Catalysis"]
const RESAMPLE_COUNT: int = 96
const CORNER_WINDOW: int = 3
const CORNER_ANGLE_RAD: float = 0.55
const MIN_PERIMETER_METERS: float = 0.08


class Result:
	var kind: Kind = Kind.NONE
	var power: float = 0.0
	var center: Vector2 = Vector2.ZERO
	var radius_meters: float = 0.0
	var vertices: int = 0
	var closure: float = 0.0
	var circularity: float = 0.0
	var regularity: float = 0.0

	func describe() -> String:
		if kind == Kind.NONE:
			return "Unrecognised scrawl (closure %.2f)" % closure
		return "%s · power %.2f · r %.0f cm · %d vertices" % [KIND_NAMES[kind], power, radius_meters * 100.0, vertices]


static func analyze(points: PackedVector2Array) -> Result:
	var result: Result = Result.new()
	if points.size() < 8:
		return result
	var perimeter: float = _length(points)
	if perimeter < MIN_PERIMETER_METERS:
		return result
	var gap: float = points[0].distance_to(points[points.size() - 1])
	result.closure = clampf(1.0 - gap / (0.2 * perimeter), 0.0, 1.0)
	var path: PackedVector2Array = _resample(points, RESAMPLE_COUNT)

	var center: Vector2 = Vector2.ZERO
	for p: Vector2 in path:
		center += p
	center /= float(path.size())
	var mean_r: float = 0.0
	for p: Vector2 in path:
		mean_r += p.distance_to(center)
	mean_r /= float(path.size())
	var var_r: float = 0.0
	for p: Vector2 in path:
		var_r += pow(p.distance_to(center) - mean_r, 2.0)
	var spread: float = sqrt(var_r / float(path.size())) / maxf(mean_r, 1e-6)
	result.center = center
	result.radius_meters = mean_r
	result.circularity = clampf(1.0 - spread * 6.0, 0.0, 1.0)

	var corners: PackedInt32Array = _corners(path, result.closure > 0.5)
	result.vertices = corners.size()
	if result.closure < 0.4:
		return result

	if spread < 0.07 and result.vertices < 3:
		result.kind = Kind.CIRCLE
		result.regularity = result.circularity
	else:
		match result.vertices:
			3: result.kind = Kind.TRIANGLE
			4: result.kind = Kind.SQUARE
			5: result.kind = Kind.PENTAGON
			6: result.kind = Kind.HEXAGON
			7, 8: result.kind = Kind.OCTAGON
			_: result.kind = Kind.NONE
		result.regularity = _side_regularity(path, corners)
	if result.kind != Kind.NONE:
		var size_factor: float = clampf(mean_r / 0.07, 0.3, 1.2)
		result.power = clampf(result.closure * (0.4 + 0.6 * result.regularity) * size_factor, 0.0, 1.2)
	return result


static func _length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


static func _resample(points: PackedVector2Array, count: int) -> PackedVector2Array:
	var total: float = _length(points)
	var step: float = total / float(count - 1)
	var out: PackedVector2Array = PackedVector2Array([points[0]])
	var carried: float = 0.0
	for i: int in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var seg: float = a.distance_to(b)
		while carried + seg >= step and out.size() < count:
			var t: float = (step - carried) / seg
			a = a.lerp(b, t)
			out.append(a)
			seg = a.distance_to(b)
			carried = 0.0
		carried += seg
	while out.size() < count:
		out.append(points[points.size() - 1])
	return out


## Indices of sharp turning-angle peaks. Closed paths wrap around.
static func _corners(path: PackedVector2Array, closed: bool) -> PackedInt32Array:
	var n: int = path.size()
	var angles: PackedFloat32Array = PackedFloat32Array()
	angles.resize(n)
	for i: int in n:
		var i0: int = i - CORNER_WINDOW
		var i1: int = i + CORNER_WINDOW
		if closed:
			i0 = posmod(i0, n - 1)
			i1 = posmod(i1, n - 1)
		elif i0 < 0 or i1 >= n:
			angles[i] = 0.0
			continue
		var d0: Vector2 = path[i] - path[i0]
		var d1: Vector2 = path[i1] - path[i]
		angles[i] = absf(d0.angle_to(d1)) if d0.length() > 1e-6 and d1.length() > 1e-6 else 0.0
	var corners: PackedInt32Array = PackedInt32Array()
	var min_gap: int = maxi(n / 14, 2)
	for i: int in n - (1 if closed else 0):
		if angles[i] < CORNER_ANGLE_RAD:
			continue
		var is_peak: bool = true
		for k: int in range(-min_gap, min_gap + 1):
			var j: int = posmod(i + k, n - 1) if closed else clampi(i + k, 0, n - 1)
			if angles[j] > angles[i] or (angles[j] == angles[i] and j < i):
				is_peak = false
				break
		if is_peak:
			corners.append(i)
	return corners


static func _side_regularity(path: PackedVector2Array, corners: PackedInt32Array) -> float:
	if corners.size() < 3:
		return 0.0
	var lengths: PackedFloat32Array = PackedFloat32Array()
	for k: int in corners.size():
		lengths.append(path[corners[k]].distance_to(path[corners[(k + 1) % corners.size()]]))
	var mean: float = 0.0
	for l: float in lengths:
		mean += l
	mean /= float(lengths.size())
	var variance: float = 0.0
	for l: float in lengths:
		variance += pow(l - mean, 2.0)
	return clampf(1.0 - sqrt(variance / float(lengths.size())) / maxf(mean, 1e-6) * 2.0, 0.0, 1.0)
