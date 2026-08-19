#ifndef HMD_DEVICE_DRIVER_H
#define HMD_DEVICE_DRIVER_H

#include "openvr_driver_stub.h"
#include "tracking_protocol.h"

struct CoordinateConfig {
    // 位置の軸反転設定
    float posXMultiplier = 1.0f; // -1.0f で反転
    float posYMultiplier = 1.0f;
    float posZMultiplier = 1.0f;

    // クォータニオン(回転)軸の反転・スワップフラグ (ポプちゃん指示 ③ 実装)
    bool invertRotW = false;
    bool invertRotX = false;
    bool invertRotY = false;
    bool invertRotZ = false;
    
    // 位置オフセット (キャリブレーション用)
    float offsetX = 0.0f;
    float offsetY = 0.0f;
    float offsetZ = 0.0f;
};

class HMDDeviceDriver {
public:
    HMDDeviceDriver();
    ~HMDDeviceDriver();

    void UpdateHeadPose(const Vector3f& headPos, const Quaternionf& headRot);
    
    vr::DriverPose_t GetPose() const { return m_pose; }
    CoordinateConfig& GetConfig() { return m_config; }

private:
    vr::DriverPose_t m_pose;
    CoordinateConfig m_config;
};

#endif // HMD_DEVICE_DRIVER_H
