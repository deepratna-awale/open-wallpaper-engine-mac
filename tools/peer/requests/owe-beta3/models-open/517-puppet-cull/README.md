# §5.51.7-puppet-cull

WE 2.8.0.42. Projects come from `../build_variants.py`, shot on monitor 2 by `../shoot_all.ps1`. The Windows taskbar covers the bottom 48 px.

The rope puppet (from the bone-physics request), with its material pass `cullmode` set to `normal`.

- **Scale 1 1 1:** draws normally.
- **Scale -1 1 1:** **disappears**, because it is culled. The flip reverses the winding, and WE does not compensate.
