"""Generate content/substances/*.tres from the table below (source of truth for
the starter set). Run: python tools/gen_substances.py

Each entry lists only non-default properties. `products` maps product id ->
mass fraction; it is what this substance becomes when a reaction channel
consumes it (never a pair recipe).
"""

import os

OUT = os.path.join(os.path.dirname(__file__), "..", "content", "substances")

S = {
    "water": dict(name="Water", formula="H₂O", molar_mass_kg_mol=0.018015, density_kg_m3=998, specific_heat_j_kg_k=4184,
                  melting_point_kelvin=273.15, boiling_point_kelvin=373.15, latent_heat_fusion_j_kg=334000,
                  latent_heat_vaporization_j_kg=2257000, viscosity_pas=0.001, pka_acidity=15.7, surface_tension_n_m=0.072,
                  base_albedo_rgba=(0.62, 0.8, 0.95, 0.22), turbidity=0.03, ior=1.333),
    "ethanol": dict(name="Spirit of Wine", formula="C₂H₅OH", molar_mass_kg_mol=0.04607, density_kg_m3=789, specific_heat_j_kg_k=2440,
                    melting_point_kelvin=159, boiling_point_kelvin=351.4, latent_heat_fusion_j_kg=108000,
                    latent_heat_vaporization_j_kg=841000, viscosity_pas=0.0012, pka_acidity=15.9, flammability=0.9, combustion_enthalpy_j_kg=-29.7e6,
                    products_burn=True, surface_tension_n_m=0.022, base_albedo_rgba=(0.96, 0.95, 0.88, 0.14), turbidity=0.02, ior=1.361),
    "quicksilver": dict(name="Quicksilver", formula="Hg", molar_mass_kg_mol=0.20059, density_kg_m3=13534, specific_heat_j_kg_k=140,
                        melting_point_kelvin=234.32, boiling_point_kelvin=629.88, latent_heat_fusion_j_kg=11400,
                        latent_heat_vaporization_j_kg=295000, viscosity_pas=0.00153, pka_acidity=15.0, redox_potential_volts=0.85,
                        surface_tension_n_m=0.485, base_albedo_rgba=(0.78, 0.8, 0.83, 1.0), turbidity=1.0, ior=1.6,
                        thaumic_density_thaums_mol=4, transmutation_valence=0.6, miscibility_group=2,
                        products={"aurum_potabile": 1.0}),
    "honey_syrup": dict(name="Honey Syrup", formula="C₆H₁₂O₆·H₂O", molar_mass_kg_mol=0.18016, density_kg_m3=1420, specific_heat_j_kg_k=2500,
                        melting_point_kelvin=240, boiling_point_kelvin=390, latent_heat_fusion_j_kg=150000,
                        latent_heat_vaporization_j_kg=1800000, viscosity_pas=10.0, pka_acidity=7.0, flammability=0.2,
                        surface_tension_n_m=0.05, base_albedo_rgba=(0.92, 0.58, 0.12, 0.85), turbidity=0.55, ior=1.49,
                        vitality_resonance=0.3),
    "moonwater": dict(name="Moonwater", formula="H₂O·Lun⁻", molar_mass_kg_mol=0.018015, density_kg_m3=990, specific_heat_j_kg_k=3900,
                      melting_point_kelvin=260, boiling_point_kelvin=365, latent_heat_fusion_j_kg=300000,
                      latent_heat_vaporization_j_kg=2000000, viscosity_pas=0.0008, pka_acidity=7.0, surface_tension_n_m=0.06,
                      base_albedo_rgba=(0.45, 0.65, 1.0, 0.5), turbidity=0.15, ior=1.34, thaumic_density_thaums_mol=40,
                      polarity_charge=-0.3, entropy_flux=-0.1, chronal_dilation=0.05, gravity_coupling=-0.6,
                      emissive_aura_hdr=(0.35, 0.6, 1.6, 1.0), products={"spent_essence": 0.3, "water": 0.7}),
    # --- Products ---------------------------------------------------------------
    "dissolved_salts": dict(name="Brine of Salts", formula="Na⁺X⁻(aq)", molar_mass_kg_mol=0.082, density_kg_m3=1150,
                            specific_heat_j_kg_k=3300, melting_point_kelvin=250, boiling_point_kelvin=380,
                            latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=2000000, viscosity_pas=0.0015,
                            pka_acidity=7.0, base_albedo_rgba=(0.92, 0.92, 0.88, 0.12), turbidity=0.05),
    "carbon_dioxide": dict(name="Fixed Air", formula="CO₂", molar_mass_kg_mol=0.04401, density_kg_m3=1100, specific_heat_j_kg_k=840,
                           melting_point_kelvin=194.0, boiling_point_kelvin=195.0, latent_heat_fusion_j_kg=196000,
                           latent_heat_vaporization_j_kg=380000, viscosity_pas=0.0001, pka_acidity=7.0,
                           base_albedo_rgba=(0.95, 0.95, 0.95, 0.05), turbidity=0.0),
    "spent_essence": dict(name="Spent Essence", formula="Æ-residue", molar_mass_kg_mol=0.05, density_kg_m3=1020,
                          specific_heat_j_kg_k=3500, melting_point_kelvin=260, boiling_point_kelvin=380,
                          latent_heat_fusion_j_kg=250000, latent_heat_vaporization_j_kg=1800000, viscosity_pas=0.0015,
                          pka_acidity=7.0, base_albedo_rgba=(0.75, 0.7, 0.85, 0.3), turbidity=0.2,
                          thaumic_density_thaums_mol=1, emissive_aura_hdr=(0.15, 0.1, 0.25, 1.0)),
    # --- Science bench reagents -------------------------------------------------------
    "acetic_acid": dict(name="Essence of Vinegar", formula="CH₃COOH", molar_mass_kg_mol=0.06005, density_kg_m3=1049,
                        specific_heat_j_kg_k=2050, melting_point_kelvin=289.8, boiling_point_kelvin=391,
                        latent_heat_fusion_j_kg=192000, latent_heat_vaporization_j_kg=395000, viscosity_pas=0.00122,
                        pka_acidity=4.76, base_albedo_rgba=(0.97, 0.95, 0.85, 0.12), turbidity=0.02,
                        products={"dissolved_salts": 0.7, "water": 0.3}),
    "baking_soda": dict(name="Salt of Soda", formula="NaHCO₃", molar_mass_kg_mol=0.08401, density_kg_m3=2200,
                        specific_heat_j_kg_k=1000, melting_point_kelvin=450, boiling_point_kelvin=900,
                        latent_heat_fusion_j_kg=100000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01,
                        pka_acidity=10.3, proton_transfer_enthalpy_j_mol=28000,
                        base_albedo_rgba=(0.97, 0.97, 0.97, 1.0), turbidity=1.0,
                        products={"carbon_dioxide": 0.524, "water": 0.214, "dissolved_salts": 0.262}),
    "pva_glue": dict(name="Polyvinyl Mucilage", formula="(C₂H₄O)ₙ(aq)", molar_mass_kg_mol=0.044, density_kg_m3=1100,
                     specific_heat_j_kg_k=3500, melting_point_kelvin=250, boiling_point_kelvin=375,
                     latent_heat_fusion_j_kg=250000, latent_heat_vaporization_j_kg=2000000, viscosity_pas=0.8,
                     pka_acidity=7.0, crosslink_sites=0.9, base_albedo_rgba=(0.95, 0.95, 0.92, 0.75), turbidity=0.7),
    "borax_solution": dict(name="Borax Lye", formula="Na₂B₄O₇(aq)", molar_mass_kg_mol=0.02, density_kg_m3=1030,
                           specific_heat_j_kg_k=4000, melting_point_kelvin=271, boiling_point_kelvin=374,
                           latent_heat_fusion_j_kg=330000, latent_heat_vaporization_j_kg=2200000, viscosity_pas=0.0011,
                           pka_acidity=9.2, crosslinker_strength=0.95, base_albedo_rgba=(0.9, 0.95, 1.0, 0.15), turbidity=0.05,
                           products={"dissolved_salts": 0.6, "water": 0.4}),
    "soap_solution": dict(name="Saponified Lather", formula="C₁₇H₃₅COONa(aq)", molar_mass_kg_mol=0.03, density_kg_m3=1010,
                          specific_heat_j_kg_k=4000, melting_point_kelvin=268, boiling_point_kelvin=374,
                          latent_heat_fusion_j_kg=320000, latent_heat_vaporization_j_kg=2200000, viscosity_pas=0.003,
                          pka_acidity=8.6, foaming=0.95, surface_tension_n_m=0.03,
                          base_albedo_rgba=(0.85, 0.95, 1.0, 0.3), turbidity=0.25,
                          products={"dissolved_salts": 0.5, "water": 0.5}),
    "glycerin": dict(name="Sweet Oil of Glycerin", formula="C₃H₈O₃", molar_mass_kg_mol=0.09209, density_kg_m3=1261,
                     specific_heat_j_kg_k=2430, melting_point_kelvin=291, boiling_point_kelvin=563,
                     latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=974000, viscosity_pas=1.41,
                     pka_acidity=14.15, foam_stability=0.9, base_albedo_rgba=(0.97, 0.97, 0.95, 0.12), turbidity=0.02, ior=1.47),
    # --- Fantasy berry juices ------------------------------------------------------------
    "glowberry_juice": dict(name="Glowberry Juice", formula="C₆H₈O₇·Lum(aq)", molar_mass_kg_mol=0.03, density_kg_m3=1050,
                            specific_heat_j_kg_k=3900, melting_point_kelvin=268, boiling_point_kelvin=374,
                            latent_heat_fusion_j_kg=300000, latent_heat_vaporization_j_kg=2100000, viscosity_pas=0.002,
                            pka_acidity=3.1, vitality_resonance=0.6, thaumic_density_thaums_mol=6,
                            base_albedo_rgba=(0.35, 0.95, 0.4, 0.6), turbidity=0.3, emissive_aura_hdr=(0.3, 1.4, 0.4, 1.0),
                            products={"dissolved_salts": 0.4, "water": 0.6}),
    "emberberry_juice": dict(name="Emberberry Juice", formula="Ign⁺·C₆H₁₂O₆(aq)", molar_mass_kg_mol=0.03, density_kg_m3=1080,
                             specific_heat_j_kg_k=3600, melting_point_kelvin=265, boiling_point_kelvin=368,
                             latent_heat_fusion_j_kg=280000, latent_heat_vaporization_j_kg=1900000, viscosity_pas=0.003,
                             pka_acidity=7.0, flammability=0.5, polarity_charge=0.6, thaumic_density_thaums_mol=30,
                             base_albedo_rgba=(0.95, 0.3, 0.12, 0.7), turbidity=0.4, emissive_aura_hdr=(1.6, 0.45, 0.1, 1.0),
                             products={"spent_essence": 0.3, "water": 0.5, "dissolved_salts": 0.2}),
    "frostberry_juice": dict(name="Frostberry Juice", formula="Glac⁻(aq)", molar_mass_kg_mol=0.025, density_kg_m3=1030,
                             specific_heat_j_kg_k=4200, melting_point_kelvin=255, boiling_point_kelvin=372,
                             latent_heat_fusion_j_kg=330000, latent_heat_vaporization_j_kg=2200000, viscosity_pas=0.0025,
                             pka_acidity=7.0, chronal_dilation=0.4, polarity_charge=-0.25, thaumic_density_thaums_mol=18,
                             base_albedo_rgba=(0.55, 0.9, 1.0, 0.5), turbidity=0.2, emissive_aura_hdr=(0.3, 0.8, 1.3, 1.0),
                             products={"spent_essence": 0.3, "water": 0.7}),
    "duskberry_juice": dict(name="Duskberry Juice", formula="C₁₅H₁₁O₆⁺(aq)", molar_mass_kg_mol=0.03, density_kg_m3=1040,
                            specific_heat_j_kg_k=3900, melting_point_kelvin=268, boiling_point_kelvin=374,
                            latent_heat_fusion_j_kg=300000, latent_heat_vaporization_j_kg=2100000, viscosity_pas=0.002,
                            pka_acidity=7.0, indicator_strength=1.0, base_albedo_rgba=(0.45, 0.15, 0.6, 0.75), turbidity=0.5,
                            indicator_acid_color=(0.95, 0.12, 0.3, 0.8), indicator_base_color=(0.1, 0.75, 0.55, 0.8)),
    # --- Precipitation, decomposition, combustion, layers ------------------------------
    "oxygen": dict(name="Vital Air", formula="O₂", molar_mass_kg_mol=0.032, density_kg_m3=1141, specific_heat_j_kg_k=918,
                   melting_point_kelvin=54.4, boiling_point_kelvin=90.2, latent_heat_fusion_j_kg=13900,
                   latent_heat_vaporization_j_kg=213000, viscosity_pas=0.0002, pka_acidity=7.0,
                   base_albedo_rgba=(0.9, 0.95, 1.0, 0.03), turbidity=0.0),
    "hydrogen_peroxide": dict(name="Oxygenated Water", formula="H₂O₂(aq)", molar_mass_kg_mol=0.034, density_kg_m3=1110,
                              specific_heat_j_kg_k=2620, melting_point_kelvin=272.7, boiling_point_kelvin=423,
                              latent_heat_fusion_j_kg=368000, latent_heat_vaporization_j_kg=1517000, viscosity_pas=0.00125,
                              pka_acidity=7.0, decomposition_rate_per_s=0.0004, decomposition_enthalpy_j_mol=-98000,
                              base_albedo_rgba=(0.85, 0.95, 1.0, 0.12), turbidity=0.02,
                              products={"water": 0.53, "oxygen": 0.47}),
    "potassium_iodide": dict(name="Catalyst of Iodine", formula="KI(aq)", molar_mass_kg_mol=0.03, density_kg_m3=1150,
                             specific_heat_j_kg_k=3600, melting_point_kelvin=265, boiling_point_kelvin=376,
                             latent_heat_fusion_j_kg=300000, latent_heat_vaporization_j_kg=2100000, viscosity_pas=0.0012,
                             pka_acidity=7.0, catalyst_strength=1.0, base_albedo_rgba=(0.95, 0.85, 0.55, 0.3), turbidity=0.05),
    "salt_brine": dict(name="Sea Brine", formula="NaCl(aq)", molar_mass_kg_mol=0.025, density_kg_m3=1070,
                       specific_heat_j_kg_k=3900, melting_point_kelvin=263, boiling_point_kelvin=375,
                       latent_heat_fusion_j_kg=300000, latent_heat_vaporization_j_kg=2200000, viscosity_pas=0.0011,
                       pka_acidity=7.0, precipitant_charge=-1.0, base_albedo_rgba=(0.9, 0.95, 0.97, 0.12), turbidity=0.03,
                       products={"dissolved_salts": 1.0}),
    "silver_nitrate": dict(name="Lunar Caustic", formula="AgNO₃(aq)", molar_mass_kg_mol=0.05, density_kg_m3=1200,
                           specific_heat_j_kg_k=3300, melting_point_kelvin=265, boiling_point_kelvin=376,
                           latent_heat_fusion_j_kg=280000, latent_heat_vaporization_j_kg=2000000, viscosity_pas=0.0013,
                           pka_acidity=7.0, precipitant_charge=1.0, base_albedo_rgba=(0.95, 0.95, 0.97, 0.1), turbidity=0.02,
                           thaumic_density_thaums_mol=3, products={"silver_precipitate": 0.84, "dissolved_salts": 0.16}),
    "silver_precipitate": dict(name="Luna Cornea", formula="AgX↓", molar_mass_kg_mol=0.1433, density_kg_m3=5560,
                               specific_heat_j_kg_k=355, melting_point_kelvin=728, boiling_point_kelvin=1820,
                               latent_heat_fusion_j_kg=92000, latent_heat_vaporization_j_kg=1300000, viscosity_pas=0.01,
                               pka_acidity=7.0, base_albedo_rgba=(0.96, 0.96, 0.94, 1.0), turbidity=1.0,
                               emissive_aura_hdr=(0.05, 0.05, 0.06, 1.0)),
    "copper_sulfate": dict(name="Blue Vitriol", formula="CuSO₄(aq)", molar_mass_kg_mol=0.04, density_kg_m3=1150,
                           specific_heat_j_kg_k=3500, melting_point_kelvin=268, boiling_point_kelvin=376,
                           latent_heat_fusion_j_kg=300000, latent_heat_vaporization_j_kg=2100000, viscosity_pas=0.0012,
                           pka_acidity=7.0, precipitant_charge=1.0, base_albedo_rgba=(0.1, 0.45, 0.95, 0.7), turbidity=0.1,
                           products={"copper_precipitate": 0.6, "dissolved_salts": 0.4}),
    "copper_precipitate": dict(name="Verditer", formula="Cu(OH)₂↓", molar_mass_kg_mol=0.0976, density_kg_m3=3370,
                               specific_heat_j_kg_k=800, melting_point_kelvin=600, boiling_point_kelvin=1500,
                               latent_heat_fusion_j_kg=150000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01,
                               pka_acidity=7.0, base_albedo_rgba=(0.18, 0.5, 0.98, 1.0), turbidity=1.0),
    "caustic_lye": dict(name="Caustic Lye", formula="NaOH(aq)", molar_mass_kg_mol=0.025, density_kg_m3=1200,
                        specific_heat_j_kg_k=3500, melting_point_kelvin=263, boiling_point_kelvin=378,
                        latent_heat_fusion_j_kg=300000, latent_heat_vaporization_j_kg=2100000, viscosity_pas=0.002,
                        pka_acidity=13.8, precipitant_charge=-1.0, base_albedo_rgba=(0.95, 0.97, 0.95, 0.12), turbidity=0.03,
                        products={"dissolved_salts": 0.7, "water": 0.3}),
    "salamander_oil": dict(name="Salamander Oil", formula="C₁₈H₃₄O₂", molar_mass_kg_mol=0.2825, density_kg_m3=910,
                           specific_heat_j_kg_k=1970, melting_point_kelvin=260, boiling_point_kelvin=570,
                           latent_heat_fusion_j_kg=140000, latent_heat_vaporization_j_kg=300000, viscosity_pas=0.06,
                           pka_acidity=7.0, flammability=0.6, combustion_enthalpy_j_kg=-37.0e6, products_burn=True,
                           miscibility_group=1, base_albedo_rgba=(0.98, 0.72, 0.15, 0.55), turbidity=0.08, ior=1.47,
                           surface_tension_n_m=0.032),
    "chameleon_ink": dict(name="Chameleon Ink", formula="[Co(H₂O)₆]²⁺ ⇌ [CoCl₄]²⁻", molar_mass_kg_mol=0.03, density_kg_m3=1080,
                          specific_heat_j_kg_k=3800, melting_point_kelvin=265, boiling_point_kelvin=376,
                          latent_heat_fusion_j_kg=300000, latent_heat_vaporization_j_kg=2100000, viscosity_pas=0.0015,
                          pka_acidity=7.0, thermochromic_strength=1.0, base_albedo_rgba=(0.6, 0.25, 0.75, 0.8), turbidity=0.3,
                          thermo_cold_color=(0.15, 0.35, 0.95, 0.8), thermo_hot_color=(0.95, 0.12, 0.25, 0.8)),
    "aurum_potabile": dict(name="Aurum Potabile", formula="Au(Æ)ₙ", molar_mass_kg_mol=0.19697, density_kg_m3=13000,
                           specific_heat_j_kg_k=130, melting_point_kelvin=230, boiling_point_kelvin=2900,
                           latent_heat_fusion_j_kg=64000, latent_heat_vaporization_j_kg=1700000, viscosity_pas=0.004,
                           pka_acidity=7.0, miscibility_group=2, vitality_resonance=0.8, thaumic_density_thaums_mol=12,
                           base_albedo_rgba=(1.0, 0.78, 0.25, 1.0), turbidity=1.0, emissive_aura_hdr=(1.2, 0.8, 0.2, 1.0)),
    # --- Minerals update: rock powders, sands, fun substances ---
    "calcite_powder": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=10.3, turbidity=1.0, name='Fizzrock Powder', formula='CaCO₃', molar_mass_kg_mol=0.1001, density_kg_m3=2710, base_albedo_rgba=(0.95, 0.94, 0.9, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500, proton_transfer_enthalpy_j_mol=15000, products={'carbon_dioxide': 0.44, 'water': 0.18, 'dissolved_salts': 0.38}),
    "malachite_powder": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=10.0, turbidity=1.0, name='Malachite Powder', formula='Cu₂CO₃(OH)₂', molar_mass_kg_mol=0.2211, density_kg_m3=3800, base_albedo_rgba=(0.1, 0.6, 0.35, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500, proton_transfer_enthalpy_j_mol=10000, products={'carbon_dioxide': 0.2, 'water': 0.08, 'copper_sulfate': 0.72}),
    "pyrite_dust": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=9.5, turbidity=1.0, name="Fool's Gold Dust", formula='FeS₂', molar_mass_kg_mol=0.12, density_kg_m3=5010, base_albedo_rgba=(0.85, 0.7, 0.3, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500, glitter=0.8, products={'rotten_egg_gas': 0.3, 'dissolved_salts': 0.7}),
    "rotten_egg_gas": dict(name='Stink Vapour', formula='H₂S', molar_mass_kg_mol=0.034, density_kg_m3=950, specific_heat_j_kg_k=1000, melting_point_kelvin=187.0, boiling_point_kelvin=213.0, latent_heat_fusion_j_kg=70000, latent_heat_vaporization_j_kg=550000, viscosity_pas=0.0002, pka_acidity=7.0, odor=1.0, base_albedo_rgba=(0.8, 0.9, 0.6, 0.05), turbidity=0.0),
    "sulfur_dioxide": dict(name='Brimstone Fume', formula='SO₂', molar_mass_kg_mol=0.064, density_kg_m3=1460, specific_heat_j_kg_k=620, melting_point_kelvin=200.0, boiling_point_kelvin=263.0, latent_heat_fusion_j_kg=115000, latent_heat_vaporization_j_kg=390000, viscosity_pas=0.0003, pka_acidity=7.0, odor=0.8, base_albedo_rgba=(0.95, 0.95, 0.8, 0.05), turbidity=0.0),
    "sulfur_powder": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Brimstone Powder', formula='S₈', molar_mass_kg_mol=0.2565, density_kg_m3=2070, base_albedo_rgba=(0.95, 0.85, 0.15, 1.0), melting_point_kelvin=388, boiling_point_kelvin=718, flammability=0.7, combustion_enthalpy_j_kg=-9200000.0, odor=0.3, products={'sulfur_dioxide': 1.0}),
    "halite_powder": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Rock Salt', formula='NaCl', molar_mass_kg_mol=0.0584, density_kg_m3=2160, base_albedo_rgba=(0.97, 0.95, 0.95, 1.0), melting_point_kelvin=1074, boiling_point_kelvin=2500, precipitant_charge=-1.0, glitter=0.2, products={'dissolved_salts': 1.0}),
    "obsidian_glitter": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Obsidian Glitter', formula='SiO₂ (volcanic glass)', molar_mass_kg_mol=0.0601, density_kg_m3=2400, base_albedo_rgba=(0.08, 0.07, 0.09, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500, glitter=1.0),
    "fluorite_powder": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Fluorite Powder', formula='CaF₂', molar_mass_kg_mol=0.0781, density_kg_m3=3180, base_albedo_rgba=(0.6, 0.4, 0.9, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500, glitter=0.3, emissive_aura_hdr=(0.25, 0.08, 0.5, 1.0)),
    "luminite_dust": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Luminite Dust', formula='Lm·SiO₂', molar_mass_kg_mol=0.07, density_kg_m3=2600, base_albedo_rgba=(0.5, 0.95, 0.85, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500, glitter=0.5, thaumic_density_thaums_mol=15, emissive_aura_hdr=(0.3, 1.4, 1.0, 1.0)),
    "stardust": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Stardust', formula='Fe–Ni·Æ', molar_mass_kg_mol=0.056, density_kg_m3=3000, base_albedo_rgba=(0.85, 0.9, 1.0, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500, glitter=1.0, thaumic_density_thaums_mol=60, gravity_coupling=-1.2, polarity_charge=-0.2, emissive_aura_hdr=(0.6, 0.7, 1.4, 1.0), magnetic=0.4, products={'spent_essence': 1.0}),
    "popping_crystals": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Fizzpop Crystals', formula='C₁₂H₂₂O₁₁·CO₂', molar_mass_kg_mol=0.342, density_kg_m3=1590, base_albedo_rgba=(1.0, 0.55, 0.75, 1.0), melting_point_kelvin=460, boiling_point_kelvin=2500, decomposition_rate_per_s=0.5, decomposition_enthalpy_j_mol=-3000, glitter=0.3, products={'carbon_dioxide': 0.1, 'honey_syrup': 0.9}),
    "firepepper_powder": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Firepepper Powder', formula='C₁₈H₂₇NO₃', molar_mass_kg_mol=0.305, density_kg_m3=1100, base_albedo_rgba=(0.85, 0.15, 0.05, 1.0), melting_point_kelvin=340, boiling_point_kelvin=2500, decomposition_rate_per_s=0.08, decomposition_enthalpy_j_mol=-150000, polarity_charge=0.3, thaumic_density_thaums_mol=8, odor=0.4, products={'dissolved_salts': 1.0}),
    "bog_gum": dict(name='Troll Snot', formula='(C₆H₁₀O₅)ₙ·bog', molar_mass_kg_mol=0.05, density_kg_m3=1080, specific_heat_j_kg_k=3500, melting_point_kelvin=250, boiling_point_kelvin=375, latent_heat_fusion_j_kg=250000, latent_heat_vaporization_j_kg=2000000, viscosity_pas=1.5, pka_acidity=7.0, crosslink_sites=0.8, odor=0.25, base_albedo_rgba=(0.45, 0.75, 0.15, 0.85), turbidity=0.6),
    "quartz_sand_coarse": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Coarse Quartz Sand', formula='SiO₂ (1–2 mm)', molar_mass_kg_mol=0.0601, density_kg_m3=2650, base_albedo_rgba=(0.78, 0.68, 0.52, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500),
    "quartz_sand_medium": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Medium Quartz Sand', formula='SiO₂ (0.25–1 mm)', molar_mass_kg_mol=0.0601, density_kg_m3=2650, base_albedo_rgba=(0.86, 0.77, 0.6, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500),
    "quartz_sand_fine": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Fine Quartz Sand', formula='SiO₂ (<0.25 mm)', molar_mass_kg_mol=0.0601, density_kg_m3=2650, base_albedo_rgba=(0.93, 0.87, 0.74, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500),
    "magnetite_sand": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Black Iron Sand', formula='Fe₃O₄', molar_mass_kg_mol=0.2315, density_kg_m3=5170, base_albedo_rgba=(0.1, 0.1, 0.11, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500, magnetic=1.0, glitter=0.3),
    "garnet_sand": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Garnet Sand', formula='Fe₃Al₂(SiO₄)₃', molar_mass_kg_mol=0.4977, density_kg_m3=4100, base_albedo_rgba=(0.6, 0.1, 0.15, 1.0), melting_point_kelvin=1200, boiling_point_kelvin=2500, glitter=0.4),
    "gold_flecks": dict(specific_heat_j_kg_k=850, latent_heat_fusion_j_kg=200000, latent_heat_vaporization_j_kg=1000000, viscosity_pas=0.01, pka_acidity=7.0, turbidity=1.0, name='Gold Flecks', formula='Au', molar_mass_kg_mol=0.19697, density_kg_m3=19300, base_albedo_rgba=(1.0, 0.8, 0.3, 1.0), melting_point_kelvin=1337, boiling_point_kelvin=2500, glitter=1.0),
}


def fmt(v):
    if isinstance(v, tuple):
        return "Color(%s)" % ", ".join("%g" % x for x in v)
    if isinstance(v, str):
        return '"%s"' % v
    return "%g" % v if isinstance(v, float) else str(v)


def main():
    import importlib.util
    here = os.path.dirname(__file__)
    for mod_name in ("substances_lab", "substances_fun", "substances_minerals"):
        path = os.path.join(here, mod_name + ".py")
        if os.path.exists(path):
            spec = importlib.util.spec_from_file_location(mod_name, path)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            for sid, patch in getattr(mod, "PATCH", {}).items():
                S[sid].update(patch)
            S.update(getattr(mod, "SUBSTANCES", {}))
    for sid, props in S.items():
        props = dict(props)
        tables = []
        products = props.pop("products", {})
        if props.pop("products_burn", False) and not products:
            products = {"carbon_dioxide": 0.6, "water": 0.4}
        tables.append(("reaction_products", "reaction_product_mass_fractions", products, "p"))
        tables.append(("redox_products", "redox_fractions", props.pop("redox", {}), "r"))
        tables.append(("complex_products", "complex_fractions", props.pop("complex", {}), "x"))
        lines = []
        ext = ['[ext_resource type="Script" path="res://core/chemistry/substance_data.gd" id="1_sub"]']
        for _, _, table, prefix in tables:
            for k, pid in enumerate(table):
                ext.append('[ext_resource type="Resource" path="res://content/substances/%s.tres" id="%s%d"]' % (pid, prefix, k))
        lines.append('script = ExtResource("1_sub")')
        lines.append('substance_id = &"%s"' % sid)
        lines.append('display_name = "%s"' % props.pop("name"))
        lines.append('chemical_formula = "%s"' % props.pop("formula"))
        for key, val in props.items():
            if isinstance(val, bool):
                lines.append("%s = %s" % (key, "true" if val else "false"))
            elif isinstance(val, str):
                lines.append('%s = "%s"' % (key, val.replace('"', "'")))
            else:
                lines.append("%s = %s" % (key, fmt(float(val) if isinstance(val, int) else val)))
        for res_key, frac_key, table, prefix in tables:
            if table:
                lines.append("%s = Array[Resource]([%s])" % (res_key, ", ".join('ExtResource("%s%d")' % (prefix, k) for k in range(len(table)))))
                lines.append("%s = PackedFloat32Array(%s)" % (frac_key, ", ".join("%g" % f for f in table.values())))
        text = '[gd_resource type="Resource" script_class="SubstanceData" load_steps=%d format=3]' % (len(ext) + 1)
        text += '\n\n' + '\n'.join(ext) + '\n\n[resource]\n' + '\n'.join(lines) + '\n'
        with open(os.path.join(OUT, sid + '.tres'), 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
    print("wrote", len(S), "substances")


main()
