# §5.21 `{"autosize": true}` image and scripts; missing `size`

## Script vs auto size
- **Setup:** the image's model has `"autosize": true`. Its origin script sets `x = 960 + 60·t` every frame.
- **Result:** the image **moves with the script**. Its bounds are x 765–1634 at t ≈ 4 s and x 942–1811 at t ≈ 7 s: about 59 px/s against 60 px/s set.
- **Conclusion:** WE does not re-centre it each frame, and the script wins.

## No `size`
- **Setup:** the same image, with `"size"` removed from the scene object.
- **Result:** it draws **identically to the control** (`mo_513_control.png`): x 525–1394, y 105–974.
- **Conclusion:** the size comes from the texture (1024×1024, drawn at scale 0.85 = 870 px). The scene stays 1920×1080, from orthogonalprojection.
