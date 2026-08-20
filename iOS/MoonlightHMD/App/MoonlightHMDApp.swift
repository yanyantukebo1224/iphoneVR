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

    @State private var isStreaming = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if isStreaming {
                // VR HMD レンダリング ＆ 6DoF カメラトラッキング画面
                ZStack(alignment: .topLeading) {
                    VRRenderViewRepresentable(hostIP: targetIP)
                        .edgesIgnoringSafeArea(.all)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("MOONLIGHT VR SBS & 6DOF / 21-JOINT ACTIVE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        }
                        Text("Head Pos: \(String(format: "%.2f, %.2f, %.2f", trackerManager.headPosition.x, trackerManager.headPosition.y, trackerManager.headPosition.z))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white)
                        Text("Gamepad: \(controllerManager.controllerStatusDescription)")
                            .font(.system(size: 10))
                            .foregroundColor(controllerManager.isConnected ? .cyan : .gray)
                        Text("Left Hand: \(trackerManager.leftHandData?.isTracked == 1 ? "Tracked (Curl: \(String(format: "%.2f", trackerManager.leftHandData?.curls.index ?? 0)))" : "Searching...")")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                        Text("Right Hand: \(trackerManager.rightHandData?.isTracked == 1 ? "Tracked (Curl: \(String(format: "%.2f", trackerManager.rightHandData?.curls.index ?? 0)))" : "Searching...")")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(8)
                    .padding()

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: toggleStreaming) {
                                Text("Exit VR Mode")
                                    .font(.caption)
                                    .bold()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
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
                        Text("Moonlight 6DoF VR HMD")
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

                        // 🔐 Moonlight / Sunshine PINペアリングカード
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.cyan)
                                Text("Moonlight / Sunshine PIN Pairing:")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: {
                                    pairingManager.checkAndPair(hostIP: targetIP)
                                }) {
                                    Text("Pair with PC")
                                        .font(.caption2)
                                        .bold()
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.cyan)
                                        .foregroundColor(.black)
                                        .cornerRadius(6)
                                }
                            }

                            if case .pairingRequired(let pin) = pairingManager.pairingState {
                                VStack(alignment: .center, spacing: 4) {
                                    Text("ENTER THIS PIN ON YOUR PC (SUNSHINE/GFE):")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.yellow)
                                    Text(pin)
                                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.green)
                                        .padding(.vertical, 4)
                                }
                                .frame(maxWidth: .infinity)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                            } else if case .paired(let server) = pairingManager.pairingState {
                                Text("✅ Paired with: \(server)")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            } else if case .failed(let err) = pairingManager.pairingState {
                                Text("Status: \(err)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                            } else {
                                Text("Tap 'Pair with PC' to generate 4-digit PIN for Sunshine / GeForce Experience")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .padding(.horizontal)

                        // 🎮 Switch / Gamepad 接続ステータスカード
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                    .foregroundColor(controllerManager.isConnected ? .green : .gray)
                                Text("VR Controller (Switch / Gamepad):")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.white)
                            }
                            Text(controllerManager.controllerStatusDescription)
                                .font(.caption2)
                                .foregroundColor(controllerManager.isConnected ? .green : .orange)
                            Text("Joy-Con L/R or Pro Controller can be paired via iOS Bluetooth Settings")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .padding(.horizontal)

                        // 📊 センサー＆トラッキング状態カード
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tracking & Stream Status:")
                                .foregroundColor(.yellow)
                                .bold()
                            Text("Head Pos: \(String(format: "%.2f, %.2f, %.2f", trackerManager.headPosition.x, trackerManager.headPosition.y, trackerManager.headPosition.z))")
                                .foregroundColor(.white)
                                .font(.caption)
                            Text("Left Hand: \(trackerManager.leftHandData?.isTracked == 1 ? "Tracked" : "Lost")")
                                .foregroundColor(.white)
                                .font(.caption)
                            Text("Right Hand: \(trackerManager.rightHandData?.isTracked == 1 ? "Tracked" : "Lost")")
                                .foregroundColor(.white)
                                .font(.caption)
                            Text("Screen Sleep: DISABLED (Keep Awake)")
                                .foregroundColor(.green)
                                .font(.caption2)
                                .bold()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    .padding()
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

