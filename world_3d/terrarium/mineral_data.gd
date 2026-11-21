@tool
class_name MineralData
extends Resource
## A collectible rock, sand, mineral, gem or fossil. Everything the lab machines
## do comes from these numbers: Mohs hardness sets how hard you must hit or
## crank, crush products say what powder it grinds into (mass-conserving), and
## inclusions say what may be hiding inside.

enum Kind { ROCK, SAND, MINERAL, GEM, FOSSIL }
enum Luster { EARTHY, GLASSY, METALLIC, WAXY, PEARLY, GLOW, ADAMANTINE, SILKY, RESINOUS }
enum Shape { BLOB, CRYSTAL, CLUSTER, GEODE, BAG, SHELL, NUGGET, CUBE, OCTAHEDRON, PLATE, BLADE, RHOMB }
## How the mineral breaks along planes of weakness (drives realistic splitting).
enum Cleavage { NONE, POOR, BASAL, CUBIC, RHOMBOHEDRAL, OCTAHEDRAL, PRISMATIC }
enum Diaphaneity { TRANSPARENT, TRANSLUCENT, OPAQUE }
enum Phenomenon { NONE, ASTERISM, CHATOYANCY, PLAY_OF_COLOR, ADULARESCENCE, COLOR_CHANGE, IRIDESCENCE, FLUORESCENCE, DOUBLE_REFRACTION, AVENTURESCENCE }
const CLEAVAGE_NAMES: PackedStringArray = ["none (conchoidal fracture)", "poor", "perfect basal (splits into sheets)", "perfect cubic (breaks into cubes)",
	"perfect rhombohedral (breaks into rhombs)", "perfect octahedral (splits into octahedra)", "good prismatic (splits into blades)"]
const PHENOMENON_NAMES: PackedStringArray = ["—", "asterism (star)", "chatoyancy (cat's eye)", "play of colour", "adularescence (moon glow)",
	"colour change", "iridescence", "fluorescence", "strong double refraction", "aventurescence (glitter)"]

@export_group("Field Guide")
@export var mineral_class: String = ""
@export var crystal_system: String = ""
@export var streak_name: String = ""
@export var streak_color: Color = Color(0.9, 0.9, 0.9)
@export var cleavage: Cleavage = Cleavage.NONE
@export var fracture: String = ""
@export var diaphaneity: Diaphaneity = Diaphaneity.OPAQUE
@export var refractive_index: float = 0.0
@export var dispersion: float = 0.0
@export var phenomenon: Phenomenon = Phenomenon.NONE
## Second colour for colour-change stones (alexandrite).
@export var color_alt: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var colors_text: String = ""
@export var localities: String = ""
@export var uses: String = ""
@export var birthstone: String = ""

const RARITY_NAMES: PackedStringArray = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS: Array[Color] = [Color(0.8, 0.8, 0.8), Color(0.45, 0.85, 0.45), Color(0.4, 0.65, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.75, 0.25)]

@export var mineral_id: StringName = &""
@export var display_name: String = ""
@export var formula: String = ""
@export var kind: Kind = Kind.ROCK
@export_range(0, 4) var rarity: int = 0
@export var hardness_mohs: float = 3.0
@export var density_kg_m3: float = 2700.0
@export var typical_mass_kg: float = 0.08
@export var color: Color = Color(0.6, 0.55, 0.5)
@export var luster: Luster = Luster.EARTHY
@export var shape: Shape = Shape.BLOB
@export var emission: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var value_coins: int = 5
@export var can_facet: bool = false
@export_multiline var fun_fact: String = ""
## SubstanceData powders this grinds into (fractions by mass, normalised).
@export var crush_products: Array[Resource] = []
@export var crush_fractions: PackedFloat32Array = PackedFloat32Array()
## MineralData that may be hiding inside (chance per extraction, 0..1).
@export var inclusions: Array[Resource] = []
@export var inclusion_chances: PackedFloat32Array = PackedFloat32Array()


func rarity_name() -> String:
	return RARITY_NAMES[clampi(rarity, 0, 4)]


func rarity_color() -> Color:
	return RARITY_COLORS[clampi(rarity, 0, 4)]
