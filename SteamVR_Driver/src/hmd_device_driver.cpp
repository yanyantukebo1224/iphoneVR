#include "hmd_device_driver.h"
#include <cstring>

HMDDeviceDriver::HMDDeviceDriver() : m_unObjectId(vr::k_unTrackedDeviceIndexInvalid), m_ulPropertyContainer(vr::k_ulInvalidPropertyContainer) {
    std::memset(&m_pose, 0, sizeof(m_pose));
    m_pose.poseIsValid = true;
    m_pose.deviceIsConnected = true;
    m_pose.result = vr::TrackingResult_Running_OK;

    m_pose.qRotation.w = 1.0;
    m_pose.qWorldFromDriverRotation.w = 1.0;
    m_pose.qDriverFromHeadRotation.w = 1.0;

    // Default eye level height 1.65m
    m_config.offsetY = 1.65f;
}

HMDDeviceDriver::~HMDDeviceDriver() {}

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
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_IsOnDesktop_Bool, true);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_HasDisplayComponent_Bool, true);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_WillDriftInYaw_Bool, false);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_DeviceIsWireless_Bool, true);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_ContainsProximitySensor_Bool, false);

    UpdateHeadPose(Vector3f{0.0f, 0.0f, 0.0f}, Quaternionf{1.0f, 0.0f, 0.0f, 0.0f});

    return vr::VRInitError_None;
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

void HMDDeviceDriver::GetWindowBounds(int32_t* pnX, int32_t* pnY, uint32_t* pnWidth, uint32_t* pnHeight) {
    *pnX = 0;
    *pnY = 0;
    *pnWidth = 2532;
    *pnHeight = 1170;
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

    if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid) {
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));
    }
}
