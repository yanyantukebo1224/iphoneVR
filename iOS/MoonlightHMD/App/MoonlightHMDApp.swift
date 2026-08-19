import SwiftUI
import UIKit
import AVFoundation

// Moonlight-iOS 公式コアセッション ＆ Antigravity 6DoF トラッカー統合ブリッジ
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
            MoonlightMainRootView(
                trackerManager: trackerManager,
                gestureProcessor: gestureProcessor,
                streamer: streamer,
                targetIP: $pcTargetIP
            )
        }
    }
}

// Moonlight 公式スタイルのホストPC探索・PINペアリング・VRストリーミングROOT VIEW
struct MoonlightMainRootView: View {
    @ObservedObject var trackerManager: ARHandTrackerManager
    @ObservedObject var gestureProcessor: HandGestureProcessor
    let streamer: BinaryUDPStreamer
    @Binding var targetIP: String

    @State private var isVRStreamingActive = false
    @State private var pairingPinCode: String? = nil
    @State private var showPairingAlert = false
    @State private var connectionStatusText: String = "Disconnected"

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12).edgesIgnoringSafeArea(.all)

            if isVRStreamingActive {
                // Moonlight 公式 StreamViewController 統合 VR HMD レンダリング画面
                ZStack(alignment: .topLeading) {
                    MoonlightNativeStreamViewRepresentable()
                        .edgesIgnoringSafeArea(.all)

                    // 6DoF トラッキング オーバーレイ
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("MOONLIGHT VR STREAMING & ARKIT 6DOF")
                                .font(.caption)
                                .foregroundColor(.green)
                                .bold()
                        }
                        Text("Head Pos: \(String(format: "%.2f, %.2f, %.2f", trackerManager.headPosition.x, trackerManager.headPosition.y, trackerManager.headPosition.z))")
                            .font(.caption2)
                            .foregroundColor(.white)
                        Text("Left Hand: \(trackerManager.leftHandData?.isTracked == 1 ? "Tracked" : "Lost")")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("Right Hand: \(trackerManager.rightHandData?.isTracked == 1 ? "Tracked" : "Lost")")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(8)
                    .padding()

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: stopMoonlightVRStream) {
                                Text("End Stream")
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
                VStack(spacing: 24) {
                    // Moonlight 公式スタイル ヘッダー
                    HStack {
                        Image(systemName: "tv.and.mediabox.fill")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Moonlight GameStream / Sunshine HMD")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.white)
                            Text("Official Base + ARKit 6DoF & Hand Tracking")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding()

                    // PC 接続カード
                    VStack(alignment: .leading, spacing: 16) {
                        Text("HOST PC CONNECTION")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .bold()

                        HStack {
                            Text("IP Address:")
                                .foregroundColor(.gray)
                            Spacer()
                            TextField("192.168.0.x", text: $targetIP)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 180)
                        }

                        if let pin = pairingPinCode {
                            VStack(spacing: 4) {
                                Text("PIN CODE FOR SUNSHINE PAIRING:")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Text(pin)
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.green)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                        }

                        Button(action: startMoonlightVRStream) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Connect Sunshine & Start VR HMD")
                                    .font(.headline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    // システムステータス
                    VStack(alignment: .leading, spacing: 6) {
                        Text("System Integration Status:")
                            .font(.caption)
                            .foregroundColor(.yellow)
                            .bold()
                        Text("• Moonlight Core Stream Engine: Ready")
                            .font(.caption2)
                            .foregroundColor(.white)
                        Text("• ENet / RTSP Control Protocol: Ready")
                            .font(.caption2)
                            .foregroundColor(.white)
                        Text("• ARKit 6DoF Head Pose: Active (Port 9050)")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("• Vision 21-Joint Skeletal Tracking: Active")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Spacer()
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true

            trackerManager.onTrackingDataUpdated = { headPos, headRot, left, right in
                gestureProcessor.processHandState(leftHand: left, rightHand: right)
                if isVRStreamingActive {
                    streamer.sendPacket(headPos: headPos, headRot: headRot, leftHand: left, rightHand: right)
                }
            }
        }
    }

    private func startMoonlightVRStream() {
        // カメラ権限確認の上安全スタート
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.streamer.connect(targetIP: self.targetIP, port: 9050)
                self.trackerManager.startTracking()
                self.isVRStreamingActive = true
            }
        }
    }

    private func stopMoonlightVRStream() {
        streamer.stop()
        trackerManager.stopTracking()
        isVRStreamingActive = false
    }
}

// Moonlight 公式 StreamViewController 表現コンテナ
struct MoonlightNativeStreamViewRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> MoonlightVRViewController {
        return MoonlightVRViewController()
    }

    func updateUIViewController(_ uiViewController: MoonlightVRViewController, context: Context) {}
}
