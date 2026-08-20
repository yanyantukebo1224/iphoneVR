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

// VR レンズ歪み補正シェーダー (Aspect Fill Dual Eye VR)
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
    float2 localUV;
    if (isRightEye) {
        localUV = float2((uv.x - 0.5) * 2.0, uv.y);
    } else {
        localUV = float2(uv.x * 2.0, uv.y);
    }

    // 各眼の中心 (0.5, 0.5)
    float2 eyeCenter = float2(0.5, 0.5);
    float2 delta = localUV - eyeCenter;

    // iPhoneの片目アスペクト比 (~1.08) と映像アスペクト比 (~1.77) の違いを解消する Aspect-Fill 補正
    // 画面の上下黒帯を完全排除し、全画面いっぱいにVR映像を大迫力展開
    float2 aspectScale = float2(0.75, 1.0); // 左右の余白を適切に拡大して上下黒帯を消去
    float2 scaledDelta = delta * aspectScale;

    // 樽型歪み計算
    float r2 = dot(scaledDelta, scaledDelta);
    float k1 = 0.08;
    float k2 = 0.03;
    float distortion = 1.0 + k1 * r2 + k2 * r2 * r2;

    float2 distortedUV = eyeCenter + delta * distortion;

    // テクスチャのアスペクト比判定 (SBS 3DかMonoフル画面か)
    float texAspect = float(videoTexture.get_width()) / max(float(videoTexture.get_height()), 1.0);
    float2 sampledUV;
    if (texAspect >= 1.9) {
        // Side-by-Side 3Dモード (左目: 左半分, 右目: 右半分)
        if (isRightEye) {
            sampledUV = float2(0.5 + distortedUV.x * 0.5, distortedUV.y);
        } else {
            sampledUV = float2(distortedUV.x * 0.5, distortedUV.y);
        }
    } else {
        // フル画面複製モード (通常のデスクトップやSteamVR 1画面映像を両眼に美しく全画面表示)
        // 16:9映像を片目画面(~1.08:1)に中央Aspect-Fillでマッピング
        float2 fillDelta = delta * float2(0.65, 1.0) * distortion;
        sampledUV = eyeCenter + fillDelta;
    }

    // 枠外クリッピング
    if (sampledUV.x < 0.0 || sampledUV.x > 1.0 || sampledUV.y < 0.0 || sampledUV.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    return videoTexture.sample(textureSampler, sampledUV);
}

