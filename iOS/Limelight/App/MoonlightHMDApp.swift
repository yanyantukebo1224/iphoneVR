import SwiftUI
import UIKit
import AVFoundation

@main
struct MoonlightHMDApp: App {
    @StateObject private var trackerManager = ARHandTrackerManager()
    @StateObject private var gestureProcessor = HandGestureProcessor()
    private let streamer = BinaryUDPStreamer()

    @AppStorage("vr_target_ip") private var targetIP: String = "192.168.0.13"
    @AppStorage("vr_udp_port") private var udpPort: String = "9050"
    @AppStorage("vr_mode_enabled") private var isVRModeEnabled: Bool = true
    @AppStorage("vr_hand_tracking_enabled") private var isHandTrackingEnabled: Bool = true

    init() {
        // iPhone画面のスリープ（消灯）を絶対発生させない！
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            CleanVRMainView(
                trackerManager: trackerManager,
                gestureProcessor: gestureProcessor,
                streamer: streamer,
                targetIP: $targetIP,
                udpPort: $udpPort,
                isVRModeEnabled: $isVRModeEnabled,
                isHandTrackingEnabled: $isHandTrackingEnabled
            )
        }
    }
}

struct VRStreamViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> MoonlightVRViewController {
        return MoonlightVRViewController()
    }

    func updateUIViewController(_ uiViewController: MoonlightVRViewController, context: Context) {}
}

struct CleanVRMainView: View {
    @ObservedObject var trackerManager: ARHandTrackerManager
    @ObservedObject var gestureProcessor: HandGestureProcessor
    let streamer: BinaryUDPStreamer

    @Binding var targetIP: String
    @Binding var udpPort: String
    @Binding var isVRModeEnabled: Bool
    @Binding var isHandTrackingEnabled: Bool

    @State private var isStreaming = false
    @State private var cameraPermissionStatusText: String = "Not Requested"
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12).edgesIgnoringSafeArea(.all)

            if isStreaming {
                // VR ストリーミング画面
                ZStack(alignment: .topLeading) {
                    VRStreamViewControllerRepresentable()
                        .edgesIgnoringSafeArea(.all)

                    // 6DoF リアルタイムステータス表示
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("MOONLIGHT VR STREAMING & 6DOF ACTIVE")
                                .font(.caption)
                                .foregroundColor(.green)
                                .bold()
                        }
                        Text("Head: \(String(format: "%.2f, %.2f, %.2f", trackerManager.headPosition.x, trackerManager.headPosition.y, trackerManager.headPosition.z))")
                            .font(.caption2)
                            .foregroundColor(.white)
                        if isHandTrackingEnabled {
                            Text("Left Hand: \(trackerManager.leftHandData?.isTracked == 1 ? "Tracked" : "Searching...")")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text("Right Hand: \(trackerManager.rightHandData?.isTracked == 1 ? "Tracked" : "Searching...")")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.80))
                    .cornerRadius(10)
                    .padding()

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: stopVRStreaming) {
                                Text("End VR Session")
                                    .font(.caption)
                                    .bold()
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 14)
                                    .background(Color.red.opacity(0.85))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding()
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 22) {
                        // タイトルヘッダー
                        VStack(spacing: 4) {
                            Text("Moonlight 6DoF & VR HMD")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.white)
                            Text("PC Streamer + ARKit 6DoF + Vision Hand Tracker")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        // メインスタートボタン
                        Button(action: requestCameraAndStart) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                Text("Start VR HMD Mode")
                                    .font(.headline)
                                    .bold()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }
                        .padding(.horizontal)

                        if let err = errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }

                        // 設定セクション
                        VStack(alignment: .leading, spacing: 16) {
                            Text("VR & TRACKING SETTINGS")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .bold()

                            Toggle(isOn: $isVRModeEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Stereoscopic 3D VR Mode (SBS)")
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                    Text("Split screen for VR headsets")
                                        .foregroundColor(.gray)
                                        .font(.caption2)
                                }
                            }

                            Divider().background(Color.gray.opacity(0.3))

                            Toggle(isOn: $isHandTrackingEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Vision 21-Joint Hand Tracking")
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                    Text("Track finger bones & pinch gestures")
                                        .foregroundColor(.gray)
                                        .font(.caption2)
                                }
                            }

                            Divider().background(Color.gray.opacity(0.3))

                            HStack {
                                Text("PC Host IP:")
                                    .foregroundColor(.white)
                                    .font(.subheadline)
                                Spacer()
                                TextField("192.168.x.x", text: $targetIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.decimalPad)
                                    .frame(width: 140)
                            }

                            HStack {
                                Text("UDP Port:")
                                    .foregroundColor(.white)
                                    .font(.subheadline)
                                Spacer()
                                TextField("9050", text: $udpPort)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad)
                                    .frame(width: 90)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(16)
                        .padding(.horizontal)

                        // システムステータス
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SYSTEM SENSOR STATUS")
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .bold()

                            HStack {
                                Text("Camera Access:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(cameraPermissionStatusText)
                                    .font(.caption)
                                    .foregroundColor(cameraPermissionStatusText == "Authorized" ? .green : .orange)
                                    .bold()
                            }

                            HStack {
                                Text("ARKit 6DoF Pose Engine:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("Ready (Port \(udpPort))")
                                    .font(.caption)
                                    .foregroundColor(.green)
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
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            checkCameraPermissionStatus()

            trackerManager.onTrackingDataUpdated = { headPos, headRot, left, right in
                gestureProcessor.processHandState(leftHand: left, rightHand: right)
                if isStreaming {
                    let port = UInt16(udpPort) ?? 9050
                    streamer.sendPacket(headPos: headPos, headRot: headRot, leftHand: left, rightHand: right)
                }
            }
        }
    }

    private func checkCameraPermissionStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionStatusText = "Authorized"
        case .notDetermined:
            cameraPermissionStatusText = "Pending"
        default:
            cameraPermissionStatusText = "Denied"
        }
    }

    private func requestCameraAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            startVRStreaming()
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.cameraPermissionStatusText = "Authorized"
                        self.startVRStreaming()
                    } else {
                        self.cameraPermissionStatusText = "Denied"
                        self.errorMessage = "Camera access is required for 6DoF tracking."
                    }
                }
            }
        } else {
            errorMessage = "Camera access denied. Enable camera in iOS Settings."
        }
    }

    private func startVRStreaming() {
        errorMessage = nil
        let port = UInt16(udpPort) ?? 9050
        streamer.connect(targetIP: targetIP, port: port)
        trackerManager.startTracking()
        isStreaming = true
    }

    private func stopVRStreaming() {
        streamer.stop()
        trackerManager.stopTracking()
        isStreaming = false
    }
}
