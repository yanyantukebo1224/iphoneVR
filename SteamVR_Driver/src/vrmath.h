#ifndef VRMATH_H
#define VRMATH_H

#include "openvr_driver.h"
#include <cmath>

inline vr::HmdQuaternion_t QuatFromEuler(float pitch, float yaw, float roll) {
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

inline vr::HmdQuaternion_t QuatMultiply(const vr::HmdQuaternion_t& q1, const vr::HmdQuaternion_t& q2) {
    return {
        q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
        q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
        q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
        q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w
    };
}

inline vr::HmdVector3_t QuatRotateVec(const vr::HmdVector3_t& v, const vr::HmdQuaternion_t& q) {
    vr::HmdQuaternion_t qv = { 0.0, (double)v.v[0], (double)v.v[1], (double)v.v[2] };
    vr::HmdQuaternion_t qConj = { q.w, -q.x, -q.y, -q.z };
    vr::HmdQuaternion_t res = QuatMultiply(QuatMultiply(q, qv), qConj);
    return { (float)res.x, (float)res.y, (float)res.z };
}

inline vr::HmdQuaternion_t QuatFromSwingTwist(const float swing[2], float twist) {
    vr::HmdQuaternion_t qSwing = QuatFromEuler(swing[0], swing[1], 0.f);
    vr::HmdQuaternion_t qTwist = QuatFromEuler(0.f, 0.f, twist);
    return QuatMultiply(qSwing, qTwist);
}

#endif
