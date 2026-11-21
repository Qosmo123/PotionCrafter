"""Build lab glassware as lathe (revolved) meshes and export them for Godot.

Run headless:
    blender --background --factory-startup --python tools/blender/build_glassware.py

For each vessel it writes:
    world_3d/vessels/meshes/<name>_glass.obj   watertight glass shell (wall thickness, rolled lip)
    world_3d/vessels/meshes/<name>_liquid.obj  inner liquid volume (closed, slightly inset)
    world_3d/vessels/profiles/<name>.tres      VesselProfile: meshes + inner profile + physical data
and saves the source scene to art_source/glassware.blend.

Units are metres. Blender is Z-up; OBJ export converts to Godot's Y-up.
Every mesh is centred on its mid-height so the RigidBody origin sits mid-vessel.
"""

import math
import os

import bmesh
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MESH_DIR = os.path.join(ROOT, "world_3d", "vessels", "meshes")
PROFILE_DIR = os.path.join(ROOT, "world_3d", "vessels", "profiles")
BLEND_PATH = os.path.join(ROOT, "art_source", "glassware.blend")

SEGMENTS = 128  # smooth silhouettes and highlights up close (4K)
GLASS_DENSITY_KG_M3 = 2230.0  # borosilicate
LIQUID_INSET_M = 0.0004


# --- Inner profiles: (radius, height) from the bottom centre up to the opening ---

def arc(cx, cy, radius, a0_deg, a1_deg, steps):
    pts = []
    for i in range(steps + 1):
        a = math.radians(a0_deg + (a1_deg - a0_deg) * i / steps)
        pts.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return pts


def round_flask():
    bulb_r = 0.046
    neck_r = 0.0115
    cy = bulb_r
    join_y = cy + math.sqrt(bulb_r * bulb_r - neck_r * neck_r)
    join_a = math.degrees(math.atan2(join_y - cy, neck_r))
    pts = arc(0.0, cy, bulb_r, -90.0, join_a, 28)
    pts[0] = (0.0, 0.0)
    pts += [(neck_r, join_y + 0.012), (neck_r, 0.150), (neck_r * 1.08, 0.158)]
    return pts


def erlenmeyer():
    base_r = 0.043
    fillet = 0.006
    neck_r = 0.0135
    cone_top = 0.098
    pts = [(0.0, 0.0), (base_r - fillet, 0.0)]
    pts += arc(base_r - fillet, fillet, fillet, -90.0, -10.0, 5)[1:]
    pts += [(neck_r + 0.004, cone_top - 0.006), (neck_r, cone_top + 0.004), (neck_r, 0.132), (neck_r * 1.1, 0.138)]
    return pts


def beaker():
    r = 0.048
    fillet = 0.004
    pts = [(0.0, 0.0), (r - fillet, 0.0)]
    pts += arc(r - fillet, fillet, fillet, -90.0, 0.0, 5)[1:]
    pts += [(r, 0.092), (r * 1.03, 0.097)]
    return pts


def vial():
    r = 0.0145
    pts = arc(0.0, r, r, -90.0, 0.0, 10)
    pts[0] = (0.0, 0.0)
    pts += [(r, 0.078), (r * 1.06, 0.083)]
    return pts


def apothecary_bottle():
    body_r = 0.031
    neck_r = 0.0095
    fillet = 0.005
    pts = [(0.0, 0.0), (body_r - fillet, 0.0)]
    pts += arc(body_r - fillet, fillet, fillet, -90.0, 0.0, 5)[1:]
    pts += [(body_r, 0.066)]
    # Shoulder: quarter-ellipse from body radius to neck radius.
    for i in range(1, 13):
        a = math.radians(90.0 * i / 12)
        pts.append((neck_r + (body_r - neck_r) * math.cos(a), 0.066 + 0.026 * math.sin(a)))
    pts += [(neck_r, 0.118), (neck_r * 1.18, 0.123)]
    return pts


VESSELS = {
    # name: (profile fn, wall thickness m)
    "round_flask": (round_flask, 0.0022),
    "erlenmeyer": (erlenmeyer, 0.0022),
    "beaker": (beaker, 0.0025),
    "vial": (vial, 0.0015),
    "apothecary_bottle": (apothecary_bottle, 0.0024),
}


# --- Geometry helpers -----------------------------------------------------------

def offset_outward(pts, thickness):
    """Offset an inner profile outward (away from the cavity) by `thickness`."""
    out = []
    n = len(pts)
    for i, (r, y) in enumerate(pts):
        r0, y0 = pts[max(i - 1, 0)]
        r1, y1 = pts[min(i + 1, n - 1)]
        tx, ty = r1 - r0, y1 - y0
        length = math.hypot(tx, ty) or 1.0
        # Outward normal of a profile walked bottom->top is (ty, -tx).
        nx, ny = ty / length, -tx / length
        if i == 0:
            nx, ny = 0.0, -1.0
        out.append((max(r + nx * thickness, 0.0) if i > 0 else 0.0, y + ny * thickness))
    return out


def shell_section(inner, thickness):
    """Closed cross-section for the glass wall: outer up, rolled lip, inner down."""
    outer = offset_outward(inner, thickness)
    top_r, top_y = inner[-1]
    lip_r = thickness * 0.75
    lip_c = (top_r + thickness * 0.5, top_y)
    lip = [(lip_c[0] + lip_r * math.cos(math.radians(a)), lip_c[1] + lip_r * math.sin(math.radians(a)))
           for a in range(0, 181, 30)]
    return outer + lip + list(reversed(inner))


def liquid_section(inner):
    pts = [(max(r - LIQUID_INSET_M, 0.0), y + LIQUID_INSET_M) for r, y in inner]
    pts[0] = (0.0, pts[0][1])
    top_y = pts[-2][1]  # stop below the lip flare
    body = [p for p in pts[:-1]]
    return body + [(0.0, top_y)]


def revolve(name, section, z_shift):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    verts = [bm.verts.new((r, 0.0, y - z_shift)) for r, y in section]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0.0, 0.0, 0.0), axis=(0.0, 0.0, 1.0),
                   angle=math.tau, steps=SEGMENTS, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    volume = abs(bm.calc_volume(signed=False))
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj, volume


def export_obj(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.wm.obj_export(filepath=path, export_selected_objects=True, forward_axis="NEGATIVE_Z",
                          up_axis="Y", export_materials=False, export_normals=True, export_uv=False,
                          apply_modifiers=True)


def write_profile(name, inner, z_shift, outer_radius, height, glass_mass_kg, liquid_capacity_m3):
    shifted = ", ".join("%.6f, %.6f" % (r, y - z_shift) for r, y in inner)
    text = f'''[gd_resource type="Resource" script_class="VesselProfile" load_steps=4 format=3]

[ext_resource type="Script" path="res://world_3d/vessels/vessel_profile.gd" id="1_script"]
[ext_resource type="ArrayMesh" path="res://world_3d/vessels/meshes/{name}_glass.obj" id="2_glass"]
[ext_resource type="ArrayMesh" path="res://world_3d/vessels/meshes/{name}_liquid.obj" id="3_liquid"]

[resource]
script = ExtResource("1_script")
vessel_name = "{name}"
glass_mesh = ExtResource("2_glass")
liquid_mesh = ExtResource("3_liquid")
inner_profile = PackedVector2Array({shifted})
outer_radius_meters = {outer_radius:.6f}
height_meters = {height:.6f}
glass_mass_kg = {glass_mass_kg:.6f}
modelled_capacity_m3 = {liquid_capacity_m3:.9f}
'''
    with open(os.path.join(PROFILE_DIR, name + ".tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    os.makedirs(MESH_DIR, exist_ok=True)
    os.makedirs(PROFILE_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    report = []
    for index, (name, (profile_fn, thickness)) in enumerate(VESSELS.items()):
        inner = profile_fn()
        section = shell_section(inner, thickness)
        bottom_y = min(y for _, y in section)
        top_y = max(y for _, y in section)
        height = top_y - bottom_y
        z_shift = bottom_y + height * 0.5
        glass, glass_volume = revolve(name + "_glass", section, z_shift)
        liquid, liquid_volume = revolve(name + "_liquid", liquid_section(inner), z_shift)
        export_obj(glass, os.path.join(MESH_DIR, name + "_glass.obj"))
        export_obj(liquid, os.path.join(MESH_DIR, name + "_liquid.obj"))
        for obj in (glass, liquid):
            obj.location.x = index * 0.15  # spread out in the .blend only, after export
        outer_radius = max(r for r, _ in section)
        mass = glass_volume * GLASS_DENSITY_KG_M3
        write_profile(name, inner, z_shift, outer_radius, height, mass, liquid_volume)
        report.append("%-18s h=%.3f m  r=%.4f m  glass=%.1f g  capacity=%.0f mL" % (
            name, height, outer_radius, mass * 1000.0, liquid_volume * 1e6))
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("\n".join(report))


main()
