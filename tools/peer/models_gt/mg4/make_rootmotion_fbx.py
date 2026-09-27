# Blender (background) script: a box skinned to a single root bone whose 1 s clip (30 fps) translates the root by
# (1,2,3)*t and rotates it by (0.3,0.6,0.9)*t rad. Exported as FBX for WE's model importer (root-motion test, MG4).
import bpy, math, sys

out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start, scene.frame_end = 0, 30

# armature with one root bone pointing up
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm = bpy.context.object
arm.name = "Rig"
eb = arm.data.edit_bones[0]
eb.name = "root"
eb.head, eb.tail = (0, 0, 0), (0, 0, 1)
bpy.ops.object.mode_set(mode="OBJECT")

# red box offset from the origin so rotation is visible
bpy.ops.mesh.primitive_cube_add(size=0.5, location=(0, 0, 0.75))
box = bpy.context.object
box.name = "Box"
mat = bpy.data.materials.new("red"); mat.diffuse_color = (1, 0, 0, 1)
box.data.materials.append(mat)
vg = box.vertex_groups.new(name="root")
vg.add(list(range(len(box.data.vertices))), 1.0, "REPLACE")
mod = box.modifiers.new("Armature", "ARMATURE"); mod.object = arm
box.parent = arm

# 1 s clip on the root bone
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
pb = arm.pose.bones["root"]
pb.rotation_mode = "XYZ"
for f in (0, 30):
    t = f / 30.0
    pb.location = (1 * t, 2 * t, 3 * t)
    pb.rotation_euler = (0.3 * t, 0.6 * t, 0.9 * t)
    pb.keyframe_insert("location", frame=f)
    pb.keyframe_insert("rotation_euler", frame=f)
act = arm.animation_data.action
act.name = "move"
for fc in getattr(act, "fcurves", []):
    for kp in fc.keyframe_points:
        kp.interpolation = "LINEAR"
bpy.ops.object.mode_set(mode="OBJECT")

bpy.ops.export_scene.fbx(filepath=out, use_selection=False, add_leaf_bones=False, bake_anim=True,
                         bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False, object_types={"ARMATURE", "MESH"})
print("EXPORTED", out)
