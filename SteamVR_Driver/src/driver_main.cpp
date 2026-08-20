#include "openvr_driver.h"
#include "hmd_device_driver.h"
#include "hand_controller_driver.h"
#include "udp_receiver.h"
#include "screen_streamer.h"
#include <iostream>
#include <memory>
#include <cstring>

class ServerTrackedDeviceProvider : public vr::IServerTrackedDeviceProvider {
public:
    ServerTrackedDeviceProvider()
        : m_pHmdDriver(nullptr), m_pLeftHandDriver(nullptr), m_pRightHandDriver(nullptr), m_pUdpReceiver(nullptr), m_pScreenStreamer(nullptr) {}
    virtual ~ServerTrackedDeviceProvider() {}

    virtual vr::EVRInitError Init(vr::IVRDriverContext* pDriverContext) override {
        VR_INIT_SERVER_DRIVER_CONTEXT(pDriverContext);

        m_pHmdDriver = new HMDDeviceDriver();
        m_pLeftHandDriver = new HandControllerDriver(vr::TrackedControllerRole_LeftHand);
        m_pRightHandDriver = new HandControllerDriver(vr::TrackedControllerRole_RightHand);

        if (vr::VRServerDriverHost()) {
            vr::VRServerDriverHost()->TrackedDeviceAdded("iPhoneVR_HMD_001", vr::TrackedDeviceClass_HMD, m_pHmdDriver);
            vr::VRServerDriverHost()->TrackedDeviceAdded("iPhoneVR_LeftHand_001", vr::TrackedDeviceClass_Controller, m_pLeftHandDriver);
            vr::VRServerDriverHost()->TrackedDeviceAdded("iPhoneVR_RightHand_001", vr::TrackedDeviceClass_Controller, m_pRightHandDriver);
        }

        m_pUdpReceiver = new UDPReceiver();
        m_pUdpReceiver->Start(9050, [this](const TrackingPacket& packet) {
            if (m_pHmdDriver) {
                m_pHmdDriver->UpdateHeadPose(packet.headPosition, packet.headRotation);
            }
            if (m_pLeftHandDriver) {
                m_pLeftHandDriver->UpdateHandPose(packet.hands[0], packet.headPosition);
            }
            if (m_pRightHandDriver) {
                m_pRightHandDriver->UpdateHandPose(packet.hands[1], packet.headPosition);
            }
        });

        // 🖥️ PC画面丸ごと iPhone VR 直接配信サーバー起動 (Port 9051)
        m_pScreenStreamer = new ScreenStreamer();
        m_pScreenStreamer->Start(9051);

        return vr::VRInitError_None;
    }

    virtual void Cleanup() override {
        if (m_pScreenStreamer) {
            m_pScreenStreamer->Stop();
            delete m_pScreenStreamer;
            m_pScreenStreamer = nullptr;
        }
        if (m_pUdpReceiver) {
            m_pUdpReceiver->Stop();
            delete m_pUdpReceiver;
            m_pUdpReceiver = nullptr;
        }
        if (m_pHmdDriver) {
            delete m_pHmdDriver;
            m_pHmdDriver = nullptr;
        }
        if (m_pLeftHandDriver) {
            delete m_pLeftHandDriver;
            m_pLeftHandDriver = nullptr;
        }
        if (m_pRightHandDriver) {
            delete m_pRightHandDriver;
            m_pRightHandDriver = nullptr;
        }
        VR_CLEANUP_SERVER_DRIVER_CONTEXT();
    }

    virtual const char* const* GetInterfaceVersions() override {
        return vr::k_InterfaceVersions;
    }

    virtual void RunFrame() override {}
    virtual bool ShouldBlockStandbyMode() override { return false; }
    virtual void EnterStandby() override {}
    virtual void LeaveStandby() override {}

private:
    HMDDeviceDriver* m_pHmdDriver;
    HandControllerDriver* m_pLeftHandDriver;
    HandControllerDriver* m_pRightHandDriver;
    UDPReceiver* m_pUdpReceiver;
    ScreenStreamer* m_pScreenStreamer;
};

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
