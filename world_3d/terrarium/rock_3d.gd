class_name Rock3D
extends RigidBody3D
## A collectible rock, sand bag, mineral, gem or fossil you can pick up.
## Hammer it (Space while holding the hammer) to crack it open and reveal its
## inclusions; feed it to the crusher for powder; polish and facet gems at the
## lapidary machines. Integrity scales with Mohs hardness, so quartz-hard
## rocks take real effort and salt crumbles at a tap.

const MINERAL_DIR: String = "res://content/minerals/"
const CRACK_SHADER: Shader = preload("res://visuals_3d/shaders/rock_cracks.gdshader")
## Rarity from which a find gets the full shimmer reveal (2 = rare).
const REVEAL_RARITY: int = 2

static var _registry: Dictionary = {}

@export var mineral: MineralData
@export var mass_kg: float = 0.0
@export_range(0.0, 1.0) var polish: float = 0.0
@export var cut: int = RockMeshes.Cut.NONE
@export_range(0.0, 1.0) var cut_quality: float = 0.0
## Fragments of a rock already searched hold no more surprises.
@export var exhausted: bool = false
## >= 0: this piece is a cleavage fragment (MineralData.Cleavage) and is drawn
## as the shape the mineral really breaks into (cubes, rhombs, sheets...).
@export var fragment_cleavage: int = -1

var integrity: float = 1.0
var integrity_max: float = 1.0
var _crack_mat: ShaderMaterial = null
var _flash: float = 0.0
var _weak_hits: int = 0
var _visual: MeshInstance3D
var _collider: CollisionShape3D
var _seed: int = 0


static func registry() -> Dictionary:
	if _registry.is_empty():
		for file_name: String in DirAccess.get_files_at(MINERAL_DIR):
			var path: String = file_name.trim_suffix(".remap")
			if path.ends_with(".tres"):
				var m: MineralData = load(MINERAL_DIR + path) as MineralData
				if m != null:
					_registry[String(m.mineral_id)] = m
	return _registry


static func get_mineral(id: String) -> MineralData:
	return registry().get(id, null)


func _ready() -> void:
	collision_layer = SimConstants.LAYER_SOLID_REAGENT
	collision_mask = SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_SOLID_REAGENT | SimConstants.LAYER_RIGID_VESSEL | SimConstants.LAYER_TACTILE_TOOL
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	if mineral == null:
		return
	if mass_kg <= 0.0:
		mass_kg = mineral.typical_mass_kg
	mass = mass_kg
	_seed = get_instance_id() % 997
	var physics: PhysicsMaterial = PhysicsMaterial.new()
	physics.friction = 0.9
	physics.rough = true
	physics.bounce = 0.05
	physics_material_override = physics
	integrity = mineral.hardness_mohs * mineral.hardness_mohs * 0.6 * clampf(mass_kg / 0.1, 0.3, 2.0)
	integrity_max = integrity
	set_process(false)
	_visual = MeshInstance3D.new()
	add_child(_visual)
	_collider = CollisionShape3D.new()
	add_child(_collider)
	_rebuild()
	add_to_group(&"collectibles")


func radius_meters() -> float:
	var density: float = mineral.density_kg_m3 if mineral.kind != MineralData.Kind.SAND else 1600.0
	return clampf(pow(3.0 * mass_kg / (4.0 * PI * density), 1.0 / 3.0) * 1.15, 0.006, 0.08)


func _rebuild() -> void:
	var r: float = radius_meters()
	var mesh: Mesh = RockMeshes.for_mineral(mineral, r, _seed, cut, fragment_cleavage)
	_visual.mesh = mesh
	_visual.material_override = RockMeshes.material_for(mineral, polish, cut)
	_visual.material_overlay = _crack_mat
	_collider.shape = mesh.create_convex_shape(true, true)


func set_polish(value: float) -> void:
	polish = clampf(value, 0.0, 1.0)
	if _visual != null:
		_visual.material_override = RockMeshes.material_for(mineral, polish, cut)


func apply_cut(new_cut: int, quality: float) -> void:
	cut = new_cut
	cut_quality = clampf(quality, 0.0, 1.0)
	if _visual != null:
		_rebuild()


## Coins this piece is worth: base value scaled by size, polish and cut.
func value() -> int:
	var size_factor: float = clampf(mass_kg / maxf(mineral.typical_mass_kg, 1e-4), 0.2, 3.0)
	var finish: float = (1.0 + polish * 1.5) * (1.0 + cut_quality * 3.0 if cut != RockMeshes.Cut.NONE else 1.0)
	return int(round(float(mineral.value_coins) * size_factor * finish))


func describe_name() -> String:
	var prefix: String = ""
	if cut != RockMeshes.Cut.NONE:
		prefix = "%s-cut " % RockMeshes.CUT_NAMES[cut]
	elif polish > 0.85:
		prefix = "Polished "
	elif polish > 0.3:
		prefix = "Smoothed "
	elif fragment_cleavage >= 0:
		prefix = "Cleaved "
	elif mineral.kind == MineralData.Kind.GEM:
		prefix = "Rough "
	return prefix + mineral.display_name


## Hammer impact. Energy in joules; harder minerals shrug off weak blows.
func strike(energy_joules: float) -> void:
	if mineral.kind == MineralData.Kind.SAND or cut != RockMeshes.Cut.NONE:
		return
	# Perfect cleavage gives the blow a plane to run along; tough, cleavage-free
	# stones (jade, flint) soak it up.
	var effective: float = energy_joules * 10.0 / maxf(mineral.hardness_mohs, 1.0) * cleavage_ease(mineral.cleavage)
	integrity -= effective
	AudioHaptics.impact(2.0)
	_show_hit(effective / maxf(integrity_max, 1e-6))
	if integrity <= 0.0:
		crack()


## Assisted blow that removes a fixed share of the rock's strength (easy
## mode: every rock cracks within a few hits, harder ones in more).
func strike_fraction(fraction: float) -> void:
	if mineral == null or mineral.kind == MineralData.Kind.SAND or cut != RockMeshes.Cut.NONE or fraction <= 0.0:
		return
	integrity -= fraction * integrity_max
	AudioHaptics.impact(2.0)
	_show_hit(fraction)
	if integrity <= 0.0:
		crack()


## 0 = pristine, 1 = about to split.
func damage() -> float:
	return clampf(1.0 - integrity / maxf(integrity_max, 1e-6), 0.0, 1.0)


## Colour of the light peeking through the cracks: the rarest thing hidden
## inside (a hint, not a promise), or warm starlight.
func crack_glow_color() -> Color:
	var best: MineralData = null
	if not exhausted:
		for inc: Resource in mineral.inclusions:
			var m: MineralData = inc as MineralData
			if m != null and (best == null or m.rarity > best.rarity):
				best = m
	if best != null and best.rarity >= 1:
		return best.color.lerp(Color.WHITE, 0.25)
	return Color(1.0, 0.72, 0.35)


## Presentation of a blow: glowing fractures, dust, sparks and a screen nudge.
func _show_hit(fraction: float) -> void:
	if _crack_mat == null:
		_crack_mat = ShaderMaterial.new()
		_crack_mat.shader = CRACK_SHADER
		_crack_mat.set_shader_parameter(&"glow_color", crack_glow_color())
		_crack_mat.set_shader_parameter(&"cell_scale", 3.2 / radius_meters())
		_crack_mat.set_shader_parameter(&"seed", float(_seed))
		if _visual != null:
			_visual.material_overlay = _crack_mat
	_crack_mat.set_shader_parameter(&"damage", damage())
	_flash = clampf(0.35 + fraction * 2.0, 0.0, 1.0)
	set_process(true)
	var fx: ImpactFx3D = ImpactFx3D.get_pool(self)
	if fx != null:
		fx.hit(global_position + Vector3(0.0, radius_meters(), 0.0), mineral.color, crack_glow_color(), clampf(fraction * 3.0, 0.0, 1.0))
	if LabCamera3D.instance != null:
		LabCamera3D.instance.shake(clampf(0.12 + fraction * 0.8, 0.0, 0.45))
	if fraction < 0.04:
		_weak_hits += 1
		if _weak_hits == 3 and GrimoireJournal.instance != null:
			GrimoireJournal.instance.toast.emit("%s is tough (Mohs %.1f). Hold Space to wind up a bigger swing!" % [mineral.display_name, mineral.hardness_mohs], &"warning")


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 3.0, 0.0)
	if _crack_mat != null:
		_crack_mat.set_shader_parameter(&"flash", _flash)
	if _flash <= 0.0:
		set_process(false)


## Split open: roll inclusions into new finds, leave a couple of smaller fragments.
func crack() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var parent: Node = get_parent()
	var finds: PackedStringArray = PackedStringArray()
	if not exhausted:
		for k: int in mini(mineral.inclusions.size(), mineral.inclusion_chances.size()):
			if rng.randf() < mineral.inclusion_chances[k]:
				var find_mineral: MineralData = mineral.inclusions[k] as MineralData
				var find: Rock3D = spawn(parent, find_mineral, global_position + Vector3(rng.randf_range(-0.03, 0.03), 0.04, rng.randf_range(-0.03, 0.03)),
					find_mineral.typical_mass_kg * rng.randf_range(0.6, 1.4))
				find.linear_velocity = Vector3(rng.randf_range(-0.3, 0.3), 0.8, rng.randf_range(-0.3, 0.3))
				finds.append(find_mineral.display_name)
				if GrimoireJournal.instance != null:
					GrimoireJournal.instance.record_find(find_mineral)
				if find_mineral.rarity >= REVEAL_RARITY:
					_reveal(find, find_mineral)
	var pieces: int = fragment_count(mineral.cleavage, rng)
	var breaks_true: bool = mineral.kind != MineralData.Kind.ROCK and mineral.kind != MineralData.Kind.FOSSIL
	if mass_kg > 0.004:
		# 90% of the mass survives as fragments; the rest is dust and chips.
		for k: int in pieces:
			var a: float = TAU * float(k) / float(pieces) + rng.randf_range(-0.3, 0.3)
			var offset: Vector3 = Vector3(cos(a), 0.0, sin(a)) * radius_meters() * 0.8 + Vector3(0.0, 0.02, 0.0)
			var frag: Rock3D = Rock3D.new()
			frag.mineral = mineral
			frag.mass_kg = mass_kg * 0.9 / float(pieces)
			frag.exhausted = true
			frag.polish = polish * 0.3
			frag.fragment_cleavage = int(mineral.cleavage) if breaks_true else -1
			frag.name = "%s_frag_%d" % [String(mineral.mineral_id), randi() % 100000]
			parent.add_child(frag)
			frag.global_position = global_position + offset
			frag.linear_velocity = Vector3(cos(a) * 0.4, 0.5, sin(a) * 0.4)
			frag.angular_velocity = Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))
	var fx: ImpactFx3D = ImpactFx3D.get_pool(self)
	if fx != null:
		fx.hit(global_position, mineral.color, crack_glow_color(), 1.0)
	if LabCamera3D.instance != null:
		LabCamera3D.instance.shake(0.55)
	if GrimoireJournal.instance != null:
		var text: String = "Cracked %s!" % mineral.display_name
		if breaks_true:
			text = break_description(mineral, pieces)
		text += ("  Found: " + ", ".join(finds)) if not finds.is_empty() else ("  Nothing inside this time." if not exhausted and not mineral.inclusions.is_empty() else "")
		GrimoireJournal.instance.toast.emit(text, &"discovery" if not finds.is_empty() else &"info")
	queue_free()


## Shimmer reveal for a rare find: pillar of light, sparkle burst, banner.
static func _reveal(find: Rock3D, m: MineralData) -> void:
	var color: Color = CosmicTheme.rarity_aura(m.rarity)
	var fx: ImpactFx3D = ImpactFx3D.get_pool(find)
	if fx != null:
		fx.reveal(find.global_position - Vector3(0.0, 0.02, 0.0), color)
	if LabCamera3D.instance != null:
		LabCamera3D.instance.shake(0.8)
	if HudOverlay.instance != null:
		HudOverlay.instance.show_reveal(m)


static func cleavage_ease(c: int) -> float:
	match c:
		MineralData.Cleavage.CUBIC, MineralData.Cleavage.RHOMBOHEDRAL, MineralData.Cleavage.BASAL: return 2.0
		MineralData.Cleavage.OCTAHEDRAL, MineralData.Cleavage.PRISMATIC: return 1.6
		MineralData.Cleavage.POOR: return 1.0
	return 0.8


static func fragment_count(c: int, rng: RandomNumberGenerator) -> int:
	match c:
		MineralData.Cleavage.CUBIC, MineralData.Cleavage.BASAL: return rng.randi_range(3, 4)
		MineralData.Cleavage.RHOMBOHEDRAL, MineralData.Cleavage.PRISMATIC: return 3
		MineralData.Cleavage.OCTAHEDRAL: return rng.randi_range(2, 3)
	return rng.randi_range(2, 3)


## What a geologist would say about the break.
static func break_description(m: MineralData, pieces: int) -> String:
	match m.cleavage:
		MineralData.Cleavage.CUBIC:
			return "%s split along three perfect cleavages at right angles into %d little cubes!" % [m.display_name, pieces]
		MineralData.Cleavage.RHOMBOHEDRAL:
			return "%s broke into %d slanted rhombs: perfect rhombohedral cleavage, like calcite." % [m.display_name, pieces]
		MineralData.Cleavage.OCTAHEDRAL:
			return "%s cleaved into %d octahedra along four perfect planes. Diamond cutters use this trick!" % [m.display_name, pieces]
		MineralData.Cleavage.BASAL:
			return "%s peeled into %d flat sheets: one perfect basal cleavage plane." % [m.display_name, pieces]
		MineralData.Cleavage.PRISMATIC:
			return "%s split lengthwise into %d blades along its prismatic cleavage." % [m.display_name, pieces]
		MineralData.Cleavage.POOR:
			return "%s broke unevenly into %d chunks (poor cleavage, %s fracture)." % [m.display_name, pieces, m.fracture if m.fracture != "" else "uneven"]
	return "%s has no cleavage: it shattered into %d pieces with curved, %s fracture surfaces." % [m.display_name, pieces, m.fracture if m.fracture != "" else "conchoidal"]


static func spawn(parent: Node, m: MineralData, at: Vector3, mass_value: float) -> Rock3D:
	var rock: Rock3D = Rock3D.new()
	rock.mineral = m
	rock.mass_kg = mass_value
	rock.name = "%s_%d" % [String(m.mineral_id), randi() % 100000]
	parent.add_child(rock)
	rock.global_position = at
	return rock
