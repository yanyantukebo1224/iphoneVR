//============ Copyright (c) Valve Corporation, All rights reserved. ============
// Inspired by Moshi Turner's code from Monado
#include "hand_simulation.h"
#include "vrmath.h"
#include <algorithm>

struct HandSimSplayableJoint
{
	vr::HmdVector2_t swing = { 0.f, 0.f };
	float twist = 0.f;
};

struct HandSimJoint
{
	float rotation = 0.f;
};

struct HandSimThumb
{
	HandSimSplayableJoint metacarpal;
	HandSimSplayableJoint proximal;
	HandSimJoint distal;
};

struct HandSimFinger
{
	HandSimSplayableJoint metacarpal;
	HandSimSplayableJoint proximal;
	HandSimJoint intermediate;
	HandSimJoint distal;
};

struct HandSimHand
{
	vr::ETrackedControllerRole role;
	HandSimThumb thumb;
	HandSimFinger fingers[4];
};

static const float finger_joint_lengths[5][5] = {
	{ 0.05f, 0.05f, 0.035f, 0.025f, 0.f },	 // thumb
	{ 0.03f, 0.073f, 0.045f, 0.025f, 0.02f }, // index
	{ 0.01f, 0.091f, 0.049f, 0.03f, 0.02f },  // middle
	{ 0.02f, 0.073f, 0.045f, 0.03f, 0.03f },  // ring
	{ 0.03f, 0.067f, 0.03f, 0.025f, 0.02f },  // pinky
};

static void InitHand(HandSimHand& out_hand)
{
	for (auto& finger : out_hand.fingers)
	{
		finger.metacarpal.swing.v[1] = 0.f;
		finger.metacarpal.twist = 0.f;

		finger.proximal.swing.v[1] = DEG_TO_RAD(10);
		finger.intermediate.rotation = DEG_TO_RAD(5.f);
		finger.distal.rotation = DEG_TO_RAD(5.f);
	}

	out_hand.thumb.metacarpal.swing.v[0] = DEG_TO_RAD(10);
	out_hand.thumb.metacarpal.swing.v[1] = DEG_TO_RAD(40);
	out_hand.thumb.metacarpal.twist = DEG_TO_RAD(70);

	out_hand.thumb.proximal.swing.v[0] = 0.f;
	out_hand.thumb.proximal.swing.v[1] = 0.f;
	out_hand.thumb.proximal.twist = 0.f;

	out_hand.thumb.distal.rotation = 0.f;

	out_hand.fingers[0].metacarpal.swing.v[1] = DEG_TO_RAD(13.f);
	out_hand.fingers[1].metacarpal.swing.v[1] = DEG_TO_RAD(-0.f);
	out_hand.fingers[2].metacarpal.swing.v[1] = DEG_TO_RAD(-15.f);
	out_hand.fingers[3].metacarpal.swing.v[1] = DEG_TO_RAD(-27.f);

	out_hand.fingers[0].proximal.swing.v[1] = DEG_TO_RAD(3.f);
	out_hand.fingers[1].proximal.swing.v[1] = DEG_TO_RAD(0.f);
	out_hand.fingers[2].proximal.swing.v[1] = DEG_TO_RAD(-1.f);
	out_hand.fingers[3].proximal.swing.v[1] = DEG_TO_RAD(-2.f);
}

static void ApplyGenericFingerTransform(const float curl, const float splay, HandSimFinger& out_finger)
{
	out_finger.metacarpal.swing.v[0] -= DEG_TO_RAD(curl * 5.f);

	out_finger.proximal.swing.v[0] = -DEG_TO_RAD(curl * 75.f);
	out_finger.proximal.swing.v[1] += DEG_TO_RAD(splay * 25.f);

	out_finger.intermediate.rotation = -DEG_TO_RAD(curl * 75.f);
	out_finger.distal.rotation = -DEG_TO_RAD(curl * 65.f);
}

static void ApplyThumbTransform(const float curl, const float splay, HandSimThumb& out_thumb)
{
	out_thumb.metacarpal.swing.v[0] -= DEG_TO_RAD(curl * 10.f);
	out_thumb.metacarpal.swing.v[1] += DEG_TO_RAD(splay * 15.f);

	out_thumb.proximal.swing.v[0] = -DEG_TO_RAD(curl * 45.f);
	out_thumb.proximal.swing.v[1] = DEG_TO_RAD((1.0f - curl) * 15.f + curl * 5.f + splay * 15.f);

	out_thumb.distal.rotation = -DEG_TO_RAD(curl * 45.f);
}

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
    return { (float)res.x, (float)res.y, (float)res.z };
}

static void ComputeBoneTransform(const vr::ETrackedControllerRole role, const vr::HmdQuaternion_t& orientation, const vr::HmdVector3_t& position, vr::VRBoneTransform_t& out_transform)
{
	out_transform.orientation.w = (float)orientation.w;
	out_transform.orientation.x = (float)orientation.x;
	out_transform.orientation.y = (float)orientation.y;
	out_transform.orientation.z = (float)orientation.z;

	out_transform.position.v[0] = (float)position.v[0];
	out_transform.position.v[1] = (float)position.v[1];
	out_transform.position.v[2] = (float)position.v[2];
	out_transform.position.v[3] = 1.0f;

	if (role == vr::TrackedControllerRole_RightHand)
	{
		out_transform.position.v[0] *= -1.f;
	}
}

static void ComputeBoneTransform(const vr::ETrackedControllerRole role, const vr::HmdQuaternion_t& orientation, const float joint_length, vr::VRBoneTransform_t& out_transform)
{
	vr::HmdVector3_t pos = { joint_length, 0.f, 0.f };
	ComputeBoneTransform(role, orientation, pos, out_transform);
}

static void ComputeBoneTransformMetacarpal(const vr::ETrackedControllerRole role, const vr::HmdQuaternion_t& orientation, const float joint_length, vr::VRBoneTransform_t& out_transform)
{
	const vr::HmdVector3_t offset = { joint_length, 0.f, 0.f };
	vr::HmdQuaternion_t magic = { 0.5, 0.5, -0.5, 0.5 };
	vr::HmdQuaternion_t bone_orientation = QuatMultiply(magic, orientation);
	vr::HmdVector3_t bone_position = QuatRotateVec(offset, bone_orientation);

	if (role == vr::TrackedControllerRole_RightHand)
	{
		bone_orientation.y *= -1.f;
		bone_orientation.z *= -1.f;
	}

	ComputeBoneTransform(role, bone_orientation, bone_position, out_transform);
}

void MyHandSimulation::ComputeSkeletonTransforms(
	vr::ETrackedControllerRole role,
	const MyFingerCurls& curls,
	const MyFingerSplays& splays,
	vr::VRBoneTransform_t out_transforms[31]
)
{
	HandSimHand hand{};
	hand.role = role;

	InitHand(hand);

	ApplyThumbTransform(curls.thumb, splays.thumb, hand.thumb);
	ApplyGenericFingerTransform(curls.index, splays.index, hand.fingers[0]);
	ApplyGenericFingerTransform(curls.middle, splays.middle, hand.fingers[1]);
	ApplyGenericFingerTransform(curls.ring, splays.ring, hand.fingers[2]);
	ApplyGenericFingerTransform(curls.pinky, splays.pinky, hand.fingers[3]);

	out_transforms[0] = { { 0.0f, 0.0f, 0.0f, 1.0f }, { 1.0f, 0.0f, 0.0f, 0.0f } };
	out_transforms[1] = { { -0.034038f, 0.036503f, 0.164722f, 1.0f }, { -0.055147f, -0.078608f, -0.920279f, 0.379296f } };

	if (role == vr::TrackedControllerRole_RightHand)
	{
		out_transforms[1].position.v[0] *= -1.f;
		out_transforms[1].orientation.y *= -1.f;
		out_transforms[1].orientation.z *= -1.f;
	}

	ComputeBoneTransformMetacarpal(role, QuatFromSwingTwist(hand.thumb.metacarpal.swing.v, hand.thumb.metacarpal.twist), finger_joint_lengths[0][0], out_transforms[2]);
	ComputeBoneTransform(role, QuatFromSwingTwist(hand.thumb.proximal.swing.v, hand.thumb.metacarpal.twist), finger_joint_lengths[0][1], out_transforms[3]);
	ComputeBoneTransform(role, QuatFromEuler(hand.thumb.distal.rotation, 0.f, 0.f), finger_joint_lengths[0][2], out_transforms[4]);
	ComputeBoneTransform(role, { 1.f, 0.f, 0.f, 0.f }, finger_joint_lengths[0][3], out_transforms[5]);

	int bone_idx = 6;
	for (int finger = 0; finger < 4; finger++)
	{
		ComputeBoneTransformMetacarpal(role, QuatFromSwingTwist(hand.fingers[finger].metacarpal.swing.v, hand.fingers[finger].metacarpal.twist),
			finger_joint_lengths[finger + 1][0], out_transforms[bone_idx++]);

		ComputeBoneTransform(role, QuatFromSwingTwist(hand.fingers[finger].proximal.swing.v, hand.fingers[finger].proximal.twist),
			finger_joint_lengths[finger + 1][1], out_transforms[bone_idx++]);

		ComputeBoneTransform(role, QuatFromEuler(hand.fingers[finger].intermediate.rotation, 0.f, 0.f),
			finger_joint_lengths[finger + 1][2], out_transforms[bone_idx++]);

		ComputeBoneTransform(role, QuatFromEuler(hand.fingers[finger].distal.rotation, 0.f, 0.f),
			finger_joint_lengths[finger + 1][3], out_transforms[bone_idx++]);

		ComputeBoneTransform(role, { 1.f, 0.f, 0.f, 0.f }, finger_joint_lengths[finger + 1][4], out_transforms[bone_idx++]);
	}

	out_transforms[26] = out_transforms[5];
	out_transforms[27] = out_transforms[10];
	out_transforms[28] = out_transforms[15];
	out_transforms[29] = out_transforms[20];
	out_transforms[30] = out_transforms[25];
}
