#ifndef TRACKING_PROTOCOL_H
#define TRACKING_PROTOCOL_H

#include <cstdint>

#pragma pack(push, 1)

// マジックナンバー ('I', 'P', 'V', 'R')
#define IPPHONE_VR_MAGIC 0x52565049 // "IPVR" in Little Endian

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

// Vision検出 21関節インデックス定義
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

struct HandPacketData {
    uint8_t chirality;     // 0: Left, 1: Right
    uint8_t isTracked;     // 0: Lost, 1: Tracking
    uint8_t isPinching;    // 0: No, 1: Pinching
    float pinchDistance;   // メートル単位
    BoneTransform joints[VISION_JOINT_COUNT]; // Vision 21点関節3Dデータ
};

// iOS -> SteamVR Driver 低遅延送信構造体
struct TrackingPacket {
    uint32_t magic;           // IPPHONE_VR_MAGIC
    uint32_t sequence;        // 連番フレームカウンタ
    double timestamp;         // 送信タイムスタンプ

    // 6DoF 頭部位置姿勢 (ARKit World Coordinate)
    Vector3f headPosition;
    Quaternionf headRotation;

    // 両手トラッキングデータ (0: Left, 1: Right)
    HandPacketData hands[2];
};

#pragma pack(pop)

#endif // TRACKING_PROTOCOL_H
