@tool
class_name SubstanceData
extends Resource
## Declarative description of one substance as continuous physical + arcane
## property vectors. No recipe logic lives here: every behaviour must emerge
## from these numbers inside the solvers.

@export var substance_id: StringName = &""
@export var display_name: String = ""
## Display formula, e.g. "H₂O" (used in reaction equations and labels).
@export var chemical_formula: String = ""

@export_group("Physical")
@export var molar_mass_kg_mol: float = 0.018
@export var density_kg_m3: float = 1000.0
## One heat capacity for all phases (simplification).
@export var specific_heat_j_kg_k: float = 4184.0
@export var melting_point_kelvin: float = 273.15
@export var boiling_point_kelvin: float = 373.15
@export var latent_heat_fusion_j_kg: float = 334000.0
@export var latent_heat_vaporization_j_kg: float = 2257000.0
@export var viscosity_pas: float = 0.001
@export var pka_acidity: float = 15.7
@export var redox_potential_volts: float = 0.0
@export_range(0.0, 1.0) var flammability: float = 0.0
@export var surface_tension_n_m: float = 0.072
@export var base_albedo_rgba: Color = Color(0.6, 0.8, 1.0, 0.3)
@export_range(0.0, 1.0) var turbidity: float = 0.05
@export var ior: float = 1.333

@export_group("Arcane")
@export var thaumic_density_thaums_mol: float = 0.0
@export_range(-1.0, 1.0) var polarity_charge: float = 0.0
@export var entropy_flux: float = 0.0
@export var vitality_resonance: float = 0.0
@export var chronal_dilation: float = 0.0
## Multiplier on gravity for this substance's mass: 1 = normal, 0 = weightless,
## negative = buoyant against gravity.
@export_range(-2.0, 2.0) var gravity_coupling: float = 1.0
@export var transmutation_valence: float = 0.0
## Linear HDR emission colour (values above 1 bloom).
@export var emissive_aura_hdr: Color = Color(0.0, 0.0, 0.0, 0.0)

@export_group("Reactivity")
## What this substance becomes when a reaction channel consumes it. Each
## substance owns its own products; there are no pair recipes. Mass is split by
## the fractions below (normalised), so every reaction conserves mass exactly.
@export var reaction_products: Array[Resource] = []
@export var reaction_product_mass_fractions: PackedFloat32Array = PackedFloat32Array()
## Extra enthalpy (J/mol) when this substance is protonated/deprotonated
## (positive = endothermic, like bicarbonate fizzing cold).
@export var proton_transfer_enthalpy_j_mol: float = 0.0
## Polymer chains that crosslink into a gel (PVA, gelatin, sap).
@export_range(0.0, 1.0) var crosslink_sites: float = 0.0
## Crosslinking agent (borate ions, arcane binders).
@export_range(0.0, 1.0) var crosslinker_strength: float = 0.0
## Surfactant strength: foams when agitated.
@export_range(0.0, 1.0) var foaming: float = 0.0
## Foam/bubble film stabiliser (glycerin-like).
@export_range(0.0, 1.0) var foam_stability: float = 0.0
## pH indicator dye: colour follows the mixture's acidity.
@export_range(0.0, 1.0) var indicator_strength: float = 0.0
@export var indicator_acid_color: Color = Color(0.9, 0.15, 0.3, 0.8)
@export var indicator_base_color: Color = Color(0.2, 0.75, 0.35, 0.8)

@export_group("Phases & Layers")
## 0 = aqueous, 1 = oily, 2 = liquid metal. Different groups do not mix: they
## stratify by density unless agitated or emulsified by a surfactant.
@export_range(0, 2) var miscibility_group: int = 0

@export_group("Precipitation")
## +1 dissolved metal cation, -1 precipitating anion. Opposite charges meet and
## both are consumed into their products (the cation's products hold the solid).
@export_range(-1.0, 1.0) var precipitant_charge: float = 0.0

@export_group("Decomposition & Catalysis")
## First-order self-decomposition rate at 20 °C (per second) into reaction_products.
@export var decomposition_rate_per_s: float = 0.0
@export var decomposition_enthalpy_j_mol: float = 0.0
## Speeds up any decomposition in the same mixture (not consumed).
@export_range(0.0, 1.0) var catalyst_strength: float = 0.0

@export_group("Combustion")
## Heat of combustion (J/kg, negative = releases heat). Burns into its
## reaction_products (CO₂ + H₂O) above the ignition temperature from flammability.
@export var combustion_enthalpy_j_kg: float = 0.0

@export_group("Fun Senses")
## Sparkly flakes that glint in the liquid (mica, pyrite, stardust).
@export_range(0.0, 1.0) var glitter: float = 0.0
## Smell strength when released as gas or present in the mix (rotten eggs = 1).
@export_range(0.0, 1.0) var odor: float = 0.0
## Responds to magnets (iron sands): magnetic stirrers spin it into a tornado.
@export_range(0.0, 1.0) var magnetic: float = 0.0

@export_group("Redox")
## Electron-grabbing power (permanganate, peroxide, rust in thermite, Cu²⁺ vs iron).
@export_range(0.0, 1.0) var oxidizer_strength: float = 0.0
## Electron-giving power (glycerin, glucose, iron, zinc, aluminium, luminol).
@export_range(0.0, 1.0) var reducer_strength: float = 0.0
## Heat per mol when this oxidizer reacts (negative = releases heat).
@export var redox_enthalpy_j_mol: float = 0.0
## Below this temperature the redox pair is frozen unless something is burning.
@export var redox_activation_kelvin: float = 0.0
@export var redox_products: Array[Resource] = []
@export var redox_fractions: PackedFloat32Array = PackedFloat32Array()

@export_group("Complexation")
## Ligand that wraps around a complexable ion (ammonia, starch).
@export_range(0.0, 1.0) var ligand_strength: float = 0.0
## Ion/molecule that forms coloured complexes with any ligand (Cu²⁺, iodine).
@export_range(0.0, 1.0) var complexable: float = 0.0
@export var complex_products: Array[Resource] = []
@export var complex_fractions: PackedFloat32Array = PackedFloat32Array()

@export_group("Dissolving & Crystals")
## Solid that dissolves in water into its reaction_products, with this heat per mol
## (positive = cold pack, negative = hot pack).
@export var dissolves_in_water: bool = false
@export var dissolution_enthalpy_j_mol: float = 0.0
## Supersaturated solution: crystallises into reaction_products as soon as any
## solid seed is present ("hot ice"), releasing this heat per mol.
@export var crystallizes_on_seed: bool = false
@export var crystallization_enthalpy_j_mol: float = 0.0
## Non-Newtonian thickening: viscosity soars when stirred hard (oobleck).
@export_range(0.0, 1.0) var shear_thickening: float = 0.0
## Optional explicit flash point (K); 0 = estimate from boiling point.
@export var flash_point_kelvin: float = 0.0

@export_group("Flame & Safety")
## Colour this substance gives a flame (flame test): Sr red, Cu green, Na yellow.
@export var flame_color: Color = Color(1.0, 0.55, 0.15, 1.0)
@export_range(0.0, 1.0) var flame_strength: float = 0.0
## 0 harmless .. 1 deadly (WHMIS acute toxicity).
@export_range(0.0, 1.0) var toxicity: float = 0.0
## Long-term health hazard (carcinogen, sensitiser).
@export_range(0.0, 1.0) var health_hazard: float = 0.0
@export_range(0.0, 1.0) var environmental_hazard: float = 0.0

@export_group("Fun Effects")
@export_range(0.0, 1.0) var spookiness: float = 0.0
@export_range(0.0, 1.0) var electric_charge: float = 0.0
@export_range(0.0, 1.0) var rainbow: float = 0.0

@export_group("Catalogue")
## Satchel shelf, e.g. "Acids", "Spooky", "Movie Magic". Empty = not stocked.
@export var shelf: String = ""
@export var cas_number: String = ""
@export_multiline var description: String = ""

@export_group("Thermochromism")
@export_range(0.0, 1.0) var thermochromic_strength: float = 0.0
@export var thermo_cold_color: Color = Color(0.2, 0.35, 0.95, 0.8)
@export var thermo_hot_color: Color = Color(0.95, 0.15, 0.2, 0.8)
@export var thermo_cold_kelvin: float = 288.0
@export var thermo_hot_kelvin: float = 333.0
