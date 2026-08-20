import SwiftUI
import UIKit
import AVFoundation

struct MoonlightVRMainView: View {
    @StateObject private var vrSettings = VRSettingsManager.shared
    @StateObject private var trackerManager = ARHandTrackerManager()
    @StateObject private var gestureProcessor = HandGestureProcessor()
    private let streamer = BinaryUDPStreamer()

    @State private var isVRStreamingActive = false
    @State private var cameraPermissionStatus: String = "Checking..."
    @State private var totalPacketsSent: Int = 0

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.11).edgesIgnoringSafeArea(.all)

                if isVRStreamingActive {
                    // VR HMD 純粋フルスクリーンVRレンダリング画面（オーバーレイ完全排除）
                    ZStack(alignment: .bottomTrailing) {
                        MoonlightNativeStreamViewRepresentable()
                            .edgesIgnoringSafeArea(.all)

                        Button(action: stopVRStreaming) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color.white.opacity(0.3))
                                .padding(16)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // ヘッダー統合バー
                            HStack {
                                Image(systemName: "vr")
                                    .font(.system(size: 36))
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Moonlight VR HMD")
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.white)
                                    Text("Official Core + 6DoF & 21-Joint Tracking")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)

                            // メインスタートボタン
                            Button(action: requestAndStartVRStreaming) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title)
                                    Text("LAUNCH VR HMD STREAMING")
                                        .font(.headline)
                                        .bold()
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .leading, endPoint: .trailing))
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                            .padding(.horizontal)

                            // 🥽 VR / Tracking 設定セクション
                            VStack(alignment: .leading, spacing: 14) {
                                Text("VR & TRACKING CONFIGURATION")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .bold()

                                Toggle(isOn: $vrSettings.isVRModeEnabled) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Stereoscopic 3D VR Mode (SBS)")
                                            .foregroundColor(.white)
                                            .font(.subheadline)
                                        Text("Splits screen into 2-eye distortion view for HMD headsets")
                                            .foregroundColor(.gray)
                                            .font(.caption2)
                                    }
                                }

                                Divider().background(Color.gray.opacity(0.3))

                                Toggle(isOn: $vrSettings.isHandTrackingEnabled) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Vision 21-Joint Hand Tracking")
                                            .foregroundColor(.white)
                                            .font(.subheadline)
                                        Text("Tracks hand 3D position & gestures for SteamVR controllers")
                                            .foregroundColor(.gray)
                                            .font(.caption2)
                                    }
                                }

                                if vrSettings.isHandTrackingEnabled {
                                    Toggle(isOn: $vrSettings.isFingerTrackingExperimentalEnabled) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Text("🧪 Experimental Finger Tracking")
                                                    .foregroundColor(.yellow)
                                                    .font(.subheadline)
                                                    .bold()
                                            }
                                            Text("Real-time 21-joint skeletal finger tracking (Joy-Con overrides automatically)")
                                                .foregroundColor(.gray)
                                                .font(.caption2)
                                        }
                                    }
                                    .padding(.leading, 12)
                                }

                                Divider().background(Color.gray.opacity(0.3))

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Target Host PC IP:")
                                            .foregroundColor(.white)
                                            .font(.subheadline)
                                        Text("SteamVR Driver Host IP")
                                            .foregroundColor(.gray)
                                            .font(.caption2)
                                    }
                                    Spacer()
                                    TextField("192.168.x.x", text: $vrSettings.targetIP)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .keyboardType(.decimalPad)
                                        .frame(width: 140)
                                }

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("UDP Tracking Port:")
                                            .foregroundColor(.white)
                                            .font(.subheadline)
                                        Text("Default: 9050")
                                            .foregroundColor(.gray)
                                            .font(.caption2)
                                    }
                                    Spacer()
                                    TextField("9050", text: $vrSettings.udpPort)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .keyboardType(.numberPad)
                                        .frame(width: 90)
                                }

                                Divider().background(Color.gray.opacity(0.3))

                                // 🔐 PIN Pairing
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Sunshine / GFE PIN Pairing:")
                                            .font(.subheadline)
                                            .bold()
                                            .foregroundColor(.white)
                                        Spacer()
                                        Button(action: {
                                            MoonlightPairingManager.shared.checkAndPair(hostIP: vrSettings.targetIP)
                                        }) {
                                            Text("Pair with PC")
                                                .font(.caption)
                                                .bold()
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.cyan)
                                                .foregroundColor(.black)
                                                .cornerRadius(6)
                                        }
                                    }

                                    if case .pairingRequired(let pin) = MoonlightPairingManager.shared.pairingState {
                                        VStack(alignment: .center, spacing: 2) {
                                            Text("ENTER THIS PIN ON YOUR PC (SUNSHINE):")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.yellow)
                                            Text(pin)
                                                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                                                .foregroundColor(.green)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .background(Color.black.opacity(0.5))
                                        .cornerRadius(6)
                                    } else if case .paired(let server) = MoonlightPairingManager.shared.pairingState {
                                        Text("✅ Paired with: \(server)")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(16)
                            .padding(.horizontal)

                            // 📊 トラッキングステータス ＆ カメラ認証カード
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SYSTEM & SENSOR STATUS")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                    .bold()

                                HStack {
                                    Text("Camera 6DoF Sensor:")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                    Spacer()
                                    Text(cameraPermissionStatus)
                                        .foregroundColor(cameraPermissionStatus == "Authorized" ? .green : .orange)
                                        .font(.caption)
                                        .bold()
                                }

                                HStack {
                                    Text("ARKit 6DoF Pose Engine:")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                    Spacer()
                                    Text("Active (Gravity Aligned)")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }

                                HStack {
                                    Text("Moonlight Core Engine:")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                    Spacer()
                                    Text("VideoToolbox NVDEC Ready")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            checkCameraAccess()

            trackerManager.onTrackingDataUpdated = { headPos, headRot, left, right in
                gestureProcessor.processHandState(leftHand: left, rightHand: right)
                if isVRStreamingActive {
                    let port = UInt16(vrSettings.udpPort) ?? 9050
                    streamer.sendPacket(headPos: headPos, headRot: headRot, leftHand: left, rightHand: right)
                }
            }
        }
    }

    private func checkCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionStatus = "Authorized"
        case .notDetermined:
            cameraPermissionStatus = "Pending Approval"
        default:
            cameraPermissionStatus = "Access Denied"
        }
    }

    private func requestAndStartVRStreaming() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    self.cameraPermissionStatus = "Authorized"
                    self.startVRStreaming()
                } else {
                    self.cameraPermissionStatus = "Access Denied"
                }
            }
        }
    }

    private func startVRStreaming() {
        let port = UInt16(vrSettings.udpPort) ?? 9050
        streamer.connect(targetIP: vrSettings.targetIP, port: port)
        trackerManager.startTracking()
        isVRStreamingActive = true
    }

    private func stopVRStreaming() {
        streamer.stop()
        trackerManager.stopTracking()
        isVRStreamingActive = false
    }
}
