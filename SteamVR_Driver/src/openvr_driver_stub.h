#ifndef OPENVR_DRIVER_STUB_H
#define OPENVR_DRIVER_STUB_H

#include <cstdint>
#include <cmath>

namespace vr {

typedef uint32_t DriverId_t;
typedef uint32_t PropertyContainerHandle_t;
typedef uint32_t VRInputComponentHandle_t;
typedef uint32_t TrackedDeviceIndex_t;

static const char* const IServerTrackedDeviceProvider_Version = "IServerTrackedDeviceProvider_004";

enum ETrackedDeviceClass {
    TrackedDeviceClass_Invalid = 0,
    TrackedDeviceClass_HMD = 1,
    TrackedDeviceClass_Controller = 2,
    TrackedDeviceClass_GenericTracker = 3,
    TrackedDeviceClass_TrackingReference = 4,
    TrackedDeviceClass_DisplayRedirect = 5,
};

enum ETrackedControllerRole {
    TrackedControllerRole_Invalid = 0,
    TrackedControllerRole_LeftHand = 1,
    TrackedControllerRole_RightHand = 2,
    TrackedControllerRole_OptOut = 3,
    TrackedControllerRole_Treadmill = 4,
    TrackedControllerRole_Max = 5
};

enum ETrackingResult {
    TrackingResult_Uninitialized = 1,
    TrackingResult_Calibrating_InProgress = 100,
    TrackingResult_Calibrating_OutOfRange = 101,
    TrackingResult_Running_OK = 200,
    TrackingResult_Running_OutOfRange = 201,
};

struct HmdVector3_t {
    float v[3];
};

struct HmdQuaternion_t {
    double w, x, y, z;
};

struct HmdMatrix34_t {
    float m[3][4];
};

struct DriverPose_t {
    uint32_t poseTimeOffset;
    HmdQuaternion_t qWorldFromDriverRotation;
    double vecWorldFromDriverTranslation[3];
    HmdQuaternion_t qDriverFromHeadRotation;
    double vecDriverFromHeadTranslation[3];
    double vecPosition[3];
    double vecVelocity[3];
    double vecAcceleration[3];
    HmdQuaternion_t qRotation;
    double vecAngularVelocity[3];
    double vecAngularAcceleration[3];
    ETrackingResult result;
    bool poseIsValid;
    bool willDriftInYaw;
    bool shouldApplyHeadModel;
    bool deviceIsConnected;
};

struct VRBoneTransform_t {
    HmdVector3_t position;
    HmdQuaternion_t orientation;
};

enum ESteamVRBoneIndex {
    STEAMVR_BONE_ROOT = 0,
    STEAMVR_BONE_WRIST = 1,
    STEAMVR_BONE_THUMB_0 = 2,
    STEAMVR_BONE_THUMB_1 = 3,
    STEAMVR_BONE_THUMB_2 = 4,
    STEAMVR_BONE_THUMB_3 = 5,
    STEAMVR_BONE_INDEX_0 = 6,
    STEAMVR_BONE_INDEX_1 = 7,
    STEAMVR_BONE_INDEX_2 = 8,
    STEAMVR_BONE_INDEX_3 = 9,
    STEAMVR_BONE_INDEX_4 = 10,
    STEAMVR_BONE_MIDDLE_0 = 11,
    STEAMVR_BONE_MIDDLE_1 = 12,
    STEAMVR_BONE_MIDDLE_2 = 13,
    STEAMVR_BONE_MIDDLE_3 = 14,
    STEAMVR_BONE_MIDDLE_4 = 15,
    STEAMVR_BONE_RING_0 = 16,
    STEAMVR_BONE_RING_1 = 17,
    STEAMVR_BONE_RING_2 = 18,
    STEAMVR_BONE_RING_3 = 19,
    STEAMVR_BONE_RING_4 = 20,
    STEAMVR_BONE_PINKY_0 = 21,
    STEAMVR_BONE_PINKY_1 = 22,
    STEAMVR_BONE_PINKY_2 = 23,
    STEAMVR_BONE_PINKY_3 = 24,
    STEAMVR_BONE_PINKY_4 = 25,
    STEAMVR_BONE_AUX_THUMB = 26,
    STEAMVR_BONE_AUX_INDEX = 27,
    STEAMVR_BONE_AUX_MIDDLE = 28,
    STEAMVR_BONE_AUX_RING = 29,
    STEAMVR_BONE_AUX_PINKY = 30,
    STEAMVR_BONE_COUNT = 31
};

enum EVRInitError {
    VRInitError_None = 0,
    VRInitError_Init_Failed = 100,
    VRInitError_Init_InterfaceNotFound = 105
};

class IVRDriverContext;

class IServerTrackedDeviceProvider {
public:
    virtual EVRInitError Init(IVRDriverContext* pDriverContext) = 0;
    virtual void Cleanup() = 0;
    virtual const char* const* GetInterfaceVersions() { return nullptr; }
    virtual void RunFrame() = 0;
    virtual bool ShouldBlockStandbyMode() = 0;
    virtual void EnterStandby() = 0;
    virtual void LeaveStandby() = 0;
};

class ITrackedDeviceServerDriver {
public:
    virtual EVRInitError Activate(uint32_t unObjectId) = 0;
    virtual void Deactivate() = 0;
    virtual void EnterStandby() = 0;
    virtual void* GetComponent(const char* pchComponentNameAndVersion) = 0;
    virtual void DebugRequest(const char* pchRequest, char* pchResponseBuffer, uint32_t unResponseBufferSize) = 0;
    virtual DriverPose_t GetPose() = 0;
};

} // namespace vr

#endif // OPENVR_DRIVER_STUB_H
