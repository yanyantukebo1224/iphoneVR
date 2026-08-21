#ifndef HAND_SIMULATION_H
#define HAND_SIMULATION_H

#include "openvr_driver.h"

#define DEG_TO_RAD(x) ((x) * (3.14159265358979f / 180.f))

struct MyFingerCurls
{
	float thumb;
	float index;
	float middle;
	float ring;
	float pinky;
};

struct MyFingerSplays
{
	float thumb;
	float index;
	float middle;
	float ring;
	float pinky;
};

class MyHandSimulation
{
public:
	void ComputeSkeletonTransforms(
		vr::ETrackedControllerRole role,
		const MyFingerCurls& curls,
		const MyFingerSplays& splays,
		vr::VRBoneTransform_t out_transforms[31]
	);
};

#endif // HAND_SIMULATION_H
