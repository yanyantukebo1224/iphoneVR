#ifndef HMD_DEVICE_DRIVER_H
#define HMD_DEVICE_DRIVER_H

#include "openvr_driver.h"
#include "tracking_protocol.h"
#include <thread>
#include <atomic>
#include <chrono>

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

    // IVRDisplayComponent
    virtual void GetWindowBounds(int32_t* pnX, int32_t* pnY, uint32_t* pnWidth, uint32_t* pnHeight) override;
    virtual bool IsDisplayOnDesktop() override { return true; }
    virtual bool IsDisplayRealDisplay() override { return false; }
    virtual void GetRecommendedRenderTargetSize(uint32_t* pnWidth, uint32_t* pnHeight) override;
    virtual void GetEyeOutputViewport(vr::EVREye eEye, uint32_t* pnX, uint32_t* pnY, uint32_t* pnWidth, uint32_t* pnHeight) override;
    virtual void GetProjectionRaw(vr::EVREye eEye, float* pfLeft, float* pfRight, float* pfTop, float* pfBottom) override;
    virtual vr::DistortionCoordinates_t ComputeDistortion(vr::EVREye eEye, float fU, float fV) override {
        vr::DistortionCoordinates_t coord;
        coord.rfRed[0] = fU; coord.rfRed[1] = fV;
        coord.rfGreen[0] = fU; coord.rfGreen[1] = fV;
        coord.rfBlue[0] = fU; coord.rfBlue[1] = fV;
        return coord;
    }
    virtual bool ComputeInverseDistortion(vr::HmdVector2_t* pResult, vr::EVREye eEye, uint32_t unChannel, float fU, float fV) override { return false; }

    void UpdateHeadPose(const Vector3f& headPos, const Quaternionf& headRot);
    CoordinateConfig& GetConfig() { return m_config; }

private:
    vr::DriverPose_t m_pose;
    CoordinateConfig m_config;
    uint32_t m_unObjectId;
    vr::PropertyContainerHandle_t m_ulPropertyContainer;

    std::atomic<bool> m_poseThreadRunning{false};
    std::thread m_poseThread;
    void PoseLoop();
};

#endif // HMD_DEVICE_DRIVER_H
