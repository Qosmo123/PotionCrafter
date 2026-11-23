class_name MortarBowl3D
extends Vessel3D
## A heavy stone mortar. It is a real vessel (pick it up, tip the powder out,
## pour vinegar on it), shaped by a revolved profile built here rather than
## by Blender, and it takes small rocks and crystals: one let go over the
## bowl drops in and sits on the bottom.
##
## Grinding (with Pestle3D) does two things, both by work done on the stone:
##   * a rock in the bowl is worn down: each joule of grinding removes
##     1 / (GRIND_J_PER_KG_PER_MOHS * Mohs hardness) kg of it, which turns into
##     its crush products (MineralData), coarse chunk -> grit -> powder;
##   * once only powder is left it gets finer: MixtureContainer.grind() raises
##     grain_surface, and solids react on that surface (dissolve faster,
##     fizz harder).
## Most grinding work ends up as heat in the contents, and pounding hard
## strikes sparks (an ignition source): grind an oxidizer with a fuel and it
## can flash. None of that is scripted per substance.

const OUTER_RADIUS_METERS: float = 0.056
const HEIGHT_METERS: float = 0.058
const CAVITY_RADIUS_METERS: float = 0.043
const CAVITY_DEPTH_METERS: float = 0.04
const MAX_ROCK_KG: float = 0.12
const MAX_ROCKS: int = 3
## Grinding energy to wear 1 kg of a Mohs-1 stone to powder (scales with Mohs).
const GRIND_J_PER_KG_PER_MOHS: float = 150.0
## Grinding energy per kg of powder for one "unit" of finer grind.
const FINE_J_PER_KG: float = 700.0
## Fraction of grinding work that heats the contents.
const FRICTION_HEAT_FRACTION: float = 0.7
## Downward pestle speed (m/s) at which a blow strikes sparks.
const SPARK_POUND_SPEED_M_S: float = 0.55

static var instance: MortarBowl3D = null

## Rocks sitting in the bowl, oldest first.
var rocks: Array[Rock3D] = []
## 0..1 how hard it is being ground right now (sound, caption).
var grinding_level: float = 0.0
var _rock_start_kg: Dictionary = {}
var _caption: WorldPill
var _sparks: GPUParticles3D
var _told: bool = false
## Seconds the top-down loupe stays up after the last grinding stroke.
var _loupe_hold_s: float = 0.0
## Blows struck with the pestle (pounding).
var pound_count: int = 0
static var _loupe: FacetLoupe = null
var _loupe_shown: bool = false


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	super._exit_tree()
	if instance == self:
		instance = null


func _ready() -> void:
	profile = _make_profile()
	show_contents_tag = true
	set_meta(&"sound_material", &"stone")
	super._ready()
	var stone: StandardMaterial3D = PropMaterials.textured("stone", Color(0.66, 0.63, 0.6), 0.25)
	var glass: MeshInstance3D = get_node_or_null(^"Glass") as MeshInstance3D
	if glass != null:
		glass.material_override = stone
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var intake: MachineIntake = MachineIntake.make(self, "mortar", Vector3(0.09, 0.26, 0.5), Vector3(0.0, HEIGHT_METERS * 0.5 + 0.13, 0.0),
		Vector3(0.0, _bottom_y() + 0.012, 0.0), _accepts_rock)
	intake.on_catch = _take_rock
	intake.catch_dx_meters = 0.06
	intake.wants = "small rocks and crystals"
	intake.drop_note = "Click to drop it in the mortar, then grind it with the pestle"
	# A stone worth selling says so before it is dropped in to be ground up.
	intake.marker_text = func(b: Node) -> String:
		var r: Rock3D = b as Rock3D
		return ("grinds to powder · worth %d ◉" % r.value()) if r != null and InventoryStore.is_find(r) and r.value() >= 15 else "grind it here"
	_caption = ClickSwitch.make_caption(self, Vector3(0.0, HEIGHT_METERS * 0.5 + 0.06, 0.06))
	_caption.busy = func() -> bool: return grinding_level > 0.05
	_build_sparks()


# --- Shape --------------------------------------------------------------------------

func _bottom_y() -> float:
	return HEIGHT_METERS * 0.5 - CAVITY_DEPTH_METERS


## Cavity: a rounded bowl from the bottom centre up to the rim (radius,
## height), ending with the lip point Vessel3D expects.
static func _cavity_points() -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var top: float = HEIGHT_METERS * 0.5
	var bottom: float = top - CAVITY_DEPTH_METERS
	var steps: int = 12
	for k: int in steps + 1:
		var a: float = float(k) / float(steps) * PI * 0.5
		# Squashed quarter-ellipse: wide flat-ish floor, steep walls near the rim.
		pts.append(Vector2(CAVITY_RADIUS_METERS * sin(a), bottom + CAVITY_DEPTH_METERS * (1.0 - cos(a)) * 0.96))
	pts.append(Vector2(CAVITY_RADIUS_METERS + 0.002, top))
	return pts


static var _shared_profile: VesselProfile = null


static func _make_profile() -> VesselProfile:
	if _shared_profile != null:
		return _shared_profile
	var p: VesselProfile = VesselProfile.new()
	p.vessel_name = "mortar"
	var cavity: PackedVector2Array = _cavity_points()
	p.inner_profile = cavity
	p.outer_radius_meters = OUTER_RADIUS_METERS
	p.height_meters = HEIGHT_METERS
	p.glass_mass_kg = 0.9
	# Stone body: foot, outer wall bulging a little, flat rim, then the cavity down to the centre.
	var top: float = HEIGHT_METERS * 0.5
	var bot: float = -HEIGHT_METERS * 0.5
	var outline: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, bot), Vector2(OUTER_RADIUS_METERS * 0.78, bot), Vector2(OUTER_RADIUS_METERS * 0.82, bot + 0.006),
		Vector2(OUTER_RADIUS_METERS * 0.9, bot + 0.014), Vector2(OUTER_RADIUS_METERS, top - 0.016),
		Vector2(OUTER_RADIUS_METERS * 0.99, top - 0.004), Vector2(OUTER_RADIUS_METERS * 0.95, top),
	])
	for k: int in range(cavity.size() - 2, -1, -1):
		outline.append(cavity[k])
	p.glass_mesh = _lathe(outline, 48)
	var liquid: PackedVector2Array = PackedVector2Array()
	for k: int in cavity.size() - 1:
		liquid.append(Vector2(cavity[k].x * 0.985, cavity[k].y + 0.0005))
	liquid.append(Vector2(0.0, cavity[cavity.size() - 2].y))
	p.liquid_mesh = _lathe(liquid, 40)
	_shared_profile = p
	return p


## Revolve a (radius, height) outline about the Y axis into a mesh.
static func _lathe(outline: PackedVector2Array, segments: int) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = outline.size()
	for i: int in n - 1:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[i + 1]
		var edge: Vector2 = b - a
		# Outward normal of this profile segment (to the right of the edge).
		var nrm2: Vector2 = Vector2(edge.y, -edge.x).normalized()
		for s: int in segments:
			var t0: float = TAU * float(s) / float(segments)
			var t1: float = TAU * float(s + 1) / float(segments)
			var c0: Vector2 = Vector2(cos(t0), sin(t0))
			var c1: Vector2 = Vector2(cos(t1), sin(t1))
			var p00: Vector3 = Vector3(a.x * c0.x, a.y, a.x * c0.y)
			var p01: Vector3 = Vector3(a.x * c1.x, a.y, a.x * c1.y)
			var p10: Vector3 = Vector3(b.x * c0.x, b.y, b.x * c0.y)
			var p11: Vector3 = Vector3(b.x * c1.x, b.y, b.x * c1.y)
			var n0: Vector3 = Vector3(nrm2.x * c0.x, nrm2.y, nrm2.x * c0.y)
			var n1: Vector3 = Vector3(nrm2.x * c1.x, nrm2.y, nrm2.x * c1.y)
			var u0: float = float(s) / float(segments) * 3.0
			var u1: float = float(s + 1) / float(segments) * 3.0
			# Clockwise seen from the side the normal faces (Godot's front faces).
			for v: Array in [[p00, n0, Vector2(u0, a.y * 8.0)], [p11, n1, Vector2(u1, b.y * 8.0)], [p10, n0, Vector2(u0, b.y * 8.0)],
					[p00, n0, Vector2(u0, a.y * 8.0)], [p01, n1, Vector2(u1, a.y * 8.0)], [p11, n1, Vector2(u1, b.y * 8.0)]]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	return st.commit()


# --- Rocks --------------------------------------------------------------------------

func _accepts_rock(b: Node) -> bool:
	var rock: Rock3D = b as Rock3D
	if rock == null or rock.mineral == null or rocks.has(rock) or rock.cut != RockMeshes.Cut.NONE:
		return false
	if rock.mineral.kind == MineralData.Kind.SAND or rock.mineral.crush_products.is_empty():
		return false
	return rock.mass_kg <= MAX_ROCK_KG and rocks.size() < MAX_ROCKS


func _take_rock(body: RigidBody3D) -> void:
	var rock: Rock3D = body as Rock3D
	if rock == null or not _accepts_rock(rock):
		return
	rock.set_meta(&"mortar_layers", Vector2i(rock.collision_layer, rock.collision_mask))
	rock.freeze = true
	rock.collision_layer = 0
	rock.collision_mask = 0
	rocks.append(rock)
	_rock_start_kg[rock.get_instance_id()] = rock.mass_kg
	player_touched = true
	AudioDirector.impact(&"stone", 0.8, global_position, 1.1)
	_seat_rocks()
	if not _told and GrimoireJournal.instance != null:
		_told = true
		GrimoireJournal.instance.toast.emit("In the mortar: %s. Hold the pestle over it and circle the mouse (or hold S) to grind it to powder" % rock.mineral.display_name, &"discovery")


## Rocks sit on the bowl floor and move with it.
func _seat_rocks() -> void:
	for k: int in range(rocks.size() - 1, -1, -1):
		if not is_instance_valid(rocks[k]) or rocks[k].is_queued_for_deletion():
			rocks.remove_at(k)
	for k: int in rocks.size():
		var a: float = TAU * float(k) / float(maxi(rocks.size(), 1))
		var off: Vector3 = Vector3(cos(a), 0.0, sin(a)) * (0.0 if rocks.size() == 1 else 0.016)
		var r: float = rocks[k].mineral.typical_mass_kg
		var lift: float = 0.004 + 0.01 * clampf(pow(rocks[k].mass_kg / maxf(r, 1e-4), 1.0 / 3.0), 0.3, 1.5)
		rocks[k].global_transform = global_transform * Transform3D(Basis(Vector3.UP, a), Vector3(off.x, _bottom_y() + lift, off.z))


func _release_rocks() -> void:
	for rock: Rock3D in rocks:
		if not is_instance_valid(rock):
			continue
		var layers: Vector2i = rock.get_meta(&"mortar_layers", Vector2i(SimConstants.LAYER_SOLID_REAGENT, SimConstants.LAYER_STATIC_BENCH))
		rock.collision_layer = layers.x
		rock.collision_mask = layers.y
		rock.freeze = false
		rock.global_position = global_transform * Vector3(0.0, HEIGHT_METERS * 0.5 + 0.02, 0.0)
		rock.linear_velocity = global_basis.y * 0.3
	rocks.clear()


func _process(delta: float) -> void:
	super._process(delta)
	_update_loupe(delta)


## A round top-down inset on the bowl while it is being ground (from the
## side view the bowl hides what is in it).
func _update_loupe(delta: float) -> void:
	_loupe_hold_s = maxf(_loupe_hold_s - delta, 0.0)
	if _loupe_hold_s <= 0.0:
		if _loupe_shown:
			_loupe_shown = false
			if _loupe != null and is_instance_valid(_loupe):
				_loupe.hide_loupe()
		return
	if _loupe == null or not is_instance_valid(_loupe):
		_loupe = FacetLoupe.new()
		get_tree().root.add_child(_loupe)
	_loupe_shown = true
	var title: String = "Mortar"
	var progress: float = (mixture.grain_surface - 1.0) / (MixtureContainer.GRAIN_SURFACE_MAX - 1.0)
	var tint: Color = CosmicTheme.PRISM_CYAN
	if not rocks.is_empty() and is_instance_valid(rocks[0]):
		var start_kg: float = float(_rock_start_kg.get(rocks[0].get_instance_id(), rocks[0].mass_kg))
		title = rocks[0].mineral.display_name
		progress = 1.0 - rocks[0].mass_kg / maxf(start_kg, 1e-6)
		tint = CosmicTheme.STARLIGHT_GOLD
	elif mixture.get_solid_mass_kg() > 1e-5:
		title = Vessel3D.contents_tag_text(mixture, 0.0)
	var detail: String = grind_stage()
	if rocks.is_empty() and detail != "":
		detail += "  ·  reacts x%.1f faster" % mixture.grain_surface
	_loupe.show_overhead(self, progress, tint, title, detail, 0.19)


## A blow with the pestle: a short, hard crushing stroke (and sparks).
func pound() -> float:
	pound_count += 1
	AudioDirector.impact(&"stone", 1.6, global_position, 0.9)
	return grind(0.012, 85.0, 1.0)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	grinding_level = maxf(grinding_level - delta * 2.5, 0.0)
	if rocks.is_empty():
		return
	# Tipped over: the rocks fall out.
	if global_basis.y.normalized().y < 0.35:
		_release_rocks()
		return
	_seat_rocks()


# --- Grinding -----------------------------------------------------------------------

## The pestle's tip moved `stroke_m` inside the bowl this tick, pressing with
## `force_n`; `pound_speed_m_s` is how fast it came down. Returns the joules
## of grinding work done.
func grind(stroke_m: float, force_n: float, pound_speed_m_s: float) -> float:
	var work_j: float = maxf(stroke_m, 0.0) * maxf(force_n, 0.0)
	if work_j <= 0.0:
		return 0.0
	_seat_rocks()
	var rock: Rock3D = rocks[0] if not rocks.is_empty() else null
	if rock != null:
		_wear(rock, work_j)
	elif mixture.get_solid_mass_kg() > 1e-5:
		mixture.grind(work_j / (mixture.get_solid_mass_kg() * FINE_J_PER_KG))
	else:
		return 0.0
	player_touched = true
	_loupe_hold_s = 1.6
	mixture.add_heat(work_j * FRICTION_HEAT_FRACTION)
	grinding_level = clampf(grinding_level + work_j * 2.0, 0.0, 1.0)
	if pound_speed_m_s > SPARK_POUND_SPEED_M_S:
		ignition_source = true
		_sparks.global_position = global_transform * Vector3(0.0, _bottom_y() + 0.01, 0.0)
		_sparks.restart()
		_sparks.emitting = true
		AudioDirector.play(&"rock_hit", global_position, -10.0, 1.3)
	add_agitation(work_j * 0.5)
	_update_caption()
	return work_j


## Wear a rock down by `work_j`; what comes off is its crush products.
func _wear(rock: Rock3D, work_j: float) -> void:
	var m: MineralData = rock.mineral
	var off_kg: float = minf(work_j / (GRIND_J_PER_KG_PER_MOHS * maxf(m.hardness_mohs, 0.5)), rock.mass_kg)
	var start_kg: float = float(_rock_start_kg.get(rock.get_instance_id(), rock.mass_kg))
	var finishing: bool = rock.mass_kg - off_kg < start_kg * 0.08
	if finishing:
		off_kg = rock.mass_kg
	_add_crush_products(m, off_kg)
	rock.mass_kg -= off_kg
	if rock._visual != null:
		rock._visual.scale = Vector3.ONE * clampf(pow(rock.mass_kg / maxf(start_kg, 1e-6), 1.0 / 3.0), 0.15, 1.0)
	if finishing:
		_finish_rock(rock)


func _add_crush_products(m: MineralData, kg: float) -> void:
	var total: float = 0.0
	for f: float in m.crush_fractions:
		total += f
	for k: int in mini(m.crush_products.size(), m.crush_fractions.size()):
		var product: SubstanceData = m.crush_products[k] as SubstanceData
		if product != null:
			mixture.add_substance(SubstanceRegistry.index_of(product), kg * m.crush_fractions[k] / maxf(total, 1e-6) / product.molar_mass_kg_mol, mixture.temperature_kelvin)


func _finish_rock(rock: Rock3D) -> void:
	var m: MineralData = rock.mineral
	AudioDirector.play(&"sand_pour", global_position, -10.0, 1.2)
	var finds: PackedStringArray = PackedStringArray()
	if not rock.exhausted:
		for k: int in mini(m.inclusions.size(), m.inclusion_chances.size()):
			if randf() < m.inclusion_chances[k] * 0.5:  # grinding destroys some finds
				var find_m: MineralData = m.inclusions[k] as MineralData
				var find: Rock3D = Rock3D.spawn(get_parent(), find_m, global_position + Vector3(0.09, 0.04, 0.05), find_m.typical_mass_kg)
				find.linear_velocity = Vector3(0.2, 0.3, 0.0)
				finds.append(find_m.display_name)
				if GrimoireJournal.instance != null:
					GrimoireJournal.instance.record_find(find_m)
	rocks.erase(rock)
	_rock_start_kg.erase(rock.get_instance_id())
	rock.queue_free()
	if GrimoireJournal.instance != null:
		var text: String = "Ground %s to powder in the mortar" % m.display_name
		if not finds.is_empty():
			text += "   Found: " + ", ".join(finds)
		GrimoireJournal.instance.toast.emit(text, &"bottle")


## Words for how far the grinding has got.
func grind_stage() -> String:
	if not rocks.is_empty():
		var rock: Rock3D = rocks[0]
		var start_kg: float = float(_rock_start_kg.get(rock.get_instance_id(), rock.mass_kg))
		return "coarse chunk" if rock.mass_kg > start_kg * 0.5 else "grit"
	if mixture.get_solid_mass_kg() < 1e-5:
		return ""
	var s: float = mixture.grain_surface
	return "coarse powder" if s < 1.6 else ("fine powder" if s < 3.0 else "superfine powder")


func _update_caption() -> void:
	var stage: String = grind_stage()
	var text: String = "Mortar" + ("\n" + stage if stage != "" else "")
	if not rocks.is_empty():
		text = "%s · %s" % [rocks[0].mineral.display_name, stage]
	elif stage != "":
		text = "%s · %d%% fine" % [stage, int(round((mixture.grain_surface - 1.0) / (MixtureContainer.GRAIN_SURFACE_MAX - 1.0) * 100.0))]
	if _caption.text != text:
		_caption.text = text


func _build_sparks() -> void:
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.0, -6.0, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(1.0, 0.75, 0.35)
	_sparks = GPUParticles3D.new()
	_sparks.top_level = true
	_sparks.one_shot = true
	_sparks.explosiveness = 0.9
	_sparks.amount = 14
	_sparks.lifetime = 0.35
	_sparks.process_material = pm
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.003, 0.003)
	quad.material = VesselEffects.billboard_material(true, 4.0, Color(1.0, 0.75, 0.35))
	_sparks.draw_pass_1 = quad
	_sparks.emitting = false
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)


## Short hover text.
func hover_info() -> String:
	var stage: String = grind_stage()
	return "[b]Mortar[/b]  [color=#B3ADD6]drop a small rock or crystal in and grind it with the pestle; keep grinding powder to make it finer (it reacts faster). Pick it up to tip the powder out%s[/color]" % ((" · now: " + stage) if stage != "" else "")
