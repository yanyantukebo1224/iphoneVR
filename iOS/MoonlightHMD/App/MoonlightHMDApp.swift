import SwiftUI
import UIKit

@main
struct MoonlightHMDApp: App {
    @StateObject private var trackerManager = ARHandTrackerManager()
    @StateObject private var gestureProcessor = HandGestureProcessor()
    @StateObject private var controllerManager = GameControllerManager.shared
    @StateObject private var pairingManager = MoonlightPairingManager.shared
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
                controllerManager: controllerManager,
                pairingManager: pairingManager,
                streamer: streamer,
                targetIP: $pcTargetIP
            )
        }
    }
}

struct ContentView: View {
    @ObservedObject var trackerManager: ARHandTrackerManager
    @ObservedObject var gestureProcessor: HandGestureProcessor
    @ObservedObject var controllerManager: GameControllerManager
    @ObservedObject var pairingManager: MoonlightPairingManager
    let streamer: BinaryUDPStreamer
    @Binding var targetIP: String

    @ObservedObject var vrSettings = VRSettingsManager.shared

    @State private var isStreaming = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.10).edgesIgnoringSafeArea(.all)

            if isStreaming {
                // VR HMD 純粋フルスクリーンVRレンダリング画面
                ZStack(alignment: .bottomTrailing) {
                    VRRenderViewRepresentable(hostIP: targetIP)
                        .edgesIgnoringSafeArea(.all)

                    Button(action: toggleStreaming) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color.white.opacity(0.4))
                            .padding(20)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 4) {
                            Text("Moonlight 6DoF VR HMD")
                                .font(.title2)
                                .foregroundColor(.white)
                                .bold()
                            Text("Sunshine / GameStream VR Controller & 6DoF")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }

                        // 接続設定カード
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SteamVR PC IP Address:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                TextField("192.168.x.x", text: $targetIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.decimalPad)
                            }

                            Divider().background(Color.gray.opacity(0.3))

                            Toggle(isOn: $vrSettings.isHandTrackingEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("3D Hand Tracking")
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                    Text("Tracks position in front of HMD via camera")
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
                                        Text("21関節リアルタイム骨格追従 (Joy-Con接続時は物理ボタン最優先)")
                                            .foregroundColor(.gray)
                                            .font(.caption2)
                                    }
                                }
                                .padding(.leading, 8)
                            }

                            Divider().background(Color.gray.opacity(0.3))

                            Button(action: toggleStreaming) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Start VR HMD Mode")
                                        .bold()
                                }
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .leading, endPoint: .trailing))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(14)
                        .padding(.horizontal)

                        // 🎮 Joy-Con / Gamepad 接続ステータスカード
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                    .foregroundColor(controllerManager.isConnected ? .green : .gray)
                                Text("VR Controller (Joy-Con / Gamepad):")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.white)
                            }
                            Text(controllerManager.controllerStatusDescription)
                                .font(.caption2)
                                .foregroundColor(controllerManager.isConnected ? .green : .orange)
                            
                            Text("💡 Joy-Conの [+] または [-] ボタンは SteamVR Home (ダッシュボード) ボタンとして動作します")
                                .font(.caption2)
                                .foregroundColor(.cyan)
                                .bold()
                                .padding(.top, 2)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(10)
                        .padding(.horizontal)

                        // 📊 トラッキング状態カード
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tracking Status:")
                                .foregroundColor(.yellow)
                                .font(.caption)
                                .bold()
                            Text("• Head: \(String(format: "%.2f, %.2f, %.2f", trackerManager.headPosition.x, trackerManager.headPosition.y, trackerManager.headPosition.z))")
                                .foregroundColor(.white)
                                .font(.caption2)
                            Text("• Left Hand: \(trackerManager.leftHandData?.isTracked == 1 ? "Active" : "Searching...")")
                                .foregroundColor(.white)
                                .font(.caption2)
                            Text("• Right Hand: \(trackerManager.rightHandData?.isTracked == 1 ? "Active" : "Searching...")")
                                .foregroundColor(.white)
                                .font(.caption2)
                            Text("• Finger Mode: \(vrSettings.isFingerTrackingExperimentalEnabled ? "🧪 Experimental ON" : "Controller Driven")")
                                .foregroundColor(vrSettings.isFingerTrackingExperimentalEnabled ? .yellow : .white)
                                .font(.caption2)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
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
            pairingManager.launchApp(hostIP: targetIP) { success in
                print("Launch app completed: \(success)")
            }
            streamer.connect(targetIP: targetIP, port: 9050)
            trackerManager.startTracking()
            isStreaming = true
        }
    }
}

// SwiftUI 向け VR Metal ビューブリッジ
struct VRRenderViewRepresentable: UIViewControllerRepresentable {
    var hostIP: String

    func makeUIViewController(context: Context) -> MoonlightVRViewController {
        let vc = MoonlightVRViewController()
        vc.hostIP = hostIP
        return vc
    }

    func updateUIViewController(_ uiViewController: MoonlightVRViewController, context: Context) {
        uiViewController.hostIP = hostIP
    }
}

