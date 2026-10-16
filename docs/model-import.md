# Model import and the Model Editor

How the Wallpaper Editor imports FBX and OBJ models as Wallpaper Engine (2.3 and later) does,
what it writes, and what is still a guess. The `.mdl` format itself is in
[`models-plan.md`](models-plan.md) §1.

## What Wallpaper Engine does

Sources: WE 2.8.0.42's install (`bin/resourcecompiler64.exe`, `bin/wallpaperui.exe`,
`ui/dist/scripts/scripts.js`), its default projects (`projects/defaultprojects/*/models/`, which
keep each model's source, configuration and compiled `.mdl` side by side), the library's
imported models, and the docs at docs.wallpaperengine.io/en/scene/models/.

- **Import.** Add Asset › Model (or a model dropped on New Project) copies the source into the
  project, writes its configuration `models/<name>.json` and compiles the `.mdl` with
  `resourcecompiler64.exe -mdl`, which reads the source with **Assimp**
  (`assimp-vc143-mt64.dll`; it accepts `.obj .fbx .blend .dae .3ds .lxo .gltf`). The docs ask for
  FBX, or OBJ for simple models without animation, −Z forward and +Y up, and textures beside
  the model. The editor recompiles a model whose `.mdl` isn't the writer's current version
  (`MDLV0023`, models-plan §1.1) before it uses it.
- **Configuration keys** (the default projects' files and the binaries' strings): `normals`,
  `tangentspace`, `seconduvchannel`, `skins` (a list of `{material: replacement}`, one material
  per skin and mesh), `additionalfiles` (Add FBX File), `clips` (`start`, `end`, `frameoffset`,
  `matchloop`, `rootmotion`, `motionflags`), `events`, `attachments`, `constraints`,
  `animationmapping`, `rootnode`. WE's importer writes `normals` and `tangentspace` as true
  (`wallpaperui.exe`: "Failed writing obj configuration"); a model without a configuration gets
  neither (the default projects' `techno/glow.mdl`, format 0x9).
- **Materials.** Each mesh material becomes `materials/models/<model>/<material>.json` with
  WE's `generic4` pass (`wallpaperui.exe`'s template: depth test and write on, back faces
  culled) and its albedo texture named after the material
  (`models/<model>/<material>`; PaRappa's imported models: `materials/models/pj/pjberri_minion_body_d (Texture 0).json`).
  Advanced Texture Settings then edits the material: lighting, reflection, rim lighting, toon
  shading, tint mask, and the albedo, normal and PBR maps (metallic, roughness, reflection,
  emissive; `generic4`'s annotations).
- **The Model Editor** (Configure Model; `views/modals/editormodeleditormodal.html` and
  `EditorModelEditorModalCtrl` in `scripts.js`) has four tabs: **Animation** (the source's
  animations with Add Clip, the FBX files with Add FBX File, the clips and their options),
  **Attachments** (Add Attachment; bone, name, origin), **Events** (per animation or clip:
  Add Event, name, frame) and **Constraints** (the bones, each with the bone-physics settings
  Puppet Warp uses, presets, Reset, Copy and Paste). **Blend Layers and Transitions are
  commented out** in WE 2.8.0.42's template: their strings exist
  (`ui_editor_model_editor_tab_blend_layers`, `…_tab_transitions`) but the tabs are empty and
  hidden, so they have no storage format to follow. A model layer's own animation layers
  (`animationlayers` in scene.json, blended by `blend`, `blendin`, `blendout`) are the scene's,
  not the model's.

## What the Wallpaper Editor does

- **Reading** (`Packages/OWEEditor`, module `OWEModelImport`): ufbx (`Vendor/ufbx`, v0.23.1,
  MIT) reads FBX and OBJ (with its `.mtl`) in the file's own axes and units, as WE keeps an
  FBX's node transforms (Blender's 100× scale and −90° turn) in its nodes. `.blend`, `.dae`,
  `.3ds`, `.lxo` and `.gltf` aren't read.
- **Compiling** (`OWESceneEditing/Models/ModelCompiler`), Assimp's steps as WE runs them:
  polygons fan from their first corner (a quad from its concave corner, by Assimp's angle
  test); a static model's parts with one material are one mesh, in material order (Assimp's
  PreTransformVertices: an OBJ's in its `.mtl` order, an FBX's in first use), its vertices
  baked into model space; texture coordinates flip (v → 1 − v); a mesh without normals gets
  smooth ones (GenSmoothNormals); the tangent space is the file's own, else Assimp's
  CalcTangentSpace (per triangle, then smoothed over corners within 1e-4 of the box diagonal
  whose normals agree to 0.9999 and tangents to 45°), with w the sign of (N × T) · B; corners are
  joined when position and influences match and every other attribute, the tangent space
  included, is within 1e-5. Normals are written with `normals`, tangents with `tangentspace`,
  and `seconduvchannel` packs both UV sets into `a_TexCoordVec4` (format 0x27).
- **Ground truth:** `WEDefaultProjectModelTests` compiles every source of WE's default projects
  (`OWE_WE_INSTALL`, the `wallpaper_engine` folder; skipped without it) and compares formats,
  vertices and indices with WE's `.mdl`s. 27 of the 34 meshes match WE's (format, vertex count,
  indices; 7 byte for byte, the rest within 0.0002 in their floats); the 7 exceptions are
  listed in the test (which of two near-equal corners Assimp keeps, and its smoothing's ties at
  exactly 45°, depend on its spatial sort's order; three OBJs without a configuration are
  `MDLV0014`-era output that WE compiles anew).
- **Skinned models** keep the nodes the skin needs (the root as "RootNode", every bone and its
  ancestors), bone flag 1 on armature bones and on nodes a skin uses, each bone's local matrix,
  and the mesh skinned into the rest pose (four influences, the largest, renormalised). The
  `MDLS0004` per-bone block is each bone's box in its bind space (half size, then the centre as
  a translation), which PaRappa's `windows_front.mdl` matches. Every animation stack is sampled
  at the file's frame rate into an `MDLA0006` record (one track per bone; the animated box over
  every frame).
- **Files** (`EditorAssetStore+Models`, `EditorModelImporter`): the model's folder is
  `<name>-<hash of the source>`; the source (and an OBJ's `.mtl`), `<name>.json`, `<name>.mdl`,
  and `materials/models/<folder>/<material>.json` with its texture (PNG or JPEG as it is, other
  images as PNG; found where the model names it, then by name beside the model; missing ones
  draw WE's white and are reported). The store never overwrites, so a configuration the Model
  Editor compiles is `<name>-<hash>.json` and `.mdl`.

## The Model Editor here

`OWEEditor/ModelEditor/` (`ModelEditorView`, `ModelEditorModel`), opened from a model layer's
inspector (Configure Model…) when the model's source is with the edits' files. It edits the
configuration (`ModelImportConfig`) and compiles with it to fill its lists
(`EditorModelImporter.inspect`); OK keeps edited materials, compiles the model again
(`recompile`, a `<name>-<hash>.mdl`) and points every layer drawing the old model at it
(`SceneEditSession.replaceModel`), one undo step.

- **Animation, Attachments, Events, Constraints:** WE's tabs and options (above). WE's clip
  options have no frame rate or playback mode (a clip keeps its animation's rate and loops);
  this editor offers both because `MDLA` stores them per clip. WE previews the model in the
  modal; here the play button plays a clip or animation on the layer itself, as WE's Skeletal
  animation › Add makes an animation layer (`animationlayers`: rate 1, blend 1).
- **Materials:** WE's Advanced Texture Settings, as a tab. The shader's combos, texture slots
  and constants come from its annotations (`ModelShaderSchema`, the `// [COMBO]` lines and the
  `uniform` comments of `shaders/<shader>.frag` and `.vert` read where the scene reads them), and
  the edited pass is kept as a new material file (`materials/models/<folder>/<material>-<hash>.json`)
  that the configuration's `materials` map names (ours: WE edits the material file in place,
  which the edits' files never do).
- **Blend Layers and Transitions:** not offered; WE 2.8.0.42 has them commented out, with no
  storage format.
- **Clean Project** keeps a used model's materials (the paths in the `.mdl`), configuration and
  sources (`ProjectCleaner.collectModelNames`).

## Guessed fields

What WE's own files didn't show, so the writer writes WE's common case:

| Field | Written | Why |
|---|---|---|
| `MDLS` version | `MDLS0004`, `MDLA0006` | The library's skinned FBX imports are `MDLV0021` with `MDLS0003`; WE's current writer tags puppets `MDLS0004`, and with no constraints the two lay out the same. |
| Animation ids (`MDLA` u64) | 1, 2, … for the source's animations, then the configuration's ids for clips | PaRappa's are 306 and 307 (the editor's object counter); scenes name them by id, so any stable number works. |
| Animation mode and flags | `"loop"`, 0 | Every imported animation in the library. |
| Clip records | flags 0x1, `matchloop` 0x400, `motionflags` << 8; the clip's own frames cut from the source | models-plan §2.8 (MG4); the configuration's clip layout is ours. |
| Configuration records | `clips`, `events`, `attachments` as objects with `id`, `name` and the keys above; `constraints` by bone name with Puppet Warp's keys | Key names from the binaries; their layout from no file. |
| Bone properties | Puppet Warp's compiled physics keys, nothing for other bones | As `PuppetMDLWriter`. |
| Mesh flags | 0, or 1 for 32-bit indices | The library's imports. |
| `MDLV` 21/23 blobs and groups | none | Every imported model in the library. |
| A static mesh in a skinned model | bound to the root with weight 1 | No library file has one. |
| Scale on import | the layer's scale 1 | The docs say WE normalises the size on import; its rule isn't known. |

## Needs a capture in WE

- Import an FBX with a skinned armature, two animations and a static mesh, then Add Clip
  (start 10, end 20, root motion on), an event, an attachment and a constraint, and diff the
  `.mdl` and `models/<name>.json` against this writer's: ids, `MDLS` version, the configuration's
  record layout, the static mesh's binding.
- Import a large OBJ and FBX to see the scale WE gives the new layer.
- Recompile `bars.obj`, `flow.obj`, `dome.obj` and `pistols.fbx` in WE 2.8 and compare with
  `WEDefaultProjectModelTests`' known divergences.
