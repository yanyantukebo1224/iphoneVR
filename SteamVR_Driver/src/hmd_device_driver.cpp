#include "hmd_device_driver.h"
#include <cstring>

HMDDeviceDriver::HMDDeviceDriver() : m_unObjectId(0) {
    std::memset(&m_pose, 0, sizeof(m_pose));
    m_pose.poseIsValid = true;
    m_pose.deviceIsConnected = true;
    m_pose.result = vr::TrackingResult_Running_OK;

    m_pose.qRotation.w = 1.0;
    m_pose.qWorldFromDriverRotation.w = 1.0;
    m_pose.qDriverFromHeadRotation.w = 1.0;
}

HMDDeviceDriver::~HMDDeviceDriver() {}

vr::EVRInitError HMDDeviceDriver::Activate(uint32_t unObjectId) {
    m_unObjectId = unObjectId;
    return vr::VRInitError_None;
}

void* HMDDeviceDriver::GetComponent(const char* pchComponentNameAndVersion) {
    if (std::strcmp(pchComponentNameAndVersion, vr::IVRDisplayComponent_Version) == 0) {
        return static_cast<vr::IVRDisplayComponent*>(this);
    }
    return nullptr;
}

// Display Component Implementation
void HMDDeviceDriver::GetWindowBounds(int32_t* pnX, int32_t* pnY, uint32_t* pnWidth, uint32_t* pnHeight) {
    *pnX = 0;
    *pnY = 0;
    *pnWidth = 2532;
    *pnHeight = 1170;
}

void HMDDeviceDriver::GetIsOnDesktop(bool* pbIsOnDesktop) {
    *pbIsOnDesktop = true;
}

void HMDDeviceDriver::GetRecommendedRenderTargetSize(uint32_t* pnWidth, uint32_t* pnHeight) {
    *pnWidth = 1266;
    *pnHeight = 1170;
}

void HMDDeviceDriver::GetEyeOutputViewport(vr::EVREye eEye, uint32_t* pnX, uint32_t* pnY, uint32_t* pnWidth, uint32_t* pnHeight) {
    *pnY = 0;
    *pnWidth = 1266;
    *pnHeight = 1170;
    if (eEye == vr::Eye_Left) {
        *pnX = 0;
    } else {
        *pnX = 1266;
    }
}

void HMDDeviceDriver::GetProjectionRaw(vr::EVREye eEye, float* pfLeft, float* pfRight, float* pfTop, float* pfBottom) {
    *pfLeft = -1.0f;
    *pfRight = 1.0f;
    *pfTop = -1.0f;
    *pfBottom = 1.0f;
}

vr::HmdMatrix34_t HMDDeviceDriver::GetEyeToHeadTransform(vr::EVREye eEye) {
    vr::HmdMatrix34_t mat{};
    mat.m[0][0] = 1.0f;
    mat.m[1][1] = 1.0f;
    mat.m[2][2] = 1.0f;

    float ipdOffset = 0.0315f;
    mat.m[0][3] = (eEye == vr::Eye_Left) ? -ipdOffset : ipdOffset;
    return mat;
}

void HMDDeviceDriver::UpdateHeadPose(const Vector3f& headPos, const Quaternionf& headRot) {
    m_pose.poseIsValid = true;
    m_pose.result = vr::TrackingResult_Running_OK;

    m_pose.vecPosition[0] = (headPos.x * m_config.posXMultiplier) + m_config.offsetX;
    m_pose.vecPosition[1] = (headPos.y * m_config.posYMultiplier) + m_config.offsetY;
    m_pose.vecPosition[2] = (headPos.z * m_config.posZMultiplier) + m_config.offsetZ;

    m_pose.qRotation.w = m_config.invertRotW ? -headRot.w : headRot.w;
    m_pose.qRotation.x = m_config.invertRotX ? -headRot.x : headRot.x;
    m_pose.qRotation.y = m_config.invertRotY ? -headRot.y : headRot.y;
    m_pose.qRotation.z = m_config.invertRotZ ? -headRot.z : headRot.z;
}
