# Puppet Warp Texture Channels: WE 2.8.42 ground truth (OFF vs ON)

- **Puppet:** the rope (96x512) with 2 bones (bone-physics A variant), project `mo_tc_off` vs `mo_tc_on`, identical except for one added channel.
- **Folders:** `off/` and `on/` hold scene.json, project.json, materials/ and models/ (puppet json and .mdl).

## UI
- **Where:** Puppet Warp → Optional → **Texture Channels** opens the "Texture Channels Configuration" dialog.
- **Contents:** a Channels list (the default entry "Puppet"), **+ Add Channel** (a file picker for png/tga/jpg/jpeg), Move Up/Down, Replace Texture, and the **Alpha writing** checkbox (on by default). There's a live preview on the right.
- **Requirement:** the dialog only works when the puppet's **source PNG exists next to its .tex** (`materials/rope.png`).
  - Without it, `prepareTextureChannelEditing` fails silently: the preview stays empty, and Add/Replace accept the file but do nothing.
- **Test channel:** `rope_channel2.png`, a recoloured copy of the rope (RGBA, the same 96x512).

## Files written when the channel is added
- **`materials/rope_channelmap.json`:**
  ```
  {"passes":[{"blending":"normal","combos":{"BLENDROWCOUNT":1},"cullmode":"nocull","depthtest":"disabled","depthwrite":"disabled","shader":"puppettexturechannels","textures":["rope_channelmap","rope"]}]}
  ```
  So g_Texture0 = the channel atlas and g_Texture1 = the base texture.
- **`materials/rope_channelmap.png`** (64x512 RGB) and `.tex` / `.tex-json` (`clampuvs`, rgba8888, nomip, nonpoweroftwo).
  - It's the channel image's opaque crop: x 16–80, the rope bar.
- **Puppet json:** gains a top-level block:
  ```
  "texturechannels": {"channels":[{"defaultlabel":"rope_channel2","elements":[{"flipped":false,"posx0":16,"posx1":80,"posy0":512,"posy1":0,"uvx0":0,"uvx1":1,"uvy0":1,"uvy1":0}],"id":22,"name":"","texture":"materials/rope_channel_170324fc.png"}],"material":"materials/rope_channelmap.json"}
  ```
  - `elements`: the crop rectangle in base-image pixels (`pos*`) and the matching atlas UVs (`uv*`).
  - The puppet's base `material` and `texture` keys are unchanged.
  - Alpha writing isn't stored here when on (the default). Only off is presumably written.

## MDLV difference (`off/` vs `on/` .mdl, both MDLV0023)
- **Size:** 40226 → 40494 bytes.
- **Mesh flag:** the **u32 at 0x11** (right after the 13-byte header `MDLV0023\0 09 00 80 01 01 00 00 00`) goes **1 → 2**. This is the mesh flag 0x2 path (BLENDROWCOUNT / g_BlendMap / a_BlendIndices).
- **Second material:** the ON .mdl has a second material string, `materials/rope_channelmap.json`, at 0x9941, before `MDLS0004`.
- **Diff count:** 891 differing bytes in total, mostly the vertex stream, which gains blend data (`a_TexCoordVec4` plus `uvec4 a_BlendIndices`).

## Not captured yet
- On/off stills and RenderDoc of the puppettexturechannels draw.
- **Why:** the PC is being used by someone, and both need the screen. The files above are all ground truth from WE's own editor.
