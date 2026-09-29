#include <metal_stdlib>
using namespace metal;

// Matches VideoYCbCrConversion.Uniforms: rgb = matrix * (ycbcr - offset).
struct VideoYCbCrUniforms {
    float3x3 matrix;
    float3 offset;
};

// Converts a bi-planar 4:2:0 frame (Y' r8Unorm, CbCr rg8Unorm at half size) into RGBA.
kernel void videoYCbCrToRGB(texture2d<float, access::read> luma [[texture(0)]],
                            texture2d<float, access::sample> chroma [[texture(1)]],
                            texture2d<float, access::write> output [[texture(2)]],
                            constant VideoYCbCrUniforms &uniforms [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    constexpr sampler chromaSampler(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    float y = luma.read(gid).r;
    float2 cbcr = chroma.sample(chromaSampler, uv).rg;
    float3 rgb = uniforms.matrix * (float3(y, cbcr) - uniforms.offset);
    output.write(float4(saturate(rgb), 1.0), gid);
}
