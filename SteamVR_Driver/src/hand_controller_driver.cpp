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

static float CalculateFingerAngleCurl(const BoneTransform& mcp, const BoneTransform& pip, const BoneTransform& tip) {
    float v1x = pip.position.x - mcp.position.x;
    float v1y = pip.position.y - mcp.position.y;
    float v1z = pip.position.z - mcp.position.z;
    float len1 = std::sqrt(v1x * v1x + v1y * v1y + v1z * v1z);

    float v2x = tip.position.x - pip.position.x;
    float v2y = tip.position.y - pip.position.y;
    float v2z = tip.position.z - pip.position.z;
    float len2 = std::sqrt(v2x * v2x + v2y * v2y + v2z * v2z);

    if (len1 < 0.001f || len2 < 0.001f) return 0.0f;

    float dot = (v1x * v2x + v1y * v2y + v1z * v2z) / (len1 * len2);
    dot = std::clamp(dot, -1.0f, 1.0f);
    float angleRad = std::acos(dot);

    return std::clamp(angleRad / 1.5708f, 0.0f, 1.0f);
}

void HandControllerDriver::ConvertVision21ToSteamVR31(
    const HandPacketData& handData,
    vr::VRBoneTransform_t outBones[31],
    vr::ETrackedControllerRole role
) {
    float curlThumb  = CalculateFingerAngleCurl(handData.joints[1], handData.joints[2], handData.joints[4]);
    float curlIndex  = CalculateFingerAngleCurl(handData.joints[5], handData.joints[6], handData.joints[8]);
    float curlMiddle = CalculateFingerAngleCurl(handData.joints[9], handData.joints[10], handData.joints[12]);
    float curlRing   = CalculateFingerAngleCurl(handData.joints[13], handData.joints[14], handData.joints[16]);
    float curlPinky  = CalculateFingerAngleCurl(handData.joints[17], handData.joints[18], handData.joints[20]);

    MyFingerCurls curls = { curlThumb, curlIndex, curlMiddle, curlRing, curlPinky };
    MyFingerSplays splays = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };

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
      m_ulTriggerTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulGripClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulGripValueComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulGripTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulAButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulATouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulBButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulBTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulXButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulXTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulYButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulYTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickXComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickYComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulThumbstickTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTrackpadXComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTrackpadYComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTrackpadTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTrackpadClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulSystemButtonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulSystemTouchComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulHapticComponent(vr::k_ulInvalidInputComponentHandle),
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

    // Trigger
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trigger/click", &m_ulTriggerClickComponent);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trigger/touch", &m_ulTriggerTouchComponent);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trigger/value", &m_ulTriggerValueComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);

    // Grip
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/grip/click", &m_ulGripClickComponent);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/grip/touch", &m_ulGripTouchComponent);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/grip/value", &m_ulGripValueComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);

    // Buttons
    if (isLeft) {
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/x/click", &m_ulXButtonComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/x/touch", &m_ulXTouchComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/y/click", &m_ulYButtonComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/y/touch", &m_ulYTouchComponent);
    } else {
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/a/click", &m_ulAButtonComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/a/touch", &m_ulATouchComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/b/click", &m_ulBButtonComponent);
        vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/b/touch", &m_ulBTouchComponent);
    }

    // Thumbstick
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/thumbstick/x", &m_ulThumbstickXComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/thumbstick/y", &m_ulThumbstickYComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/thumbstick/click", &m_ulThumbstickClickComponent);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/thumbstick/touch", &m_ulThumbstickTouchComponent);

    // Trackpad
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trackpad/x", &m_ulTrackpadXComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trackpad/y", &m_ulTrackpadYComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trackpad/click", &m_ulTrackpadClickComponent);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trackpad/touch", &m_ulTrackpadTouchComponent);

    // System Button
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/system/click", &m_ulSystemButtonComponent);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/system/touch", &m_ulSystemTouchComponent);

    // Haptics
    vr::VRDriverInput()->CreateHapticComponent(m_ulPropertyContainer, "/output/haptic", &m_ulHapticComponent);

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

    // 1. Wrist 3D Position
    vr::HmdVector3_t localWrist;
    if (handData.isTracked == 1) {
        m_lastMovementTime = now;
        localWrist.v[0] = std::clamp(handData.joints[0].position.x, -0.60f, 0.60f);
        localWrist.v[1] = std::clamp(handData.joints[0].position.y, -0.60f, 0.40f);
        localWrist.v[2] = std::clamp(handData.joints[0].position.z, -0.75f, -0.15f);
    } else {
        localWrist.v[0] = isLeft ? -0.22f : 0.22f;
        localWrist.v[1] = -0.20f;
        localWrist.v[2] = -0.35f;
    }

    vr::HmdVector3_t worldWrist = RotateVectorByQuat(qHead, localWrist);
    m_pose.vecPosition[0] = headPos.x + worldWrist.v[0];
    m_pose.vecPosition[1] = effectiveHeadY + worldWrist.v[1];
    m_pose.vecPosition[2] = headPos.z + worldWrist.v[2];

    // 2. Knuckles base grip offset
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

    // 3. Solve 3D Wrist Orientation from 21 MediaPipe Landmarks
    vr::HmdQuaternion_t qWrist = { 1.0, 0.0, 0.0, 0.0 };
    if (handData.isTracked == 1) {
        float fwdX = handData.joints[9].position.x - handData.joints[0].position.x;
        float fwdY = handData.joints[9].position.y - handData.joints[0].position.y;
        float fwdZ = handData.joints[9].position.z - handData.joints[0].position.z;
        float fLen = std::sqrt(fwdX * fwdX + fwdY * fwdY + fwdZ * fwdZ);

        if (fLen > 0.01f) {
            fwdX /= fLen; fwdY /= fLen; fwdZ /= fLen;

            float rX = handData.joints[17].position.x - handData.joints[5].position.x;
            float rY = handData.joints[17].position.y - handData.joints[5].position.y;
            float rZ = handData.joints[17].position.z - handData.joints[5].position.z;
            float rLen = std::sqrt(rX * rX + rY * rY + rZ * rZ);

            if (rLen > 0.01f) {
                rX /= rLen; rY /= rLen; rZ /= rLen;
                float upX = rY * fwdZ - rZ * fwdY;
                float upY = rZ * fwdX - rX * fwdZ;
                float upZ = rX * fwdY - rY * fwdX;

                double trace = rX + upY + fwdZ;
                if (trace > 0) {
                    double s = 0.5 / sqrt(trace + 1.0);
                    qWrist.w = 0.25 / s;
                    qWrist.x = (upZ - fwdY) * s;
                    qWrist.y = (fwdX - rZ) * s;
                    qWrist.z = (rY - upX) * s;
                }
            }
        }
    }

    vr::HmdQuaternion_t qCombinedLocal = QuatMultiply(qWrist, qKnucklesOffset);
    m_pose.qRotation = QuatMultiply(qHead, qCombinedLocal);

    if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid) {
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));

        // Full Controller Input Mapping
        bool btnPrimary = false;   // Bit 0: A/X
        bool btnSecondary = false; // Bit 1: B/Y
        bool btnXorPlus = false;   // Bit 2: X/+
        bool btnYorMinus = false;  // Bit 3: Y/-
        bool btnTrigClick = false; // Bit 4: Trigger Click
        bool btnGripClick = false; // Bit 5: Grip Click
        bool btnStickClick = false;// Bit 6: Stick Click
        bool btnSystem = false;    // Bit 7: System Button

        float trigVal = 0.0f;
        float gripVal = 0.0f;
        float stickX = 0.0f;
        float stickY = 0.0f;

        if (handData.controller.isConnected == 1) {
            trigVal = handData.controller.triggerValue;
            gripVal = handData.controller.gripValue;
            stickX = handData.controller.stickX;
            stickY = handData.controller.stickY;

            uint32_t mask = handData.controller.buttonMask;
            btnPrimary    = (mask & (1 << 0)) != 0;
            btnSecondary  = (mask & (1 << 1)) != 0;
            btnXorPlus    = (mask & (1 << 2)) != 0;
            btnYorMinus   = (mask & (1 << 3)) != 0;
            btnTrigClick  = (mask & (1 << 4)) != 0;
            btnGripClick  = (mask & (1 << 5)) != 0;
            btnStickClick = (mask & (1 << 6)) != 0;
            btnSystem     = (mask & (1 << 7)) != 0;

            if (btnTrigClick && trigVal < 0.5f) {
                trigVal = 1.0f;
            }
            if (btnGripClick && gripVal < 0.5f) {
                gripVal = 1.0f;
            }
        } else if (handData.isPinching == 1) {
            trigVal = 1.0f;
            btnPrimary = true;
        }

        bool isStickTouched = (std::abs(stickX) > 0.05f || std::abs(stickY) > 0.05f);

        if (isLeft) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulXButtonComponent, btnPrimary || btnXorPlus, 0);
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulXTouchComponent, btnPrimary || btnXorPlus, 0);
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulYButtonComponent, btnSecondary || btnYorMinus, 0);
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulYTouchComponent, btnSecondary || btnYorMinus, 0);
        } else {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulAButtonComponent, btnPrimary || btnXorPlus, 0);
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulATouchComponent, btnPrimary || btnXorPlus, 0);
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulBButtonComponent, btnSecondary || btnYorMinus, 0);
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulBTouchComponent, btnSecondary || btnYorMinus, 0);
        }

        vr::VRDriverInput()->UpdateScalarComponent(m_ulTriggerValueComponent, trigVal, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulTriggerClickComponent, (trigVal > 0.65f) || btnTrigClick, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulTriggerTouchComponent, trigVal > 0.05f, 0);

        vr::VRDriverInput()->UpdateScalarComponent(m_ulGripValueComponent, gripVal, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulGripClickComponent, (gripVal > 0.65f) || btnGripClick, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulGripTouchComponent, gripVal > 0.05f, 0);

        vr::VRDriverInput()->UpdateScalarComponent(m_ulThumbstickXComponent, stickX, 0);
        vr::VRDriverInput()->UpdateScalarComponent(m_ulThumbstickYComponent, stickY, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulThumbstickClickComponent, btnStickClick, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulThumbstickTouchComponent, isStickTouched, 0);

        vr::VRDriverInput()->UpdateScalarComponent(m_ulTrackpadXComponent, stickX, 0);
        vr::VRDriverInput()->UpdateScalarComponent(m_ulTrackpadYComponent, stickY, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulTrackpadClickComponent, btnStickClick, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulTrackpadTouchComponent, isStickTouched, 0);

        vr::VRDriverInput()->UpdateBooleanComponent(m_ulSystemButtonComponent, btnSystem, 0);
        vr::VRDriverInput()->UpdateBooleanComponent(m_ulSystemTouchComponent, btnSystem, 0);

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
