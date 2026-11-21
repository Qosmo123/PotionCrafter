class_name RockCrusher3D
extends StaticBody3D
## Hand-cranked rock mill. Drop a rock into the hopper and turn the crank: each
## radian of cranking does work against the rock; it needs roughly
## hardness^1.6 × mass × 25 J, so soft fizzrock grinds in seconds while
## meteorite takes real effort. The rock's mass pours into the tray vessel as
## its crush products (mass-conserving), and hidden inclusions may tumble out.

const CRANK_TORQUE_N_M: float = 2.0
const CRANK_RADIUS_METERS: float = 0.075
const IDLE_TEXT: String = "Rock Crusher\ndrop a rock in the top"

@export var model: PackedScene
@export var tray: Vessel3D
@export var hopper_height_meters: float = 0.26
@export var crank_height_meters: float = 0.34

var progress: float = 0.0
var _handle: MachineHandle3D
var _hopper: Area3D
var _current: Rock3D = null
var _work_joules: float = 0.0
var _dust: GPUParticles3D
var _dust_process: ParticleProcessMaterial
var _status: Label3D
var _gear: Node3D
var _needle: Node3D
var _crank_angle: float = 0.0
var _last_handle_angle: float = NAN


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	if model != null:
		var visual: Node3D = model.instantiate() as Node3D
		add_child(visual)
		PropMaterials.apply(visual)
	# Housing below the hopper, plus four hopper walls so rocks sit inside.
	_box(Vector3(0.16, hopper_height_meters - 0.06, 0.16), Vector3(0.0, (hopper_height_meters - 0.06) * 0.5, 0.0))
	for i: int in 4:
		var a: float = PI * 0.5 * float(i)
		var d: Vector3 = Vector3(cos(a), 0.0, sin(a))
		_box(Vector3(0.012, 0.08, 0.14) if i % 2 == 0 else Vector3(0.14, 0.08, 0.012), d * 0.065 + Vector3(0.0, hopper_height_meters + 0.0, 0.0))
	_hopper = Area3D.new()
	_hopper.collision_layer = 0
	_hopper.collision_mask = SimConstants.LAYER_SOLID_REAGENT
	_hopper.monitorable = false
	var hs: CollisionShape3D = CollisionShape3D.new()
	var hb: BoxShape3D = BoxShape3D.new()
	hb.size = Vector3(0.12, 0.1, 0.12)
	hs.shape = hb
	_hopper.add_child(hs)
	_hopper.position.y = hopper_height_meters - 0.01
	add_child(_hopper)
	_build_crank.call_deferred()
	_dust_process = ParticleProcessMaterial.new()
	_dust_process.direction = Vector3(0.0, -0.3, 1.0)
	_dust_process.spread = 20.0
	_dust_process.initial_velocity_min = 0.05
	_dust_process.initial_velocity_max = 0.15
	_dust_process.gravity = Vector3(0.0, -1.5, 0.0)
	_dust_process.scale_min = 0.5
	_dust_process.scale_max = 1.5
	_dust = GPUParticles3D.new()
	_dust.amount = 60
	_dust.lifetime = 0.8
	_dust.emitting = false
	_dust.process_material = _dust_process
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.006, 0.006)
	quad.material = VesselEffects.billboard_material(false, 0.0)
	_dust.draw_pass_1 = quad
	_dust.position = Vector3(0.0, 0.07, 0.09)
	add_child(_dust)
	_status = Label3D.new()
	_status.font_size = 32
	_status.pixel_size = 0.00045
	_status.outline_size = 8
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.position = Vector3(0.0, 0.235, 0.1)  # on the dark upper housing
	_status.text = IDLE_TEXT
	add_child(_status)
	# Catch zone over the hopper: a rock let go roughly above it drops in.
	MachineIntake.make(self, "rock crusher", Vector3(0.3, 0.34, 0.5), Vector3(0.0, hopper_height_meters + 0.22, 0.0),
		Vector3(0.0, hopper_height_meters - 0.01, 0.0), _takes)
	_build_detail()


func _build_crank() -> void:
	_handle = MachineHandle3D.new()
	_handle.knob_color = Color(0.6, 0.2, 0.08)
	_handle.label = "Crusher crank"
	_handle.hint = "Drag the crank round in circles to crush the rock"
	get_parent().add_child(_handle)
	var axis_world: Vector3 = global_transform * Vector3(0.0, crank_height_meters, 0.0)
	_handle.global_position = axis_world + global_basis.x * CRANK_RADIUS_METERS
	var arm: MeshInstance3D = MeshInstance3D.new()
	var arm_mesh: BoxMesh = BoxMesh.new()
	arm_mesh.size = Vector3(CRANK_RADIUS_METERS, 0.008, 0.014)
	var brass: StandardMaterial3D = StandardMaterial3D.new()
	brass.albedo_color = Color(0.85, 0.65, 0.3)
	brass.metallic = 1.0
	brass.roughness = 0.3
	arm_mesh.material = brass
	arm.mesh = arm_mesh
	arm.position = Vector3(-CRANK_RADIUS_METERS * 0.5, -0.012, 0.0)
	_handle.add_child(arm)
	var hinge: HingeJoint3D = HingeJoint3D.new()
	add_child(hinge)
	hinge.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), axis_world)  # hinge axis = local Z -> world Y
	hinge.node_a = hinge.get_path_to(self)
	hinge.node_b = hinge.get_path_to(_handle)


func _box(size: Vector3, center: Vector3) -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	add_child(cs)


func required_work_joules(rock: Rock3D) -> float:
	return pow(rock.mineral.hardness_mohs, 1.6) * rock.mass_kg * 25.0


func _physics_process(delta: float) -> void:
	if _handle == null:
		return
	if _current == null or not is_instance_valid(_current):
		_current = null
		_work_joules = 0.0
		progress = 0.0
		for body: Node3D in _hopper.get_overlapping_bodies():
			var rock: Rock3D = body as Rock3D
			if rock != null and rock.mineral != null and rock.mineral.kind != MineralData.Kind.SAND:
				_current = rock
				_status.text = "%s loaded\ndrag the red crank in circles" % rock.mineral.display_name
				break
	var omega: float = absf(_handle.angular_velocity.dot(global_basis.y))
	_animate()
	_dust.emitting = _current != null and omega > 0.8
	# The crank ratchets freely; with a rock in the jaws it grinds.
	if _current != null:
		AudioDirector.loop(&"crusher", &"crusher_loop", global_position, clampf(omega / 5.0, 0.0, 1.0), clampf(0.75 + omega * 0.06, 0.75, 1.3), -3.0)
	elif omega > 1.0 and randf() < _delta_ratchet(omega):
		AudioDirector.play(&"ratchet", global_position, -14.0)
	if _current == null:
		return
	_work_joules += omega * CRANK_TORQUE_N_M * delta
	progress = clampf(_work_joules / required_work_joules(_current), 0.0, 1.0)
	_status.text = "Crushing %s  %d%%" % [_current.mineral.display_name, int(progress * 100.0)]
	if _dust.emitting:
		_dust_process.color = _current.mineral.color
		if randf() < delta * 6.0:
			AudioHaptics.impact(0.6)
	if progress >= 1.0:
		_finish(_current)


## Chance per tick of a ratchet click at this crank speed (about 2 per turn).
func _delta_ratchet(omega_rad_s: float) -> float:
	return clampf(omega_rad_s / PI * get_physics_process_delta_time(), 0.0, 1.0)


func _finish(rock: Rock3D) -> void:
	AudioDirector.play(&"rock_crack", global_position, -2.0, 0.85)
	AudioDirector.play(&"sand_pour", global_position, -6.0)
	var m: MineralData = rock.mineral
	var made: PackedStringArray = PackedStringArray()
	var total: float = 0.0
	for f: float in m.crush_fractions:
		total += f
	for k: int in mini(m.crush_products.size(), m.crush_fractions.size()):
		var product: SubstanceData = m.crush_products[k] as SubstanceData
		var kg: float = rock.mass_kg * m.crush_fractions[k] / maxf(total, 1e-6)
		if tray != null and tray.mixture != null:
			tray.mixture.add_substance(SubstanceRegistry.index_of(product), kg / product.molar_mass_kg_mol, SimConstants.AMBIENT_TEMP_KELVIN)
		made.append("%.0f g %s" % [kg * 1000.0, product.display_name])
	var finds: PackedStringArray = PackedStringArray()
	if not rock.exhausted:
		for k: int in mini(m.inclusions.size(), m.inclusion_chances.size()):
			if randf() < m.inclusion_chances[k] * 0.5:  # grinding destroys some finds
				var find_m: MineralData = m.inclusions[k] as MineralData
				var find: Rock3D = Rock3D.spawn(get_parent(), find_m, global_transform * Vector3(0.0, 0.12, 0.14), find_m.typical_mass_kg)
				find.linear_velocity = global_basis.z * 0.4
				finds.append(find_m.display_name)
				if GrimoireJournal.instance != null:
					GrimoireJournal.instance.record_find(find_m)
	if GrimoireJournal.instance != null:
		var text: String = "Crushed %s → %s" % [m.display_name, ", ".join(made)]
		if not finds.is_empty():
			text += "   Found: " + ", ".join(finds)
		GrimoireJournal.instance.toast.emit(text, &"bottle")
	_status.text = IDLE_TEXT
	rock.queue_free()
	_current = null
	_work_joules = 0.0
	progress = 0.0


func _takes(b: Node) -> bool:
	var rock: Rock3D = b as Rock3D
	return rock != null and rock.mineral != null and rock.mineral.kind != MineralData.Kind.SAND


## Short hover text.
func hover_info() -> String:
	if _current != null:
		return "[b]Rock Crusher[/b]  [color=#5CE1E6]%s · %d%%[/color]  [color=#B3ADD6]turn the crank[/color]" % [_current.mineral.display_name, int(progress * 100.0)]
	return "[b]Rock Crusher[/b]  [color=#B3ADD6]drop a rock in the top, turn the crank; the powder lands in the beaker[/color]"


# --- Detail -------------------------------------------------------------------------

## Extra parts on top of the Blender model: a funnel flare on the hopper, a
## geared drive wheel and a progress gauge either side of the nameplate, and
## a feed chute down to the tray. The gear turns with the crank; the gauge needle
## shows how far the current rock is ground.
func _build_detail() -> void:
	var iron: StandardMaterial3D = PropMaterials.textured("iron", Color(0.2, 0.2, 0.22), 0.12, 0.65)
	var brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.88, 0.66, 0.3), 0.1, 0.9)
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.07, 0.07)
	dark.roughness = 0.8
	var face_mat: StandardMaterial3D = StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.93, 0.88, 0.76)
	face_mat.roughness = 0.7
	var red: StandardMaterial3D = StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.12, 0.08)
	red.roughness = 0.5
	var front_z: float = 0.084
	var h: float = hopper_height_meters
	# Funnel flare: four plates leaning out above the hopper walls.
	for i: int in 4:
		var a: float = PI * 0.5 * float(i)
		var out: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var plate: MeshInstance3D = _part(BoxMesh.new(), iron)
		(plate.mesh as BoxMesh).size = Vector3(0.006, 0.05, 0.2)
		plate.transform = Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 0.45), out * 0.09 + Vector3(0.0, h + 0.058, 0.0))
	for k: int in 5:
		var rivet: MeshInstance3D = _part(SphereMesh.new(), brass)
		(rivet.mesh as SphereMesh).radius = 0.0035
		(rivet.mesh as SphereMesh).height = 0.005
		rivet.position = Vector3(-0.07 + 0.035 * float(k), h + 0.07, 0.104)
	# Drive gear on the front face (turns with the crank).
	_gear = Node3D.new()
	_gear.position = Vector3(-0.056, 0.1, front_z + 0.004)
	_gear.scale = Vector3.ONE * 0.62  # beside the nameplate
	add_child(_gear)
	var disc: MeshInstance3D = _part(CylinderMesh.new(), iron, _gear)
	_cyl(disc, 0.034, 0.008)
	for k: int in 16:
		var tooth: MeshInstance3D = _part(BoxMesh.new(), iron, _gear)
		(tooth.mesh as BoxMesh).size = Vector3(0.007, 0.008, 0.008)
		var ta: float = TAU * float(k) / 16.0
		tooth.transform = Transform3D(Basis(Vector3.BACK, ta), Vector3(-sin(ta), cos(ta), 0.0) * 0.037)
	for k: int in 4:
		var spoke: MeshInstance3D = _part(BoxMesh.new(), dark, _gear)
		(spoke.mesh as BoxMesh).size = Vector3(0.05, 0.005, 0.004)
		spoke.position.z = 0.005
		spoke.rotation.z = PI * 0.25 * float(k)
	var hub: MeshInstance3D = _part(CylinderMesh.new(), brass, _gear)
	_cyl(hub, 0.009, 0.014)
	# Progress gauge: cream face, red needle, brass bezel.
	var gauge: Node3D = Node3D.new()
	gauge.position = Vector3(0.056, 0.1, front_z + 0.003)
	gauge.scale = Vector3.ONE * 0.8
	add_child(gauge)
	_cyl(_part(CylinderMesh.new(), brass, gauge), 0.026, 0.006)
	var face: MeshInstance3D = _part(CylinderMesh.new(), face_mat, gauge)
	_cyl(face, 0.021, 0.002)
	face.position.z = 0.003
	for k: int in 6:
		var tick: MeshInstance3D = _part(BoxMesh.new(), dark, gauge)
		(tick.mesh as BoxMesh).size = Vector3(0.0015, 0.005, 0.001)
		var ga: float = lerpf(-2.2, 2.2, float(k) / 5.0)
		tick.transform = Transform3D(Basis(Vector3.BACK, -ga), Vector3(sin(ga), cos(ga), 0.0) * 0.016 + Vector3(0.0, 0.0, 0.0045))
	_needle = Node3D.new()
	_needle.position.z = 0.005
	gauge.add_child(_needle)
	var needle: MeshInstance3D = _part(BoxMesh.new(), red, _needle)
	(needle.mesh as BoxMesh).size = Vector3(0.002, 0.017, 0.001)
	needle.position.y = 0.007
	_needle.rotation.z = 2.2
	var label: Label3D = Label3D.new()
	label.text = "GROUND"
	label.font_size = 18
	label.pixel_size = 0.00025
	label.modulate = Color(0.2, 0.15, 0.1)
	label.outline_size = 0
	label.position = Vector3(0.0, -0.01, 0.0052)
	gauge.add_child(label)
	# Feed chute from the front bottom down toward the tray.
	var tray_local: Vector3 = to_local(tray.global_position) if tray != null else Vector3(0.0, 0.05, 0.24)
	var start: Vector3 = Vector3(0.0, 0.07, front_z)
	var finish: Vector3 = Vector3(tray_local.x, 0.08, tray_local.z - 0.035)
	var chute_dir: Vector3 = finish - start
	var chute_basis: Basis = Basis.looking_at(chute_dir.normalized(), Vector3.UP)
	var trough: MeshInstance3D = _part(BoxMesh.new(), iron)
	(trough.mesh as BoxMesh).size = Vector3(0.04, 0.004, chute_dir.length())
	trough.transform = Transform3D(chute_basis, (start + finish) * 0.5)
	for side: float in [-1.0, 1.0]:
		var lip: MeshInstance3D = _part(BoxMesh.new(), iron)
		(lip.mesh as BoxMesh).size = Vector3(0.004, 0.014, chute_dir.length())
		lip.transform = Transform3D(chute_basis, (start + finish) * 0.5 + chute_basis * Vector3(side * 0.02, 0.006, 0.0))


func _part(mesh: PrimitiveMesh, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	mesh.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	(parent if parent != null else self).add_child(mi)
	return mi


## Make a cylinder part a flat disc facing the camera (+Z).
func _cyl(mi: MeshInstance3D, radius: float, thickness: float) -> void:
	var c: CylinderMesh = mi.mesh as CylinderMesh
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = thickness
	mi.rotation.x = PI * 0.5


## Turn the gear with the crank and point the gauge at the grinding progress.
func _animate() -> void:
	var arm: Vector3 = to_local(_handle.global_position) - Vector3(0.0, crank_height_meters, 0.0)
	var a: float = atan2(arm.z, arm.x)
	if not is_nan(_last_handle_angle):
		_crank_angle += wrapf(a - _last_handle_angle, -PI, PI)
	_last_handle_angle = a
	if _gear != null:
		_gear.rotation.z = -_crank_angle * 2.0
	if _needle != null:
		_needle.rotation.z = lerpf(_needle.rotation.z, lerpf(2.2, -2.2, progress), 0.2)
