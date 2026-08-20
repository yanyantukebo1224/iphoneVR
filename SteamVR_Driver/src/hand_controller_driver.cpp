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
    
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_TrackingSystemName_String, "indexcontroller");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ModelNumber_String, isLeft ? "Knuckles Left" : "Knuckles Right");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_SerialNumber_String, isLeft ? "iPhoneVR_Knuckles_Left" : "iPhoneVR_Knuckles_Right");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ManufacturerName_String, "Valve");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_RenderModelName_String, isLeft ? "{indexcontroller}valve_controller_knuckles_left" : "{indexcontroller}valve_controller_knuckles_right");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ControllerType_String, "knuckles");
    
    vr::VRProperties()->SetInt32Property(m_ulPropertyContainer, vr::Prop_ControllerRoleHint_Int32, m_role);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_WillDriftInYaw_Bool, false);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_DeviceIsWireless_Bool, true);
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_InputProfilePath_String, "{iphonevr}/input/iphonevr_controller_profile.json");

    const char* skelComponentPath = isLeft ? "/input/skeleton/left" : "/input/skeleton/right";
    const char* skelTypePath = isLeft ? "/skeleton/hand/left" : "/skeleton/hand/right";
    vr::VRDriverInput()->CreateSkeletonComponent(
        m_ulPropertyContainer,
        skelComponentPath,
        skelTypePath,
        skelTypePath,
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
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/thumbstick/touch", &m_ulThumbstickTouchComponent);

    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trackpad/x", &m_ulTrackpadXComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trackpad/y", &m_ulTrackpadYComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trackpad/click", &m_ulTrackpadClickComponent);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trackpad/touch", &m_ulTrackpadTouchComponent);

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

        m_pose.vecPosition[0] = headPos.x + (isLeft ? -0.05f : 0.05f) + rawX;
        m_pose.vecPosition[1] = effectiveHeadY - 0.10f + rawY;
        m_pose.vecPosition[2] = headPos.z + rawZ;

        const Quaternionf& wRot = handData.joints[VISION_JOINT_WRIST].orientation;
        m_pose.qRotation.w = wRot.w;
        m_pose.qRotation.x = wRot.x;
        m_pose.qRotation.y = wRot.y;
        m_pose.qRotation.z = wRot.z;
    } else {
        auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastMovementTime).count();
        if (elapsedMs > 500) {
            m_pose.vecPosition[0] = headPos.x + defaultOffsetX;
            m_pose.vecPosition[1] = effectiveHeadY + defaultOffsetY;
            m_pose.vecPosition[2] = headPos.z + defaultOffsetZ;

            if (handData.controller.isConnected == 1) {
                const Quaternionf& cRot = handData.controller.controllerRot;
                if (cRot.w != 0.0f || cRot.x != 0.0f || cRot.y != 0.0f || cRot.z != 0.0f) {
                    m_pose.qRotation.w = cRot.w;
                    m_pose.qRotation.x = cRot.x;
                    m_pose.qRotation.y = cRot.y;
                    m_pose.qRotation.z = cRot.z;
                } else {
                    m_pose.qRotation.w = 1.0;
                    m_pose.qRotation.x = 0.0;
                    m_pose.qRotation.y = 0.0;
                    m_pose.qRotation.z = 0.0;
                }
            } else {
                m_pose.qRotation.w = 1.0;
                m_pose.qRotation.x = 0.0;
                m_pose.qRotation.y = 0.0;
                m_pose.qRotation.z = 0.0;
            }
        }
    }

    if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid) {
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));

        // Physical inputs from connected Joy-Con or Gamepad
        bool btnAorX = false;
        bool btnBorY = false;
        bool isTriggerClicked = false;
        float trigVal = 0.0f;
        bool isGripClicked = false;
        float gripVal = 0.0f;
        bool stickClicked = false;
        bool systemClicked = false;
        float stickX = 0.0f;
        float stickY = 0.0f;

        if (handData.controller.isConnected == 1) {
            uint32_t mask = handData.controller.buttonMask;
            btnAorX = (mask & BTN_A_OR_X) != 0;
            btnBorY = (mask & BTN_B_OR_Y) != 0;

            trigVal = handData.controller.triggerValue;
            isTriggerClicked = (mask & BTN_TRIGGER_CLICK) != 0 || (trigVal > 0.5f);

            gripVal = handData.controller.gripValue;
            isGripClicked = (mask & BTN_GRIP_CLICK) != 0 || (gripVal > 0.5f);

            stickClicked = (mask & BTN_THUMBSTICK_CLICK) != 0;
            systemClicked = (mask & BTN_SYSTEM) != 0;
            stickX = handData.controller.stickX;
            stickY = handData.controller.stickY;
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
        bool isStickTouched = (std::abs(stickX) > 0.05f || std::abs(stickY) > 0.05f || stickClicked);

        if (m_ulThumbstickXComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateScalarComponent(m_ulThumbstickXComponent, stickX, 0);
        }
        if (m_ulThumbstickYComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateScalarComponent(m_ulThumbstickYComponent, stickY, 0);
        }
        if (m_ulThumbstickClickComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulThumbstickClickComponent, stickClicked, 0);
        }
        if (m_ulThumbstickTouchComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulThumbstickTouchComponent, isStickTouched, 0);
        }

        // Trackpad にも同時にミラーリング (Trackpad 移動型ゲーム対応)
        if (m_ulTrackpadXComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateScalarComponent(m_ulTrackpadXComponent, stickX, 0);
        }
        if (m_ulTrackpadYComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateScalarComponent(m_ulTrackpadYComponent, stickY, 0);
        }
        if (m_ulTrackpadTouchComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulTrackpadTouchComponent, isStickTouched, 0);
        }
        if (m_ulTrackpadClickComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateBooleanComponent(m_ulTrackpadClickComponent, stickClicked, 0);
        }

        if (m_ulSystemButtonComponent != vr::k_ulInvalidInputComponentHandle) {
            if (systemClicked != m_lastSystemClicked) {
                m_lastSystemClicked = systemClicked;
                vr::VRDriverInput()->UpdateBooleanComponent(m_ulSystemButtonComponent, systemClicked, 0);
            }
        }

        vr::VRBoneTransform_t bones[31];
        ConvertVision21ToSteamVR31(handData, bones, m_role);
        if (m_ulSkeletonComponent != vr::k_ulInvalidInputComponentHandle) {
            vr::VRDriverInput()->UpdateSkeletonComponent(m_ulSkeletonComponent, vr::VRSkeletalMotionRange_WithController, bones, 31);
            vr::VRDriverInput()->UpdateSkeletonComponent(m_ulSkeletonComponent, vr::VRSkeletalMotionRange_WithoutController, bones, 31);
        }
    }
}

// Valve Official Skeletal Input Simulation
#define DEG_TO_RAD(deg) ((deg) * 0.017453292519943295f)

enum EOpenVRBone {
    eBone_Root = 0,
    eBone_Wrist,
    eBone_Thumb0,
    eBone_Thumb1,
    eBone_Thumb2,
    eBone_Thumb3,
    eBone_IndexFinger0,
    eBone_IndexFinger1,
    eBone_IndexFinger2,
    eBone_IndexFinger3,
    eBone_IndexFinger4,
    eBone_MiddleFinger0,
    eBone_MiddleFinger1,
    eBone_MiddleFinger2,
    eBone_MiddleFinger3,
    eBone_MiddleFinger4,
    eBone_RingFinger0,
    eBone_RingFinger1,
    eBone_RingFinger2,
    eBone_RingFinger3,
    eBone_RingFinger4,
    eBone_PinkyFinger0,
    eBone_PinkyFinger1,
    eBone_PinkyFinger2,
    eBone_PinkyFinger3,
    eBone_PinkyFinger4,
    eBone_Aux_Thumb,
    eBone_Aux_IndexFinger,
    eBone_Aux_MiddleFinger,
    eBone_Aux_RingFinger,
    eBone_Aux_PinkyFinger,
    eBone_Count
};

struct HandSimSplayableJoint {
    float swing[2] = { 0.f, 0.f };
    float twist = 0.f;
};

struct HandSimJoint {
    float rotation = 0.f;
};

struct HandSimThumb {
    HandSimSplayableJoint metacarpal;
    HandSimSplayableJoint proximal;
    HandSimJoint distal;
};

struct HandSimFinger {
    HandSimSplayableJoint metacarpal;
    HandSimSplayableJoint proximal;
    HandSimJoint intermediate;
    HandSimJoint distal;
};

struct HandSimHand {
    vr::ETrackedControllerRole role;
    HandSimThumb thumb;
    HandSimFinger fingers[4];
};

static const float finger_joint_lengths[5][5] = {
    { 0.05f, 0.05f, 0.035f, 0.025f, 0.f },
    { 0.03f, 0.073f, 0.045f, 0.025f, 0.02f },
    { 0.01f, 0.091f, 0.049f, 0.03f, 0.02f },
    { 0.02f, 0.073f, 0.045f, 0.03f, 0.03f },
    { 0.03f, 0.067f, 0.03f, 0.025f, 0.02f }
};

static inline vr::HmdQuaternion_t QuatMultiply(const vr::HmdQuaternion_t& q1, const vr::HmdQuaternion_t& q2) {
    return {
        q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
        q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
        q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
        q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w
    };
}

static inline vr::HmdVector3_t QuatRotateVec(const vr::HmdVector3_t& v, const vr::HmdQuaternion_t& q) {
    vr::HmdQuaternion_t qv = { 0.0, (double)v.v[0], (double)v.v[1], (double)v.v[2] };
    vr::HmdQuaternion_t qConj = { q.w, -q.x, -q.y, -q.z };
    vr::HmdQuaternion_t res = QuatMultiply(QuatMultiply(q, qv), qConj);
    vr::HmdVector3_t outV;
    outV.v[0] = (float)res.x;
    outV.v[1] = (float)res.y;
    outV.v[2] = (float)res.z;
    return outV;
}

static inline vr::HmdQuaternion_t QuatFromEuler(float pitch, float yaw, float roll) {
    float cp = std::cos(pitch * 0.5f), sp = std::sin(pitch * 0.5f);
    float cy = std::cos(yaw * 0.5f),   sy = std::sin(yaw * 0.5f);
    float cr = std::cos(roll * 0.5f),  sr = std::sin(roll * 0.5f);
    return {
        (double)(cr * cp * cy + sr * sp * sy),
        (double)(sr * cp * cy - cr * sp * sy),
        (double)(cr * sp * cy + sr * cp * sy),
        (double)(cr * cp * sy - sr * sp * cy)
    };
}

static inline vr::HmdQuaternion_t QuatFromSwingTwist(const float swing[2], float twist) {
    vr::HmdQuaternion_t qSwing = QuatFromEuler(swing[0], swing[1], 0.f);
    vr::HmdQuaternion_t qTwist = QuatFromEuler(0.f, 0.f, twist);
    return QuatMultiply(qSwing, qTwist);
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
        std::swap(bone_orientation.w, bone_orientation.x);
        std::swap(bone_orientation.y, bone_orientation.z);
        bone_orientation.x *= -1.f;
        bone_orientation.z *= -1.f;
    }

    ComputeBoneTransform(role, bone_orientation, bone_position, out_transform);
}

static int CalculateBoneTransformPositionFromFinger(int finger, int bone_in_finger) {
    return eBone_IndexFinger0 + finger * 5 + bone_in_finger;
}

void HandControllerDriver::ConvertVision21ToSteamVR31(
    const HandPacketData& handData,
    vr::VRBoneTransform_t outBones[31],
    vr::ETrackedControllerRole role
) {

    HandSimHand hand{};
    hand.role = role;

    outBones[eBone_Root] = { { 0.0f, 0.0f, 0.0f, 1.0f }, { 1.0f, 0.0f, 0.0f, 0.0f } };
    outBones[eBone_Wrist] = { { -0.034038f, 0.036503f, 0.164722f, 1.0f }, { -0.055147f, -0.078608f, -0.920279f, 0.379296f } };

    if (role == vr::TrackedControllerRole_RightHand) {
        outBones[eBone_Wrist].position.v[0] *= -1.f;
        outBones[eBone_Wrist].orientation.y *= -1.f;
        outBones[eBone_Wrist].orientation.z *= -1.f;
    }

    for (auto& finger : hand.fingers) {
        finger.proximal.swing[1] = DEG_TO_RAD(10.f);
        finger.intermediate.rotation = DEG_TO_RAD(5.f);
        finger.distal.rotation = DEG_TO_RAD(5.f);
    }

    hand.thumb.metacarpal.swing[0] = DEG_TO_RAD(10.f);
    hand.thumb.metacarpal.swing[1] = DEG_TO_RAD(40.f);
    hand.thumb.metacarpal.twist = DEG_TO_RAD(70.f);

    hand.fingers[0].metacarpal.swing[1] = DEG_TO_RAD(13.f);
    hand.fingers[1].metacarpal.swing[1] = DEG_TO_RAD(0.f);
    hand.fingers[2].metacarpal.swing[1] = DEG_TO_RAD(-15.f);
    hand.fingers[3].metacarpal.swing[1] = DEG_TO_RAD(-27.f);

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

    hand.thumb.metacarpal.swing[0] += DEG_TO_RAD(curlThumb * 5.f);
    hand.thumb.metacarpal.swing[1] += DEG_TO_RAD(splayThumb * 5.f);
    hand.thumb.proximal.swing[0] += DEG_TO_RAD(curlThumb * 90.f);
    hand.thumb.proximal.swing[1] += DEG_TO_RAD(splayThumb * 20.f);
    hand.thumb.distal.rotation += DEG_TO_RAD(curlThumb * 90.f);

    float curls[4] = { curlIndex, curlMiddle, curlRing, curlPinky };
    float splays[4] = { splayIndex, splayMiddle, splayRing, splayPinky };

    for (int i = 0; i < 4; ++i) {
        hand.fingers[i].metacarpal.swing[0] += DEG_TO_RAD(curls[i] * 5.f);
        hand.fingers[i].proximal.swing[0] += DEG_TO_RAD(curls[i] * 90.f);
        hand.fingers[i].proximal.swing[1] += DEG_TO_RAD(splays[i] * 15.f);
        hand.fingers[i].intermediate.rotation += DEG_TO_RAD(curls[i] * 80.f);
        hand.fingers[i].distal.rotation += DEG_TO_RAD(curls[i] * 80.f);
    }

    ComputeBoneTransformMetacarpal(role, QuatFromSwingTwist(hand.thumb.metacarpal.swing, hand.thumb.metacarpal.twist), finger_joint_lengths[0][0], outBones[eBone_Thumb0]);
    ComputeBoneTransform(role, QuatFromSwingTwist(hand.thumb.proximal.swing, hand.thumb.metacarpal.twist), finger_joint_lengths[0][1], outBones[eBone_Thumb1]);
    ComputeBoneTransform(role, QuatFromEuler(hand.thumb.distal.rotation, 0.f, 0.f), finger_joint_lengths[0][2], outBones[eBone_Thumb2]);
    ComputeBoneTransform(role, { 1.f, 0.f, 0.f, 0.f }, finger_joint_lengths[0][3], outBones[eBone_Thumb3]);

    for (int finger = 0; finger < 4; finger++) {
        ComputeBoneTransformMetacarpal(role, QuatFromSwingTwist(hand.fingers[finger].metacarpal.swing, hand.fingers[finger].metacarpal.twist),
            finger_joint_lengths[finger + 1][0], outBones[CalculateBoneTransformPositionFromFinger(finger, 0)]);

        ComputeBoneTransform(role, QuatFromSwingTwist(hand.fingers[finger].proximal.swing, hand.fingers[finger].proximal.twist), finger_joint_lengths[finger + 1][1],
            outBones[CalculateBoneTransformPositionFromFinger(finger, 1)]);

        ComputeBoneTransform(role, QuatFromEuler(hand.fingers[finger].intermediate.rotation, 0.f, 0.f), finger_joint_lengths[finger + 1][2],
            outBones[CalculateBoneTransformPositionFromFinger(finger, 2)]);

        ComputeBoneTransform(role, QuatFromEuler(hand.fingers[finger].distal.rotation, 0.f, 0.f), finger_joint_lengths[finger + 1][3],
            outBones[CalculateBoneTransformPositionFromFinger(finger, 3)]);

        ComputeBoneTransform(role, { 1.f, 0.f, 0.f, 0.f }, finger_joint_lengths[finger + 1][4], outBones[CalculateBoneTransformPositionFromFinger(finger, 4)]);
    }

    outBones[eBone_Aux_Thumb] = outBones[eBone_Thumb3];
    outBones[eBone_Aux_IndexFinger] = outBones[eBone_IndexFinger4];
    outBones[eBone_Aux_MiddleFinger] = outBones[eBone_MiddleFinger4];
    outBones[eBone_Aux_RingFinger] = outBones[eBone_RingFinger4];
    outBones[eBone_Aux_PinkyFinger] = outBones[eBone_PinkyFinger4];
}
