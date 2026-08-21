#ifndef VRMATH_H
#define VRMATH_H

#include "openvr_driver.h"
#include <cmath>

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
    vr::HmdQuaternion_t res;
    res.w = qSwing.w * qTwist.w - qSwing.x * qTwist.x - qSwing.y * qTwist.y - qSwing.z * qTwist.z;
    res.x = qSwing.w * qTwist.x + qSwing.x * qTwist.w + qSwing.y * qTwist.z - qSwing.z * qTwist.y;
    res.y = qSwing.w * qTwist.y - qSwing.x * qTwist.z + qSwing.y * qTwist.w + qSwing.z * qTwist.x;
    res.z = qSwing.w * qTwist.z + qSwing.x * qTwist.y - qSwing.y * qTwist.x + qSwing.z * qTwist.w;
    return res;
}

#endif
