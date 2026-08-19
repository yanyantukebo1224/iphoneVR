#ifndef HAND_CONTROLLER_DRIVER_H
#define HAND_CONTROLLER_DRIVER_H

#include "openvr_driver_stub.h"
#include "tracking_protocol.h"
#include <string>

class HandControllerDriver : public vr::ITrackedDeviceServerDriver {
public:
    HandControllerDriver(vr::ETrackedControllerRole role);
    virtual ~HandControllerDriver();

    // ITrackedDeviceServerDriver 仮想関数
    virtual vr::EVRInitError Activate(uint32_t unObjectId) override;
    virtual void Deactivate() override {}
    virtual void EnterStandby() override {}
    virtual void* GetComponent(const char* pchComponentNameAndVersion) override { return nullptr; }
    virtual void DebugRequest(const char* pchRequest, char* pchResponseBuffer, uint32_t unResponseBufferSize) override {}
    virtual vr::DriverPose_t GetPose() override { return m_pose; }

    void UpdateHandPose(const HandPacketData& handData, const Vector3f& headPos);
    
    static void ConvertVision21ToSteamVR31(
        const HandPacketData& handData,
        vr::VRBoneTransform_t outBones[31]
    );

private:
    vr::ETrackedControllerRole m_role;
    vr::DriverPose_t m_pose;
    uint32_t m_unObjectId;
    bool m_isTracked;
};

#endif // HAND_CONTROLLER_DRIVER_H
