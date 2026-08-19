#ifndef HAND_CONTROLLER_DRIVER_H
#define HAND_CONTROLLER_DRIVER_H

#include "openvr_driver.h"
#include "tracking_protocol.h"
#include <string>
#include <chrono>

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

    vr::VRInputComponentHandle_t m_ulSkeletonComponent;
    vr::VRInputComponentHandle_t m_ulTriggerClickComponent;
    vr::VRInputComponentHandle_t m_ulTriggerValueComponent;
    vr::VRInputComponentHandle_t m_ulGripClickComponent;
    vr::VRInputComponentHandle_t m_ulGripValueComponent;
    vr::VRInputComponentHandle_t m_ulAButtonComponent;
    vr::VRInputComponentHandle_t m_ulBButtonComponent;
    vr::VRInputComponentHandle_t m_ulXButtonComponent;
    vr::VRInputComponentHandle_t m_ulYButtonComponent;
    vr::VRInputComponentHandle_t m_ulThumbstickXComponent;
    vr::VRInputComponentHandle_t m_ulThumbstickYComponent;
    vr::VRInputComponentHandle_t m_ulThumbstickClickComponent;
    vr::VRInputComponentHandle_t m_ulSystemButtonComponent;

    bool m_isTracked;

    std::chrono::steady_clock::time_point m_lastMovementTime;
    float m_lastPosition[3];
    float m_smoothedPosition[3];
};

#endif // HAND_CONTROLLER_DRIVER_H
