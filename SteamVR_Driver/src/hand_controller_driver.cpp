#include "hand_controller_driver.h"
#include <cstring>
#include <cmath>

HandControllerDriver::HandControllerDriver(vr::ETrackedControllerRole role)
    : m_role(role), m_unObjectId(vr::k_unTrackedDeviceIndexInvalid),
      m_ulPropertyContainer(vr::k_ulInvalidPropertyContainer),
      m_ulSkeletonComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTriggerClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulTriggerValueComponent(vr::k_ulInvalidInputComponentHandle),
      m_ulGripClickComponent(vr::k_ulInvalidInputComponentHandle),
      m_isTracked(false) {
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
    
    // Set official Vive controller model guaranteed to exist in SteamVR
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_TrackingSystemName_String, "driver_iphonevr");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ModelNumber_String, isLeft ? "iPhoneVR Left Hand" : "iPhoneVR Right Hand");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_SerialNumber_String, isLeft ? "iPhoneVR_LeftHand_001" : "iPhoneVR_RightHand_001");
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_ManufacturerName_String, "HTC/Valve/iPhoneVR");
    
    // Render model path guaranteed by SteamVR
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_RenderModelName_String, "vr_controller_vive_1_5");
    
    vr::VRProperties()->SetInt32Property(m_ulPropertyContainer, vr::Prop_ControllerRoleHint_Int32, m_role);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_WillDriftInYaw_Bool, false);
    vr::VRProperties()->SetBoolProperty(m_ulPropertyContainer, vr::Prop_DeviceIsWireless_Bool, true);
    vr::VRProperties()->SetStringProperty(m_ulPropertyContainer, vr::Prop_InputProfilePath_String, "{driver_iphonevr}/resources/input/iphonevr_controller_profile.json");

    // Skeletal Input Component
    const char* skelComponentPath = isLeft ? "/input/skeleton/left" : "/input/skeleton/right";
    vr::VRDriverInput()->CreateSkeletonComponent(
        m_ulPropertyContainer,
        skelComponentPath,
        skelComponentPath,
        "/skeleton/hand/left",
        vr::VRSkeletalTracking_Full,
        nullptr,
        0,
        &m_ulSkeletonComponent
    );

    // Input Components
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/trigger/click", &m_ulTriggerClickComponent);
    vr::VRDriverInput()->CreateScalarComponent(m_ulPropertyContainer, "/input/trigger/value", &m_ulTriggerValueComponent, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);
    vr::VRDriverInput()->CreateBooleanComponent(m_ulPropertyContainer, "/input/grip/click", &m_ulGripClickComponent);

    // Default Init Pose
    HandPacketData dummyHand{};
    dummyHand.isTracked = 1;
    dummyHand.joints[VISION_JOINT_WRIST].position = Vector3f{0.0f, 0.0f, 0.0f};
    dummyHand.joints[VISION_JOINT_WRIST].orientation = Quaternionf{1.0f, 0.0f, 0.0f, 0.0f};

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

    float baseOffsetX = isLeft ? -0.22f : 0.22f;
    float baseOffsetY = -0.20f;
    float baseOffsetZ = -0.35f;

    // Wrist movement offset
    float offsetPositionX = handData.joints[VISION_JOINT_WRIST].position.x;
    float offsetPositionY = handData.joints[VISION_JOINT_WRIST].position.y;
    float offsetPositionZ = handData.joints[VISION_JOINT_WRIST].position.z;

    if (offsetPositionX != offsetPositionX) offsetPositionX = 0.0f;
    if (offsetPositionY != offsetPositionY) offsetPositionY = 0.0f;
    if (offsetPositionZ != offsetPositionZ) offsetPositionZ = 0.0f;

    // Calculate real world hand position
    m_pose.vecPosition[0] = headPos.x + baseOffsetX + offsetPositionX;
    m_pose.vecPosition[1] = effectiveHeadY + baseOffsetY + offsetPositionY;
    m_pose.vecPosition[2] = headPos.z + baseOffsetZ + offsetPositionZ;

    // Forward pointing rotation
    m_pose.qRotation.w = 0.92388f;
    m_pose.qRotation.x = 0.38268f;
    m_pose.qRotation.y = 0.0f;
    m_pose.qRotation.z = 0.0f;

    if (m_unObjectId != vr::k_unTrackedDeviceIndexInvalid) {
        // Update 6DoF Pose
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(m_unObjectId, m_pose, sizeof(vr::DriverPose_t));

        // Update Click Inputs
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

        // Update Skeletal bones
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
    auto makeIdentity = [](vr::VRBoneTransform_t& b, float bx=0, float by=0, float bz=0) {
        b.position.v[0] = bx;
        b.position.v[1] = by;
        b.position.v[2] = bz;
        b.orientation.w = 1.0;
        b.orientation.x = 0.0;
        b.orientation.y = 0.0;
        b.orientation.z = 0.0;
    };

    for (int i = 0; i < 31; ++i) {
        makeIdentity(outBones[i]);
    }

    auto mapJoint = [](const BoneTransform& src, vr::VRBoneTransform_t& dst) {
        dst.position.v[0] = src.position.x;
        dst.position.v[1] = src.position.y;
        dst.position.v[2] = src.position.z;
        dst.orientation.w = src.orientation.w;
        dst.orientation.x = src.orientation.x;
        dst.orientation.y = src.orientation.y;
        dst.orientation.z = src.orientation.z;
    };

    mapJoint(handData.joints[VISION_JOINT_WRIST], outBones[1]);

    struct FingerMap {
        int steamvr_start;
        int vision_start;
    } fingerMaps[] = {
        { 2,  VISION_JOINT_THUMB_CMC },
        { 7,  VISION_JOINT_INDEX_MCP },
        { 12, VISION_JOINT_MIDDLE_MCP },
        { 17, VISION_JOINT_RING_MCP },
        { 22, VISION_JOINT_PINKY_MCP }
    };

    makeIdentity(outBones[6],  0.03f, 0.0f, 0.05f);
    makeIdentity(outBones[11], 0.01f, 0.0f, 0.06f);
    makeIdentity(outBones[16], -0.01f, 0.0f, 0.05f);
    makeIdentity(outBones[21], -0.03f, 0.0f, 0.04f);

    for (const auto& f : fingerMaps) {
        for (int step = 0; step < 4; ++step) {
            mapJoint(handData.joints[f.vision_start + step], outBones[f.steamvr_start + step]);
        }
    }

    outBones[26] = outBones[5];
    outBones[27] = outBones[10];
    outBones[28] = outBones[15];
    outBones[29] = outBones[20];
    outBones[30] = outBones[25];
}
