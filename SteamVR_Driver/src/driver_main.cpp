#include "openvr_driver_stub.h"
#include "hmd_device_driver.h"
#include "hand_controller_driver.h"
#include "udp_receiver.h"
#include <iostream>
#include <memory>
#include <cstring>

class ServerTrackedDeviceProvider : public vr::IServerTrackedDeviceProvider {
public:
    ServerTrackedDeviceProvider() {}
    virtual ~ServerTrackedDeviceProvider() {}

    virtual vr::EVRInitError Init(vr::IVRDriverContext* pDriverContext) override {
        g_hmdDriver = std::make_unique<HMDDeviceDriver>();
        g_leftHandDriver = std::make_unique<HandControllerDriver>(vr::TrackedControllerRole_LeftHand);
        g_rightHandDriver = std::make_unique<HandControllerDriver>(vr::TrackedControllerRole_RightHand);

        g_udpReceiver = std::make_unique<UDPReceiver>();
        g_udpReceiver->Start(9050, OnTrackingPacketReceived);

        return vr::VRInitError_None;
    }

    virtual void Cleanup() override {
        if (g_udpReceiver) {
            g_udpReceiver->Stop();
            g_udpReceiver.reset();
        }
        g_hmdDriver.reset();
        g_leftHandDriver.reset();
        g_rightHandDriver.reset();
    }

    virtual const char* const* GetInterfaceVersions() override {
        static const char* const pInterfaceVersions[] = {
            vr::IServerTrackedDeviceProvider_Version,
            nullptr
        };
        return pInterfaceVersions;
    }

    virtual void RunFrame() override {}
    virtual bool ShouldBlockStandbyMode() override { return false; }
    virtual void EnterStandby() override {}
    virtual void LeaveStandby() override {}

private:
    static void OnTrackingPacketReceived(const TrackingPacket& packet) {
        if (g_hmdDriver) {
            g_hmdDriver->UpdateHeadPose(packet.headPosition, packet.headRotation);
        }
        if (g_leftHandDriver) {
            g_leftHandDriver->UpdateHandPose(packet.hands[0], packet.headPosition);
        }
        if (g_rightHandDriver) {
            g_rightHandDriver->UpdateHandPose(packet.hands[1], packet.headPosition);
        }
    }

    static std::unique_ptr<HMDDeviceDriver> g_hmdDriver;
    static std::unique_ptr<HandControllerDriver> g_leftHandDriver;
    static std::unique_ptr<HandControllerDriver> g_rightHandDriver;
    static std::unique_ptr<UDPReceiver> g_udpReceiver;
};

std::unique_ptr<HMDDeviceDriver> ServerTrackedDeviceProvider::g_hmdDriver = nullptr;
std::unique_ptr<HandControllerDriver> ServerTrackedDeviceProvider::g_leftHandDriver = nullptr;
std::unique_ptr<HandControllerDriver> ServerTrackedDeviceProvider::g_rightHandDriver = nullptr;
std::unique_ptr<UDPReceiver> ServerTrackedDeviceProvider::g_udpReceiver = nullptr;

static ServerTrackedDeviceProvider g_serverTrackedDeviceProvider;

#if defined(_WIN32)
#define HMD_DLL_EXPORT __declspec(dllexport)
#else
#define HMD_DLL_EXPORT __attribute__((visibility("default")))
#endif

extern "C" HMD_DLL_EXPORT void* HmdDriverFactory(const char* pInterfaceName, int* pReturnCode) {
    if (std::strcmp(pInterfaceName, vr::IServerTrackedDeviceProvider_Version) == 0) {
        if (pReturnCode) *pReturnCode = vr::VRInitError_None;
        return &g_serverTrackedDeviceProvider;
    }

    if (pReturnCode) *pReturnCode = vr::VRInitError_Init_InterfaceNotFound;
    return nullptr;
}
