#include "hmd_device_driver.h"
#include <cstring>
#include <cmath>

static bool g_recenterInitialized = false;
static float g_initYaw = 0.0f;
static Vector3f g_initPos = {0.0f, 0.0f, 0.0f};

HMDDeviceDriver::HMDDeviceDriver() : m_unObjectId(vr::k_unTrackedDeviceIndexInvalid), m_ulPropertyContainer(vr::k_ulInvalidPropertyContainer) {
    std::memset(&m_pose, 0, sizeof(m_pose));
    m_pose.poseIsValid = true;
    m_pose.deviceIsConnected = true;
    m_pose.result = vr::TrackingResult_Running_OK;

    m_pose.qRotation.w = 1.0;
    m_pose.qWorldFromDriverRotation.w = 1.0;
    m_pose.qDriverFromHeadRotation.w = 1.0;

    m_config.offsetY = 1.65f;
}

HMDDeviceDriver::~HMDDeviceDriver() {
    m_poseThreadRunning = false;
    if (m_poseThread.joinable()) {
        m_poseThread.join();
    }
}

vr::EVRInitError HMDDeviceDriver::Activate(uint32_t unObjectId) {
    m_unObjectId = unObjectId;
    m_ulPropertyContainer = vr::VRProperties()->TrackedDeviceToPropertyContainer(m_unObjectId);

    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_TrackingSystemName_String, "iPhoneVR");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_SerialNumber_String, "iPhoneVR_HMD_001");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ModelNumber_String, "iPhoneVR HMD");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ManufacturerName_String, "iPhoneVR");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_RenderModelName_String, "generic_hmd");
    vr::VRProperties()->SetFloatProperty(m_ulPropertyContainer, vr::Prop_UserIpdMeters_Float, 0.063f);
    vr::VRProperties()->SetFloatProperty(m_ulPropertyContainer, vr::Prop_DisplayFrequency_Float, 60.0f);
    vr::VRProperties()->SetFloatProperty(m_ulPropertyContainer, vr::Prop_SecondsFromVsyncToPhotons_Float, 0.011f);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_IsOnDesktop_Bool, false);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_HasDisplayComponent_Bool, true);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_WillDriftInYaw_Bool, false);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_DeviceIsWireless_Bool, true);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_ContainsProximitySensor_Bool, false);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_DriverProvidedChaperoneVisibility_Bool, false);
    vr::VRProperties()->SetUint64Property(m_ulPropertyContainer, vr::Prop_CurrentUniverseId_Uint64, 2);

    m_lastVsyncTime = std::chrono::high_resolution_clock::now();
    m_frameCounter = 0;

    UpdateHeadPose(Vector3f{0.0f, 0.0f, 0.0f}, Quaternionf{1.0f, 0.0f, 0.0f, 0.0f});

    m_poseThreadRunning = true;
    m_poseThread = std::thread(&HMDDeviceDriver::PoseLoop, this);

    return vr::VRInitError_None;
}

void HMDDeviceDriver::PoseLoop() {
    while (m_poseThreadRunning) {
        if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid) {
            vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }
}

void* HMDDeviceDriver::GetComponent(const char* pchComponentNameAndVersion) {
    if (std::strcmp(pchComponentNameAndVersion, vr::IVRDisplayComponent_Version) == 0) {
        return static_cast<vr::IVRDisplayComponent*>(this);
    }
    if (std::strcmp(pchComponentNameAndVersion, vr::IVRVirtualDisplay_Version) == 0) {
        return static_cast<vr::IVRVirtualDisplay*>(this);
    }
    return nullptr;
}

void HMDDeviceDriver::Present(const vr::PresentInfo_t *pPresentInfo, uint32_t unPresentInfoSize) {
    m_lastVsyncTime = std::chrono::high_resolution_clock::now();
    m_frameCounter++;
}

void HMDDeviceDriver::WaitForPresent() {
    auto now = std::chrono::high_resolution_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(now - m_lastVsyncTime).count();
    const int64_t targetFrameMicroseconds = 16666;
    if (elapsed < targetFrameMicroseconds) {
        std::this_thread::sleep_for(std::chrono::microseconds(targetFrameMicroseconds - elapsed));
    }
}

bool HMDDeviceDriver::GetTimeSinceLastVsync(float *pfSecondsSinceLastVsync, uint64_t *pulFrameCounter) {
    auto now = std::chrono::high_resolution_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(now - m_lastVsyncTime).count();
    if (pfSecondsSinceLastVsync) {
        *pfSecondsSinceLastVsync = (float)(elapsed / 1000000.0);
    }
    if (pulFrameCounter) {
        *pulFrameCounter = m_frameCounter;
    }
    return true;
}

void HMDDeviceDriver::GetWindowBounds(int32_t* pnX, int32_t* pnY, uint32_t* pnWidth, uint32_t* pnHeight) {
    *pnX = 0;
    *pnY = 0;
    *pnWidth = 1920;
    *pnHeight = 1080;
}

void HMDDeviceDriver::GetRecommendedRenderTargetSize(uint32_t* pnWidth, uint32_t* pnHeight) {
    *pnWidth = 960;
    *pnHeight = 1080;
}

void HMDDeviceDriver::GetEyeOutputViewport(vr::EVREye eEye, uint32_t* pnX, uint32_t* pnY, uint32_t* pnWidth, uint32_t* pnHeight) {
    *pnY = 0;
    *pnWidth = 960;
    *pnHeight = 1080;
    if (eEye == vr::Eye_Left) {
        *pnX = 0;
    } else {
        *pnX = 960;
    }
}

void HMDDeviceDriver::GetProjectionRaw(vr::EVREye eEye, float* pfLeft, float* pfRight, float* pfTop, float* pfBottom) {
    *pfLeft = -1.0f;
    *pfRight = 1.0f;
    *pfTop = -1.0f;
    *pfBottom = 1.0f;
}

void HMDDeviceDriver::UpdateHeadPose(const Vector3f& headPos, const Quaternionf& headRot) {
    m_pose.poseIsValid = true;
    m_pose.result = vr::TrackingResult_Running_OK;

    // 初回トラッキング受信時に正面 Yaw 角度・初期原点位置をキャリブレーション
    if (!g_recenterInitialized && (headPos.x != 0.0f || headPos.y != 0.0f || headPos.z != 0.0f)) {
        g_initPos = headPos;
        double siny_cosp = 2.0 * (headRot.w * headRot.y + headRot.x * headRot.z);
        double cosy_cosp = 1.0 - 2.0 * (headRot.x * headRot.x + headRot.y * headRot.y);
        g_initYaw = (float)std::atan2(siny_cosp, cosy_cosp);
        g_recenterInitialized = true;
    }

    float relX = headPos.x - g_initPos.x;
    float relY = headPos.y - g_initPos.y;
    float relZ = headPos.z - g_initPos.z;

    // Yaw リセット補正回転の適用
    float cosY = std::cos(-g_initYaw);
    float sinY = std::sin(-g_initYaw);

    float rotX = relX * cosY - relZ * sinY;
    float rotZ = relX * sinY + relZ * cosY;

    m_pose.vecPosition[0] = (rotX * m_config.posXMultiplier) + m_config.offsetX;
    m_pose.vecPosition[1] = (relY * m_config.posYMultiplier) + m_config.offsetY;
    m_pose.vecPosition[2] = (rotZ * m_config.posZMultiplier) + m_config.offsetZ;

    m_pose.qRotation.w = m_config.invertRotW ? -headRot.w : headRot.w;
    m_pose.qRotation.x = m_config.invertRotX ? -headRot.x : headRot.x;
    m_pose.qRotation.y = m_config.invertRotY ? -headRot.y : headRot.y;
    m_pose.qRotation.z = m_config.invertRotZ ? -headRot.z : headRot.z;

    if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid) {
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));
    }
}
