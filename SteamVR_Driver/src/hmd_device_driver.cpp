#include "hmd_device_driver.h"
#include <cstring>

HMDDeviceDriver::HMDDeviceDriver() {
    std::memset(&m_pose, 0, sizeof(m_pose));
    m_pose.poseIsValid = true;
    m_pose.deviceIsConnected = true;
    m_pose.result = vr::TrackingResult_Running_OK;

    m_pose.qRotation.w = 1.0;
    m_pose.qWorldFromDriverRotation.w = 1.0;
    m_pose.qDriverFromHeadRotation.w = 1.0;
}

HMDDeviceDriver::~HMDDeviceDriver() {}

void HMDDeviceDriver::UpdateHeadPose(const Vector3f& headPos, const Quaternionf& headRot) {
    m_pose.poseIsValid = true;
    m_pose.result = vr::TrackingResult_Running_OK;

    // 1) 位置座標変換 (ARKit -> OpenVR 軸調整 & オフセット)
    m_pose.vecPosition[0] = (headPos.x * m_config.posXMultiplier) + m_config.offsetX;
    m_pose.vecPosition[1] = (headPos.y * m_config.posYMultiplier) + m_config.offsetY;
    m_pose.vecPosition[2] = (headPos.z * m_config.posZMultiplier) + m_config.offsetZ;

    // 2) 回転クォータニオンの符号反転・スワップ補正 (ポプちゃん指示 ③ 座標変換)
    m_pose.qRotation.w = m_config.invertRotW ? -headRot.w : headRot.w;
    m_pose.qRotation.x = m_config.invertRotX ? -headRot.x : headRot.x;
    m_pose.qRotation.y = m_config.invertRotY ? -headRot.y : headRot.y;
    m_pose.qRotation.z = m_config.invertRotZ ? -headRot.z : headRot.z;
}
