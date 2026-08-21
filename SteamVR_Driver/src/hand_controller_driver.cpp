#include "hand_controller_driver.h"
#include "hand_simulation.h"
#include "vrmath.h"
#include <cstring>
#include <cmath>
#include <chrono>
#include <algorithm>

#ifndef DEG_TO_RAD
#define DEG_TO_RAD(deg) ((deg) * 0.017453292519943295f)
#endif

enum EOpenVRBone {
    eBone_Root = 0,
    eBone_Wrist,
    eBone_Thumb0,
    eBone_Thumb1,
    eBone_Thumb2,
    eBone_IndexFinger0,
    eBone_IndexFinger1,
    eBone_IndexFinger2,
    eBone_IndexFinger3,
    eBone_MiddleFinger0,
    eBone_MiddleFinger1,
    eBone_MiddleFinger2,
    eBone_MiddleFinger3,
    eBone_RingFinger0,
    eBone_RingFinger1,
    eBone_RingFinger2,
    eBone_RingFinger3,
    eBone_PinkyFinger0,
    eBone_PinkyFinger1,
    eBone_PinkyFinger2,
    eBone_PinkyFinger3,
    eBone_Aux_Thumb,
    eBone_Aux_IndexFinger,
    eBone_Aux_MiddleFinger,
    eBone_Aux_RingFinger,
    eBone_Aux_PinkyFinger,
    eBone_Count
};

static const float c_fingerLengths[5][5] = {
    { 0.038f, 0.035f, 0.025f, 0.f, 0.f },
    { 0.045f, 0.040f, 0.025f, 0.02f, 0.f },
    { 0.048f, 0.042f, 0.027f, 0.02f, 0.f },
    { 0.045f, 0.040f, 0.025f, 0.02f, 0.f },
    { 0.035f, 0.030f, 0.020f, 0.018f, 0.f }
};

static const float c_metacarpalLength[5] = { 0.03f, 0.065f, 0.063f, 0.058f, 0.052f };
static const float c_metacarpalOffset[5][3] = {
    { 0.025f, 0.015f, 0.01f },
    { 0.03f, 0.08f, 0.015f },
    { 0.01f, 0.095f, 0.015f },
    { -0.01f, 0.09f, 0.015f },
    { -0.025f, 0.08f, 0.015f }
};

static const float c_fingerSplayDefault[5][5] = {
    { 0.15f, 0.05f, 0.f, 0.f, 0.f },
    { 0.05f, 0.05f, 0.035f, 0.025f, 0.f },
    { 0.03f, 0.073f, 0.045f, 0.025f, 0.02f },
    { 0.01f, 0.091f, 0.049f, 0.03f, 0.02f },
    { 0.02f, 0.073f, 0.045f, 0.03f, 0.03f }
};

static inline vr::HmdVector3_t RotateVectorByQuat(const vr::HmdQuaternion_t& q, const vr::HmdVector3_t& v) {
    double qvW = 0.0, qvX = (double)v.v[0], qvY = (double)v.v[1], qvZ = (double)v.v[2];
    double qCW = q.w, qCX = -q.x, qCY = -q.y, qCZ = -q.z;

    double tW = 0.0 - q.x * qvX - q.y * qvY - q.z * qvZ;
    double tX = q.w * qvX + 0.0 + q.y * qvZ - q.z * qvY;
    double tY = q.w * qvY - q.x * qvZ + 0.0 + q.z * qvX;
    double tZ = q.w * qvZ + q.x * qvY - q.y * qvX + 0.0;

    vr::HmdVector3_t res;
    res.v[0] = (float)(tW * qCX + tX * qCW + tY * qCZ - tZ * qCY);
    res.v[1] = (float)(tW * qCY - tX * qCZ + tY * qCW + tZ * qCX);
    res.v[2] = (float)(tW * qCZ + tX * qCY - tY * qCX + tZ * qCW);
    return res;
}

static void ComputeBoneTransform(const vr::ETrackedControllerRole role, const vr::HmdQuaternion_t& orientation, const vr::HmdVector3_t& position, vr::VRBoneTransform_t& out_transform) {
    out_transform.orientation.w = (float)orientation.w;
    out_transform.orientation.x = (float)orientation.x;
    out_transform.orientation.y = (float)orientation.y;
    out_transform.orientation.z = (float)orientation.z;

    out_transform.position.v[0] = (float)position.v[0];
    out_transform.position.v[1] = (float)position.v[1];
    out_transform.position.v[2] = (float)position.v[2];
    out_transform.position.v[3] = 1.0f;

    if (role == vr::TrackedControllerRole_RightHand) {
        out_transform.position.v[0] *= -1.f;
    }
}

static void ComputeBoneTransform(const vr::ETrackedControllerRole role, const vr::HmdQuaternion_t& orientation, const float joint_length, vr::VRBoneTransform_t& out_transform) {
    vr::HmdVector3_t pos = { joint_length, 0.f, 0.f };
    ComputeBoneTransform(role, orientation, pos, out_transform);
}

static void ComputeBoneTransformMetacarpal(const vr::ETrackedControllerRole role, const vr::HmdQuaternion_t& orientation, const float joint_length, vr::VRBoneTransform_t& out_transform) {
    const vr::HmdVector3_t offset = { joint_length, 0.f, 0.f };
    vr::HmdQuaternion_t magic = { 0.5, 0.5, -0.5, 0.5 };
    vr::HmdQuaternion_t bone_orientation = QuatMultiply(magic, orientation);
    vr::HmdVector3_t bone_position = QuatRotateVec(offset, bone_orientation);

    if (role == vr::TrackedControllerRole_RightHand) {
        bone_position.v[0] *= -1.f;
    }
    ComputeBoneTransform(role, bone_orientation, bone_position, out_transform);
}

void HandControllerDriver::ConvertVision21ToSteamVR31(
    const HandPacketData& handData,
    vr::VRBoneTransform_t outBones[31],
    vr::ETrackedControllerRole role
) {
    float curlThumb  = std::clamp(handData.curls.thumb, 0.0f, 1.0f);
    float curlIndex  = std::clamp(handData.curls.index, 0.0f, 1.0f);
    float curlMiddle = std::clamp(handData.curls.middle, 0.0f, 1.0f);
    float curlRing   = std::clamp(handData.curls.ring, 0.0f, 1.0f);
    float curlPinky  = std::clamp(handData.curls.pinky, 0.0f, 1.0f);

    MyFingerCurls curls = { curlThumb, curlIndex, curlMiddle, curlRing, curlPinky };
    MyFingerSplays splays = {
        handData.splays.thumb,
        handData.splays.index,
        handData.splays.middle,
        handData.splays.ring,
        handData.splays.pinky
    };

    static MyHandSimulation sim;
    sim.ComputeSkeletonTransforms(role, curls, splays, outBones);
}

HandControllerDriver::HandControllerDriver(vr::ETrackedControllerRole role)
    : m_role(role),
      m_unObjectId(vr::k_unTrackedDeviceIndexInvalid),
      m_ulPropertyContainer(vr::k_ulInvalidPropertyContainer),
      m_ulSkeletonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTriggerClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTriggerValueComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulGripClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulGripValueComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickXComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickYComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTrackpadXComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTrackpadYComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTrackpadClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTrackpadTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulAButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulBButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulXButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulYButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulSystemButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_poseThreadRunning(false)
{
    memset(&m_pose, 0, sizeof(m_pose));
    m_pose.poseIsValid = false;
    m_pose.deviceIsConnected = true;
    m_pose.result = vr::TrackingResult_Uninitialized;

    m_pose.qWorldFromDriverRotation.w = 1.0;
    m_pose.qDriverFromHeadRotation.w = 1.0;

    m_lastMovementTime = std::chrono::steady_clock::now();
}

HandControllerDriver::~HandControllerDriver() {
    Deactivate();
}

vr::EVRInitError HandControllerDriver::Activate(uint32_t unObjectId) {
    m_unObjectId = unObjectId;
    m_ulPropertyContainer = vr::VRProperties()->TrackedDeviceToPropertyContainer(m_unObjectId);

    bool isLeft = (m_role == vr::TrackedControllerRole_LeftHand);
    const char* renderModel = isLeft ? "valve/valve_controller_knu_ev3_0_left" : "valve/valve_controller_knu_ev3_0_right";
    const char* serialNumber = isLeft ? "iPhoneVR_Hand_Left_001" : "iPhoneVR_Hand_Right_001";

    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ModelNumber_String, "Knuckles EV3");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_RenderModelName_String, renderModel);
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_SerialNumber_String, serialNumber);
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ManufacturerName_String, "Valve");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_TrackingSystemName_String, "lighthouse");
    vr::VRProperties()->SetInt32Property(m_ulPropertyContainer, vr::Prop_DeviceClass_Int32, vr::TrackedDeviceClass_Controller);
    vr::VRProperties()->SetInt32Property(m_ulPropertyContainer, vr::Prop_ControllerRoleHint_Int32, isLeft ? vr::TrackedControllerRole_LeftHand : vr::TrackedControllerRole_RightHand);
    vr::VRProperties()->SetInt32Property(m_ulPropertyContainer, vr::Prop_ControllerHandSelectionPriority_Int32, 20000);

    const char* skeletonPath = isLeft ? "/input/skeleton/left" : "/input/skeleton/right";
    vr::VRDriverInput()->CreateSkeletonComponent(
        m_ulPropertyContainer,
        skeletonPath,
        skeletonPath,
        "/pose/raw",
        vr::VRSkeletalTracking_Partial,
        nullptr,
        0,
        &m_ulSkeletonComponent
    );

    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trigger/click", &m_ulTriggerClickComponent);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trigger/value", &m_ulTriggerValueComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/grip/click", &m_ulGripClickComponent);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/grip/value", &m_ulGripValueComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);

    if (isLeft) {
        vr::VRDriverInput()->CreateBooleanComponent(m_ulXButtonComponent, "/input/x/click", &m_ulXButtonComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulYButtonComponent, "/input/y/click", &m_ulYButtonComponent);
    } else {
        vr::VRDriverInput()->CreateBooleanComponent(m_ulAButtonComponent, "/input/a/click", &m_ulAButtonComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulBButtonComponent, "/input/b/click", &m_ulBButtonComponent);
    }

    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/thumbstick/x", &m_ulThumbstickXComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/thumbstick/y", &m_ulThumbstickYComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/thumbstick/click", &m_ulThumbstickClickComponent);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/thumbstick/touch", &m_ulThumbstickTouchComponent);

    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trackpad/x", &m_ulTrackpadXComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trackpad/y", &m_ulTrackpadYComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trackpad/click", &m_ulTrackpadClickComponent);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trackpad/touch", &m_ulTrackpadTouchComponent);

    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/system/click", &m_ulSystemButtonComponent);

    m_poseThreadRunning = true;
    m_poseThread = std::thread(&HandControllerDriver::PoseLoop, this);

    return vr::VRInitError_None;
}

void HandControllerDriver::Deactivate() {
    m_poseThreadRunning = false;
    if (m_poseThread.joinable()) {
        m_poseThread.join();
    }
    m_unObjectId = vr::k_unTrackedDeviceIndexInvalid;
}

void HandControllerDriver::EnterStandby() {}

void* HandControllerDriver::GetComponent(const char* pchComponentNameAndVersion) {
    return nullptr;
}

void HandControllerDriver::DebugRequest(const char* pchRequest, char* pchResponseBuffer, uint32_t unResponseBufferSize) {
    if (unResponseBufferSize > 0) {
        pchResponseBuffer[0] = 0;
    }
}

void HandControllerDriver::UpdateHandPose(const HandPacketData& handData, const Vector3f& headPos, const Quaternionf& headRot) {
    m_pose.poseIsValid = true;
    m_pose.deviceIsConnected = true;
    m_pose.result = vr::TrackingResult_Running_OK;
    m_pose.qWorldFromDriverRotation = { 1.0, 0.0, 0.0, 0.0 };
    m_pose.qDriverFromHeadRotation = { 1.0, 0.0, 0.0, 0.0 };

    bool isLeft = (m_role == vr::TrackedControllerRole_LeftHand);
    float effectiveHeadY = (headPos.y < 0.5f) ? 1.65f : headPos.y;

    vr::HmdQuaternion_t qHead;
    qHead.w = (double)headRot.w;
    qHead.x = (double)headRot.x;
    qHead.y = (double)headRot.y;
    qHead.z = (double)headRot.z;
    if (qHead.w == 0.0 && qHead.x == 0.0 && qHead.y == 0.0 && qHead.z == 0.0) {
        qHead.w = 1.0;
    }

    auto now = std::chrono::steady_clock::now();

    // Natural local wrist offset relative to HMD head
    vr::HmdVector3_t localWrist;
    if (handData.isTracked == 1) {
        m_lastMovementTime = now;
        localWrist.v[0] = std::clamp(handData.joints[VISION_JOINT_WRIST].position.x, -0.60f, 0.60f);
        localWrist.v[1] = std::clamp(handData.joints[VISION_JOINT_WRIST].position.y, -0.60f, 0.40f);
        localWrist.v[2] = std::clamp(handData.joints[VISION_JOINT_WRIST].position.z, -0.75f, -0.15f);
    } else {
        localWrist.v[0] = isLeft ? -0.22f : 0.22f;
        localWrist.v[1] = -0.20f;
        localWrist.v[2] = -0.35f;
    }

    // Rotate local wrist offset by head rotation into world space
    vr::HmdVector3_t worldWrist = RotateVectorByQuat(qHead, localWrist);
    m_pose.vecPosition[0] = headPos.x + worldWrist.v[0];
    m_pose.vecPosition[1] = effectiveHeadY + worldWrist.v[1];
    m_pose.vecPosition[2] = headPos.z + worldWrist.v[2];

    // Perfect Valve Index Knuckles Controller Mesh Ergonomic Orientation Offset
    // Pitch: -60 deg, Roll: Left +90 deg / Right -90 deg, Yaw: Left +15 deg / Right -15 deg
    double pitchAngle = -1.047;
    double yawAngle   = isLeft ? 0.261 : -0.261;
    double rollAngle  = isLeft ? 1.5707 : -1.5707;

    double cy = cos(yawAngle * 0.5);
    double sy = sin(yawAngle * 0.5);
    double cp = cos(pitchAngle * 0.5);
    double sp = sin(pitchAngle * 0.5);
    double cr = cos(rollAngle * 0.5);
    double sr = sin(rollAngle * 0.5);

    vr::HmdQuaternion_t qKnucklesOffset;
    qKnucklesOffset.w = cr * cp * cy + sr * sp * sy;
    qKnucklesOffset.x = sr * cp * cy - cr * sp * sy;
    qKnucklesOffset.y = cr * sp * cy + sr * cp * sy;
    qKnucklesOffset.z = cr * cp * sy - sr * sp * cy;

    m_pose.qRotation = QuatMultiply(qHead, qKnucklesOffset);

    if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid) {
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));

        bool btnPrimary = false;
        bool btnSecondary = false;
        bool btnStickClick = false;
        float trigVal = 0.0f;
        float gripVal = 0.0f;
        float stickX = 0.0f;
        float stickY = 0.0f;

        if (handData.controller.isConnected == 1) {
            trigVal = handData.controller.triggerValue;
            gripVal = handData.controller.gripValue;
            stickX = handData.controller.stickX;
            stickY = handData.controller.stickY;

            btnPrimary = (handData.controller.buttonMask & (1 << 0)) != 0;
            btnSecondary = (handData.controller.buttonMask & (1 << 1)) != 0;
            btnStickClick = (handData.controller.buttonMask & (1 << 2)) != 0;
        } else if (handData.isPinching == 1) {
            trigVal = 1.0f;
        }

        if (isLeft) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulXButtonComponent, btnPrimary, 0);
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulYButtonComponent, btnSecondary, 0);
        } else {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulAButtonComponent, btnPrimary, 0);
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulBButtonComponent, btnSecondary, 0);
        }

        vr::VRDriverInput()->UpdateScalarComponent(m_ulTriggerValueComponent, trigVal, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulTriggerClickComponent, trigVal > 0.75f, 0);

        vr::VRDriverInput()->UpdateScalarComponent(m_ulGripValueComponent, gripVal, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulGripClickComponent, gripVal > 0.75f, 0);

        vr::VRDriverInput()->UpdateScalarComponent(m_ulThumbstickXComponent, stickX, 0);
        vr::VRDriverInput()->UpdateScalarComponent(m_ulThumbstickYComponent, stickY, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulThumbstickClickComponent, btnStickClick, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulThumbstickTouchComponent, (std::abs(stickX) > 0.05f || std::abs(stickY) > 0.05f), 0);

        vr::VRBoneTransform_t bones[31];
        ConvertVision21ToSteamVR31(handData, bones, m_role);
        vr::VRDriverInput()->UpdateSkeletonComponent(m_ulSkeletonComponent, vr::VRSkeletalMotionRange_WithController, bones, 31);
        vr::VRDriverInput()->UpdateSkeletonComponent(m_ulSkeletonComponent, vr::VRSkeletalMotionRange_WithoutController, bones, 31);
    }
}

void HandControllerDriver::PoseLoop() {
    while (m_poseThreadRunning) {
        std::this_thread::sleep_for(std::chrono::milliseconds(11));
        if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid && m_pose.poseIsValid) {
            vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));
        }
    }
}
