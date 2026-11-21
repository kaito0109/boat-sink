# Blender 4.5 — semi-auto pistol viewmodel for Boat Sink v3.
# Authored in Godot coordinates (x=right, y=up, z: muzzle is -Z) and
# converted to Blender coordinates (x, z_godot, y_godot) for modelling.
# OBJ is exported with axis_forward='Z', axis_up='Y' (same as the boat).
# Run: blender --background --python tools/build_pistol.py
import bpy
import math
import os
from mathutils import Vector

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
OUT_DIR = os.path.normpath(OUT_DIR)

MAT_DEFS = {
    # name: (r, g, b, roughness, metallic)
    "SteelDark":  (0.14, 0.15, 0.17, 0.38, 0.85),
    "SteelLight": (0.35, 0.37, 0.40, 0.30, 0.90),
    "Polymer":    (0.045, 0.045, 0.05, 0.62, 0.10),
    "GripPanel":  (0.08, 0.08, 0.085, 0.88, 0.0),
    "BlackHole":  (0.008, 0.008, 0.01, 0.90, 0.0),
    "Brass":      (0.42, 0.30, 0.12, 0.38, 0.90),
    "OrangeDot":  (0.95, 0.35, 0.05, 0.50, 0.0),
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
        if name == "OrangeDot":
            bsdf.inputs["Emission Color"].default_value = (r, g, b, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 1.6
        MATS[name] = m

def G(p):
    return (p[0], p[2], p[1])

def assign_mats(obj, names):
    for n in names:
        obj.data.materials.append(MATS[n])

def box(name, pos, size, mat, bevel=0.0, rot_g_deg=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=G(pos))
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rot_g_deg != (0, 0, 0):
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

def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    # --- slide (steel) ---
    box("Slide", (0, 0.045, -0.005), (0.042, 0.038, 0.215), "SteelDark", bevel=0.006)
    # rear slide serrations: vertical ribs on both sides of the slide
    for i in range(5):
        z = 0.058 + i * 0.0075
        box("SerrationL", (-0.0214, 0.045, z), (0.002, 0.024, 0.0032), "SteelLight")
        box("SerrationR", (0.0214, 0.045, z), (0.002, 0.024, 0.0032), "SteelLight")
    # ejection port (right side) with a hint of brass barrel hood inside
    box("EjectionPort", (0.0212, 0.048, -0.015), (0.002, 0.016, 0.052), "BlackHole")
    box("BarrelHood", (0.0219, 0.048, -0.015), (0.0012, 0.008, 0.032), "Brass")
    # muzzle: barrel hole + crown
    cylinder_between("MuzzleHole", (0, 0.047, -0.114), (0, 0.047, -0.108), 0.0075, "BlackHole", 14)
    cylinder_between("MuzzleCrown", (0, 0.047, -0.1135), (0, 0.047, -0.1115), 0.0105, "SteelLight", 14)
    # sights
    box("RearSightL", (-0.009, 0.0675, 0.086), (0.007, 0.008, 0.013), "BlackHole")
    box("RearSightR", (0.009, 0.0675, 0.086), (0.007, 0.008, 0.013), "BlackHole")
    box("FrontSight", (0, 0.070, -0.096), (0.005, 0.012, 0.007), "BlackHole")
    box("FrontDot", (0, 0.070, -0.0922), (0.0032, 0.005, 0.0012), "OrangeDot")
    # --- frame (polymer) ---
    box("Frame", (0, 0.0125, -0.008), (0.037, 0.029, 0.205), "Polymer", bevel=0.004)
    # accessory rail slots under the front frame
    for i in range(3):
        z = -0.098 + i * 0.016
        box("RailSlot", (0, -0.0135, z), (0.030, 0.004, 0.006), "BlackHole")
    # takedown lever + slide stop + mag release
    cylinder_between("TakedownPin", (-0.020, 0.012, -0.045), (0.020, 0.012, -0.045), 0.004, "SteelLight", 10)
    cylinder_between("MagRelease", (-0.023, -0.006, 0.028), (-0.018, -0.006, 0.028), 0.0055, "SteelDark", 10)
    box("SlideStop", (-0.0205, 0.014, 0.012), (0.003, 0.008, 0.024), "SteelDark")
    # --- trigger guard + trigger ---
    cylinder_between("GuardFront", (0, -0.006, -0.062), (0, -0.032, -0.058), 0.0036, "Polymer", 8)
    cylinder_between("GuardBottom", (0, -0.032, -0.058), (0, -0.030, -0.006), 0.0036, "Polymer", 8)
    cylinder_between("GuardRear", (0, -0.030, -0.006), (0, -0.010, 0.002), 0.0036, "Polymer", 8)
    box("Trigger", (0, -0.020, -0.028), (0.006, 0.024, 0.008), "SteelDark", rot_g_deg=(14, 0, 0))
    # --- grip (angled back ~13 deg) ---
    grip_rot = (13, 0, 0)
    box("Grip", (0, -0.058, 0.046), (0.035, 0.104, 0.050), "Polymer", bevel=0.006, rot_g_deg=grip_rot)
    box("GripPanelL", (-0.0185, -0.058, 0.046), (0.0025, 0.082, 0.040), "GripPanel", rot_g_deg=grip_rot)
    box("GripPanelR", (0.0185, -0.058, 0.046), (0.0025, 0.082, 0.040), "GripPanel", rot_g_deg=grip_rot)
    # beavertail + hammer
    box("Beavertail", (0, -0.002, 0.096), (0.030, 0.012, 0.026), "Polymer", bevel=0.004)
    box("Hammer", (0, 0.018, 0.104), (0.010, 0.022, 0.010), "SteelDark", rot_g_deg=(18, 0, 0))
    # magazine baseplate (follows grip angle, at its bottom)
    box("MagBase", (0, -0.112, 0.0585), (0.039, 0.013, 0.055), "SteelDark", bevel=0.003, rot_g_deg=grip_rot)

def render_preview():
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.device = 'CPU'
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = G((0.30, 0.10, -0.34))
    cam.rotation_mode = 'QUATERNION'
    direction = Vector(G((0, 0.0, 0.0))) - cam.location
    cam.rotation_quaternion = direction.to_track_quat('-Z', 'Y')
    scene.camera = cam
    sun_data = bpy.data.lights.new("sun", 'SUN')
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), math.radians(20), math.radians(-30))
    fill_data = bpy.data.lights.new("fill", 'AREA')
    fill_data.energy = 250.0
    fill_data.shape = 'DISK'
    fill_data.size = 0.6
    fill = bpy.data.objects.new("fill", fill_data)
    scene.collection.objects.link(fill)
    fill.location = G((-0.3, 0.25, 0.25))
    fill.rotation_mode = 'QUATERNION'
    fill.rotation_quaternion = (Vector(G((0, 0, 0))) - fill.location).to_track_quat('-Z', 'Y')
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.62, 0.68, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    scene.render.resolution_x = 640
    scene.render.resolution_y = 480
    scene.render.filepath = os.path.join(OUT_DIR, "..", "shots", "pistol_preview.png")
    bpy.ops.render.render(write_still=True)

def main():
    build()
    obj_path = os.path.join(OUT_DIR, "pistol.obj")
    bpy.ops.wm.obj_export(filepath=obj_path, export_selected_objects=False,
                          export_materials=True, export_uv=True, export_normals=True,
                          forward_axis='Z', up_axis='Y', path_mode='COPY')
    render_preview()
    print("PISTOL_DONE", obj_path)

main()
