#ifndef TRACKING_PROTOCOL_H
#define TRACKING_PROTOCOL_H

#include <cstdint>

#pragma pack(push, 4)

#define IPPHONE_VR_MAGIC 0x52565049

struct Vector3f {
    float x;
    float y;
    float z;
};

struct Quaternionf {
    float w;
    float x;
    float y;
    float z;
};

struct BoneTransform {
    Vector3f position;
    Quaternionf orientation;
};

enum VisionJointIndex {
    VISION_JOINT_WRIST = 0,
    VISION_JOINT_THUMB_CMC = 1,
    VISION_JOINT_THUMB_MP = 2,
    VISION_JOINT_THUMB_IP = 3,
    VISION_JOINT_THUMB_TIP = 4,
    VISION_JOINT_INDEX_MCP = 5,
    VISION_JOINT_INDEX_PIP = 6,
    VISION_JOINT_INDEX_DIP = 7,
    VISION_JOINT_INDEX_TIP = 8,
    VISION_JOINT_MIDDLE_MCP = 9,
    VISION_JOINT_MIDDLE_PIP = 10,
    VISION_JOINT_MIDDLE_DIP = 11,
    VISION_JOINT_MIDDLE_TIP = 12,
    VISION_JOINT_RING_MCP = 13,
    VISION_JOINT_RING_PIP = 14,
    VISION_JOINT_RING_DIP = 15,
    VISION_JOINT_RING_TIP = 16,
    VISION_JOINT_PINKY_MCP = 17,
    VISION_JOINT_PINKY_PIP = 18,
    VISION_JOINT_PINKY_DIP = 19,
    VISION_JOINT_PINKY_TIP = 20,
    VISION_JOINT_COUNT = 21
};

enum ControllerButtonBits : uint32_t {
    BTN_A_OR_X           = (1 << 0), // A (Right) or X (Left)
    BTN_B_OR_Y           = (1 << 1), // B (Right) or Y (Left)
    BTN_X_OR_PLUS        = (1 << 2), // X (Right) or Plus
    BTN_Y_OR_MINUS       = (1 << 3), // Y (Right) or Minus
    BTN_TRIGGER_CLICK    = (1 << 4), // ZR or ZL click
    BTN_GRIP_CLICK       = (1 << 5), // R or L bumper
    BTN_THUMBSTICK_CLICK = (1 << 6), // Stick press
    BTN_SYSTEM           = (1 << 7), // Home / Capture / System menu
    BTN_DPAD_UP          = (1 << 8),
    BTN_DPAD_DOWN        = (1 << 9),
    BTN_DPAD_LEFT        = (1 << 10),
    BTN_DPAD_RIGHT       = (1 << 11),
};

struct ControllerInputData {
    uint32_t isConnected;      // 4 bytes: 1 if physical gamepad is connected
    uint32_t buttonMask;       // 4 bytes: ControllerButtonBits
    float stickX;              // 4 bytes: -1.0 to 1.0
    float stickY;              // 4 bytes: -1.0 to 1.0
    float triggerValue;        // 4 bytes: 0.0 to 1.0 (ZL/ZR)
    float gripValue;           // 4 bytes: 0.0 to 1.0 (L/R)
    Quaternionf controllerRot; // 16 bytes: Controller IMU rotation
};

struct FingerCurls {
    float thumb;  // 0.0 (open) to 1.0 (fully curled)
    float index;
    float middle;
    float ring;
    float pinky;
};

struct FingerSplays {
    float thumb;  // -1.0 (abducted) to 1.0 (adducted)
    float index;  // Splay angle relative to palm
    float middle;
    float ring;
    float pinky;
};

struct HandPacketData {
    uint32_t chirality;        // 4 bytes: 0 = Left, 1 = Right
    uint32_t isTracked;        // 4 bytes
    uint32_t isPinching;       // 4 bytes
    float pinchDistance;       // 4 bytes
    FingerCurls curls;         // 20 bytes
    FingerSplays splays;       // 20 bytes
    BoneTransform joints[VISION_JOINT_COUNT]; // 21 * 28 = 588 bytes
    ControllerInputData controller;           // 40 bytes
};

struct TrackingPacket {
    uint32_t magic;            // 4 bytes
    uint32_t sequence;         // 4 bytes
    double timestamp;          // 8 bytes
    Vector3f headPosition;     // 12 bytes
    Quaternionf headRotation;  // 16 bytes
    HandPacketData hands[2];   // 2 * 664 = 1328 bytes
};

#pragma pack(pop)

#endif // TRACKING_PROTOCOL_H