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
        static auto lastLogTime = std::chrono::steady_clock::now();
        m_pUdpReceiver->Start(9050, [this](const TrackingPacket& packet) {
            if (m_pHmdDriver) {
                m_pHmdDriver->UpdateHeadPose(packet.headPosition, packet.headRotation);
            }
            if (m_pLeftHandDriver) {
                m_pLeftHandDriver->UpdateHandPose(packet.hands[0], packet.headPosition, packet.headRotation);
            }
            if (m_pRightHandDriver) {
                m_pRightHandDriver->UpdateHandPose(packet.hands[1], packet.headPosition, packet.headRotation);
            }

            // Debug log tracking packets every 1 second
            std::chrono::steady_clock::time_point currentTime = std::chrono::steady_clock::now();
            auto diff = std::chrono::duration_cast<std::chrono::milliseconds>(currentTime - lastLogTime).count();
            if (diff > 1000) {
                lastLogTime = currentTime;
                FILE* f = fopen("tracking_debug.log", "w");
                if (f) {
                    const auto& lh = packet.hands[0];
                    const auto& rh = packet.hands[1];
                    fprintf(f, "=== iPhoneVR Live Tracking Debug ===\n");
                    fprintf(f, "Head: Pos(%.2f, %.2f, %.2f) Rot(%.2f, %.2f, %.2f, %.2f)\n",
                        packet.headPosition.x, packet.headPosition.y, packet.headPosition.z,
                        packet.headRotation.w, packet.headRotation.x, packet.headRotation.y, packet.headRotation.z);
                    fprintf(f, "\n[LEFT HAND] Tracked:%d Pinch:%d Dist:%.3f\n", lh.isTracked, lh.isPinching, lh.pinchDistance);
                    fprintf(f, "  Wrist Pos:(%.2f, %.2f, %.2f) Rot:(w:%.2f, x:%.2f, y:%.2f, z:%.2f)\n",
                        lh.joints[0].position.x, lh.joints[0].position.y, lh.joints[0].position.z,
                        lh.joints[0].orientation.w, lh.joints[0].orientation.x, lh.joints[0].orientation.y, lh.joints[0].orientation.z);
                    fprintf(f, "  Curls: Thumb:%.2f Index:%.2f Mid:%.2f Ring:%.2f Pinky:%.2f\n",
                        lh.curls.thumb, lh.curls.index, lh.curls.middle, lh.curls.ring, lh.curls.pinky);
                    fprintf(f, "  Joy-Con Connected:%d Mask:0x%X Trig:%.2f Grip:%.2f Stick:(%.2f, %.2f)\n",
                        lh.controller.isConnected, lh.controller.buttonMask, lh.controller.triggerValue, lh.controller.gripValue, lh.controller.stickX, lh.controller.stickY);
                    
                    fprintf(f, "\n[RIGHT HAND] Tracked:%d Pinch:%d Dist:%.3f\n", rh.isTracked, rh.isPinching, rh.pinchDistance);
                    fprintf(f, "  Wrist Pos:(%.2f, %.2f, %.2f) Rot:(w:%.2f, x:%.2f, y:%.2f, z:%.2f)\n",
                        rh.joints[0].position.x, rh.joints[0].position.y, rh.joints[0].position.z,
                        rh.joints[0].orientation.w, rh.joints[0].orientation.x, rh.joints[0].orientation.y, rh.joints[0].orientation.z);
                    fprintf(f, "  Curls: Thumb:%.2f Index:%.2f Mid:%.2f Ring:%.2f Pinky:%.2f\n",
                        rh.curls.thumb, rh.curls.index, rh.curls.middle, rh.curls.ring, rh.curls.pinky);
                    fprintf(f, "  Joy-Con Connected:%d Mask:0x%X Trig:%.2f Grip:%.2f Stick:(%.2f, %.2f)\n",
                        rh.controller.isConnected, rh.controller.buttonMask, rh.controller.triggerValue, rh.controller.gripValue, rh.controller.stickX, rh.controller.stickY);
                    fclose(f);
                }
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
