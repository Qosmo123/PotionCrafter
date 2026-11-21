class_name ScienceDressing
extends PropDressing
## Fine detail for the science bench: engraved nameplates and brass levelling
## screws on each instrument, a graduated face on the air meter's gauge, a
## display and knob on the pH meter, a scale behind the balance beam, and the
## room around them: a chalkboard of working formulas, a wall thermometer and
## barometer, a block of brass weights and a lab notebook with a pencil.

@export var wall_z_meters: float = -0.825
@export var bench_top_y_meters: float = 0.8

const INK: Color = Color(0.07, 0.035, 0.012)
const CHALK: Color = Color(0.92, 0.92, 0.86)
const INSTRUMENTS: Array = [["Viscometer", "VISCOMETER"], ["AirMeter", "AIR METER"], ["VolatilityTester", "VOLATILITY"], ["Hydrometer", "HYDROMETER"]]

var _station: Node3D


func _ready() -> void:
	_station = get_parent() as Node3D
	if _station != null:
		# Instruments build themselves in _ready; dress them afterwards.
		_dress.call_deferred()


func _dress() -> void:
	for entry: Array in INSTRUMENTS:
		_dress_base(_station.get_node_or_null(entry[0]) as Node3D, entry[1])
	_dress_gauge(_station.get_node_or_null("AirMeter") as Node3D)
	_dress_ph_meter(_station.get_node_or_null("Hydrometer") as Node3D)
	_dress_balance(_station.get_node_or_null("VolatilityTester") as Node3D)
	var bench: Node3D = _station.get_node_or_null("Bench") as Node3D
	if bench != null:
		var cx: float = bench.global_position.x
		_hang_chalkboard(Vector3(cx, 0.895, wall_z_meters))
		_hang_thermometer(Vector3(cx - 0.4, 0.96, wall_z_meters))
		_hang_barometer(Vector3(cx + 0.4, 0.94, wall_z_meters))
		_set_weights(Vector3(cx - 0.4, bench_top_y_meters, -0.13))
		_set_notebook(Vector3(cx + 0.02, bench_top_y_meters, -0.03))
	_build_batches()


# --- Instruments --------------------------------------------------------------------

## Instrument plinth: 0.2 x 0.029 x 0.24 m, origin at the centre of its base.
func _dress_base(instrument: Node3D, title: String) -> void:
	if instrument == null:
		return
	var o: Vector3 = instrument.global_position
	var front: float = o.z + 0.12
	_box(&"brass", Vector3(o.x, o.y + 0.0125, front + 0.001), Vector3(0.104, 0.016, 0.002))
	_text(title, Vector3(o.x, o.y + 0.0125, front + 0.0023), 0.088, 0.0095, INK)
	for sx: float in [-1.0, 1.0]:
		_dome(&"brass", Vector3(o.x + sx * 0.047, o.y + 0.0125, front + 0.002), Vector3.BACK, 0.0016)
		_dome(&"iron", Vector3(o.x + sx * 0.09, o.y + 0.0125, front + 0.0002), Vector3.BACK, 0.0032)
		# Knurled levelling screw at each front corner.
		var foot: Vector3 = Vector3(o.x + sx * 0.086, o.y + 0.029, front - 0.016)
		_cyl(&"brass", foot, foot + Vector3(0.0, 0.004, 0.0), 0.0085)
		_cyl(&"brass", foot + Vector3(0.0, 0.004, 0.0), foot + Vector3(0.0, 0.011, 0.0), 0.004)
		_dome(&"brass", foot + Vector3(0.0, 0.011, 0.0), Vector3.UP, 0.0058)


## Air meter gauge: cream dial, radius 0.032 m, facing the viewer.
func _dress_gauge(meter: Node3D) -> void:
	if meter == null:
		return
	var c: Vector3 = meter.global_position + Vector3(0.065, 0.12, -0.04)
	var z: float = c.z + 0.0043
	for k: int in 13:
		var a: float = deg_to_rad(-120.0 + 20.0 * float(k))
		var major: bool = k % 3 == 0
		var r: float = 0.0265 - (0.003 if major else 0.002)
		var xf: Transform3D = Transform3D(Basis(Vector3.BACK, -a).scaled(Vector3(0.0014 if major else 0.0009, 0.006 if major else 0.004, 0.0003)), Vector3(c.x + sin(a) * r, c.y + cos(a) * r, z))
		_tint_xf(xf, INK)
	_text("% AIR", Vector3(c.x, c.y - 0.014, z), 0.022, 0.0055, INK)
	_dome(&"brass", Vector3(c.x, c.y, c.z + 0.0058), Vector3.BACK, 0.0038)


## pH meter: small box on the probe arm, 0.05 x 0.03 x 0.012 m.
func _dress_ph_meter(hydrometer: Node3D) -> void:
	if hydrometer == null:
		return
	var c: Vector3 = hydrometer.global_position + Vector3(0.07, 0.2, -0.05)
	var z: float = c.z + 0.0062
	_tint(Vector3(c.x - 0.004, c.y + 0.003, z), Vector3(0.034, 0.016, 0.0004), Color(0.05, 0.05, 0.05))
	_tint(Vector3(c.x - 0.004, c.y + 0.003, z + 0.0003), Vector3(0.031, 0.013, 0.0004), Color(0.62, 0.78, 0.6))
	_text("pH", Vector3(c.x - 0.004, c.y + 0.003, z + 0.0007), 0.02, 0.009, Color(0.06, 0.12, 0.06))
	_dome(&"brass", Vector3(c.x + 0.019, c.y - 0.008, z), Vector3.BACK, 0.003)
	_dome(&"brass", Vector3(c.x + 0.019, c.y + 0.006, z), Vector3.BACK, 0.002)


## Balance: beam pivots 0.15 m up; a graduated brass scale sits behind it.
func _dress_balance(tester: Node3D) -> void:
	if tester == null:
		return
	var c: Vector3 = tester.global_position + Vector3(0.0, 0.15, -0.05)
	_box(&"brass", Vector3(c.x, c.y + 0.016, c.z - 0.007), Vector3(0.06, 0.03, 0.0016))
	for k: int in 9:
		var x: float = c.x - 0.024 + 0.006 * float(k)
		_tint(Vector3(x, c.y + (0.025 if k % 4 == 0 else 0.0265), c.z - 0.006), Vector3(0.0009, 0.008 if k % 4 == 0 else 0.005, 0.0003), INK)
	# Pivot cap and a sliding rider weight on the beam's far arm.
	_dome(&"brass", Vector3(c.x, c.y, c.z + 0.0045), Vector3.BACK, 0.0045)


# --- Wall ---------------------------------------------------------------------------

## Framed slate with the formulas the four instruments rest on, in chalk.
func _hang_chalkboard(at: Vector3) -> void:
	# Kept low on the wall so it never sits behind the instruments' readouts.
	var w: float = 0.36
	var h: float = 0.17
	var z: float = at.z
	_box(&"slate", Vector3(at.x, at.y, z + 0.004), Vector3(w, h, 0.008))
	var t: float = 0.018
	_box(&"wood", Vector3(at.x, at.y + h * 0.5 + t * 0.5, z + 0.007), Vector3(w + t * 2.0, t, 0.014))
	_box(&"wood", Vector3(at.x, at.y - h * 0.5 - t * 0.5, z + 0.007), Vector3(w + t * 2.0, t, 0.014))
	for sx: float in [-1.0, 1.0]:
		_box(&"wood", Vector3(at.x + sx * (w * 0.5 + t * 0.5), at.y, z + 0.007), Vector3(t, h, 0.014))
	# Chalk ledge with a few sticks and a felt eraser.
	var ledge_y: float = at.y - h * 0.5 - t
	_box(&"wood", Vector3(at.x, ledge_y - 0.003, z + 0.02), Vector3(w + t * 2.0, 0.006, 0.04))
	_cyl(&"bristle", Vector3(at.x - 0.13, ledge_y + 0.004, z + 0.03), Vector3(at.x - 0.09, ledge_y + 0.004, z + 0.032), 0.004)
	_cyl(&"bristle", Vector3(at.x - 0.08, ledge_y + 0.004, z + 0.026), Vector3(at.x - 0.05, ledge_y + 0.004, z + 0.03), 0.004)
	_box(&"wood", Vector3(at.x + 0.11, ledge_y + 0.011, z + 0.028), Vector3(0.07, 0.01, 0.026))
	_box(&"dark", Vector3(at.x + 0.11, ledge_y + 0.003, z + 0.028), Vector3(0.07, 0.006, 0.026))
	var fz: float = z + 0.0086
	_text("PV = nRT", Vector3(at.x - 0.075, at.y + 0.05, fz), 0.17, 0.03, CHALK)
	_tint(Vector3(at.x - 0.075, at.y + 0.028, fz), Vector3(0.17, 0.0014, 0.0003), CHALK)
	_text("pH = -log [H+]", Vector3(at.x - 0.06, at.y + 0.002, fz), 0.2, 0.02, CHALK)
	_text("fall time ~ viscosity", Vector3(at.x - 0.035, at.y - 0.04, fz), 0.25, 0.018, CHALK)
	# A little sketch: a ball falling through a tube.
	var sx0: float = at.x + 0.14
	_tint(Vector3(sx0 - 0.011, at.y + 0.02, fz), Vector3(0.0014, 0.09, 0.0003), CHALK)
	_tint(Vector3(sx0 + 0.011, at.y + 0.02, fz), Vector3(0.0014, 0.09, 0.0003), CHALK)
	_tint(Vector3(sx0, at.y - 0.025, fz), Vector3(0.0234, 0.0014, 0.0003), CHALK)
	_tint_xf(Transform3D(Basis(Vector3.BACK, PI * 0.25).scaled(Vector3(0.008, 0.008, 0.0003)), Vector3(sx0, at.y + 0.03, fz)), CHALK)
	_tint(Vector3(sx0, at.y + 0.01, fz), Vector3(0.0012, 0.018, 0.0003), CHALK)


## Spirit thermometer on a wooden backboard, reading room temperature.
func _hang_thermometer(at: Vector3) -> void:
	var h: float = 0.25
	var z: float = at.z
	_box(&"wood", Vector3(at.x, at.y, z + 0.004), Vector3(0.05, h, 0.008))
	_dome(&"brass", Vector3(at.x, at.y + h * 0.5 - 0.012, z + 0.008), Vector3.BACK, 0.004)
	var bottom: float = at.y - h * 0.5 + 0.03
	var top: float = at.y + h * 0.5 - 0.03
	_cyl(&"bristle", Vector3(at.x - 0.008, bottom, z + 0.012), Vector3(at.x - 0.008, top, z + 0.012), 0.0032)
	# 20 C on a -10..50 C scale.
	var level: float = lerpf(bottom, top, 0.5)
	_cyl(&"red", Vector3(at.x - 0.008, bottom, z + 0.0125), Vector3(at.x - 0.008, level, z + 0.0125), 0.0018)
	_dome(&"red", Vector3(at.x - 0.008, bottom - 0.004, z + 0.012), Vector3.BACK, 0.0068)
	for k: int in 13:
		var y: float = lerpf(bottom, top, float(k) / 12.0)
		var major: bool = k % 2 == 0
		_tint(Vector3(at.x + (0.005 if major else 0.003), y, z + 0.0083), Vector3(0.014 if major else 0.009, 0.0011, 0.0003), INK)
	for cap_y: float in [bottom - 0.012, top + 0.006]:
		_box(&"brass", Vector3(at.x - 0.008, cap_y, z + 0.011), Vector3(0.014, 0.005, 0.008))


## Aneroid barometer: brass case, cream face, a ring of ticks and two hands.
func _hang_barometer(at: Vector3) -> void:
	var z: float = at.z
	_cyl(&"brass", Vector3(at.x, at.y, z), Vector3(at.x, at.y, z + 0.014), 0.075)
	_cyl(&"bristle", Vector3(at.x, at.y, z + 0.012), Vector3(at.x, at.y, z + 0.0155), 0.064)
	_box(&"brass", Vector3(at.x, at.y + 0.082, z + 0.006), Vector3(0.014, 0.02, 0.006))
	var fz: float = z + 0.0158
	for k: int in 28:
		var a: float = deg_to_rad(-135.0 + 10.0 * float(k))
		var major: bool = k % 3 == 0
		var r: float = 0.058 - (0.004 if major else 0.0025)
		_tint_xf(Transform3D(Basis(Vector3.BACK, -a).scaled(Vector3(0.0016 if major else 0.001, 0.008 if major else 0.005, 0.0003)), Vector3(at.x + sin(a) * r, at.y + cos(a) * r, fz)), INK)
	_text("FAIR", Vector3(at.x, at.y + 0.028, fz), 0.03, 0.0085, INK)
	_text("RAIN", Vector3(at.x - 0.03, at.y - 0.012, fz), 0.024, 0.007, INK)
	_text("DRY", Vector3(at.x + 0.03, at.y - 0.012, fz), 0.022, 0.007, INK)
	# Reading hand, and the brass marker hand you set by the knob.
	var hand_a: float = deg_to_rad(18.0)
	_tint_xf(Transform3D(Basis(Vector3.BACK, -hand_a).scaled(Vector3(0.0018, 0.05, 0.0003)), Vector3(at.x + sin(hand_a) * 0.02, at.y + cos(hand_a) * 0.02, fz + 0.0006)), Color(0.05, 0.05, 0.08))
	var set_a: float = deg_to_rad(-40.0)
	_tint_xf(Transform3D(Basis(Vector3.BACK, -set_a).scaled(Vector3(0.0014, 0.044, 0.0003)), Vector3(at.x + sin(set_a) * 0.02, at.y + cos(set_a) * 0.02, fz + 0.0003)), Color(0.75, 0.52, 0.2))
	_dome(&"brass", Vector3(at.x, at.y, fz + 0.0008), Vector3.BACK, 0.005)


# --- Bench --------------------------------------------------------------------------

## Brass calibration weights standing in a drilled wooden block.
func _set_weights(at: Vector3) -> void:
	_box(&"wood", at + Vector3(0.0, 0.008, 0.0), Vector3(0.14, 0.016, 0.042))
	var x: float = at.x - 0.052
	for i: int in 6:
		var r: float = lerpf(0.0125, 0.0045, float(i) / 5.0)
		var h: float = r * 1.7
		var base: Vector3 = Vector3(x + r, at.y + 0.016, at.z)
		_cyl(&"brass", base, base + Vector3(0.0, h, 0.0), r)
		_cyl(&"brass", base + Vector3(0.0, h, 0.0), base + Vector3(0.0, h + r * 0.35, 0.0), r * 0.4)
		_dome(&"brass", base + Vector3(0.0, h + r * 0.35, 0.0), Vector3.UP, r * 0.6)
		x += r * 2.0 + 0.004


## A closed lab notebook lying on the bench with a pencil across it.
func _set_notebook(at: Vector3) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var book: Node3D = Book3D.make(0.018, 0.17, 0.12, Color(0.08, 0.16, 0.22), Color(0.55, 0.45, 0.3), rng)
	book.name = "Notebook"
	add_child(book)
	# Lying flat, spine toward the viewer, a little askew.
	book.global_transform = Transform3D(Basis(Vector3.UP, 0.12) * Basis(Vector3.BACK, PI * 0.5), at + Vector3(0.0, 0.009, 0.0))
	var top: float = at.y + 0.018 + 0.0035
	var a: Vector3 = Vector3(at.x - 0.07, top, at.z + 0.02)
	var b: Vector3 = Vector3(at.x + 0.06, top, at.z - 0.025)
	_cyl(&"pencil", a, b, 0.0035)
	var dir: Vector3 = (b - a).normalized()
	_cyl(&"wood", b, b + dir * 0.009, 0.0028)
	_cyl(&"dark", b + dir * 0.009, b + dir * 0.013, 0.0012)
	_cyl(&"brass", a - dir * 0.008, a, 0.0037)
