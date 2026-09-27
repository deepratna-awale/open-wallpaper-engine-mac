#include <metal_stdlib>
using namespace metal;

/// `ParticleEmitterImagePoints.reduce`: WE's `downsample_quarter` shader with `WRITEALPHA` for one
/// texel of the reduced image, the mean of four bilinear samples two source texels from its
/// centre (clamped at the edges), written as RGBA8. `parameters`: the content's UV extent in the
/// texture, one texel in UV.
kernel void particleEmitterImageReduce(texture2d<float> image [[texture(0)]],
                                       device uchar4 *output [[buffer(0)]],
                                       constant float4 &parameters [[buffer(1)]],
                                       constant uint2 &size [[buffer(2)]],
                                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= size.x || gid.y >= size.y) return;
    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);
    const float2 centre = (float2(gid) + 0.5f) / float2(size) * parameters.xy;
    const float2 texel = parameters.zw * 2;
    float4 albedo = image.sample(bilinear, centre - texel) + image.sample(bilinear, centre + texel)
        + image.sample(bilinear, centre + float2(-texel.x, texel.y)) + image.sample(bilinear, centre + float2(texel.x, -texel.y));
    albedo = saturate(albedo * 0.25f);
    output[gid.y * size.x + gid.x] = uchar4(round(albedo * 255));
}
