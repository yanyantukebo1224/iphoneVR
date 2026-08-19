import SwiftUI

@main
struct MoonlightHMDApp: App {
    @StateObject private var trackerManager = ARHandTrackerManager()
    @StateObject private var gestureProcessor = HandGestureProcessor()
    private let streamer = BinaryUDPStreamer()

    @AppStorage("pc_target_ip") private var pcTargetIP: String = "192.168.1.100"

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

struct ContentView: View {
    @ObservedObject var trackerManager: ARHandTrackerManager
    @ObservedObject var gestureProcessor: HandGestureProcessor
    let streamer: BinaryUDPStreamer
    @Binding var targetIP: String

    @State private var isStreaming = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Text("Moonlight 6DoF & Hand Tracking HMD")
                    .font(.title)
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
                    Text(isStreaming ? "Stop Streaming" : "Start VR HMD Mode")
                        .font(.headline)
                        .padding()
                        .frame(width: 240)
                        .background(isStreaming ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tracking Status:")
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
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
        .onAppear {
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
            streamer.connect(targetIP: targetIP, port: 9050)
            trackerManager.startTracking()
            isStreaming = true
        }
    }
}
