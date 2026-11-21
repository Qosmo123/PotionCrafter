class_name LapidaryWheel3D
extends StaticBody3D
## Lapidary bench machine. Click the brass switch to start the wheel, then hold
## a mineral or gem against it with the grabber.
##   POLISH: polish rises with contact time, slower for harder stones (Mohs).
##   FACET:  click the index dial to choose a cut; holding a polished gem steady
##           on the lap cuts the facets. Cut quality = polish + steadiness of
##           your hand while cutting. Finished gems are worth far more.

enum Mode { POLISH, FACET }

@export var mode: Mode = Mode.POLISH
@export var model: PackedScene
@export var camera: Camera3D
@export var wheel_radius_meters: float = 0.07
@export var wheel_height_meters: float = 0.11

var running: bool = false
var selected_cut: int = RockMeshes.Cut.ROUND
var _wheel: MeshInstance3D
var _contact: Area3D
var _switch: StaticBody3D
var _dial: StaticBody3D
var _led: StandardMaterial3D
var _status: Label3D
var _sparks: GPUParticles3D
var _spin: float = 0.0
var _work_target: Rock3D = null
var _cut_progress: float = 0.0
var _steadiness_sum: float = 0.0
var _steadiness_samples: int = 0


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	if model != null:
		var visual: Node3D = model.instantiate() as Node3D
		add_child(visual)
		PropMaterials.apply(visual)
	var housing: BoxShape3D = BoxShape3D.new()
	housing.size = Vector3(0.2, wheel_height_meters - 0.01, 0.2)
	var hc: CollisionShape3D = CollisionShape3D.new()
	hc.shape = housing
	hc.position.y = (wheel_height_meters - 0.01) * 0.5
	add_child(hc)
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = wheel_radius_meters
	disc.bottom_radius = wheel_radius_meters
	disc.height = 0.008
	disc.radial_segments = 48
	var disc_mat: StandardMaterial3D = StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.55, 0.55, 0.6) if mode == Mode.POLISH else Color(0.75, 0.6, 0.35)
	disc_mat.metallic = 0.8
	disc_mat.roughness = 0.3 if mode == Mode.POLISH else 0.2
	disc_mat.anisotropy_enabled = true
	disc_mat.anisotropy = 0.8
	disc.material = disc_mat
	_wheel = MeshInstance3D.new()
	_wheel.mesh = disc
	_wheel.position.y = wheel_height_meters
	add_child(_wheel)
	var wheel_shape: CylinderShape3D = CylinderShape3D.new()
	wheel_shape.radius = wheel_radius_meters
	wheel_shape.height = 0.008
	var wc: CollisionShape3D = CollisionShape3D.new()
	wc.shape = wheel_shape
	wc.position.y = wheel_height_meters
	add_child(wc)
	_contact = Area3D.new()
	_contact.collision_layer = 0
	_contact.collision_mask = SimConstants.LAYER_SOLID_REAGENT
	_contact.monitorable = false
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = wheel_radius_meters
	area_shape.height = 0.04
	var ac: CollisionShape3D = CollisionShape3D.new()
	ac.shape = area_shape
	_contact.add_child(ac)
	_contact.position.y = wheel_height_meters + 0.02
	add_child(_contact)
	_switch = _button(Vector3(0.085, 0.06, 0.1), Color(0.85, 0.65, 0.3))
	_led = StandardMaterial3D.new()
	_led.albedo_color = Color(0.3, 0.05, 0.05)
	_led.emission_enabled = true
	_led.emission = Color(1.0, 0.1, 0.05)
	_led.emission_energy_multiplier = 0.3
	var led_mesh: SphereMesh = SphereMesh.new()
	led_mesh.radius = 0.006
	led_mesh.height = 0.012
	led_mesh.material = _led
	var led: MeshInstance3D = MeshInstance3D.new()
	led.mesh = led_mesh
	led.position = Vector3(0.085, 0.085, 0.1)
	add_child(led)
	if mode == Mode.FACET:
		_dial = _button(Vector3(-0.085, 0.06, 0.1), Color(0.3, 0.3, 0.35))
	_status = Label3D.new()
	_status.font_size = 32
	_status.pixel_size = 0.00045
	_status.outline_size = 8
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.position = Vector3(-0.06 if mode == Mode.FACET else 0.0, wheel_height_meters + 0.16, 0.0)
	add_child(_status)
	_sparks = GPUParticles3D.new()
	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 0.5, 1.0)
	proc.spread = 35.0
	proc.initial_velocity_min = 0.3
	proc.initial_velocity_max = 0.8
	proc.gravity = Vector3(0.0, -3.0, 0.0)
	proc.color = Color(1.0, 0.85, 0.5) if mode == Mode.FACET else Color(0.75, 0.85, 0.95)
	_sparks.process_material = proc
	_sparks.amount = 50
	_sparks.lifetime = 0.4
	_sparks.emitting = false
	var spark_quad: QuadMesh = QuadMesh.new()
	spark_quad.size = Vector2(0.004, 0.004)
	spark_quad.material = VesselEffects.billboard_material(true, 2.0, Color(1.0, 0.8, 0.5))
	_sparks.draw_pass_1 = spark_quad
	_sparks.position.y = wheel_height_meters + 0.01
	add_child(_sparks)
	_update_status()


func _button(at: Vector3, color: Color) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = SimConstants.LAYER_STATIC_BENCH
	body.collision_mask = 0
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.016
	mesh.bottom_radius = 0.018
	mesh.height = 0.02
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.7
	mat.roughness = 0.3
	mesh.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.rotation.x = PI * 0.5
	body.add_child(mi)
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.03  # roomy click/touch target
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = at
	add_child(body)
	return body


func _unhandled_input(event: InputEvent) -> void:
	var press: InputEventMouseButton = event as InputEventMouseButton
	if press == null or not press.pressed or (press.button_index != MOUSE_BUTTON_LEFT and press.button_index != MOUSE_BUTTON_RIGHT) or camera == null or TactileGrabber3D.input_captured:
		return
	var origin: Vector3 = camera.project_ray_origin(press.position)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(press.position) * 8.0, SimConstants.LAYER_STATIC_BENCH)
	var hit: Object = get_world_3d().direct_space_state.intersect_ray(query).get("collider")
	if hit == _switch and press.button_index == MOUSE_BUTTON_LEFT:
		toggle()
		get_viewport().set_input_as_handled()
	elif hit != null and hit == _dial:
		cycle_cut(1 if press.button_index == MOUSE_BUTTON_LEFT else -1)
		AudioHaptics.tick()
		_update_status()
		get_viewport().set_input_as_handled()


## Step the index dial through every cut (skipping "Uncut").
func cycle_cut(step: int) -> void:
	var count: int = RockMeshes.CUT_NAMES.size() - 1
	selected_cut = posmod(selected_cut - 1 + step, count) + 1


## How well this stone suits the chosen cut. Real lapidaries cut opaque and
## phenomenal stones (star, cat's eye, opal, moonstone) en cabochon: facets
## would hide the effect. Cleavage-prone stones are risky to facet.
static func cut_suitability(m: MineralData, cut: int) -> float:
	var cab: bool = cut == RockMeshes.Cut.CABOCHON
	var phen: bool = m.phenomenon in [MineralData.Phenomenon.ASTERISM, MineralData.Phenomenon.CHATOYANCY,
		MineralData.Phenomenon.PLAY_OF_COLOR, MineralData.Phenomenon.ADULARESCENCE, MineralData.Phenomenon.AVENTURESCENCE]
	var opaque: bool = m.diaphaneity == MineralData.Diaphaneity.OPAQUE
	if cab:
		return 1.15 if phen or opaque else 0.9
	var k: float = 1.0
	if phen:
		k *= 0.7
	if opaque:
		k *= 0.6
	if m.cleavage in [MineralData.Cleavage.BASAL, MineralData.Cleavage.CUBIC, MineralData.Cleavage.RHOMBOHEDRAL]:
		k *= 0.9
	return k


func toggle() -> void:
	running = not running
	_led.emission = Color(0.1, 1.0, 0.3) if running else Color(1.0, 0.1, 0.05)
	_led.emission_energy_multiplier = 2.0 if running else 0.3
	AudioHaptics.tick()
	_update_status()


func _process(delta: float) -> void:
	_spin = lerpf(_spin, 40.0 if running else 0.0, 1.0 - exp(-delta * 2.0))
	_wheel.rotation.y += _spin * delta


func _physics_process(delta: float) -> void:
	_sparks.emitting = false
	if not running:
		return
	var stone: Rock3D = null
	for body: Node3D in _contact.get_overlapping_bodies():
		var r: Rock3D = body as Rock3D
		if r != null and r.mineral != null and r.mineral.kind != MineralData.Kind.ROCK and r.mineral.kind != MineralData.Kind.SAND:
			stone = r
			break
	if stone != _work_target:
		_work_target = stone
		_cut_progress = 0.0
		_steadiness_sum = 0.0
		_steadiness_samples = 0
	if stone == null:
		_update_status()
		return
	_sparks.emitting = true
	var hardness_drag: float = 1.0 + stone.mineral.hardness_mohs * 0.15
	if mode == Mode.POLISH:
		if stone.polish < 1.0:
			var before: float = stone.polish
			stone.set_polish(stone.polish + delta * 0.3 / hardness_drag)
			if before < 1.0 and stone.polish >= 1.0:
				_announce(stone, "Mirror polish! %s now shines" % stone.mineral.display_name)
		_status.text = "Polishing %s\n%d%%" % [stone.mineral.display_name, int(stone.polish * 100.0)]
	else:
		if not stone.mineral.can_facet:
			_status.text = "%s can't be faceted\ntry a gem" % stone.mineral.display_name
			return
		if stone.polish < 0.3:
			_status.text = "Polish it first\n(%d%% / 30%%)" % int(stone.polish * 100.0)
			return
		_steadiness_sum += clampf(1.0 - stone.linear_velocity.length() * 6.0, 0.0, 1.0)
		_steadiness_samples += 1
		_cut_progress += delta * 0.2 / hardness_drag
		_status.text = "Cutting %s: %s\n%d%%  steady hands!" % [stone.mineral.display_name, RockMeshes.CUT_NAMES[selected_cut], int(_cut_progress * 100.0)]
		if _cut_progress >= 1.0:
			var steadiness: float = _steadiness_sum / maxf(float(_steadiness_samples), 1.0)
			var suit: float = cut_suitability(stone.mineral, selected_cut)
			stone.apply_cut(selected_cut, clampf((stone.polish * 0.4 + steadiness * 0.6) * suit, 0.0, 1.0))
			var tip: String = ""
			if suit > 1.0:
				tip = "  Perfect choice: a cabochon shows off its %s!" % ("magic" if stone.mineral.phenomenon == MineralData.Phenomenon.NONE else MineralData.PHENOMENON_NAMES[stone.mineral.phenomenon])
			elif suit < 0.8:
				tip = "  Tip: opaque or phenomenal stones look best as a Cabochon."
			_announce(stone, "Faceted a %s! Quality %d%%, worth %d ◉%s" % [stone.describe_name(), int(stone.cut_quality * 100.0), stone.value(), tip])
			_cut_progress = 0.0
			_work_target = null


func _announce(stone: Rock3D, text: String) -> void:
	if GrimoireJournal.instance != null:
		GrimoireJournal.instance.toast.emit(text, &"coins")
		GrimoireJournal.instance.record_specimen(stone)


func _update_status() -> void:
	var title: String = "Gem Polisher" if mode == Mode.POLISH else "Faceting Machine"
	var state: String = "ON: hold a stone on the wheel" if running else "click the brass switch to start"
	if mode == Mode.FACET:
		state += "\ncut %d/%d: %s\n%s\n(click dial / right-click)" % [selected_cut, RockMeshes.CUT_NAMES.size() - 1,
			RockMeshes.CUT_NAMES[selected_cut], RockMeshes.CUT_INFO[selected_cut]]
	_status.text = "%s\n%s" % [title, state]
