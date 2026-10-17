# Blender script: a static 1x1x1 cube centred on its origin ,
# exported as FBX. Run: blender -b -P make_centered_cube_fbx.py -- centered_cube.fbx
import bpy, sys
out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
o = bpy.context.object; o.name = "CenteredCube"
bpy.ops.export_scene.fbx(filepath=out, use_selection=False, add_leaf_bones=False, bake_anim=False)
