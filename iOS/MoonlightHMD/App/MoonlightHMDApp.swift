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

    @State private var isStreaming = false
    @State private var cameraPermissionGranted = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if isStreaming {
                ZStack(alignment: .topLeading) {
                    VRStreamViewControllerRepresentable()
                        .edgesIgnoringSafeArea(.all)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("MOONLIGHT VR STREAM & 6DOF ACTIVE")
                                .font(.caption)
                                .foregroundColor(.green)
                                .bold()
                        }
                        Text("Head Pos: \(String(format: "%.2f, %.2f, %.2f", trackerManager.headPosition.x, trackerManager.headPosition.y, trackerManager.headPosition.z))")
                            .font(.caption2)
                            .foregroundColor(.white)
                        Text("Left Hand: \(trackerManager.leftHandData?.isTracked == 1 ? "Tracked" : "Searching...")")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("Right Hand: \(trackerManager.rightHandData?.isTracked == 1 ? "Tracked" : "Searching...")")
                            .font(.caption2)
                            .foregroundColor(.gray)
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
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text("Moonlight Native VR HMD")
                            .font(.title)
                            .foregroundColor(.white)
                            .bold()
                        Text("Sunshine / GameStream Low-Latency Streamer")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Target Host PC Address:")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextField("192.168.x.x", text: $targetIP)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                                .frame(width: 260)
                        }

                        Button(action: requestCameraAndStart) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Connect & Start VR HMD")
                                    .font(.headline)
                            }
                            .padding()
                            .frame(width: 260)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(16)

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Moonlight Engine Status:")
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .bold()
                        Text("• VideoToolbox H.264/HEVC Decoder: Ready")
                            .foregroundColor(.white)
                            .font(.caption2)
                        Text("• ARKit 6DoF + Vision 21-Joint Tracker: Ready")
                            .foregroundColor(.white)
                            .font(.caption2)
                        Text("• Camera Permission: \(cameraPermissionGranted ? "Granted" : "Pending Approval")")
                            .foregroundColor(cameraPermissionGranted ? .green : .orange)
                            .font(.caption2)
                    }
                    .padding()
                    .frame(width: 280, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                }
                .padding()
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
            streamer.connect(targetIP: targetIP, port: 9050)
            trackerManager.startTracking()
            isStreaming = true
        }
    }
}
