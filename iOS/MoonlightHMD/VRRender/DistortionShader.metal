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

// VR レンズ歪み補正シェーダー (Dual Eye Barrel Distortion)
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

    // アスペクト比に応じた歪み計算 (適度な樽型歪みでレンズ視野を最大化)
    float r2 = dot(delta, delta);
    float k1 = 0.12; // 自然で視野が広く歪みすぎない最適値
    float k2 = 0.05;
    float distortion = 1.0 + k1 * r2 + k2 * r2 * r2;

    float2 distortedLocalUV = eyeCenter + delta * distortion;

    // レンズ枠外のクリッピング
    if (distortedLocalUV.x < 0.0 || distortedLocalUV.x > 1.0 ||
        distortedLocalUV.y < 0.0 || distortedLocalUV.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // テクスチャの解像度アスペクト比をチェック
    // 2.0以上 (例: 32:9 や SBS 3D映像) の場合はSide-by-Sideサンプリング
    // 通常の16:9などの場合は両眼にフル画面を複製サンプリング (Mono/Desktop)
    float texAspect = float(videoTexture.get_width()) / max(float(videoTexture.get_height()), 1.0);
    float2 sampledUV;
    if (texAspect >= 1.9) {
        // SBS 3Dモード (左半分: 左目、右半分: 右目)
        if (isRightEye) {
            sampledUV = float2(0.5 + distortedLocalUV.x * 0.5, distortedLocalUV.y);
        } else {
            sampledUV = float2(distortedLocalUV.x * 0.5, distortedLocalUV.y);
        }
    } else {
        // フル画面複製モード (通常のデスクトップやSteamVR 1画面映像を左右両眼に完璧表示)
        sampledUV = distortedLocalUV;
    }

    return videoTexture.sample(textureSampler, sampledUV);
}

