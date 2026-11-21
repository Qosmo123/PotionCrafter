"""Build the lab's furniture, potion stands and tools in Blender and export glTF.

Run headless:
    blender --background --factory-startup --python tools/blender/build_lab_props.py

Writes world_3d/props/<name>.gltf (+ .bin) per prop and art_source/lab_props.blend.
Conventions: metres, origin at the floor (or wall-contact) centre, fronts face
Blender -Y, which becomes Godot +Z (toward the default camera).
"""

import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "world_3d", "props")
BLEND_PATH = os.path.join(ROOT, "art_source", "lab_props.blend")

MATS = {}


# --- Materials ------------------------------------------------------------------

def mat(name, color, rough=0.5, metal=0.0, transmission=0.0, emission=None, strength=0.0, coat=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if transmission > 0.0:
        b.inputs["Transmission Weight"].default_value = transmission
        b.inputs["IOR"].default_value = 1.47
    if emission is not None:
        b.inputs["Emission Color"].default_value = (*emission, 1.0)
        b.inputs["Emission Strength"].default_value = strength
    if coat > 0.0:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.15
    MATS[name] = m
    return m


def materials():
    return {
        "oak": mat("Oak", (0.30, 0.18, 0.09), 0.55, coat=0.3),
        "dark_wood": mat("DarkWood", (0.13, 0.075, 0.04), 0.5, coat=0.4),
        "brass": mat("Brass", (0.86, 0.66, 0.32), 0.28, 1.0),
        "copper": mat("Copper", (0.93, 0.52, 0.36), 0.25, 1.0),
        "iron": mat("Iron", (0.16, 0.16, 0.17), 0.45, 1.0),
        "ceramic": mat("Ceramic", (0.92, 0.91, 0.87), 0.12, coat=0.6),
        "stone": mat("Stone", (0.38, 0.36, 0.33), 0.8),
        "glass": mat("Glass", (0.95, 0.98, 1.0), 0.02, transmission=1.0),
        "frost": mat("FrostGlass", (0.75, 0.88, 1.0), 0.35, transmission=0.9),
        "frost_glow": mat("FrostGlow", (0.4, 0.75, 1.0), 0.4, emission=(0.35, 0.7, 1.0), strength=3.0),
        "rune_violet": mat("RuneViolet", (0.5, 0.2, 0.9), 0.3, emission=(0.7, 0.3, 1.0), strength=6.0),
        "orb": mat("ArcaneOrb", (0.6, 0.85, 1.0), 0.05, transmission=0.7, emission=(0.3, 0.6, 1.0), strength=4.0),
        "leather_red": mat("LeatherRed", (0.35, 0.06, 0.05), 0.6),
        "leather_green": mat("LeatherGreen", (0.07, 0.2, 0.1), 0.6),
        "leather_blue": mat("LeatherBlue", (0.06, 0.1, 0.28), 0.6),
        "parchment": mat("Parchment", (0.86, 0.78, 0.6), 0.85),
        "rubber": mat("Rubber", (0.55, 0.12, 0.08), 0.7),
        "cork": mat("Cork", (0.62, 0.45, 0.28), 0.92),
        "silver": mat("Silver", (0.92, 0.92, 0.94), 0.18, 1.0),
        "light_wood": mat("LightWood", (0.62, 0.45, 0.27), 0.6),
        "wand_wood": mat("WandWood", (0.18, 0.1, 0.06), 0.45, coat=0.5),
        "wand_gem": mat("WandGem", (0.9, 0.3, 0.8), 0.05, emission=(1.0, 0.35, 0.9), strength=5.0),
        "enamel": mat("Enamel", (0.85, 0.85, 0.82), 0.25, coat=0.5),
        "book_leather": mat("BookLeather", (0.22, 0.07, 0.05), 0.55, coat=0.25),
        "page_edge": mat("PageEdge", (0.62, 0.53, 0.36), 0.85),
        "gilt": mat("Gilt", (0.95, 0.72, 0.3), 0.22, 1.0),
        "sigil_glow": mat("SigilGlow", (0.9, 0.6, 0.25), 0.3, emission=(1.0, 0.62, 0.22), strength=4.0),
        "ribbon_red": mat("RibbonRed", (0.6, 0.05, 0.08), 0.5),
        "ribbon_green": mat("RibbonGreen", (0.05, 0.35, 0.18), 0.5),
        "glaze_teal": mat("GlazeTeal", (0.05, 0.32, 0.36), 0.18, coat=0.8),
        "glaze_cream": mat("GlazeCream", (0.86, 0.8, 0.66), 0.35, coat=0.4),
        "dial_glow": mat("DialGlow", (0.2, 0.9, 0.5), 0.3, emission=(0.2, 1.0, 0.5), strength=3.0),
    }


# --- Primitive helpers ------------------------------------------------------------

def _finish(obj, name, material, bevel, parent, smooth):
    obj.name = name
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
        mod.harden_normals = True
    if material is not None:
        obj.data.materials.append(material)
    if smooth:
        for poly in obj.data.polygons:
            poly.use_smooth = True
    if parent is not None:
        obj.parent = parent
    return obj


def box(name, size, loc, material, bevel=0.003, parent=None, rot=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, name, material, bevel, parent, False)


def cyl(name, radius, depth, loc, material, verts=40, rot=(0.0, 0.0, 0.0), bevel=0.0, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=verts, location=loc, rotation=rot)
    return _finish(bpy.context.active_object, name, material, bevel, parent, True)


def cone(name, r1, r2, depth, loc, material, verts=40, rot=(0.0, 0.0, 0.0), parent=None):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth, vertices=verts, location=loc, rotation=rot)
    return _finish(bpy.context.active_object, name, material, 0.0, parent, True)


def sphere(name, radius, loc, material, parent=None, scale=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc, segments=32, ring_count=16)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, name, material, 0.0, parent, True)


def torus(name, major, minor, loc, material, rot=(0.0, 0.0, 0.0), parent=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot,
                                     major_segments=48, minor_segments=12)
    return _finish(bpy.context.active_object, name, material, 0.0, parent, True)


def hollow(outer, inner):
    """Boolean-subtract `inner` from `outer`, then delete `inner`."""
    mod = outer.modifiers.new("Hollow", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = inner
    bpy.context.view_layer.objects.active = outer
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(inner, do_unlink=True)


# --- Props ---------------------------------------------------------------------

def wall_shelf(m):
    width, depth, t = 1.8, 0.26, 0.032
    for i, z in enumerate((0.0, 0.42, 0.84)):
        box("Plank%d" % i, (width, depth, t), (0.0, -depth / 2, z), m["oak"], 0.004)
        box("Lip%d" % i, (width, 0.012, 0.02), (0.0, -depth + 0.006, z + t / 2 + 0.01), m["oak"], 0.002)
        for x in (-0.75, 0.0, 0.75):
            box("BracketV%d%d" % (i, x * 10), (0.012, 0.012, 0.16), (x, -0.006, z - 0.095), m["brass"], 0.002)
            box("BracketH%d%d" % (i, x * 10), (0.012, 0.18, 0.012), (x, -0.095, z - t / 2 - 0.006), m["brass"], 0.002)
            box("BracketD%d%d" % (i, x * 10), (0.01, 0.2, 0.01), (x, -0.075, z - 0.08), m["brass"], 0.002,
                rot=(math.radians(-38.0), 0.0, 0.0))
    for x in (-0.9, 0.9):
        box("Side%d" % x, (0.03, depth, 0.9), (x, -depth / 2, 0.42), m["oak"], 0.004)


def cabinet_low(m):
    w, h, d = 0.9, 0.86, 0.52
    box("Carcass", (w, d, h - 0.08), (0.0, -d / 2, 0.08 + (h - 0.08) / 2), m["dark_wood"], 0.004)
    box("Top", (w + 0.04, d + 0.03, 0.035), (0.0, -d / 2 - 0.015, h + 0.0175), m["oak"], 0.006)
    box("Plinth", (w - 0.04, d - 0.04, 0.08), (0.0, -d / 2, 0.04), m["dark_wood"], 0.002)
    for i, x in enumerate((-w / 4, w / 4)):
        box("Door%d" % i, (w / 2 - 0.02, 0.022, h - 0.16), (x, -d - 0.011, 0.08 + (h - 0.08) / 2), m["oak"], 0.004)
        box("Panel%d" % i, (w / 2 - 0.12, 0.01, h - 0.3), (x, -d - 0.025, 0.08 + (h - 0.08) / 2), m["dark_wood"], 0.006)
        sphere("Knob%d" % i, 0.014, (x + (0.16 if i == 0 else -0.16), -d - 0.045, 0.6), m["brass"])


def sink_unit(m):
    w, h, d = 0.85, 0.82, 0.56
    box("Base", (w, d, h), (0.0, -d / 2, h / 2), m["dark_wood"], 0.004)
    for i, x in enumerate((-w / 4, w / 4)):
        box("Door%d" % i, (w / 2 - 0.02, 0.02, h - 0.12), (x, -d - 0.01, h / 2), m["oak"], 0.004)
        sphere("Knob%d" % i, 0.013, (x + (0.16 if i == 0 else -0.16), -d - 0.035, h - 0.15), m["brass"])
    basin = box("Basin", (0.66, 0.46, 0.2), (0.0, -d / 2, h + 0.1), m["ceramic"], 0.0)
    inner = box("BasinCut", (0.58, 0.38, 0.2), (0.0, -d / 2, h + 0.135), None, 0.0)
    hollow(basin, inner)
    bev = basin.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.012
    bev.segments = 4
    cyl("TapRiser", 0.012, 0.32, (0.0, -0.05, h + 0.36), m["brass"])
    cyl("TapArm", 0.011, 0.2, (0.0, -0.15, h + 0.51), m["brass"], rot=(math.radians(90.0), 0.0, 0.0))
    cyl("TapSpout", 0.009, 0.07, (0.0, -0.25, h + 0.48), m["brass"])
    sphere("TapElbow", 0.014, (0.0, -0.05, h + 0.51), m["brass"])
    for side in (-1.0, 1.0):
        cyl("Valve%d" % side, 0.008, 0.06, (side * 0.06, -0.05, h + 0.3), m["brass"], rot=(0.0, math.radians(90.0), 0.0))
        torus("Wheel%d" % side, 0.025, 0.005, (side * 0.1, -0.05, h + 0.3), m["brass"], rot=(0.0, math.radians(90.0), 0.0))


def icebox(m):
    w, h, d = 0.74, 1.72, 0.62
    box("Body", (w, d, h), (0.0, -d / 2, h / 2), m["dark_wood"], 0.008)
    box("Door", (w - 0.06, 0.03, h - 0.5), (0.0, -d - 0.015, 0.25 + (h - 0.5) / 2), m["oak"], 0.006)
    box("Window", (w - 0.24, 0.012, 0.5), (0.0, -d - 0.032, 1.05), m["frost"], 0.004)
    box("InnerGlow", (w - 0.26, 0.01, 0.48), (0.0, -d - 0.018, 1.05), m["frost_glow"], 0.0)
    box("Drawer", (w - 0.06, 0.03, 0.2), (0.0, -d - 0.015, 0.12), m["oak"], 0.006)
    box("Handle", (0.02, 0.03, 0.3), (w / 2 - 0.08, -d - 0.05, 1.0), m["brass"], 0.004)
    box("DrawerPull", (0.18, 0.025, 0.02), (0.0, -d - 0.045, 0.14), m["brass"], 0.004)
    for z in (0.45, 1.5):
        box("Hinge%.1f" % z, (0.03, 0.04, 0.09), (-w / 2 + 0.02, -d - 0.02, z), m["brass"], 0.003)
    for i in range(6):
        torus("Coil%d" % i, 0.12, 0.012, (0.0, -d / 2, h + 0.02 + i * 0.026), m["copper"])
    cyl("CoilCore", 0.03, 0.18, (0.0, -d / 2, h + 0.09), m["frost_glow"])
    torus("RuneSeal", 0.07, 0.006, (0.0, -d - 0.035, 1.55), m["frost_glow"], rot=(math.radians(90.0), 0.0, 0.0))


def magic_stand(m):
    cyl("RuneBase", 0.13, 0.03, (0.0, 0.0, 0.015), m["stone"], bevel=0.004)
    torus("RuneRing", 0.105, 0.004, (0.0, 0.0, 0.032), m["rune_violet"])
    torus("RuneRingInner", 0.06, 0.003, (0.0, 0.0, 0.032), m["rune_violet"])
    for i in range(3):
        a = math.tau * i / 3
        x, y = math.cos(a) * 0.07, math.sin(a) * 0.07
        cyl("Leg%d" % i, 0.006, 0.42, (x * 0.6, y * 0.6, 0.23), m["brass"],
            rot=(math.sin(a) * math.radians(-8.0), math.cos(a) * math.radians(8.0), 0.0))
    for j, (z, r) in enumerate(((0.16, 0.06), (0.3, 0.05))):
        torus("Tier%d" % j, r, 0.005, (0.0, 0.0, z), m["brass"])
        for k in range(3):
            a = math.tau * (k + 0.5 * j) / 3
            torus("Holder%d%d" % (j, k), 0.022, 0.003, (math.cos(a) * r, math.sin(a) * r, z + 0.004), m["brass"])
    torus("Crown", 0.035, 0.005, (0.0, 0.0, 0.44), m["brass"])
    sphere("Orb", 0.04, (0.0, 0.0, 0.48), m["orb"])


def science_stand(m):
    box("BasePlate", (0.22, 0.14, 0.014), (0.0, 0.0, 0.007), m["iron"], 0.003)
    cyl("Rod", 0.0065, 0.62, (-0.07, 0.0, 0.32), m["iron"])
    for z, arm_len, ring in ((0.42, 0.13, 0.045), (0.25, 0.11, 0.0)):
        box("Boss%.2f" % z, (0.03, 0.03, 0.035), (-0.07, 0.0, z), m["brass"], 0.003)
        cyl("Arm%.2f" % z, 0.005, arm_len, (-0.07 + arm_len / 2, 0.0, z), m["iron"], rot=(0.0, math.radians(90.0), 0.0))
        if ring > 0.0:
            torus("Ring%.2f" % z, ring, 0.004, (-0.07 + arm_len + ring - 0.01, 0.0, z), m["iron"])
        else:
            box("ClampJaw%.2f" % z, (0.04, 0.012, 0.02), (-0.07 + arm_len, 0.012, z), m["cork"], 0.003)
            box("ClampJawB%.2f" % z, (0.04, 0.012, 0.02), (-0.07 + arm_len, -0.012, z), m["cork"], 0.003)


def mortar_pestle(m):
    outer = cyl("Mortar", 0.06, 0.07, (0.0, 0.0, 0.035), m["stone"], bevel=0.006)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=(0.0, 0.0, 0.075))
    hollow(outer, bpy.context.active_object)
    cyl("Pestle", 0.011, 0.13, (0.03, 0.0, 0.09), m["stone"], rot=(0.0, math.radians(25.0), 0.0))
    sphere("PestleHead", 0.016, (0.005, 0.0, 0.04), m["stone"])


def tools_set(m):
    # Stirring rod, tongs, pipette, funnel, magnifier, books, scroll, berry bowl.
    cyl("StirRod", 0.003, 0.25, (-0.25, 0.0, 0.004), m["glass"], rot=(0.0, math.radians(90.0), 0.0))
    for side in (-1.0, 1.0):
        box("TongArm%d" % side, (0.2, 0.008, 0.004), (-0.05, side * 0.01, 0.004), m["brass"], 0.001,
            rot=(0.0, 0.0, side * math.radians(4.0)))
    cyl("Pipette", 0.0035, 0.16, (0.12, 0.04, 0.004), m["glass"], rot=(0.0, math.radians(90.0), 0.0))
    sphere("PipetteBulb", 0.009, (0.2, 0.04, 0.009), m["rubber"], scale=(1.4, 1.0, 1.0))
    funnel = cone("Funnel", 0.045, 0.006, 0.06, (0.3, -0.06, 0.07), m["glass"], rot=(0.0, 0.0, 0.0))
    funnel.rotation_euler = (math.radians(180.0), 0.0, 0.0)
    cyl("FunnelStem", 0.005, 0.05, (0.3, -0.06, 0.015), m["glass"])
    torus("MagnifierRim", 0.035, 0.004, (0.42, 0.05, 0.004), m["brass"])
    cyl("MagnifierLens", 0.034, 0.004, (0.42, 0.05, 0.004), m["glass"])
    cyl("MagnifierHandle", 0.006, 0.09, (0.5, 0.1, 0.006), m["dark_wood"], rot=(0.0, math.radians(90.0), math.radians(35.0)))
    for i, (lm, h) in enumerate((("leather_red", 0.04), ("leather_green", 0.035), ("leather_blue", 0.045))):
        z = 0.02 + i * 0.042
        box("Book%d" % i, (0.2, 0.15, h), (-0.45, -0.12, z), m[lm], 0.004, rot=(0.0, 0.0, math.radians(i * 7.0 - 5.0)))
        box("Pages%d" % i, (0.19, 0.142, h - 0.008), (-0.452, -0.122, z), m["parchment"], 0.001,
            rot=(0.0, 0.0, math.radians(i * 7.0 - 5.0)))
    cyl("Scroll", 0.018, 0.22, (0.0, -0.14, 0.018), m["parchment"], rot=(0.0, math.radians(90.0), math.radians(15.0)))
    bowl = sphere("Bowl", 0.07, (0.18, -0.16, 0.05), m["oak"], scale=(1.0, 1.0, 0.6))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.064, location=(0.18, -0.16, 0.058))
    cut = bpy.context.active_object
    cut.scale = (1.0, 1.0, 0.6)
    hollow(bowl, cut)


# Stirring tools: modelled upright along Z, centred at mid-length, tip at the bottom.

def glass_rod(m):
    cyl("Rod", 0.0035, 0.26, (0.0, 0.0, 0.0), m["glass"], verts=16)
    sphere("TipBead", 0.0045, (0.0, 0.0, -0.13), m["glass"])


def silver_rod(m):
    cyl("Rod", 0.003, 0.26, (0.0, 0.0, 0.0), m["silver"], verts=16)
    sphere("Finial", 0.007, (0.0, 0.0, 0.132), m["silver"])
    torus("Collar", 0.0045, 0.0015, (0.0, 0.0, 0.08), m["silver"])
    cyl("Paddle", 0.009, 0.002, (0.0, 0.0, -0.125), m["silver"], verts=24, rot=(math.radians(90.0), 0.0, 0.0))


def wooden_spoon(m):
    cyl("Handle", 0.0055, 0.24, (0.0, 0.0, 0.02), m["light_wood"], verts=16)
    sphere("Bowl", 0.022, (0.0, 0.0, -0.115), m["light_wood"], scale=(1.0, 0.35, 1.4))


def whisk(m):
    cyl("Handle", 0.009, 0.11, (0.0, 0.0, 0.075), m["dark_wood"], verts=20)
    torus("Ferrule", 0.009, 0.002, (0.0, 0.0, 0.02), m["silver"])
    for i in range(8):
        a = math.pi * i / 8
        torus("Wire%d" % i, 0.03, 0.0011, (0.0, 0.0, -0.045), m["silver"],
              rot=(math.radians(90.0), 0.0, a))
        bpy.context.active_object.scale = (0.55, 1.0, 1.25)


def arcane_wand(m):
    cone("Shaft", 0.0065, 0.0028, 0.26, (0.0, 0.0, 0.0), m["wand_wood"], verts=16, rot=(math.radians(180.0), 0.0, 0.0))
    for z in (0.05, 0.08, 0.11):
        torus("Band%.2f" % z, 0.0062, 0.0012, (0.0, 0.0, z), m["brass"])
    sphere("Gem", 0.0055, (0.0, 0.0, -0.132), m["wand_gem"])


def magnetic_stirrer(m):
    box("Housing", (0.17, 0.2, 0.06), (0.0, 0.0, 0.03), m["enamel"], 0.01)
    cyl("Plate", 0.07, 0.006, (0.0, 0.0, 0.063), m["iron"])
    cyl("Dial", 0.014, 0.012, (0.0, -0.1, 0.03), m["dial_glow"], rot=(math.radians(90.0), 0.0, 0.0))
    box("Badge", (0.06, 0.004, 0.012), (0.04, -0.101, 0.045), m["brass"], 0.001)



# Tool storage --------------------------------------------------------------------

def tool_pegboard(m):
    w, h = 0.62, 0.5
    box("Board", (w, 0.018, h), (0.0, -0.009, h / 2), m["light_wood"], 0.004)
    box("Frame", (w + 0.03, 0.026, 0.025), (0.0, -0.013, h), m["dark_wood"], 0.004)
    box("FrameB", (w + 0.03, 0.026, 0.025), (0.0, -0.013, 0.0), m["dark_wood"], 0.004)
    for row in range(5):
        for col in range(9):
            cyl("Hole%d_%d" % (row, col), 0.004, 0.004, (-w / 2 + 0.05 + col * 0.065, -0.019, 0.06 + row * 0.095),
                m["dark_wood"], verts=8, rot=(math.radians(90.0), 0.0, 0.0))
    hooks = [(-0.24, 0.42), (-0.12, 0.42), (0.0, 0.42), (0.13, 0.42), (0.25, 0.42), (-0.2, 0.2), (0.05, 0.2), (0.22, 0.2)]
    for i, (x, z) in enumerate(hooks):
        cyl("Hook%d" % i, 0.0025, 0.04, (x, -0.038, z), m["brass"], verts=8, rot=(math.radians(90.0), 0.0, 0.0))
    # Hanging tools: ladle, tongs, sieve, spatula, scissors-like shears, small saw.
    cyl("LadleHandle", 0.004, 0.22, (-0.24, -0.05, 0.31), m["copper"])
    sphere("LadleBowl", 0.028, (-0.24, -0.05, 0.19), m["copper"], scale=(1.0, 0.6, 0.55))
    for side in (-1.0, 1.0):
        box("Tong%d" % side, (0.008, 0.004, 0.2), (-0.12 + side * 0.008, -0.045, 0.32), m["brass"], 0.001,
            rot=(0.0, side * math.radians(4.0), 0.0))
    torus("SieveRim", 0.045, 0.004, (0.0, -0.05, 0.36), m["iron"], rot=(math.radians(90.0), 0.0, 0.0))
    cyl("SieveMesh", 0.043, 0.002, (0.0, -0.05, 0.36), m["iron"], rot=(math.radians(90.0), 0.0, 0.0))
    cyl("SieveHandle", 0.004, 0.1, (0.0, -0.05, 0.46), m["dark_wood"])
    box("SpatulaBlade", (0.03, 0.003, 0.06), (0.13, -0.045, 0.24), m["silver"], 0.002)
    cyl("SpatulaHandle", 0.004, 0.14, (0.13, -0.045, 0.34), m["dark_wood"])
    box("ScoopBlade", (0.035, 0.012, 0.05), (0.25, -0.05, 0.25), m["brass"], 0.004)
    cyl("ScoopHandle", 0.004, 0.13, (0.25, -0.05, 0.35), m["dark_wood"])
    for i, (x, color) in enumerate(((-0.2, "leather_red"), (0.05, "leather_green"), (0.22, "leather_blue"))):
        box("Pouch%d" % i, (0.07, 0.03, 0.09), (x, -0.045, 0.13), m[color], 0.01)


def drawer_chest(m):
    w, h, d = 0.26, 0.2, 0.2
    box("Carcass", (w, d, h), (0.0, -d / 2, h / 2), m["dark_wood"], 0.004)
    box("Top", (w + 0.012, d + 0.012, 0.01), (0.0, -d / 2, h + 0.005), m["oak"], 0.003)
    for row in range(3):
        z = 0.035 + row * 0.063
        for col, x in enumerate((-w / 4, w / 4)):
            box("Drawer%d%d" % (row, col), (w / 2 - 0.012, 0.012, 0.055), (x, -d - 0.004, z), m["oak"], 0.003)
            sphere("Pull%d%d" % (row, col), 0.006, (x, -d - 0.016, z), m["brass"])
            box("Label%d%d" % (row, col), (0.04, 0.002, 0.014), (x, -d - 0.011, z + 0.017), m["parchment"], 0.0)



def tool_crock(m):
    """Glazed stoneware utensil crock: hollow cylinder with a thick base, a
    rolled lip, two glaze bands and a brass collar. Origin at the floor centre."""
    r_out, h, wall, base = 0.055, 0.17, 0.006, 0.012
    outer = cyl("Body", r_out, h, (0.0, 0.0, h / 2), m["glaze_teal"], verts=64, bevel=0.003)
    inner = cyl("BodyCut", r_out - wall, h, (0.0, 0.0, base + h / 2), None, verts=64)
    hollow(outer, inner)
    torus("Lip", r_out - wall * 0.5, wall * 0.6, (0.0, 0.0, h), m["glaze_teal"])
    torus("Foot", r_out - 0.002, 0.004, (0.0, 0.0, 0.004), m["glaze_cream"])
    for z in (0.04, 0.14):
        torus("Band%.3f" % z, r_out + 0.0005, 0.0025, (0.0, 0.0, z), m["glaze_cream"])
    torus("Collar", r_out + 0.0012, 0.0032, (0.0, 0.0, 0.09), m["brass"])
    for i in range(6):
        a = math.tau * i / 6
        sphere("Stud%d" % i, 0.0042, (math.cos(a) * (r_out + 0.003), math.sin(a) * (r_out + 0.003), 0.09), m["brass"])



def grimoire_book(m):
    """Thick leather-bound grimoire lying closed: boards, page block, rounded
    spine, brass corners and clasp, a glowing cover sigil and silk ribbons.
    Origin at the bottom centre; the spine runs along -X."""
    w, d, t, board = 0.24, 0.18, 0.065, 0.006
    box("BackBoard", (w, d, board), (0.0, 0.0, board / 2), m["book_leather"], 0.003)
    box("FrontBoard", (w, d, board), (0.0, 0.0, t - board / 2), m["book_leather"], 0.003)
    box("Pages", (w - 0.012, d - 0.01, t - 2 * board), (0.006, 0.0, t / 2), m["page_edge"], 0.002)
    cyl("Spine", t / 2, d, (-w / 2, 0.0, t / 2), m["book_leather"], verts=24, rot=(math.radians(90.0), 0.0, 0.0))
    for y in (-d * 0.3, 0.0, d * 0.3):
        torus("SpineBand%.2f" % y, t / 2 + 0.001, 0.0018, (-w / 2, y, t / 2), m["gilt"], rot=(math.radians(90.0), 0.0, 0.0))
    for sx in (1.0, -1.0):
        for sy in (1.0, -1.0):
            if sx < 0:
                continue
            for z in (t - board / 2, board / 2):
                box("Corner%d%d%.3f" % (sx, sy, z), (0.03, 0.03, board + 0.002), (sx * (w / 2 - 0.013), sy * (d / 2 - 0.013), z), m["gilt"], 0.002,
                    rot=(0.0, 0.0, math.radians(45.0)))
    box("ClaspStrap", (0.05, 0.022, 0.003), (w / 2 - 0.005, 0.0, t + 0.0015), m["book_leather"], 0.001)
    box("ClaspPlate", (0.012, 0.03, t + 0.004), (w / 2 + 0.004, 0.0, t / 2), m["gilt"], 0.002)
    torus("SigilRing", 0.045, 0.003, (0.01, 0.0, t + 0.0012), m["sigil_glow"])
    torus("SigilInner", 0.028, 0.002, (0.01, 0.0, t + 0.0012), m["gilt"])
    for i in range(6):
        a = math.tau * i / 6 + math.pi / 6
        box("SigilSpoke%d" % i, (0.05, 0.003, 0.0016), (0.01 + math.cos(a) * 0.022, math.sin(a) * 0.022, t + 0.0012), m["sigil_glow"], 0.0,
            rot=(0.0, 0.0, a))
    sphere("SigilGem", 0.008, (0.01, 0.0, t + 0.004), m["sigil_glow"], scale=(1.0, 1.0, 0.5))
    box("RibbonA", (0.012, 0.0015, 0.07), (-0.03, -d / 2 - 0.001, t / 2 - 0.03), m["ribbon_red"], 0.0)
    box("RibbonB", (0.01, 0.0015, 0.06), (0.03, -d / 2 - 0.001, t / 2 - 0.035), m["ribbon_green"], 0.0)



# Mineral lab machines ------------------------------------------------------------

def rock_crusher(m):
    """Iron jaw-mill housing (0.16 m square) with a hopper on top and a chute."""
    box("Housing", (0.16, 0.16, 0.2), (0.0, 0.0, 0.1), m["iron"], 0.006)
    for z in (0.03, 0.17):
        box("Band%.2f" % z, (0.165, 0.165, 0.012), (0.0, 0.0, z), m["brass"], 0.002)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (0.03, 0.17):
                sphere("Rivet%d%d%.2f" % (sx, sy, z), 0.004, (sx * 0.083, sy * 0.083, z), m["brass"])
    # Hopper: four tapered walls.
    for i, (dx, dy) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
        wall = box("HopperWall%d" % i, (0.012 if dx else 0.15, 0.15 if dx else 0.012, 0.09), (dx * 0.07, dy * 0.07, 0.25), m["iron"], 0.003)
        wall.rotation_euler = (dy * math.radians(14.0), -dx * math.radians(14.0), 0.0)
    box("Chute", (0.06, 0.08, 0.012), (0.0, -0.11, 0.06), m["iron"], 0.003, rot=(math.radians(-25.0), 0.0, 0.0))
    cyl("Axle", 0.01, 0.16, (0.0, 0.0, 0.29), m["brass"])
    box("Plate", (0.07, 0.003, 0.03), (0.0, -0.0815, 0.12), m["brass"], 0.001)


def sand_sifter(m):
    """Wooden frame: four legs, side rails and a catch funnel below the deck."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("Leg%d%d" % (sx, sy), (0.02, 0.02, 0.2), (sx * 0.11, sy * 0.09, 0.1), m["oak"], 0.003)
    for sy in (-1, 1):
        box("Rail%d" % sy, (0.26, 0.012, 0.02), (0.0, sy * 0.095, 0.19), m["dark_wood"], 0.002)
    box("Funnel", (0.2, 0.16, 0.01), (0.0, 0.0, 0.07), m["copper"], 0.004)


def sifter_deck(m):
    """Three stacked sieve screens (coarse, medium, fine) on a shaking deck."""
    for i, (z, mesh_mat) in enumerate(((0.0, "brass"), (0.035, "copper"), (0.07, "brass"))):
        for sy in (-1, 1):
            box("Side%d%d" % (i, sy), (0.22, 0.008, 0.03), (0.0, sy * 0.075, z + 0.015), m["oak"], 0.002)
        for sx in (-1, 1):
            box("End%d%d" % (i, sx), (0.008, 0.15, 0.03), (sx * 0.11, 0.0, z + 0.015), m["oak"], 0.002)
        for k in range(9):
            box("WireX%d%d" % (i, k), (0.21, 0.0015, 0.0015), (0.0, -0.068 + k * 0.017, z + 0.004), m[mesh_mat], 0.0)
            box("WireY%d%d" % (i, k), (0.0015, 0.14, 0.0015), (-0.1 + k * 0.025, 0.0, z + 0.004), m[mesh_mat], 0.0)


def lapidary_polisher(m):
    """Enamel housing with a splash pan around the (Godot-spun) wheel."""
    box("Housing", (0.2, 0.2, 0.1), (0.0, 0.0, 0.05), m["enamel"], 0.01)
    torus("SplashPan", 0.09, 0.008, (0.0, 0.0, 0.11), m["copper"])
    cyl("PanFloor", 0.09, 0.006, (0.0, 0.0, 0.1), m["copper"])
    box("Badge", (0.08, 0.003, 0.02), (0.0, -0.101, 0.05), m["brass"], 0.001)
    cyl("Motor", 0.03, 0.05, (0.0, 0.07, 0.035), m["iron"], rot=(math.radians(90.0), 0.0, 0.0))


def faceting_machine(m):
    """Housing and lap with a mast, protractor quadrant and dop arm."""
    box("Housing", (0.2, 0.2, 0.1), (0.0, 0.0, 0.05), m["dark_wood"], 0.008)
    torus("SplashPan", 0.09, 0.008, (0.0, 0.0, 0.11), m["brass"])
    cyl("Mast", 0.008, 0.2, (0.08, 0.08, 0.2), m["iron"])
    torus("Quadrant", 0.05, 0.004, (0.08, 0.08, 0.27), m["brass"], rot=(math.radians(90.0), 0.0, 0.0))
    cyl("DopArm", 0.005, 0.12, (0.04, 0.08, 0.24), m["iron"], rot=(0.0, math.radians(60.0), 0.0))
    for k in range(12):
        a = math.tau * k / 12.0
        box("Tick%d" % k, (0.002, 0.002, 0.008), (0.08 + math.cos(a) * 0.05, 0.075, 0.27 + math.sin(a) * 0.05), m["gilt"], 0.0)


def stone_anvil(m):
    box("Block", (0.16, 0.12, 0.08), (0.0, 0.0, 0.04), m["stone"], 0.01)
    box("Plate", (0.14, 0.1, 0.01), (0.0, 0.0, 0.085), m["iron"], 0.003)


def rock_crate(m):
    for sy in (-1, 1):
        box("Side%d" % sy, (0.26, 0.012, 0.08), (0.0, sy * 0.09, 0.04), m["light_wood"], 0.003)
    for sx in (-1, 1):
        box("End%d" % sx, (0.012, 0.18, 0.08), (sx * 0.125, 0.0, 0.04), m["light_wood"], 0.003)
    box("Bottom", (0.26, 0.18, 0.01), (0.0, 0.0, 0.005), m["light_wood"], 0.002)
    box("Label", (0.08, 0.002, 0.03), (0.0, -0.097, 0.045), m["parchment"], 0.0)


PROPS = {
    "wall_shelf": wall_shelf,
    "cabinet_low": cabinet_low,
    "sink_unit": sink_unit,
    "icebox": icebox,
    "magic_potion_stand": magic_stand,
    "science_retort_stand": science_stand,
    "mortar_pestle": mortar_pestle,
    "tools_set": tools_set,
    "glass_rod": glass_rod,
    "silver_rod": silver_rod,
    "wooden_spoon": wooden_spoon,
    "whisk": whisk,
    "arcane_wand": arcane_wand,
    "magnetic_stirrer": magnetic_stirrer,
    "tool_pegboard": tool_pegboard,
    "drawer_chest": drawer_chest,
    "tool_crock": tool_crock,
    "grimoire_book": grimoire_book,
    "rock_crusher": rock_crusher,
    "sand_sifter": sand_sifter,
    "sifter_deck": sifter_deck,
    "lapidary_polisher": lapidary_polisher,
    "faceting_machine": faceting_machine,
    "stone_anvil": stone_anvil,
    "rock_crate": rock_crate,
}


def export_collection(coll, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in coll.all_objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", use_selection=True,
                              export_apply=True, export_yup=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m = materials()
    for index, (name, builder) in enumerate(PROPS.items()):
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
        layer_coll = bpy.context.view_layer.layer_collection.children[name]
        bpy.context.view_layer.active_layer_collection = layer_coll
        builder(m)
        export_collection(coll, os.path.join(OUT_DIR, name + ".gltf"))
        for obj in coll.all_objects:
            if obj.parent is None:
                obj.location.x += index * 2.2  # spread out in the .blend only, after export
        print("built", name, len(coll.all_objects), "objects")
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)


main()
