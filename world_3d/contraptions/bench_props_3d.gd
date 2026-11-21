class_name BenchProps3D
extends Node3D
## Clickable props on the front of the potion bench, so nothing needs a
## keyboard shortcut (the keys still work):
##   Cork & wax dish   set a filled vessel in it and it is corked, sealed
##                     and labelled (same as B).
##   Chalk and sponge  click the chalk to pick it up and draw sigils (C);
##                     click the damp sponge to wipe them away (X).
##   Magnifying lens   a tool: hold it over a vessel for a quick reading.

const SETTLE_SECONDS: float = 0.5

@export var lens_offset: Vector3 = Vector3(0.16, 0.012, 0.0)

var _dish: SupportStand3D
var _chalk_button: StaticBody3D
var _sponge_button: StaticBody3D
var _settle_s: float = 0.0
var _settle_vessel: Vessel3D = null
var _caption: WorldPill
var _tick: int = 0


func _ready() -> void:
	var wood: StandardMaterial3D = PropMaterials.textured("wood", Color(0.36, 0.22, 0.12), 0.3)
	var brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.88, 0.66, 0.3), 0.1, 0.9)
	var cork: StandardMaterial3D = StandardMaterial3D.new()
	cork.albedo_color = Color(0.66, 0.48, 0.3)
	cork.roughness = 0.95
	var wax: StandardMaterial3D = StandardMaterial3D.new()
	wax.albedo_color = Color(0.6, 0.08, 0.1)
	wax.roughness = 0.4
	# --- Cork & wax dish: a shallow turned bowl with corks and a wax stick.
	var bowl: MeshInstance3D = MeshInstance3D.new()
	bowl.mesh = MeshUtil.lathe(PackedVector2Array([Vector2(0.0, 0.004), Vector2(0.05, 0.004), Vector2(0.058, 0.016), Vector2(0.062, 0.022),
		Vector2(0.056, 0.022), Vector2(0.05, 0.01), Vector2(0.0, 0.01)]), 40)
	bowl.material_override = wood
	add_child(bowl)
	_solid(Vector3(0.11, 0.008, 0.11), Vector3(0.0, 0.006, 0.0))
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0 + 0.4
		var c: CylinderMesh = CylinderMesh.new()
		c.top_radius = 0.0075
		c.bottom_radius = 0.0065
		c.height = 0.014
		c.material = cork
		var cm: MeshInstance3D = MeshInstance3D.new()
		cm.mesh = c
		cm.position = Vector3(cos(a) * 0.04, 0.016, sin(a) * 0.04)
		cm.rotation = Vector3(1.4, a, 0.0)
		add_child(cm)
	var stick: CylinderMesh = CylinderMesh.new()
	stick.top_radius = 0.004
	stick.bottom_radius = 0.004
	stick.height = 0.06
	stick.material = wax
	var sm: MeshInstance3D = MeshInstance3D.new()
	sm.mesh = stick
	sm.position = Vector3(0.0, 0.02, 0.05)
	sm.rotation = Vector3(0.0, 0.0, PI * 0.5)
	add_child(sm)
	_dish = SupportStand3D.new()
	_dish.kind = SupportStand3D.Kind.PAD
	_dish.pad_radius_meters = 0.04
	_dish.seat_name = "cork & wax dish"
	_dish.position = Vector3(0.0, 0.011, 0.0)
	add_child(_dish)
	_caption = WorldPill.make(self, Vector3(0.0, 0.1, 0.04), 24, 0.0004)
	_caption.text = "Cork & wax dish"
	# --- Slate ledge with a chalk stick and a damp sponge.
	var ledge_x: float = -0.14
	var slate: StandardMaterial3D = StandardMaterial3D.new()
	slate.albedo_color = Color(0.14, 0.15, 0.16)
	slate.roughness = 0.85
	_visual_box(Vector3(0.1, 0.008, 0.05), Vector3(ledge_x, 0.004, 0.0), slate)
	var chalk_mat: StandardMaterial3D = StandardMaterial3D.new()
	chalk_mat.albedo_color = Color(0.95, 0.94, 0.9)
	chalk_mat.emission_enabled = true
	chalk_mat.emission = Color(0.5, 0.6, 1.0)
	chalk_mat.emission_energy_multiplier = 0.35
	var chalk: CylinderMesh = CylinderMesh.new()
	chalk.top_radius = 0.005
	chalk.bottom_radius = 0.005
	chalk.height = 0.05
	chalk.material = chalk_mat
	var chalk_mi: MeshInstance3D = MeshInstance3D.new()
	chalk_mi.mesh = chalk
	chalk_mi.position = Vector3(ledge_x - 0.022, 0.013, 0.0)
	chalk_mi.rotation = Vector3(0.0, 0.3, PI * 0.5)
	add_child(chalk_mi)
	_chalk_button = ClickSwitch.make_button(self, Vector3(0.05, 0.03, 0.04), Vector3(ledge_x - 0.022, 0.015, 0.0))
	var sponge_mat: StandardMaterial3D = StandardMaterial3D.new()
	sponge_mat.albedo_color = Color(0.82, 0.72, 0.38)
	sponge_mat.roughness = 1.0
	_visual_box(Vector3(0.036, 0.02, 0.03), Vector3(ledge_x + 0.028, 0.018, 0.0), sponge_mat)
	_sponge_button = ClickSwitch.make_button(self, Vector3(0.04, 0.03, 0.04), Vector3(ledge_x + 0.028, 0.018, 0.0))
	# --- The magnifying lens lies beside them.
	_place_lens.call_deferred()


func _place_lens() -> void:
	var lens: MagnifyingLens3D = MagnifyingLens3D.new()
	lens.name = "MagnifyingLens"
	get_parent().add_child(lens)
	lens.global_position = global_transform * lens_offset


func _solid(size: Vector3, center: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = SimConstants.LAYER_STATIC_BENCH
	body.collision_mask = 0
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = center
	add_child(body)


func _visual_box(size: Vector3, center: Vector3, mat: Material) -> void:
	var m: BoxMesh = BoxMesh.new()
	m.size = size
	m.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = m
	mi.position = center
	add_child(mi)


func _unhandled_input(event: InputEvent) -> void:
	var hit: Object = ClickSwitch.clicked(self, event, [_chalk_button, _sponge_button])
	if hit == null:
		return
	var chalk: ChalkDrawing3D = ChalkDrawing3D.instance
	if chalk != null:
		if hit == _chalk_button:
			chalk.toggle_chalk()
		else:
			chalk.wipe()
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_tick += 1
	if _tick % 6 != 0:
		return
	var seat: Vector3 = _dish.global_position
	var on_dish: Vessel3D = null
	for v: Vessel3D in Vessel3D.all_vessels:
		if v == TactileGrabber3D.current_held or not v.is_inside_tree() or v.mixture == null:
			continue
		var p: Vector3 = v.global_position
		if Vector2(p.x - seat.x, p.z - seat.z).length() < 0.04 and p.y > seat.y - 0.01 and p.y < seat.y + 0.2:
			on_dish = v
			break
	if on_dish != _settle_vessel:
		_settle_vessel = on_dish
		_settle_s = 0.0
	if on_dish == null or on_dish.sealed or on_dish.mixture.get_liquid_volume_m3() < 2e-6:
		return
	_settle_s += delta * 6.0
	if _settle_s < SETTLE_SECONDS or on_dish.linear_velocity.length() > 0.05:
		return
	if HudOverlay.instance != null:
		HudOverlay.instance.bottle(on_dish)
	_settle_s = -1e9  # once per visit


## Short hover text.
func hover_info() -> String:
	return "[b]Cork & wax dish[/b]  [color=#B3ADD6]set a filled vessel in it to cork, seal and label it · chalk: draw sigils · sponge: wipe them[/color]"
