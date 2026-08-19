#include "openvr_driver_stub.h"
#include "hmd_device_driver.h"
#include "hand_controller_driver.h"
#include "udp_receiver.h"
#include <iostream>
#include <memory>

static std::unique_ptr<HMDDeviceDriver> g_hmdDriver;
static std::unique_ptr<HandControllerDriver> g_leftHandDriver;
static std::unique_ptr<HandControllerDriver> g_rightHandDriver;
static std::unique_ptr<UDPReceiver> g_udpReceiver;

void OnTrackingPacketReceived(const TrackingPacket& packet) {
    // 1) 6DoF HMD ポーズ更新
    if (g_hmdDriver) {
        g_hmdDriver->UpdateHeadPose(packet.headPosition, packet.headRotation);
    }

    // 2) 両手ポーズ ＆ 31ボーン Skeletal Input 更新
    if (g_leftHandDriver) {
        g_leftHandDriver->UpdateHandPose(packet.hands[0], packet.headPosition);
    }
    if (g_rightHandDriver) {
        g_rightHandDriver->UpdateHandPose(packet.hands[1], packet.headPosition);
    }
}

// OpenVR Driver DLL エントリーポイント
#if defined(_WIN32)
#define HMD_DLL_EXPORT __declspec(dllexport)
#else
#define HMD_DLL_EXPORT __attribute__((visibility("default")))
#endif

extern "C" HMD_DLL_EXPORT void* HmdDriverFactory(const char* pInterfaceName, int* pReturnCode) {
    if (g_udpReceiver == nullptr) {
        g_hmdDriver = std::make_unique<HMDDeviceDriver>();
        g_leftHandDriver = std::make_unique<HandControllerDriver>(vr::TrackedControllerRole_LeftHand);
        g_rightHandDriver = std::make_unique<HandControllerDriver>(vr::TrackedControllerRole_RightHand);
        
        g_udpReceiver = std::make_unique<UDPReceiver>();
        g_udpReceiver->Start(9050, OnTrackingPacketReceived);
    }

    if (pReturnCode) *pReturnCode = vr::VRInitError_None;
    return nullptr;
}
