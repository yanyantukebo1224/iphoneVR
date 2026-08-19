#ifndef HAND_CONTROLLER_DRIVER_H
#define HAND_CONTROLLER_DRIVER_H

#include "openvr_driver.h"
#include "tracking_protocol.h"
#include <string>

class HandControllerDriver : public vr::ITrackedDeviceServerDriver {
public:
    HandControllerDriver(vr::ETrackedControllerRole role);
    virtual ~HandControllerDriver();

    virtual vr::EVRInitError Activate(uint32_t unObjectId) override;
    virtual void Deactivate() override {}
    virtual void EnterStandby() override {}
    virtual void* GetComponent(const char* pchComponentNameAndVersion) override { return nullptr; }
    virtual void DebugRequest(const char* pchRequest, char* pchResponseBuffer, uint32_t unResponseBufferSize) override {}
    virtual vr::DriverPose_t GetPose() override { return m_pose; }

    // 手位置 ＆ 指ジェスチャーコントローラー入力更新 (ポプちゃん指示 動作＆操作)
    void UpdateHandPose(const HandPacketData& handData, const Vector3f& headPos);
    
    static void ConvertVision21ToSteamVR31(
        const HandPacketData& handData,
        vr::VRBoneTransform_t outBones[31]
    );

private:
    vr::ETrackedControllerRole m_role;
    vr::DriverPose_t m_pose;
    uint32_t m_unObjectId;
    vr::PropertyContainerHandle_t m_ulPropertyContainer;

    // SteamVR Input Components (トリガー・クリック・グリップ入力)
    vr::VRInputComponentHandle_t m_ulSkeletonComponent;
    vr::VRInputComponentHandle_t m_ulTriggerClickComponent;
    vr::VRInputComponentHandle_t m_ulTriggerValueComponent;
    vr::VRInputComponentHandle_t m_ulGripClickComponent;

    bool m_isTracked;
};

#endif // HAND_CONTROLLER_DRIVER_H
