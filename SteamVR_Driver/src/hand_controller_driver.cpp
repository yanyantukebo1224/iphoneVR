#include "hand_controller_driver.h"
#include <cstring>
#include <cmath>
#include <chrono>

HandControllerDriver::HandControllerDriver(vr::ETrackedControllerRole role)
    : m_role(role), m_unObjectId(vr::k_unTrackedDeviceIndexInvalid),
      m_ulPropertyContainer(vr::k_ulInvalidPropertyContainer),
      m_ulSkeletonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTriggerClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTriggerValueComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulGripClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_isTracked(false),
      m_lastMovementTime(std::chrono::steady_clock::now()),
      m_lastPosition{0.0f, 0.0f, 0.0f},
      m_smoothedPosition{0.0f, 0.0f, 0.0f} {
    std::memset(&m_pose, 0, sizeof(m_pose));
    m_pose.poseIsValid = true;
    m_pose.deviceIsConnected = true;
    m_pose.result = vr::TrackingResult_Running_OK;
    
    m_pose.qRotation.w = 1.0;
    m_pose.qWorldFromDriverRotation.w = 1.0;
    m_pose.qDriverFromHeadRotation.w = 1.0;
}

HandControllerDriver::~HandControllerDriver() {}

vr::EVRInitError HandControllerDriver::Activate(uint32_t unObjectId) {
    m_unObjectId = unObjectId;
    m_ulPropertyContainer = vr::VRProperties()->TrackedDeviceToPropertyContainer(m_unObjectId);

    bool isLeft = (m_role == vr::TrackedControllerRole_LeftHand);
    
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_TrackingSystemName_String, "driver_iphonevr");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ModelNumber_String, isLeft ? "iPhoneVR Left Hand" : "iPhoneVR Right Hand");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_SerialNumber_String, isLeft ? "iPhoneVR_LeftHand_001" : "iPhoneVR_RightHand_001");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ManufacturerName_String, "HTC/Valve/iPhoneVR");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_RenderModelName_String, "vr_controller_vive_1_5");
    
    vr::VRProperties()->SetInt32Property(m_ulPropertyContainer, vr::Prop_ControllerRoleHint_Int32, m_role);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_WillDriftInYaw_Bool, false);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_DeviceIsWireless_Bool, true);
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_InputProfilePath_String, "{driver_iphonevr}/resources/input/iphonevr_controller_profile.json");

    const char* skelComponentPath = isLeft ? "/input/skeleton/left" : "/input/skeleton/right";
    vr::VRDriverInput()->CreateSkeletonComponent(
        m_ulPropertyContainer,
        skelComponentPath,
        skelComponentPath,
        isLeft ? "/skeleton/hand/left" : "/skeleton/hand/right",
        vr::VRSkeletalTracking_Full,
        nullptr,
        0,
        &m_ulSkeletonComponent
    );

    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trigger/click", &m_ulTriggerClickComponent);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trigger/value", &m_ulTriggerValueComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/grip/click", &m_ulGripClickComponent);

    HandPacketData dummyHand{};
    dummyHand.isTracked = 1;
    dummyHand.joints[VISION_JOINT_WRIST].position = Vector3f{0.0f, 0.0f, 0.0f};

    UpdateHandPose(dummyHand, Vector3f{0.0f, 1.65f, 0.0f});

    return vr::VRInitError_None;
}

void HandControllerDriver::UpdateHandPose(const HandPacketData& handData, const Vector3f& headPos) {
    m_pose.poseIsValid = true;
    m_pose.deviceIsConnected = true;
    m_pose.result = vr::TrackingResult_Running_OK;
    m_pose.qWorldFromDriverRotation.w = 1.0;

    bool isLeft = (m_role == vr::TrackedControllerRole_LeftHand);
    float effectiveHeadY = (headPos.y < 1.0f) ? 1.65f : headPos.y;

    float defaultOffsetX = isLeft ? -0.20f : 0.20f;
    float defaultOffsetY = -0.22f;
    float defaultOffsetZ = -0.35f;

    float rawX = handData.joints[VISION_JOINT_WRIST].position.x;
    float rawY = handData.joints[VISION_JOINT_WRIST].position.y;
    float rawZ = handData.joints[VISION_JOINT_WRIST].position.z;

    if (rawX != rawX) rawX = 0.0f;
    if (rawY != rawY) rawY = 0.0f;
    if (rawZ != rawZ) rawZ = 0.0f;

    // 異常値飛びガード
    if (std::abs(rawX) > 0.60f) rawX = (rawX > 0) ? 0.60f : -0.60f;
    if (std::abs(rawY) > 0.60f) rawY = (rawY > 0) ? 0.60f : -0.60f;
    if (std::abs(rawZ) > 0.60f) rawZ = (rawZ > 0) ? 0.60f : -0.60f;

    auto now = std::chrono::steady_clock::now();
    float deltaMovement = std::sqrt(
        (rawX - m_lastPosition[0]) * (rawX - m_lastPosition[0]) +
        (rawY - m_lastPosition[1]) * (rawY - m_lastPosition[1]) +
        (rawZ - m_lastPosition[2]) * (rawZ - m_lastPosition[2])
    );

    if (handData.isTracked == 1 && deltaMovement > 0.002f) {
        m_lastMovementTime = now;
        m_lastPosition[0] = rawX;
        m_lastPosition[1] = rawY;
        m_lastPosition[2] = rawZ;
    }

    auto elapsedSeconds = std::chrono::duration_cast<std::chrono::seconds>(now - m_lastMovementTime).count();

    float targetOffsetX = defaultOffsetX;
    float targetOffsetY = defaultOffsetY;
    float targetOffsetZ = defaultOffsetZ;

    if (elapsedSeconds < 3 && handData.isTracked == 1) {
        targetOffsetX = defaultOffsetX + rawX;
        targetOffsetY = defaultOffsetY + rawY;
        targetOffsetZ = defaultOffsetZ + rawZ;
    }

    // Cubic Ease-Out イージング補間
    float easingFactor = 0.25f;
    m_smoothedPosition[0] += (targetOffsetX - m_smoothedPosition[0]) * easingFactor;
    m_smoothedPosition[1] += (targetOffsetY - m_smoothedPosition[1]) * easingFactor;
    m_smoothedPosition[2] += (targetOffsetZ - m_smoothedPosition[2]) * easingFactor;

    m_pose.vecPosition[0] = headPos.x + m_smoothedPosition[0];
    m_pose.vecPosition[1] = effectiveHeadY + m_smoothedPosition[1];
    m_pose.vecPosition[2] = headPos.z + m_smoothedPosition[2];

    m_pose.qRotation.w = 0.92388f;
    m_pose.qRotation.x = 0.38268f;
    m_pose.qRotation.y = 0.0f;
    m_pose.qRotation.z = 0.0f;

    if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid) {
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));

        bool isPinchingActive = (handData.isPinching == 1);
        float trigVal = isPinchingActive ? 1.0f : 0.0f;

        if (m_ulTriggerClickComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulTriggerClickComponent, isPinchingActive, 0);
        }
        if (m_ulTriggerValueComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateScalarComponent(m_ulTriggerValueComponent, trigVal, 0);
        }
        if (m_ulGripClickComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulGripClickComponent, isPinchingActive, 0);
        }

        vr::VRBoneTransform_t bones[31];
        ConvertVision21ToSteamVR31(handData, bones);
        if (m_ulSkeletonComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateSkeletonComponent(m_ulSkeletonComponent, vr::VRSkeletalMotionRange_WithController, bones, 31);
        }
    }
}

void HandControllerDriver::ConvertVision21ToSteamVR31(
    const HandPacketData& handData,
    vr::VRBoneTransform_t outBones[31]
) {
    auto makeBone = [](vr::VRBoneTransform_t& b, float px, float py, float pz, float qw=1.0f, float qx=0.0f, float qy=0.0f, float qz=0.0f) {
        b.position.v[0] = px;
        b.position.v[1] = py;
        b.position.v[2] = pz;
        b.orientation.w = qw;
        b.orientation.x = qx;
        b.orientation.y = qy;
        b.orientation.z = qz;
    };

    for (int i = 0; i < 31; ++i) {
        makeBone(outBones[i], 0, 0, 0);
    }

    makeBone(outBones[0], 0, 0, 0);
    makeBone(outBones[1], 0, 0, 0);

    bool isPinch = (handData.isPinching == 1);
    float curlAngle = isPinch ? 1.1f : 0.15f;

    float qw = std::cos(curlAngle / 2.0f);
    float qx = std::sin(curlAngle / 2.0f);

    struct FingerMapping {
        int rootIndex;
        float defaultX, defaultY, defaultZ;
    } fingers[] = {
        { 2,   0.03f, -0.01f,  0.03f },
        { 7,   0.02f,  0.0f,   0.06f },
        { 12,  0.00f,  0.0f,   0.07f },
        { 17, -0.02f,  0.0f,   0.06f },
        { 22, -0.04f, -0.01f,  0.05f }
    };

    for (const auto& f : fingers) {
        makeBone(outBones[f.rootIndex], f.defaultX, f.defaultY, f.defaultZ, qw, qx, 0, 0);
        makeBone(outBones[f.rootIndex + 1], 0.0f, 0.0f, 0.03f, qw, qx, 0, 0);
        makeBone(outBones[f.rootIndex + 2], 0.0f, 0.0f, 0.025f, qw, qx, 0, 0);
        makeBone(outBones[f.rootIndex + 3], 0.0f, 0.0f, 0.02f, 1.0f, 0, 0, 0);
    }

    outBones[26] = outBones[5];
    outBones[27] = outBones[10];
    outBones[28] = outBones[15];
    outBones[29] = outBones[20];
    outBones[30] = outBones[25];
}
