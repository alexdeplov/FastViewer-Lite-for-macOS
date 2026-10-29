#include <metal_stdlib>
using namespace metal;

struct ImageVertex {
    float4 position [[position]];
    float2 uv;
};

// xy = image half-size / viewport half-size; zw = image center in NDC.
vertex ImageVertex imageVertex(uint id [[vertex_id]], constant float4 &geometry [[buffer(0)]]) {
    const float2 positions[] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };
    const float2 texcoords[] = { {0,1}, {1,1}, {0,0}, {1,0} };
    return { float4(positions[id] * geometry.xy + geometry.zw, 0, 1), texcoords[id] };
}

fragment float4 imageFragment(ImageVertex in [[stage_in]],
                              texture2d<float> image [[texture(0)]],
                              constant uint &nearest [[buffer(0)]]) {
    constexpr sampler pixels(coord::normalized, address::clamp_to_edge, filter::nearest);
    constexpr sampler smooth(coord::normalized, address::clamp_to_edge, filter::linear);
    return nearest ? image.sample(pixels, in.uv) : image.sample(smooth, in.uv);
}
