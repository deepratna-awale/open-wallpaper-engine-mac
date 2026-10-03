# §5.24 bone angle units: **radians**

## Setup
- **Puppet:** the rope puppet (`mo_probe`, from the bone-physics B variant: translation physics only).
- **Script:** an origin script (`probe-script.js`) logs `getLocalBoneAngles('tail')` and `getLocalBoneAngles(1)` every 0.5 s in the editor's Run Preview.

## Results
- **Before:** the tail's bind angles are 0 0 0, and it logs `0,0,0` (`probe_log_bind0.txt`).
- **After:** I set the tail's **Angles Z = 90** in the Skeleton editor, then Confirm and Save.
  - It logs **`0.0000,0.0000,1.5708`** for both `'tail'` and index `1` (`probe_log_bind90.txt`).
  - The compiled `rope_puppet.json` stores `"angles": "0 -0 1.57080"`.
- **Conclusion:** the editor shows degrees, while the stored and scripted values are **radians**.
- **Bone index:** a numeric index works in place of the name, and index 1 = tail.
