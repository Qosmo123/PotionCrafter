"""Mineral powders produced by realistic crushing (streak-coloured, with the
chemistry of the parent mineral). Loaded by gen_substances.py."""

SOLID = dict(specific_heat_j_kg_k=800, melting_point_kelvin=1500, boiling_point_kelvin=3000, latent_heat_fusion_j_kg=200000,
             latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0)


def powder(name, formula, M, rho, color, desc, **kw):
    d = dict(SOLID)
    d.update(name=name, formula=formula, molar_mass_kg_mol=M, density_kg_m3=rho, base_albedo_rgba=color + (1.0,), description=desc)
    d.update(kw)
    return d


SULFIDE_ACID = {"rotten_egg_gas": 0.25, "dissolved_salts": 0.75}
CARBONATE_ACID = {"carbon_dioxide": 0.4, "water": 0.15, "dissolved_salts": 0.45}

SUBSTANCES = {
    "feldspar_powder": powder("Feldspar Powder", "KAlSi₃O₈", 0.278, 2560, (0.95, 0.88, 0.82), "Ground feldspar: the main ingredient of porcelain and most of the Earth's crust."),
    "mica_flakes": powder("Mica Flakes", "KAl₂(AlSi₃O₁₀)(OH)₂", 0.398, 2820, (0.85, 0.82, 0.7), "Paper-thin glittering sheets split from mica. Nature's glitter.", glitter=0.9),
    "talc_powder": powder("Talc Powder", "Mg₃Si₄O₁₀(OH)₂", 0.379, 2750, (0.97, 0.97, 0.95), "The softest mineral, ground to a silky, slippery powder.", shear_thickening=0.2),
    "gypsum_powder": powder("Gypsum (Plaster)", "CaSO₄·2H₂O", 0.172, 2320, (0.98, 0.97, 0.95), "Plaster of Paris: soft gypsum ground fine.", crosslinker_strength=0.2),
    "graphite_powder": powder("Graphite Powder", "C (graphite)", 0.012, 2230, (0.15, 0.15, 0.16), "Pencil 'lead'. Slippery, black and conducts electricity.", electric_charge=0.3, flammability=0.1, combustion_enthalpy_j_kg=-32.8e6, products={"carbon_dioxide": 1.0}),
    "galena_powder": powder("Galena Powder", "PbS", 0.239, 7600, (0.3, 0.3, 0.32), "Heavy lead-grey powder. Toxic! Releases rotten-egg gas in acid.", pka_acidity=9.5, toxicity=0.8, health_hazard=0.8, environmental_hazard=0.8, products=SULFIDE_ACID),
    "sphalerite_powder": powder("Sphalerite Powder", "ZnS", 0.097, 4050, (0.75, 0.6, 0.35), "Zinc ore powder with a pale brown streak. Stinks in acid.", pka_acidity=9.5, products=SULFIDE_ACID),
    "cinnabar_powder": powder("Vermilion", "HgS", 0.233, 8100, (0.85, 0.15, 0.1), "The ancient red pigment vermilion. Contains mercury: very toxic! Roasted over a flame it gives up quicksilver.", toxicity=0.9, health_hazard=0.9, environmental_hazard=0.9,
                              decomposition_rate_per_s=0.00003, decomposition_enthalpy_j_mol=20000, products={"quicksilver": 0.86, "sulfur_dioxide": 0.14}),  # roasting: slow cold, quick hot
    "chalcopyrite_powder": powder("Chalcopyrite Dust", "CuFeS₂", 0.183, 4200, (0.25, 0.3, 0.15), "Greenish-black copper-iron sulfide dust.", pka_acidity=9.5, glitter=0.3, products={"rotten_egg_gas": 0.2, "copper_sulfate": 0.3, "dissolved_salts": 0.5}),
    "stibnite_powder": powder("Stibnite Powder", "Sb₂S₃", 0.34, 4630, (0.3, 0.3, 0.33), "Antimony sulfide: once used as ancient eyeliner (kohl). Toxic.", pka_acidity=9.5, toxicity=0.6, products=SULFIDE_ACID),
    "rhodochrosite_powder": powder("Rhodochrosite Powder", "MnCO₃", 0.115, 3690, (0.95, 0.65, 0.7), "Rosy pink manganese carbonate that fizzes in warm acid.", pka_acidity=10.0, proton_transfer_enthalpy_j_mol=12000, products=CARBONATE_ACID),
    "siderite_powder": powder("Siderite Powder", "FeCO₃", 0.116, 3960, (0.75, 0.65, 0.5), "Iron carbonate powder.", pka_acidity=9.8, proton_transfer_enthalpy_j_mol=12000, products=CARBONATE_ACID),
    "corundum_grit": powder("Corundum Grit", "Al₂O₃", 0.102, 4000, (0.95, 0.95, 0.95), "Hardness 9 grit: the abrasive on sandpaper and nail files.", melting_point_kelvin=2345),
    "titania_powder": powder("Titanium White", "TiO₂", 0.0799, 4230, (0.99, 0.99, 0.99), "Brilliant white pigment from rutile.", melting_point_kelvin=2116),
    "metal_oxide_dust": powder("Metal Oxide Dust", "MₓOᵧ", 0.15, 5000, (0.4, 0.35, 0.3), "Heavy dark oxide powder (tin, chromium, manganese oxides).", melting_point_kelvin=1900),
    "apatite_powder": powder("Apatite Powder", "Ca₅(PO₄)₃(F,Cl,OH)", 0.504, 3190, (0.95, 0.97, 0.95), "Calcium phosphate: the same mineral as your teeth and bones.", pka_acidity=9.0, products={"dissolved_salts": 1.0}),
    "turquoise_powder": powder("Turquoise Powder", "CuAl₆(PO₄)₄(OH)₈·4H₂O", 0.813, 2700, (0.4, 0.8, 0.75), "Sky-blue copper phosphate powder.", complexable=0.5, complex={"copper_ammine_complex": 1.0}),
    "ultramarine": powder("Ultramarine Pigment", "Na₇Al₆Si₆O₂₄S₃", 0.95, 2400, (0.1, 0.2, 0.75), "Ground lapis lazuli: once more precious than gold, the blue of Renaissance skies.", odor=0.3, pka_acidity=9.0, products=SULFIDE_ACID),
    "barite_powder": powder("Barite Powder", "BaSO₄", 0.233, 4480, (0.98, 0.98, 0.97), "Very heavy white powder used in drilling mud.", flame_color=(0.6, 1.0, 0.25, 1.0), flame_strength=0.6),
    "celestine_powder": powder("Celestine Powder", "SrSO₄", 0.184, 3960, (0.85, 0.92, 1.0), "Strontium mineral powder: burns with a crimson-red flame.", flame_color=(1.0, 0.1, 0.1, 1.0), flame_strength=0.9),
    "beryl_powder": powder("Beryl Powder", "Be₃Al₂Si₆O₁₈", 0.537, 2760, (0.92, 0.95, 0.92), "Beryllium silicate dust. Never breathe beryllium dust!", toxicity=0.7, health_hazard=0.9),
    "zircon_sand": powder("Zircon Sand", "ZrSiO₄", 0.183, 4650, (0.85, 0.75, 0.6), "Heavy golden sand of zircon, the oldest minerals on Earth.", melting_point_kelvin=2823),
    "olivine_sand": powder("Olivine Sand", "(Mg,Fe)₂SiO₄", 0.172, 3300, (0.55, 0.65, 0.25), "Green sand of olivine, from Earth's mantle.", melting_point_kelvin=2163),
    "silicate_dust": powder("Rock Flour", "(Ca,Mg,Fe) silicates", 0.22, 3000, (0.5, 0.5, 0.48), "Grey-green flour of ground silicate minerals (pyroxenes, amphiboles, clays)."),
    "tourmaline_powder": powder("Tourmaline Powder", "(Na,Ca)(Mg,Fe,Li,Al)₃Al₆(BO₃)₃Si₆O₁₈(OH)₄", 0.95, 3100, (0.3, 0.3, 0.3), "Tourmaline makes static electricity when warmed (pyroelectric).", electric_charge=0.3),
    "silver_flakes": powder("Silver Flakes", "Ag", 0.1079, 10490, (0.9, 0.9, 0.92), "Shiny native silver flakes.", melting_point_kelvin=1235, glitter=1.0),
    "bismuth_flakes": powder("Bismuth Flakes", "Bi", 0.209, 9780, (0.75, 0.7, 0.8), "Iridescent rainbow flakes of bismuth metal.", melting_point_kelvin=544, glitter=0.8, rainbow=0.5),
    "diamond_dust": powder("Diamond Dust", "C (diamond)", 0.012, 3510, (0.97, 0.97, 1.0), "The ultimate abrasive. Sparkles like frozen starlight.", melting_point_kelvin=3800, glitter=1.0),
    "jade_powder": powder("Jade Powder", "NaAlSi₂O₆", 0.202, 3330, (0.4, 0.7, 0.45), "Pale green jadeite powder."),
    "coal_dust": powder("Coal Dust", "C (+ H, S)", 0.012, 1350, (0.08, 0.08, 0.08), "Black, sooty and flammable.", flammability=0.5, flash_point_kelvin=420, combustion_enthalpy_j_kg=-29e6, odor=0.2, products={"carbon_dioxide": 0.9, "sulfur_dioxide": 0.1}),
    "boracite_powder": powder("Borax Powder", "Na₂B₄O₇·10H₂O", 0.381, 1730, (0.98, 0.98, 0.98), "Crushed borax crystals: dissolve to make slime activator.", dissolves_in_water=True, dissolution_enthalpy_j_mol=110000, products={"borax_solution": 1.0}),
    # Powders of the ingredient rocks: carbonates and crusts that give flame salts in acid.
    "strontianite_powder": powder("Strontianite Powder", "SrCO₃", 0.1476, 3760, (0.9, 0.93, 0.85), "Strontium carbonate. Fizzes in acid and leaves a salt that burns scarlet.", pka_acidity=10.0, proton_transfer_enthalpy_j_mol=10000, products={"carbon_dioxide": 0.3, "water": 0.12, "strontium_chloride": 0.58}),
    "witherite_powder": powder("Witherite Powder", "BaCO₃", 0.1973, 4290, (0.93, 0.92, 0.86), "Heavy barium carbonate. Poisonous! Fizzes in acid and leaves a salt that burns apple green.", pka_acidity=10.0, proton_transfer_enthalpy_j_mol=10000, toxicity=0.7, health_hazard=0.7, products={"carbon_dioxide": 0.22, "water": 0.09, "barium_chloride": 0.69}),
    "atacamite_powder": powder("Atacamite Powder", "Cu₂Cl(OH)₃", 0.2136, 3760, (0.25, 0.62, 0.38), "Green copper chloride hydroxide. Acid frees its copper salt, which burns blue-green.", pka_acidity=9.5, proton_transfer_enthalpy_j_mol=8000, toxicity=0.4, environmental_hazard=0.6, products={"copper_chloride": 0.8, "water": 0.2}),
    "lepidolite_powder": powder("Lepidolite Flakes", "K(Li,Al)₃(Al,Si)₄O₁₀(F,OH)₂", 0.388, 2840, (0.78, 0.62, 0.85), "Lilac lithium mica. Acid leaches out a lithium salt that burns crimson.", pka_acidity=9.0, proton_transfer_enthalpy_j_mol=6000, glitter=0.7, products={"lithium_chloride": 0.35, "dissolved_salts": 0.65}),

}


# Discovery routes (2026-11-21): crushed minerals that become shelf
# ingredients when put into water. Each is an ordinary dissolution, so the
# player finds them by experiment rather than by recipe.
PATCH = {
    "halite_powder": dict(dissolves_in_water=True, dissolution_enthalpy_j_mol=3900, products={"salt_brine": 1.0}),
    "luminite_dust": dict(dissolves_in_water=True, dissolution_enthalpy_j_mol=2000, products={"moonwater": 1.0}),
    "firepepper_powder": dict(decomposition_rate_per_s=0.0, dissolves_in_water=True, dissolution_enthalpy_j_mol=-150000, products={"salamander_oil": 1.0}),
    # Acid turns borax into boric acid (the green-flame salt).
    "borax_solution": dict(products={"boric_acid": 0.6, "water": 0.4}),
}
