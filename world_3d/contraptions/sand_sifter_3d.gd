class_name SandSifter3D
extends StaticBody3D
## Shaking sand sieve. Drop a sand bag in the hopper, then drag the shaker
## handle back and forth. Each grain class passes the screens at a rate set by
## how hard you shake: coarse grains stay on the top screen, medium on the
## middle, fine and dust fall through to the bottom. Every class pours into
## its own tray. Treasures hidden in the bag turn up as the charge thins out.

const SHAKE_RATE: float = 0.9
const STROKE_METERS: float = 0.05
const IDLE_TEXT: String = "Sand Sifter\ndrop a sand bag in the top"

@export var model: PackedScene
@export var deck_model: PackedScene
@export var trays: Array[Vessel3D] = []
@export var deck_height_meters: float = 0.2

var charge_kg: PackedFloat64Array = PackedFloat64Array()
var charge_species: PackedInt32Array = PackedInt32Array()
var charge_class: PackedInt32Array = PackedInt32Array()
var _charge_total_kg: float = 0.0
var _treasures: Array[MineralData] = []
var _treasure_chances: PackedFloat32Array = PackedFloat32Array()
var _treasure_thresholds: PackedFloat32Array = PackedFloat32Array()
var _bag_name: String = ""
var _handle: MachineHandle3D
var _deck: Node3D
var _hopper: Area3D
var _rain: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _status: Label3D
var _rest_x: float = 0.0
var _shake_hint_s: float = 0.0


func _ready() -> void:
	collision_layer = SimConstants.LAYER_STATIC_BENCH
	collision_mask = 0
	if model != null:
		var visual: Node3D = model.instantiate() as Node3D
		add_child(visual)
		PropMaterials.apply(visual)
	_hopper = Area3D.new()
	_hopper.collision_layer = 0
	_hopper.collision_mask = SimConstants.LAYER_SOLID_REAGENT
	_hopper.monitorable = false
	var hs: CollisionShape3D = CollisionShape3D.new()
	var hb: BoxShape3D = BoxShape3D.new()
	hb.size = Vector3(0.2, 0.12, 0.16)
	hs.shape = hb
	_hopper.add_child(hs)
	_hopper.position.y = deck_height_meters + 0.08
	add_child(_hopper)
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(0.22, 0.01, 0.18)
	var fc: CollisionShape3D = CollisionShape3D.new()
	fc.shape = floor_shape
	fc.position.y = deck_height_meters + 0.03
	add_child(fc)
	_rain_process = ParticleProcessMaterial.new()
	_rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_process.emission_box_extents = Vector3(0.09, 0.002, 0.07)
	_rain_process.direction = Vector3.DOWN
	_rain_process.spread = 5.0
	_rain_process.initial_velocity_min = 0.05
	_rain_process.initial_velocity_max = 0.1
	_rain_process.gravity = Vector3(0.0, -3.0, 0.0)
	_rain = GPUParticles3D.new()
	_rain.amount = 160
	_rain.lifetime = 0.35
	_rain.emitting = false
	_rain.process_material = _rain_process
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.003, 0.003)
	quad.material = VesselEffects.billboard_material(false, 0.0)
	_rain.draw_pass_1 = quad
	_rain.position.y = deck_height_meters - 0.01
	add_child(_rain)
	_status = Label3D.new()
	_status.font_size = 32
	_status.pixel_size = 0.00045
	_status.outline_size = 8
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.position = Vector3(0.0, 0.17, 0.15)
	_status.text = IDLE_TEXT
	add_child(_status)
	# Catch zone over the hopper: a sand bag let go roughly above it drops in.
	MachineIntake.make(self, "sand sifter", Vector3(0.3, 0.3, 0.5), Vector3(0.0, deck_height_meters + 0.3, 0.0),
		Vector3(0.0, deck_height_meters + 0.08, 0.0), _takes)
	_build_shaker.call_deferred()


func _build_shaker() -> void:
	_handle = MachineHandle3D.new()
	_handle.knob_color = Color(0.2, 0.35, 0.6)
	_handle.label = "Shaker handle"
	_handle.hint = "Drag the handle left and right to shake the sieve"
	get_parent().add_child(_handle)
	_handle.global_position = global_transform * Vector3(0.17, deck_height_meters + 0.05, 0.0)
	_rest_x = (global_transform.affine_inverse() * _handle.global_position).x
	if deck_model != null:
		_deck = deck_model.instantiate() as Node3D
		add_child(_deck)
		PropMaterials.apply(_deck)
		_deck.position.y = deck_height_meters
	var slider: SliderJoint3D = SliderJoint3D.new()
	add_child(slider)
	slider.global_transform = Transform3D(global_basis, _handle.global_position)  # slides along local X
	slider.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_UPPER, STROKE_METERS)
	slider.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_LOWER, -STROKE_METERS)
	slider.node_a = slider.get_path_to(self)
	slider.node_b = slider.get_path_to(_handle)
	# A push rod from the knob to the sieve deck, so it is clear what the
	# handle moves.
	if _deck != null:
		var rod: MeshInstance3D = MeshInstance3D.new()
		var rod_mesh: CylinderMesh = CylinderMesh.new()
		var reach: float = _rest_x - 0.1
		rod_mesh.top_radius = 0.004
		rod_mesh.bottom_radius = 0.004
		rod_mesh.height = reach
		rod_mesh.material = PropMaterials.textured("metal", Color(0.85, 0.65, 0.3), 0.1, 0.9)
		rod.mesh = rod_mesh
		rod.rotation.z = PI * 0.5
		rod.position = Vector3(0.1 + reach * 0.5, 0.05, 0.0)
		_deck.add_child(rod)


## Size class of a grain substance: 0 coarse (top screen), 1 medium, 2 fine.
static func grain_class(s: SubstanceData) -> int:
	var id: String = String(s.substance_id)
	if id.contains("coarse"):
		return 0
	if id.contains("medium") or id in ["garnet_sand", "magnetite_sand", "obsidian_glitter"]:
		return 1
	return 2


func _physics_process(delta: float) -> void:
	if _handle == null:
		return
	if _deck != null:
		_deck.position.x = (global_transform.affine_inverse() * _handle.global_position).x - _rest_x
	if _charge_total_kg <= 0.0:
		_rain.emitting = false
		_load_bag()
		return
	var shake: float = absf(_handle.linear_velocity.dot(global_basis.x))
	var f: float = 1.0 - exp(-SHAKE_RATE * shake * delta)
	var remaining: float = 0.0
	for k: int in charge_kg.size():
		var moved: float = charge_kg[k] * f * (0.6 if charge_class[k] == 0 else 1.0)
		if moved > 0.0:
			charge_kg[k] -= moved
			var tray: Vessel3D = trays[charge_class[k]] if charge_class[k] < trays.size() else null
			if tray != null and tray.mixture != null:
				var s: SubstanceData = SubstanceRegistry.get_substance(charge_species[k])
				tray.mixture.add_substance(charge_species[k], moved / s.molar_mass_kg_mol, SimConstants.AMBIENT_TEMP_KELVIN)
		remaining += charge_kg[k]
	var fraction_left: float = remaining / _charge_total_kg
	_rain.emitting = shake > 0.05
	AudioDirector.loop(&"sifter", &"sifter_loop", global_position, clampf(shake / 0.5, 0.0, 1.0) * clampf(fraction_left * 3.0 + 0.25, 0.0, 1.0), clampf(0.85 + shake * 0.4, 0.85, 1.3), -4.0)
	_status.text = "Sifting %s  %d%%" % [_bag_name, int((1.0 - fraction_left) * 100.0)]
	if shake < 0.05:
		_shake_hint_s += delta
		if _shake_hint_s > 2.0:
			_status.text += "\ndrag the blue handle left-right"
	else:
		_shake_hint_s = 0.0
	for t: int in _treasures.size():
		if _treasure_thresholds[t] > 0.0 and fraction_left < _treasure_thresholds[t]:
			_treasure_thresholds[t] = -1.0
			if randf() < _treasure_chances[t]:
				_reveal(_treasures[t])
	if fraction_left < 0.01:
		_charge_total_kg = 0.0
		_status.text = "Sand Sifter\ndone! drop in another bag"
		_shake_hint_s = 0.0
		if GrimoireJournal.instance != null:
			GrimoireJournal.instance.toast.emit("Sifted %s into coarse, medium and fine trays" % _bag_name, &"bottle")


func _load_bag() -> void:
	for body: Node3D in _hopper.get_overlapping_bodies():
		var bag: Rock3D = body as Rock3D
		if bag == null or bag.mineral == null or bag.mineral.kind != MineralData.Kind.SAND:
			continue
		var m: MineralData = bag.mineral
		charge_kg.clear()
		charge_species.clear()
		charge_class.clear()
		var total: float = 0.0
		for f: float in m.crush_fractions:
			total += f
		for k: int in mini(m.crush_products.size(), m.crush_fractions.size()):
			var s: SubstanceData = m.crush_products[k] as SubstanceData
			charge_kg.append(bag.mass_kg * m.crush_fractions[k] / maxf(total, 1e-6))
			charge_species.append(SubstanceRegistry.index_of(s))
			charge_class.append(grain_class(s))
		_charge_total_kg = bag.mass_kg
		_treasures.clear()
		_treasure_chances.clear()
		_treasure_thresholds.clear()
		for k: int in mini(m.inclusions.size(), m.inclusion_chances.size()):
			_treasures.append(m.inclusions[k] as MineralData)
			_treasure_chances.append(m.inclusion_chances[k])
			_treasure_thresholds.append(randf_range(0.15, 0.8))
		_bag_name = m.display_name.replace(" Bag", "")
		_rain_process.color = m.color
		_status.text = "%s loaded\ndrag the blue handle left-right" % _bag_name
		bag.queue_free()
		return


func _reveal(m: MineralData) -> void:
	var find: Rock3D = Rock3D.spawn(get_parent(), m, global_transform * Vector3(-0.14, deck_height_meters + 0.08, 0.0), m.typical_mass_kg)
	find.linear_velocity = -global_basis.x * 0.3 + Vector3.UP * 0.4
	if GrimoireJournal.instance != null:
		GrimoireJournal.instance.toast.emit("Something glints in the sieve... a %s!" % m.display_name, &"discovery")
		GrimoireJournal.instance.record_find(m)


func _takes(b: Node) -> bool:
	var bag: Rock3D = b as Rock3D
	return bag != null and bag.mineral != null and bag.mineral.kind == MineralData.Kind.SAND


## Short hover text.
func hover_info() -> String:
	if _charge_total_kg > 0.0:
		return "[b]Sand Sifter[/b]  [color=#5CE1E6]%s[/color]  [color=#B3ADD6]shake the blue handle[/color]" % _bag_name
	return "[b]Sand Sifter[/b]  [color=#B3ADD6]drop a sand bag in the top, shake the handle; grains sort into three beakers[/color]"
