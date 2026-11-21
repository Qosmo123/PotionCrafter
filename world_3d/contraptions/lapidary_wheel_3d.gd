class_name LapidaryWheel3D
extends StaticBody3D
## Lapidary bench machine. Click the brass switch to start the wheel, then hold
## a mineral or gem against it with the grabber.
##   POLISH: polish rises with contact time, slower for harder stones (Mohs).
##   FACET:  click the index dial (or press F) to open the cut picker; holding
##           a polished gem steady on the lap cuts the facets. Cut quality =
##           polish + steadiness of your hand while cutting, times how well the
##           cut suits the stone. A fan of prism rays brightens as the facets
##           come in; the ring on the lap shows how steady your hand is.
##           Cuts done 3x at 70%+ are mastered and can be quick-faceted.

enum Mode { POLISH, FACET }

const PRISM_SHADER: Shader = preload("res://visuals_3d/shaders/prism_ray.gdshader")
const RAY_COLORS: PackedColorArray = [Color("#FF5A5A"), Color("#FFA34D"), Color("#FFE45C"), Color("#6BFF8A"), Color("#5CE1E6"), Color("#6B8BFF"), Color("#B46BFF")]
const QUICK_FACET_SPEED: float = 4.0

## The faceting machine in the scene (read by the cut picker).
static var faceter: LapidaryWheel3D = null

signal cut_changed

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
var quick_facet: bool = false
## Smoothed steadiness of the hand right now (0..1), for the ring and meters.
var live_steadiness: float = 1.0
var _rays: Array[MeshInstance3D] = []
var _beam_in: MeshInstance3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _milestone: int = 0
var _ray_spin: float = 0.0
## Close-up inset of the stone on the lap (shared by both machines).
static var _loupe: FacetLoupe = null


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	if model != null:
		var visual: Node3D = model.instantiate() as Node3D
		add_child(visual)
		PropMaterials.apply(visual)
		_reskin_period(visual)
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
	_status = WorldPill.new()
	_status.busy = func() -> bool: return running
	_status.font_size = 32
	_status.pixel_size = 0.00045
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
	if mode == Mode.FACET:
		faceter = self
		_build_light_guides()
		var panel: CanvasLayer = (load("res://world_3d/grimoire_system/faceting_panel.gd") as GDScript).new() as CanvasLayer
		add_child(panel)
	_update_status()


func _exit_tree() -> void:
	if faceter == self:
		faceter = null


## Prism fan (one incoming white beam, seven rainbow rays out) and the
## steadiness ring on the lap.
func _build_light_guides() -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = PRISM_SHADER
	for i: int in RAY_COLORS.size() + 1:
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(0.008 if i > 0 else 0.012, 1.0)
		quad.center_offset = Vector3(0.0, -0.5, 0.0)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		mi.set_instance_shader_parameter(&"tint", Color.WHITE if i == 0 else RAY_COLORS[i - 1])
		if i == 0:
			_beam_in = mi
		else:
			_rays.append(mi)
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = wheel_radius_meters * 0.55
	torus.outer_radius = wheel_radius_meters * 0.6
	torus.rings = 48
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(CosmicTheme.SUCCESS, 0.0)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = wheel_height_meters + 0.006
	_ring.scale = Vector3(1.0, 0.25, 1.0)
	add_child(_ring)


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
		if press.button_index == MOUSE_BUTTON_LEFT:
			picker_requested.emit()
		else:
			cycle_cut(1)
		AudioHaptics.tick()
		AudioDirector.play(&"click", global_position, -8.0)
		_update_status()
		get_viewport().set_input_as_handled()


signal picker_requested


## Step the index dial through every cut (skipping "Uncut").
func cycle_cut(step: int) -> void:
	var count: int = RockMeshes.CUT_NAMES.size() - 1
	select_cut(posmod(selected_cut - 1 + step, count) + 1)


func select_cut(cut: int) -> void:
	selected_cut = clampi(cut, 1, RockMeshes.CUT_NAMES.size() - 1)
	if not is_mastered(selected_cut):
		quick_facet = false
	_cut_progress = 0.0
	_milestone = 0
	_update_status()
	cut_changed.emit()


static func is_mastered(cut: int) -> bool:
	return GrimoireJournal.instance != null and GrimoireJournal.instance.is_mastered(RockMeshes.CUT_NAMES[cut])


## The stone being worked (or null).
func work_target() -> Rock3D:
	return _work_target if is_instance_valid(_work_target) else null


func cut_progress() -> float:
	return _cut_progress


## Quality the cut would get if it finished now.
func projected_quality() -> float:
	var stone: Rock3D = work_target()
	if stone == null:
		return 0.0
	var steadiness: float = _steadiness_sum / maxf(float(_steadiness_samples), 1.0) if _steadiness_samples > 0 else live_steadiness
	return clampf((stone.polish * 0.4 + steadiness * 0.6) * cut_suitability(stone.mineral, selected_cut), 0.0, 1.0)


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
	AudioDirector.play(&"switch", global_position, -6.0)
	_update_status()


func _process(delta: float) -> void:
	_spin = lerpf(_spin, 40.0 if running else 0.0, 1.0 - exp(-delta * 2.0))
	# Motor whirr follows the wheel as it spins up and down.
	AudioDirector.loop(&"wheel", &"wheel_loop", global_position, clampf(_spin / 40.0, 0.0, 1.0) * 0.8, 0.5 + 0.5 * _spin / 40.0, -12.0)
	_wheel.rotation.y += _spin * delta
	if mode == Mode.FACET and _ring != null:
		_update_light_guides(delta)


## Live light guides: rays grow and brighten with cut progress x steadiness;
## the ring glows green when the hand is steady, amber/pink when it wobbles.
func _update_light_guides(delta: float) -> void:
	var stone: Rock3D = work_target()
	var active: bool = running and stone != null and stone.mineral.can_facet and stone.polish >= 0.3
	var ring_target: float = 0.75 if running and stone != null else (0.25 if running else 0.0)
	var ring_col: Color = CosmicTheme.SUCCESS.lerp(CosmicTheme.WARNING, clampf((0.85 - live_steadiness) * 3.0, 0.0, 1.0))
	ring_col = ring_col.lerp(CosmicTheme.PRISM_PINK, clampf((0.5 - live_steadiness) * 3.0, 0.0, 1.0))
	_ring_mat.albedo_color = Color(ring_col, lerpf(_ring_mat.albedo_color.a, ring_target, 1.0 - exp(-delta * 6.0)))
	_beam_in.visible = active
	for r: MeshInstance3D in _rays:
		r.visible = active
	if not active:
		return
	var glow: float = clampf(_cut_progress, 0.0, 1.0) * (0.35 + 0.65 * live_steadiness)
	var center: Vector3 = stone.global_position
	var cam: Camera3D = get_viewport().get_camera_3d()
	# Incoming white beam from a lamp above-behind.
	_orient_ray(_beam_in, center + Vector3(-0.05, 0.3, -0.12), center, cam, 0.6 + 0.4 * glow)
	_ray_spin += delta * 0.6
	for i: int in _rays.size():
		var a: float = _ray_spin + TAU * float(i) / float(_rays.size())
		var dir: Vector3 = Vector3(cos(a), 0.55 + 0.15 * sin(a * 2.0), sin(a)).normalized()
		var length: float = 0.05 + 0.18 * glow
		_orient_ray(_rays[i], center, center + dir * length, cam, glow)


## Point a quad ray from `a` to `b`, turned to face the camera.
static func _orient_ray(ray: MeshInstance3D, a: Vector3, b: Vector3, cam: Camera3D, strength: float) -> void:
	var along: Vector3 = b - a
	var length: float = along.length()
	if length < 1e-4:
		ray.visible = false
		return
	var y: Vector3 = -along / length  # QuadMesh tip is at -Y after the center offset
	var to_cam: Vector3 = (cam.global_position - a).normalized() if cam != null else Vector3.BACK
	var x: Vector3 = y.cross(to_cam).normalized()
	if x.length() < 0.5:
		x = y.cross(Vector3.UP).normalized()
	var z: Vector3 = x.cross(y)
	ray.global_transform = Transform3D(Basis(x, y * length, z), a)
	ray.set_instance_shader_parameter(&"strength", strength)


## The shared close-up loupe, created on first use.
func _get_loupe() -> FacetLoupe:
	if _loupe == null or not is_instance_valid(_loupe):
		_loupe = FacetLoupe.new()
		get_tree().root.add_child(_loupe)
	return _loupe


func _physics_process(delta: float) -> void:
	_sparks.emitting = false
	_update_loupe()
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
	# Harder stones scream higher against the lap; polishing is gentler.
	AudioDirector.loop(&"grind", &"grind_loop", stone.global_position, 0.55 if mode == Mode.POLISH else 0.9, 0.8 + stone.mineral.hardness_mohs * 0.05, -9.0)
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
		var sample: float = clampf(1.0 - stone.linear_velocity.length() * 6.0, 0.0, 1.0)
		var mastered: bool = quick_facet and is_mastered(selected_cut)
		if mastered:
			# Practised hands: the mastered cut goes fast and holds your best form.
			sample = maxf(sample, float(GrimoireJournal.instance.cut_mastery[RockMeshes.CUT_NAMES[selected_cut]]["best"]) * 0.95)
		live_steadiness = lerpf(live_steadiness, sample, 1.0 - exp(-delta * 8.0))
		_steadiness_sum += sample
		_steadiness_samples += 1
		_cut_progress += delta * 0.2 / hardness_drag * (QUICK_FACET_SPEED if mastered else 1.0)
		var quarter: int = int(_cut_progress * 4.0)
		if quarter > _milestone and quarter < 4:
			# Crystalline chime cue: a glint of sparks each quarter of the way.
			_milestone = quarter
			AudioHaptics.tick()
			AudioDirector.play(&"impact_crystal", stone.global_position, -8.0, 1.0 + 0.12 * float(quarter))
			var fx: ImpactFx3D = ImpactFx3D.get_pool(self)
			if fx != null:
				fx.hit(stone.global_position + Vector3(0.0, 0.015, 0.0), stone.mineral.color, CosmicTheme.STARLIGHT_GOLD, 0.35)
		_status.text = "Cutting %s: %s\n%d%%  steady hands!" % [stone.mineral.display_name, RockMeshes.CUT_NAMES[selected_cut], int(_cut_progress * 100.0)]
		if _cut_progress >= 1.0:
			var steadiness: float = _steadiness_sum / maxf(float(_steadiness_samples), 1.0)
			var suit: float = cut_suitability(stone.mineral, selected_cut)
			stone.apply_cut(selected_cut, clampf((stone.polish * 0.4 + steadiness * 0.6) * suit, 0.0, 1.0))
			var fx: ImpactFx3D = ImpactFx3D.get_pool(self)
			if fx != null:
				fx.reveal(stone.global_position - Vector3(0.0, 0.02, 0.0), CosmicTheme.STARLIGHT_GOLD if stone.cut_quality >= 0.85 else CosmicTheme.PRISM_CYAN)
			if GrimoireJournal.instance != null and GrimoireJournal.instance.record_cut(RockMeshes.CUT_NAMES[selected_cut], stone.cut_quality):
				GrimoireJournal.instance.toast.emit("Cut mastered: %s! Quick-facet is now available for it." % RockMeshes.CUT_NAMES[selected_cut], &"secret")
			_milestone = 0
			var tip: String = ""
			if suit > 1.0:
				tip = "  Perfect choice: a cabochon shows off its %s!" % ("magic" if stone.mineral.phenomenon == MineralData.Phenomenon.NONE else MineralData.PHENOMENON_NAMES[stone.mineral.phenomenon])
			elif suit < 0.8:
				tip = "  Tip: opaque or phenomenal stones look best as a Cabochon."
			_announce(stone, "Faceted a %s! Quality %d%%, worth %d ◉%s" % [stone.describe_name(), int(stone.cut_quality * 100.0), stone.value(), tip])
			# Hero shot of the finished gem.
			var grade: String = "flawless" if stone.cut_quality >= 0.92 else ("fine" if stone.cut_quality >= 0.75 else ("good" if stone.cut_quality >= 0.5 else "rough"))
			GemShowcase.play(stone, "Faceted  ·  %s cut" % RockMeshes.CUT_NAMES[selected_cut], stone.describe_name(),
				"%s work, quality %d%%  ·  worth %d coins  ·  Mohs %.1f" % [grade.capitalize(), int(stone.cut_quality * 100.0), stone.value(), stone.mineral.hardness_mohs],
				clampi(stone.mineral.rarity + (1 if stone.cut_quality >= 0.92 else 0), 1, 4))
			_cut_progress = 0.0
			_work_target = null


## Keep the close-up on the stone while this machine is working it.
func _update_loupe() -> void:
	var stone: Rock3D = _work_target if running else null
	if stone == null or not is_instance_valid(stone):
		if _loupe != null and is_instance_valid(_loupe) and _loupe.get_meta(&"owner", null) == self:
			_loupe.hide_loupe()
		return
	var loupe: FacetLoupe = _get_loupe()
	loupe.set_meta(&"owner", self)
	if mode == Mode.POLISH:
		loupe.show_on(stone, stone.polish, 1.0, stone.mineral.display_name, "polishing  ·  %d%%" % int(stone.polish * 100.0))
	elif stone.mineral.can_facet and stone.polish >= 0.3:
		loupe.show_on(stone, _cut_progress, live_steadiness, "%s  ·  %s cut" % [stone.mineral.display_name, RockMeshes.CUT_NAMES[selected_cut]],
			"%d%%  ·  hold steady (%d%% steady)" % [int(_cut_progress * 100.0), int(live_steadiness * 100.0)])
	else:
		loupe.show_on(stone, stone.polish / 0.3, 1.0, stone.mineral.display_name,
			"can't be faceted: try a gem" if not stone.mineral.can_facet else "polish it to 30% first")


func _announce(stone: Rock3D, text: String) -> void:
	if GrimoireJournal.instance != null:
		GrimoireJournal.instance.toast.emit(text, &"coins")
		GrimoireJournal.instance.record_specimen(stone)


func _update_status() -> void:
	var title: String = "Gem Polisher" if mode == Mode.POLISH else "Faceting Machine"
	var state: String = "on · hold a stone on the wheel" if running else "click the brass switch"
	if mode == Mode.FACET:
		title += "\ncut: %s%s  (F to change)" % [RockMeshes.CUT_NAMES[selected_cut], " ⚡" if quick_facet else ""]
	_status.text = "%s\n%s" % [title, state]


## Short hover text.
func hover_info() -> String:
	if mode == Mode.FACET:
		return "[b]Faceting Machine[/b]  [color=#5CE1E6]%s · %s[/color]  [color=#B3ADD6]switch on, hold a polished gem on the wheel; F picks the cut[/color]" % ["on" if running else "off", RockMeshes.CUT_NAMES[selected_cut]]
	return "[b]Gem Polisher[/b]  [color=#5CE1E6]%s[/color]  [color=#B3ADD6]switch on, hold a stone on the wheel until it shines[/color]" % ("on" if running else "off")



## The model's housing was white plastic, out of place among the iron and
## brass. Light-coloured parts become dark green enamel over cast iron;
## everything else (copper ring, brass) keeps its material.
func _reskin_period(visual: Node3D) -> void:
	var enamel: StandardMaterial3D = PropMaterials.textured("iron", Color(0.1, 0.17, 0.14), 0.15, 0.25)
	enamel.roughness = 0.38
	enamel.clearcoat_enabled = true
	enamel.clearcoat = 0.7
	enamel.clearcoat_roughness = 0.25
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		for s: int in mi.mesh.get_surface_count():
			var mat: BaseMaterial3D = mi.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var c: Color = mat.albedo_color
			if c.get_luminance() > 0.6 and c.s < 0.25:
				mi.set_surface_override_material(s, enamel)