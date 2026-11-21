extends Node
## Frame-time probe. Run the real game with:
##   godot --path . --resolution 1920x1080 -- fps
## For each graphics preset and each station it warms up, then samples CPU
## and GPU frame times with vsync off, prints a table and quits.

const WARMUP_FRAMES: int = 90
const SAMPLE_FRAMES: int = 120

var _plan: Array[Vector2i] = []  # (preset, station)
var _step: int = 0
var _frame: int = 0
var _cpu_ms: float = 0.0
var _gpu_ms: float = 0.0
var _draws: float = 0.0
var _prims: float = 0.0
var _profile: GraphicsProfile


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_profile = get_tree().current_scene.get_node_or_null("GraphicsProfile") as GraphicsProfile
	for preset: int in [2, 1, 0]:
		for station: int in 3:
			_plan.append(Vector2i(preset, station))
	_begin()


func _begin() -> void:
	var p: Vector2i = _plan[_step]
	if _profile != null:
		_profile.preset = p.x as GraphicsProfile.Preset
		_profile.apply()
	if LabCamera3D.instance != null:
		LabCamera3D.instance.go_to_station(p.y)
	_frame = 0
	_cpu_ms = 0.0
	_gpu_ms = 0.0
	_draws = 0.0
	_prims = 0.0


func _process(delta: float) -> void:
	_frame += 1
	if _frame <= WARMUP_FRAMES:
		return
	var vp: RID = get_viewport().get_viewport_rid()
	_cpu_ms += delta * 1000.0
	_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	if _frame < WARMUP_FRAMES + SAMPLE_FRAMES:
		return
	var n: float = float(SAMPLE_FRAMES)
	var p: Vector2i = _plan[_step]
	print("FPS %-5s station %d: frame %.2f ms (%.0f fps)  gpu %.2f ms  draws %.0f  tris %.0fk  process %.2f ms  physics %.2f ms" % [
		GraphicsProfile.PRESET_NAMES[p.x], p.y, _cpu_ms / n, 1000.0 / (_cpu_ms / n), _gpu_ms / n, _draws / n, _prims / n / 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	_step += 1
	if _step >= _plan.size():
		get_tree().quit()
		return
	_begin()
