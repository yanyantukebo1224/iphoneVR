#include "hand_controller_driver.h"
#include <cstring>
#include <cmath>
#include <chrono>
#include <algorithm>

static inline void SetBone(vr::VRBoneTransform_t& b, float px, float py, float pz, float qw = 1.0f, float qx = 0.0f, float qy = 0.0f, float qz = 0.0f) {
    b.position.v[0] = px;
    b.position.v[1] = py;
    b.position.v[2] = pz;
    b.orientation.w = qw;
    b.orientation.x = qx;
    b.orientation.y = qy;
    b.orientation.z = qz;
}

static inline Quaternionf GetBoneRotation(float curlFactor, float maxAngleRad) {
    float angle = curlFactor * maxAngleRad;
    return Quaternionf{ std::cos(angle * 0.5f), std::sin(angle * 0.5f), 0.0f, 0.0f };
}

HandControllerDriver::HandControllerDriver(vr::ETrackedControllerRole role)
    : m_role(role), m_unObjectId(vr::k_unTrackedDeviceIndexInvalid),
      m_ulPropertyContainer(vr::k_ulInvalidPropertyContainer),
      m_ulSkeletonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTriggerClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTriggerValueComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulGripClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulGripValueComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulAButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulBButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulXButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulYButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickXComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickYComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulSystemButtonComponent(vr::k_ulInvalidInputComponentHandle),
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
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/grip/value", &m_ulGripValueComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);

    if (isLeft) {
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/x/click", &m_ulXButtonComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/y/click", &m_ulYButtonComponent);
    } else {
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/a/click", &m_ulAButtonComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/b/click", &m_ulBButtonComponent);
    }

    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/thumbstick/x", &m_ulThumbstickXComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/thumbstick/y", &m_ulThumbstickYComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/thumbstick/click", &m_ulThumbstickClickComponent);

    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/system/click", &m_ulSystemButtonComponent);

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
    float defaultOffsetY = -0.25f;
    float defaultOffsetZ = -0.35f;

    float rawX = handData.joints[VISION_JOINT_WRIST].position.x;
    float rawY = handData.joints[VISION_JOINT_WRIST].position.y;
    float rawZ = handData.joints[VISION_JOINT_WRIST].position.z;

    if (rawX != rawX) rawX = 0.0f;
    if (rawY != rawY) rawY = 0.0f;
    if (rawZ != rawZ) rawZ = 0.0f;

    auto now = std::chrono::steady_clock::now();
    float deltaMovement = std::sqrt(
        (rawX - m_lastPosition[0]) * (rawX - m_lastPosition[0]) +
        (rawY - m_lastPosition[1]) * (rawY - m_lastPosition[1]) +
        (rawZ - m_lastPosition[2]) * (rawZ - m_lastPosition[2])
    );

    if (handData.isTracked == 1 && deltaMovement > 0.001f) {
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

    float easingFactor = 0.35f;
    m_smoothedPosition[0] += (targetOffsetX - m_smoothedPosition[0]) * easingFactor;
    m_smoothedPosition[1] += (targetOffsetY - m_smoothedPosition[1]) * easingFactor;
    m_smoothedPosition[2] += (targetOffsetZ - m_smoothedPosition[2]) * easingFactor;

    m_pose.vecPosition[0] = headPos.x + m_smoothedPosition[0];
    m_pose.vecPosition[1] = effectiveHeadY + m_smoothedPosition[1];
    m_pose.vecPosition[2] = headPos.z + m_smoothedPosition[2];

    if (handData.controller.isConnected == 1 && 
        (handData.controller.controllerRot.w != 0.0f || handData.controller.controllerRot.x != 0.0f || 
         handData.controller.controllerRot.y != 0.0f || handData.controller.controllerRot.z != 0.0f)) {
        m_pose.qRotation.w = handData.controller.controllerRot.w;
        m_pose.qRotation.x = handData.controller.controllerRot.x;
        m_pose.qRotation.y = handData.controller.controllerRot.y;
        m_pose.qRotation.z = handData.controller.controllerRot.z;
    } else {
        m_pose.qRotation.w = 0.92388f;
        m_pose.qRotation.x = 0.38268f;
        m_pose.qRotation.y = 0.0f;
        m_pose.qRotation.z = 0.0f;
    }

    if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid) {
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));

        bool isTriggerClicked = false;
        float trigVal = 0.0f;
        bool isGripClicked = false;
        float gripVal = 0.0f;
        bool btnAorX = false;
        bool btnBorY = false;
        bool stickClicked = false;
        bool systemClicked = false;
        float stickX = 0.0f;
        float stickY = 0.0f;

        if (handData.controller.isConnected == 1) {
            uint32_t mask = handData.controller.buttonMask;
            btnAorX = (mask & BTN_A_OR_X) != 0;
            btnBorY = (mask & BTN_B_OR_Y) != 0;
            isTriggerClicked = (mask & BTN_TRIGGER_CLICK) != 0 || (handData.controller.triggerValue > 0.5f);
            trigVal = handData.controller.triggerValue;
            if (isTriggerClicked && trigVal < 0.1f) trigVal = 1.0f;

            isGripClicked = (mask & BTN_GRIP_CLICK) != 0 || (handData.controller.gripValue > 0.5f);
            gripVal = handData.controller.gripValue;
            if (isGripClicked && gripVal < 0.1f) gripVal = 1.0f;

            stickClicked = (mask & BTN_THUMBSTICK_CLICK) != 0;
            systemClicked = (mask & BTN_SYSTEM) != 0;
            stickX = handData.controller.stickX;
            stickY = handData.controller.stickY;
        } else {
            bool isPinchingActive = (handData.isPinching == 1);
            isTriggerClicked = isPinchingActive || (handData.curls.index > 0.65f);
            trigVal = isPinchingActive ? 1.0f : handData.curls.index;

            float avgGripCurl = (handData.curls.middle + handData.curls.ring + handData.curls.pinky) / 3.0f;
            isGripClicked = (avgGripCurl > 0.70f);
            gripVal = avgGripCurl;
        }

        if (m_ulTriggerClickComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulTriggerClickComponent, isTriggerClicked, 0);
        }
        if (m_ulTriggerValueComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateScalarComponent(m_ulTriggerValueComponent, trigVal, 0);
        }

        if (m_ulGripClickComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulGripClickComponent, isGripClicked, 0);
        }
        if (m_ulGripValueComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateScalarComponent(m_ulGripValueComponent, gripVal, 0);
        }

        if (isLeft) {
            if (m_ulXButtonComponent != vr::k_ulInvalidInputComponentHandle) {
                vr::VRDriverInput()->UpdateBooleanComponent(m_ulXButtonComponent, btnAorX, 0);
            }
            if (m_ulYButtonComponent != vr::k_ulInvalidInputComponentHandle) {
                vr::VRDriverInput()->UpdateBooleanComponent(m_ulYButtonComponent, btnBorY, 0);
            }
        } else {
            if (m_ulAButtonComponent != vr::k_ulInvalidInputComponentHandle) {
                vr::VRDriverInput()->UpdateBooleanComponent(m_ulAButtonComponent, btnAorX, 0);
            }
            if (m_ulBButtonComponent != vr::k_ulInvalidInputComponentHandle) {
                vr::VRDriverInput()->UpdateBooleanComponent(m_ulBButtonComponent, btnBorY, 0);
            }
        }

        if (m_ulThumbstickXComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateScalarComponent(m_ulThumbstickXComponent, stickX, 0);
        }
        if (m_ulThumbstickYComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateScalarComponent(m_ulThumbstickYComponent, stickY, 0);
        }
        if (m_ulThumbstickClickComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulThumbstickClickComponent, stickClicked, 0);
        }

        if (m_ulSystemButtonComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulSystemButtonComponent, systemClicked, 0);
        }

        vr::VRBoneTransform_t bones[31];
        ConvertVision21ToSteamVR31(handData, bones);
        if (m_ulSkeletonComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateSkeletonComponent(m_ulSkeletonComponent, vr::VRSkeletalMotionRange_WithController, bones, 31);
        }
    }
}

static inline Quaternionf GetBoneRotationMultiAxis(float pitchAngleRad, float yawAngleRad, float rollAngleRad = 0.0f) {
    float cp = std::cos(pitchAngleRad * 0.5f), sp = std::sin(pitchAngleRad * 0.5f);
    float cy = std::cos(yawAngleRad * 0.5f),   sy = std::sin(yawAngleRad * 0.5f);
    float cr = std::cos(rollAngleRad * 0.5f),  sr = std::sin(rollAngleRad * 0.5f);

    Quaternionf q;
    q.w = cr * cp * cy + sr * sp * sy;
    q.x = sr * cp * cy - cr * sp * sy;
    q.y = cr * sp * cy + sr * cp * sy;
    q.z = cr * cp * sy - sr * sp * cy;
    return q;
}

void HandControllerDriver::ConvertVision21ToSteamVR31(
    const HandPacketData& handData,
    vr::VRBoneTransform_t outBones[31]
) {
    for (int i = 0; i < 31; ++i) {
        SetBone(outBones[i], 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f);
    }

    SetBone(outBones[0], 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f);
    SetBone(outBones[1], 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f);

    float curlThumb  = (handData.curls.thumb < 0.0f) ? 0.0f : ((handData.curls.thumb > 1.0f) ? 1.0f : handData.curls.thumb);
    float curlIndex  = (handData.curls.index < 0.0f) ? 0.0f : ((handData.curls.index > 1.0f) ? 1.0f : handData.curls.index);
    float curlMiddle = (handData.curls.middle < 0.0f) ? 0.0f : ((handData.curls.middle > 1.0f) ? 1.0f : handData.curls.middle);
    float curlRing   = (handData.curls.ring < 0.0f) ? 0.0f : ((handData.curls.ring > 1.0f) ? 1.0f : handData.curls.ring);
    float curlPinky  = (handData.curls.pinky < 0.0f) ? 0.0f : ((handData.curls.pinky > 1.0f) ? 1.0f : handData.curls.pinky);

    float splayThumb  = handData.splays.thumb;
    float splayIndex  = handData.splays.index;
    float splayMiddle = handData.splays.middle;
    float splayRing   = handData.splays.ring;
    float splayPinky  = handData.splays.pinky;

    if (handData.isPinching == 1) {
        if (curlThumb < 0.85f) curlThumb = 0.85f;
        if (curlIndex < 0.90f) curlIndex = 0.90f;
    }

    // 1. Thumb (Opposition + Multi-joint curl)
    Quaternionf qThumbRoot = GetBoneRotationMultiAxis(curlThumb * 0.40f, splayThumb * 0.35f, curlThumb * 0.25f);
    Quaternionf qThumbMP   = GetBoneRotationMultiAxis(curlThumb * 0.45f, 0.0f, 0.0f);
    Quaternionf qThumbIP   = GetBoneRotationMultiAxis(curlThumb * 0.35f, 0.0f, 0.0f);

    SetBone(outBones[2],  0.030f, -0.015f,  0.025f, qThumbRoot.w, qThumbRoot.x, qThumbRoot.y, qThumbRoot.z);
    SetBone(outBones[3],  0.000f,  0.000f,  0.035f, qThumbMP.w, qThumbMP.x, qThumbMP.y, qThumbMP.z);
    SetBone(outBones[4],  0.000f,  0.000f,  0.030f, qThumbIP.w, qThumbIP.x, qThumbIP.y, qThumbIP.z);
    SetBone(outBones[5],  0.000f,  0.000f,  0.025f, 1.0f, 0.0f, 0.0f, 0.0f);

    // 2. Index (Splay + 3-joint progressive curl)
    Quaternionf qIndexMCP = GetBoneRotationMultiAxis(curlIndex * 0.50f, splayIndex * 0.30f, 0.0f);
    Quaternionf qIndexPIP = GetBoneRotationMultiAxis(curlIndex * 0.35f, 0.0f, 0.0f);
    Quaternionf qIndexDIP = GetBoneRotationMultiAxis(curlIndex * 0.20f, 0.0f, 0.0f);

    SetBone(outBones[6],  0.000f,  0.000f,  0.000f, 1.0f, 0.0f, 0.0f, 0.0f);
    SetBone(outBones[7],  0.025f,  0.000f,  0.065f, qIndexMCP.w, qIndexMCP.x, qIndexMCP.y, qIndexMCP.z);
    SetBone(outBones[8],  0.000f,  0.000f,  0.040f, qIndexPIP.w, qIndexPIP.x, qIndexPIP.y, qIndexPIP.z);
    SetBone(outBones[9],  0.000f,  0.000f,  0.030f, qIndexDIP.w, qIndexDIP.x, qIndexDIP.y, qIndexDIP.z);
    SetBone(outBones[10], 0.000f,  0.000f,  0.022f, 1.0f, 0.0f, 0.0f, 0.0f);

    // 3. Middle (Splay + 3-joint progressive curl)
    Quaternionf qMidMCP = GetBoneRotationMultiAxis(curlMiddle * 0.52f, splayMiddle * 0.15f, 0.0f);
    Quaternionf qMidPIP = GetBoneRotationMultiAxis(curlMiddle * 0.36f, 0.0f, 0.0f);
    Quaternionf qMidDIP = GetBoneRotationMultiAxis(curlMiddle * 0.20f, 0.0f, 0.0f);

    SetBone(outBones[11], 0.000f,  0.000f,  0.000f, 1.0f, 0.0f, 0.0f, 0.0f);
    SetBone(outBones[12], 0.000f,  0.000f,  0.070f, qMidMCP.w, qMidMCP.x, qMidMCP.y, qMidMCP.z);
    SetBone(outBones[13], 0.000f,  0.000f,  0.045f, qMidPIP.w, qMidPIP.x, qMidPIP.y, qMidPIP.z);
    SetBone(outBones[14], 0.000f,  0.000f,  0.032f, qMidDIP.w, qMidDIP.x, qMidDIP.y, qMidDIP.z);
    SetBone(outBones[15], 0.000f,  0.000f,  0.024f, 1.0f, 0.0f, 0.0f, 0.0f);

    // 4. Ring (Splay + 3-joint progressive curl)
    Quaternionf qRingMCP = GetBoneRotationMultiAxis(curlRing * 0.52f, splayRing * 0.25f, 0.0f);
    Quaternionf qRingPIP = GetBoneRotationMultiAxis(curlRing * 0.36f, 0.0f, 0.0f);
    Quaternionf qRingDIP = GetBoneRotationMultiAxis(curlRing * 0.20f, 0.0f, 0.0f);

    SetBone(outBones[16], 0.000f,  0.000f,  0.000f, 1.0f, 0.0f, 0.0f, 0.0f);
    SetBone(outBones[17], -0.020f, 0.000f,  0.065f, qRingMCP.w, qRingMCP.x, qRingMCP.y, qRingMCP.z);
    SetBone(outBones[18],  0.000f, 0.000f,  0.038f, qRingPIP.w, qRingPIP.x, qRingPIP.y, qRingPIP.z);
    SetBone(outBones[19],  0.000f, 0.000f,  0.028f, qRingDIP.w, qRingDIP.x, qRingDIP.y, qRingDIP.z);
    SetBone(outBones[20],  0.000f, 0.000f,  0.022f, 1.0f, 0.0f, 0.0f, 0.0f);

    // 5. Pinky (Splay + 3-joint progressive curl)
    Quaternionf qPinkyMCP = GetBoneRotationMultiAxis(curlPinky * 0.50f, splayPinky * 0.35f, 0.0f);
    Quaternionf qPinkyPIP = GetBoneRotationMultiAxis(curlPinky * 0.35f, 0.0f, 0.0f);
    Quaternionf qPinkyDIP = GetBoneRotationMultiAxis(curlPinky * 0.20f, 0.0f, 0.0f);

    SetBone(outBones[21], 0.000f,  0.000f,  0.000f, 1.0f, 0.0f, 0.0f, 0.0f);
    SetBone(outBones[22], -0.040f, -0.010f, 0.055f, qPinkyMCP.w, qPinkyMCP.x, qPinkyMCP.y, qPinkyMCP.z);
    SetBone(outBones[23],  0.000f,  0.000f, 0.030f, qPinkyPIP.w, qPinkyPIP.x, qPinkyPIP.y, qPinkyPIP.z);
    SetBone(outBones[24],  0.000f,  0.000f, 0.022f, qPinkyDIP.w, qPinkyDIP.x, qPinkyDIP.y, qPinkyDIP.z);
    SetBone(outBones[25],  0.000f,  0.000f, 0.018f, 1.0f, 0.0f, 0.0f, 0.0f);

    outBones[26] = outBones[5];
    outBones[27] = outBones[10];
    outBones[28] = outBones[15];
    outBones[29] = outBones[20];
    outBones[30] = outBones[25];
}
