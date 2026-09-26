#include <metal_stdlib>
using namespace metal;

// A Puppet Warp image's albedo target (`ScenePuppetRenderer`). The mesh is drawn premultiplied
// into a float scratch target, so overlapping triangles composite like WE's straight-alpha draws
// over each other; this writes it back as the straight-alpha image the layer's material, effects
// and native draw sample, in the layer image's own texture layout: the image in the top-left
// `content` texels, the padding around it transparent.
kernel void scenePuppetUnpremultiply(texture2d<float, access::read> scratch [[texture(0)]],
                                     texture2d<float, access::write> target [[texture(1)]],
                                     constant uint2 &content [[buffer(0)]],
                                     uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) {
        return;
    }
    float4 color = float4(0.0);
    if (gid.x < content.x && gid.y < content.y) {
        color = scratch.read(gid);
        color.rgb = color.a > 0.0 ? saturate(color.rgb / color.a) : float3(0.0);
    }
    target.write(color, gid);
}
