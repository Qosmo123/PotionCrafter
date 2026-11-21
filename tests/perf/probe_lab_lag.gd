extends SceneTree
## Diagnostic: hitches in the Mineral Lab. Times one-off actions (spawning
## rocks, cracking them, loading the anvil) and the worst frame in the half
## second after each, which catches shader compiles and physics pile-ups.
## Usage: godot --path . --resolution 1280x720 --script res://tests/perf/probe_lab_lag.gd

var _bench: Node3D
var _camera: LabCamera3D
var _tick: int = 0
var _last_us: int = 0
var _watch: String = ""
var _watch_until: int = 0
var _worst_ms: float = 0.0
var _ids: Array = []
var _spawned: Array[Rock3D] = []
var _idle_worst: float = 0.0


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_camera = _bench.get_node("Camera3D") as LabCamera3D
	_ids = ["granite", "pegmatite", "geode", "kimberlite", "gem_gravel", "ruby_marble", "copper_gossan", "basalt"]


func _timed(what: String, c: Callable) -> void:
	var t0: int = Time.get_ticks_usec()
	c.call()
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	_watch = what
	_watch_until = _tick + 30
	_worst_ms = 0.0
	print("  %-34s call %7.1f ms" % [what, ms])


func _process(_d: float) -> bool:
	_tick += 1
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = (now - _last_us) / 1000.0
	_last_us = now
	if _watch != "":
		_worst_ms = maxf(_worst_ms, frame_ms)
		if _tick >= _watch_until:
			print("  %-34s worst frame after %6.1f ms" % [_watch, _worst_ms])
			_watch = ""
	if _tick == 20:
		_camera.go_to_station(1)
	if _tick > 150 and _tick < 300:
		_idle_worst = maxf(_idle_worst, frame_ms)
	if _tick == 300:
		print("idle worst frame %.1f ms" % _idle_worst)
	# Spawn each rock type twice (first time vs. cached), 40 frames apart.
	var k: int = (_tick - 320) / 40
	if _tick >= 320 and (_tick - 320) % 40 == 0 and k < _ids.size() * 2:
		var id: String = _ids[k % _ids.size()]
		var m: MineralData = Rock3D.get_mineral(id)
		_timed("spawn %s #%d" % [id, k / _ids.size() + 1], func() -> void:
			_spawned.append(Rock3D.spawn(_bench, m, Vector3(2.7 + 0.12 * float(k % 6), 1.0, 0.1), m.typical_mass_kg)))
	var crack_start: int = 320 + _ids.size() * 2 * 40 + 40
	var c: int = (_tick - crack_start) / 40
	if _tick >= crack_start and (_tick - crack_start) % 40 == 0 and c < _spawned.size():
		var rock: Rock3D = _spawned[c]
		if is_instance_valid(rock):
			_timed("crack %s" % rock.mineral.mineral_id, func() -> void: rock.crack())
	var end_tick: int = crack_start + _spawned.size() * 40 + 60
	if _tick == crack_start - 20:
		print("rocks in scene: %d  nodes %d" % [get_nodes_in_group(&"collectibles").size(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	if _tick == end_tick:
		print("rocks in scene after cracking: %d  nodes %d" % [get_nodes_in_group(&"collectibles").size(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		quit()
	return false

