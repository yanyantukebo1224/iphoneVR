#include "hand_controller_driver.h"
#include <cstring>
#include <cmath>

HandControllerDriver::HandControllerDriver(vr::ETrackedControllerRole role)
    : m_role(role), m_isTracked(false) {
    std::memset(&m_pose, 0, sizeof(m_pose));
    m_pose.poseIsValid = false;
    m_pose.deviceIsConnected = true;
    m_pose.result = vr::TrackingResult_Uninitialized;
    
    m_pose.qRotation.w = 1.0;
    m_pose.qWorldFromDriverRotation.w = 1.0;
    m_pose.qDriverFromHeadRotation.w = 1.0;
}

HandControllerDriver::~HandControllerDriver() {}

void HandControllerDriver::UpdateHandPose(const HandPacketData& handData, const Vector3f& headPos) {
    if (!handData.isTracked) {
        m_pose.poseIsValid = false;
        m_pose.result = vr::TrackingResult_Running_OutOfRange;
        return;
    }

    m_pose.poseIsValid = true;
    m_pose.result = vr::TrackingResult_Running_OK;

    // 手首 (Wrist) を Controller Pose 位置として適用
    m_pose.vecPosition[0] = handData.joints[VISION_JOINT_WRIST].position.x;
    m_pose.vecPosition[1] = handData.joints[VISION_JOINT_WRIST].position.y;
    m_pose.vecPosition[2] = handData.joints[VISION_JOINT_WRIST].position.z;

    m_pose.qRotation.w = handData.joints[VISION_JOINT_WRIST].orientation.w;
    m_pose.qRotation.x = handData.joints[VISION_JOINT_WRIST].orientation.x;
    m_pose.qRotation.y = handData.joints[VISION_JOINT_WRIST].orientation.y;
    m_pose.qRotation.z = handData.joints[VISION_JOINT_WRIST].orientation.z;
}

// Vision 21関節 -> SteamVR 31ボーンマッピングテーブル (ポプちゃん指示 ① 31ボーン補正)
void HandControllerDriver::ConvertVision21ToSteamVR31(
    const HandPacketData& handData,
    vr::VRBoneTransform_t outBones[31]
) {
    // 恒等変換ヘルパー
    auto makeIdentity = [](vr::VRBoneTransform_t& b, float px=0, float py=0, float pz=0) {
        b.position.v[0] = px;
        b.position.v[1] = py;
        b.position.v[2] = pz;
        b.orientation.w = 1.0;
        b.orientation.x = 0.0;
        b.orientation.y = 0.0;
        b.orientation.z = 0.0;
    };

    // 全31ボーンを一旦初期化
    for (int i = 0; i < 31; ++i) {
        makeIdentity(outBones[i]);
    }

    if (!handData.isTracked) return;

    // Helper: Joint変換
    auto mapJoint = [](const BoneTransform& src, vr::VRBoneTransform_t& dst) {
        dst.position.v[0] = src.position.x;
        dst.position.v[1] = src.position.y;
        dst.position.v[2] = src.position.z;
        dst.orientation.w = src.orientation.w;
        dst.orientation.x = src.orientation.x;
        dst.orientation.y = src.orientation.y;
        dst.orientation.z = src.orientation.z;
    };

    // 0: Root, 1: Wrist
    mapJoint(handData.joints[VISION_JOINT_WRIST], outBones[vr::STEAMVR_BONE_WRIST]);

    // 親関節からの相対オフセットで Metacarpal (ボーン0) を補間
    // 指（Thumb, Index, Middle, Ring, Pinky）
    struct FingerMap {
        int steamvr_start;
        int vision_start;
    } fingerMaps[] = {
        { vr::STEAMVR_BONE_THUMB_0,  VISION_JOINT_THUMB_CMC },
        { vr::STEAMVR_BONE_INDEX_1,  VISION_JOINT_INDEX_MCP },
        { vr::STEAMVR_BONE_MIDDLE_1, VISION_JOINT_MIDDLE_MCP },
        { vr::STEAMVR_BONE_RING_1,   VISION_JOINT_RING_MCP },
        { vr::STEAMVR_BONE_PINKY_1,  VISION_JOINT_PINKY_MCP }
    };

    // 1) Metacarpal (0番目の関節) の補間
    // Visionには中手骨(Metacarpal)がないため、MCP関節の親オフセットとして手首からMCP方向の固定オフセットを生成
    makeIdentity(outBones[vr::STEAMVR_BONE_INDEX_0],  0.03f, 0.0f, 0.05f); // Index Metacarpal
    makeIdentity(outBones[vr::STEAMVR_BONE_MIDDLE_0], 0.01f, 0.0f, 0.06f); // Middle Metacarpal
    makeIdentity(outBones[vr::STEAMVR_BONE_RING_0],  -0.01f, 0.0f, 0.05f); // Ring Metacarpal
    makeIdentity(outBones[vr::STEAMVR_BONE_PINKY_0], -0.03f, 0.0f, 0.04f); // Pinky Metacarpal

    // 2) 4段階の関節＋先端TipをVisionデータから連続マッピング
    for (const auto& f : fingerMaps) {
        for (int step = 0; step < 4; ++step) {
            mapJoint(handData.joints[f.vision_start + step], outBones[f.steamvr_start + step]);
        }
    }

    // 3) 補助ボーン (Auxiliary Bones 26..30) は各指先Tipと同じ位置姿勢でミラーリング
    outBones[vr::STEAMVR_BONE_AUX_THUMB]  = outBones[vr::STEAMVR_BONE_THUMB_3];
    outBones[vr::STEAMVR_BONE_AUX_INDEX]  = outBones[vr::STEAMVR_BONE_INDEX_4];
    outBones[vr::STEAMVR_BONE_AUX_MIDDLE] = outBones[vr::STEAMVR_BONE_MIDDLE_4];
    outBones[vr::STEAMVR_BONE_AUX_RING]   = outBones[vr::STEAMVR_BONE_RING_4];
    outBones[vr::STEAMVR_BONE_AUX_PINKY]  = outBones[vr::STEAMVR_BONE_PINKY_4];
}
