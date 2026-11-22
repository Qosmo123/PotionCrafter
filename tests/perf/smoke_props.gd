extends SceneTree
## Smoke test for the audit's phase 4 (mouse props, discovery hints, lens,
## Mineral Lab juice):
##   Cork dish    a filled flask set in it gets corked.
##   Satchel tab  shows while holding; pressing it stores the item.
##   Lens         held over the beaker, it reads it and the HUD panel shows.
##   Warmth       recipe proximity scores near-misses high, with a hint.
##   Seam         a hammer blow on a rock's glowing seam splits it at once.
##   Flywheel     a cranked crusher keeps turning after letting go.
##   Momentum     a shaken sifter keeps rocking after letting go.
##   Lessons      the three starter commissions exist as recipes.
## Usage: godot --path . --resolution 1280x720 --script res://tests/perf/smoke_props.gd

const TICKS_PER_S: float = 60.0

var _bench: Node3D
var _grabber: TactileGrabber3D
var _camera: LabCamera3D
var _hud: HudOverlay
var _failures: int = 0
var _step: int = 0
var _t: int = 0
var _flask: Vessel3D
var _lens: MagnifyingLens3D
var _rock: Rock3D
var _hammer: Hammer3D
var _crusher: RockCrusher3D
var _sifter: SandSifter3D
var _phase: float = 0.0


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D
	_camera = _bench.get_node("Camera3D") as LabCamera3D
	_hud = _bench.get_node("HudOverlay") as HudOverlay
	_flask = _bench.get_node("Vessels/FlaskSpirits") as Vessel3D
	_crusher = _bench.get_node("MineralLab/RockCrusher") as RockCrusher3D
	_sifter = _bench.get_node("MineralLab/SandSifter") as SandSifter3D


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


var _tab_seen: bool = false


func _next() -> void:
	_step += 1
	_t = 0


func _move(p: Vector2) -> void:
	_grabber._note_motion(p - _grabber._pointer_screen)
	_grabber._pointer_screen = p


func _physics_process(_d: float) -> bool:
	_t += 1
	match _step:
		0:
			if _t > 30:
				_grabber.grab(_flask)
				_next()
		1:  # Carry the flask to the cork & wax dish and put it down there.
			var props: BenchProps3D = _bench.get_node("Stands/BenchProps") as BenchProps3D
			_move(_camera.unproject_position(props._dish.global_position + Vector3(0.0, 0.2, 0.0)))
			# The HUD redraws at frame rate, so give it a few ticks to catch up.
			if _t <= 20 and _hud._satchel_tab.visible:
				_tab_seen = true
			if _t == 20:
				_check(_tab_seen, "the satchel pocket tab shows while holding something")
			if _t > 20 and not _grabber.dock_seat.is_empty() and absf(_flask.global_position.x - props._dish.global_position.x) < 0.03:
				_check(_grabber.assist_hint().contains("cork"), "the dish is offered as a place to set it (\"%s\")" % _grabber.assist_hint())
				var e: InputEventMouseButton = InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = true
				e.position = _grabber._pointer_screen
				_grabber._unhandled_input(e)
				_next()
			elif _t > 600:
				_check(false, "the flask reaches the cork dish")
				_next()
		2:
			if _flask.sealed or _t > 360:
				var dish: Vector3 = (_bench.get_node("Stands/BenchProps") as BenchProps3D)._dish.global_position
				_check(_flask.sealed, "setting a filled flask in the cork & wax dish corks it (flask %s, dish %s, held %s)" % [_flask.global_position, dish, _grabber.held_body])
				_lens = _bench.get_node("Stands/MagnifyingLens") as MagnifyingLens3D
				_check(_lens != null, "a magnifying lens lies on the bench")
				if _lens != null:
					_grabber.grab(_lens)
				_next()
		3:  # Hold the lens over the beaker.
			var beaker: Vessel3D = _bench.get_node("Vessels/Beaker") as Vessel3D
			_move(_camera.unproject_position(beaker.global_position + Vector3(0.0, 0.18, 0.0)))
			if _t > 240:
				_check(_lens.target == beaker, "held over the beaker, the lens reads it")
				_check(_hud._lens_panel.visible == (beaker.mixture.get_total_mass_kg() > 1e-6), "the Alchemist's Lens panel shows its readings")
				# Satchel tab: store the lens.
				_hud._satchel_tab.pressed.emit()
				_next()
		4:
			if _t > 5:
				_check(_grabber.held_body == null, "pressing the satchel tab puts the held item away")
				_check_warmth()
				_camera.go_to_station(1)
				_next()
		5:  # Mineral Lab: a seam strike.
			if _t == 90:
				var anvil: Node3D = _bench.get_node("MineralLab/Anvil") as Node3D
				_rock = Rock3D.spawn(_bench, Rock3D.get_mineral("granite"), anvil.global_position + Vector3(0.0, 0.2, 0.0), 0.12)
				_hammer = _bench.get_node("MineralLab/Hammer") as Hammer3D
				_grabber.grab(_hammer)
			if _t > 90 and _rock != null and is_instance_valid(_rock):
				_move(_camera.unproject_position(_rock.global_position + Vector3(0.0, 0.12, 0.0)))
			if _t == 260:
				_check(_rock._seam != null and _rock._seam.visible, "aiming the hammer at a rock shows its glowing seam")
				_hammer.global_position.x = _rock.global_position.x + _rock.seam_offset_x
				_hammer._target = _rock
				_hammer._finish_swing()
			if _t == 275:
				_check(not is_instance_valid(_rock) or _rock.is_queued_for_deletion(), "a blow on the seam splits the rock in one hit")
				Engine.time_scale = 1.0
				_grabber.release()
				_grabber.grab(_crusher._handle)
				_next()
		6:  # Crank the crusher briskly for a second, then let go.
			var axis: Vector3 = _crusher.global_transform * Vector3(0.0, _crusher.crank_height_meters, 0.0)
			if _t < 90:
				_phase += TAU * 1.2 / TICKS_PER_S
				_move(_camera.unproject_position(axis + Vector3(cos(_phase), 0.0, sin(_phase)) * RockCrusher3D.CRANK_RADIUS_METERS))
			if _t == 90:
				_grabber.release()
			if _t == 150:
				var omega: float = absf(_crusher._handle.angular_velocity.dot(_crusher.global_basis.y))
				_check(omega > 1.0, "the crusher's flywheel keeps the crank turning after letting go (%.1f rad/s)" % omega)
				_grabber.grab(_sifter._handle)
				_phase = 0.0
				_next()
		7:  # Shake the sifter, then let go.
			var base: Vector2 = _camera.unproject_position(_sifter.global_transform * Vector3(0.17, _sifter.deck_height_meters + 0.05, 0.0))
			if _t < 150:
				_phase += TAU * 1.1 / TICKS_PER_S
				_move(base + Vector2(sin(_phase) * 90.0, 0.0))
			if _t == 150:
				_grabber.release()
			if _t > 190 and _t < 230:
				_phase = maxf(_phase, absf(_sifter._handle.linear_velocity.dot(_sifter.global_basis.x)) + 100.0)
			if _t == 230:
				_check(_phase - 100.0 > 0.03, "the sifter keeps rocking after letting go (%.2f m/s)" % maxf(_phase - 100.0, 0.0))
				for t: Array in GrimoireJournal.TUTORIAL_ORDERS:
					_check(GrimoireJournal.instance._recipe(StringName(t[0])) != null, "starter commission '%s' matches a real recipe" % t[1])
				print("PROPS SMOKE %s" % ("PASS" if _failures == 0 else "FAIL"))
				quit(0 if _failures == 0 else 1)
	return false


func _check_warmth() -> void:
	var r: RecipeData = RecipeData.new()
	r.condition_traits = PackedStringArray(["temperature_c", "ph"])
	r.condition_min = PackedFloat32Array([60.0, 6.0])
	r.condition_max = PackedFloat32Array([90.0, 8.0])
	var near: Array = RecipeBook.proximity(r, {"temperature_c": 52.0, "ph": 7.0})
	var far: Array = RecipeBook.proximity(r, {"temperature_c": -20.0, "ph": 1.0})
	_check(float(near[0]) >= 0.78 and float(near[0]) < 1.0, "a near miss scores as getting warm (%.2f)" % float(near[0]))
	_check(String(near[1]) == "Needs more heat", "the hint names what's missing (\"%s\")" % near[1])
	_check(float(far[0]) < 0.5, "a far miss scores cold (%.2f)" % float(far[0]))
