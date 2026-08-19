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

class HMDDeviceDriver : public vr::ITrackedDeviceServerDriver, public vr::IVRDisplayComponent {
public:
    HMDDeviceDriver();
    virtual ~HMDDeviceDriver();

    // ITrackedDeviceServerDriver
    virtual vr::EVRInitError Activate(uint32_t unObjectId) override;
    virtual void Deactivate() override {}
    virtual void EnterStandby() override {}
    virtual void* GetComponent(const char* pchComponentNameAndVersion) override;
    virtual void DebugRequest(const char* pchRequest, char* pchResponseBuffer, uint32_t unResponseBufferSize) override {}
    virtual vr::DriverPose_t GetPose() override { return m_pose; }

    // IVRDisplayComponent (仮想HMDのウィンドウ・レンダリング定義)
    virtual void GetWindowBounds(int32_t* pnX, int32_t* pnY, uint32_t* pnWidth, uint32_t* pnHeight) override;
    virtual void GetIsOnDesktop(bool* pbIsOnDesktop) override;
    virtual void GetRecommendedRenderTargetSize(uint32_t* pnWidth, uint32_t* pnHeight) override;
    virtual void GetEyeOutputViewport(vr::EVREye eEye, uint32_t* pnX, uint32_t* pnY, uint32_t* pnWidth, uint32_t* pnHeight) override;
    virtual void GetProjectionRaw(vr::EVREye eEye, float* pfLeft, float* pfRight, float* pfTop, float* pfBottom) override;
    virtual vr::HmdMatrix34_t GetEyeToHeadTransform(vr::EVREye eEye) override;

    void UpdateHeadPose(const Vector3f& headPos, const Quaternionf& headRot);
    CoordinateConfig& GetConfig() { return m_config; }

private:
    vr::DriverPose_t m_pose;
    CoordinateConfig m_config;
    uint32_t m_unObjectId;
};

#endif // HMD_DEVICE_DRIVER_H
