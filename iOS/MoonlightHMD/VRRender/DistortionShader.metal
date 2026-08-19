#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// VR レンズ歪み補正シェーダー (Side-by-Side)
fragment float4 vrDistortionFragmentShader(VertexOut in [[stage_in]],
                                            texture2d<float> videoTexture [[texture(0)]],
                                            sampler textureSampler [[sampler(0)]]) {
    float2 uv = in.texCoord;
    
    // 左右画面判定 (Left Eye: 0.0~0.5, Right Eye: 0.5~1.0)
    bool isRightEye = uv.x >= 0.5;
    float2 eyeCenter = isRightEye ? float2(0.75, 0.5) : float2(0.25, 0.5);
    
    // 中心からの相対位置
    float2 delta = (uv - eyeCenter) * float2(2.0, 1.0); // アスペクト比補正
    float r2 = dot(delta, delta);
    
    // 樽型歪み補正パラメータ (k1, k2)
    float k1 = 0.22;
    float k2 = 0.15;
    float distortion = 1.0 + k1 * r2 + k2 * r2 * r2;
    
    float2 distortedDelta = delta * distortion;
    float2 sampledUV = eyeCenter + distortedDelta * float2(0.5, 1.0);
    
    // レンズ枠外は黒
    if (sampledUV.x < (isRightEye ? 0.5 : 0.0) || sampledUV.x > (isRightEye ? 1.0 : 0.5) ||
        sampledUV.y < 0.0 || sampledUV.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    
    return videoTexture.sample(textureSampler, sampledUV);
}
