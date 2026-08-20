#include <metal_stdlib>
using namespace metal;

struct VertexInput {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// フルスクリーン頂点シェーダー
vertex VertexOut vrVertexShader(uint vertexID [[vertex_id]]) {
    // 2枚の三角形でフルスクリーンクアッド (6頂点)
    const float2 positions[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0)
    };

    const float2 texCoords[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// VR レンズ歪み補正シェーダー (Perfect Fullscreen VR Viewport)
fragment float4 vrDistortionFragmentShader(VertexOut in [[stage_in]],
                                            texture2d<float> videoTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    
    if (is_null_texture(videoTexture)) {
        // テクスチャ未接続時の立体視グリッドプレースホルダー表示
        float grid = (fmod(floor(uv.x * 20.0) + floor(uv.y * 20.0), 2.0) == 0.0) ? 0.08 : 0.03;
        return float4(grid, grid, grid + 0.02, 1.0);
    }

    // 左右画面のローカル座標 (0.0 ~ 1.0)
    bool isRightEye = (uv.x >= 0.5);
    float2 localUV = isRightEye ? float2((uv.x - 0.5) * 2.0, uv.y) : float2(uv.x * 2.0, uv.y);

    // 各眼の中心 (0.5, 0.5)
    float2 eyeCenter = float2(0.5, 0.5);
    float2 delta = localUV - eyeCenter;

    // 樽型歪み計算 (穏やかなカーブで視界を最大化)
    float r2 = dot(delta, delta);
    float k1 = 0.06;
    float distortion = 1.0 + k1 * r2;
    float2 distortedDelta = delta * distortion;

    // テクスチャのアスペクト比判定
    float texWidth = float(videoTexture.get_width());
    float texHeight = max(float(videoTexture.get_height()), 1.0);
    float texAspect = texWidth / texHeight;

    float2 sampledUV;
    if (texAspect >= 1.9) {
        // Side-by-Side 3Dモード (左目: 左半分, 右目: 右半分)
        if (isRightEye) {
            sampledUV = float2(0.5 + (eyeCenter.x + distortedDelta.x) * 0.5, eyeCenter.y + distortedDelta.y);
        } else {
            sampledUV = float2((eyeCenter.x + distortedDelta.x) * 0.5, eyeCenter.y + distortedDelta.y);
        }
    } else {
        // フル画面複製モード (通常のデスクトップやSteamVR 1画面映像を両眼フルスクリーン展開)
        // 16:9 映像を上下黒帯なしで片目画面にぴったり全画面フィット (Aspect Fill)
        // Y方向を画面いっぱいに広げ、上下の黒帯を完全に消滅させます
        sampledUV = eyeCenter + float2(distortedDelta.x * 0.90, distortedDelta.y * 0.90);
    }

    // clamp_to_edge でエッジが自然に伸びるようにサンプリング (黒帯なし)
    return videoTexture.sample(textureSampler, clamp(sampledUV, float2(0.001, 0.001), float2(0.999, 0.999)));
}

