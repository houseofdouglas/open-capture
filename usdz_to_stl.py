# Headless Blender: USDZ -> keep largest part -> voxel remesh -> STL
# Usage: blender -b -P cleanup.py -- input.usdz output.stl
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=src)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    sys.exit("no meshes imported")

bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# split into loose parts, keep the biggest (drops floating artifact blobs)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="LOOSE")
bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.data.objects if o.type == "MESH"]
parts.sort(key=lambda o: len(o.data.vertices), reverse=True)
keep, drop = parts[0], parts[1:]
print(f"parts: {[(o.name, len(o.data.vertices)) for o in parts]}")
for o in drop:
    bpy.data.objects.remove(o, do_unlink=True)

# voxel remesh: watertight, uniform. ~350 voxels across the largest dimension
bpy.context.view_layer.objects.active = keep
keep.select_set(True)
size = max(keep.dimensions)
keep.data.remesh_voxel_size = size / 350
bpy.ops.object.voxel_remesh()
print(f"dimensions (m): {tuple(round(d, 4) for d in keep.dimensions)}")
print(f"verts after remesh: {len(keep.data.vertices)}")

bpy.ops.wm.stl_export(filepath=dst, export_selected_objects=True,
                      global_scale=1000.0)  # meters -> mm for slicers
print("STL written:", dst)
