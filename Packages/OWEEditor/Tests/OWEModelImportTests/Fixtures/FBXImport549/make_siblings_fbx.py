# Blender: armature "Rig" with root plus TWO sibling chains (armL1 > armL2, armR1 > armR2), a mesh skinned
# to all four chain bones, and one action "flap" (both chains rotate 0 -> 45 deg -> 0 over 30 frames).
# Run: blender -b -P make_siblings_fbx.py -- siblings.fbx
import bpy, sys, math
out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene; sc.render.fps = 30; sc.frame_start = 0; sc.frame_end = 30
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm = bpy.context.object; arm.name = "Rig"
eb = arm.data.edit_bones; root = eb[0]; root.name = "root"; root.head = (0, 0, 0); root.tail = (0, 0, 0.5)
def b(n, h, t, p):
    x = eb.new(n); x.head = h; x.tail = t; x.parent = p; return x
l1 = b("armL1", (0, 0, 0.5), (-1, 0, 0.5), root); b("armL2", (-1, 0, 0.5), (-2, 0, 0.5), l1)
r1 = b("armR1", (0, 0, 0.5), (1, 0, 0.5), root); b("armR2", (1, 0, 0.5), (2, 0, 0.5), r1)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.5)); m = bpy.context.object; m.name = "Bar"
m.scale = (4, 0.3, 0.3); bpy.ops.object.transform_apply(scale=True)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.subdivide(number_cuts=7); bpy.ops.object.mode_set(mode="OBJECT")
g = {n: m.vertex_groups.new(name=n) for n in ("armL1", "armL2", "armR1", "armR2")}
for v in m.data.vertices:
    x = v.co.x; n = ("armL2" if x < -1 else "armL1") if x < 0 else ("armR2" if x > 1 else "armR1")
    g[n].add([v.index], 1.0, "REPLACE")
mod = m.modifiers.new("Armature", "ARMATURE"); mod.object = arm; m.parent = arm
bpy.context.view_layer.objects.active = arm; bpy.ops.object.mode_set(mode="POSE")
arm.animation_data_create(); ac = bpy.data.actions.new("flap"); arm.animation_data.action = ac
for n in ("armL1", "armR1"):
    pb = arm.pose.bones[n]; pb.rotation_mode = "XYZ"
    for f in (0, 15, 30):
        pb.rotation_euler = (0, 0, math.radians(45) * math.sin(math.pi * f / 30) * (1 if n == "armL1" else -1)); pb.keyframe_insert("rotation_euler", frame=f)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.export_scene.fbx(filepath=out, use_selection=False, add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False)
