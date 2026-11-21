class_name WaterTap3D
extends Node3D
## A brass wall tap over a drip tray. It fills by itself: any open vessel
## under the spout (set on the tray, or held there) gets fresh water until it
## is nearly full, then the tap stops. Click the handle to let it run freely:
## then it keeps pouring, into the tray's drain, or over the brim of a full
## glass (which overflows onto the bench).
##
## The node sits on the bench where the tray goes; the spout hangs above it.

const WATER_ID: StringName = &"water"
## Fills a glass at 80 mL/s (a steady kitchen-tap flow).
const FLOW_M3_S: float = 8.0e-5
const FULL_FRACTION: float = 0.9
const WATER_TEMP_KELVIN: float = 288.0

static var all_taps: Array[WaterTap3D] = []

@export var spout_height_meters: float = 0.3
@export var wall_z_meters: float = -0.825

var running_free: bool = false
var filling: Vessel3D = null
var _water_index: int = -1
var _stream: MeshInstance3D
var _handle: StaticBody3D
var _handle_visual: Node3D
var _caption: Label3D
var _stream_len: float = 0.0


func _ready() -> void:
	all_taps.append(self)
	_water_index = SubstanceRegistry.index_of_id(WATER_ID)
	var brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.92, 0.7, 0.34), 0.1, 0.92)
	var spout: Vector3 = Vector3(0.0, spout_height_meters, 0.0)
	var back: float = wall_z_meters - global_position.z
	# Wall flange and the pipe running out over the bench, then the spout.
	var arm_y: float = spout_height_meters + 0.05
	_rod(Vector3(0.0, arm_y, back + 0.01), Vector3(0.0, arm_y, 0.0), 0.009, brass)
	_rod(Vector3(0.0, arm_y, 0.0), spout + Vector3(0.0, 0.012, 0.0), 0.009, brass)
	_rod(spout + Vector3(0.0, 0.012, 0.0), spout, 0.0065, brass)
	var flange: CylinderMesh = CylinderMesh.new()
	flange.top_radius = 0.026
	flange.bottom_radius = 0.026
	flange.height = 0.012
	flange.material = brass
	var flange_mi: MeshInstance3D = MeshInstance3D.new()
	flange_mi.mesh = flange
	flange_mi.rotation.x = PI * 0.5
	flange_mi.position = Vector3(0.0, arm_y, back + 0.006)
	add_child(flange_mi)
	var elbow: SphereMesh = SphereMesh.new()
	elbow.radius = 0.012
	elbow.height = 0.024
	elbow.material = brass
	var elbow_mi: MeshInstance3D = MeshInstance3D.new()
	elbow_mi.mesh = elbow
	elbow_mi.position = Vector3(0.0, arm_y, 0.0)
	add_child(elbow_mi)
	# Cross-head handle on top of the elbow (clickable).
	_handle_visual = Node3D.new()
	_handle_visual.position = Vector3(0.0, arm_y + 0.022, 0.0)
	add_child(_handle_visual)
	_rod(Vector3(0.0, -0.02, 0.0), Vector3(0.0, 0.0, 0.0), 0.004, brass, _handle_visual)
	for a: float in [0.0, PI * 0.5]:
		var bar_from: Vector3 = Vector3(cos(a), 0.0, sin(a)) * 0.026
		_rod(-bar_from, bar_from, 0.0035, brass, _handle_visual)
		for end: Vector3 in [bar_from, -bar_from]:
			var knob: SphereMesh = SphereMesh.new()
			knob.radius = 0.006
			knob.height = 0.012
			var porcelain: StandardMaterial3D = PropMaterials.textured("ceramic", Color(0.95, 0.94, 0.9), 0.1)
			knob.material = porcelain
			var knob_mi: MeshInstance3D = MeshInstance3D.new()
			knob_mi.mesh = knob
			knob_mi.position = end
			_handle_visual.add_child(knob_mi)
	_handle = ClickSwitch.make_button(self, Vector3(0.07, 0.05, 0.07), Vector3(0.0, arm_y + 0.015, 0.0))
	# Drip tray with a grate, on the bench under the spout.
	var tray_body: StaticBody3D = StaticBody3D.new()
	tray_body.collision_layer = SimConstants.LAYER_STATIC_BENCH
	tray_body.collision_mask = 0
	add_child(tray_body)
	var tray_shape: BoxShape3D = BoxShape3D.new()
	tray_shape.size = Vector3(0.13, 0.012, 0.11)
	var tray_cs: CollisionShape3D = CollisionShape3D.new()
	tray_cs.shape = tray_shape
	tray_cs.position.y = 0.006
	tray_body.add_child(tray_cs)
	var tray: BoxMesh = BoxMesh.new()
	tray.size = tray_shape.size
	tray.material = PropMaterials.textured("ceramic", Color(0.86, 0.88, 0.9), 0.2)
	var tray_mi: MeshInstance3D = MeshInstance3D.new()
	tray_mi.mesh = tray
	tray_mi.position.y = 0.006
	tray_body.add_child(tray_mi)
	for k: int in 7:
		var slat: BoxMesh = BoxMesh.new()
		slat.size = Vector3(0.11, 0.003, 0.004)
		slat.material = brass
		var slat_mi: MeshInstance3D = MeshInstance3D.new()
		slat_mi.mesh = slat
		slat_mi.position = Vector3(0.0, 0.0135, -0.042 + 0.014 * float(k))
		tray_body.add_child(slat_mi)
	var seat: SupportStand3D = SupportStand3D.new()
	seat.kind = SupportStand3D.Kind.PAD
	seat.seat_name = "tap tray"
	seat.pad_radius_meters = 0.05
	seat.position.y = 0.015
	add_child(seat)
	# The water stream (a thin bright column, stretched to the vessel).
	var column: CylinderMesh = CylinderMesh.new()
	column.top_radius = 0.0032
	column.bottom_radius = 0.0045
	column.height = 1.0
	column.radial_segments = 12
	var water: StandardMaterial3D = StandardMaterial3D.new()
	water.albedo_color = Color(0.75, 0.88, 1.0, 0.55)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	water.metallic_specular = 0.9
	water.emission_enabled = true
	water.emission = Color(0.25, 0.35, 0.45)
	column.material = water
	_stream = MeshInstance3D.new()
	_stream.mesh = column
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stream.visible = false
	add_child(_stream)
	_caption = ClickSwitch.make_caption(self, Vector3(0.0, spout_height_meters + 0.12, 0.0))
	_caption.text = "Tap · set a glass under it"


func _exit_tree() -> void:
	all_taps.erase(self)


func _rod(a: Vector3, b: Vector3, radius: float, material: Material, parent: Node3D = null) -> void:
	var length: float = a.distance_to(b)
	if length < 1e-5:
		return
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.material = material
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	var y: Vector3 = (b - a) / length
	var x: Vector3 = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	(parent if parent != null else self).add_child(mi)


func spout_world() -> Vector3:
	return global_transform * Vector3(0.0, spout_height_meters, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if ClickSwitch.clicked(self, event, [_handle]) != null:
		running_free = not running_free
		AudioDirector.play(&"click", spout_world(), -8.0)
		get_viewport().set_input_as_handled()


## The open, upright vessel whose mouth is under the spout (any height below
## it), or null.
func vessel_under() -> Vessel3D:
	var spout: Vector3 = spout_world()
	for v: Vessel3D in Vessel3D.all_vessels:
		if not v.open_top or v.sealed or v.mixture == null or not v.is_inside_tree() or v.global_basis.y.y < 0.9:
			continue
		var rim: Vector3 = v.global_transform * Vector3(0.0, v.get_lip_local_y(), 0.0)
		var r: float = v.get_lip_radius_meters()
		if rim.y < spout.y - 0.005 and rim.y > spout.y - spout_height_meters - 0.05 and absf(rim.x - spout.x) < r + 0.004 and absf(rim.z - spout.z) < r + 0.01:
			return v
	return null


func _physics_process(delta: float) -> void:
	var v: Vessel3D = vessel_under()
	filling = null
	var bottom_y: float = global_position.y + 0.015
	if v != null and (v.get_fill_fraction() < FULL_FRACTION or running_free) and _water_index >= 0:
		filling = v
		var moles: float = FLOW_M3_S * delta * SubstanceRegistry.get_substance(_water_index).density_kg_m3 / SubstanceRegistry.get_substance(_water_index).molar_mass_kg_mol
		v.mixture.add_substance(_water_index, moles, WATER_TEMP_KELVIN)
		v.add_agitation(0.15)
		bottom_y = v.get_surface_point_world().y
	var running: bool = filling != null or running_free
	var spout: Vector3 = spout_world()
	if running_free and filling == null:
		# Nothing under it: water runs into the tray's drain (or onto the bench
		# if the tray has been moved away).
		bottom_y = global_position.y + 0.015
	_stream.visible = running
	if running:
		var target_len: float = maxf(spout.y - bottom_y, 0.01)
		_stream_len = target_len if _stream_len <= 0.0 else lerpf(_stream_len, target_len, 0.5)
		_stream.global_transform = Transform3D(Basis.from_scale(Vector3(1.0, _stream_len, 1.0)), spout - Vector3(0.0, _stream_len * 0.5, 0.0))
		AudioDirector.loop(&"tap", &"pour_loop", Vector3(spout.x, bottom_y, spout.z), 0.7, 1.15, -6.0)
		_handle_visual.rotation.y = lerpf(_handle_visual.rotation.y, 1.2, 0.2)
	else:
		_stream_len = 0.0
		_handle_visual.rotation.y = lerpf(_handle_visual.rotation.y, 0.0, 0.2)
	var text: String = "Tap · filling" if filling != null else ("Tap · running" if running_free else ("Tap · full" if v != null else "Tap · set a glass under it"))
	if _caption.text != text:
		_caption.text = text



## Short hover text.
func hover_info() -> String:
	var state: String = "running" if running_free else ("filling" if filling != null else "off")
	return "[b]Water Tap[/b]  [color=#5CE1E6]%s[/color]  [color=#B3ADD6]hold a glass under it to fill; click the handle to leave it running[/color]" % state
