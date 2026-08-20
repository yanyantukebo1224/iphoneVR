import Foundation
import Network
import simd

class BinaryUDPStreamer {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.iphonevr.udp.stream", qos: .userInteractive)
    private var sequenceNumber: UInt32 = 0

    func connect(targetIP: String, port: UInt16 = 9050) {
        let host = NWEndpoint.Host(targetIP)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? 9050
        
        let params = NWParameters.udp
        connection = NWConnection(host: host, port: nwPort, using: params)
        connection?.start(queue: queue)
    }

    func sendPacket(headPos: SIMD3<Float>, headRot: simd_quatf, leftHand: HandPacketData?, rightHand: HandPacketData?) {
        guard let connection = connection else { return }

        sequenceNumber += 1

        let dummyBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let dummyJoints: HandJointsTuple = (
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone, dummyBone
        )

        var finalLeft = leftHand ?? HandPacketData(
            chirality: 0,
            isTracked: 0,
            isPinching: 0,
            pinchDistance: 1.0,
            curls: FingerCurls(),
            splays: FingerSplays(),
            joints: dummyJoints,
            controller: ControllerInputData()
        )
        finalLeft.chirality = 0

        var finalRight = rightHand ?? HandPacketData(
            chirality: 1,
            isTracked: 0,
            isPinching: 0,
            pinchDistance: 1.0,
            curls: FingerCurls(),
            splays: FingerSplays(),
            joints: dummyJoints,
            controller: ControllerInputData()
        )
        finalRight.chirality = 1

        var packet = TrackingPacket(
            magic: 0x52565049,
            sequence: sequenceNumber,
            timestamp: Date().timeIntervalSince1970,
            headPosition: Vector3f(x: headPos.x, y: headPos.y, z: headPos.z),
            headRotation: Quaternionf(w: headRot.real, x: headRot.imag.x, y: headRot.imag.y, z: headRot.imag.z),
            hands: (finalLeft, finalRight)
        )

        // ゼロコピー完全一致バイナリ送信 (Swift ↔ C++ 構造体 1対1完全一致)
        let data = Data(bytes: &packet, count: MemoryLayout<TrackingPacket>.size)

        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("UDP Send Error: \(error)")
            }
        }))
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }
}