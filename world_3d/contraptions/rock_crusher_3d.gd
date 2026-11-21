class_name RockCrusher3D
extends StaticBody3D
## Hand-cranked rock mill. Drop a rock into the hopper and turn the crank: each
## radian of cranking does work against the rock; it needs roughly
## hardness^1.6 × mass × 25 J, so soft fizzrock grinds in seconds while
## meteorite takes real effort. The rock's mass pours into the tray vessel as
## its crush products (mass-conserving), and hidden inclusions may tumble out.

const CRANK_TORQUE_N_M: float = 2.0
const CRANK_RADIUS_METERS: float = 0.075

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
	_status.position = Vector3(0.0, crank_height_meters + 0.08, 0.0)
	_status.text = "Rock Crusher\ndrop a rock in, turn the crank"
	add_child(_status)


func _build_crank() -> void:
	_handle = MachineHandle3D.new()
	_handle.knob_color = Color(0.6, 0.2, 0.08)
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
				_status.text = "%s in the hopper\nturn the crank!" % rock.mineral.display_name
				break
	var omega: float = absf(_handle.angular_velocity.dot(global_basis.y))
	_dust.emitting = _current != null and omega > 0.8
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


func _finish(rock: Rock3D) -> void:
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
	_status.text = "Rock Crusher\ndrop a rock in, turn the crank"
	rock.queue_free()
	_current = null
	_work_joules = 0.0
	progress = 0.0
