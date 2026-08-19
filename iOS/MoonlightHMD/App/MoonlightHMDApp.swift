import SwiftUI
import UIKit

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

    @State private var isStreaming = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if isStreaming {
                // アプリ単体で動作するMetal 2眼 VR画面ストリームビューアー (Moonlight統合)
                ZStack(alignment: .topLeading) {
                    VRStreamViewControllerRepresentable()
                        .edgesIgnoringSafeArea(.all)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("VR HMD Streaming & Tracking Active")
                            .font(.caption)
                            .foregroundColor(.green)
                            .bold()
                        Text("Head: \(String(format: "%.2f, %.2f, %.2f", trackerManager.headPosition.x, trackerManager.headPosition.y, trackerManager.headPosition.z))")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding()

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: toggleStreaming) {
                                Text("Exit HMD Mode")
                                    .font(.caption)
                                    .padding(8)
                                    .background(Color.red.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding()
                        }
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Text("Moonlight 6DoF & Hand Tracking HMD")
                        .font(.title2)
                        .foregroundColor(.white)
                        .bold()

                    HStack {
                        Text("PC IP Address:")
                            .foregroundColor(.gray)
                        TextField("192.168.x.x", text: $targetIP)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                    }

                    Button(action: toggleStreaming) {
                        Text("Start VR HMD Mode")
                            .font(.headline)
                            .padding()
                            .frame(width: 240)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tracking & Built-in Streamer:")
                            .foregroundColor(.yellow)
                        Text("Head Pos: \(String(format: "%.2f, %.2f, %.2f", trackerManager.headPosition.x, trackerManager.headPosition.y, trackerManager.headPosition.z))")
                            .foregroundColor(.white)
                            .font(.caption)
                        Text("Left Hand: \(trackerManager.leftHandData?.isTracked == 1 ? "Tracked" : "Lost")")
                            .foregroundColor(.white)
                            .font(.caption)
                        Text("Right Hand: \(trackerManager.rightHandData?.isTracked == 1 ? "Tracked" : "Lost")")
                            .foregroundColor(.white)
                            .font(.caption)
                        Text("Moonlight Embedded VR Engine: READY")
                            .foregroundColor(.green)
                            .font(.caption2)
                            .bold()
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true

            trackerManager.onTrackingDataUpdated = { headPos, headRot, left, right in
                gestureProcessor.processHandState(leftHand: left, rightHand: right)
                if isStreaming {
                    streamer.sendPacket(headPos: headPos, headRot: headRot, leftHand: left, rightHand: right)
                }
            }
        }
    }

    private func toggleStreaming() {
        if isStreaming {
            streamer.stop()
            trackerManager.stopTracking()
            isStreaming = false
        } else {
            UIApplication.shared.isIdleTimerDisabled = true
            streamer.connect(targetIP: targetIP, port: 9050)
            trackerManager.startTracking()
            isStreaming = true
        }
    }
}
