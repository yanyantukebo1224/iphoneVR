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
        var data = Data()

        // 1. ヘッダー
        var magic: UInt32 = 0x52565049 // "IPVR"
        var seq = sequenceNumber
        var ts = Date().timeIntervalSince1970

        var hx = headPos.x
        var hy = headPos.y
        var hz = headPos.z

        var rw = headRot.real
        var rx = headRot.imag.x
        var ry = headRot.imag.y
        var rz = headRot.imag.z

        data.append(UnsafeBufferPointer(start: &magic, count: 1))
        data.append(UnsafeBufferPointer(start: &seq, count: 1))
        data.append(UnsafeBufferPointer(start: &ts, count: 1))
        data.append(UnsafeBufferPointer(start: &hx, count: 1))
        data.append(UnsafeBufferPointer(start: &hy, count: 1))
        data.append(UnsafeBufferPointer(start: &hz, count: 1))
        data.append(UnsafeBufferPointer(start: &rw, count: 1))
        data.append(UnsafeBufferPointer(start: &rx, count: 1))
        data.append(UnsafeBufferPointer(start: &ry, count: 1))
        data.append(UnsafeBufferPointer(start: &rz, count: 1))

        // 2. 左右の手データ (0: 左手, 1: 右手)
        appendHandData(hand: leftHand, defaultChirality: 0, to: &data)
        appendHandData(hand: rightHand, defaultChirality: 1, to: &data)

        // 3. 高速UDP送信
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("UDP Send Error: \(error)")
            }
        }))
    }

    private func appendHandData(hand: HandPacketData?, defaultChirality: UInt8, to data: inout Data) {
        var chirality = defaultChirality
        var isTracked: UInt8 = (hand?.isTracked == 1) ? 1 : 0
        var isPinching: UInt8 = hand?.isPinching ?? 0
        var pinchDist: Float = hand?.pinchDistance ?? 1.0

        var curls = hand?.curls ?? FingerCurls()
        var splays = hand?.splays ?? FingerSplays()

        data.append(UnsafeBufferPointer(start: &chirality, count: 1))
        data.append(UnsafeBufferPointer(start: &isTracked, count: 1))
        data.append(UnsafeBufferPointer(start: &isPinching, count: 1))
        data.append(UnsafeBufferPointer(start: &pinchDist, count: 1))
        data.append(UnsafeBufferPointer(start: &curls, count: 1))
        data.append(UnsafeBufferPointer(start: &splays, count: 1))

        var dummyBone = BoneTransform(
            position: Vector3f(x: 0, y: 0, z: 0),
            orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0)
        )

        if let hand = hand {
            withUnsafeBytes(of: hand.joints) { rawPtr in
                data.append(rawPtr.bindMemory(to: UInt8.self))
            }
        } else {
            for _ in 0..<21 {
                data.append(UnsafeBufferPointer(start: &dummyBone, count: 1))
            }
        }

        var controller = hand?.controller ?? ControllerInputData()
        data.append(UnsafeBufferPointer(start: &controller, count: 1))
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }
}

