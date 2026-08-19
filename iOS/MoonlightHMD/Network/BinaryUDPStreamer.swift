import Foundation
import Network
import simd

// C++ tracking_protocol.h と完全互換のバイナリ構造体定義 (ポプちゃん指示: UDPバイナリパッキング)
struct Vector3f {
    var x: Float
    var y: Float
    var z: Float
}

struct Quaternionf {
    var w: Float
    var x: Float
    var y: Float
    var z: Float
}

struct BoneTransform {
    var position: Vector3f
    var orientation: Quaternionf
}

struct HandPacketData {
    var chirality: UInt8 // 0: Left, 1: Right
    var isTracked: UInt8 // 0: No, 1: Yes
    var isPinching: UInt8 // 0: No, 1: Yes
    var pinchDistance: Float
    var joints: (
        BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
        BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
        BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
        BoneTransform, BoneTransform, BoneTransform, BoneTransform, BoneTransform,
        BoneTransform
    )
}

struct TrackingPacket {
    var magic: UInt32 = 0x52565049 // "IPVR"
    var sequence: UInt32 = 0
    var timestamp: Double = 0.0
    var headPosition: Vector3f = Vector3f(x: 0, y: 0, z: 0)
    var headRotation: Quaternionf = Quaternionf(w: 1, x: 0, y: 0, z: 0)
    var hands: (HandPacketData, HandPacketData)
}

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
        var packet = TrackingPacket(
            magic: 0x52565049,
            sequence: sequenceNumber,
            timestamp: Date().timeIntervalSince1970,
            headPosition: Vector3f(x: headPos.x, y: headPos.y, z: headPos.z),
            headRotation: Quaternionf(w: headRot.real, x: headRot.imag.x, y: headRot.imag.y, z: headRot.imag.z),
            hands: (
                leftHand ?? dummyHand(chirality: 0),
                rightHand ?? dummyHand(chirality: 1)
            )
        )

        // C struct のメモリブロックを直接 Data として抽出 (コピーフリー / 低遅延)
        let data = withUnsafeBytes(of: &packet) { Data($0) }
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("UDP Send Error: \(error)")
            }
        }))
    }

    private func dummyHand(chirality: UInt8) -> HandPacketData {
        let dummyBone = BoneTransform(
            position: Vector3f(x: 0, y: 0, z: 0),
            orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0)
        )
        return HandPacketData(
            chirality: chirality,
            isTracked: 0,
            isPinching: 0,
            pinchDistance: 0.0,
            joints: (
                dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
                dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
                dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
                dummyBone, dummyBone, dummyBone, dummyBone, dummyBone, dummyBone
            )
        )
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }
}
