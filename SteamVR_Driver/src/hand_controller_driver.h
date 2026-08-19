#ifndef HAND_CONTROLLER_DRIVER_H
#define HAND_CONTROLLER_DRIVER_H

#include "openvr_driver_stub.h"
#include "tracking_protocol.h"
#include <string>

class HandControllerDriver {
public:
    HandControllerDriver(vr::ETrackedControllerRole role);
    ~HandControllerDriver();

    void UpdateHandPose(const HandPacketData& handData, const Vector3f& headPos);
    
    // SteamVR 31ボーン変換処理 (ポプちゃん指示 ① 実装)
    static void ConvertVision21ToSteamVR31(
        const HandPacketData& handData,
        vr::VRBoneTransform_t outBones[31]
    );

    vr::DriverPose_t GetPose() const { return m_pose; }

private:
    vr::ETrackedControllerRole m_role;
    vr::DriverPose_t m_pose;
    bool m_isTracked;
};

#endif // HAND_CONTROLLER_DRIVER_H
