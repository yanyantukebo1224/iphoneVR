import Foundation
import Network
import simd

class BinaryUDPStreamer {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.iphonevr.udp.streamer", qos: .userInteractive)
    private var sequenceNumber: UInt32 = 0

    func connect(targetIP: String, port: UInt16 = 9050) {
        let host = NWEndpoint.Host(targetIP)
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? 9050

        let connection = NWConnection(host: host, port: endpointPort, using: .udp)
        connection.start(queue: queue)
        self.connection = connection
        print("BinaryUDPStreamer: Connected to \(targetIP):\(port)")
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }

    func sendPacket(headPos: SIMD3<Float>, headRot: simd_quatf, leftHand: HandPacketData?, rightHand: HandPacketData?) {
        guard let connection = connection else { return }

        var data = Data()

        var magic: UInt32 = 0x52565049 // "IPVR"
        var seq = sequenceNumber
        sequenceNumber += 1
        var ts = Date().timeIntervalSince1970

        var hx = headPos.x
        var hy = headPos.y
        var hz = headPos.z

        var rw = headRot.real
        var rx = headRot.imag.x
        var ry = headRot.imag.y
        var rz = headRot.imag.z

        data.append(contentsOf: withUnsafeBytes(of: &magic) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &seq) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &ts) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &hx) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &hy) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &hz) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &rw) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &rx) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &ry) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &rz) { Data($0) })

        appendHandData(hand: leftHand, defaultChirality: 0, to: &data)
        appendHandData(hand: rightHand, defaultChirality: 1, to: &data)

        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("UDP Send Error: \(error)")
            }
        }))
    }

    private func appendHandData(hand: HandPacketData?, defaultChirality: UInt8, to data: inout Data) {
        if var h = hand {
            data.append(contentsOf: withUnsafeBytes(of: &h.chirality) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: &h.isTracked) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: &h.isPinching) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: &h.pinchDistance) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: &h.joints) { Data($0) })
        } else {
            var chirality = defaultChirality
            var isTracked: UInt8 = 0
            var isPinching: UInt8 = 0
            var pinchDist: Float = 1.0

            data.append(contentsOf: withUnsafeBytes(of: &chirality) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: &isTracked) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: &isPinching) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: &pinchDist) { Data($0) })

            var dummyBone = BoneTransform(
                position: Vector3f(x: 0, y: 0, z: 0),
                orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0)
            )

            for _ in 0..<21 {
                data.append(contentsOf: withUnsafeBytes(of: &dummyBone) { Data($0) })
            }
        }
    }
}
