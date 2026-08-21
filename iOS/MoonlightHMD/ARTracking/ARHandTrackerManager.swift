import Foundation
import ARKit
import Vision
import Combine
import UIKit

class ARHandTrackerManager: NSObject, ARSessionDelegate, ObservableObject {
    let session = ARSession()
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private let processingQueue = DispatchQueue(label: "com.iphonevr.vision.processing", qos: .userInteractive)

    @Published var headPosition: SIMD3<Float> = .zero
    @Published var headRotation: simd_quatf = simd_quatf(real: 1, imag: .zero)
    @Published var leftHandData: HandPacketData?
    @Published var rightHandData: HandPacketData?

    private var prevLeftPos: SIMD3<Float> = SIMD3<Float>(-0.18, -0.15, -0.45)
    private var prevRightPos: SIMD3<Float> = SIMD3<Float>(0.18, -0.15, -0.45)

    private var prevLeftRot: simd_quatf = simd_quatf(real: 1, imag: .zero)
    private var prevRightRot: simd_quatf = simd_quatf(real: 1, imag: .zero)

    private var prevLeftCurls = FingerCurls()
    private var prevRightCurls = FingerCurls()

    var onTrackingDataUpdated: ((SIMD3<Float>, simd_quatf, HandPacketData?, HandPacketData?) -> Void)?

    override init() {
        super.init()
        handPoseRequest.maximumHandCount = 2
        session.delegate = self
    }

    func startTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopTracking() {
        session.pause()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let rotation = simd_quaternion(transform)

        DispatchQueue.main.async {
            self.headPosition = position
            self.headRotation = rotation
        }

        let pixelBuffer = frame.capturedImage
        processingQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([self.handPoseRequest])
                self.processHandObservation(results: self.handPoseRequest.results)
            } catch {
                print("Vision Hand Error: \(error)")
            }
        }
    }

    private func processHandObservation(results: [VNHumanHandPoseObservation]?) {
        var newLeft: HandPacketData?
        var newRight: HandPacketData?

        if let observations = results, !observations.isEmpty {
            if observations.count >= 2 {
                let sortedObs = observations.sorted { obs1, obs2 in
                    let x1 = (try? obs1.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                    let x2 = (try? obs2.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                    return x1 < x2
                }
                newLeft = buildCleanHandData(from: sortedObs[0], chirality: 0)
                newRight = buildCleanHandData(from: sortedObs[1], chirality: 1)
            } else if let singleObs = observations.first {
                let wristX = (try? singleObs.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                let chiralityVal: UInt32 = (wristX >= 0.5) ? 1 : 0
                if chiralityVal == 1 {
                    newRight = buildCleanHandData(from: singleObs, chirality: 1)
                } else {
                    newLeft = buildCleanHandData(from: singleObs, chirality: 0)
                }
            }
        }

        let gcMgr = GameControllerManager.shared
        let leftInput = gcMgr.getInputData(for: 0)
        let rightInput = gcMgr.getInputData(for: 1)

        if leftInput.isConnected == 1 {
            if newLeft == nil { newLeft = createBaseHandData(chirality: 0) }
            newLeft?.controller = leftInput
        }
        if rightInput.isConnected == 1 {
            if newRight == nil { newRight = createBaseHandData(chirality: 1) }
            newRight?.controller = rightInput
        }

        DispatchQueue.main.async {
            self.leftHandData = newLeft
            self.rightHandData = newRight
        }

        onTrackingDataUpdated?(headPosition, headRotation, newLeft, newRight)
    }

    private func buildCleanHandData(from observation: VNHumanHandPoseObservation, chirality: UInt32) -> HandPacketData? {
        guard let points = try? observation.recognizedPoints(.all),
              let wrist = points[.wrist] else { return nil }

        let isLeft = (chirality == 0)

        // 1. ピンチ計算
        var isPinching: UInt32 = 0
        var pinchDist: Float = 1.0
        if let thumbTip = points[.thumbTip], let indexTip = points[.indexTip] {
            let dx = Float(thumbTip.location.x - indexTip.location.x)
            let dy = Float(thumbTip.location.y - indexTip.location.y)
            pinchDist = sqrt(dx * dx + dy * dy)
            isPinching = (pinchDist < 0.065) ? 1 : 0
        }

        // 2. 3D位置 (Position)
        let wx = Float(wrist.location.x)
        let wy = Float(wrist.location.y)

        var scale: Float = 0.15
        if let midMCP = points[.middleMCP] {
            scale = max(0.04, hypot(Float(midMCP.location.x) - wx, Float(midMCP.location.y) - wy))
        }
        let depth: Float = max(0.30, min(0.70, 0.070 / scale))

        let rawX: Float = (wx - 0.5) * depth * 1.2
        let rawY: Float = (0.5 - wy) * depth * 1.2
        let rawZ: Float = -depth

        let rawPos = SIMD3<Float>(rawX, rawY, rawZ)
        let prevP = isLeft ? prevLeftPos : prevRightPos
        let smoothPos = prevP * 0.5 + rawPos * 0.5
        if isLeft { prevLeftPos = smoothPos } else { prevRightPos = smoothPos }

        // 3. 手首のひねり (Wrist 3D Rotation / Orientation) の極めて滑らかな抽出
        var wristRot = simd_quatf(real: 1, imag: .zero)
        if let midMCP = points[.middleMCP], let indexMCP = points[.indexMCP], let pinkyMCP = points[.littleMCP] {
            let fwd = simd_normalize(SIMD3<Float>(Float(midMCP.location.x - wrist.location.x), Float(0.5 - midMCP.location.y) - Float(0.5 - wrist.location.y), -0.2))
            let right = simd_normalize(SIMD3<Float>(Float(pinkyMCP.location.x - indexMCP.location.x), Float(0.5 - pinkyMCP.location.y) - Float(0.5 - indexMCP.location.y), 0.0))
            let up = simd_cross(right, fwd)
            
            let rotMat = simd_float3x3(right, up, fwd)
            wristRot = simd_quaternion(rotMat)
            if wristRot.real.isNaN { wristRot = simd_quatf(real: 1, imag: .zero) }
        }

        let prevR = isLeft ? prevLeftRot : prevRightRot
        let smoothRot = simd_slerp(prevR, wristRot, 0.4)
        if isLeft { prevLeftRot = smoothRot } else { prevRightRot = smoothRot }

        // 4. 指の屈曲度 (Finger Curls)
        let calcCurl = { (mcpKey: VNHumanHandPoseObservation.JointName, tipKey: VNHumanHandPoseObservation.JointName) -> Float in
            guard let mcp = points[mcpKey], let tip = points[tipKey] else { return 0.0 }
            let dMCP = hypot(Float(mcp.location.x) - wx, Float(mcp.location.y) - wy)
            let dTip = hypot(Float(tip.location.x) - wx, Float(tip.location.y) - wy)
            let ratio = dTip / max(0.001, dMCP)
            let curl = (1.85 - ratio) / 1.0
            return max(0.0, min(1.0, curl))
        }

        var rawCurls = FingerCurls()
        rawCurls.thumb = calcCurl(.thumbMP, .thumbTip)
        rawCurls.index = calcCurl(.indexMCP, .indexTip)
        rawCurls.middle = calcCurl(.middleMCP, .middleTip)
        rawCurls.ring = calcCurl(.ringMCP, .ringTip)
        rawCurls.pinky = calcCurl(.littleMCP, .littleTip)

        let prevC = isLeft ? prevLeftCurls : prevRightCurls
        let smoothCurls = FingerCurls(
            thumb: prevC.thumb * 0.4 + rawCurls.thumb * 0.6,
            index: prevC.index * 0.4 + rawCurls.index * 0.6,
            middle: prevC.middle * 0.4 + rawCurls.middle * 0.6,
            ring: prevC.ring * 0.4 + rawCurls.ring * 0.6,
            pinky: prevC.pinky * 0.4 + rawCurls.pinky * 0.6
        )
        if isLeft { prevLeftCurls = smoothCurls } else { prevRightCurls = smoothCurls }

        // 手首骨構造に 3D 回転を反映
        let wristBone = BoneTransform(
            position: Vector3f(x: smoothPos.x, y: smoothPos.y, z: smoothPos.z),
            orientation: Quaternionf(w: smoothRot.real, x: smoothRot.imag.x, y: smoothRot.imag.y, z: smoothRot.imag.z)
        )
        let identityBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))

        let tupleJoints = (
            wristBone, identityBone, identityBone, identityBone, identityBone,
            identityBone, identityBone, identityBone, identityBone, identityBone,
            identityBone, identityBone, identityBone, identityBone, identityBone,
            identityBone, identityBone, identityBone, identityBone, identityBone, identityBone
        )

        return HandPacketData(
            chirality: chirality,
            isTracked: 1,
            isPinching: isPinching,
            pinchDistance: pinchDist,
            curls: smoothCurls,
            splays: FingerSplays(),
            joints: tupleJoints,
            controller: GameControllerManager.shared.getInputData(for: chirality)
        )
    }

    private func createBaseHandData(chirality: UInt32) -> HandPacketData {
        let isLeft = (chirality == 0)
        let defaultPos = Vector3f(x: isLeft ? -0.18 : 0.18, y: -0.15, z: -0.45)
        let wristBone = BoneTransform(position: defaultPos, orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let identityBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let tupleJoints = (
            wristBone, identityBone, identityBone, identityBone, identityBone,
            identityBone, identityBone, identityBone, identityBone, identityBone,
            identityBone, identityBone, identityBone, identityBone, identityBone,
            identityBone, identityBone, identityBone, identityBone, identityBone, identityBone
        )
        return HandPacketData(
            chirality: chirality,
            isTracked: 1,
            isPinching: 0,
            pinchDistance: 1.0,
            curls: FingerCurls(),
            splays: FingerSplays(),
            joints: tupleJoints,
            controller: GameControllerManager.shared.getInputData(for: chirality)
        )
    }
}
