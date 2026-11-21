"""Generate content/minerals/*.tres (collectible rocks, sands, minerals, gems,
fossils). Run: python tools/gen_minerals.py

kind: ROCK 0, SAND 1, MINERAL 2, GEM 3, FOSSIL 4
luster: EARTHY 0, GLASSY 1, METALLIC 2, WAXY 3, PEARLY 4, GLOW 5
shape: BLOB 0, CRYSTAL 1, CLUSTER 2, GEODE 3, BAG 4, SHELL 5, NUGGET 6
rarity: 0 Common .. 4 Legendary
"""

import os

OUT = os.path.join(os.path.dirname(__file__), "..", "content", "minerals")

# --- Collectible finds (minerals, gems, fossils) — listed first so rocks can include them.
FINDS = {
    "amethyst": dict(name="Amethyst", formula="SiO₂ (Fe³⁺)", kind=3, rarity=1, hardness=7, density=2650, mass=0.012,
                     color=(0.6, 0.3, 0.85), luster=1, shape=1, value=25, facet=True, crush={"quartz_sand_fine": 1.0},
                     fact="Amethyst is quartz that turned purple thanks to a pinch of iron and millions of years of natural radiation."),
    "crystal_quartz": dict(name="Crystal Quartz", formula="SiO₂", kind=2, rarity=0, hardness=7, density=2650, mass=0.01,
                           color=(0.92, 0.95, 1.0), luster=1, shape=1, value=8, facet=True, crush={"quartz_sand_fine": 1.0},
                           fact="Squeeze a quartz crystal and it makes a tiny spark of electricity. That is why quartz keeps time in watches!"),
    "fire_opal": dict(name="Fire Opal", formula="SiO₂·nH₂O", kind=3, rarity=3, hardness=6, density=2100, mass=0.008,
                      color=(1.0, 0.45, 0.15), luster=1, shape=0, value=90, facet=True, emission=(0.4, 0.12, 0.02),
                      crush={"quartz_sand_fine": 1.0},
                      fact="Opal is up to 20% water locked inside glassy silica. Tiny spheres inside bend light into flashes of fire."),
    "azurite": dict(name="Azurite", formula="Cu₃(CO₃)₂(OH)₂", kind=2, rarity=1, hardness=3.5, density=3800, mass=0.015,
                    color=(0.1, 0.25, 0.85), luster=1, shape=2, value=20, crush={"malachite_powder": 1.0},
                    fact="Medieval painters ground azurite into a dazzling blue paint. Over centuries some of it slowly turns green!"),
    "gold_nugget": dict(name="Gold Nugget", formula="Au", kind=2, rarity=3, hardness=2.5, density=19300, mass=0.006,
                        color=(1.0, 0.8, 0.3), luster=2, shape=6, value=120, crush={"gold_flecks": 1.0},
                        fact="Gold is so soft you can squash it flat with your fingers, and it never rusts. Pirates loved it!"),
    "pink_salt": dict(name="Pink Salt Crystal", formula="NaCl (Fe)", kind=2, rarity=0, hardness=2.5, density=2160, mass=0.01,
                      color=(1.0, 0.7, 0.75), luster=1, shape=1, value=6, crush={"halite_powder": 0.75, "baking_soda": 0.25},  # natron crust: salt of soda
                      fact="Salt crystals grow as perfect little cubes. Lick test not recommended in a real lab!"),
    "moonstone": dict(name="Moonstone", formula="KAlSi₃O₈ (Æ)", kind=3, rarity=2, hardness=6, density=2560, mass=0.01,
                      color=(0.85, 0.9, 1.0), luster=4, shape=0, value=60, facet=True, emission=(0.15, 0.2, 0.4),
                      crush={"luminite_dust": 1.0},
                      fact="Moonstone glows with a soft blue shimmer called adularescence, made by light bouncing between thin crystal layers."),
    "star_sapphire": dict(name="Star Sapphire", formula="Al₂O₃ (Ti, Fe)", kind=3, rarity=4, hardness=9, density=4000, mass=0.009,
                          color=(0.15, 0.25, 0.8), luster=1, shape=1, value=300, facet=True, crush={"stardust": 1.0},
                          fact="Needle-thin crystals inside a star sapphire catch the light and paint a six-pointed star on its surface."),
    "meteoric_iron": dict(name="Meteoric Iron", formula="Fe–Ni", kind=2, rarity=2, hardness=4.5, density=7800, mass=0.02,
                          color=(0.45, 0.45, 0.5), luster=2, shape=0, value=50, crush={"magnetite_sand": 0.6, "stardust": 0.4},
                          fact="This metal fell from space! Cut and etched, meteoric iron shows criss-cross patterns that only form in space."),
    "ruby": dict(name="Ruby", formula="Al₂O₃ (Cr)", kind=3, rarity=3, hardness=9, density=4000, mass=0.008,
                 color=(0.85, 0.05, 0.15), luster=1, shape=1, value=150, facet=True, emission=(0.15, 0.0, 0.02),
                 crush={"firepepper_powder": 1.0},
                 fact="Ruby and sapphire are the same mineral! A dash of chromium makes it red, and it even glows red under UV light."),
    "ammonite_fossil": dict(name="Ammonite Fossil", formula="CaCO₃ (fossil)", kind=4, rarity=2, hardness=3.5, density=2700, mass=0.03,
                            color=(0.75, 0.62, 0.45), luster=4, shape=5, value=70, crush={"calcite_powder": 1.0},
                            fact="Ammonites were squid-like sea creatures with spiral shells that swam the oceans with the dinosaurs."),
    "garnet": dict(name="Garnet", formula="Fe₃Al₂(SiO₄)₃", kind=3, rarity=1, hardness=7.5, density=4100, mass=0.006,
                   color=(0.55, 0.05, 0.1), luster=1, shape=1, value=30, facet=True, crush={"garnet_sand": 1.0},
                   fact="Garnet sand is so hard that people use it to blast and cut steel with super-fast water jets."),
    "peridot": dict(name="Peridot", formula="(Mg,Fe)₂SiO₄", kind=3, rarity=2, hardness=6.5, density=3300, mass=0.006,
                    color=(0.55, 0.8, 0.15), luster=1, shape=1, value=55, facet=True, crush={"obsidian_glitter": 1.0},
                    fact="Peridot comes from deep inside the Earth and is carried up by volcanoes. It has been found in meteorites too!"),
    "sea_glass": dict(name="Sea Glass", formula="SiO₂ (frosted)", kind=2, rarity=1, hardness=5.5, density=2500, mass=0.005,
                      color=(0.4, 0.75, 0.65), luster=3, shape=0, value=15, crush={"quartz_sand_fine": 1.0},
                      fact="Sea glass started life as a bottle. Waves and sand tumbled it for decades until it went smooth and frosty."),
    "seashell": dict(name="Spiral Seashell", formula="CaCO₃ (aragonite)", kind=4, rarity=0, hardness=3.5, density=2900, mass=0.008,
                     color=(0.95, 0.85, 0.75), luster=4, shape=5, value=5, crush={"calcite_powder": 1.0},
                     fact="Seashells are built by soft sea animals from the same stuff as chalk, one thin layer at a time."),
    "desert_rose": dict(name="Desert Rose", formula="CaSO₄·2H₂O", kind=2, rarity=2, hardness=2, density=2300, mass=0.02,
                        color=(0.85, 0.65, 0.5), luster=0, shape=2, value=45, crush={"quartz_sand_fine": 1.0},
                        fact="Desert roses grow when salty water evaporates in the sand, leaving crystal petals that look like a flower."),
    "tektite": dict(name="Tektite", formula="SiO₂ (impact glass)", kind=2, rarity=2, hardness=5.5, density=2400, mass=0.006,
                    color=(0.15, 0.2, 0.1), luster=1, shape=0, value=40, crush={"obsidian_glitter": 0.7, "stardust": 0.3},
                    fact="When a meteorite smashes into Earth, melted rock splashes into the sky and rains down as glassy tektites."),
    "diamond": dict(name="Diamond", formula="C", kind=3, rarity=4, hardness=10, density=3510, mass=0.004,
                    color=(0.97, 0.98, 1.0), luster=1, shape=1, value=500, facet=True, crush={"stardust": 1.0},
                    fact="Diamond is pure carbon, just like pencil lead, squeezed so hard deep underground that it became the hardest natural material."),
    "fool_gold_cube": dict(name="Pyrite Cube", formula="FeS₂", kind=2, rarity=1, hardness=6.3, density=5010, mass=0.015,
                           color=(0.85, 0.72, 0.35), luster=2, shape=1, value=12, crush={"pyrite_dust": 1.0},
                           fact="Pyrite grows in perfect shiny cubes. Gold rush miners got so excited they called it Fool's Gold!"),
    "fluorite_octahedron": dict(name="Fluorite", formula="CaF₂", kind=3, rarity=1, hardness=4, density=3180, mass=0.012,
                                color=(0.55, 0.35, 0.95), luster=1, shape=1, value=22, facet=True, emission=(0.1, 0.03, 0.2),
                                crush={"fluorite_powder": 1.0},
                                fact="Fluorite glows under ultraviolet light. It gave its name to the word fluorescence!"),
}

ROCKS = {
    "fizzrock": dict(name="Fizzrock (Limestone)", formula="CaCO₃", kind=0, rarity=0, hardness=3, density=2700, mass=0.12,
                     color=(0.85, 0.82, 0.74), shape=0, value=3, crush={"calcite_powder": 1.0},
                     incl={"ammonite_fossil": 0.25, "seashell": 0.4},
                     fact="Limestone is made from billions of tiny sea shells. Drip vinegar on it and it fizzes!"),
    "geode": dict(name="Geode", formula="SiO₂ shell", kind=0, rarity=1, hardness=6, density=2400, mass=0.15,
                  color=(0.55, 0.5, 0.45), shape=3, value=10, crush={"quartz_sand_fine": 0.8, "fluorite_powder": 0.2},
                  incl={"amethyst": 0.85, "crystal_quartz": 0.6, "fluorite_octahedron": 0.25},
                  fact="Geodes look like boring rocks outside, but crack one open and it can be full of sparkling crystals."),
    "volcanic_obsidian": dict(name="Volcanic Obsidian", formula="SiO₂ glass", kind=0, rarity=1, hardness=5.5, density=2400, mass=0.1,
                              color=(0.06, 0.05, 0.07), luster=1, shape=0, value=8, crush={"obsidian_glitter": 1.0},
                              incl={"fire_opal": 0.15, "peridot": 0.2},
                              fact="Obsidian is lava that cooled so fast it had no time to make crystals, so it turned into natural glass."),
    "malachite_ore": dict(name="Malachite Ore", formula="Cu₂CO₃(OH)₂", kind=0, rarity=1, hardness=3.5, density=3800, mass=0.12,
                          color=(0.1, 0.55, 0.3), luster=4, shape=0, value=9, crush={"malachite_powder": 1.0},
                          incl={"azurite": 0.35},
                          fact="Malachite has swirly green stripes like a slice of agate. Ancient Egyptians used it as eye makeup!"),
    "pyrite_cluster": dict(name="Pyrite Cluster", formula="FeS₂", kind=0, rarity=1, hardness=6.3, density=5010, mass=0.13,
                           color=(0.75, 0.65, 0.35), luster=2, shape=2, value=10, crush={"pyrite_dust": 0.8, "sulfur_powder": 0.2},
                           incl={"fool_gold_cube": 0.6, "gold_nugget": 0.08},
                           fact="Strike pyrite against steel and it makes sparks. Its name comes from the Greek word for fire."),
    "halite_rock": dict(name="Rock Salt", formula="NaCl", kind=0, rarity=0, hardness=2.5, density=2160, mass=0.1,
                        color=(0.95, 0.85, 0.85), luster=1, shape=1, value=2, crush={"halite_powder": 0.75, "baking_soda": 0.25},  # natron crust: salt of soda
                        incl={"pink_salt": 0.5},
                        fact="Rock salt is what is left of an ancient sea that dried up millions of years ago."),
    "moonstone_ore": dict(name="Moonstone Ore", formula="KAlSi₃O₈ (Æ)", kind=0, rarity=2, hardness=6, density=2560, mass=0.1,
                          color=(0.7, 0.75, 0.85), luster=4, shape=0, value=18, emission=(0.05, 0.07, 0.15),
                          crush={"luminite_dust": 0.5, "quartz_sand_fine": 0.5}, incl={"moonstone": 0.6},
                          fact="Moonstone ore glimmers faintly at night. Alchemists believed it soaked up moonlight."),
    "meteorite": dict(name="Meteorite", formula="Fe–Ni + silicates", kind=0, rarity=3, hardness=5, density=5500, mass=0.14,
                      color=(0.3, 0.28, 0.27), luster=2, shape=0, value=40, crush={"stardust": 0.4, "magnetite_sand": 0.6},
                      incl={"meteoric_iron": 0.6, "star_sapphire": 0.08, "diamond": 0.03},
                      fact="Meteorites are pieces of asteroids. Some are older than the Earth itself, about 4.6 billion years!"),
    "dragonstone": dict(name="Dragonstone", formula="Fe₂O₃·S (Ign)", kind=0, rarity=2, hardness=4, density=3500, mass=0.12,
                        color=(0.55, 0.15, 0.08), luster=0, shape=0, value=16, emission=(0.2, 0.03, 0.0),
                        crush={"firepepper_powder": 0.6, "sulfur_powder": 0.4}, incl={"ruby": 0.25, "garnet": 0.4},
                        fact="Legend says dragonstone is warm to the touch because a dragon once slept on it. It does smell a bit like a dragon."),
    "fizzpop_rock": dict(name="Fizzpop Candy Rock", formula="C₁₂H₂₂O₁₁·CO₂", kind=0, rarity=0, hardness=1.5, density=1590, mass=0.06,
                         color=(1.0, 0.55, 0.75), luster=1, shape=2, value=3, crush={"popping_crystals": 1.0},
                         fact="Popping candy is sugar with fizzy gas trapped inside. When it melts, POP! the bubbles escape."),
    "troll_amber": dict(name="Troll-Tooth Amber", formula="(C₁₀H₁₆)ₙ resin", kind=0, rarity=1, hardness=2.5, density=1080, mass=0.06,
                        color=(0.75, 0.5, 0.1), luster=3, shape=0, value=12, crush={"bog_gum": 1.0},
                        fact="Amber is fossilised tree sap. Sometimes tiny insects from millions of years ago are trapped inside!"),
}

SANDS = {
    "river_sand": dict(name="River Sand Bag", formula="SiO₂ mix", kind=1, rarity=0, hardness=7, density=1600, mass=0.25,
                       color=(0.7, 0.62, 0.48), shape=4, value=2,
                       crush={"quartz_sand_coarse": 0.3, "quartz_sand_medium": 0.4, "quartz_sand_fine": 0.25, "magnetite_sand": 0.05},
                       incl={"gold_nugget": 0.12, "garnet": 0.25, "crystal_quartz": 0.3},
                       fact="River sand is ground-down mountains carried downstream. Prospectors still pan rivers for gold!"),
    "beach_sand": dict(name="Beach Sand Bag", formula="SiO₂ + shell", kind=1, rarity=0, hardness=6, density=1600, mass=0.25,
                       color=(0.93, 0.85, 0.66), shape=4, value=2,
                       crush={"quartz_sand_medium": 0.35, "quartz_sand_fine": 0.45, "calcite_powder": 0.15, "garnet_sand": 0.05},
                       incl={"seashell": 0.6, "sea_glass": 0.35},
                       fact="Some beaches are made of tiny broken shells and coral, and a few are even green, pink or black!"),
    "desert_sand": dict(name="Desert Sand Bag", formula="SiO₂ (fine)", kind=1, rarity=0, hardness=7, density=1600, mass=0.25,
                        color=(0.9, 0.7, 0.45), shape=4, value=2, crush={"quartz_sand_fine": 0.85, "quartz_sand_medium": 0.15},
                        incl={"desert_rose": 0.3},
                        fact="Desert sand grains are rounded and frosted from being blown around by the wind for thousands of years."),
    "volcanic_sand": dict(name="Volcanic Sand Bag", formula="basalt + glass", kind=1, rarity=1, hardness=6, density=1700, mass=0.25,
                          color=(0.15, 0.14, 0.15), shape=4, value=4,
                          crush={"obsidian_glitter": 0.3, "magnetite_sand": 0.4, "quartz_sand_medium": 0.3},
                          incl={"peridot": 0.3, "fire_opal": 0.05},
                          fact="Black sand beaches form when hot lava hits the cold sea and shatters into tiny pieces."),
    "crater_sand": dict(name="Crater Sand Bag", formula="impact debris", kind=1, rarity=2, hardness=6, density=1800, mass=0.25,
                        color=(0.4, 0.35, 0.33), shape=4, value=8,
                        crush={"magnetite_sand": 0.4, "stardust": 0.1, "quartz_sand_coarse": 0.5},
                        incl={"tektite": 0.4, "meteoric_iron": 0.2, "diamond": 0.02},
                        fact="Sand from a meteor crater can hold tiny diamonds made in the blink of an eye by the giant impact!"),
}


def write(mid, d):
    d = dict(d)
    d["crush"] = {k: v for k, v in d.get("crush", {}).items() if v > 0.0}
    d["incl"] = {k: v for k, v in d.get("incl", {}).items() if v > 0.0}
    ext = ['[ext_resource type="Script" path="res://world_3d/terrarium/mineral_data.gd" id="1_min"]']
    crush = d.get("crush", {})
    incl = d.get("incl", {})
    for k, sid in enumerate(crush):
        ext.append('[ext_resource type="Resource" path="res://content/substances/%s.tres" id="c%d"]' % (sid, k))
    for k, iid in enumerate(incl):
        ext.append('[ext_resource type="Resource" path="res://content/minerals/%s.tres" id="i%d"]' % (iid, k))
    em = d.get("emission", (0.0, 0.0, 0.0))
    lines = [
        'script = ExtResource("1_min")',
        'mineral_id = &"%s"' % mid,
        'display_name = "%s"' % d["name"],
        'formula = "%s"' % d["formula"],
        "kind = %d" % d["kind"],
        "rarity = %d" % d["rarity"],
        "hardness_mohs = %g" % d["hardness"],
        "density_kg_m3 = %g" % d["density"],
        "typical_mass_kg = %g" % d["mass"],
        "color = Color(%g, %g, %g, 1)" % d["color"],
        "luster = %d" % d.get("luster", 0),
        "shape = %d" % d.get("shape", 0),
        "emission = Color(%g, %g, %g, 1)" % em,
        "value_coins = %d" % d["value"],
        "can_facet = %s" % ("true" if d.get("facet") else "false"),
        'fun_fact = "%s"' % d["fact"],
        "crush_products = Array[Resource]([%s])" % ", ".join('ExtResource("c%d")' % k for k in range(len(crush))),
        "crush_fractions = PackedFloat32Array(%s)" % ", ".join("%g" % v for v in crush.values()),
        "inclusions = Array[Resource]([%s])" % ", ".join('ExtResource("i%d")' % k for k in range(len(incl))),
        "inclusion_chances = PackedFloat32Array(%s)" % ", ".join("%g" % v for v in incl.values()),
    ]
    if "system" in d:
        sname, scol = d["streak"]
        lines += [
            'mineral_class = "%s"' % d["mclass"],
            'crystal_system = "%s"' % d["system"],
            'streak_name = "%s"' % sname,
            "streak_color = Color(%g, %g, %g, 1)" % scol,
            "cleavage = %d" % d["cleavage"],
            'fracture = "%s"' % d["fracture"],
            "diaphaneity = %d" % d["diaph"],
            "refractive_index = %g" % d["ri"],
            "dispersion = %g" % d["disp"],
            "phenomenon = %d" % d["phen"],
            'colors_text = "%s"' % d["colors"],
            'localities = "%s"' % d["localities"],
            'uses = "%s"' % d["uses"],
            'birthstone = "%s"' % d.get("birth", ""),
        ]
        if d.get("alt"):
            lines.append("color_alt = Color(%g, %g, %g, 1)" % tuple(d["alt"]))
    text = '[gd_resource type="Resource" script_class="MineralData" load_steps=%d format=3]\n\n%s\n\n[resource]\n%s\n' % (
        len(ext) + 1, "\n".join(ext), "\n".join(lines))
    with open(os.path.join(OUT, mid + ".tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    import sys
    sys.path.insert(0, os.path.dirname(__file__))
    import minerals_encyclopedia as enc
    import minerals_more
    for group in (FINDS, ROCKS):
        for mid, extra in enc.ENRICH.items():
            if mid in group:
                group[mid].update(extra)
    entries = dict(enc.ENTRIES)
    entries.update(minerals_more.ENTRIES)
    for mid, d in entries.items():
        # Keep hand-tuned emission glow of originals when an entry replaces them.
        old = FINDS.get(mid) or ROCKS.get(mid)
        if old and "emission" in old and "emission" not in d:
            d["emission"] = old["emission"]
        target = ROCKS if d["kind"] == 0 else FINDS
        FINDS.pop(mid, None)
        ROCKS.pop(mid, None)
        target[mid] = d
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for group in (FINDS, ROCKS, SANDS):
        for mid, d in group.items():
            write(mid, d)
            n += 1
    print("wrote", n, "minerals")


main()
