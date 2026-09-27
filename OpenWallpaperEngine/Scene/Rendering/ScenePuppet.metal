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

// Another image-space texture of a puppet (its normal map, PBR mask…) laid out like the posed
// mesh, for a lit puppet without effects: WE draws that mesh in the scene, so every texture of its
// material is sampled at the mesh's coordinates (docs/models-plan.md §2.13). The vertices are
// skinned exactly as the translated `SKINNING` stage does (Σ wᵢ · g_Bones[iᵢ] · p).
struct ScenePuppetWarpUniforms {
    float4x4 projection;
    float2 uvScale;
    uint positionOffset;
    uint indicesOffset;
    uint weightsOffset;
    uint texCoordOffset;
    uint stride;
    uint boneCount;
};

struct ScenePuppetWarpOut {
    float4 position [[position]];
    float2 uv;
};

vertex ScenePuppetWarpOut scenePuppetWarpVertex(uint vid [[vertex_id]],
                                                device const uchar *mesh [[buffer(0)]],
                                                constant ScenePuppetWarpUniforms &u [[buffer(1)]],
                                                constant float4x4 *bones [[buffer(2)]]) {
    device const uchar *v = mesh + vid * u.stride;
    float3 p = float3(*(device const packed_float3 *)(v + u.positionOffset));
    uint4 index = uint4(*(device const packed_uint4 *)(v + u.indicesOffset));
    float4 weight = float4(*(device const packed_float4 *)(v + u.weightsOffset));
    float4 skinned = float4(0.0);
    for (uint k = 0; k < 4; k++) {
        if (weight[k] != 0.0 && index[k] < u.boneCount) {
            skinned += weight[k] * (bones[index[k]] * float4(p, 1.0));
        }
    }
    ScenePuppetWarpOut out;
    out.position = u.projection * float4(skinned.xyz, 1.0);
    // `projection` targets GL clip with the rows flipped for the translated stages, which negate y.
    out.position.y = -out.position.y;
    out.position.z = 0.5 * out.position.w;
    out.uv = float2(*(device const packed_float2 *)(v + u.texCoordOffset)) * u.uvScale;
    return out;
}

fragment float4 scenePuppetWarpFragment(ScenePuppetWarpOut in [[stage_in]],
                                        texture2d<float> source [[texture(0)]],
                                        sampler smp [[sampler(0)]]) {
    return source.sample(smp, in.uv);
}
