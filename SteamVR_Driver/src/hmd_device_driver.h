#ifndef HMD_DEVICE_DRIVER_H
#define HMD_DEVICE_DRIVER_H

#include "openvr_driver_stub.h"
#include "tracking_protocol.h"

struct CoordinateConfig {
    float posXMultiplier = 1.0f;
    float posYMultiplier = 1.0f;
    float posZMultiplier = 1.0f;

    bool invertRotW = false;
    bool invertRotX = false;
    bool invertRotY = false;
    bool invertRotZ = false;
    
    float offsetX = 0.0f;
    float offsetY = 0.0f;
    float offsetZ = 0.0f;
};

class HMDDeviceDriver : public vr::ITrackedDeviceServerDriver {
public:
    HMDDeviceDriver();
    virtual ~HMDDeviceDriver();

    // ITrackedDeviceServerDriver 仮想関数
    virtual vr::EVRInitError Activate(uint32_t unObjectId) override;
    virtual void Deactivate() override {}
    virtual void EnterStandby() override {}
    virtual void* GetComponent(const char* pchComponentNameAndVersion) override { return nullptr; }
    virtual void DebugRequest(const char* pchRequest, char* pchResponseBuffer, uint32_t unResponseBufferSize) override {}
    virtual vr::DriverPose_t GetPose() override { return m_pose; }

    void UpdateHeadPose(const Vector3f& headPos, const Quaternionf& headRot);
    CoordinateConfig& GetConfig() { return m_config; }

private:
    vr::DriverPose_t m_pose;
    CoordinateConfig m_config;
    uint32_t m_unObjectId;
};

#endif // HMD_DEVICE_DRIVER_H
