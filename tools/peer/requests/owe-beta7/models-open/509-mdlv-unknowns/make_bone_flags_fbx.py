# Blender (background) script, the same flow as models_gt/mg4/make_rootmotion_fbx.py:
#   blender -b -P make_bone_flags_fbx.py -- bone_flags.fbx
# An armature "Rig" with the chain root -> mid -> tip, and an extra bone "loose" (child of root) that no
# vertex is weighted to. The box is weighted to root (lower half) and mid (upper half). An empty "Pivot"
# sits between the scene root and the armature. It asks which of these nodes WE's importer marks with
# MDLS bone flag 0x1: the library has flag 0 only on non-bone nodes (RootNode, the object and the
# armature node) and flag 1 on every armature bone, unweighted leaves included.
import bpy, sys

out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start, scene.frame_end = 0, 30

bpy.ops.object.empty_add(location=(0, 0, 0))
pivot = bpy.context.object
pivot.name = "Pivot"

bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm = bpy.context.object
arm.name = "Rig"
eb = arm.data.edit_bones
root = eb[0]; root.name = "root"; root.head, root.tail = (0, 0, 0), (0, 0, 0.5)
mid = eb.new("mid"); mid.head, mid.tail = (0, 0, 0.5), (0, 0, 1.0); mid.parent = root
tip = eb.new("tip"); tip.head, tip.tail = (0, 0, 1.0), (0, 0, 1.3); tip.parent = mid
loose = eb.new("loose"); loose.head, loose.tail = (0, 0, 0.25), (0.4, 0, 0.25); loose.parent = root
bpy.ops.object.mode_set(mode="OBJECT")
arm.parent = pivot

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.5))
box = bpy.context.object
box.name = "Box"
box.scale = (0.3, 0.3, 1.0)
bpy.ops.object.transform_apply(scale=True)
mat = bpy.data.materials.new("white"); mat.diffuse_color = (1, 1, 1, 1)
box.data.materials.append(mat)
g_root, g_mid = box.vertex_groups.new(name="root"), box.vertex_groups.new(name="mid")
for v in box.data.vertices:
    (g_mid if v.co.z > 0.5 else g_root).add([v.index], 1.0, "REPLACE")
mod = box.modifiers.new("Armature", "ARMATURE"); mod.object = arm
box.parent = arm

# a 1 s clip that bends mid so the import has an animation
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
pb = arm.pose.bones["mid"]
pb.rotation_mode = "XYZ"
for f, a in ((0, 0.0), (15, 0.6), (30, 0.0)):
    pb.rotation_euler = (a, 0, 0)
    pb.keyframe_insert("rotation_euler", frame=f)
arm.animation_data.action.name = "bend"
bpy.ops.object.mode_set(mode="OBJECT")

bpy.ops.export_scene.fbx(filepath=out, use_selection=False, add_leaf_bones=False, bake_anim=True,
                         bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False,
                         object_types={"EMPTY", "ARMATURE", "MESH"})
print("EXPORTED", out)
