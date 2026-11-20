# Blender 4.5 — centre-console fishing boat for Boat Sink v2.
# Authored in Godot coordinates (x=right, y=up, z=bow) and converted to
# Blender coordinates (x, z_godot, y_godot) for modelling. OBJ is exported
# with axis_forward='Z', axis_up='Y' so the file lands in Godot space.
# Run: blender --background --python tools/build_boat_model.py
import bpy
import math
import os
from mathutils import Vector

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
OUT_DIR = os.path.normpath(OUT_DIR)

# ----------------------------------------------------------------- materials
MAT_DEFS = {
    # name: (r, g, b, roughness, metallic)
    "HullWhite":      (0.92, 0.94, 0.95, 0.32, 0.0),
    "HullBottom":     (0.04, 0.11, 0.14, 0.50, 0.0),
    "DeckGray":       (0.55, 0.58, 0.58, 0.85, 0.0),
    "ConsoleWhite":   (0.90, 0.92, 0.93, 0.35, 0.0),
    "VinylTeal":      (0.00, 0.42, 0.45, 0.60, 0.0),
    "WoodBrown":      (0.48, 0.29, 0.14, 0.75, 0.0),
    "OrangeHatch":    (0.80, 0.30, 0.02, 0.50, 0.0),
    "MetalRail":      (0.75, 0.78, 0.80, 0.30, 0.90),
    "BlackParts":     (0.04, 0.045, 0.05, 0.55, 0.20),
    "GlassWindshield": (0.25, 0.55, 0.65, 0.08, 0.10),
    "MotorDark":      (0.07, 0.08, 0.09, 0.42, 0.35),
    "NavRed":         (0.90, 0.05, 0.05, 0.40, 0.0),
    "NavGreen":       (0.05, 0.85, 0.25, 0.40, 0.0),
    "CrateDark":      (0.30, 0.18, 0.08, 0.85, 0.0),
}
MATS = {}

def make_materials():
    for name, (r, g, b, rough, metal) in MAT_DEFS.items():
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if name == "GlassWindshield":
            bsdf.inputs["Alpha"].default_value = 0.38
            m.surface_render_method = 'DITHERED'
        if name in ("NavRed", "NavGreen"):
            bsdf.inputs["Emission Color"].default_value = (r, g, b, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 2.0
        MATS[name] = m

# ----------------------------------------------------------------- helpers
def G(p):
    """Godot point (x, y_up, z_bow) -> Blender point (x, z_bow, y_up)."""
    return (p[0], p[2], p[1])

def assign_mats(obj, names):
    for n in names:
        obj.data.materials.append(MATS[n])

def fix_orientation(obj):
    """Reverse faces if the signed volume is negative (closed meshes)."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    try:
        vol = bm.calc_volume(signed=True)
    except Exception:
        vol = 0.0
    if vol < -1e-6:
        for f in bm.faces:
            f.normal_flip()
        bm.to_mesh(obj.data)
    bm.free()

def make_mesh(name, verts_g, faces, face_mats, smooth=None):
    """verts_g/faces in Godot coords; face_mats = material name per face."""
    verts = [G(v) for v in verts_g]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    names = []
    for fm in face_mats:
        if fm not in names:
            names.append(fm)
    for n in names:
        mesh.materials.append(MATS[n])
    for i, poly in enumerate(mesh.polygons):
        poly.material_index = names.index(face_mats[i])
        poly.use_smooth = True if smooth is None else smooth[i]
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    fix_orientation(obj)
    return obj

def box(name, pos, size, mat, bevel=0.0, rot_g_deg=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=G(pos))
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rot_g_deg != (0, 0, 0):
        # Godot rotation about Y (yaw) maps to Blender rotation about Z.
        obj.rotation_euler = (math.radians(rot_g_deg[0]),
                              math.radians(rot_g_deg[2]),
                              math.radians(rot_g_deg[1]))
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    if bevel > 0.0:
        mod = obj.modifiers.new("bev", 'BEVEL')
        mod.width = bevel
        mod.segments = 2
    assign_mats(obj, [mat])
    return obj

def cylinder_between(name, p1, p2, radius, mat, vertices=10):
    a = Vector(G(p1))
    b = Vector(G(p2))
    mid = (a + b) * 0.5
    direction = b - a
    length = direction.length
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                        depth=length, location=mid)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = direction.to_track_quat('Z', 'Y')
    assign_mats(obj, [mat])
    return obj

def sphere(name, pos, radii, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=G(pos))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (radii[0], radii[2], radii[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for p in obj.data.polygons:
        p.use_smooth = True
    assign_mats(obj, [mat])
    return obj

def torus(name, pos, major, minor, mat, rot_b_deg=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=24, minor_segments=8,
                                     location=G(pos))
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = tuple(math.radians(a) for a in rot_b_deg)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    assign_mats(obj, [mat])
    return obj

# ----------------------------------------------------------------- hull loft
# station: (z, half_beam, keel_y, chine_y, gunwale_y)
STATIONS = [
    (-3.20, 1.02, 0.34, 0.52, 1.16),
    (-2.70, 1.13, 0.16, 0.40, 1.18),
    (-1.60, 1.15, 0.06, 0.34, 1.19),
    (-0.40, 1.14, 0.03, 0.32, 1.19),
    ( 0.80, 1.08, 0.05, 0.34, 1.20),
    ( 1.80, 0.94, 0.12, 0.42, 1.21),
    ( 2.55, 0.68, 0.28, 0.58, 1.22),
    ( 3.05, 0.36, 0.52, 0.78, 1.23),
    ( 3.30, 0.04, 0.88, 1.02, 1.24),
]
OUT_SEG_MATS = ["HullWhite", "HullWhite", "HullBottom", "HullBottom",
                "HullBottom", "HullBottom", "HullWhite", "HullWhite"]

def outer_profile(st):
    z, b, keel, chine, gun = st
    return [
        (-b, gun, z), (-b * 0.97, chine + 0.16, z), (-b * 0.86, chine, z),
        (-b * 0.52, keel + 0.10, z), (0.0, keel, z),
        (b * 0.52, keel + 0.10, z), (b * 0.86, chine, z),
        (b * 0.97, chine + 0.16, z), (b, gun, z),
    ]

# inner stations: (z, half_beam_inner, gunwale_y)
INNER_STATIONS = [
    (-3.14, 0.90, 1.13),
    (-2.70, 1.00, 1.15),
    (-1.60, 1.02, 1.16),
    (-0.40, 1.01, 1.16),
    ( 0.80, 0.95, 1.17),
    ( 1.80, 0.81, 1.18),
    ( 2.30, 0.65, 1.19),
]
IN_SEG_MATS = ["HullWhite", "DeckGray", "DeckGray", "DeckGray", "DeckGray", "HullWhite"]

def inner_profile(st):
    z, b, gun = st
    return [
        (-b, gun, z), (-b * 0.97, 0.62, z), (-b * 0.60, 0.42, z),
        (0.0, 0.38, z),
        (b * 0.60, 0.42, z), (b * 0.97, 0.62, z), (b, gun, z),
    ]

def build_hull():
    verts = []
    faces = []
    fmats = []
    smooth = []

    def add_verts(points):
        base = len(verts)
        verts.extend(points)
        return base

    # outer loft
    outer_bases = [add_verts(outer_profile(st)) for st in STATIONS]
    for i in range(len(STATIONS) - 1):
        for j in range(8):
            faces.append((outer_bases[i] + j, outer_bases[i] + j + 1,
                          outer_bases[i + 1] + j + 1, outer_bases[i + 1] + j))
            fmats.append(OUT_SEG_MATS[j])
            smooth.append(True)
    # inner loft
    inner_bases = [add_verts(inner_profile(st)) for st in INNER_STATIONS]
    for i in range(len(INNER_STATIONS) - 1):
        for j in range(6):
            faces.append((inner_bases[i] + j, inner_bases[i + 1] + j,
                          inner_bases[i + 1] + j + 1, inner_bases[i] + j + 1))
            fmats.append(IN_SEG_MATS[j])
            smooth.append(True)
    # gunwale caps: pair outer top endpoints with inner top endpoints
    cap_pairs = [  # (outer station idx, inner station idx) matched by z
        (0, 0), (1, 1), (2, 2), (3, 3), (4, 4), (5, 5), (6, 6),
    ]
    for side_pt, side_sign in ((0, -1), (8, 1)):
        inner_pt = 0 if side_sign < 0 else 6
        for k in range(len(cap_pairs) - 1):
            o0 = outer_bases[cap_pairs[k][0]] + side_pt
            o1 = outer_bases[cap_pairs[k + 1][0]] + side_pt
            i0 = inner_bases[cap_pairs[k][1]] + inner_pt
            i1 = inner_bases[cap_pairs[k + 1][1]] + inner_pt
            faces.append((o0, o1, i1, i0))
            fmats.append("HullWhite")
            smooth.append(False)
    # stern fans (outer + inner transom faces) — single ngons
    faces.append(tuple(outer_bases[0] + j for j in range(9)))
    fmats.append("HullWhite")
    smooth.append(False)
    faces.append(tuple(inner_bases[0] + j for j in range(7)))
    fmats.append("HullWhite")
    smooth.append(False)
    # stern rim strips between outer and inner profiles
    for j in range(8):
        faces.append((outer_bases[0] + j, inner_bases[0] + min(j, 6),
                      inner_bases[0] + min(j + 1, 6), outer_bases[0] + j + 1))
        fmats.append(OUT_SEG_MATS[j])
        smooth.append(False)
    # bow bulkhead: fan across the last inner profile (ngon)
    faces.append(tuple(inner_bases[-1] + j for j in range(7)))
    fmats.append("DeckGray")
    smooth.append(False)

    return make_mesh("Hull", verts, faces, fmats, smooth)

def prism(name, bottom, top, mat):
    """bottom/top: lists of (x, z) footprints at heights bottom_y/top_y encoded
    as (points, y). Simple 4-sided tapered prism."""
    bp, by = bottom
    tp, ty = top
    verts = [(x, by, z) for (x, z) in bp] + [(x, ty, z) for (x, z) in tp]
    n = len(bp)
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    faces.append(tuple(range(n - 1, -1, -1)))
    faces.append(tuple(range(n, 2 * n)))
    return make_mesh(name, verts, faces, [mat] * len(faces),
                     [True] * (len(faces) - 2) + [False, False])

def build_details():
    # ---- bow deck (tapered prism following the bow) + orange hatch ----
    deck_verts = []
    deck_faces = []
    deck_st = [  # (z, half_width, y_top)
        (1.90, 0.98, 1.19), (2.50, 0.72, 1.21), (3.02, 0.38, 1.23), (3.28, 0.05, 1.24),
    ]
    for (z, w, y) in deck_st:
        deck_verts += [(-w, y - 0.10, z), (w, y - 0.10, z), (w, y, z), (-w, y, z)]
    # sides + top strips between consecutive stations (4 pts per station)
    for i in range(len(deck_st) - 1):
        b0 = i * 4
        b1 = (i + 1) * 4
        deck_faces += [
            (b0 + 0, b1 + 0, b1 + 3, b0 + 3),   # port side
            (b0 + 1, b0 + 2, b1 + 2, b1 + 1),   # starboard side
            (b0 + 3, b1 + 3, b1 + 2, b0 + 2),   # top
            (b0 + 0, b0 + 1, b1 + 1, b1 + 0),   # bottom
        ]
    deck_faces.append((0, 3, 2, 1))
    last = (len(deck_st) - 1) * 4
    deck_faces.append((last + 0, last + 1, last + 2, last + 3))
    make_mesh("BowDeck", deck_verts, deck_faces,
              ["ConsoleWhite"] * len(deck_faces),
              [False] * len(deck_faces))
    box("OrangeHatch", (0, 1.30, 2.62), (0.62, 0.10, 0.85), "OrangeHatch", bevel=0.03)

    # ---- centre console (tapered prism) + windshield + dash + wheel ----
    prism("Console",
          ([(-0.46, 0.02), (0.46, 0.02), (0.46, 0.60), (-0.46, 0.60)], 0.42),
          ([(-0.39, 0.10), (0.39, 0.10), (0.39, 0.56), (-0.39, 0.56)], 1.34),
          "ConsoleWhite")
    box("Windshield", (0, 1.52, 0.50), (0.78, 0.46, 0.04), "GlassWindshield",
        bevel=0.01, rot_g_deg=(-16, 0, 0))
    box("DashPanel", (0.10, 1.30, 0.16), (0.44, 0.22, 0.05), "BlackParts")
    cylinder_between("WheelColumn", (-0.22, 1.18, 0.10), (-0.22, 1.30, -0.02),
                     0.028, "BlackParts")
    torus("SteeringWheel", (-0.22, 1.34, -0.05), 0.19, 0.022, "BlackParts",
          rot_b_deg=(65, 0, 0))

    # ---- benches with teal cushions ----
    box("MidBenchBase", (0, 0.60, 1.58), (1.80, 0.38, 0.52), "ConsoleWhite", bevel=0.03)
    box("MidBenchCushion", (0, 0.84, 1.58), (1.74, 0.12, 0.46), "VinylTeal", bevel=0.04)
    box("SternBenchBase", (0, 0.58, -2.52), (1.84, 0.34, 0.50), "ConsoleWhite", bevel=0.03)
    box("SternBenchCushion", (0, 0.80, -2.52), (1.78, 0.12, 0.44), "VinylTeal", bevel=0.04)

    # ---- wooden crate + slats (sits ON the mid bench, like the photo) ----
    box("Crate", (0.18, 1.06, 1.58), (0.82, 0.34, 0.44), "WoodBrown", bevel=0.015)
    for dz in (-0.16, 0.16):
        box("CrateSlat", (0.18, 1.24, 1.58 + dz), (0.86, 0.05, 0.07), "CrateDark")
    box("Cooler", (-0.55, 0.60, -0.85), (0.62, 0.36, 0.42), "VinylTeal", bevel=0.03)
    box("CoolerLid", (-0.55, 0.80, -0.85), (0.64, 0.06, 0.44), "ConsoleWhite", bevel=0.02)

    # ---- gunwale rub rail strips (dark) along the top outer edge ----
    for sign in (-1, 1):
        pts = []
        for st in STATIONS[:-1]:
            z, b, keel, chine, gun = st
            pts.append((sign * (b + 0.01), gun - 0.03, z))
        for i in range(len(pts) - 1):
            cylinder_between("RubRail", pts[i], pts[i + 1], 0.035, "BlackParts", vertices=8)

    # ---- bow rail (metal) ----
    rail_pts = [(-0.62, 1.24, 2.95), (-0.60, 1.58, 3.02), (0.0, 1.62, 3.18),
                (0.60, 1.58, 3.02), (0.62, 1.24, 2.95)]
    for i in range(len(rail_pts) - 1):
        cylinder_between("BowRail", rail_pts[i], rail_pts[i + 1], 0.028, "MetalRail")

    # ---- cleats ----
    for (x, z) in ((-0.95, -2.95), (0.95, -2.95), (-0.55, 2.90), (0.55, 2.90)):
        box("Cleat", (x, 1.24, z), (0.20, 0.05, 0.06), "MetalRail", bevel=0.015)

    # ---- nav lights (port red / starboard green) ----
    sphere("NavLightPort", (-0.86, 1.16, 2.45), (0.055, 0.055, 0.055), "NavRed")
    sphere("NavLightStbd", (0.86, 1.16, 2.45), (0.055, 0.055, 0.055), "NavGreen")

    # ---- fishing rods (stern holders, tips up/back) ----
    cylinder_between("Rod1", (-0.58, 0.95, -2.90), (-0.78, 2.55, -3.55), 0.016, "BlackParts")
    cylinder_between("Rod2", (-0.36, 0.95, -2.92), (-0.44, 2.70, -3.70), 0.016, "BlackParts")
    box("Reel1", (-0.63, 1.25, -3.05), (0.10, 0.13, 0.06), "MetalRail", bevel=0.02)
    box("Reel2", (-0.39, 1.28, -3.08), (0.10, 0.13, 0.06), "MetalRail", bevel=0.02)

    # ---- life ring on console side ----
    torus("LifeRing", (0.48, 1.05, 0.32), 0.17, 0.05, "OrangeHatch", rot_b_deg=(0, 90, 0))

    # ---- outboard motor on the transom ----
    box("MotorCowling", (0, 1.06, -3.38), (0.46, 0.62, 0.34), "MotorDark", bevel=0.09)
    box("MotorShaft", (0, 0.48, -3.40), (0.13, 0.62, 0.10), "MotorDark", bevel=0.02)
    box("MotorFin", (0, 0.16, -3.46), (0.04, 0.22, 0.30), "MotorDark", bevel=0.01)
    cylinder_between("PropHub", (0, 0.30, -3.52), (0, 0.30, -3.62), 0.035, "MetalRail")
    box("PropBlade", (0, 0.30, -3.60), (0.03, 0.30, 0.03), "MetalRail", rot_g_deg=(0, 0, 30))
    box("MotorClamp", (0, 0.92, -3.26), (0.30, 0.14, 0.10), "BlackParts")

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    build_hull()
    build_details()
    os.makedirs(OUT_DIR, exist_ok=True)
    obj_path = os.path.join(OUT_DIR, "boat.obj")
    bpy.ops.wm.obj_export(filepath=obj_path, export_selected_objects=False,
                          apply_modifiers=True, export_materials=True,
                          export_smooth_groups=False, smooth_group_bitflags=False,
                          forward_axis='Z', up_axis='Y', path_mode='COPY')
    # stats
    total_v = 0
    total_p = 0
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            total_v += len(o.data.vertices)
            total_p += len(o.data.polygons)
    print("BOAT_EXPORT_DONE", obj_path, os.path.getsize(obj_path),
          "verts=", total_v, "polys=", total_p,
          "objects=", len(bpy.context.scene.objects),
          "materials=", len(bpy.data.materials))

if __name__ == "__main__":
    main()
