import SwiftUI
import UIKit
import AVFoundation

@main
struct MoonlightHMDApp: App {
    @StateObject private var trackerManager = ARHandTrackerManager()
    @StateObject private var gestureProcessor = HandGestureProcessor()
    private let streamer = BinaryUDPStreamer()

    @AppStorage("pc_target_ip") private var pcTargetIP: String = "192.168.0.13"

    init() {
        // iPhone画面のスリープ（消灯）を絶対発生させない！
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                trackerManager: trackerManager,
                gestureProcessor: gestureProcessor,
                streamer: streamer,
                targetIP: $pcTargetIP
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

struct ContentView: View {
    @ObservedObject var trackerManager: ARHandTrackerManager
    @ObservedObject var gestureProcessor: HandGestureProcessor
    let streamer: BinaryUDPStreamer
    @Binding var targetIP: String

    @ObservedObject var vrSettings = VRSettingsManager.shared
    @ObservedObject var gcManager = GameControllerManager.shared

    @State private var isStreaming = false
    @State private var cameraPermissionGranted = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.12).edgesIgnoringSafeArea(.all)

            if isStreaming {
                ZStack(alignment: .topLeading) {
                    VRStreamViewControllerRepresentable()
                        .edgesIgnoringSafeArea(.all)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("MOONLIGHT VR 6DoF ACTIVE")
                                .font(.caption)
                                .foregroundColor(.green)
                                .bold()
                        }
                        Text("Head: \(String(format: "%.2f, %.2f, %.2f", trackerManager.headPosition.x, trackerManager.headPosition.y, trackerManager.headPosition.z))")
                            .font(.caption2)
                            .foregroundColor(.white)
                        Text("Left: \(trackerManager.leftHandData?.isTracked == 1 ? "Tracked (3D)" : "Searching...")")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("Right: \(trackerManager.rightHandData?.isTracked == 1 ? "Tracked (3D)" : "Searching...")")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("Joy-Con: \(gcManager.isConnected ? "Connected (Primary)" : "None")")
                            .font(.caption2)
                            .foregroundColor(gcManager.isConnected ? .cyan : .gray)
                        Text("Finger Tracking: \(vrSettings.isFingerTrackingExperimentalEnabled ? "🧪 Experimental ON" : "Off (Controller Driven)")")
                            .font(.caption2)
                            .foregroundColor(vrSettings.isFingerTrackingExperimentalEnabled ? .yellow : .gray)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(10)
                    .padding()

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: toggleStreaming) {
                                Text("Disconnect VR Stream")
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
                    VStack(spacing: 20) {
                        VStack(spacing: 6) {
                            Text("Moonlight VR HMD")
                                .font(.title)
                                .foregroundColor(.white)
                                .bold()
                            Text("6DoF Head & 3D Hand Controller Tracking")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        // 設定カード
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SteamVR Host PC IP Address:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                TextField("192.168.x.x", text: $vrSettings.targetIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.decimalPad)
                            }

                            Divider().background(Color.gray.opacity(0.3))

                            Toggle(isOn: $vrSettings.isHandTrackingEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Vision 3D Hand Tracking")
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                    Text("Tracks 3D position & wrist orientation via camera")
                                        .foregroundColor(.gray)
                                        .font(.caption2)
                                }
                            }

                            if vrSettings.isHandTrackingEnabled {
                                Toggle(isOn: $vrSettings.isFingerTrackingExperimentalEnabled) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("🧪 実験的フィンガートラッキング")
                                            .foregroundColor(.yellow)
                                            .font(.subheadline)
                                            .bold()
                                        Text("21関節リアルタイム骨格追従 (Joy-Con接続時は物理操作が自動優先)")
                                            .foregroundColor(.gray)
                                            .font(.caption2)
                                    }
                                }
                                .padding(.leading, 8)
                            }

                            Divider().background(Color.gray.opacity(0.3))

                            Button(action: requestCameraAndStart) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Connect & Start VR HMD")
                                        .font(.headline)
                                        .bold()
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .leading, endPoint: .trailing))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(16)
                        .padding(.horizontal)

                        if let err = errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }

                        // ステータスカード
                        VStack(alignment: .leading, spacing: 6) {
                            Text("System & Hardware Status:")
                                .foregroundColor(.yellow)
                                .font(.caption)
                                .bold()
                            Text("• Gamepad: \(gcManager.controllerStatusDescription)")
                                .foregroundColor(gcManager.isConnected ? .cyan : .white)
                                .font(.caption2)
                            Text("• ARKit 6DoF Engine: Active (Gravity Aligned)")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text("• Camera Access: \(cameraPermissionGranted ? "Authorized" : "Pending")")
                                .foregroundColor(cameraPermissionGranted ? .green : .orange)
                                .font(.caption2)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            checkCameraPermission()

            trackerManager.onTrackingDataUpdated = { headPos, headRot, left, right in
                gestureProcessor.processHandState(leftHand: left, rightHand: right)
                if isStreaming {
                    streamer.sendPacket(headPos: headPos, headRot: headRot, leftHand: left, rightHand: right)
                }
            }
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.cameraPermissionGranted = granted
                }
            }
        default:
            cameraPermissionGranted = false
        }
    }

    private func requestCameraAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            toggleStreaming()
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.cameraPermissionGranted = granted
                    if granted {
                        self.toggleStreaming()
                    } else {
                        self.errorMessage = "Camera permission is required for 6DoF tracking."
                    }
                }
            }
        } else {
            errorMessage = "Camera access denied in Settings. Please allow camera access."
        }
    }

    private func toggleStreaming() {
        if isStreaming {
            streamer.stop()
            trackerManager.stopTracking()
            isStreaming = false
        } else {
            errorMessage = nil
            UIApplication.shared.isIdleTimerDisabled = true
            let port = UInt16(vrSettings.udpPort) ?? 9050
            streamer.connect(targetIP: vrSettings.targetIP, port: port)
            trackerManager.startTracking()
            isStreaming = true
        }
    }
}
